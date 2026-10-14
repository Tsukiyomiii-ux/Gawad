import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'payroll_template.dart'; // Reuses TanodPerson

/// Template 4: ID Photocopy.
/// Builds an A4 "photocopy" of the ID: front on top, back below,
/// both printed in full color at the real card size.
class IdPhotocopy {
  // PhilID is the standard ID-1 card size: 85.6 x 54 mm, with ~3.18 mm rounded corners
  static const double _cardWidth = 85.6 * PdfPageFormat.mm;
  static const double _cardHeight = 54 * PdfPageFormat.mm;
  static const double _cornerRadius = 3.18 * PdfPageFormat.mm;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const String _defaultPurpose = 'For Tanod incentive records only';

  static const _margin = pw.EdgeInsets.symmetric(
    horizontal: 20 * PdfPageFormat.mm,
    vertical: 25 * PdfPageFormat.mm,
  );

  static String _today() {
    final now = DateTime.now();
    return '${_months[now.month - 1]} ${now.day}, ${now.year}';
  }

  /// One ID. [front] and [back] should be the flattened card images from `flattenCard`.
  static Future<Uint8List> build({
    required Uint8List front,
    required Uint8List back,
    String purpose = _defaultPurpose,
  }) async {
    final doc = pw.Document(title: 'PhilID Photocopy', author: 'Tanod ID Scanner');
    doc.addPage(_page(front, back, '$purpose  •  ${_today()}'));
    return doc.save();
  }

  /// MERGE: all scanned tanods in one PDF, one page per ID (used by TemplatePdfScreen).
  /// Tanods without ID photos (QR scans) are listed on a cover note instead.
  static Future<Uint8List> buildAll({
    required List<TanodPerson> tanodList,
    String purpose = _defaultPurpose,
  }) async {
    final doc = pw.Document(title: 'PhilID Photocopies', author: 'Tanod ID Scanner');
    final date = _today();

    final withPhotos = tanodList.where((t) => t.hasIdPhotos).toList();
    final withoutPhotos = tanodList.where((t) => !t.hasIdPhotos).toList();

    for (final t in withPhotos) {
      doc.addPage(_page(t.idFront!, t.idBack!, '${t.fullName}  •  $purpose  •  $date'));
    }

    // Without this, a list of only QR scans would give an empty (invalid) PDF
    if (withoutPhotos.isNotEmpty) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: _margin,
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'No ID photo on file',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'These tanods were scanned by QR code, so no photo of the card was taken. '
                'Attach a physical photocopy of their ID.',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 10),
              ...List.generate(
                withoutPhotos.length,
                (i) => pw.Text(
                  '${i + 1}. ${withoutPhotos[i].fullName} (${withoutPhotos[i].barangay})',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return doc.save();
  }

  static pw.Page _page(Uint8List front, Uint8List back, String caption) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: _margin,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          _card(front),
          pw.SizedBox(height: 15 * PdfPageFormat.mm),
          _card(back),
          pw.SizedBox(height: 8 * PdfPageFormat.mm),
          // Common practice for ID photocopies: state the purpose so it can't be reused elsewhere
          pw.Text(
            caption,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
          // MERGE (Gawad): each ID copy is signed three (3) times by the tanod
          pw.SizedBox(height: 10 * PdfPageFormat.mm),
          for (var i = 1; i <= 3; i++)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 9 * PdfPageFormat.mm),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('$i.', style: const pw.TextStyle(fontSize: 9)),
                  pw.SizedBox(width: 6),
                  pw.Container(width: 70 * PdfPageFormat.mm, height: 0.7, color: PdfColors.black),
                ],
              ),
            ),
          pw.SizedBox(height: 2 * PdfPageFormat.mm),
          pw.Text('Signature of tanod', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        ],
      ),
    );
  }

  static pw.Widget _card(Uint8List bytes) => pw.SizedBox(
        width: _cardWidth,
        height: _cardHeight,
        // Rounded clip matches the real card and hides any background
        // that slips in at the corners
        child: pw.ClipRRect(
          horizontalRadius: _cornerRadius,
          verticalRadius: _cornerRadius,
          child: pw.Image(
            pw.MemoryImage(bytes),
            width: _cardWidth,
            height: _cardHeight,
            // The flattened image already has the card's exact ratio, so this fills
            // the slot exactly; an un-flattened fallback photo is trimmed, not stretched
            fit: pw.BoxFit.cover,
          ),
        ),
      );
}
