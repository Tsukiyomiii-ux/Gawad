// FIREBASE: connects the Gawad screens to the real database.
//
// The screens keep reading `store.abat` (the signed-in barangay) like in demo
// mode. This file fills it from Firebase and keeps it up to date (live), and
// sends every change back using the team's services in lib/services/.
//
// When nobody signed in with a real account (demo login, or Firebase not
// connected), `cloud.live` is false and every method here does nothing, so the
// demo keeps working exactly as before.
//
// Extra Firestore data this app adds on top of the team's database_service.dart:
//   tanods/{id}            + nameChecked (bool), suffix (String)
//   signedCopies/{year_brgyPsgc_kind}
//       { year, barangayId, municipalityId, kind, fileName, isPdf, via, data (Blob),
//         version, outdated, correction, uploadedAt }
// The security rules must allow these (see the note sent with this file).

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:printing/printing.dart' show Printing;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' show PdfPageFormat;

import 'package:tanod_incentives/theme.dart';
import 'package:tanod_incentives/data/demo_data.dart';
import 'package:tanod_incentives/data/doc_kind.dart';
import 'package:tanod_incentives/Templates/payroll_template.dart' show payrollOfficials;
import 'package:tanod_incentives/data/store.dart';
import 'package:tanod_incentives/services/auth_service.dart';
import 'package:tanod_incentives/services/database_service.dart';
import 'package:tanod_incentives/services/message_service.dart';

/// True when the app connected to Firebase at start-up (set in main.dart).
bool firebaseReady = false;

final cloud = Cloud._();

class Cloud {
  Cloud._();

  final auth = AuthService();
  late final db = DatabaseService(onSyncError: (e) => _error(friendly(e)));
  FirebaseFirestore get _fs => FirebaseFirestore.instance;

  /// users/{uid} of whoever signed in: role, displayName, municipalityId, barangayId
  Map<String, dynamic>? profile;
  bool get live => profile != null;
  String get role => (profile?['role'] ?? '') as String;
  String get barangayId => profile!['barangayId'] as String;
  String get municipalityId => profile!['municipalityId'] as String;
  String get threadId => MessageService.barangayThreadId(barangayId);

  int year = kYear;
  int awardStart = 1, awardEnd = 0;
  Set<int> usedNumbers = {};

  /// Changes every time online data arrives → screens listen and redraw.
  final changes = ValueNotifier<int>(0);

  /// A save that failed in the background → screens show it as a red pop-up.
  final errors = ValueNotifier<String?>(null);

  final List<StreamSubscription> _subs = [];
  final Set<String> _loadingScans = {};

  BrgyRecord get rec => store.abat;

  // ======================= SIGN IN / OUT =======================

  /// Signs in with the team's accounts (e.g. "brgy-ungka1"). Returns the role:
  /// 'barangay', 'municipal' or 'admin'. Throws a readable message on failure.
  Future<String> signIn(String loginId, String password) async {
    try {
      final p = await auth.signIn(loginId, password);
      profile = p;
      if (role == 'barangay') await _openBarangay();
      if (role == 'municipal') await _openMunicipal();
      return role;
    } catch (e) {
      profile = null;
      throw friendly(e);
    }
  }

  Future<void> signOut() async {
    await _stop();
    if (!live) return;
    profile = null;
    try {
      await auth.signOut();
    } catch (_) {}
    _restoreDemoValues();
    store.reset(); // back to the demo data
  }

  // The demo values, so signing out of a real account brings the demo back
  List<Object>? _demo;

  void _saveDemoValues() => _demo ??= [
        kRepName, kRepFirstName, kRepPosition, kCaptain, kBarangay, kMunicipality, kYear, kQuota, kAmountEach,
        kReviewerName, kReviewerFirstName,
      ];

  void _restoreDemoValues() {
    final d = _demo;
    if (d == null) return;
    kRepName = d[0] as String;
    kRepFirstName = d[1] as String;
    kRepPosition = d[2] as String;
    kCaptain = d[3] as String;
    kBarangay = d[4] as String;
    kMunicipality = d[5] as String;
    kYear = d[6] as int;
    kQuota = d[7] as int;
    kAmountEach = d[8] as int;
    kReviewerName = d[9] as String;
    kReviewerFirstName = d[10] as String;
  }

  Future<void> _stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
  }

  // ======================= LOADING (barangay) =======================

  Future<void> _openBarangay() async {
    await _stop();
    final y = await db.getCurrentYear();
    if (y == null) throw StateError('No incentive year has been started yet. Ask OPPDC (admin) to start one.');
    year = y;

    final bc = await db.getBarangayCompliance(barangayId, year: y);
    final yearInfo = await db.getYear(y);
    Map<String, dynamic>? brgy;
    try {
      brgy = await db.getBarangay(barangayId);
    } catch (_) {} // optional (only for the Punong Barangay name)

    // The values the screens show (were demo constants)
    _saveDemoValues();
    kYear = y;
    kBarangay = '${bc['barangayName'] ?? kBarangay}';
    kMunicipality = '${bc['municipalityName'] ?? kMunicipality}';
    final amount = yearInfo?['amountPerTanod'];
    if (amount is num) kAmountEach = amount.toInt();
    final name = '${profile!['displayName'] ?? kBarangay}';
    kRepName = name;
    kRepFirstName = name.split(' ').first;
    kCaptain = '${brgy?['punongBarangay'] ?? ''}';

    final r = rec;
    r
      ..name = kBarangay
      ..rep = name
      ..captain = kCaptain
      ..accountPending = false
      ..unreadBrgy = 0
      ..unreadMuni = 0
      ..paperOk.clear();
    r.tanods.clear();
    r.chat.clear();
    for (final f in r.files.values) {
      _resetFile(f);
    }
    _applyCompliance(bc);

    // Live updates
    _subs.add(db.watchBarangayCompliance(barangayId, y).listen((s) {
      if (s.exists) {
        _applyCompliance({'id': s.id, ...s.data()!});
        _changed();
      }
    }, onError: _onStreamError));
    _subs.add(db.watchBarangayTanods(barangayId, y).listen(_applyTanods, onError: _onStreamError));
    // The municipality's status with OPPDC (needs the barangay read rule on
    // municipalCompliance; without it the tracker just stops at "Received")
    _muniStatusForBrgy = '';
    _subs.add(_fs
        .collection('municipalCompliance')
        .doc(DatabaseService.complianceId(y, municipalityId))
        .snapshots()
        .listen((s) {
      _muniStatusForBrgy = '${s.data()?['status'] ?? ''}';
      _applyBarangayStage();
      _changed();
    }, onError: (Object e) => debugPrint('Municipal status not readable (rules): $e')));
    _subs.add(db.messages.watchMessages(threadId, limit: 200).listen(_applyMessages, onError: _onStreamError));
    _subs.add(_fs.collection('threads').doc(threadId).snapshots().listen((s) {
      final unread = s.data()?['unread'];
      rec.unreadBrgy = unread is Map ? ((unread['barangay'] as num?)?.toInt() ?? 0) : 0;
      _changed();
    }, onError: _onStreamError));
    for (final k in DocKind.values) {
      _subs.add(_copyRef(k).snapshots().listen((s) => _applyCopy(k, s), onError: _onStreamError));
    }
  }

  // BARANGAY STAGE: the barangay's own status + its municipality's status with
  // OPPDC (same rule as the admin dashboard):
  //   verified by the municipality  → Received at the Municipality
  //   + municipality submitted      → Enroute to OPPDC
  //   + OPPDC verified municipality → Incentive Released
  String _bcStatus = '';
  String _muniStatusForBrgy = '';

  void _applyBarangayStage() {
    rec.status = switch (_bcStatus) {
      Status.submitted => BrgyStatus.submitted,
      Status.returned => BrgyStatus.corrections,
      Status.verified => switch (_muniStatusForBrgy) {
          Status.verified => BrgyStatus.released,
          Status.submitted => BrgyStatus.sentToOppdc,
          _ => BrgyStatus.checked,
        },
      _ => BrgyStatus.preparing,
    };
  }

  void _applyCompliance(Map<String, dynamic> bc) {
    final limit = bc['tanodLimit'];
    if (limit is num) {
      kQuota = limit.toInt();
      rec.quota = kQuota;
    }
    awardStart = (bc['awardStart'] as num?)?.toInt() ?? 1;
    awardEnd = (bc['awardEnd'] as num?)?.toInt() ?? awardStart + kQuota - 1;
    usedNumbers = ((bc['usedNumbers'] as List?) ?? []).map((e) => (e as num).toInt()).toSet();

    _bcStatus = '${bc['status'] ?? ''}';
    _applyBarangayStage();

    // Signatories: the Punong Barangay, and whoever prepares the documents
    final sigs = (bc['signatories'] as List?) ?? [];
    for (final s in sigs) {
      if (s is! Map) continue;
      final n = '${s['name'] ?? ''}'.trim();
      final p = '${s['position'] ?? ''}'.trim();
      if (n.isEmpty) continue;
      if (p.toLowerCase().contains('punong')) {
        rec.captain = n;
        kCaptain = n;
      } else {
        rec.rep = n;
        if (p.isNotEmpty) {
          rec.position = p.replaceFirst(RegExp(r'^barangay\s+', caseSensitive: false), '');
          kRepPosition = rec.position;
        }
      }
    }
  }

  void _applyTanods(QuerySnapshot<Map<String, dynamic>> snap) {
    final old = {for (final t in rec.tanods) if (t.id != null) t.id!: t};
    final list = <Tanod>[];
    for (final d in snap.docs) {
      final m = d.data();
      final t = old[d.id] ?? Tanod('?', '', '?', kIdType);
      t
        ..id = d.id
        ..awardNumber = (m['awardNumber'] as num?)?.toInt()
        ..first = '${m['firstName'] ?? ''}'
        ..middle = '${m['middleInitial'] ?? ''}'
        ..last = '${m['lastName'] ?? ''}'
        ..suffix = '${m['suffix'] ?? ''}'
        ..scannedAddress = '${m['address'] ?? ''}'
        ..idType = kIdType
        ..confirmed = m['nameChecked'] is bool ? m['nameChecked'] as bool : true;
      list.add(t);
      if (m['hasIdScan'] == true && t.idFront == null) _loadScan(t);
    }
    // Keep tanods added on this device that are still being saved
    final pending = rec.tanods.where((t) => t.id == null).toList();
    rec.tanods
      ..clear()
      ..addAll(list)
      ..addAll(pending);
    _changed();
  }

  Future<void> _loadScan(Tanod t) async {
    final id = t.id;
    if (id == null || !_loadingScans.add(id)) return;
    try {
      final s = await db.getIdScan(id);
      if (s != null) {
        t.idFront = s.front;
        t.idBack = s.back;
        _changed();
      }
    } catch (_) {
      // photo not reachable right now; the tanod shows "Missing inputs"
    } finally {
      _loadingScans.remove(id);
    }
  }

  void _applyMessages(QuerySnapshot<Map<String, dynamic>> snap) {
    _fillChat(rec, snap);
    _changed();
  }

  /// Messages → the record's chat. A message whose text is a document's
  /// correction note is tagged with that document (shown on its card).
  void _fillChat(BrgyRecord r, QuerySnapshot<Map<String, dynamic>> snap) {
    r.chat
      ..clear()
      ..addAll(snap.docs.map((d) {
        final m = d.data();
        final text = '${m['text'] ?? ''}';
        DocKind? doc = _docKind(m['doc']);
        if (doc == null) {
          for (final f in r.files.values) {
            if (f.note != null && f.note == text) doc = f.kind;
          }
        }
        return ChatMsg(
          fromMunicipality: m['senderRole'] != 'barangay',
          text: text,
          time: timeLabel(m['createdAt']),
          doc: doc,
        );
      }));
  }

  void _applyCopy(DocKind k, DocumentSnapshot<Map<String, dynamic>> s) {
    _fillCopy(rec, rec.files[k]!, s.data());
    _retag(rec);
    _changed();
  }

  /// Correction notes can arrive after the messages: tag those messages now.
  void _retag(BrgyRecord r) {
    for (var i = 0; i < r.chat.length; i++) {
      final c = r.chat[i];
      if (c.doc != null) continue;
      for (final f in r.files.values) {
        if (f.note != null && f.note == c.text) {
          r.chat[i] = ChatMsg(fromMunicipality: c.fromMunicipality, text: c.text, time: c.time, doc: f.kind, system: c.system);
        }
      }
    }
  }

  /// signedCopies document → one document card. A record without `data` only
  /// holds the reviewer's marks (correction / paper OK), not an upload.
  void _fillCopy(BrgyRecord r, DocFile f, Map<String, dynamic>? m) {
    if (m == null) {
      _resetFile(f);
      r.paperOk.remove(f.kind);
      return;
    }
    final data = m['data'];
    final uploaded = data is Blob;
    f
      ..version = uploaded ? ((m['version'] as num?)?.toInt() ?? 1) : 0
      ..uploadedOn = uploaded ? timeLabel(m['uploadedAt']) : null
      ..via = '${m['via'] ?? 'photo'}'
      ..bytes = uploaded ? data.bytes : null
      ..fileName = m['fileName'] as String?
      ..isPdf = m['isPdf'] == true
      ..outdated = m['outdated'] == true
      ..correction = m['correction'] == true
      ..note = m['correctionNote'] as String?
      ..checkNote = uploaded ? m['autoCheck'] as String? : null
      ..checkOk = m['autoCheckOk'] != false;
    if (m['paperOk'] == true) {
      r.paperOk.add(f.kind);
    } else {
      r.paperOk.remove(f.kind);
    }
  }

  void _resetFile(DocFile f) {
    f
      ..version = 0
      ..uploadedOn = null
      ..bytes = null
      ..fileName = null
      ..isPdf = false
      ..outdated = false
      ..correction = false
      ..note = null
      ..checkNote = null
      ..checkOk = true;
  }

  // ======================= SAVING (barangay) =======================

  /// The award number the next added tanod will get (lowest free in the block).
  int? get nextAwardNumber {
    for (var n = awardStart; n <= awardEnd; n++) {
      if (!usedNumbers.contains(n)) return n;
    }
    return null;
  }

  /// Saves a new tanod (already shown in the list) and gives it its award number.
  Future<void> addTanod(Tanod t) async {
    if (!live) return;
    final front = t.idFront == null ? null : await compute(compressIdPhoto, t.idFront!);
    final back = (front == null || t.idBack == null) ? null : await compute(compressIdPhoto, t.idBack!);
    final r = await db.addTanod(
      barangayPsgc: barangayId,
      firstName: t.first,
      middleInitial: t.middle,
      lastName: t.last,
      address: t.scannedAddress,
      idFront: front,
      idBack: back,
    );
    t
      ..id = r.tanodId
      ..awardNumber = r.awardNumber;
    usedNumbers.add(r.awardNumber);
    // The live list may already have this tanod as a second copy: keep ours
    rec.tanods.removeWhere((x) => x.id == r.tanodId && !identical(x, t));
    _saveExtras(t);
    _changed();
  }

  /// Name or spelling-check changes.
  Future<void> updateTanod(Tanod t) async {
    if (!live || t.id == null) return;
    await db.updateTanodInfo(t.id!, firstName: t.first, middleInitial: t.middle, lastName: t.last);
    _saveExtras(t);
  }

  /// Removes a tanod. Its award number is freed for the next tanod added.
  Future<void> removeTanod(Tanod t) async {
    if (!live || t.id == null) return;
    final n = await db.replaceTanod(t.id!);
    usedNumbers.remove(n);
  }

  /// New or retaken ID photos.
  Future<void> saveIdPhotos(Tanod t) async {
    if (!live || t.id == null || t.idFront == null) return;
    final front = await compute(compressIdPhoto, t.idFront!);
    final back = t.idBack == null ? null : await compute(compressIdPhoto, t.idBack!);
    await db.saveIdScan(t.id!, front: front, back: back);
  }

  void _saveExtras(Tanod t) {
    if (t.id == null) return;
    _write(_fs.collection('tanods').doc(t.id).update({'nameChecked': t.confirmed, 'suffix': t.suffix}));
  }

  /// "Prepared by" and Punong Barangay from Documents → Edit.
  Future<void> saveSignatories() async {
    if (!live) return;
    await db.setBarangaySignatories(barangayId, [
      if (rec.captain.trim().isNotEmpty) {'name': rec.captain.trim(), 'position': 'Punong Barangay'},
      if (rec.rep.trim().isNotEmpty) {'name': rec.rep.trim(), 'position': 'Barangay ${rec.position}'.trim()},
    ]);
  }

  /// Photo or file of a signed document (the backup copy).
  /// Saves the signed copy online. Waits for the database to answer, so a
  /// refused or too-big file shows an error instead of failing quietly
  /// (that is how the municipality ended up seeing only the app's file).
  /// With no internet the save is queued and sent when the phone is back online.
  Future<void> uploadSignedCopy(DocKind k,
      {required Uint8List bytes,
      required String fileName,
      required bool isPdf,
      required String via,
      required int version,
      String? check,
      bool checkOk = true}) async {
    if (!live) return;
    var data = isPdf ? bytes : await compute(compressPagePhoto, bytes);
    // A big PDF (scans, many ID photos) is redrawn smaller so it fits
    if (isPdf && data.length > 900 * 1024) data = await shrinkPdf(data);
    if (data.length > 900 * 1024) {
      throw StateError('This file is too big to save online (${data.length ~/ 1024} KB, the limit is 900 KB). '
          'Take a photo instead, or make the PDF smaller.');
    }
    final save = _copyRef(k).set({
      'year': year,
      'barangayId': barangayId,
      'municipalityId': municipalityId,
      'kind': k.name,
      'fileName': fileName,
      'isPdf': isPdf,
      'via': via,
      'data': Blob(data),
      'version': version,
      'outdated': false,
      'correction': false,
      'autoCheck': check,
      'autoCheckOk': checkOk,
      'uploadedAt': FieldValue.serverTimestamp(),
    });
    _track(save);
    await save.timeout(const Duration(seconds: 20), onTimeout: () {}); // offline: stays queued
  }

  /// Before sharing: every signed copy must really be in the database, so the
  /// municipality opens the signed papers and not the app's ready-to-print files.
  /// A copy that is missing there is sent again from this phone.
  Future<void> _ensureSignedCopiesOnline() async {
    for (final k in kBarangayDocs) {
      final f = rec.files[k]!;
      if (!f.uploaded) {
        throw StateError('Upload the signed ${k.title} first.');
      }
      Map<String, dynamic>? m;
      try {
        final s = await _copyRef(k).get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 15));
        m = s.data();
      } catch (_) {
        throw StateError('No internet connection. Connect to the internet and press Share again, '
            'so the municipality receives your signed copies.');
      }
      final online = m != null && m['data'] is Blob && (m['version'] as num?)?.toInt() == f.version;
      if (online) continue;
      final bytes = f.bytes;
      if (bytes == null) {
        throw StateError('The signed ${k.title} did not reach the database. Please upload it again.');
      }
      await uploadSignedCopy(k,
          bytes: bytes,
          fileName: f.fileName ?? '${k.title}.${f.isPdf ? 'pdf' : 'jpg'}',
          isPdf: f.isPdf,
          via: f.via,
          version: f.version,
          check: f.checkNote,
          checkOk: f.checkOk);
      final again = await _copyRef(k).get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 15));
      if (again.data()?['data'] is! Blob) {
        throw StateError('The signed ${k.title} could not be saved online. Please upload it again.');
      }
    }
  }

  /// The tanod list changed after signing: uploaded copies no longer match.
  void markCopiesOutdated() {
    if (!live) return;
    for (final f in rec.files.values) {
      if (f.uploaded) _write(_copyRef(f.kind).update({'outdated': true}));
    }
  }

  /// Barangay → municipality. The signed ID copy sheet counts as every tanod's
  /// signed ID (the team's submit check needs documents.idSigned on each tanod).
  Future<void> submit() async {
    if (!live) return;
    await _ensureSignedCopiesOnline(); // the signed papers, not the generated files
    for (final t in rec.tanods) {
      if (t.id != null) await db.setChecklist(t.id!, idSigned: true);
    }
    await db.submitBarangay(barangayId);
  }

  Future<void> sendMessage(String text) async {
    if (!live) return;
    await db.messages.send(threadId: threadId, text: text);
  }

  void markRead() {
    if (!live) return;
    db.messages.markRead(threadId).catchError((Object _) {});
  }

  // ======================= MUNICIPAL =======================

  bool get isMunicipal => live && role == 'municipal';

  /// PSGC of the barangay whose checking page (and chat) is open right now,
  /// so no "new message" pop-up is shown for a chat already on screen.
  String? viewingBarangay;

  /// This year's status of the municipality: in_progress, submitted, returned, verified
  String municipalStatus = Status.inProgress;

  final Map<String, BrgyRecord> _byId = {};
  final Map<String, int> _blockStart = {};
  final Set<String> _chatThreads = {};

  /// Barangay record for a PSGC code (made the first time it is seen).
  BrgyRecord _brgy(String id) => _byId.putIfAbsent(id, () {
        final b = BrgyRecord(
          name: '…',
          rep: '—',
          position: '',
          captain: '',
          quota: 0,
          tanods: [],
          files: filesWith(0),
          status: BrgyStatus.notStarted,
          updated: '—',
        )..id = id;
        store.brgys.add(b);
        return b;
      });

  Future<void> _openMunicipal() async {
    await _stop();
    final y = await db.getCurrentYear();
    if (y == null) throw StateError('No incentive year has been started yet. Ask OPPDC (admin) to start one.');
    year = y;
    final mc = await db.getMunicipalCompliance(municipalityId, year: y);

    _saveDemoValues();
    kYear = y;
    kMunicipality = '${mc['municipalityName'] ?? kMunicipality}';
    final name = '${profile!['displayName'] ?? 'Municipal reviewer'}';
    kReviewerName = name;
    kReviewerFirstName = name.split(' ').first;
    try {
      final amount = (await db.getYear(y))?['amountPerTanod'];
      if (amount is num) kAmountEach = amount.toInt();
    } catch (_) {}

    _byId.clear();
    _blockStart.clear();
    _chatThreads.clear();
    store
      ..brgys = []
      ..requests = [] // accounts are made by OPPDC in Firebase, not requested here
      ..sentToOppdc = false
      ..sentOn = null;
    _applyMunicipal(mc);

    final fs = _fs;
    _subs.add(fs.collection('municipalCompliance').doc(DatabaseService.complianceId(y, municipalityId)).snapshots().listen((s) {
      if (s.exists) _applyMunicipal(s.data()!);
      _changed();
    }, onError: _onStreamError));
    _subs.add(fs
        .collection('barangayCompliance')
        .where('year', isEqualTo: y)
        .where('municipalityId', isEqualTo: municipalityId)
        .snapshots()
        .listen(_applyBarangays, onError: _onStreamError));
    _subs.add(fs
        .collection('tanods')
        .where('municipalityId', isEqualTo: municipalityId)
        .where('year', isEqualTo: y)
        .where('status', isEqualTo: 'active')
        .orderBy('awardNumber')
        .snapshots()
        .listen(_applyMunicipalTanods, onError: _onStreamError));
    _subs.add(db.messages.watchMunicipalityThreads(municipalityId).listen(_applyThreads, onError: _onStreamError));
    _subs.add(fs
        .collection('signedCopies')
        .where('municipalityId', isEqualTo: municipalityId)
        .where('year', isEqualTo: y)
        .snapshots()
        .listen(_applyMunicipalCopies, onError: _onStreamError));
  }

  void _applyMunicipal(Map<String, dynamic> mc) {
    municipalStatus = '${mc['status'] ?? Status.inProgress}';
    store.sentToOppdc = municipalStatus == Status.submitted || municipalStatus == Status.verified;
    store.sentOn = store.sentToOppdc ? timeLabel(mc['submittedAt']) : null;
    // Payroll signatories the municipality edited
    final officials = mc['payrollOfficials'];
    if (officials is Map) {
      for (final e in officials.entries) {
        payrollOfficials['${e.key}'] = '${e.value ?? ''}';
      }
    }
    _refreshStatuses();
  }

  /// Saves the Payroll signatories (municipalCompliance/{year_psgc}.payrollOfficials).
  Future<void> savePayrollOfficials(Map<String, String> officials) async {
    if (!isMunicipal) return;
    await _fs
        .collection('municipalCompliance')
        .doc(DatabaseService.complianceId(year, municipalityId))
        .set({'payrollOfficials': officials}, SetOptions(merge: true))
        .timeout(const Duration(seconds: 20), onTimeout: () {});
  }

  void _applyBarangays(QuerySnapshot<Map<String, dynamic>> snap) {
    for (final d in snap.docs) {
      final m = d.data();
      final id = '${m['barangayId'] ?? d.id.split('_').last}';
      final b = _brgy(id);
      b
        ..name = '${m['barangayName'] ?? b.name}'
        ..quota = (m['tanodLimit'] as num?)?.toInt() ?? b.quota
        ..cloudStatus = '${m['status'] ?? Status.inProgress}';
      _blockStart[id] = (m['awardStart'] as num?)?.toInt() ?? 0;
      final submitted = m['submittedAt'] ?? m['reviewedAt'];
      if (submitted != null && b.updated == '—') b.updated = timeLabel(submitted);
      for (final sig in (m['signatories'] as List?) ?? []) {
        if (sig is! Map) continue;
        final n = '${sig['name'] ?? ''}'.trim();
        final p = '${sig['position'] ?? ''}'.trim();
        if (n.isEmpty) continue;
        if (p.toLowerCase().contains('punong')) {
          b.captain = n;
        } else {
          b
            ..rep = n
            ..position = p.replaceFirst(RegExp(r'^barangay\s+', caseSensitive: false), '');
        }
      }
    }
    // Same order as the award numbers (alphabetical blocks)
    store.brgys.sort((a, b) => (_blockStart[a.id] ?? 0).compareTo(_blockStart[b.id] ?? 0));
    _refreshStatuses();
    _changed();
  }

  /// Firebase status → the app's stages.
  void _refreshStatuses() {
    final withOppdc = store.sentToOppdc;
    for (final b in store.brgys) {
      b.status = switch (b.cloudStatus) {
        Status.submitted => BrgyStatus.submitted,
        Status.returned => BrgyStatus.corrections,
        Status.verified => withOppdc ? BrgyStatus.sentToOppdc : BrgyStatus.checked,
        _ => b.tanods.isEmpty ? BrgyStatus.notStarted : BrgyStatus.preparing,
      };
    }
  }

  void _applyMunicipalTanods(QuerySnapshot<Map<String, dynamic>> snap) {
    final groups = <String, List<Tanod>>{};
    for (final d in snap.docs) {
      final m = d.data();
      final t = Tanod('${m['firstName'] ?? ''}', '${m['middleInitial'] ?? ''}', '${m['lastName'] ?? ''}', kIdType,
          confirmed: m['nameChecked'] is bool ? m['nameChecked'] as bool : true,
          suffix: '${m['suffix'] ?? ''}',
          scannedAddress: '${m['address'] ?? ''}')
        ..id = d.id
        ..awardNumber = (m['awardNumber'] as num?)?.toInt();
      groups.putIfAbsent('${m['barangayId']}', () => []).add(t);
    }
    for (final b in store.brgys) {
      b.tanods
        ..clear()
        ..addAll(groups[b.id] ?? const []);
    }
    for (final e in groups.entries) {
      if (!_byId.containsKey(e.key)) _brgy(e.key).tanods.addAll(e.value);
    }
    _refreshStatuses();
    _changed();
  }

  void _applyThreads(QuerySnapshot<Map<String, dynamic>> snap) {
    for (final d in snap.docs) {
      final m = d.data();
      if (m['type'] != 'barangay' || m['barangayId'] == null) continue;
      final b = _brgy('${m['barangayId']}');
      final unread = m['unread'];
      b.unreadMuni = unread is Map ? ((unread['municipal'] as num?)?.toInt() ?? 0) : 0;
      if (m['lastAt'] != null) b.updated = timeLabel(m['lastAt']);
      // Live chat for each barangay (started once)
      if (_chatThreads.add(d.id)) {
        _subs.add(db.messages.watchMessages(d.id, limit: 200).listen((s) {
          _fillChat(b, s);
          _changed();
        }, onError: _onStreamError));
      }
    }
    _changed();
  }

  void _applyMunicipalCopies(QuerySnapshot<Map<String, dynamic>> snap) {
    final seen = <String>{};
    for (final d in snap.docs) {
      final m = d.data();
      final k = _docKind(m['kind']);
      final id = m['barangayId'];
      if (k == null || id == null) continue;
      final b = _brgy('$id');
      _fillCopy(b, b.files[k]!, m);
      seen.add('${id}_${k.name}');
    }
    for (final b in store.brgys) {
      for (final f in b.files.values) {
        if (!seen.contains('${b.id}_${f.kind.name}')) _fillCopy(b, f, null);
      }
      _retag(b);
    }
    _changed();
  }

  // ---- municipal actions ----

  /// Message to a barangay. With [doc], it asks for a corrected copy of that
  /// document and returns the paper set to the barangay (status "returned").
  Future<void> messageBarangay(BrgyRecord b, String text, DocKind? doc) async {
    if (!isMunicipal || b.id == null) return;
    final clean = text.trim();
    if (doc != null) {
      // Mark the document first, so the message is tagged with it when it arrives
      _write(_copyRefFor(b.id!, doc).set({
        'year': year,
        'barangayId': b.id,
        'municipalityId': municipalityId,
        'kind': doc.name,
        'correction': true,
        'paperOk': false,
        'correctionNote': clean,
      }, SetOptions(merge: true)));
      if (b.cloudStatus == Status.submitted || b.cloudStatus == Status.verified) {
        _write(_fs.collection('barangayCompliance').doc(DatabaseService.complianceId(year, b.id!)).update({
          'status': Status.returned,
          'reviewedAt': FieldValue.serverTimestamp(),
          'reviewNote': clean,
        }));
      }
    }
    await db.messages.send(threadId: MessageService.barangayThreadId(b.id!), text: clean);
  }

  /// "Paper is correct" / "Undo" on one document.
  void setPaperOk(BrgyRecord b, DocKind k, bool ok) {
    if (!isMunicipal || b.id == null) return;
    _write(_copyRefFor(b.id!, k).set({
      'year': year,
      'barangayId': b.id,
      'municipalityId': municipalityId,
      'kind': k.name,
      'paperOk': ok,
    }, SetOptions(merge: true)));
  }

  /// "Mark as checked" → verified.
  Future<void> markChecked(BrgyRecord b) async {
    if (!isMunicipal || b.id == null) return;
    await db.reviewBarangay(barangayPsgc: b.id!, approve: true);
  }

  Future<void> remind(List<BrgyRecord> list, String text) async {
    if (!isMunicipal) return;
    for (final b in list) {
      if (b.id != null) await db.sendReminderToBarangay(b.id!, text);
    }
  }

  /// Every barangay verified → submit the municipality to OPPDC.
  Future<void> submitToOppdc() async {
    if (!isMunicipal) return;
    await db.submitMunicipality(municipalityId);
  }

  /// Opening a barangay's messages clears the municipality's badge.
  void markReadFor(BrgyRecord b) {
    if (!isMunicipal || b.id == null) return;
    db.messages.markRead(MessageService.barangayThreadId(b.id!)).catchError((Object _) {});
  }

  // ======================= HELPERS =======================

  DocumentReference<Map<String, dynamic>> _copyRef(DocKind k) => _copyRefFor(barangayId, k);

  DocumentReference<Map<String, dynamic>> _copyRefFor(String brgyPsgc, DocKind k) =>
      _fs.collection('signedCopies').doc('${year}_${brgyPsgc}_${k.name}');

  void _changed() => changes.value++;

  void _error(String m) => errors.value = m;

  void _onStreamError(Object e) => _error(friendly(e));

  /// SYNC CHIP: saves sent to Firebase but not confirmed by the server yet
  /// (offline they stay here until the internet is back).
  final pendingWrites = ValueNotifier<int>(0);

  void _track(Future<void> f) {
    pendingWrites.value++;
    f.then((_) {}, onError: (Object _) {}).whenComplete(() {
      if (pendingWrites.value > 0) pendingWrites.value--;
    });
  }

  void _write(Future<void> f) {
    _track(f);
    unawaited(f.catchError((Object e) => _error(friendly(e))));
  }

  static DocKind? _docKind(dynamic name) {
    for (final k in DocKind.values) {
      if (k.name == name) return k;
    }
    return null;
  }

  /// Readable text for any Firebase / database error.
  static String friendly(Object e) {
    if (e is String) return e;
    if (e is FirebaseAuthException) {
      return switch (e.code) {
        'invalid-credential' || 'wrong-password' || 'user-not-found' || 'invalid-email' =>
          tr('Wrong login ID or password.', 'Mali ang login ID o password.', 'Sala ang login ID ukon password.'),
        'network-request-failed' => tr('No internet. Connect and try again.', 'Walang internet. Kumonekta at subukan ulit.',
            'Wala sang internet. Mag-connect kag tilawi liwat.'),
        'too-many-requests' => tr('Too many tries. Wait a minute, then try again.', 'Sobrang dami ng subok. Maghintay ng isang minuto.',
            'Sobra na kadamo nga tilaw. Maghulat sing isa ka minuto.'),
        _ => e.message ?? e.code,
      };
    }
    if (e is FirebaseException) {
      return switch (e.code) {
        'permission-denied' => tr('Firebase didn’t allow this (security rules). Ask the database admin.',
            'Hindi ito pinayagan ng Firebase (security rules).', 'Wala ini gintugot sang Firebase (security rules).'),
        'unavailable' => tr('No internet right now. It will be sent when you’re back online.',
            'Walang internet. Ipapadala ito pagbalik ng internet.', 'Wala sang internet. Ipadala ini pagbalik sang internet.'),
        'failed-precondition' => tr('The database needs an index. Open the link in the debug console once.',
            'Kailangan ng index sa database.', 'Kinahanglan sang index sa database.'),
        _ => e.message ?? e.code,
      };
    }
    if (e is StateError) return e.message;
    if (e is ArgumentError) return '${e.message}';
    return '$e';
  }
}

/// "Today 6:09 PM", or "Oct 15 6:09 PM" for other days.
String timeLabel(dynamic ts) {
  if (ts is! Timestamp) return nowLabel(); // still being saved
  final t = ts.toDate();
  final now = DateTime.now();
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final clock = '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  final today = t.year == now.year && t.month == now.month && t.day == now.day;
  return today ? '${tr('Today', 'Ngayon', 'Subong')} $clock' : '${months[t.month - 1]} ${t.day} $clock';
}

/// ID card photo → small JPG (a Firestore record holds at most 1 MB for both sides).
/// Makes a big PDF smaller: each page is redrawn as a JPG picture
/// (tries sharper first, then smaller until it fits under ~880 KB).
Future<Uint8List> shrinkPdf(Uint8List pdf) async {
  for (final (dpi, quality) in const [(120.0, 65), (96.0, 55), (72.0, 45)]) {
    try {
      final doc = pw.Document(creator: 'Gawad signed copy');
      await for (final page in Printing.raster(pdf, dpi: dpi)) {
        final png = await page.toPng();
        final jpg = await compute(_toJpg, (png, quality));
        final w = page.width * 72 / dpi, h = page.height * 72 / dpi; // points
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat(w, h),
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Image(pw.MemoryImage(jpg), fit: pw.BoxFit.fill),
        ));
      }
      final out = await doc.save();
      if (out.length <= 880 * 1024) return out;
    } catch (e) {
      debugPrint('shrinkPdf: $e');
      break;
    }
  }
  return pdf; // couldn't make it small enough: the size check reports it
}

Uint8List _toJpg((Uint8List, int) job) {
  final image = img.decodeImage(job.$1);
  return image == null ? job.$1 : Uint8List.fromList(img.encodeJpg(image, quality: job.$2));
}

Uint8List compressIdPhoto(Uint8List bytes) => _shrink(bytes, maxSide: 1000, quality: 75);

/// Photo of a signed paper → JPG under ~900 KB.
Uint8List compressPagePhoto(Uint8List bytes) {
  var out = _shrink(bytes, maxSide: 1700, quality: 70);
  if (out.length > 880 * 1024) out = _shrink(bytes, maxSide: 1300, quality: 55);
  return out;
}

Uint8List _shrink(Uint8List bytes, {required int maxSide, required int quality}) {
  final image = img.decodeImage(bytes);
  if (image == null) return bytes;
  final big = image.width > image.height ? image.width : image.height;
  final resized = big > maxSide
      ? (image.width >= image.height ? img.copyResize(image, width: maxSide) : img.copyResize(image, height: maxSide))
      : image;
  return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
}