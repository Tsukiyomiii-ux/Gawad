// What the ID scanners collect. Only what the four documents need:
// name (first, middle initial, last, suffix) + ID photos.
//
// Set a flag to true to bring that field back everywhere (scan screens,
// typed checks, saved data). Nothing else needs to change.

/// Address on the ID. Off: the documents use the barangay of the signed-in
/// account, and there is no "lives in another barangay" warning.
const kCollectAddress = false;

/// Birthday on the ID. Off: not shown, not read, not saved.
const kCollectBirthday = false;

/// Only accept QR codes from a PhilSys National ID. Off (demo, no PSA
/// permission yet): any ID works. If its QR has no name, or there is no QR,
/// the name is read from the front photo instead, and you check/type it on
/// the next screen.
const kRequirePhilSysQr = false;