import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'payroll_template.dart'; // Reuses TanodPerson

extension MiddleInitialHelper on TanodPerson {
  String get middleInitial {
    final clean = middleName.trim();
    if (clean.isEmpty) return '';
    if (clean.endsWith('.')) return clean;
    return '${clean[0].toUpperCase()}.';
  }
}

Future<Uint8List> generateMasterlistPdf({
  required List<TanodPerson> tanodList,
  String calendarYear = '________',
}) async {
  final pdf = pw.Document();

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4, // Standard Portrait for masterlists
      margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 36),
      header: (pw.Context context) {
        return pw.Column(
          children: [
            pw.Center(
              child: pw.Text(
                'MASTERLIST OF BARANGAY TANODS CY $calendarYear',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 14),
          ],
        );
      },
      build: (pw.Context context) {
        return [
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black, width: 0.8),
            columnWidths: const {
              0: pw.FlexColumnWidth(0.8), // NO.
              1: pw.FlexColumnWidth(2.5), // LAST NAME
              2: pw.FlexColumnWidth(2.5), // FIRST NAME
              3: pw.FlexColumnWidth(1.4), // MIDDLE INITIAL
              4: pw.FlexColumnWidth(1.0), // SUFFIX
              5: pw.FlexColumnWidth(2.2), // ADDRESS
            },
            children: [
              // Header Row
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.white),
                children: [
                  _headerCell('NO.'),
                  _headerCell('LAST NAME'),
                  _headerCell('FIRST NAME'),
                  _headerCell('MIDDLE INITIAL'),
                  _headerCell('SUFFIX'),
                  _headerCell('ADDRESS'),
                ],
              ),
              // Data Rows populated dynamically from scanned IDs
              ...List.generate(tanodList.length, (index) {
                final tanod = tanodList[index];
                final String number = '${index + 1}';

                return pw.TableRow(
                  children: [
                    _dataCell(number, center: true),
                    _dataCell(tanod.lastName.toUpperCase()),
                    _dataCell(tanod.firstName),
                    _dataCell(tanod.middleInitial, center: true),
                    _dataCell(tanod.suffix, center: true),
                    _dataCell(
                      tanod.barangay.isNotEmpty ? tanod.barangay : tanod.rawAddress,
                    ),
                  ],
                );
              }),
            ],
          ),
        ];
      },
    ),
  );

  return pdf.save();
}

pw.Widget _headerCell(String text) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
    child: pw.Align(
      alignment: pw.Alignment.centerLeft,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    ),
  );
}

pw.Widget _dataCell(String text, {bool center = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
    child: pw.Align(
      alignment: center ? pw.Alignment.center : pw.Alignment.centerLeft,
      child: pw.Text(
        text,
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
        style: const pw.TextStyle(
          fontSize: 8.5,
        ),
      ),
    ),
  );
}