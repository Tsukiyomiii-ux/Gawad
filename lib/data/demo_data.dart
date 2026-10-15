import 'dart:typed_data';

// Account settings for the barangay dashboard (demo values until accounts
// come from a server). The tanod list itself starts empty and is filled
// only from scanned or typed IDs.

// Shows the status switcher in the top bar for presenting. Set to false
// once statuses come from the municipality and OPPDC through the backend.
const kDemoMode = true;

const kRepName = 'Melanie Dela Cruz';
const kRepFirstName = 'Melanie';
const kRepPosition = 'Treasurer';
const kCaptain = 'Hon. Roberto S. Abellar'; // Punong Barangay (signatory for this year)
const kBarangay = 'Abat';
const kMunicipality = 'Mina';
const kYear = 2026;
const kQuota = 20; // allowed number of tanods, set by OPPDC
const kAmountEach = 1000; // pesos per tanod (Ordinance 2020-240, Sec. 7(C))

const kIdTypes = [
  'PhilSys National ID',
  "Voter's ID",
  "Driver's License",
  'Barangay ID',
  'Postal ID',
  'Senior Citizen ID',
];

class Tanod {
  String first, middle, last, idType;
  bool confirmed;

  // MERGE: filled by the real ID scanners (empty / null for typed entries).
  String suffix;         // JR, SR, III...
  String scannedAddress; // only used to check the tanod lives in this barangay
  Uint8List? idFront;    // card photos from the OCR scan → ID photocopy sheet
  Uint8List? idBack;

  Tanod(
    this.first,
    this.middle,
    this.last,
    this.idType, {
    this.confirmed = true,
    this.suffix = '',
    this.scannedAddress = '',
    this.idFront,
    this.idBack,
  });

  String get fullName {
    final base = middle.isEmpty ? '$first $last' : '$first $middle. $last';
    return suffix.isEmpty ? base : '$base $suffix';
  }
  String get initials => '${first[0]}${last[0]}'.toUpperCase();

  // Used to spot names that may belong to the same person.
  String get nameKey => '${first.trim().toLowerCase()} ${last.trim().toLowerCase()}';
}
