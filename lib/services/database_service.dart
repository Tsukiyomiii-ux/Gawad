import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'message_service.dart';

/// Status values for barangay and municipal compliance.
class Status {
  static const String inProgress = 'in_progress';
  static const String submitted = 'submitted';
  static const String returned = 'returned';
  static const String verified = 'verified';

  /// Records can only be edited while in one of these statuses
  static const List<String> editable = [inProgress, returned];

  static const List<String> all = [inProgress, submitted, returned, verified];
}

/// One barangay to load, e.g. (psgc: '0603036018', name: 'Ungka I', tanodLimit: 9)
typedef BarangaySeed = ({String psgc, String name, int tanodLimit});

/// What addTanod gives back
typedef AddTanodResult = ({String tanodId, int awardNumber});

/// All Gawad database operations.
///
/// IDs: municipalities and barangays use their official 10-digit PSGC code (as text).
///
/// DATA THAT STAYS THE SAME EVERY YEAR
///   users/{uid}                  { loginId, role, displayName, municipalityId, barangayId }
///   municipalities/{psgc}        { psgc, name }
///   barangays/{psgc}             { psgc, name, municipalityId, municipalityName, tanodLimit,
///                                  punongBarangay, limitHistory [ {limit, note, at} ] }
///
/// DATA PER YEAR
///   settings/current             { year }   <- which year is open
///   years/{year}                 { year, amountPerTanod, eoNumber, status: open | closed }
///   barangayCompliance/{year_psgc}   { year, barangayId, barangayName, municipalityId,
///                                      municipalityName, tanodLimit, awardStart, awardEnd,
///                                      usedNumbers, status, signatories, submittedAt,
///                                      reviewedAt, reviewNote }
///   municipalCompliance/{year_psgc}  { year, municipalityId, municipalityName, status,
///                                      signatories, submittedAt, reviewedAt, reviewNote }
///   tanods/{autoId}              { firstName, middleInitial, lastName, address, awardNumber,
///                                  year, status: active | replaced, barangayId, barangayName,
///                                  municipalityId, municipality (name), hasIdScan,
///                                  documents { idSigned, payrollSigned }, createdAt }
///   idScans/{tanodId}            { front, back (compressed image bytes), barangayId,
///                                  municipalityId, year }
///
/// MESSAGES: see message_service.dart
///
/// STATUS FLOW
///   Barangay:     in_progress -> submitted -> verified, or returned (-> submitted again)
///   Municipality: in_progress -> submitted -> verified, or returned (-> submitted again)
///
/// OFFLINE: everything a barangay does (adding tanods, checklist, submitting, messages)
/// is saved on the phone first and sent when internet returns. Admin setup needs internet.
/// Only ONE phone per barangay should add tanods, so award numbers can't clash offline.
class DatabaseService {
  DatabaseService({this.onSyncError}) : messages = MessageService(onSyncError: onSyncError);

  /// Called if a save made on the phone is later rejected by the server
  final void Function(Object error)? onSyncError;

  final MessageService messages;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _settings => _db.collection('settings');
  CollectionReference<Map<String, dynamic>> get _years => _db.collection('years');
  CollectionReference<Map<String, dynamic>> get _municipalities => _db.collection('municipalities');
  CollectionReference<Map<String, dynamic>> get _barangays => _db.collection('barangays');
  CollectionReference<Map<String, dynamic>> get _barangayCompliance =>
      _db.collection('barangayCompliance');
  CollectionReference<Map<String, dynamic>> get _municipalCompliance =>
      _db.collection('municipalCompliance');
  CollectionReference<Map<String, dynamic>> get _tanods => _db.collection('tanods');
  CollectionReference<Map<String, dynamic>> get _idScans => _db.collection('idScans');
  CollectionReference<Map<String, dynamic>> get _threads => _db.collection('threads');

  /// e.g. complianceId(2026, '0603036018') -> '2026_0603036018'
  static String complianceId(int year, String psgc) => '${year}_$psgc';

  // =====================================================================
  // YEARS (admin)
  // =====================================================================

  Future<int?> getCurrentYear() async {
    final snap = await _settings.doc('current').get();
    final year = snap.data()?['year'];
    return year == null ? null : _toInt(year);
  }

  Future<Map<String, dynamic>?> getYear(int year) async {
    final snap = await _years.doc('$year').get();
    return snap.exists ? _withId(snap) : null;
  }

  /// All years, newest first (for the analytics year picker)
  Future<List<Map<String, dynamic>>> getYears() async {
    final snap = await _years.get();
    final list = snap.docs.map(_withId).toList();
    list.sort((a, b) => _toInt(b['year']).compareTo(_toInt(a['year'])));
    return list;
  }

  /// Opens a new incentive year: closes the previous one, then gives every
  /// barangay its block of award numbers using its current tanod limit.
  Future<void> startYear({
    required int year,
    required num amountPerTanod,
    String eoNumber = '',
  }) async {
    final current = await getCurrentYear();
    if (current != null && year <= current) {
      throw StateError('Year $year must be after the current year $current.');
    }
    if (amountPerTanod <= 0) throw ArgumentError('Amount per tanod must be more than 0.');

    final batch = _db.batch();
    if (current != null) {
      batch.set(
        _years.doc('$current'),
        {'status': 'closed', 'closedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    }
    batch.set(_years.doc('$year'), {
      'year': year,
      'amountPerTanod': amountPerTanod,
      'eoNumber': eoNumber.trim(),
      'status': 'open',
      'startedAt': FieldValue.serverTimestamp(),
    });
    batch.set(_settings.doc('current'), {'year': year});
    await batch.commit();

    final muns = await _municipalities.get();
    for (final m in muns.docs) {
      await _syncYearForMunicipality(year, m.id);
    }
  }

  /// Correct the amount or Executive Order number of a year
  Future<void> updateYear(int year, {num? amountPerTanod, String? eoNumber}) async {
    await _years.doc('$year').update({
      if (amountPerTanod != null) 'amountPerTanod': amountPerTanod,
      if (eoNumber != null) 'eoNumber': eoNumber.trim(),
    });
  }

  // =====================================================================
  // MUNICIPALITIES & BARANGAYS (admin)
  // =====================================================================

  Future<void> addMunicipality({required String psgc, required String name}) async {
    _checkPsgc(psgc, 'Municipality code');
    await _createMunicipality(psgc, name);
    final year = await getCurrentYear();
    if (year != null) await _syncYearForMunicipality(year, psgc);
  }

  /// Adds one barangay. Returns true if it got award numbers for the current year
  /// right away, or false if numbers are already in use in its municipality
  /// (then it joins at the start of next year).
  Future<bool> addBarangay({
    required String psgc,
    required String name,
    required String municipalityPsgc,
    required int tanodLimit,
    String punongBarangay = '',
  }) async {
    await _createBarangay(
      psgc: psgc,
      name: name,
      municipalityPsgc: municipalityPsgc,
      tanodLimit: tanodLimit,
      punongBarangay: punongBarangay,
    );
    final year = await getCurrentYear();
    if (year == null) return true;
    return _syncYearForMunicipality(year, municipalityPsgc);
  }

  /// Loads a municipality and all its barangays at once.
  /// Barangays that already exist are skipped, so it is safe to run again.
  Future<void> loadMunicipality({
    required String psgc,
    required String name,
    required List<BarangaySeed> barangays,
  }) async {
    _checkPsgc(psgc, 'Municipality code');
    await _createMunicipality(psgc, name);

    for (final b in barangays) {
      final exists = (await _barangays.doc(b.psgc).get()).exists;
      if (!exists) {
        await _createBarangay(
          psgc: b.psgc,
          name: b.name,
          municipalityPsgc: psgc,
          tanodLimit: b.tanodLimit,
        );
      }
    }

    final year = await getCurrentYear();
    if (year != null) await _syncYearForMunicipality(year, psgc);
  }

  /// Changes a barangay's fixed tanod limit (e.g. after an amended ordinance).
  /// Returns true if it applies to the current year right away, or false if award
  /// numbers are already in use in that municipality (then it starts next year,
  /// so nobody's award number shifts).
  Future<bool> amendTanodLimit({
    required String barangayPsgc,
    required int newLimit,
    required String note,
  }) async {
    _checkLimit(newLimit);
    if (note.trim().isEmpty) {
      throw ArgumentError('Write a short reason for the amendment, e.g. the ordinance number.');
    }

    final ref = _barangays.doc(barangayPsgc);
    final snap = await ref.get();
    if (!snap.exists) throw StateError('Barangay $barangayPsgc not found.');

    await ref.update({
      'tanodLimit': newLimit,
      'limitHistory': FieldValue.arrayUnion([
        {'limit': newLimit, 'note': note.trim(), 'at': Timestamp.now()},
      ]),
    });

    final year = await getCurrentYear();
    if (year == null) return true;
    return _syncYearForMunicipality(year, snap.data()!['municipalityId'] as String);
  }

  Future<void> updateBarangayInfo(String barangayPsgc, {String? name, String? punongBarangay}) =>
      _barangays.doc(barangayPsgc).update({
        if (name != null) 'name': name.trim(),
        if (punongBarangay != null) 'punongBarangay': punongBarangay.trim(),
      });

  Future<List<Map<String, dynamic>>> getMunicipalities() async {
    final snap = await _municipalities.get();
    final list = snap.docs.map(_withId).toList();
    list.sort((a, b) => _naturalCompare(a['name'], b['name']));
    return list;
  }

  /// A barangay's permanent info (name, tanod limit, limit history)
  Future<Map<String, dynamic>?> getBarangay(String barangayPsgc) async {
    final snap = await _barangays.doc(barangayPsgc).get();
    return snap.exists ? _withId(snap) : null;
  }

  /// All barangays of a municipality, alphabetical (permanent info)
  Future<List<Map<String, dynamic>>> getBarangaysOf(String municipalityPsgc) async {
    final snap = await _barangays.where('municipalityId', isEqualTo: municipalityPsgc).get();
    final list = snap.docs.map(_withId).toList();
    list.sort((a, b) => _naturalCompare(a['name'], b['name']));
    return list;
  }

  // =====================================================================
  // COMPLIANCE RECORDS (this year's status of a barangay / municipality)
  // =====================================================================

  Future<Map<String, dynamic>> getBarangayCompliance(String barangayPsgc, {int? year}) async {
    final y = year ?? await _requireYear();
    final snap = await _barangayCompliance.doc(complianceId(y, barangayPsgc)).get();
    if (!snap.exists) throw StateError('Barangay $barangayPsgc has no record for $y.');
    return _withId(snap);
  }

  Future<Map<String, dynamic>> getMunicipalCompliance(String municipalityPsgc, {int? year}) async {
    final y = year ?? await _requireYear();
    final snap = await _municipalCompliance.doc(complianceId(y, municipalityPsgc)).get();
    if (!snap.exists) throw StateError('Municipality $municipalityPsgc has no record for $y.');
    return _withId(snap);
  }

  /// Live status of one barangay (barangay dashboard)
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchBarangayCompliance(
          String barangayPsgc, int year) =>
      _barangayCompliance.doc(complianceId(year, barangayPsgc)).snapshots();

  // =====================================================================
  // TANODS (barangay)
  // =====================================================================

  /// Adds a tanod with the lowest free award number in the barangay's block.
  /// Pass the compressed ID images from the scanner (front required if any).
  /// Works offline: the save is queued and sent when internet returns.
  Future<AddTanodResult> addTanod({
    required String barangayPsgc,
    required String firstName,
    String middleInitial = '',
    required String lastName,
    String address = '',
    Uint8List? idFront,
    Uint8List? idBack,
  }) async {
    if (firstName.trim().isEmpty || lastName.trim().isEmpty) {
      throw ArgumentError('First name and last name are required.');
    }
    if (idFront == null && idBack != null) {
      throw ArgumentError('The back of the ID was given without the front.');
    }
    if (idFront != null) _checkScanSize(idFront, idBack);

    final bc = await getBarangayCompliance(barangayPsgc);
    _ensureEditable(bc, 'add tanods');

    final start = _toInt(bc['awardStart']);
    final end = _toInt(bc['awardEnd']);
    final used = _intList(bc['usedNumbers']).toSet();

    int? number;
    for (var n = start; n <= end; n++) {
      if (!used.contains(n)) {
        number = n;
        break;
      }
    }
    if (number == null) {
      throw StateError('${bc['barangayName']} has reached its limit of ${bc['tanodLimit']} tanods.');
    }

    final year = _toInt(bc['year']);
    final tanodRef = _tanods.doc();
    final batch = _db.batch();

    batch.set(tanodRef, {
      'firstName': firstName.trim(),
      'middleInitial': middleInitial.trim(),
      'lastName': lastName.trim(),
      'address': address.trim(),
      'awardNumber': number, // always an int
      'year': year,
      'status': 'active',
      'barangayId': barangayPsgc,
      'barangayName': bc['barangayName'],
      'municipalityId': bc['municipalityId'],
      'municipality': bc['municipalityName'], // municipality name (used by the admin dashboard)
      'hasIdScan': idFront != null,
      'documents': {'idSigned': false, 'payrollSigned': false},
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_barangayCompliance.doc(bc['id'] as String), {
      'usedNumbers': FieldValue.arrayUnion([number]),
    });
    if (idFront != null) {
      batch.set(_idScans.doc(tanodRef.id), _scanData(bc, idFront, idBack));
    }

    _commit(batch.commit());
    return (tanodId: tanodRef.id, awardNumber: number);
  }

  /// Fix the name or address after saving (e.g. the scanner misread it)
  Future<void> updateTanodInfo(
    String tanodId, {
    String? firstName,
    String? middleInitial,
    String? lastName,
    String? address,
  }) async {
    final t = await _getTanod(tanodId);
    await _ensureTanodEditable(t, 'edit tanods');
    if ((firstName != null && firstName.trim().isEmpty) ||
        (lastName != null && lastName.trim().isEmpty)) {
      throw ArgumentError('First name and last name cannot be empty.');
    }
    _commit(_tanods.doc(tanodId).update({
      if (firstName != null) 'firstName': firstName.trim(),
      if (middleInitial != null) 'middleInitial': middleInitial.trim(),
      if (lastName != null) 'lastName': lastName.trim(),
      if (address != null) 'address': address.trim(),
    }));
  }

  /// Checklist: idSigned = printed ID copy signed 3 times.
  /// payrollSigned can still be ticked after submitting (signed upon release).
  Future<void> setChecklist(String tanodId, {bool? idSigned, bool? payrollSigned}) async {
    if (idSigned == null && payrollSigned == null) return;
    final t = await _getTanod(tanodId);
    if (idSigned != null) await _ensureTanodEditable(t, 'change the ID checklist');
    _commit(_tanods.doc(tanodId).update({
      if (idSigned != null) 'documents.idSigned': idSigned,
      if (payrollSigned != null) 'documents.payrollSigned': payrollSigned,
    }));
  }

  /// Marks a tanod as replaced and frees the award number for the next tanod added.
  /// The record is kept for history. Returns the freed award number.
  Future<int> replaceTanod(String tanodId) async {
    final t = await _getTanod(tanodId);
    if (t['status'] != 'active') throw StateError('This tanod is already ${t['status']}.');
    final bc = await _ensureTanodEditable(t, 'replace tanods');

    final number = _toInt(t['awardNumber']);
    final batch = _db.batch();
    batch.update(_tanods.doc(tanodId), {
      'status': 'replaced',
      'replacedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_barangayCompliance.doc(bc['id'] as String), {
      'usedNumbers': FieldValue.arrayRemove([number]),
    });
    _commit(batch.commit());
    return number;
  }

  /// Saves or replaces a tanod's ID scan (compressed images)
  Future<void> saveIdScan(String tanodId, {required Uint8List front, Uint8List? back}) async {
    _checkScanSize(front, back);
    final t = await _getTanod(tanodId);
    final bc = await _ensureTanodEditable(t, 'change ID scans');

    final batch = _db.batch();
    batch.set(_idScans.doc(tanodId), _scanData(bc, front, back));
    batch.update(_tanods.doc(tanodId), {'hasIdScan': true});
    _commit(batch.commit());
  }

  /// The ID images, for making the photocopy PDF. Null if none saved.
  Future<({Uint8List front, Uint8List? back})?> getIdScan(String tanodId) async {
    final snap = await _idScans.doc(tanodId).get();
    if (!snap.exists) return null;
    final data = snap.data()!;
    return (
      front: (data['front'] as Blob).bytes,
      back: (data['back'] as Blob?)?.bytes,
    );
  }

  /// Active tanods of a barangay, by award number
  Future<List<Map<String, dynamic>>> getBarangayTanods(String barangayPsgc, {int? year}) async {
    final y = year ?? await _requireYear();
    final snap = await _activeTanods('barangayId', barangayPsgc, y).get();
    return snap.docs.map(_withId).toList();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchBarangayTanods(String barangayPsgc, int year) =>
      _activeTanods('barangayId', barangayPsgc, year).snapshots();

  /// Active tanods of a whole municipality, by award number
  /// (award numbers follow alphabetical barangays, so this is already grouped)
  Future<List<Map<String, dynamic>>> getMunicipalTanods(String municipalityPsgc, {int? year}) async {
    final y = year ?? await _requireYear();
    final snap = await _activeTanods('municipalityId', municipalityPsgc, y).get();
    return snap.docs.map(_withId).toList();
  }

  // =====================================================================
  // SUBMITTING & REVIEWING
  // =====================================================================

  /// Signatories are typed in manually, e.g.
  /// [{'name': 'Juan Cruz', 'position': 'Punong Barangay'}]
  Future<void> setBarangaySignatories(
      String barangayPsgc, List<Map<String, String>> signatories) async {
    final bc = await getBarangayCompliance(barangayPsgc);
    _ensureEditable(bc, 'change signatories');
    _commit(_barangayCompliance
        .doc(bc['id'] as String)
        .update({'signatories': _cleanSignatories(signatories)}));
  }

  Future<void> setMunicipalSignatories(
      String municipalityPsgc, List<Map<String, String>> signatories) async {
    final mc = await getMunicipalCompliance(municipalityPsgc);
    _ensureEditable(mc, 'change signatories', who: mc['municipalityName']);
    _commit(_municipalCompliance
        .doc(mc['id'] as String)
        .update({'signatories': _cleanSignatories(signatories)}));
  }

  /// Barangay -> municipality. Needs at least one tanod, and every tanod's
  /// ID copy signed. After this the tanod list is locked until returned.
  Future<void> submitBarangay(String barangayPsgc) async {
    final bc = await getBarangayCompliance(barangayPsgc);
    _ensureEditable(bc, 'submit');

    final tanods = await getBarangayTanods(barangayPsgc, year: _toInt(bc['year']));
    if (tanods.isEmpty) throw StateError('Add at least one tanod before submitting.');

    final unsigned = tanods
        .where((t) => t['documents']?['idSigned'] != true)
        .map((t) => '#${t['awardNumber']}')
        .toList();
    if (unsigned.isNotEmpty) {
      throw StateError('These tanods have no signed ID copy yet: ${unsigned.join(', ')}.');
    }

    _commit(_barangayCompliance.doc(bc['id'] as String).update({
      'status': Status.submitted,
      'submittedAt': FieldValue.serverTimestamp(),
    }));
  }

  /// Municipality reviews a barangay. Returning it unlocks the barangay and
  /// sends the note as a reminder to the barangay's messages.
  Future<void> reviewBarangay({
    required String barangayPsgc,
    required bool approve,
    String note = '',
  }) async {
    final bc = await getBarangayCompliance(barangayPsgc);
    if (bc['status'] != Status.submitted && bc['status'] != Status.verified) {
      throw StateError('${bc['barangayName']} has not submitted yet (status: ${bc['status']}).');
    }
    final mc = await getMunicipalCompliance(bc['municipalityId'] as String, year: _toInt(bc['year']));
    _ensureEditable(mc, 'review barangays', who: mc['municipalityName']);
    if (!approve && note.trim().isEmpty) {
      throw ArgumentError('Write what needs to be fixed when returning a submission.');
    }

    final batch = _db.batch();
    batch.update(_barangayCompliance.doc(bc['id'] as String), {
      'status': approve ? Status.verified : Status.returned,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewNote': note.trim(),
    });
    if (!approve) {
      await messages.addToBatch(
        batch,
        threadId: MessageService.barangayThreadId(barangayPsgc),
        text: 'Returned for correction: ${note.trim()}',
        type: 'reminder',
      );
    }
    _commit(batch.commit());
  }

  /// Municipality -> OPPDC. Every barangay must be verified first.
  Future<void> submitMunicipality(String municipalityPsgc) async {
    final mc = await getMunicipalCompliance(municipalityPsgc);
    _ensureEditable(mc, 'submit', who: mc['municipalityName']);

    final brgys = await getBarangaysProgress(municipalityPsgc, year: _toInt(mc['year']));
    if (brgys.isEmpty) throw StateError('This municipality has no barangays for this year.');
    final notDone = brgys
        .where((b) => b['status'] != Status.verified)
        .map((b) => b['barangayName'])
        .toList();
    if (notDone.isNotEmpty) {
      throw StateError('Not all barangays are verified yet: ${notDone.join(', ')}.');
    }

    _commit(_municipalCompliance.doc(mc['id'] as String).update({
      'status': Status.submitted,
      'submittedAt': FieldValue.serverTimestamp(),
    }));
  }

  /// OPPDC reviews a municipality. Returning it sends the note as a reminder.
  Future<void> reviewMunicipality({
    required String municipalityPsgc,
    required bool approve,
    String note = '',
  }) async {
    final mc = await getMunicipalCompliance(municipalityPsgc);
    if (mc['status'] != Status.submitted && mc['status'] != Status.verified) {
      throw StateError('${mc['municipalityName']} has not submitted yet (status: ${mc['status']}).');
    }
    if (!approve && note.trim().isEmpty) {
      throw ArgumentError('Write what needs to be fixed when returning a submission.');
    }

    final batch = _db.batch();
    batch.update(_municipalCompliance.doc(mc['id'] as String), {
      'status': approve ? Status.verified : Status.returned,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewNote': note.trim(),
    });
    if (!approve) {
      await messages.addToBatch(
        batch,
        threadId: MessageService.municipalThreadId(municipalityPsgc),
        text: 'Returned for correction: ${note.trim()}',
        type: 'reminder',
      );
    }
    _commit(batch.commit());
  }

  /// OPPDC override: set any barangay's status directly (corrections, testing)
  Future<void> adminSetBarangayStatus(String barangayPsgc, String status, {String note = ''}) async {
    if (!Status.all.contains(status)) throw ArgumentError('Unknown status: $status');
    final bc = await getBarangayCompliance(barangayPsgc);
    _commit(_barangayCompliance.doc(bc['id'] as String).update({
      'status': status,
      'reviewNote': note.trim(),
      'reviewedAt': FieldValue.serverTimestamp(),
    }));
  }

  Future<void> sendReminderToBarangay(String barangayPsgc, String text) => messages.send(
      threadId: MessageService.barangayThreadId(barangayPsgc), text: text, type: 'reminder');

  Future<void> sendReminderToMunicipality(String municipalityPsgc, String text) => messages.send(
      threadId: MessageService.municipalThreadId(municipalityPsgc), text: text, type: 'reminder');

  // =====================================================================
  // DASHBOARDS
  // =====================================================================

  /// Barangays of one municipality with this year's status and tanod count
  /// (municipal dashboard, and admin when tapping a municipality)
  Future<List<Map<String, dynamic>>> getBarangaysProgress(String municipalityPsgc, {int? year}) async {
    final y = year ?? await _requireYear();
    final snap = await _barangayCompliance
        .where('year', isEqualTo: y)
        .where('municipalityId', isEqualTo: municipalityPsgc)
        .get();
    final list = snap.docs.map((d) {
      final data = _withId(d);
      return {...data, 'tanodCount': _intList(data['usedNumbers']).length};
    }).toList();
    list.sort((a, b) => _toInt(a['awardStart']).compareTo(_toInt(b['awardStart'])));
    return list;
  }

  /// Every municipality with this year's status and progress (admin dashboard)
  Future<List<Map<String, dynamic>>> getMunicipalitiesProgress({int? year}) async {
    final y = year ?? await _requireYear();
    final mcSnap = await _municipalCompliance.where('year', isEqualTo: y).get();
    final bcSnap = await _barangayCompliance.where('year', isEqualTo: y).get();

    final byMun = <String, List<Map<String, dynamic>>>{};
    for (final d in bcSnap.docs) {
      byMun.putIfAbsent(d.data()['municipalityId'] as String, () => []).add(d.data());
    }

    final list = mcSnap.docs.map((d) {
      final m = _withId(d);
      final brgys = byMun[m['municipalityId']] ?? [];
      int countStatus(String s) => brgys.where((b) => b['status'] == s).length;
      return {
        ...m,
        'barangayCount': brgys.length,
        'verifiedCount': countStatus(Status.verified),
        'submittedCount': countStatus(Status.submitted),
        'returnedCount': countStatus(Status.returned),
        'inProgressCount': countStatus(Status.inProgress),
        'tanodCount': brgys.fold<int>(0, (sum, b) => sum + _intList(b['usedNumbers']).length),
        'tanodLimitTotal': brgys.fold<int>(0, (sum, b) => sum + _toInt(b['tanodLimit'])),
      };
    }).toList();
    list.sort((a, b) => _naturalCompare(a['municipalityName'], b['municipalityName']));
    return list;
  }

  // =====================================================================
  // DATA FOR PRINTING (the app builds the PDFs from these)
  // =====================================================================

  /// Barangay masterlist, payroll and barangay certification
  Future<Map<String, dynamic>> getBarangayDocumentData(String barangayPsgc) async {
    final bc = await getBarangayCompliance(barangayPsgc);
    final year = _toInt(bc['year']);
    final yearInfo = await getYear(year);
    final barangay = await getBarangay(barangayPsgc);
    final amount = (yearInfo?['amountPerTanod'] as num?) ?? 0;
    final rows = (await getBarangayTanods(barangayPsgc, year: year)).map(_tanodRow).toList();

    return {
      'year': year,
      'eoNumber': yearInfo?['eoNumber'] ?? '',
      'barangayName': bc['barangayName'],
      'municipalityName': bc['municipalityName'],
      'punongBarangay': barangay?['punongBarangay'] ?? '',
      'status': bc['status'],
      'signatories': bc['signatories'] ?? [],
      'amountPerTanod': amount,
      'tanodCount': rows.length,
      'totalAmount': amount * rows.length,
      'tanods': rows,
    };
  }

  /// Whole-municipality masterlist and payroll: barangays alphabetical,
  /// tanods by award number inside each barangay
  Future<Map<String, dynamic>> getMunicipalDocumentData(String municipalityPsgc) async {
    final mc = await getMunicipalCompliance(municipalityPsgc);
    final year = _toInt(mc['year']);
    final yearInfo = await getYear(year);
    final amount = (yearInfo?['amountPerTanod'] as num?) ?? 0;
    final brgys = await getBarangaysProgress(municipalityPsgc, year: year);
    final tanods = await getMunicipalTanods(municipalityPsgc, year: year);

    final groups = brgys.map((b) {
      final rows = tanods
          .where((t) => t['barangayId'] == b['barangayId'])
          .map(_tanodRow)
          .toList();
      return {
        'barangayId': b['barangayId'],
        'barangayName': b['barangayName'],
        'status': b['status'],
        'tanods': rows,
        'subtotal': amount * rows.length,
      };
    }).toList();

    return {
      'year': year,
      'eoNumber': yearInfo?['eoNumber'] ?? '',
      'municipalityName': mc['municipalityName'],
      'status': mc['status'],
      'signatories': mc['signatories'] ?? [],
      'amountPerTanod': amount,
      'tanodCount': tanods.length,
      'totalAmount': amount * tanods.length,
      'barangays': groups,
    };
  }

  // =====================================================================
  // ANALYTICS (admin)
  // =====================================================================

  /// Totals for one year: tanods, amount released, statuses, per municipality
  Future<Map<String, dynamic>> getYearSummary(int year) async {
    final yearInfo = await getYear(year);
    final amount = (yearInfo?['amountPerTanod'] as num?) ?? 0;
    final mcSnap = await _municipalCompliance.where('year', isEqualTo: year).get();
    final bcSnap = await _barangayCompliance.where('year', isEqualTo: year).get();

    final barangayStatus = {for (final s in Status.all) s: 0};
    final municipalStatus = {for (final s in Status.all) s: 0};
    final perMun = <String, Map<String, dynamic>>{};
    var tanods = 0;
    var slots = 0;

    for (final d in mcSnap.docs) {
      final m = d.data();
      municipalStatus[m['status'] as String] = (municipalStatus[m['status']] ?? 0) + 1;
      perMun[m['municipalityId'] as String] = {
        'municipalityName': m['municipalityName'],
        'status': m['status'],
        'tanods': 0,
        'slots': 0,
        'barangays': 0,
      };
    }

    for (final d in bcSnap.docs) {
      final b = d.data();
      final count = _intList(b['usedNumbers']).length;
      final limit = _toInt(b['tanodLimit']);
      tanods += count;
      slots += limit;
      barangayStatus[b['status'] as String] = (barangayStatus[b['status']] ?? 0) + 1;
      final m = perMun[b['municipalityId']];
      if (m != null) {
        m['tanods'] = (m['tanods'] as int) + count;
        m['slots'] = (m['slots'] as int) + limit;
        m['barangays'] = (m['barangays'] as int) + 1;
      }
    }

    final perMunicipality = perMun.values.map((m) => {
          ...m,
          'amount': amount * (m['tanods'] as int),
        }).toList()
      ..sort((a, b) => _naturalCompare(a['municipalityName'], b['municipalityName']));

    return {
      'year': year,
      'eoNumber': yearInfo?['eoNumber'] ?? '',
      'amountPerTanod': amount,
      'municipalities': mcSnap.size,
      'barangays': bcSnap.size,
      'tanods': tanods,
      'slots': slots,
      'fillRate': slots == 0 ? 0.0 : tanods / slots,
      'totalAmount': amount * tanods,
      'municipalStatus': municipalStatus,
      'barangayStatus': barangayStatus,
      'perMunicipality': perMunicipality,
    };
  }

  // =====================================================================
  // HELPERS
  // =====================================================================

  /// Creates this year's compliance records for a municipality and gives each
  /// barangay its block of award numbers, alphabetically.
  /// Returns false (and changes no numbers) if any barangay there already has tanods.
  Future<bool> _syncYearForMunicipality(int year, String municipalityPsgc) async {
    final mun = await _municipalities.doc(municipalityPsgc).get();
    if (!mun.exists) throw StateError('Municipality $municipalityPsgc not found.');
    final munName = mun.data()!['name'];
    final batch = _db.batch();

    final mcRef = _municipalCompliance.doc(complianceId(year, municipalityPsgc));
    if (!(await mcRef.get()).exists) {
      batch.set(mcRef, {
        'year': year,
        'municipalityId': municipalityPsgc,
        'municipalityName': munName,
        'status': Status.inProgress,
        'signatories': <Map<String, String>>[],
        'submittedAt': null,
        'reviewedAt': null,
        'reviewNote': '',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    final existing = await _barangayCompliance
        .where('year', isEqualTo: year)
        .where('municipalityId', isEqualTo: municipalityPsgc)
        .get();
    final locked = existing.docs.any((d) => _intList(d.data()['usedNumbers']).isNotEmpty);
    if (locked) {
      await batch.commit();
      return false;
    }

    final existingIds = existing.docs.map((d) => d.id).toSet();
    final brgys = (await _barangays.where('municipalityId', isEqualTo: municipalityPsgc).get())
        .docs
        .toList()
      ..sort((a, b) => _naturalCompare(a.data()['name'], b.data()['name']));

    var next = 1;
    for (final b in brgys) {
      final limit = _toInt(b.data()['tanodLimit']);
      final ref = _barangayCompliance.doc(complianceId(year, b.id));
      final block = {
        'tanodLimit': limit,
        'awardStart': next,
        'awardEnd': next + limit - 1,
        'barangayName': b.data()['name'],
      };
      if (existingIds.contains(ref.id)) {
        batch.update(ref, block);
      } else {
        batch.set(ref, {
          ...block,
          'year': year,
          'barangayId': b.id,
          'municipalityId': municipalityPsgc,
          'municipalityName': munName,
          'usedNumbers': <int>[],
          'status': Status.inProgress,
          'signatories': <Map<String, String>>[],
          'submittedAt': null,
          'reviewedAt': null,
          'reviewNote': '',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      next += limit;
    }
    await batch.commit();
    return true;
  }

  Future<void> _createMunicipality(String psgc, String name) async {
    final batch = _db.batch();
    batch.set(_municipalities.doc(psgc), {'psgc': psgc, 'name': name.trim()}, SetOptions(merge: true));

    final threadRef = _threads.doc(MessageService.municipalThreadId(psgc));
    if (!(await threadRef.get()).exists) {
      batch.set(threadRef, {
        'type': 'municipal',
        'municipalityId': psgc,
        'title': '${name.trim()} - OPPDC',
        'lastMessage': '',
        'lastType': null,
        'lastSenderRole': null,
        'lastAt': null,
        'unread': {'municipal': 0, 'admin': 0},
      });
    }
    await batch.commit();
  }

  Future<void> _createBarangay({
    required String psgc,
    required String name,
    required String municipalityPsgc,
    required int tanodLimit,
    String punongBarangay = '',
  }) async {
    _checkPsgc(psgc, 'Barangay code');
    _checkPsgc(municipalityPsgc, 'Municipality code');
    _checkLimit(tanodLimit);

    final mun = await _municipalities.doc(municipalityPsgc).get();
    if (!mun.exists) throw StateError('Municipality $municipalityPsgc does not exist. Add it first.');
    final ref = _barangays.doc(psgc);
    if ((await ref.get()).exists) {
      throw StateError('Barangay $psgc already exists. Use amendTanodLimit to change its limit.');
    }
    final munName = mun.data()!['name'];

    final batch = _db.batch();
    batch.set(ref, {
      'psgc': psgc,
      'name': name.trim(),
      'municipalityId': municipalityPsgc,
      'municipalityName': munName,
      'tanodLimit': tanodLimit,
      'punongBarangay': punongBarangay.trim(),
      'limitHistory': [
        {'limit': tanodLimit, 'note': 'Initial limit', 'at': Timestamp.now()},
      ],
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(_threads.doc(MessageService.barangayThreadId(psgc)), {
      'type': 'barangay',
      'barangayId': psgc,
      'municipalityId': municipalityPsgc,
      'title': '${name.trim()} - $munName',
      'lastMessage': '',
      'lastType': null,
      'lastSenderRole': null,
      'lastAt': null,
      'unread': {'barangay': 0, 'municipal': 0},
    });
    await batch.commit();
  }

  // Needs composite indexes:
  //   barangayId, year, status, awardNumber      (barangay list)
  //   municipalityId, year, status, awardNumber  (municipal masterlist)
  Query<Map<String, dynamic>> _activeTanods(String field, String code, int year) => _tanods
      .where(field, isEqualTo: code)
      .where('year', isEqualTo: year)
      .where('status', isEqualTo: 'active')
      .orderBy('awardNumber');

  Future<Map<String, dynamic>> _getTanod(String tanodId) async {
    final snap = await _tanods.doc(tanodId).get();
    if (!snap.exists) throw StateError('Tanod not found.');
    return _withId(snap);
  }

  /// Checks the tanod's barangay is still editable; returns its compliance record
  Future<Map<String, dynamic>> _ensureTanodEditable(Map<String, dynamic> tanod, String action) async {
    final current = await _requireYear();
    if (_toInt(tanod['year']) != current) {
      throw StateError('Only tanods from the current year ($current) can be changed.');
    }
    final bc = await getBarangayCompliance(tanod['barangayId'] as String, year: current);
    _ensureEditable(bc, action);
    return bc;
  }

  void _ensureEditable(Map<String, dynamic> record, String action, {Object? who}) {
    if (!Status.editable.contains(record['status'])) {
      throw StateError(
        'Locked: ${who ?? record['barangayName']} is "${record['status']}", '
        'so you can\'t $action now. It unlocks only if it is returned.',
      );
    }
  }

  Map<String, dynamic> _scanData(Map<String, dynamic> bc, Uint8List front, Uint8List? back) => {
        'front': Blob(front),
        'back': back == null ? null : Blob(back),
        'barangayId': bc['barangayId'],
        'municipalityId': bc['municipalityId'],
        'year': _toInt(bc['year']),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// A Firestore document can hold at most 1 MB, so the scanner must compress the images
  void _checkScanSize(Uint8List front, Uint8List? back) {
    final total = front.length + (back?.length ?? 0);
    if (total > 900 * 1024) {
      throw ArgumentError(
        'ID images are too big (${total ~/ 1024} KB). Compress them to under 900 KB in total.',
      );
    }
  }

  List<Map<String, String>> _cleanSignatories(List<Map<String, String>> list) {
    final clean = list
        .map((s) => {'name': (s['name'] ?? '').trim(), 'position': (s['position'] ?? '').trim()})
        .where((s) => s['name']!.isNotEmpty || s['position']!.isNotEmpty)
        .toList();
    if (clean.any((s) => s['name']!.isEmpty || s['position']!.isEmpty)) {
      throw ArgumentError('Each signatory needs both a name and a position.');
    }
    return clean;
  }

  static Map<String, dynamic> _tanodRow(Map<String, dynamic> t) => {
        'id': t['id'],
        'awardNumber': t['awardNumber'],
        'lastName': t['lastName'],
        'firstName': t['firstName'],
        'middleInitial': t['middleInitial'] ?? '',
        'address': t['address'] ?? '',
        'barangayName': t['barangayName'],
        'idSigned': t['documents']?['idSigned'] == true,
        'payrollSigned': t['documents']?['payrollSigned'] == true,
      };

  Future<int> _requireYear() async {
    final year = await getCurrentYear();
    if (year == null) throw StateError('No year started yet. The admin must start a year first.');
    return year;
  }

  /// Saves happen on the phone right away; errors from the server arrive later
  void _commit(Future<void> write) {
    unawaited(write.catchError((Object e) => onSyncError?.call(e)));
  }

  void _checkPsgc(String code, String label) {
    if (!RegExp(r'^\d{10}$').hasMatch(code)) {
      throw ArgumentError('$label must be a 10-digit PSGC code, got "$code".');
    }
  }

  void _checkLimit(int limit) {
    if (limit < 1) throw ArgumentError('Tanod limit must be at least 1.');
  }

  static Map<String, dynamic> _withId(DocumentSnapshot<Map<String, dynamic>> d) =>
      {'id': d.id, ...d.data()!};

  static int _toInt(dynamic v) => (v as num).toInt();

  static List<int> _intList(dynamic v) =>
      ((v as List?) ?? []).map((e) => (e as num).toInt()).toList();

  /// Alphabetical, but numbers compare as numbers ("Ungka 2" before "Ungka 10")
  static int _naturalCompare(dynamic a, dynamic b) {
    final re = RegExp(r'\d+|\D+');
    final pa = re.allMatches('$a'.toLowerCase()).map((m) => m[0]!).toList();
    final pb = re.allMatches('$b'.toLowerCase()).map((m) => m[0]!).toList();
    for (var i = 0; i < pa.length && i < pb.length; i++) {
      final na = int.tryParse(pa[i]);
      final nb = int.tryParse(pb[i]);
      final c = (na != null && nb != null) ? na.compareTo(nb) : pa[i].compareTo(pb[i]);
      if (c != 0) return c;
    }
    return pa.length.compareTo(pb.length);
  }
}