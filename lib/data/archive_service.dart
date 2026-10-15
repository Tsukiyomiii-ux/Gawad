// ARCHIVE: a permanent copy of each finished document (Payroll, Masterlist,
// Certification, ID photocopy sheet), kept by year in Firebase.
//
// Matches the team's security rules (match /archives/{archiveId}):
//
//   archives/{autoId}
//     type            'payroll' | 'masterlist' | 'barangay_certificate' | 'id_photocopy'
//     level           'municipal' (Payroll / Masterlist) | 'barangay' (Certification / ID sheet)
//     year            2026 (int)
//     fileName        'Payroll - Pavia (all barangays) - 2026.pdf'
//     sizeBytes       size of the PDF (int, max 8 MB)
//     chunkCount      number of pieces (int, 1..10)
//     uploadedBy      Firebase uid of who archived it
//     municipalityId, municipalityName, barangayId, barangayName,
//     tanodCount, savedBy (name), savedAt (server time)
//
//   archives/{autoId}/chunks/{0,1,2…}
//     index           piece number
//     data            the bytes (max 900 KB per piece)
//
// The record and all its pieces are saved together in ONE batch (the rules
// check the record while the pieces are added). Nothing is ever edited;
// archiving again makes a new copy. In demo mode (no Firebase sign-in) the
// archive is kept in memory only, so the screens still work in the pitch.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:tanod_incentives/data/doc_kind.dart';
import 'package:tanod_incentives/data/cloud.dart';

const _chunkSize = 900 * 1024; // the rules allow 921600 bytes per piece
const _maxBytes = 8388608; // 8 MB (rules)

/// Our document kinds ↔ the "type" names in the rules.
const Map<DocKind, String> _typeOf = {
  DocKind.payroll: 'payroll',
  DocKind.masterlist: 'masterlist',
  DocKind.certification: 'barangay_certificate',
  DocKind.idSheet: 'id_photocopy',
};

DocKind _kindOf(dynamic type) =>
    _typeOf.entries.firstWhere((e) => e.value == type, orElse: () => const MapEntry(DocKind.payroll, 'payroll')).key;

class ArchiveEntry {
  final String id;
  final DocKind kind;
  final int year;
  final String municipalityId, municipalityName;
  final String barangayId, barangayName;
  final int tanodCount;
  final String fileName;
  final int sizeBytes;
  final int chunkCount;
  final String savedBy;
  final DateTime? savedAt;
  final Uint8List? demoPdf; // demo mode only (online copies are loaded when opened)

  const ArchiveEntry({
    required this.id,
    required this.kind,
    required this.year,
    required this.municipalityId,
    required this.municipalityName,
    required this.barangayId,
    required this.barangayName,
    required this.tanodCount,
    required this.fileName,
    required this.sizeBytes,
    required this.chunkCount,
    required this.savedBy,
    required this.savedAt,
    this.demoPdf,
  });

  bool get municipal => barangayId.isEmpty;

  /// "Pavia" or "Brgy. Ungka I, Pavia"
  String get place => municipal ? municipalityName : 'Brgy. $barangayName, $municipalityName';

  factory ArchiveEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    final ts = m['savedAt'];
    return ArchiveEntry(
      id: d.id,
      kind: _kindOf(m['type']),
      year: (m['year'] as num?)?.toInt() ?? 0,
      municipalityId: '${m['municipalityId'] ?? ''}',
      municipalityName: '${m['municipalityName'] ?? ''}',
      barangayId: m['level'] == 'barangay' ? '${m['barangayId'] ?? ''}' : '',
      barangayName: '${m['barangayName'] ?? ''}',
      tanodCount: (m['tanodCount'] as num?)?.toInt() ?? 0,
      fileName: '${m['fileName'] ?? 'document.pdf'}',
      sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
      chunkCount: (m['chunkCount'] as num?)?.toInt() ?? 0,
      savedBy: '${m['savedBy'] ?? ''}',
      savedAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

class ArchiveService {
  ArchiveService._();
  static final instance = ArchiveService._();

  FirebaseFirestore get _fs => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col => _fs.collection('archives');

  /// Signed in with a real Firebase account?
  bool get online {
    if (!firebaseReady) return false;
    try {
      return FirebaseAuth.instance.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  // Demo mode: kept in memory
  final List<ArchiveEntry> _memory = [];
  final _memoryChanges = StreamController<List<ArchiveEntry>>.broadcast();

  /// Saves one PDF to the archive (record + pieces in one batch).
  Future<void> save({
    required DocKind kind,
    required int year,
    required String municipalityId,
    required String municipalityName,
    String barangayId = '',
    String barangayName = '',
    required int tanodCount,
    required String fileName,
    required Uint8List pdf,
  }) async {
    if (pdf.isEmpty) throw StateError('The PDF is empty.');
    if (pdf.length > _maxBytes) {
      throw StateError('This PDF is too big to archive (${pdf.length ~/ 1024} KB, the limit is 8 MB).');
    }
    final savedBy = '${cloud.profile?['displayName'] ?? cloud.profile?['role'] ?? 'Demo user'}';
    final chunkCount = (pdf.length / _chunkSize).ceil();
    final municipalDoc = barangayId.isEmpty;

    if (!online) {
      _memory.insert(
        0,
        ArchiveEntry(
          id: 'demo-${DateTime.now().microsecondsSinceEpoch}',
          kind: kind,
          year: year,
          municipalityId: municipalityId,
          municipalityName: municipalityName,
          barangayId: barangayId,
          barangayName: barangayName,
          tanodCount: tanodCount,
          fileName: fileName,
          sizeBytes: pdf.length,
          chunkCount: chunkCount,
          savedBy: savedBy,
          savedAt: DateTime.now(),
          demoPdf: pdf,
        ),
      );
      _memoryChanges.add(List.of(_memory));
      return;
    }

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = _col.doc();
    final batch = _fs.batch();
    batch.set(ref, {
      // checked by the rules
      'type': _typeOf[kind],
      'level': municipalDoc ? 'municipal' : 'barangay',
      'year': year,
      'fileName': fileName,
      'sizeBytes': pdf.length,
      'chunkCount': chunkCount,
      'uploadedBy': uid,
      'municipalityId': municipalityId,
      if (!municipalDoc) 'barangayId': barangayId,
      // extra info for the screens
      'municipalityName': municipalityName,
      'barangayName': barangayName,
      'tanodCount': tanodCount,
      'contentType': 'application/pdf',
      'savedBy': savedBy,
      'savedAt': FieldValue.serverTimestamp(),
    });
    for (var i = 0; i < chunkCount; i++) {
      final start = i * _chunkSize;
      final end = math.min(start + _chunkSize, pdf.length);
      batch.set(ref.collection('chunks').doc('$i'), {
        'index': i,
        'data': Blob(Uint8List.sublistView(pdf, start, end)),
      });
    }
    await batch.commit().timeout(const Duration(seconds: 60));
  }

  /// The archived PDF (pieces joined back together).
  Future<Uint8List> loadPdf(ArchiveEntry e) async {
    final demo = e.demoPdf;
    if (demo != null) return demo;
    final snap = await _col.doc(e.id).collection('chunks').get();
    final pieces = snap.docs.toList()
      ..sort((a, b) => ((a.data()['index'] as num?) ?? 0).compareTo((b.data()['index'] as num?) ?? 0));
    final out = BytesBuilder(copy: false);
    for (final p in pieces) {
      final d = p.data()['data'];
      if (d is Blob) out.add(d.bytes);
    }
    final bytes = out.toBytes();
    if (bytes.isEmpty) throw StateError('This archived copy has no file.');
    return bytes;
  }

  /// Live list, newest first. [municipalityId] = only that town (municipal
  /// accounts); null = everything (OPPDC).
  Stream<List<ArchiveEntry>> watch({String? municipalityId}) {
    if (!online) {
      List<ArchiveEntry> pick(List<ArchiveEntry> l) =>
          [for (final e in l) if (municipalityId == null || e.municipalityId == municipalityId) e];
      late final StreamController<List<ArchiveEntry>> c;
      StreamSubscription<List<ArchiveEntry>>? sub;
      c = StreamController<List<ArchiveEntry>>(
        onListen: () {
          c.add(pick(_memory));
          sub = _memoryChanges.stream.listen((l) => c.add(pick(l)));
        },
        onCancel: () => sub?.cancel(),
      );
      return c.stream;
    }
    // No orderBy here (it would need a Firestore index); sorted on the phone.
    final Query<Map<String, dynamic>> q =
        municipalityId == null ? _col : _col.where('municipalityId', isEqualTo: municipalityId);
    return q.snapshots().map((s) {
      final list = s.docs.map(ArchiveEntry.fromDoc).toList()
        ..sort((a, b) => (b.savedAt ?? DateTime(3000)).compareTo(a.savedAt ?? DateTime(3000)));
      return list;
    });
  }
}

final archive = ArchiveService.instance;