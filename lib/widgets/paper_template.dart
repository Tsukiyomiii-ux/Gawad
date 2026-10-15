// TEMPLATE MATCH: compares the uploaded paper with the documents the app
// makes, by LAYOUT (where the tables, text blocks, ID boxes and lines are on
// the page). Works offline on every device (phone and computer).
//
// The app draws its own 4 documents for this barangay (same tanods, same
// names), and the upload is compared with each:
//   • Payroll is landscape with one big table, the Certification is a letter,
//     the ID sheet has card boxes… so each one has its own "shape".
//   • The upload must look most like the document it is uploaded as.
//
// Steps for a photo: find the white paper (ignores the table/desk around it),
// mark the ink on it, cut it into a 32 × 32 grid and compare the grids.
// Tested on scans and on tilted / shadowed photos: the right document scores
// about 0.7–1.0, a different document or a random letter scores below 0.45.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:printing/printing.dart';

import 'package:tanod_incentives/data/doc_kind.dart';
import 'package:tanod_incentives/data/store.dart';
import 'package:tanod_incentives/Templates/gawad_pdf.dart' show buildOfficialPdf;

/// Same layout as the app's document.
const kLayoutMatch = 0.55;

/// Below this the paper is refused (between the two: "please check" warning).
const kLayoutRefuse = 0.45;

class TemplateMatch {
  final Map<DocKind, double> scores; // how much the upload looks like each document (−1 … 1)
  final DocKind expected;
  final bool noPaper; // no sheet of paper found in the picture
  const TemplateMatch(this.scores, this.expected, {this.noPaper = false});

  double get score => scores[expected] ?? -1;

  /// Another document that fits clearly better, or null.
  DocKind? get looksLike {
    DocKind? best;
    for (final e in scores.entries) {
      if (e.key == expected) continue;
      if (best == null || e.value > scores[best]!) best = e.key;
    }
    if (best == null) return null;
    final s = scores[best]!;
    return s >= kLayoutMatch && s > score + .15 ? best : null;
  }

  bool get matches => looksLike == null && score >= kLayoutMatch;
  bool get refused => looksLike != null || score < kLayoutRefuse;

  String get percent => '${(math.max(0, score) * 100).round()}%';
}

typedef _Layout = (Float64List grid, double aspect);

// The app's documents, drawn once per tanod list (so it's fast the next time)
final Map<String, _Layout> _refCache = {};

String _refKey(BrgyRecord rec, DocKind k) => [
      k.name,
      rec.name,
      rec.captain,
      for (final t in rec.tanods) '${t.awardNumber}|${t.fullName}|${t.idFront != null}',
    ].join('~');

Future<_Layout?> _reference(BrgyRecord rec, DocKind k) async {
  final key = _refKey(rec, k);
  final hit = _refCache[key];
  if (hit != null) return hit;
  try {
    final pdf = await buildOfficialPdf(rec, k);
    Uint8List? png;
    await for (final p in Printing.raster(pdf, pages: const [0], dpi: 72)) {
      png = await p.toPng();
      break;
    }
    if (png == null) return null;
    final lay = await compute(_layoutOf, png);
    if (lay != null) {
      if (_refCache.length > 40) _refCache.clear();
      _refCache[key] = lay;
    }
    return lay;
  } catch (e) {
    debugPrint('Template match: could not draw the ${k.title}: $e');
    return null;
  }
}

/// Compares the first page of the upload with the app's 4 documents.
/// Returns null when it can't be done (no tanods yet, or the picture has no paper on it).
Future<TemplateMatch?> matchTemplate(Uint8List pagePicture, DocKind expected, BrgyRecord rec) async {
  if (rec.tanods.isEmpty) return null;
  final up = await compute(_layoutOf, pagePicture);
  if (up == null) return TemplateMatch({expected: -1}, expected, noPaper: true);

  final scores = <DocKind, double>{};
  for (final k in DocKind.values) {
    final ref = await _reference(rec, k);
    if (ref != null) scores[k] = _bestScore(up, ref);
  }
  if (!scores.containsKey(expected)) return null;
  debugPrint('Template match for ${expected.title}: '
      '${scores.entries.map((e) => '${e.key.name} ${e.value.toStringAsFixed(2)}').join(', ')}');
  return TemplateMatch(scores, expected);
}

/// Likeness of two layouts; the upload may be turned (photo taken sideways / upside down).
double _bestScore(_Layout up, _Layout ref) {
  var best = -9.0;
  var g = up.$1;
  var aspect = up.$2;
  for (var turn = 0; turn < 4; turn++) {
    final s = _dot(g, ref.$1) - .6 * (math.log(aspect / ref.$2)).abs();
    if (s > best) best = s;
    g = _turn(g);
    aspect = 1 / aspect;
  }
  return best;
}

double _dot(Float64List a, Float64List b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

const _g = 32; // grid size

/// The grid turned a quarter clockwise.
Float64List _turn(Float64List g) {
  final out = Float64List(_g * _g);
  for (var y = 0; y < _g; y++) {
    for (var x = 0; x < _g; x++) {
      out[x * _g + (_g - 1 - y)] = g[y * _g + x];
    }
  }
  return out;
}

// ============================== LAYOUT (runs in the background) ==============================

/// Ink layout of the paper in a picture: a 32 × 32 grid (zero mean, length 1)
/// and the paper's width / height. Null if no paper or no ink was found.
_Layout? _layoutOf(Uint8List bytes) {
  var im = img.decodeImage(bytes);
  if (im == null) return null;
  im = img.bakeOrientation(im);
  final longSide = math.max(im.width, im.height);
  if (longSide > 800) {
    im = im.width >= im.height ? img.copyResize(im, width: 800) : img.copyResize(im, height: 800);
  }
  final w = im.width, h = im.height, n = w * h;
  final a = Float64List(n);
  for (final p in im) {
    a[p.y * w + p.x] = p.luminance.toDouble();
  }

  // 1) Paper = brighter than the Otsu threshold
  final t = _otsu(a);
  final paper = Uint8List(n);
  for (var i = 0; i < n; i++) {
    if (a[i] > t) paper[i] = 1;
  }

  // 2) Close the gaps left by text, keep the biggest white area, fill its holes
  final k = math.max(5, (math.max(w, h) / 40).floor()) | 1;
  final paperSum = _integral(paper.map((v) => v.toDouble()).toList(), w, h);
  final closed = Uint8List(n);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (_boxMean(paperSum, w, h, x, y, k ~/ 2) > .5) closed[y * w + x] = 1;
    }
  }
  final big = _biggestArea(closed, w, h);
  if (big == null) return null;
  _fillHoles(big, w, h);

  // 3) Ink: clearly darker than the paper around it, away from the paper's edge
  final rad = math.max(3, (math.max(w, h) / 60).floor());
  final bigSum = _integral(big.map((v) => v.toDouble()).toList(), w, h);
  final lumOnPaper = _integral([for (var i = 0; i < n; i++) paper[i] == 1 ? a[i] : 0.0], w, h);
  final ink = Uint8List(n);
  var inkCount = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (big[i] == 0) continue;
      if (_boxMean(bigSum, w, h, x, y, rad) < .999) continue; // too close to the paper edge
      final den = _boxMean(paperSum, w, h, x, y, 2 * rad);
      if (den < .05) continue;
      final bg = _boxMean(lumOnPaper, w, h, x, y, 2 * rad) / den;
      if (a[i] < bg * .72) {
        ink[i] = 1;
        inkCount++;
      }
    }
  }
  if (inkCount < 50) return null;

  // 4) The paper's box (ignoring the outer 0.5 %)
  final rows = List<int>.filled(h, 0), cols = List<int>.filled(w, 0);
  var total = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (big[y * w + x] == 1) {
        rows[y]++;
        cols[x]++;
        total++;
      }
    }
  }
  final (y0, y1) = _trim(rows, total);
  final (x0, x1) = _trim(cols, total);
  final bw = x1 - x0 + 1, bh = y1 - y0 + 1;
  if (bw < 20 || bh < 20) return null;

  // 5) 32 × 32 grid of ink, smoothed, zero mean, length 1
  final grid = Float64List(_g * _g);
  for (var gy = 0; gy < _g; gy++) {
    final ya = y0 + gy * bh ~/ _g, yb = math.max(ya + 1, y0 + (gy + 1) * bh ~/ _g);
    for (var gx = 0; gx < _g; gx++) {
      final xa = x0 + gx * bw ~/ _g, xb = math.max(xa + 1, x0 + (gx + 1) * bw ~/ _g);
      var c = 0;
      for (var y = ya; y < yb; y++) {
        for (var x = xa; x < xb; x++) {
          c += ink[y * w + x];
        }
      }
      grid[gy * _g + gx] = c / ((yb - ya) * (xb - xa));
    }
  }
  final smooth = Float64List(_g * _g);
  for (var gy = 0; gy < _g; gy++) {
    for (var gx = 0; gx < _g; gx++) {
      var s = 0.0;
      var c = 0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final yy = gy + dy, xx = gx + dx;
          if (yy < 0 || xx < 0 || yy >= _g || xx >= _g) continue;
          s += grid[yy * _g + xx];
          c++;
        }
      }
      smooth[gy * _g + gx] = s / c;
    }
  }
  var mean = 0.0;
  for (final v in smooth) {
    mean += v;
  }
  mean /= smooth.length;
  var norm = 0.0;
  for (var i = 0; i < smooth.length; i++) {
    smooth[i] -= mean;
    norm += smooth[i] * smooth[i];
  }
  norm = math.sqrt(norm) + 1e-9;
  for (var i = 0; i < smooth.length; i++) {
    smooth[i] /= norm;
  }
  return (smooth, bw / bh);
}

double _otsu(Float64List a) {
  final hist = List<double>.filled(256, 0);
  for (final v in a) {
    hist[v.round().clamp(0, 255).toInt()]++;
  }
  final n = a.length.toDouble();
  var sumAll = 0.0;
  for (var i = 0; i < 256; i++) {
    sumAll += i * hist[i];
  }
  var wB = 0.0, sumB = 0.0, best = 0.0, t = 128.0;
  for (var i = 0; i < 256; i++) {
    wB += hist[i];
    if (wB == 0) continue;
    final wF = n - wB;
    if (wF == 0) break;
    sumB += i * hist[i];
    final mB = sumB / wB, mF = (sumAll - sumB) / wF;
    final v = wB * wF * (mB - mF) * (mB - mF);
    if (v > best) {
      best = v;
      t = i.toDouble();
    }
  }
  return t;
}

/// Summed-area table ((w+1) × (h+1)) for fast box averages.
Float64List _integral(List<double> v, int w, int h) {
  final s = Float64List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var row = 0.0;
    for (var x = 0; x < w; x++) {
      row += v[y * w + x];
      s[(y + 1) * (w + 1) + x + 1] = s[y * (w + 1) + x + 1] + row;
    }
  }
  return s;
}

/// Average inside the square of radius r around (x, y), clipped to the picture.
double _boxMean(Float64List s, int w, int h, int x, int y, int r) {
  final xa = math.max(0, x - r), ya = math.max(0, y - r);
  final xb = math.min(w, x + r + 1), yb = math.min(h, y + r + 1);
  final sum = s[yb * (w + 1) + xb] - s[ya * (w + 1) + xb] - s[yb * (w + 1) + xa] + s[ya * (w + 1) + xa];
  return sum / ((xb - xa) * (yb - ya));
}

/// The biggest connected white area (as a 0/1 mask), or null if there is none.
Uint8List? _biggestArea(Uint8List m, int w, int h) {
  final label = Int32List(w * h);
  var next = 0, bestLabel = 0, bestSize = 0;
  final stack = <int>[];
  for (var start = 0; start < w * h; start++) {
    if (m[start] == 0 || label[start] != 0) continue;
    next++;
    var size = 0;
    stack.add(start);
    label[start] = next;
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      size++;
      final x = i % w, y = i ~/ w;
      void visit(int j) {
        if (m[j] == 1 && label[j] == 0) {
          label[j] = next;
          stack.add(j);
        }
      }

      if (x > 0) visit(i - 1);
      if (x < w - 1) visit(i + 1);
      if (y > 0) visit(i - w);
      if (y < h - 1) visit(i + w);
    }
    if (size > bestSize) {
      bestSize = size;
      bestLabel = next;
    }
  }
  if (bestSize < w * h * .05) return null; // no real paper in the picture
  final out = Uint8List(w * h);
  for (var i = 0; i < w * h; i++) {
    if (label[i] == bestLabel) out[i] = 1;
  }
  return out;
}

/// Fills the holes inside the paper (dark areas not connected to the picture's border).
void _fillHoles(Uint8List m, int w, int h) {
  final outside = Uint8List(w * h);
  final stack = <int>[];
  void seed(int i) {
    if (m[i] == 0 && outside[i] == 0) {
      outside[i] = 1;
      stack.add(i);
    }
  }

  for (var x = 0; x < w; x++) {
    seed(x);
    seed((h - 1) * w + x);
  }
  for (var y = 0; y < h; y++) {
    seed(y * w);
    seed(y * w + w - 1);
  }
  while (stack.isNotEmpty) {
    final i = stack.removeLast();
    final x = i % w, y = i ~/ w;
    if (x > 0) seed(i - 1);
    if (x < w - 1) seed(i + 1);
    if (y > 0) seed(i - w);
    if (y < h - 1) seed(i + w);
  }
  for (var i = 0; i < w * h; i++) {
    if (outside[i] == 0) m[i] = 1;
  }
}

/// First and last index after dropping 0.5 % of the total on each side.
(int, int) _trim(List<int> counts, int total) {
  final cut = total * .005;
  var acc = 0.0;
  var lo = 0;
  for (var i = 0; i < counts.length; i++) {
    acc += counts[i];
    if (acc > cut) {
      lo = i;
      break;
    }
  }
  acc = 0;
  var hi = counts.length - 1;
  for (var i = counts.length - 1; i >= 0; i--) {
    acc += counts[i];
    if (acc > cut) {
      hi = i;
      break;
    }
  }
  return (lo, math.max(lo, hi));
}