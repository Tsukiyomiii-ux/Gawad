import 'dart:typed_data';

// Demo records shared by the barangay and municipality screens, so a message
// or an upload made on one side shows up on the other during the demo.
// The backend will replace this with real records.
//
// How the process works:
//   1. The barangay prints the four documents, has them signed, and uploads a
//      photo or scan of each signed paper. The upload is the backup copy.
//   2. The barangay brings the paper set to the municipality.
//   3. The municipality checks the PAPER copy. Mistakes are sent to the
//      barangay as messages. The barangay fixes the paper and uploads the
//      corrected copy so the backup stays the same as the paper.
//   4. When every barangay is checked, the municipality brings all the paper
//      sets to OPPDC together. OPPDC can open the uploaded copies as a backup.

import 'package:tanod_incentives/theme.dart';
import 'package:tanod_incentives/data/demo_data.dart';
import 'package:tanod_incentives/data/doc_kind.dart';

// Demo reviewer; replaced by the signed-in municipal account (data/cloud.dart)
var kReviewerName = 'Liza M. Tolentino';
var kReviewerFirstName = 'Liza';

enum BrgyStatus { notStarted, preparing, submitted, corrections, checked, sentToOppdc, released }

String statusLabel(BrgyStatus s) => switch (s) {
      BrgyStatus.notStarted => tr('Not started', 'Hindi pa nagsisimula', 'Wala pa nagsugod'),
      BrgyStatus.preparing => tr('Preparing', 'Inihahanda pa', 'Ginahanda pa'),
      BrgyStatus.submitted => tr('Documents on the way', 'Papunta na ang dokumento', 'Padulong na ang dokumento'),
      BrgyStatus.corrections => tr('Fixing corrections', 'Inaayos ang mali', 'Ginatadlong ang sala'),
      BrgyStatus.checked => tr('Complete', 'Kumpleto', 'Kompleto'),
      BrgyStatus.sentToOppdc => tr('With OPPDC', 'Nasa OPPDC na', 'Ara na sa OPPDC'),
      BrgyStatus.released => tr('Released', 'Na-release na', 'Na-release na'),
    };

// "Today 9:40 AM" in the current language.
String nowLabel() {
  final t = DateTime.now();
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '${tr('Today', 'Ngayon', 'Subong')} $h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
}

// One of the four documents for one barangay.
class DocFile {
  final DocKind kind;
  int version = 0; // 0 = no signed copy uploaded yet
  String? uploadedOn;
  String via = 'photo'; // 'photo' or 'file'
  bool outdated = false; // the tanod list changed after this copy was signed
  bool correction = false; // the municipality asked for a corrected copy

  // The real uploaded file (photo or chosen file). null = demo data only.
  Uint8List? bytes;
  String? fileName;
  bool isPdf = false;

  // FIREBASE: the reviewer's correction message for this document (tags it in the chat)
  String? note;

  // PAPER CHECK: what the automatic check found on the upload (null = not checked)
  String? checkNote;
  bool checkOk = true;

  DocFile(this.kind);

  bool get uploaded => version > 0;
  bool get done => uploaded && !outdated && !correction;
}

class ChatMsg {
  final bool fromMunicipality;
  final String text;
  final DocKind? doc; // which document the message is about, if any
  final String time;
  final bool system; // automatic note, e.g. "Uploaded corrected Payroll"

  const ChatMsg({
    required this.fromMunicipality,
    required this.text,
    required this.time,
    this.doc,
    this.system = false,
  });
}

class AccountRequest {
  final String name, position, barangay, mobile, proof, sent;
  const AccountRequest(this.name, this.position, this.barangay, this.mobile, this.proof, this.sent);
}

class BrgyRecord {
  String name; // not final: replaced by the real barangay name after sign-in

  // FIREBASE: barangay PSGC code and its status there (in_progress, submitted, returned, verified)
  String? id;
  String? cloudStatus;
  String rep, position, captain;
  int quota; // not final: Firebase tanodLimit
  final List<Tanod> tanods;
  final Map<DocKind, DocFile> files;
  final List<ChatMsg> chat;
  final Set<DocKind> paperOk = {}; // documents the municipality found correct on paper
  BrgyStatus status;
  String updated;
  bool accountPending;
  int unreadBrgy = 0; // messages the barangay hasn't opened
  int unreadMuni = 0; // messages the municipality hasn't opened

  BrgyRecord({
    required this.name,
    required this.rep,
    required this.position,
    required this.captain,
    required this.quota,
    required this.tanods,
    required this.files,
    required this.status,
    required this.updated,
    List<ChatMsg>? chat,
    this.accountPending = false,
  }) : chat = chat ?? [];

  int get payroll => tanods.length * kAmountEach;
  /// The barangay's own documents (Certification + ID sheet).
  List<DocFile> get docs => [for (final k in kBarangayDocs) files[k]!];
  int get backupCount => docs.where((f) => f.done).length;
  int get paperOkCount => kBarangayDocs.where(paperOk.contains).length;
  bool get backupComplete => backupCount == kBarangayDocs.length;
  List<DocFile> get toFix => [for (final f in docs) if (f.correction) f];
  List<DocFile> get outdatedFiles => [for (final f in docs) if (f.outdated) f];
  ChatMsg? get last => chat.isEmpty ? null : chat.last;

  // The latest municipality message about one document.
  ChatMsg? lastAbout(DocKind k) {
    for (var i = chat.length - 1; i >= 0; i--) {
      if (chat[i].doc == k && chat[i].fromMunicipality && !chat[i].system) return chat[i];
    }
    return null;
  }

  void post({required bool fromMunicipality, required String text, DocKind? doc, bool system = false}) {
    chat.add(ChatMsg(fromMunicipality: fromMunicipality, text: text, doc: doc, system: system, time: nowLabel()));
    if (fromMunicipality) {
      unreadBrgy++;
    } else {
      unreadMuni++;
    }
    updated = tr('Today', 'Ngayon', 'Subong');
  }

  // Everything uploaded, checked and correct (used by the demo switchers).
  void completeAll({String on = 'Oct 14'}) {
    for (final t in tanods) {
      t.confirmed = true;
    }
    for (final f in files.values) {
      if (!f.uploaded) {
        f.version = 1;
        f.uploadedOn = on;
      }
      f.outdated = false;
      f.correction = false;
    }
  }
}

// The barangay's own documents (Certification, ID sheet) are filled first.
Map<DocKind, DocFile> filesWith(int uploaded, {String on = 'Oct 13'}) {
  final order = [...kBarangayDocs, for (final k in DocKind.values) if (!kBarangayDocs.contains(k)) k];
  return {
    for (final k in DocKind.values)
      k: DocFile(k)
        ..version = order.indexOf(k) < uploaded ? 1 : 0
        ..uploadedOn = order.indexOf(k) < uploaded ? on : null,
  };
}

// Builds a believable tanod list for the OTHER demo barangays on the
// municipality side. Brgy. Abat (the signed-in barangay) never uses this.
List<Tanod> _makeTanods(int count, int seed) {
  const firsts = [
    'Ramon', 'Eduardo', 'Nestor', 'Joel', 'Arturo', 'Rolando', 'Dennis', 'Virgilio', 'Benjie', 'Romeo',
    'Alvin', 'Marlon', 'Rudy', 'Jesus', 'Leo', 'Ronnie', 'Fernando', 'Glenn', 'Rex', 'Allan',
  ];
  const lasts = [
    'Aguirre', 'Bautista', 'Castillo', 'Dalisay', 'Espinosa', 'Fuentes', 'Garcia', 'Hilado', 'Ilagan', 'Javier',
    'Lacson', 'Magbanua', 'Natividad', 'Ortiz', 'Pama', 'Quimpo', 'Robles', 'Sison', 'Tabares', 'Villanueva',
  ];
  const ids = [kIdType]; // PhilSys only
  return [
    for (var i = 0; i < count; i++)
      Tanod(
        firsts[(i * 7 + seed * 3) % firsts.length],
        String.fromCharCode(65 + (i * 5 + seed) % 26),
        lasts[(i * 11 + seed * 5) % lasts.length],
        ids[(i + seed) % ids.length],
      ),
  ];
}

const _welcome = 'Hello! When your paper set is signed, bring it to the MLGOO office. '
    'I check the paper copy and will message you here if anything needs fixing.';

List<BrgyRecord> _barangays() {
  final amiroy = BrgyRecord(
    name: 'Amiroy',
    rep: 'Marites L. Baylon',
    position: 'Treasurer',
    captain: 'Hon. Danilo S. Gerona',
    quota: 14,
    tanods: _makeTanods(12, 3),
    files: filesWith(4, on: 'Oct 11'),
    status: BrgyStatus.corrections,
    updated: 'Oct 12',
    chat: [
      const ChatMsg(fromMunicipality: true, text: _welcome, time: 'Oct 9'),
      const ChatMsg(fromMunicipality: false, text: 'Submitted. The paper set will be brought to the municipal office.', time: 'Oct 11', system: true),
      const ChatMsg(
        fromMunicipality: true,
        doc: DocKind.idSheet,
        text: 'No. 004 has only 2 of 3 signatures on the paper copy. Please have it signed again, then upload the corrected copy.',
        time: 'Oct 12 2:15 PM',
      ),
      const ChatMsg(fromMunicipality: false, text: 'Okay po, I’ll have him sign tomorrow.', time: 'Oct 12 3:02 PM'),
    ],
  );
  amiroy.files[DocKind.idSheet]!.correction = true;

  final agmanaphao = BrgyRecord(
    name: 'Agmanaphao',
    rep: 'Joy C. Tupas',
    position: 'Secretary',
    captain: 'Hon. Ernesto P. Lim',
    quota: 15,
    tanods: _makeTanods(15, 2),
    files: filesWith(4, on: 'Oct 8'),
    status: BrgyStatus.checked,
    updated: 'Oct 10',
    chat: [
      const ChatMsg(fromMunicipality: true, text: _welcome, time: 'Oct 6'),
      const ChatMsg(fromMunicipality: true, text: 'Paper set checked. Nothing to fix. Thank you!', time: 'Oct 10', system: true),
    ],
  );
  agmanaphao.paperOk.addAll(DocKind.values);

  final bangac = BrgyRecord(
    name: 'Bangac',
    rep: 'Rhea D. Moreno',
    position: 'Treasurer',
    captain: 'Hon. Arnold B. Tiongson',
    quota: 20,
    tanods: _makeTanods(20, 5),
    files: filesWith(4, on: 'Oct 14'),
    status: BrgyStatus.submitted,
    updated: 'Oct 15',
    chat: [
      const ChatMsg(fromMunicipality: true, text: _welcome, time: 'Oct 9'),
      const ChatMsg(fromMunicipality: false, text: 'Submitted. The paper set will be brought to the municipal office.', time: 'Oct 14', system: true),
      const ChatMsg(fromMunicipality: false, text: 'Good morning ma’am, I left our paper set at your office.', time: 'Oct 15 8:20 AM'),
    ],
  );
  bangac.unreadMuni = 1;

  final abat = BrgyRecord(
    name: kBarangay,
    rep: kRepName,
    position: kRepPosition,
    captain: kCaptain,
    quota: kQuota,
    tanods: [], // filled only from scanned / typed IDs
    files: filesWith(0),
    status: BrgyStatus.preparing,
    updated: 'Oct 14',
    chat: [const ChatMsg(fromMunicipality: true, text: _welcome, time: 'Oct 12')],
  );
  abat.unreadBrgy = 1;

  return [
    abat,
    agmanaphao,
    amiroy,
    BrgyRecord(
      name: 'Badiangan',
      rep: 'Ana P. Sorongon',
      position: 'Secretary',
      captain: 'Hon. Felix A. Panes',
      quota: 16,
      tanods: _makeTanods(9, 4),
      files: filesWith(1),
      status: BrgyStatus.preparing,
      updated: 'Oct 13',
      chat: [const ChatMsg(fromMunicipality: true, text: _welcome, time: 'Oct 9')],
    ),
    bangac,
    BrgyRecord(
      name: 'Cabalabaguan',
      rep: '—',
      position: '',
      captain: 'Hon. Rogelio M. Alba',
      quota: 12,
      tanods: [],
      files: filesWith(0),
      status: BrgyStatus.notStarted,
      updated: '—',
      accountPending: true,
    ),
    BrgyRecord(
      name: 'Janipaan Oeste',
      rep: 'Edwin P. Tan',
      position: 'Treasurer',
      captain: 'Hon. Lorna V. Segovia',
      quota: 18,
      tanods: _makeTanods(4, 6),
      files: filesWith(0),
      status: BrgyStatus.preparing,
      updated: 'Oct 9',
      accountPending: true,
    ),
  ];
}

const _requests = [
  AccountRequest('Rosalie T. Gonzaga', 'Secretary', 'Cabalabaguan', '09171234567', 'Appointed January 2026', 'Oct 14'),
  AccountRequest('Edwin P. Tan', 'Treasurer', 'Janipaan Oeste', '09281234567', 'Designation letter dated Feb 3, 2026', 'Oct 9'),
];

class DemoStore {
  late List<BrgyRecord> brgys;
  late List<AccountRequest> requests;
  bool sentToOppdc = false; // the municipality brought every paper set to OPPDC
  String? sentOn;

  DemoStore() {
    reset();
  }

  void reset() {
    brgys = _barangays();
    requests = List.of(_requests);
    sentToOppdc = false;
    sentOn = null;
  }

  // The barangay the barangay-side demo signs in as.
  BrgyRecord get abat => brgys.first;

  // Demo only: put Brgy. Abat at a given point in the process.
  void setAbatDemo(String key) {
    final b = abat;
    b.accountPending = key == 'pending';
    b.chat
      ..clear()
      ..add(const ChatMsg(fromMunicipality: true, text: _welcome, time: 'Oct 12'));
    b.paperOk.clear();
    b.unreadBrgy = 0;
    for (final f in b.files.values) {
      f.correction = false;
      f.outdated = false;
    }

    if (key == 'pending' || key == 'preparing') {
      b.status = BrgyStatus.preparing;
      return;
    }

    b.completeAll();
    b.post(fromMunicipality: false, system: true, text: 'Submitted. The paper set will be brought to the municipal office.');
    b.status = BrgyStatus.submitted;
    if (key == 'submitted') return;

    if (key == 'corrections') {
      final t7 = b.tanods.length > 6 ? b.tanods[6].fullName : 'No. 007';
      final t12 = b.tanods.length > 11 ? b.tanods[11].fullName : 'No. 012';
      b.post(
        fromMunicipality: true,
        doc: DocKind.certification,
        text: 'No. 007 ($t7) is spelled differently on the paper Certification than on his ID. '
            'Please correct it, have the page signed again, and upload the corrected copy.',
      );
      b.post(
        fromMunicipality: true,
        doc: DocKind.idSheet,
        text: 'No. 012 ($t12) has only 2 of 3 signatures on the ID photocopy.',
      );
      b.files[DocKind.certification]!.correction = true;
      b.files[DocKind.idSheet]!.correction = true;
      b.status = BrgyStatus.corrections;
      return;
    }

    b.paperOk.addAll(DocKind.values);
    b.post(fromMunicipality: true, system: true, text: 'Paper set checked. Nothing to fix. Thank you!');
    b.status = switch (key) {
      'oppdc' => BrgyStatus.sentToOppdc,
      'released' => BrgyStatus.released,
      _ => BrgyStatus.checked,
    };
    if (b.status == BrgyStatus.sentToOppdc || b.status == BrgyStatus.released) {
      b.post(
        fromMunicipality: true,
        system: true,
        text: 'All barangays’ paper sets were brought to OPPDC. OPPDC can also open your uploaded copies.',
      );
    }
  }

  // Demo only: mark every barangay as checked so "Submit to OPPDC" can be shown.
  void checkAllForDemo() {
    for (final b in brgys) {
      if (b.status == BrgyStatus.sentToOppdc || b.status == BrgyStatus.released) continue;
      // Never invent tanods for the real (signed-in) barangay
      if (b.tanods.isEmpty && b != abat) b.tanods.addAll(_makeTanods(b.quota - 2, b.name.length));
      if (b.rep == '—') {
        b.rep = 'Rosalie T. Gonzaga';
        b.position = 'Secretary';
      }
      b.accountPending = false;
      b.completeAll();
      b.paperOk.addAll(DocKind.values);
      b.status = BrgyStatus.checked;
    }
    requests.clear();
  }
}

final store = DemoStore();