// TEMP: dummy tanods for testing the Overview tiles and filters.
// Used by store.dart (Brgy. Abat): `tanods: demoTanods()`.
// For real use, set that back to `tanods: []` and delete this file.

import 'dart:convert';
import 'dart:typed_data';

import 'package:tanod_incentives/data/demo_data.dart'; // Tanod

// A 1x1 grey picture standing in for an ID photo, so a dummy tanod can count
// as "has front/back ID photo". Real scans have the actual card photos.
final Uint8List _demoPhoto = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

// Gives a dummy tanod both ID photos (so it isn't "Missing inputs")
Tanod _withPhotos(Tanod t) => t
  ..idFront = _demoPhoto
  ..idBack = _demoPhoto;

List<Tanod> demoTanods() => [
      // Completed: name checked + ID photos (8)
      _withPhotos(Tanod('Rodel', 'A', 'Gonzaga', kIdType)),
      _withPhotos(Tanod('Ernesto', 'B', 'Villanueva', kIdType)),
      _withPhotos(Tanod('Jonathan', 'D', 'Tupas', kIdType)),
      _withPhotos(Tanod('Arnel', 'S', 'Caballero', kIdType)),
      _withPhotos(Tanod('Romeo', 'L', 'Sorongon', kIdType)),
      _withPhotos(Tanod('Danilo', 'M', 'Belleza', kIdType)),
      _withPhotos(Tanod('Noel', 'R', 'Tolentino', kIdType)),
      _withPhotos(Tanod('Jessie', '', 'Alcantara', kIdType)), // no middle initial: still complete

      // Misspelled only: has photos, name not checked yet (4)
      _withPhotos(Tanod('Mario', 'C', 'Peñaflor', kIdType, confirmed: false)),
      _withPhotos(Tanod('Rogelio', 'P', 'Jaleco', kIdType, confirmed: false)),
      _withPhotos(Tanod('Edgar', 'G', 'Lamasan', kIdType, confirmed: false)),
      _withPhotos(Tanod('Wilfredo', 'O', 'Dioso', kIdType, confirmed: false)),

      // Missing inputs only: name checked, but no ID photos (4)
      Tanod('Felix', 'T', 'Gallego', kIdType),
      Tanod('Ricardo', 'V', 'Panes', kIdType),
      Tanod('Leonardo', 'E', 'Hechanova', kIdType),
      Tanod('Alfredo', 'J', 'Moreno', kIdType),

      // Name not checked AND no ID photos (2)
      Tanod('Ramil', 'K', 'Segovia', kIdType, confirmed: false),
      Tanod('Virgilio', 'N', 'Dela Peña', kIdType, confirmed: false),

      // Duplicates: same first + last name as someone above (2)
      Tanod('Rodel', '', 'Gonzaga', kIdType), // same as 001 Rodel A. Gonzaga
      Tanod('Noel', 'R', 'Tolentino', kIdType, confirmed: false), // same as 007 Noel R. Tolentino
    ];