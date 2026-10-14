import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

// These are top-level functions so they can run with `compute()` in a
// background isolate and the UI doesn't freeze while images are processed.

/// A point in the photo, normalized to 0-1000 (same scale Gemini uses).
typedef NormPoint = (double x, double y);

// Output size of the flattened card: ID-1 ratio (85.6 x 54 mm) at ~300 dpi,
// so it prints sharp at real size.
const int _cardOutWidth = 1012;
const int _cardOutHeight = 638;

/// Applies the camera's rotation metadata so every step (Gemini, cropping,
/// the PDF) works on the same upright image.
Uint8List normalizePhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  return Uint8List.fromList(img.encodeJpg(img.bakeOrientation(decoded), quality: 92));
}

/// Cuts the card out of the photo and straightens it, like a flatbed scan.
///
/// [corners] are the card's 4 corners from Gemini, in the card's own reading
/// order: top-left, top-right, bottom-right, bottom-left (0-1000 scale).
/// Because the order follows the card, the result is upright even if the
/// photo was taken sideways or upside down. Keeps full color.
///
/// Falls back to a plain rectangular crop, or the full photo, if the corners
/// are missing or don't form a sensible shape (e.g. offline).
Uint8List flattenCard((Uint8List, List<NormPoint>?) args) {
  final (bytes, corners) = args;
  if (corners == null || corners.length != 4) return bytes;

  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final w = decoded.width, h = decoded.height;

  // 0-1000 -> pixel positions
  final pts = [for (final (x, y) in corners) (x / 1000 * w, y / 1000 * h)];

  if (!_isValidQuad(pts, w, h)) return _cropToBounds(decoded, pts) ?? bytes;

  // Map every pixel of the flat output card back to where it is in the photo
  const double right = _cardOutWidth - 1.0, bottom = _cardOutHeight - 1.0;
  final outCorners = <NormPoint>[
    (0.0, 0.0),
    (right, 0.0),
    (right, bottom),
    (0.0, bottom),
  ];
  final hm = _homography(outCorners, pts);
  if (hm == null) return _cropToBounds(decoded, pts) ?? bytes;

  final src = decoded.numChannels == 3 ? decoded : decoded.convert(numChannels: 3);
  final sb = src.toUint8List();
  final out = Uint8List(_cardOutWidth * _cardOutHeight * 3);

  final maxX = w - 1.001, maxY = h - 1.001;
  int o = 0;
  for (int v = 0; v < _cardOutHeight; v++) {
    for (int u = 0; u < _cardOutWidth; u++) {
      final d = hm[6] * u + hm[7] * v + 1;
      final x = math.min(math.max((hm[0] * u + hm[1] * v + hm[2]) / d, 0.0), maxX);
      final y = math.min(math.max((hm[3] * u + hm[4] * v + hm[5]) / d, 0.0), maxY);

      // Bilinear sampling keeps edges and text smooth
      final x0 = x.floor(), y0 = y.floor();
      final fx = x - x0, fy = y - y0;
      final i00 = (y0 * w + x0) * 3;
      final i10 = i00 + 3;
      final i01 = i00 + w * 3;
      final i11 = i01 + 3;

      for (int c = 0; c < 3; c++) {
        final top = sb[i00 + c] * (1 - fx) + sb[i10 + c] * fx;
        final bottom = sb[i01 + c] * (1 - fx) + sb[i11 + c] * fx;
        out[o++] = (top * (1 - fy) + bottom * fy).round();
      }
    }
  }

  final flat = img.Image.fromBytes(
    width: _cardOutWidth,
    height: _cardOutHeight,
    bytes: out.buffer,
    numChannels: 3,
  );
  return Uint8List.fromList(img.encodeJpg(flat, quality: 95));
}

/// Sharpness score (variance of the Laplacian). Higher = sharper.
/// Blurry photos have soft edges, so this number drops a lot.
double sharpnessScore(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return 0;

  // Fixed width so scores are comparable between photos
  final small = img.grayscale(img.copyResize(decoded, width: 640));
  final w = small.width, h = small.height;

  final lum = Float64List(w * h);
  for (final p in small) {
    lum[p.y * w + p.x] = p.r.toDouble();
  }

  double sum = 0, sumSq = 0;
  int n = 0;
  for (int y = 1; y < h - 1; y++) {
    for (int x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final lap = lum[i - w] + lum[i + w] + lum[i - 1] + lum[i + 1] - 4 * lum[i];
      sum += lap;
      sumSq += lap * lap;
      n++;
    }
  }
  if (n == 0) return 0;
  final mean = sum / n;
  return sumSq / n - mean * mean;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// The 4 points must form a convex shape that covers a reasonable part of the
/// photo, otherwise Gemini's corners are probably wrong.
bool _isValidQuad(List<NormPoint> p, int w, int h) {
  for (final (x, y) in p) {
    if (x < -w * 0.02 || y < -h * 0.02 || x > w * 1.02 || y > h * 1.02) return false;
  }

  // Convex: every turn goes the same direction
  int sign = 0;
  for (int i = 0; i < 4; i++) {
    final (ax, ay) = p[i];
    final (bx, by) = p[(i + 1) % 4];
    final (cx, cy) = p[(i + 2) % 4];
    final cross = (bx - ax) * (cy - by) - (by - ay) * (cx - bx);
    final s = cross > 0 ? 1 : (cross < 0 ? -1 : 0);
    if (s == 0) return false;
    if (sign == 0) sign = s;
    if (s != sign) return false;
  }

  // Area (shoelace) must be at least 5% of the photo
  double area = 0;
  for (int i = 0; i < 4; i++) {
    final (x1, y1) = p[i];
    final (x2, y2) = p[(i + 1) % 4];
    area += x1 * y2 - x2 * y1;
  }
  return area.abs() / 2 > w * h * 0.05;
}

/// Solves the perspective transform that maps [from] points onto [to] points.
/// Returns the 8 coefficients (the 9th is fixed at 1), or null if unsolvable.
List<double>? _homography(List<NormPoint> from, List<NormPoint> to) {
  final a = List.generate(8, (_) => List<double>.filled(9, 0));
  for (int i = 0; i < 4; i++) {
    final (u, v) = from[i];
    final (x, y) = to[i];
    a[2 * i] = [u, v, 1, 0, 0, 0, -u * x, -v * x, x];
    a[2 * i + 1] = [0, 0, 0, u, v, 1, -u * y, -v * y, y];
  }

  // Gaussian elimination with partial pivoting
  for (int col = 0; col < 8; col++) {
    int pivot = col;
    for (int r = col + 1; r < 8; r++) {
      if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
    }
    if (a[pivot][col].abs() < 1e-12) return null;
    final tmp = a[col];
    a[col] = a[pivot];
    a[pivot] = tmp;

    for (int r = 0; r < 8; r++) {
      if (r == col) continue;
      final f = a[r][col] / a[col][col];
      if (f == 0) continue;
      for (int c = col; c < 9; c++) {
        a[r][c] -= f * a[col][c];
      }
    }
  }
  return [for (int i = 0; i < 8; i++) a[i][8] / a[i][i]];
}

/// Plain rectangular crop around the points (no straightening).
Uint8List? _cropToBounds(img.Image image, List<NormPoint> pts) {
  final w = image.width, h = image.height;
  final xs = pts.map((p) => p.$1), ys = pts.map((p) => p.$2);
  final x1 = xs.reduce(math.min).round().clamp(0, w - 1);
  final y1 = ys.reduce(math.min).round().clamp(0, h - 1);
  final x2 = xs.reduce(math.max).round().clamp(x1 + 1, w);
  final y2 = ys.reduce(math.max).round().clamp(y1 + 1, h);
  if ((x2 - x1) < w * 0.15 || (y2 - y1) < h * 0.15) return null;

  final cropped = img.copyCrop(image, x: x1, y: y1, width: x2 - x1, height: y2 - y1);
  return Uint8List.fromList(img.encodeJpg(cropped, quality: 95));
}