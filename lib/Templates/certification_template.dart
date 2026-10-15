import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'payroll_template.dart'; // Reuses TanodPerson

/// Long bond paper (8.5" x 13"), 1-inch margins — same as the .docx template.
const PdfPageFormat _longBond = PdfPageFormat(
  8.5 * PdfPageFormat.inch,
  13 * PdfPageFormat.inch,
  marginAll: PdfPageFormat.inch,
);

/// Fixed "as of" date for the six (6) months of service.
/// Matches the payroll period (CY 2025). Change here if it ever changes.
const String kDateOfServiceRendered = 'December 31, 2025';

const List<String> _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Template 3: Certification of Barangay Tanods.
///
/// One certificate is generated per barangay, because each Punong Barangay
/// can only certify the tanods of their own barangay.
///
/// Fields that are NOT on the PhilSys ID (date of service, Punong Barangay)
/// are parameters so the UI text fields can pass them in later. When left
/// empty they print as blank lines to be filled in by hand.
Future<Uint8List> generateCertificationPdf({
  required List<TanodPerson> tanodList,
  String dateOfServiceRendered = kDateOfServiceRendered,
  String punongBarangay = '', // Punong Barangay of [signingBarangay]
  String signingBarangay = '', // the signed-in account's barangay
  DateTime? issueDate, // Defaults to the day the PDF is generated
}) async {
  final pdf = pw.Document();
  final date = issueDate ?? DateTime.now();
  final String day = _ordinal(date.day);
  final String month = _months[date.month - 1];
  final String year = '${date.year}';

  // Group scanned tanods by barangay → one certificate each
  // One certificate per barangay the tanods LIVE in (from their ID address).
  // Keyed by barangay + municipality so same-named barangays in different
  // towns don't get merged.
  final Map<String, List<TanodPerson>> groupedByBarangay = {};
  for (final person in tanodList) {
    final key = '${person.addressBarangay}|${person.addressMunicipality}';
    groupedByBarangay.putIfAbsent(key, () => []).add(person);
  }

  groupedByBarangay.forEach((key, members) {
    final String barangayName = members.first.addressBarangay;
    final String barangay = _titleCase(barangayName);
    final String municipality = _titleCase(members.first.addressMunicipality);
    // Only the account's own Punong Barangay is known; other barangays get a blank line
    final String captain = barangayName.trim().toUpperCase() == signingBarangay.trim().toUpperCase()
        ? punongBarangay
        : '';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: _longBond,
        // MultiPage lets a long list of names flow onto a 2nd page
        build: (pw.Context context) => [
          // --- LETTERHEAD ---
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text('Republic of the Philippines',
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.Text('PROVINCE OF ILOILO',
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.Text('City/Municipality of $municipality',
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 12),
                pw.Text('BARANGAY ${barangayName.toUpperCase()}',
                    style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 30),
                pw.Text('OFFICE OF THE PUNONG BARANGAY',
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 12),
                pw.Text('CERTIFICATION',
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // --- BODY ---
          pw.Text('TO WHOM IT MAY CONCERN:',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          _paragraph([const pw.TextSpan(text: 'This is to certify that the following names:')]),
          pw.SizedBox(height: 12),

          // Numbered list of names from the scanned IDs
          ...List.generate(members.length, (i) {
            return pw.Padding(
              padding: const pw.EdgeInsets.only(left: 72, bottom: 1),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 22,
                    child: pw.Text('${i + 1}.', style: const pw.TextStyle(fontSize: 12)),
                  ),
                  pw.Text(
                    _certName(members[i]),
                    style: const pw.TextStyle(
                      fontSize: 12,
                      decoration: pw.TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            );
          }),
          pw.SizedBox(height: 14),

          _paragraph([
            const pw.TextSpan(text: 'Are Barangay Tanod members of Barangay '),
            _fill(barangay),
            const pw.TextSpan(text: ', '),
            _fill(municipality),
            const pw.TextSpan(
                text: ', Iloilo have rendered at least six (6) months of service as of '),
            _fill(dateOfServiceRendered, blankWidth: 20),
            const pw.TextSpan(text: '.'),
          ]),
          pw.SizedBox(height: 12),

          _paragraph([
            const pw.TextSpan(
              text: 'This is to certify further that the above-said names of Barangay '
                  'Tanod have planted and grown at least five (5) trees within this year.',
            ),
          ]),
          pw.SizedBox(height: 4),
          _paragraph([
            const pw.TextSpan(
                text: 'This certification is issued for whatever legal purpose it may serve.'),
          ]),
          pw.SizedBox(height: 12),

          _paragraph([
            const pw.TextSpan(text: 'Done this '),
            _fill(day), // e.g. "14th" — the day the PDF was generated
            const pw.TextSpan(text: ' day of '),
            _fill(month),
            const pw.TextSpan(text: ', '),
            _fill(year),
            const pw.TextSpan(text: ' at Barangay '),
            _fill(barangay),
            const pw.TextSpan(text: ', '),
            _fill(municipality),
            const pw.TextSpan(text: ', Iloilo.'),
          ]),
          pw.SizedBox(height: 60),

          // --- SIGNATORY (Punong Barangay comes from the UI later) ---
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 230,
              child: pw.Column(
                children: [
                  pw.Text(
                    captain.trim().isEmpty
                        ? '(Signature over Printed Name)'
                        : captain.trim().toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      fontStyle: captain.trim().isEmpty
                          ? pw.FontStyle.italic
                          : pw.FontStyle.normal,
                    ),
                  ),
                  pw.Container(height: 0.8, color: PdfColors.black),
                  pw.SizedBox(height: 2),
                  pw.Text('Punong Barangay', style: const pw.TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  });

  return pdf.save();
}

/// "Elmer S. Abenido Jr." — first name, middle initial, last name, suffix.
String _certName(TanodPerson t) {
  final mid = t.middleName.trim();
  final String mi = mid.isEmpty
      ? ''
      : (mid.endsWith('.') ? mid : '${mid[0].toUpperCase()}.');
  final parts = [
    _titleCase(t.firstName),
    mi,
    _titleCase(t.lastName),
    t.suffix.trim(),
  ].where((s) => s.isNotEmpty);
  return parts.join(' ');
}

/// 1 → "1st", 2 → "2nd", 3 → "3rd", 11 → "11th", 22 → "22nd"
String _ordinal(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}

/// "SAN RAFAEL" → "San Rafael" (IDs and the parser store names in caps).
String _titleCase(String s) {
  return s
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// Justified paragraph with a half-inch first-line indent, like the .docx.
pw.Widget _paragraph(List<pw.InlineSpan> spans) {
  return pw.RichText(
    textAlign: pw.TextAlign.justify,
    text: pw.TextSpan(
      style: const pw.TextStyle(fontSize: 12, lineSpacing: 2),
      children: [
        pw.WidgetSpan(child: pw.SizedBox(width: 36)),
        ...spans,
      ],
    ),
  );
}

/// Underlined "filled-in" value. Empty values print as a blank line.
pw.TextSpan _fill(String value, {int blankWidth = 14}) {
  final text = value.trim().isEmpty ? '_' * blankWidth : value.trim();
  return pw.TextSpan(
    text: text,
    style: pw.TextStyle(
      decoration: value.trim().isEmpty ? null : pw.TextDecoration.underline,
    ),
  );
}