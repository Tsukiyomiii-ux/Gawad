// PAPER CHECK: before a signed copy is uploaded, make sure it is
//   1. the right document (no Masterlist in the Payroll slot),
//   2. really signed by hand (not the blank file the app made),
//   3. about this barangay's tanods.
//
// How it checks:
//   • Every device, offline: a PDF made by the app itself is the UNSIGNED file → refused.
//   • Every device, offline: SAME TEMPLATE? The page layout is compared with the
//     4 documents the app makes for this barangay (paper_template.dart). A different
//     document or a paper that isn't the app's template → refused.
//   Then, for the signatures (best one available is used):
//   • With internet + GEMINI_API_KEY (same key the ID scanner uses): Gemini reads the
//     page(s) and answers what the document is and how many places are signed.
//   • Phones, offline: on-device text reading (ML Kit) finds the document type from its
//     printed words, then looks for handwriting ink where the signatures go.
//   • Otherwise (computer, no internet): not checked; the upload is marked
//     "not auto-checked" so the municipality knows to look closely.
//
// The result is saved with the upload (autoCheck / autoCheckOk) and shown to the
// municipality and OPPDC in the soft copy viewer.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:printing/printing.dart';

import 'package:tanod_incentives/theme.dart';
import 'package:tanod_incentives/data/doc_kind.dart';
import 'package:tanod_incentives/data/store.dart';
import 'package:tanod_incentives/widgets/upload_sheet.dart' show UploadedFile;
import 'package:tanod_incentives/widgets/paper_template.dart'; // same layout as the app's document?

/// Words printed on each document (letters only, no spaces). Add more here if a
/// template's wording changes. The Masterlist template is yours, so check that
/// its title words are listed.
const Map<DocKind, List<String>> kPaperWords = {
  DocKind.payroll: [
    'PAYROLL', 'ACKNOWLEDGETOHAVERECEIVED', 'PROVINCIALTREASURER', 'AMOUNTDUE', 'ACCOUNTINGENTRIES',
    'DISBURSINGOFFICER', 'APPROVEDFORPAYMENT', 'CAFOA', 'CLAIMANT', 'FINANCIALASSISTANCE',
  ],
  DocKind.masterlist: ['MASTERLIST', 'MASTERSLIST', 'LISTOFBARANGAYTANOD', 'LISTOFTANOD'],
  DocKind.certification: [
    'CERTIFICATION', 'TOWHOMITMAYCONCERN', 'THISISTOCERTIFY', 'OFFICEOFTHEPUNONGBARANGAY', 'RENDEREDATLEAST',
    'PLANTEDANDGROWN', 'WHATEVERLEGALPURPOSE', 'MONTHSOFSERVICE',
  ],
  DocKind.idSheet: [
    'SIGNATUREOFTANOD', 'TANODINCENTIVERECORDS', 'NOIDPHOTOONFILE', 'PAMBANSANGPAGKAKAKILANLAN',
    'PHILIPPINEIDENTIFICATION', 'REPUBLIKANGPILIPINAS', 'PHILID',
  ],
};

enum PaperVerdict {
  ok, // right document, signed
  wrongDocument, // a different document (refused)
  appFile, // the unsigned PDF the app made (refused)
  noSignature, // right document but no handwriting found
  notOurTanods, // none of this barangay's tanods are on it
  unsure, // couldn't read it well
  notChecked, // no checker on this device right now
}

class PaperCheck {
  final PaperVerdict verdict;
  final String message; // shown to the barangay
  final String note; // saved with the upload, shown to reviewers
  const PaperCheck(this.verdict, this.message, this.note);

  bool get ok => verdict == PaperVerdict.ok;
  bool get refused => verdict == PaperVerdict.wrongDocument || verdict == PaperVerdict.appFile;
}

// ============================== CHECKING ==============================

/// What a checker found on the paper.
class _Facts {
  final DocKind? found; // null = not one of the four
  final bool readable;
  final int spaces; // places where a signature belongs (0 = couldn't find them)
  final int signed; // of those, how many have handwriting
  final int namesFound; // this barangay's tanod names seen on the paper (-1 = not checked)
  final String how; // 'AI' or 'phone'
  final String issue;
  const _Facts({
    required this.found,
    required this.readable,
    required this.spaces,
    required this.signed,
    required this.namesFound,
    required this.how,
    this.issue = '',
  });

  _Facts withFound(DocKind k) =>
      _Facts(found: k, readable: readable, spaces: spaces, signed: signed, namesFound: namesFound, how: how, issue: issue);
}

/// PITCH MODE: only check that the upload is the same document/template.
/// Signatures are NOT required and the app's own PDF is accepted.
/// Set to true to bring back the signature checks.
const kRequireSignature = false;

/// PITCH: turn the whole paper check off (no template / signature checks,
/// no "Checking…" window). Set to true to turn it back on.
const kPaperCheckOn = false;

const _kAppPdfMark = 'DavBfr/dart_pdf'; // written at the top of every PDF the app makes
const kSignedCopyMark = 'Gawad signed copy'; // set on PDFs that wrap an uploaded photo

bool _contains(Uint8List bytes, String text, {int? limit}) {
  final hay = latin1.decode(limit == null || bytes.length <= limit ? bytes : bytes.sublist(0, limit), allowInvalid: true);
  return hay.contains(text);
}

bool get _phone => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// Checks one upload against the document it is meant to be.
Future<PaperCheck> checkPaper(UploadedFile up, DocKind expected, BrgyRecord rec) async {
  final title = expected.title;

  // 1) The app's own (unsigned) PDF uploaded back
  if (kRequireSignature && up.isPdf && _contains(up.bytes, _kAppPdfMark, limit: 400) && !_contains(up.bytes, kSignedCopyMark)) {
    return PaperCheck(
      PaperVerdict.appFile,
      'This is the blank $title file made by the app, without signatures. Print it, have it signed by hand, '
          'then take a photo or scan of the signed paper and upload that.',
      'Refused: unsigned file from the app',
    );
  }

  // 2) Page pictures (a PDF is turned into pictures, first 3 pages)
  final pages = <Uint8List>[];
  try {
    if (up.isPdf) {
      var i = 0;
      await for (final p in Printing.raster(up.bytes, dpi: 140)) {
        pages.add(await compute(_preparePage, await p.toPng()));
        if (++i >= 3) break;
      }
    } else {
      pages.add(await compute(_preparePage, up.bytes));
    }
  } catch (e) {
    debugPrint('Paper check: could not open the file: $e');
  }
  if (pages.isEmpty) {
    return const PaperCheck(PaperVerdict.unsure, 'We couldn’t open this file to check it.', 'Not auto-checked: file could not be opened');
  }

  // 3) SAME TEMPLATE? Compare the layout with the documents the app makes (offline, every device)
  TemplateMatch? layout;
  try {
    layout = await matchTemplate(pages.first, expected, rec);
  } catch (e) {
    debugPrint('Template match failed: $e');
  }
  if (layout != null) {
    if (layout.noPaper) {
      return PaperCheck(PaperVerdict.wrongDocument,
          'We couldn’t find a sheet of paper in this picture. Put the signed $title on a table and take the photo from above, showing the whole page.',
          'Refused: no paper found in the picture');
    }
    final other = layout.looksLike;
    if (other != null) {
      return PaperCheck(PaperVerdict.wrongDocument,
          'This looks like the ${other.title}, not the $title. Upload the ${other.title} in its own slot, and the signed $title here.',
          'Refused: layout matches the ${other.title}');
    }
    if (layout.refused) {
      return PaperCheck(PaperVerdict.wrongDocument,
          'This paper doesn’t match the $title made by this app (layout match ${layout.percent}). '
              'Print the $title from the Documents tab, have it signed, and upload a photo or scan of that paper.',
          'Refused: not the app’s $title (layout ${layout.percent})');
    }
  }
  final layoutNote = layout == null ? '' : ' · layout ${layout.matches ? '✓' : '?'} ${layout.percent}';

  // PITCH MODE: the template check above is the only check
  if (!kRequireSignature) {
    if (layout == null) {
      return const PaperCheck(PaperVerdict.notChecked, 'The paper could not be compared with the template.',
          'Not auto-checked (template not available)');
    }
    if (layout.matches) {
      return PaperCheck(PaperVerdict.ok, 'Checked: this matches the $title template (${layout.percent}).',
          'Template ✓ matches the $title (${layout.percent})');
    }
    return PaperCheck(
      PaperVerdict.unsure,
      'This only partly matches the $title made by this app (${layout.percent}). Take a straight photo of the whole page, or upload a scan.',
      'Template only partly matches the $title (${layout.percent})',
    );
  }

  // 4) Signed? Gemini (internet), then the phone's own text reader (offline)
  _Facts? facts = await _askGemini(pages, expected, rec);
  if (facts == null && _phone) {
    try {
      facts = await _readOnPhone(pages, expected, rec);
    } catch (e) {
      debugPrint('Paper check (phone) failed: $e');
    }
  }
  if (facts == null) {
    if (layout != null && layout.matches) {
      return PaperCheck(
        PaperVerdict.notChecked,
        'The layout matches the $title (${layout.percent}). Signatures can’t be checked on this device right now.',
        'Layout ✓ matches the $title (${layout.percent}) · signatures not auto-checked',
      );
    }
    if (layout != null) {
      return PaperCheck(
        PaperVerdict.unsure,
        'This only partly matches the $title made by this app (${layout.percent}). Take a straight photo of the whole page, or upload a scan.',
        'Layout only partly matches the $title (${layout.percent})',
      );
    }
    return const PaperCheck(
      PaperVerdict.notChecked,
      'This device can’t check the paper right now (no internet). It will be uploaded, and the municipality will check it.',
      'Not auto-checked (no internet on this device)',
    );
  }
  // A clear layout match decides the document type (the readers can misread a word)
  if (layout != null && layout.score >= .65 && facts.found != expected) {
    facts = facts.withFound(expected);
  }
  final r = _decide(expected, facts, rec);
  if (layout != null && !layout.matches && r.ok) {
    return PaperCheck(PaperVerdict.unsure,
        'This only partly matches the $title made by this app (${layout.percent}). Take a straight photo of the whole page, or upload a scan.',
        '${r.note}$layoutNote');
  }
  return PaperCheck(r.verdict, r.message, '${r.note}$layoutNote');
}

PaperCheck _decide(DocKind expected, _Facts f, BrgyRecord rec) {
  final title = expected.title;
  final by = f.how == 'AI' ? 'AI check' : 'Phone check';
  if (!f.readable) {
    return PaperCheck(PaperVerdict.unsure,
        'We couldn’t read this paper clearly. Take a straight, well-lit photo of the whole page.', '$by: paper hard to read');
  }
  if (f.found == null) {
    return PaperCheck(PaperVerdict.wrongDocument,
        'This doesn’t look like the $title.${f.issue.isEmpty ? '' : ' ${f.issue}'} Please upload the signed $title.',
        'Refused: not the $title');
  }
  if (f.found != expected) {
    return PaperCheck(PaperVerdict.wrongDocument,
        'This looks like the ${f.found!.title}, not the $title. Upload the ${f.found!.title} in its own slot, and the signed $title here.',
        'Refused: it was the ${f.found!.title}');
  }
  if (f.namesFound == 0 && rec.tanods.isNotEmpty) {
    return PaperCheck(PaperVerdict.notOurTanods,
        'None of your tanods’ names were found on this $title. Is it from another barangay, or an old list?',
        '$by: tanod names not found on the paper');
  }
  if (f.spaces > 0 && f.signed == 0) {
    return PaperCheck(PaperVerdict.noSignature,
        'We couldn’t find any handwritten signature on this $title. Have it signed first, then take the photo again.',
        '$by: no signature found');
  }
  if (f.spaces == 0) {
    return PaperCheck(PaperVerdict.unsure,
        'This is the $title, but we couldn’t find where the signatures are. Make sure the whole page is in the photo.',
        '$by: right document, signatures not found');
  }
  final part = f.signed < f.spaces ? ' (${f.signed} of ${f.spaces} signed)' : '';
  return PaperCheck(PaperVerdict.ok, 'Checked: this is the signed $title$part.', '$by: signed $title ✓$part');
}

/// Upright JPEG, at most 1800 px long, no rotation tag (so text positions match pixels).
Uint8List _preparePage(Uint8List bytes) {
  var im = img.decodeImage(bytes);
  if (im == null) throw StateError('not a picture');
  im = img.bakeOrientation(im);
  final longSide = math.max(im.width, im.height);
  if (longSide > 1800) {
    im = im.width >= im.height ? img.copyResize(im, width: 1800) : img.copyResize(im, height: 1800);
  }
  im.exif = img.ExifData();
  return img.encodeJpg(im, quality: 88);
}

String _letters(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');

// ------------------------------ Gemini ------------------------------

const _geminiKey = String.fromEnvironment('GEMINI_API_KEY');

const _typeNames = {
  'payroll': DocKind.payroll,
  'masterlist': DocKind.masterlist,
  'certification': DocKind.certification,
  'id_photocopy_sheet': DocKind.idSheet,
};

Future<_Facts?> _askGemini(List<Uint8List> pages, DocKind expected, BrgyRecord rec) async {
  if (_geminiKey.isEmpty) return null;
  final names = rec.tanods.take(40).map((t) => t.fullName).join('; ');
  final prompt = '''
You check a photo or scan of a paper uploaded to a barangay tanod incentive system (Iloilo, Philippines).
The barangay says this is the "${expected.title}". Decide what the paper really is:
- payroll: "PROVINCIAL PAYROLL", "We hereby acknowledge to have received ... Provincial Treasurer", a table with award number, name, address, amount due, and a SIGNATURE column with one row per tanod.
- masterlist: a MASTERLIST (list) of barangay tanods with their details. It is not a payroll (no amount due / acknowledgement).
- certification: "CERTIFICATION", "TO WHOM IT MAY CONCERN", certifies the tanods rendered service, signed by the Punong Barangay.
- id_photocopy_sheet: photocopies of ID cards; each ID has 3 numbered lines labelled "Signature of tanod".
- other: anything else (blank page, a random photo, a different form).
Signatures: count only HANDWRITTEN ink signatures. Printed or typed names and empty lines are NOT signatures.
- payroll: signatureSpaces = tanod rows; signedSpaces = rows with a handwritten signature in the SIGNATURE column.
- certification: the Punong Barangay signature above the printed name (spaces = 1 per certificate).
- id_photocopy_sheet: one space per ID box; signed if at least one of its 3 lines has a handwritten signature.
- masterlist: the signature lines of the signatories (prepared by / certified by / Punong Barangay).
This account is Barangay ${rec.name}. Tanods on its list: $names.
tanodNamesFound = how many of those tanod names you can read on the paper.
readable = false only if the paper is too blurry, dark, or cut off to judge.
issue = one short sentence if something is wrong (empty if fine).''';

  final schema = Schema.object(properties: {
    'documentType': Schema.enumString(enumValues: [..._typeNames.keys, 'other']),
    'readable': Schema.boolean(),
    'signatureSpaces': Schema.integer(),
    'signedSpaces': Schema.integer(),
    'tanodNamesFound': Schema.integer(),
    'issue': Schema.string(),
  }, requiredProperties: [
    'documentType',
    'readable',
    'signatureSpaces',
    'signedSpaces',
    'tanodNamesFound',
    'issue',
  ]);

  try {
    final model = GenerativeModel(
      model: 'gemini-flash-latest',
      apiKey: _geminiKey,
      generationConfig: GenerationConfig(temperature: 0, responseMimeType: 'application/json', responseSchema: schema),
    );
    final res = await model.generateContent([
      Content.multi([TextPart(prompt), for (final p in pages) DataPart('image/jpeg', p)]),
    ]).timeout(const Duration(seconds: 30));
    final text = res.text;
    if (text == null || text.trim().isEmpty) return null;
    debugPrint('--- PAPER CHECK (Gemini) ---\n$text');
    final j = jsonDecode(text) as Map<String, dynamic>;
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return _Facts(
      found: _typeNames[j['documentType']],
      readable: j['readable'] != false,
      spaces: n('signatureSpaces'),
      signed: n('signedSpaces'),
      namesFound: rec.tanods.isEmpty ? -1 : n('tanodNamesFound'),
      how: 'AI',
      issue: '${j['issue'] ?? ''}'.trim(),
    );
  } catch (e) {
    debugPrint('Paper check: Gemini not used ($e)');
    return null;
  }
}

// ------------------------------ Phone (offline) ------------------------------

class _Line {
  final String text; // letters only, upper case
  final Rect box;
  _Line(this.text, this.box);
}

Future<_Facts> _readOnPhone(List<Uint8List> pages, DocKind expected, BrgyRecord rec) async {
  final reader = TextRecognizer(script: TextRecognitionScript.latin);
  final pageLines = <List<_Line>>[];
  try {
    for (var i = 0; i < pages.length; i++) {
      final file = File('${Directory.systemTemp.path}/gawad_paper_check_$i.jpg');
      await file.writeAsBytes(pages[i], flush: true);
      final r = await reader.processImage(InputImage.fromFilePath(file.path));
      pageLines.add([
        for (final b in r.blocks)
          for (final l in b.lines) _Line(_letters(l.text), l.boundingBox),
      ]);
      file.delete().ignore();
    }
  } finally {
    reader.close();
  }

  final all = pageLines.expand((l) => l).map((l) => l.text).join();
  if (all.length < 40) {
    return const _Facts(found: null, readable: false, spaces: 0, signed: 0, namesFound: -1, how: 'phone');
  }

  // Which document? (count its printed words)
  final score = {for (final k in DocKind.values) k: kPaperWords[k]!.where(all.contains).length};
  final best = DocKind.values.reduce((a, b) => score[b]! > score[a]! ? b : a);
  DocKind? found;
  if (score[expected]! > 0 && score[expected]! >= score[best]!) {
    found = expected;
  } else if (score[best]! >= 2 || (score[best]! >= 1 && score[expected] == 0)) {
    found = best;
  } else if (score[expected]! > 0) {
    found = expected;
  } else {
    // Nothing matched. A well-read page with none of the words is not this document;
    // a short or messy read is just "unsure" (the Masterlist words may differ).
    if (all.length < 300 || expected == DocKind.masterlist) {
      return const _Facts(found: null, readable: false, spaces: 0, signed: 0, namesFound: -1, how: 'phone');
    }
  }

  // This barangay's tanods on the paper (by last name)
  final lastNames = {for (final t in rec.tanods) _letters(t.last)}..removeWhere((s) => s.length < 3);
  final namesFound = lastNames.isEmpty ? -1 : lastNames.where(all.contains).length;

  if (found != expected) {
    return _Facts(found: found, readable: true, spaces: 0, signed: 0, namesFound: namesFound, how: 'phone');
  }

  // Signatures: look for handwriting ink where each signature goes
  var spaces = 0, signed = 0;
  for (var i = 0; i < pages.length; i++) {
    final areas = _signatureAreas(pageLines[i], expected, rec);
    if (areas.regions.isEmpty) continue;
    final ink = await compute(_inkIn, (pages[i], areas.regions, areas.masks));
    for (final group in areas.groups) {
      spaces++;
      if (group.any((r) => _isSigned(ink[r]))) signed++;
    }
  }
  return _Facts(found: found, readable: true, spaces: spaces, signed: signed, namesFound: namesFound, how: 'phone');
}

bool _isSigned((double, double) v) => v.$1 >= 0.004 && v.$2 >= 0.10;

/// Where to look for signatures on one page.
///   regions: rectangles [l, t, r, b] to measure
///   groups:  one entry per signature place (indexes into regions)
///   masks:   printed text to ignore
({List<List<double>> regions, List<List<int>> groups, List<List<double>> masks}) _signatureAreas(
    List<_Line> lines, DocKind kind, BrgyRecord rec) {
  final regions = <List<double>>[];
  final groups = <List<int>>[];
  final masks = <List<double>>[];
  if (lines.isEmpty) return (regions: regions, groups: groups, masks: masks);

  final heights = lines.map((l) => l.box.height).toList()..sort();
  final lh = math.max(heights[heights.length ~/ 2], 8.0); // usual line height

  List<double> rect(double l, double t, double r, double b) => [l, t, r, b];
  List<double> boxOf(_Line l) => rect(l.box.left, l.box.top, l.box.right, l.box.bottom);
  int add(List<double> r) {
    regions.add(r);
    return regions.length - 1;
  }

  // Printed text that may sit inside a signature area
  final captain = _letters(rec.captain);
  for (final l in lines) {
    final t = l.text;
    final printed = t.contains('SIGNATURE') ||
        t.contains('PRINTED') ||
        t.contains('PUNONGBARANGAY') ||
        t.contains('TANODINCENTIVE') ||
        t.length <= 2 || // "1." "2." "3."
        (captain.length >= 4 && _similar(t, captain) >= .6) ||
        rec.tanods.any((x) => t.length >= 6 && _similar(t, _letters(x.fullName)) >= .7);
    if (printed) masks.add(boxOf(l));
  }

  // Area ABOVE a label (signature over the printed name)
  void above(_Line a, {double up = 5.5, double widen = 1.5}) {
    final cx = a.box.center.dx;
    final hw = math.max(a.box.width * widen, lh * 6);
    groups.add([add(rect(cx - hw, a.box.top - lh * up, cx + hw, a.box.top - lh * .35))]);
  }

  // A SIGNATURE column: one area per tanod row (or the whole column)
  void column(_Line header) {
    final cx = header.box.center.dx;
    final hw = header.box.width * 1.25;
    final rows = lines.where((l) =>
        l.box.top > header.box.bottom &&
        l.text.length >= 6 &&
        rec.tanods.any((x) => _similar(l.text, _letters(x.fullName)) >= .7));
    if (rows.isNotEmpty) {
      for (final r in rows) {
        final pad = r.box.height * .25;
        groups.add([add(rect(cx - hw, r.box.top - pad, cx + hw, r.box.bottom + pad))]);
      }
    } else {
      final n = math.max(rec.tanods.length, 1);
      groups.add([add(rect(cx - hw, header.box.bottom + lh * 2.5, cx + hw, header.box.bottom + lh * (2.5 + 1.8 * n)))]);
    }
  }

  switch (kind) {
    case DocKind.payroll:
      for (final h in lines.where((l) => l.text == 'SIGNATURE')) {
        column(h);
      }
    case DocKind.certification:
      for (final a in lines.where((l) => l.text == 'PUNONGBARANGAY')) {
        above(a);
      }
    case DocKind.idSheet:
      for (final a in lines.where((l) => l.text.contains('SIGNATUREOFTANOD'))) {
        above(a, up: 10.5, widen: 1.6);
      }
    case DocKind.masterlist:
      break;
  }

  // Any document (and the Masterlist): the usual signature labels
  if (groups.isEmpty) {
    for (final l in lines) {
      final t = l.text;
      if (t == 'SIGNATURE') {
        column(l);
      } else if (t == 'PUNONGBARANGAY' || t.contains('SIGNATUREOVERPRINTEDNAME') || t.contains('SIGNATUREOVERPRINTED')) {
        above(l);
      } else if (const ['PREPAREDBY', 'CERTIFIEDBY', 'CERTIFIEDCORRECT', 'ATTESTEDBY', 'NOTEDBY', 'APPROVEDBY'].any(t.startsWith)) {
        // "Prepared by: ____" → the signature is to the right of / below the label
        groups.add([add(rect(l.box.left, l.box.top - lh * 2, l.box.right + lh * 14, l.box.bottom + lh * 3))]);
      }
    }
  }
  return (regions: regions, groups: groups, masks: masks);
}

/// 0..1 likeness of two letter strings (edit distance).
double _similar(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0;
  if (a.contains(b) || b.contains(a)) return math.min(a.length, b.length) / math.max(a.length, b.length) + .3;
  final m = a.length, n = b.length;
  var prev = List<int>.generate(n + 1, (j) => j);
  for (var i = 1; i <= m; i++) {
    final cur = List<int>.filled(n + 1, 0)..[0] = i;
    for (var j = 1; j <= n; j++) {
      cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
    }
    prev = cur;
  }
  return 1 - prev[n] / math.max(m, n);
}

/// For each region: (share of dark "ink" pixels, share of columns with real strokes),
/// after ignoring printed text and removing ruled lines.
List<(double, double)> _inkIn((Uint8List, List<List<double>>, List<List<double>>) job) {
  final (jpg, regions, masks) = job;
  final im = img.decodeJpg(jpg)!;
  final w = im.width, h = im.height;
  final lum = Uint8List(w * h);
  for (final p in im) {
    lum[p.y * w + p.x] = math.min(255, math.max(0, p.luminance.toInt()));
  }

  final out = <(double, double)>[];
  for (final r in regions) {
    final int x0 = math.min(w - 1, math.max(0, r[0].floor())), y0 = math.min(h - 1, math.max(0, r[1].floor()));
    final int x1 = math.min(w, math.max(0, r[2].ceil())), y1 = math.min(h, math.max(0, r[3].ceil()));
    final rw = x1 - x0, rh = y1 - y0;
    if (rw < 10 || rh < 6) {
      out.add((0, 0));
      continue;
    }
    // Paper brightness here → what counts as ink
    final hist = List<int>.filled(256, 0);
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        hist[lum[y * w + x]]++;
      }
    }
    var acc = 0, median = 0;
    final half = rw * rh ~/ 2;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= half) {
        median = v;
        break;
      }
    }
    final t = math.min(median * .62, median - 45.0);
    if (t < 15) {
      out.add((0, 0)); // too dark to judge
      continue;
    }

    final dark = Uint8List(rw * rh);
    for (var y = 0; y < rh; y++) {
      for (var x = 0; x < rw; x++) {
        if (lum[(y + y0) * w + x + x0] < t) dark[y * rw + x] = 1;
      }
    }
    // Ignore printed text
    for (final m in masks) {
      final mx0 = math.max(0, m[0].floor() - 3 - x0), my0 = math.max(0, m[1].floor() - 3 - y0);
      final mx1 = math.min(rw, m[2].ceil() + 3 - x0), my1 = math.min(rh, m[3].ceil() + 3 - y0);
      for (var y = my0; y < my1; y++) {
        for (var x = mx0; x < mx1; x++) {
          dark[y * rw + x] = 0;
        }
      }
    }
    // Remove ruled lines (signature lines, table borders)
    final clearRows = <int>{};
    for (var y = 0; y < rh; y++) {
      var c = 0;
      for (var x = 0; x < rw; x++) {
        c += dark[y * rw + x];
      }
      if (c > rw * .35) clearRows.addAll([y - 1, y, y + 1]);
    }
    for (final y in clearRows) {
      if (y < 0 || y >= rh) continue;
      dark.fillRange(y * rw, y * rw + rw, 0);
    }
    for (var x = 0; x < rw; x++) {
      var c = 0;
      for (var y = 0; y < rh; y++) {
        c += dark[y * rw + x];
      }
      if (c > rh * .35) {
        for (var xx = math.max(0, x - 1); xx <= math.min(rw - 1, x + 1); xx++) {
          for (var y = 0; y < rh; y++) {
            dark[y * rw + xx] = 0;
          }
        }
      }
    }
    // Measure
    var total = 0, strongCols = 0;
    for (var x = 0; x < rw; x++) {
      var c = 0;
      for (var y = 0; y < rh; y++) {
        c += dark[y * rw + x];
      }
      total += c;
      if (c >= 4) strongCols++;
    }
    out.add((total / (rw * rh), strongCols / rw));
  }
  return out;
}

// ============================== ON SCREEN ==============================

/// Checks the picked file with a "Checking…" window, then explains the result.
/// Returns:
///   (check, retry: false) → go ahead and upload (check.note is saved with it)
///   (null, retry: true)   → the person wants to pick another file
///   (null, retry: false)  → cancelled
Future<({PaperCheck? check, bool retry})> runPaperCheck(
    BuildContext context, UploadedFile up, DocKind kind, BrgyRecord rec) async {
  if (!kPaperCheckOn) {
    return (check: const PaperCheck(PaperVerdict.ok, '', ''), retry: false);
  }
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Row(children: [
          const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(width: 18),
          Expanded(
            child: Text(tr('Checking the signed ${kind.title}…', 'Sinusuri ang pirmadong ${kind.title}…', 'Ginausisa ang may pirma nga ${kind.title}…'),
                style: sans(16, w: FontWeight.w600, color: C.navy)),
          ),
        ]),
      ),
    ),
  );

  PaperCheck check;
  try {
    check = await checkPaper(up, kind, rec);
  } catch (e) {
    debugPrint('Paper check failed: $e');
    check = const PaperCheck(PaperVerdict.notChecked, 'The paper could not be checked.', 'Not auto-checked (check failed)');
  }
  if (!context.mounted) return (check: null, retry: false);
  Navigator.of(context, rootNavigator: true).pop(); // close "Checking…"

  if (check.ok || check.verdict == PaperVerdict.notChecked) return (check: check, retry: false);

  // Something's off: explain it
  final refused = check.refused;
  final color = refused ? C.red : C.yellowDark;
  final title = switch (check.verdict) {
    PaperVerdict.wrongDocument => 'Wrong document',
    PaperVerdict.appFile => 'This file isn’t signed',
    PaperVerdict.noSignature => 'No signature found',
    PaperVerdict.notOurTanods => 'Different tanod list?',
    _ => 'Please check the photo',
  };
  final answer = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      icon: Icon(refused ? Icons.block_rounded : Icons.warning_amber_rounded, color: color, size: 34),
      title: Text(title, textAlign: TextAlign.center, style: sans(19, w: FontWeight.w700, color: C.navy)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(check.message, textAlign: TextAlign.center, style: sans(15.5, color: C.ink, h: 1.45)),
          if (!refused) ...[
            const SizedBox(height: 12),
            Text('If you upload it anyway, the municipality will see this note.',
                textAlign: TextAlign.center, style: sans(13.5, color: C.muted, h: 1.4)),
          ],
        ]),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsOverflowButtonSpacing: 8,
      actions: [
        if (!refused)
          TextButton(onPressed: () => Navigator.pop(ctx, 'anyway'), child: Text('Upload anyway', style: sans(15, color: C.muted))),
        TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: Text('Cancel', style: sans(15, color: C.muted))),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: C.navy, foregroundColor: Colors.white, minimumSize: const Size(0, 46)),
          onPressed: () => Navigator.pop(ctx, 'retry'),
          icon: const Icon(Icons.upload_rounded, size: 18),
          label: const Text('Upload another'),
        ),
      ],
    ),
  );
  if (answer == 'anyway') {
    return (check: PaperCheck(check.verdict, check.message, '${check.note} · uploaded anyway'), retry: false);
  }
  return (check: null, retry: answer == 'retry');
}