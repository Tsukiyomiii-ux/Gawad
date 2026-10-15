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
      _withPhotos(Tanod('Rodel', 'A', 'Gonzaga', 'PhilSys National ID')),
      _withPhotos(Tanod('Ernesto', 'B', 'Villanueva', 'PhilSys National ID')),
      _withPhotos(Tanod('Jonathan', 'D', 'Tupas', 'PhilSys National ID')),
      _withPhotos(Tanod('Arnel', 'S', 'Caballero', "Driver's License")),
      _withPhotos(Tanod('Romeo', 'L', 'Sorongon', 'PhilSys National ID')),
      _withPhotos(Tanod('Danilo', 'M', 'Belleza', 'Postal ID')),
      _withPhotos(Tanod('Noel', 'R', 'Tolentino', 'PhilSys National ID')),
      _withPhotos(Tanod('Jessie', '', 'Alcantara', 'PhilSys National ID')), // no middle initial: still complete

      // Misspelled only: has photos, name not checked yet (4)
      _withPhotos(Tanod('Mario', 'C', 'Peñaflor', 'PhilSys National ID', confirmed: false)),
      _withPhotos(Tanod('Rogelio', 'P', 'Jaleco', "Voter's ID", confirmed: false)),
      _withPhotos(Tanod('Edgar', 'G', 'Lamasan', 'PhilSys National ID', confirmed: false)),
      _withPhotos(Tanod('Wilfredo', 'O', 'Dioso', 'Barangay ID', confirmed: false)),

      // Missing inputs only: name checked, but no ID photos (4)
      Tanod('Felix', 'T', 'Gallego', 'Senior Citizen ID'),
      Tanod('Ricardo', 'V', 'Panes', 'Barangay ID'),
      Tanod('Leonardo', 'E', 'Hechanova', "Driver's License"),
      Tanod('Alfredo', 'J', 'Moreno', "Voter's ID"),

      // Both: name not checked AND no ID photos (2)
      Tanod('Ramil', 'K', 'Segovia', "Voter's ID", confirmed: false),
      Tanod('Virgilio', 'N', 'Dela Peña', 'Postal ID', confirmed: false),
    ];