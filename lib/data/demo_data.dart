import 'dart:typed_data';

// Account settings for the barangay dashboard. These start as demo values;
// when someone signs in with a real account, data/cloud.dart replaces them
// with the values from Firebase (so they are `var`, not `const`).
// The tanod list itself is filled only from scanned or typed IDs.

// Shows the status switcher in the top bar for presenting. Set to false
// once statuses come from the municipality and OPPDC through the backend.
const kDemoMode = true;

var kRepName = 'Melanie Dela Cruz';
var kRepFirstName = 'Melanie';
var kRepPosition = 'Treasurer';
var kCaptain = 'Hon. Roberto S. Abellar'; // Punong Barangay (signatory for this year)
var kBarangay = 'Abat';
var kMunicipality = 'Mina';
var kYear = 2026;
var kQuota = 20; // allowed number of tanods, set by OPPDC (Firebase: tanodLimit)
var kAmountEach = 1000; // pesos per tanod (Firebase: years/{year}.amountPerTanod)

// Gawad accepts the PhilSys National ID only.
const kIdType = 'PhilSys National ID';
const kIdTypes = [kIdType]; // kept so older code still compiles

class Tanod {
  String first, middle, last, idType;
  bool confirmed;

  // MERGE: filled by the real ID scanners (empty / null for typed entries).
  String suffix;         // JR, SR, III...
  String scannedAddress; // only used to check the tanod lives in this barangay
  Uint8List? idFront;    // card photos from the OCR scan → ID photocopy sheet
  Uint8List? idBack;

  // FIREBASE: set once the tanod is saved online (null in demo mode)
  String? id;            // tanods/{id} document
  int? awardNumber;      // fixed number from the barangay's block (never shifts)

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