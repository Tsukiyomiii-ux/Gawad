// MERGE: connects the Gawad UI (Tanod / BrgyRecord) with the scanners and
// PDF templates (TanodPerson). The templates were written for TanodPerson,
// so every PDF is built from this conversion.

import 'package:tanod_incentives/Templates/payroll_template.dart';
import 'package:tanod_incentives/data/demo_data.dart';
import 'package:tanod_incentives/data/store.dart';

/// Scanner result → Gawad tanod. [idType] is what was scanned.
Tanod tanodFromPerson(TanodPerson p, {String idType = 'PhilSys National ID'}) {
  final mid = p.middleName.trim().replaceAll('.', '');
  return Tanod(
    _title(p.firstName),
    mid.isEmpty ? '' : mid[0].toUpperCase(),
    _title(p.lastName),
    idType,
    suffix: p.suffix.trim().toUpperCase(),
    scannedAddress: p.rawAddress,
    idFront: p.idFront,
    idBack: p.idBack,
  );
}

/// Gawad tanod → TanodPerson for the PDF templates. The barangay and
/// municipality always come from the barangay's account, not from the ID.
TanodPerson personFromTanod(Tanod t, BrgyRecord rec) {
  final brgy = rec.name.toUpperCase();
  final muni = kMunicipality.toUpperCase();
  return TanodPerson(
    pcn: 'N/A', // not kept (see the privacy notice on the scan screen)
    firstName: t.first,
    middleName: t.middle.isEmpty ? '' : '${t.middle}.',
    lastName: t.last,
    suffix: t.suffix,
    sex: 'N/A',
    dob: 'N/A',
    pob: 'N/A',
    rawAddress: '$brgy, $muni',
    barangay: brgy,
    municipality: muni,
    idFront: t.idFront,
    idBack: t.idBack,
  );
}

List<TanodPerson> personsFor(BrgyRecord rec) => [for (final t in rec.tanods) personFromTanod(t, rec)];

/// True when the ID's address names a different barangay than this account's.
/// Empty address (typed entries, QR without address) → no warning.
bool livesElsewhere(String scannedBarangay, String accountBarangay) {
  final a = scannedBarangay.trim().toUpperCase();
  return a.isNotEmpty && a != accountBarangay.trim().toUpperCase();
}

// "DELA CRUZ" → "Dela Cruz" so scanned names match the typed ones in the UI.
String _title(String s) => s
    .trim()
    .toLowerCase()
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');
