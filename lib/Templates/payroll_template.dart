import 'dart:convert';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Data model populated strictly from scanned PhilSys / QR data
class TanodPerson {
  final String pcn;
  final String firstName;
  final String middleName;
  final String lastName;
  final String suffix;
  final String sex;
  final String dob;
  final String pob;
  final String rawAddress;
  final String barangay;
  final String municipality;

  /// Flattened card photos from the OCR scanner (null for QR scans).
  /// Used by Template 4: ID Photocopy.
  final Uint8List? idFront;
  final Uint8List? idBack;

  /// True if this person came from the OCR (no-internet) scanner.
  final bool scannedByOcr;

  bool get hasIdPhotos => idFront != null && idBack != null;

  TanodPerson({
    required this.pcn,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.suffix,
    required this.sex,
    required this.dob,
    required this.pob,
    required this.rawAddress,
    required this.barangay,
    required this.municipality,
    this.idFront,
    this.idBack,
    this.scannedByOcr = false,
  });

  /// Built from the OCR scanner. Birthday and address are read from the card
  /// photo; barangay & municipality are split from the address (and checked
  /// by the tanod on the scanner screen). No PCN on the card front.
  factory TanodPerson.fromOcr({
    required String firstName,
    required String lastName,
    required String middleInitial,
    String birthDate = '',
    String address = '',
    required String barangay,
    required String municipality,
    Uint8List? idFront,
    Uint8List? idBack,
  }) {
    final mi = middleInitial.trim();
    final brgy = barangay.trim().toUpperCase();
    final muni = municipality.trim().toUpperCase();
    return TanodPerson(
      pcn: 'N/A',
      firstName: firstName.trim(),
      // Stored as "S." so every template prints the initial the same way
      middleName: mi.isEmpty ? '' : '${mi[0].toUpperCase()}.',
      lastName: lastName.trim(),
      suffix: '',
      sex: 'N/A',
      dob: birthDate.trim().isEmpty ? 'N/A' : birthDate.trim(),
      pob: 'N/A',
      rawAddress: address.trim().isEmpty ? '$brgy, $muni' : address.trim(),
      barangay: brgy,
      municipality: muni,
      idFront: idFront,
      idBack: idBack,
      scannedByOcr: true,
    );
  }

  String get fullName {
    final parts = [firstName, middleName, lastName, suffix]
        .where((s) => s.trim().isNotEmpty);
    return parts.isEmpty ? 'N/A' : parts.join(' ');
  }

  /// [idFront] / [idBack]: optional card photos taken after the QR scan
  /// (for Template 4: ID Photocopy).
  factory TanodPerson.fromJsonString(String raw, {Uint8List? idFront, Uint8List? idBack}) {
    try {
      final Map<String, dynamic> map = jsonDecode(raw);
      final Map<String, dynamic> data = map['data'] is Map<String, dynamic>
          ? map['data']
          : (map['subject'] is Map<String, dynamic> ? map['subject'] : map);

      final String addr = (data['address'] ?? data['permAddress'] ?? '').toString().trim();
      String brgy = (data['barangay'] ?? data['brgy'] ?? '').toString().trim();
      String muni = (data['municipality'] ?? data['city'] ?? '').toString().trim();

      // Extract barangay & municipality from address string if not isolated
      if (brgy.isEmpty && addr.isNotEmpty) {
        final tokens = addr.split(',');
        if (tokens.isNotEmpty) {
          brgy = tokens[0].replaceAll(RegExp(r'(?i)brgy\.?\s*'), '').trim();
        }
        if (tokens.length > 1) {
          muni = tokens[1].trim();
        }
      }

      return TanodPerson(
        pcn: (data['pcn'] ?? data['PCN'] ?? 'N/A').toString(),
        firstName: (data['firstName'] ?? data['fName'] ?? '').toString(),
        middleName: (data['middleName'] ?? data['mName'] ?? '').toString(),
        lastName: (data['lastName'] ?? data['lName'] ?? '').toString(),
        suffix: (data['suffix'] ?? '').toString(),
        sex: (data['sex'] ?? data['gender'] ?? 'N/A').toString(),
        dob: (data['dob'] ?? data['dateOfBirth'] ?? 'N/A').toString(),
        pob: (data['pob'] ?? data['placeOfBirth'] ?? 'N/A').toString(),
        rawAddress: addr.isNotEmpty ? addr : '$brgy, $muni',
        barangay: brgy.isNotEmpty ? brgy.toUpperCase() : 'ARIPDIP',
        municipality: muni.isNotEmpty ? muni.toUpperCase() : 'SAN RAFAEL',
        idFront: idFront,
        idBack: idBack,
      );
    } catch (_) {
      return TanodPerson(
        pcn: 'N/A',
        firstName: raw,
        middleName: '',
        lastName: '',
        suffix: '',
        sex: 'N/A',
        dob: 'N/A',
        pob: 'N/A',
        rawAddress: 'Aripdip, San Rafael',
        barangay: 'ARIPDIP',
        municipality: 'SAN RAFAEL',
        idFront: idFront,
        idBack: idBack,
      );
    }
  }
}

Future<Uint8List> generatePayrollPdf({
  required List<TanodPerson> tanodList,
  String period = 'For the period CY 2025',
  String municipality = 'MUNICIPALITY OF SAN RAFAEL',
  double defaultAmount = 2000.0,
}) async {
  final pdf = pw.Document();

  // 1. Group scanned Tanods by Barangay dynamically
  final Map<String, List<TanodPerson>> groupedByBarangay = {};
  for (final person in tanodList) {
    groupedByBarangay.putIfAbsent(person.barangay, () => []).add(person);
  }

  // Running Award Number continuously increments across the entire municipality
  int runningAwardNumber = 1;

  // 2. Generate an exact 1-to-1 official sheet per Barangay
  groupedByBarangay.forEach((barangayName, members) {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // --- 1. TOP OFFICIAL HEADER ---
              pw.Center(
                child: pw.Text(
                  'P  R  O  V  I  N  C  I   A   L               P   A   Y   R   O   L   L',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(period, style: const pw.TextStyle(fontSize: 7.5)),
              pw.SizedBox(height: 2),
              pw.Text(
                'We hereby acknowledge to have received from JEAN MAIRE G. UMADHAY, Provincial Treasurer of Iloilo, the sum herein specified opposite our respective names, as Financial Assistance to Barangay Tanods in their services;',
                style: const pw.TextStyle(fontSize: 7),
              ),
              pw.SizedBox(height: 5),

              // --- 2. MASTERLIST TABLE ---
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.black, width: 0.8),
                ),
                child: pw.Column(
                  children: [
                    // Header Row 1
                    pw.Row(
                      children: [
                        _box('AWARD\nNUMBER', flex: 7, height: 22),
                        _box('NAME', flex: 44, height: 22),
                        _box('ADDRESS', flex: 26, height: 22),
                        _box('AMOUNT\nDUE', flex: 11, height: 22),
                        _box('AWARD\nNUMBER', flex: 7, height: 22),
                        _box('REMARKS', flex: 10, height: 22),
                        _box('SIGNATURE', flex: 15, height: 22, isLast: true),
                      ],
                    ),
                    // Header Row 2
                    pw.Row(
                      children: [
                        _box('', flex: 7, height: 14),
                        _box('CLAIMANT', flex: 24, height: 14),
                        _box('POSITION', flex: 20, height: 14),
                        _box('', flex: 13, height: 14),
                        _box('', flex: 13, height: 14),
                        _box('', flex: 11, height: 14),
                        _box('', flex: 7, height: 14),
                        _box('', flex: 10, height: 14),
                        _box('', flex: 15, height: 14, isLast: true),
                      ],
                    ),
                    // Municipality Banner
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.symmetric(vertical: 2),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          top: pw.BorderSide(color: PdfColors.black, width: 0.7),
                          bottom: pw.BorderSide(color: PdfColors.black, width: 0.7),
                        ),
                      ),
                      child: pw.Center(
                        child: pw.Text(
                          municipality,
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
                        ),
                      ),
                    ),
                    // Cyan Barangay Banner
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.symmetric(vertical: 2),
                      color: const PdfColor.fromInt(0xFF00B0F0),
                      child: pw.Center(
                        child: pw.Text(
                          'BARANGAY $barangayName',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
                        ),
                      ),
                    ),
                    // Claimant Records for this Barangay
                    ...members.map((tanod) {
                      final awardNum = '${runningAwardNumber++}';
                      return pw.Container(
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(
                            top: pw.BorderSide(color: PdfColors.black, width: 0.5),
                          ),
                        ),
                        child: pw.Row(
                          children: [
                            _box(awardNum, flex: 7),
                            _box(tanod.fullName, flex: 24, bold: true, alignLeft: true),
                            _box('BARANGAY TANOD', flex: 20),
                            _box(tanod.barangay, flex: 13),
                            _box(tanod.municipality, flex: 13),
                            _box(defaultAmount.toStringAsFixed(2), flex: 11, alignRight: true),
                            _box(awardNum, flex: 7),
                            _box('', flex: 10),
                            _box('', flex: 15, isLast: true),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),

              pw.SizedBox(height: 6),

              // --- 3. ALL CERTIFICATIONS & ACCOUNTING ENTRIES (ROWS 26-50) ---
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.black, width: 0.8),
                ),
                child: pw.Column(
                  children: [
                    // ROW 1: Box A, B, C
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _footerBox(
                          flex: 1,
                          tag: 'A',
                          certText: 'CERTIFIED:  Services duly rendred as  stated',
                          officialName: 'MARIA ALFREDA S. FAJARDO',
                          subTitle: 'Signature over Printed Name / Position',
                          role: 'Authorized Official',
                        ),
                        _footerBox(
                          flex: 1,
                          tag: 'B',
                          certText: 'CERTIFIED: Supporting documents complete and proper',
                          officialName: 'ORWEN M. ANUEVO',
                          subTitle: 'Signature over Printed Name',
                          role: 'Head of Accounting Division Unit',
                        ),
                        _footerBox(
                          flex: 1,
                          tag: 'C',
                          certText: 'CERTIFIED: Cash available for the purpose',
                          officialName: 'JEAN MAIRE G. UMADHAY',
                          subTitle: 'Signature over Printed Name',
                          role: 'Head of Treasury Division/Unit',
                          isLast: true,
                        ),
                      ],
                    ),
                    pw.Container(height: 0.8, color: PdfColors.black),
                    // ROW 2: Box D, E, F
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _footerBox(
                          flex: 1,
                          tag: 'D',
                          certText: 'APPROVED FOR PAYMENT: ',
                          officialName: 'GOV. ARTHUR R. DEFENSOR, JR.',
                          subTitle: 'Signature over Printed Name / Position',
                          role: 'Local Chied Executive',
                        ),
                        _footerBox(
                          flex: 1,
                          tag: 'E',
                          certText: 'CERTIFIED: Each employee whose name appears on the payroll has been paid the',
                          officialName: '',
                          subTitle: 'Signature over Printed Name',
                          role: 'Disbursing Officer',
                        ),
                        // Box F: CAFOA
                        pw.Expanded(
                          flex: 1,
                          child: pw.Padding(
                            padding: const pw.EdgeInsets.all(3),
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text('[F]', style: const pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold)),
                                pw.SizedBox(height: 6),
                                pw.Text('CAFOA No.: _____________________', style: const pw.TextStyle(fontSize: 6.5)),
                                pw.SizedBox(height: 8),
                                pw.Text('Date: __________________________', style: const pw.TextStyle(fontSize: 6.5)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    pw.Container(height: 0.8, color: PdfColors.black),
                    // ROW 3: Box G - ACCOUNTING ENTRIES
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            '[G] ACCOUNTING ENTRIES',
                            style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold),
                          ),
                          pw.SizedBox(height: 2),
                          // Accounting columns
                          pw.Row(
                            children: [
                              _accCol('Particulars', flex: 2),
                              _accCol('Account Code', flex: 1),
                              _accCol('Debit', flex: 1),
                              _accCol('Credit', flex: 1),
                              pw.SizedBox(width: 8),
                              _accCol('Particulars', flex: 2),
                              _accCol('Account Code', flex: 1),
                              _accCol('Debit', flex: 1),
                              _accCol('Credit', flex: 1),
                            ],
                          ),
                          pw.SizedBox(height: 8),
                          // Prepared by row
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text('Prepared by: __________________________', style: const pw.TextStyle(fontSize: 6.5)),
                              pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.center,
                                children: [
                                  pw.Text('ORWEN M. ANUEVO', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                                  pw.Container(height: 0.5, width: 120, color: PdfColors.black),
                                  pw.Text('Head, Accounting Department Unit', style: const pw.TextStyle(fontSize: 6)),
                                ],
                              ),
                              pw.SizedBox(width: 20),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  });

  return pdf.save();
}

// Table cell helper
pw.Widget _box(
  String text, {
  required int flex,
  double? height,
  bool bold = false,
  bool alignLeft = false,
  bool alignRight = false,
  bool isLast = false,
}) {
  return pw.Expanded(
    flex: flex,
    child: pw.Container(
      height: height,
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1.5),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          right: isLast ? pw.BorderSide.none : const pw.BorderSide(color: PdfColors.black, width: 0.5),
        ),
      ),
      child: pw.Align(
        alignment: alignLeft
            ? pw.Alignment.centerLeft
            : (alignRight ? pw.Alignment.centerRight : pw.Alignment.center),
        child: pw.Text(
          text,
          textAlign: alignLeft
              ? pw.TextAlign.left
              : (alignRight ? pw.TextAlign.right : pw.TextAlign.center),
          style: pw.TextStyle(
            fontSize: 7,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ),
    ),
  );
}

// Certification sub-box helper
pw.Widget _footerBox({
  required int flex,
  required String tag,
  required String certText,
  required String officialName,
  required String subTitle,
  required String role,
  bool isLast = false,
}) {
  return pw.Expanded(
    flex: flex,
    child: pw.Container(
      padding: const pw.EdgeInsets.all(3),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          right: isLast ? pw.BorderSide.none : const pw.BorderSide(color: PdfColors.black, width: 0.8),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('[$tag] $certText', style: const pw.TextStyle(fontSize: 6)),
          pw.SizedBox(height: 12),
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text(
                  officialName,
                  style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
                ),
                pw.Container(height: 0.5, width: 140, color: PdfColors.black),
                pw.SizedBox(height: 1),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(subTitle, style: const pw.TextStyle(fontSize: 5.5)),
                    pw.Text('Date', style: const pw.TextStyle(fontSize: 5.5)),
                  ],
                ),
                pw.SizedBox(height: 1),
                pw.Text(role, style: const pw.TextStyle(fontSize: 6)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// Accounting entries mini-cell
pw.Widget _accCol(String title, {required int flex}) {
  return pw.Expanded(
    flex: flex,
    child: pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black, width: 0.4)),
      child: pw.Center(
        child: pw.Text(title, style: const pw.TextStyle(fontSize: 5.5)),
      ),
    ),
  );
}