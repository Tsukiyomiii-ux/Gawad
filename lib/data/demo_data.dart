import 'dart:typed_data';

// Demo data for the barangay dashboard. Replace with real records later.

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

List<Tanod> demoTanods() => [
      Tanod('Rodel', 'A', 'Gonzaga', 'PhilSys National ID'),
      Tanod('Ernesto', 'B', 'Villanueva', "Voter's ID"),
      Tanod('Mario', 'C', 'Peñaflor', 'Barangay ID', confirmed: false),
      Tanod('Jonathan', 'D', 'Tupas', 'PhilSys National ID'),
      Tanod('Arnel', 'S', 'Caballero', "Driver's License"),
      Tanod('Romeo', 'L', 'Sorongon', 'PhilSys National ID'),
      Tanod('Danilo', 'M', 'Belleza', 'Postal ID'),
      Tanod('Rogelio', 'P', 'Jaleco', "Voter's ID"),
      Tanod('Felix', 'T', 'Gallego', 'Senior Citizen ID'),
      Tanod('Noel', 'R', 'Tolentino', 'PhilSys National ID'),
      Tanod('Ricardo', 'V', 'Panes', 'Barangay ID'),
      Tanod('Edgar', 'G', 'Lamasan', "Voter's ID"),
      Tanod('Jessie', 'N', 'Alcantara', 'PhilSys National ID'),
      Tanod('Leonardo', 'E', 'Hechanova', "Driver's License"),
      Tanod('Wilfredo', 'O', 'Dioso', 'PhilSys National ID'),
      Tanod('Alfredo', 'J', 'Moreno', 'Barangay ID'),
      Tanod('Ramil', 'K', 'Segovia', "Voter's ID"),
      Tanod('Rodel', '', 'Gonzaga', 'Barangay ID'),
    ];
