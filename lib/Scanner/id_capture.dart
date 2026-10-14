// MERGE: the online/offline routing that used to live in the old main.dart.
// Online → PhilSys QR scanner. Offline → OCR photo scanner.
// Used by the Gawad "Scan PhilSys ID" flow (screens/scan/scan_flow_page.dart).

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tanod_incentives/Scanner/philsys_scanner.dart';
import 'package:tanod_incentives/Scanner/ocr_files/id_scanner_screen.dart';
import 'package:tanod_incentives/Templates/payroll_template.dart';

enum ScanMethod { auto, qr, ocr }

/// Quick internet check (no extra package needed).
Future<bool> hasInternet() async {
  try {
    final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 3));
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Opens the right scanner and returns the person, or null if cancelled
/// or the QR could not be read.
///
/// [barangay] / [municipality] are the account's area. The OCR screen uses
/// them when the address on the card can't be read.
Future<TanodPerson?> captureId(
  BuildContext context, {
  ScanMethod method = ScanMethod.auto,
  required String barangay,
  required String municipality,
}) async {
  var useQr = method == ScanMethod.qr;
  if (method == ScanMethod.auto) useQr = await hasInternet();
  if (!context.mounted) return null;

  if (useQr) {
    // PhilsysScannerView may return the raw QR text, or (with the
    // "take ID photos after the QR" feature) a finished TanodPerson.
    final result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(builder: (_) => const PhilsysScannerView()),
    );
    final TanodPerson? p = switch (result) {
      TanodPerson person => person,
      String raw => TanodPerson.fromJsonString(raw),
      _ => null,
    };
    // fromJsonString puts the whole text in firstName when it isn't PhilSys JSON
    if (p == null || p.lastName.isEmpty) return null;
    return p;
  }

  return Navigator.push<TanodPerson>(
    context,
    MaterialPageRoute(
      builder: (_) => IdScannerScreen(
        fallbackBarangay: barangay,
        fallbackMunicipality: municipality,
      ),
    ),
  );
}