import 'package:flutter/material.dart';

// The four documents every barangay prepares for the tanod incentive.
enum DocKind { payroll, masterlist, certification, idSheet }

/// The documents the barangay signs, uploads and shares. Payroll and
/// Masterlist are still made by the system (OPPDC / municipality can open
/// them), but the barangay no longer previews or uploads them.
const kBarangayDocs = [DocKind.certification, DocKind.idSheet];

extension DocKindInfo on DocKind {
  // Official document names stay in English on every screen.
  String get title => switch (this) {
        DocKind.payroll => 'Payroll',
        DocKind.masterlist => 'Masterlist',
        DocKind.certification => 'Barangay Certification',
        DocKind.idSheet => 'ID photocopy sheet',
      };

  IconData get icon => switch (this) {
        DocKind.payroll => Icons.receipt_long_outlined,
        DocKind.masterlist => Icons.list_alt_outlined,
        DocKind.certification => Icons.verified_outlined,
        DocKind.idSheet => Icons.badge_outlined,
      };

  String get blurb => switch (this) {
        DocKind.payroll => 'Names, amounts and total, with a payee signature column',
        DocKind.masterlist => 'Every tanod with the ID they presented',
        DocKind.certification => 'Certifies the tanods who served this year',
        DocKind.idSheet => 'One box per ID copy with 3 signature lines',
      };
}