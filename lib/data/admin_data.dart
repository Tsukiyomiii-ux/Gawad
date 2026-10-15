// ADMIN (OPPDC, provincial level): every municipality in the province and
// every barangay under it, for the Admin dashboard.
//
//   Live  → signed in with the Firebase "admin" account: real data, live.
//   Demo  → username "oppdc": built-in sample data, works without internet.
//
// Past years: Firebase only has the years that were really run. For the
// presentation, 2023–2025 are filled with SAMPLE numbers (marked sample: true
// and labelled "Sample" on screen). Set kSamplePastYears = false to hide them.

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:tanod_incentives/data/areas.dart';
import 'package:tanod_incentives/data/cloud.dart';
import 'package:tanod_incentives/data/demo_data.dart';
import 'package:tanod_incentives/data/doc_kind.dart';
import 'package:tanod_incentives/data/store.dart';
import 'package:tanod_incentives/services/database_service.dart' show Status, DatabaseService;
import 'package:tanod_incentives/Templates/gawad_pdf.dart' show buildOfficialPdf;
import 'package:tanod_incentives/Templates/payroll_template.dart' show generatePayrollPdf;
import 'package:tanod_incentives/Templates/masterlist_template.dart' show generateMasterlistPdf;
import 'package:tanod_incentives/data/tanod_bridge.dart' show personsFor;

/// Show sample numbers for 2023–2025 in Analytics (for the presentation).
const kSamplePastYears = false; // dummy 2023–2025 numbers OFF: past years come from the database

// ============================== MODELS ==============================

class AdminBrgy {
  final String id; // PSGC code (demo: made-up id)
  String name;
  final String muniId;
  String muniName;
  int limit; // this year's tanod limit
  int? nextLimit; // a changed limit that starts next year (numbers already in use)
  int tanods; // tanods listed this year
  int awardStart, awardEnd;
  String status; // Status.inProgress / submitted / returned / verified
  String reviewNote;
  BrgyRecord? demoRecord; // demo only: the record with tanods and files

  AdminBrgy({
    required this.id,
    required this.name,
    required this.muniId,
    required this.muniName,
    required this.limit,
    this.tanods = 0,
    this.awardStart = 0,
    this.awardEnd = 0,
    this.status = Status.inProgress,
    this.reviewNote = '',
    this.demoRecord,
  });

  bool get started => tanods > 0 || status != Status.inProgress;

  /// Submitted to (or verified by) the municipality: its documents are "passed".
  bool get passed => status == Status.submitted || status == Status.verified;
}

class AdminMuni {
  final String id;
  String name;
  String status; // the municipality's own status with OPPDC
  String reviewNote;
  String? submittedOn;
  final List<AdminBrgy> brgys = [];

  AdminMuni({required this.id, required this.name, this.status = Status.inProgress, this.reviewNote = ''});

  int get tanods => brgys.fold(0, (a, b) => a + b.tanods);
  int get slots => brgys.fold(0, (a, b) => a + b.limit);
  int count(String s) => brgys.where((b) => b.status == s).length;
  int get verified => count(Status.verified);
  int get notStarted => brgys.where((b) => !b.started).length;
  double get fill => slots == 0 ? 0 : tanods / slots;
}

/// One year's totals for Analytics.
class YearStat {
  final int year;
  final bool sample;
  final int tanods, slots, barangays, verifiedBarangays, municipalities, verifiedMunicipalities;
  final num amountPerTanod;
  final Map<String, int> muniTanods; // municipality name → tanods

  const YearStat({
    required this.year,
    required this.sample,
    required this.tanods,
    required this.slots,
    required this.barangays,
    required this.verifiedBarangays,
    required this.municipalities,
    required this.verifiedMunicipalities,
    required this.amountPerTanod,
    this.muniTanods = const {},
  });

  num get total => tanods * amountPerTanod;
  double get fill => slots == 0 ? 0 : tanods / slots;
  double get completion => barangays == 0 ? 0 : verifiedBarangays / barangays;
}

// ============================== DATA ==============================

final admin = AdminData._();

class AdminData {
  AdminData._();

  bool live = false;
  int year = kYear;
  num amountPerTanod = kAmountEach;
  String adminName = 'OPPDC Admin';
  final List<AdminMuni> munis = [];
  List<YearStat> pastYears = []; // years before [year], oldest first

  final changes = ValueNotifier<int>(0);
  final List<StreamSubscription> _subs = [];
  final Map<String, int> _permanentLimits = {}; // barangays/{id}.tanodLimit

  List<AdminBrgy> get allBrgys => [for (final m in munis) ...m.brgys];
  int get tanods => munis.fold(0, (a, m) => a + m.tanods);
  int get slots => munis.fold(0, (a, m) => a + m.slots);
  num get totalAmount => tanods * amountPerTanod;

  /// This year's totals (same shape as past years, for the charts)
  YearStat get current => YearStat(
        year: year,
        sample: false,
        tanods: tanods,
        slots: slots,
        barangays: allBrgys.length,
        verifiedBarangays: allBrgys.where((b) => b.status == Status.verified).length,
        municipalities: munis.length,
        verifiedMunicipalities: munis.where((m) => m.status == Status.verified).length,
        amountPerTanod: amountPerTanod,
        muniTanods: {for (final m in munis) m.name: m.tanods},
      );

  List<YearStat> get allYears => [...pastYears, current];

  void _changed() => changes.value++;

  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
  }

  // ---------------------------------------------------------------- LIVE

  Future<void> openLive() async {
    await close();
    live = true;
    munis.clear();
    final db = cloud.db;
    final y = await db.getCurrentYear();
    if (y == null) throw StateError('No incentive year has been started yet in Firebase.');
    year = y;
    final info = await db.getYear(y);
    amountPerTanod = (info?['amountPerTanod'] as num?) ?? kAmountEach;
    adminName = '${cloud.profile?['displayName'] ?? 'OPPDC Admin'}';

    final fs = FirebaseFirestore.instance;
    _subs.add(fs.collection('municipalCompliance').where('year', isEqualTo: y).snapshots().listen((snap) {
      for (final d in snap.docs) {
        final m = d.data();
        final muni = _muni('${m['municipalityId']}', '${m['municipalityName'] ?? ''}');
        muni
          ..status = '${m['status'] ?? Status.inProgress}'
          ..reviewNote = '${m['reviewNote'] ?? ''}'
          ..submittedOn = m['submittedAt'] == null ? null : timeLabel(m['submittedAt']);
      }
      _sort();
      _changed();
    }, onError: (Object e) => cloud.errors.value = Cloud.friendly(e)));

    _subs.add(fs.collection('barangayCompliance').where('year', isEqualTo: y).snapshots().listen((snap) {
      for (final m in munis) {
        m.brgys.clear();
      }
      for (final d in snap.docs) {
        final m = d.data();
        final muni = _muni('${m['municipalityId']}', '${m['municipalityName'] ?? ''}');
        final id = '${m['barangayId']}';
        final limit = (m['tanodLimit'] as num?)?.toInt() ?? 0;
        final perm = _permanentLimits[id];
        muni.brgys.add(AdminBrgy(
          id: id,
          name: '${m['barangayName'] ?? id}',
          muniId: muni.id,
          muniName: muni.name,
          limit: limit,
          tanods: ((m['usedNumbers'] as List?) ?? const []).length,
          awardStart: (m['awardStart'] as num?)?.toInt() ?? 0,
          awardEnd: (m['awardEnd'] as num?)?.toInt() ?? 0,
          status: '${m['status'] ?? Status.inProgress}',
          reviewNote: '${m['reviewNote'] ?? ''}',
        )..nextLimit = (perm != null && perm != limit) ? perm : null);
      }
      _sort();
      _changed();
    }, onError: (Object e) => cloud.errors.value = Cloud.friendly(e)));

    // Permanent limits (a changed limit may only start next year)
    _subs.add(fs.collection('barangays').snapshots().listen((snap) {
      for (final d in snap.docs) {
        final l = d.data()['tanodLimit'];
        if (l is num) _permanentLimits[d.id] = l.toInt();
      }
      for (final b in allBrgys) {
        final perm = _permanentLimits[b.id];
        b.nextLimit = (perm != null && perm != b.limit) ? perm : null;
      }
      _changed();
    }, onError: (Object e) => cloud.errors.value = Cloud.friendly(e)));

    // Past years: the real ones from Firebase, plus samples for the presentation
    final real = <YearStat>[];
    try {
      for (final yr in await db.getYears()) {
        final n = (yr['year'] as num?)?.toInt();
        if (n == null || n >= y) continue;
        final s = await db.getYearSummary(n);
        real.add(YearStat(
          year: n,
          sample: false,
          tanods: (s['tanods'] as num).toInt(),
          slots: (s['slots'] as num).toInt(),
          barangays: (s['barangays'] as num).toInt(),
          verifiedBarangays: ((s['barangayStatus'] as Map)[Status.verified] as num?)?.toInt() ?? 0,
          municipalities: (s['municipalities'] as num).toInt(),
          verifiedMunicipalities: ((s['municipalStatus'] as Map)[Status.verified] as num?)?.toInt() ?? 0,
          amountPerTanod: (s['amountPerTanod'] as num?) ?? 0,
          muniTanods: {
            for (final m in (s['perMunicipality'] as List)) '${(m as Map)['municipalityName']}': (m['tanods'] as num).toInt(),
          },
        ));
      }
    } catch (e) {
      debugPrint('Past years not loaded: $e');
    }
    pastYears = real;
    // Samples are added once this year's numbers have arrived (they are based on them)
    Future.delayed(const Duration(seconds: 2), () {
      _addSamples();
      _changed();
    });
  }

  AdminMuni _muni(String id, String name) {
    for (final m in munis) {
      if (m.id == id) {
        if (name.isNotEmpty) m.name = name;
        return m;
      }
    }
    final m = AdminMuni(id: id, name: name.isEmpty ? id : name);
    munis.add(m);
    return m;
  }

  void _sort() {
    munis.sort((a, b) => a.name.compareTo(b.name));
    for (final m in munis) {
      m.brgys.sort((a, b) => a.awardStart != b.awardStart ? a.awardStart.compareTo(b.awardStart) : a.name.compareTo(b.name));
      for (final b in m.brgys) {
        b.muniName = m.name;
      }
    }
  }

  // ---------------------------------------------------------------- DEMO

  void openDemo() {
    live = false;
    year = kYear;
    amountPerTanod = kAmountEach;
    adminName = 'Ma. Teresa D. Javellana';
    munis.clear();

    // Mina: the same barangays as the municipal demo
    final mina = AdminMuni(id: 'demo-mina', name: 'Mina');
    var next = 1;
    for (final r in store.brgys) {
      mina.brgys.add(AdminBrgy(
        id: 'demo-${r.name}',
        name: r.name,
        muniId: mina.id,
        muniName: mina.name,
        limit: r.quota,
        tanods: r.tanods.length,
        awardStart: next,
        awardEnd: next + r.quota - 1,
        status: switch (r.status) {
          BrgyStatus.submitted => Status.submitted,
          BrgyStatus.corrections => Status.returned,
          BrgyStatus.checked || BrgyStatus.sentToOppdc || BrgyStatus.released => Status.verified,
          _ => Status.inProgress,
        },
        demoRecord: r,
      ));
      next += r.quota;
    }
    munis.add(mina);

    // Two more sample towns, with real barangay names
    munis.add(_sampleTown('Pavia', status: Status.submitted, seed: 3));
    munis.add(_sampleTown('Oton', status: Status.inProgress, seed: 7));
    munis.add(_sampleTown('Leganes', status: Status.verified, seed: 5));
    _sort();
    pastYears = [];
    _addSamples();
    _changed();
  }

  AdminMuni _sampleTown(String name, {required String status, required int seed}) {
    final m = AdminMuni(id: 'demo-$name', name: name, status: status);
    final names = (kAreas[name] ?? const ['Poblacion']).take(6).toList();
    var next = 1;
    for (var i = 0; i < names.length; i++) {
      final limit = 8 + (i * seed) % 7;
      final verified = status == Status.verified || status == Status.submitted || (i + seed) % 3 == 0;
      final bStatus = verified ? Status.verified : [Status.inProgress, Status.submitted, Status.returned][(i + seed) % 3];
      final count = bStatus == Status.inProgress && (i + seed) % 2 == 0 ? 0 : limit - (i % 3);
      final rec = BrgyRecord(
        name: names[i],
        rep: '—',
        position: 'Treasurer',
        captain: 'Hon. ${_first[(i + seed) % _first.length]} ${_last[(i * 3 + seed) % _last.length]}',
        quota: limit,
        tanods: _demoTanods(count, seed + i),
        files: filesWith(bStatus == Status.verified || bStatus == Status.submitted ? 4 : 0, on: 'Oct ${8 + i}'),
        status: BrgyStatus.preparing,
        updated: 'Oct ${8 + i}',
      );
      m.brgys.add(AdminBrgy(
        id: 'demo-$name-${names[i]}',
        name: names[i],
        muniId: m.id,
        muniName: name,
        limit: limit,
        tanods: count,
        awardStart: next,
        awardEnd: next + limit - 1,
        status: bStatus,
        demoRecord: rec,
      ));
      next += limit;
    }
    return m;
  }

  static const _first = ['Ramon', 'Eduardo', 'Nestor', 'Joel', 'Arturo', 'Rolando', 'Dennis', 'Virgilio', 'Romeo', 'Alvin', 'Marlon', 'Rudy'];
  static const _last = ['Aguirre', 'Bautista', 'Castillo', 'Dalisay', 'Espinosa', 'Fuentes', 'Garcia', 'Hilado', 'Javier', 'Lacson', 'Magbanua', 'Robles'];

  List<Tanod> _demoTanods(int count, int seed) => [
        for (var i = 0; i < count; i++)
          Tanod(_first[(i * 7 + seed) % _first.length], String.fromCharCode(65 + (i * 5 + seed) % 26),
              _last[(i * 11 + seed * 5) % _last.length], kIdType)
            ..awardNumber = i + 1,
      ];

  // ---------------------------------------------------------------- SAMPLE PAST YEARS

  void _addSamples() {
    if (!kSamplePastYears) return;
    final have = {for (final p in pastYears) p.year};
    final cur = current;
    final baseSlots = cur.slots == 0 ? 120 : cur.slots;
    final townNames = cur.muniTanods.keys.toList();
    // Steady improvement each year (the story the charts tell)
    const fills = [0.78, 0.86, 0.93];
    const done = [0.72, 0.84, 0.91];
    const amounts = [800, 900, 1000];
    for (var i = 0; i < 3; i++) {
      final yr = year - 3 + i;
      if (have.contains(yr)) continue;
      final slots = (baseSlots * (0.92 + i * 0.03)).round();
      final t = (slots * fills[i]).round();
      final brgys = cur.barangays == 0 ? 20 : cur.barangays;
      pastYears.add(YearStat(
        year: yr,
        sample: true,
        tanods: t,
        slots: slots,
        barangays: brgys,
        verifiedBarangays: (brgys * done[i]).round(),
        municipalities: cur.municipalities,
        verifiedMunicipalities: (cur.municipalities * done[i]).round(),
        amountPerTanod: amounts[i],
        muniTanods: {
          for (var k = 0; k < townNames.length; k++)
            townNames[k]: ((t / (townNames.isEmpty ? 1 : townNames.length)) * (0.85 + (k % 3) * 0.1)).round(),
        },
      ));
    }
    pastYears.sort((a, b) => a.year.compareTo(b.year));
  }

  // ---------------------------------------------------------------- ACTIONS

  /// Changes a barangay's tanod limit. Returns true if it applies this year,
  /// false if it starts next year (award numbers already in use in that town,
  /// so nobody's number shifts).
  Future<bool> setLimit(AdminBrgy b, int limit, String note) async {
    if (!live) {
      b.limit = limit;
      b.demoRecord?.quota = limit;
      _changed();
      return true;
    }
    final applied = await cloud.db.amendTanodLimit(barangayPsgc: b.id, newLimit: limit, note: note);
    return applied;
  }

  /// Verify, or return with a note (sent to the municipality's messages).
  Future<void> reviewMuni(AdminMuni m, {required bool approve, String note = ''}) async {
    if (!live) {
      m
        ..status = approve ? Status.verified : Status.returned
        ..reviewNote = note;
      _changed();
      return;
    }
    await cloud.db.reviewMunicipality(municipalityPsgc: m.id, approve: approve, note: note);
  }

  // ---------------------------------------------------------------- DOCUMENTS

  /// Everything needed to show / download one barangay's four documents.
  Future<BrgyRecord> loadRecord(AdminBrgy b, {bool idPhotos = true}) async {
    final demo = b.demoRecord;
    if (!live) return demo!;

    final db = cloud.db;
    final fs = FirebaseFirestore.instance;
    final bc = await db.getBarangayCompliance(b.id, year: year);
    var captain = '', rep = '—', position = '';
    for (final s in (bc['signatories'] as List?) ?? const []) {
      if (s is! Map) continue;
      final n = '${s['name'] ?? ''}'.trim();
      final p = '${s['position'] ?? ''}'.trim();
      if (p.toLowerCase().contains('punong')) {
        captain = n;
      } else if (n.isNotEmpty) {
        rep = n;
        position = p.replaceFirst(RegExp(r'^barangay\s+', caseSensitive: false), '');
      }
    }

    final rows = await db.getBarangayTanods(b.id, year: year);
    final tanods = <Tanod>[
      for (final m in rows)
        Tanod('${m['firstName'] ?? ''}', '${m['middleInitial'] ?? ''}', '${m['lastName'] ?? ''}', kIdType,
            confirmed: m['nameChecked'] is bool ? m['nameChecked'] as bool : true,
            suffix: '${m['suffix'] ?? ''}')
          ..id = '${m['id']}'
          ..awardNumber = (m['awardNumber'] as num?)?.toInt(),
    ];
    // ID photos (for the ID photocopy sheet)
    if (idPhotos) await Future.wait([
      for (final t in tanods)
        db.getIdScan(t.id!).then((s) {
          if (s != null) {
            t.idFront = s.front;
            t.idBack = s.back;
          }
        }).catchError((Object _) {}),
    ]);

    final rec = BrgyRecord(
      name: b.name,
      rep: rep,
      position: position,
      captain: captain,
      quota: b.limit,
      tanods: tanods,
      files: filesWith(0),
      status: BrgyStatus.preparing,
      updated: '—',
    )..id = b.id;

    // Signed copies (the barangay's uploaded backups)
    for (final k in DocKind.values) {
      try {
        final s = await fs.collection('signedCopies').doc('${year}_${b.id}_${k.name}').get();
        final m = s.data();
        final data = m?['data'];
        if (m != null && data is Blob) {
          rec.files[k]!
            ..version = (m['version'] as num?)?.toInt() ?? 1
            ..uploadedOn = timeLabel(m['uploadedAt'])
            ..bytes = data.bytes
            ..fileName = m['fileName'] as String?
            ..isPdf = m['isPdf'] == true
            ..checkNote = m['autoCheck'] as String?
            ..checkOk = m['autoCheckOk'] != false;
        }
      } catch (_) {}
    }
    return rec;
  }

  /// The official PDF for a barangay of any municipality. The templates read
  /// the town name from kMunicipality, so it is set just while the PDF is made.
  Future<Uint8List> buildPdf(AdminBrgy b, BrgyRecord rec, DocKind k) async {
    final saved = kMunicipality;
    kMunicipality = b.muniName;
    try {
      return await buildOfficialPdf(rec, k);
    } finally {
      kMunicipality = saved;
    }
  }

  /// Payroll and Masterlist are made per MUNICIPALITY, once every barangay is verified.
  bool muniDocsReady(AdminMuni m) => m.brgys.isNotEmpty && m.brgys.every((b) => b.status == Status.verified);

  /// One Payroll / Masterlist with every barangay of the municipality, each
  /// tanod at the award number saved in the database.
  Future<Uint8List> buildMuniPdf(AdminMuni m, DocKind k) async {
    final recs = await Future.wait([
      for (final b in m.brgys.where((b) => b.tanods > 0)) loadRecord(b, idPhotos: false),
    ]);
    final listed = [for (final r in recs) ...personsFor(r)];
    int n(int? v) => v ?? (1 << 30);
    final order = List<int>.generate(listed.length, (i) => i)
      ..sort((i, j) {
        final c = n(listed[i].awardNumber).compareTo(n(listed[j].awardNumber));
        return c != 0 ? c : i.compareTo(j);
      });
    final people = [for (final i in order) listed[i]];
    final saved = kMunicipality;
    kMunicipality = m.name;
    try {
      return await (k == DocKind.payroll
          ? generatePayrollPdf(
              tanodList: people,
              period: 'For the period CY $year',
              municipality: 'MUNICIPALITY OF ${m.name.toUpperCase()}',
              defaultAmount: kAmountEach.toDouble(),
            )
          : generateMasterlistPdf(tanodList: people, calendarYear: '$year'));
    } finally {
      kMunicipality = saved;
    }
  }

  String muniPdfKey(AdminMuni m, DocKind k) =>
      ['adminMuni', m.id, k.name, year, for (final b in m.brgys) '${b.id}|${b.tanods}|${b.awardStart}|${b.status}'].join('~');

  /// Cache key for previews (changes when the content changes).
  String pdfKey(AdminBrgy b, BrgyRecord rec, DocKind k) => [
        'admin',
        k.name,
        b.muniName,
        rec.name,
        year,
        rec.captain,
        for (final t in rec.tanods) '${t.awardNumber}|${t.fullName}|${t.idFront?.length}',
      ].join('~');

  /// Compliance id (for messages etc.)
  String complianceId(String psgc) => DatabaseService.complianceId(year, psgc);
}


// ======================= STAGE (same names as the barangay's Submission status) =======================

/// 0 Not Started · 1 Enroute to Municipality · 2 Received at the Municipality
/// 3 Enroute to OPPDC · 4 Incentive Released
int brgyStage(AdminBrgy b) {
  if (b.status == Status.submitted || b.status == Status.returned) return 1;
  if (b.status != Status.verified) return 0;
  final m = admin.munis.where((x) => x.id == b.muniId).firstOrNull;
  if (m?.status == Status.verified) return 4;
  if (m?.status == Status.submitted) return 3;
  return 2;
}

const kStageNames = [
  'Not Started',
  'Enroute to Municipality',
  'Received at the Municipality',
  'Enroute to OPPDC',
  'Incentive Released',
];