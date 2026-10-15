// MERGE: the 4 Gawad documents → the real PDF templates, filled from the
// barangay's tanod list. Replaces the "Saved … (demo)" toasts.

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'package:tanod_incentives/theme.dart';
import 'package:tanod_incentives/data/demo_data.dart';
import 'package:tanod_incentives/data/doc_kind.dart';
import 'package:tanod_incentives/data/store.dart';
import 'package:tanod_incentives/data/tanod_bridge.dart';
import 'payroll_template.dart';
import 'masterlist_template.dart';
import 'certification_template.dart';
import 'id_photocopy.dart';

Future<Uint8List> buildOfficialPdf(BrgyRecord rec, DocKind kind) {
  final people = personsFor(rec);
  return switch (kind) {
    DocKind.payroll => generatePayrollPdf(
        tanodList: people,
        period: 'For the period CY $kYear',
        municipality: 'MUNICIPALITY OF ${kMunicipality.toUpperCase()}',
        defaultAmount: kAmountEach.toDouble(),
      ),
    DocKind.masterlist => generateMasterlistPdf(tanodList: people, calendarYear: '$kYear'),
    // Punong Barangay = "Certified correct" field in Documents → Edit
    // One certificate per barangay the tanods live in (from their IDs).
    // Only this account's own certificate gets its Punong Barangay's name.
    DocKind.certification => generateCertificationPdf(
        tanodList: people,
        punongBarangay: rec.captain,
        signingBarangay: rec.name,
      ),
    DocKind.idSheet => IdPhotocopy.buildAll(tanodList: people),
  };
}

String officialPdfName(BrgyRecord rec, DocKind kind) => '${kind.title} - Brgy ${rec.name} - $kYear.pdf';

/// Opens the filled PDF with print / share / save buttons.
Future<void> showOfficialPdf(BuildContext context, BrgyRecord rec, DocKind kind) {
  if (rec.tanods.isEmpty) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(tr('Add at least one tanod first.', 'Magdagdag muna ng kahit isang tanod.', 'Palihog magdugang anay sang bisan isa ka tanod.')),
        behavior: SnackBarBehavior.floating,
      ));
    return Future.value();
  }
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(
          title: Text('${kind.title} · Brgy. ${rec.name}'),
          backgroundColor: C.navy,
          foregroundColor: Colors.white,
        ),
        body: PdfPreview(
          build: (_) => buildOfficialPdf(rec, kind),
          pdfFileName: officialPdfName(rec, kind),
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
          allowPrinting: true,
          allowSharing: true,
        ),
      ),
    ),
  );
}