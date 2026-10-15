import 'package:flutter/material.dart';

import 'package:tanod_incentives/theme.dart';
import 'package:tanod_incentives/data/demo_data.dart';
import 'package:tanod_incentives/data/store.dart';
import 'package:tanod_incentives/widgets/app_field.dart';
import 'package:tanod_incentives/widgets/chat_thread.dart';
import 'package:tanod_incentives/widgets/upload_sheet.dart';
import 'package:tanod_incentives/screens/auth/auth_page.dart';
import 'package:tanod_incentives/screens/dashboard/documents_view.dart';
import 'package:tanod_incentives/screens/scan/scan_flow_page.dart';
import 'package:tanod_incentives/Templates/gawad_pdf.dart'; // MERGE: real PDFs

// Barangay representative dashboard.
// Pages: Overview, Tanods, Documents, Messages, Account, Help.
//
// The barangay prints the filled documents, has them signed, uploads a photo
// or scan of each signed paper (the backup), and brings the paper set to the
// municipality. The municipality checks the paper and sends corrections as
// messages; the barangay fixes the paper and uploads the corrected copy.

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _NavItem {
  final IconData icon, activeIcon;
  final String en, fil, hil;
  const _NavItem(this.icon, this.activeIcon, this.en, this.fil, this.hil);
  String get label => tr(en, fil, hil);
}

const _nav = [
  _NavItem(Icons.space_dashboard_outlined, Icons.space_dashboard, 'Overview', 'Buod', 'Kabilugan'),
  _NavItem(Icons.groups_outlined, Icons.groups, 'Tanods', 'Mga Tanod', 'Mga Tanod'),
  _NavItem(Icons.description_outlined, Icons.description, 'Documents', 'Dokumento', 'Dokumento'),
  _NavItem(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Messages', 'Mensahe', 'Mensahe'),
  _NavItem(Icons.person_outline, Icons.person, 'Account', 'Account', 'Account'),
  _NavItem(Icons.help_outline, Icons.help, 'Help', 'Tulong', 'Bulig'),
];

const _messagesTab = 3;
const _accountTab = 4;
const _helpTab = 5;

// Opens a small "what does this mean?" box.
void explain(BuildContext context, String title, String body) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      icon: const Icon(Icons.lightbulb_outline_rounded, color: C.yellowDark, size: 30),
      title: Text(title, textAlign: TextAlign.center, style: serif(22)),
      content: Text(body, style: sans(15.5, color: C.ink, h: 1.55)),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: C.navy,
            foregroundColor: Colors.white,
            minimumSize: const Size(140, 46),
          ),
          onPressed: () => Navigator.pop(ctx),
          child: Text(tr('Got it', 'Sige', 'Sige')),
        ),
      ],
    ),
  );
}

const _stepCount = 5;

String _stepName(int i) => [
      tr('Preparing', 'Inihahanda', 'Ginahanda'),
      tr('With $kMunicipality', 'Nasa $kMunicipality', 'Ara sa $kMunicipality'),
      tr('Checked', 'Nasuri na', 'Nausisa na'),
      tr('With OPPDC', 'Nasa OPPDC', 'Ara sa OPPDC'),
      tr('Released', 'Na-release', 'Na-release na'),
    ][i];

class _Issue {
  final String id, title, body;
  final IconData icon;
  const _Issue(this.id, this.title, this.body, this.icon);
}

class _Alert {
  final String title, body, action;
  final IconData icon;
  final VoidCallback? onAction;
  final bool red;
  const _Alert(this.title, this.body, this.icon, this.action, this.onAction, {this.red = false});
}

String peso(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '₱$b';
}

String awardNo(int index) => (index + 1).toString().padLeft(3, '0');

class _DashboardPageState extends State<DashboardPage> {
  final Set<String> resolved = {};
  int navIndex = 0;
  bool online = false;
  int pendingSync = 3;

  // ---------- derived values ----------
  BrgyRecord get rec => store.abat;
  List<Tanod> get tanods => rec.tanods;
  bool get pending => rec.accountPending;
  bool get corrections => rec.status == BrgyStatus.corrections;

  // Position on the 5-step tracker.
  int get stage => switch (rec.status) {
        BrgyStatus.notStarted || BrgyStatus.preparing => 0,
        BrgyStatus.submitted || BrgyStatus.corrections => 1,
        BrgyStatus.checked => 2,
        BrgyStatus.sentToOppdc => 3,
        BrgyStatus.released => 4,
      };

  // The list can't change while the municipality or OPPDC has the set,
  // except when the municipality asked for corrections.
  bool get locked => switch (rec.status) {
        BrgyStatus.submitted || BrgyStatus.checked || BrgyStatus.sentToOppdc || BrgyStatus.released => true,
        _ => false,
      };

  bool get canSubmit => !pending && stage == 0 && rec.backupComplete && issues.isEmpty;
  bool get canSendBack => corrections && rec.toFix.isEmpty && rec.outdatedFiles.isEmpty && issues.isEmpty;

  List<_Issue> get issues {
    final out = <_Issue>[];
    final seen = <String, Tanod>{};
    for (final t in tanods) {
      final other = seen[t.nameKey];
      if (other == null) {
        seen[t.nameKey] = t;
        continue;
      }
      final id = 'dup-${t.nameKey}';
      if (!resolved.contains(id)) {
        out.add(_Issue(
          id,
          tr('Names look alike', 'Magkahawig na pangalan', 'Daw pareho ang ngalan'),
          tr('“${other.fullName}” and “${t.fullName}” may be the same person.',
              'Baka iisang tao sina “${other.fullName}” at “${t.fullName}”.', 'Basi isa lang ka tawo sanday “${other.fullName}” kag “${t.fullName}”.'),
          Icons.people_alt_outlined,
        ));
      }
    }
    for (final t in tanods.where((t) => !t.confirmed)) {
      out.add(_Issue('conf-${t.fullName}', tr('Spelling not checked yet', 'Hindi pa nasusuri ang baybay', 'Wala pa nausisa ang spelling'),
          tr('Compare “${t.fullName}” with the original ID.', 'Ikumpara ang “${t.fullName}” sa orihinal na ID.', 'Palihog ikumpara ang “${t.fullName}” sa orihinal nga ID.'),
          Icons.document_scanner_outlined));
    }
    return out;
  }

  // Warnings shown only when something is wrong.
  List<_Alert> get alerts {
    final out = <_Alert>[];
    for (final i in issues) {
      final isConf = i.id.startsWith('conf-');
      out.add(_Alert(
        i.title,
        i.body,
        i.icon,
        isConf ? tr('Check name', 'Suriin', 'Usisaa ang ngalan') : tr('Compare', 'Ikumpara', 'Ikumpara'),
        locked
            ? null
            : () {
                if (isConf) {
                  final at = tanods.indexWhere((t) => 'conf-${t.fullName}' == i.id);
                  if (at >= 0) _editTanod(at);
                } else {
                  _reviewDuplicate(i);
                }
              },
      ));
    }
    if (rec.toFix.isNotEmpty) {
      out.add(_Alert(
        tr('$kMunicipality found mistakes on the paper', 'May nakitang mali ang $kMunicipality sa papel', 'May nakita nga sala ang $kMunicipality sa papel'),
        tr('Correct the paper and upload the corrected copy of: ${rec.toFix.map((f) => f.kind.title).join(', ')}.',
            'Itama ang papel at i-upload ang naitamang kopya ng: ${rec.toFix.map((f) => f.kind.title).join(', ')}.', 'Palihog tadlunga ang papel kag i-upload ang natadlong nga kopya sang: ${rec.toFix.map((f) => f.kind.title).join(', ')}.'),
        Icons.assignment_return_outlined,
        tr('Open messages', 'Buksan ang mensahe', 'Buksan ang mensahe'),
        () => _go(_messagesTab),
        red: true,
      ));
    }
    if (rec.outdatedFiles.isNotEmpty) {
      out.add(_Alert(
        tr('Signed copies are out of date', 'Luma na ang pirmadong kopya', 'Daan na ang may pirma nga kopya'),
        tr('You changed the tanod list after signing ${rec.outdatedFiles.map((f) => f.kind.title).join(', ')}. '
                'Award numbers and names on the paper may no longer match. Print the new versions, have them signed, and upload them again.',
            'Binago ang listahan matapos pirmahan ang ${rec.outdatedFiles.map((f) => f.kind.title).join(', ')}. '
                'Baka hindi na tugma ang award number at pangalan sa papel. I-print ang bagong bersyon, papirmahan, at i-upload ulit.', 'Nabag-o ang listahan sang tanod pagkatapos mapirmahan ang ${rec.outdatedFiles.map((f) => f.kind.title).join(', ')}. ' 'Basi indi na pareho ang award number kag ngalan sa papel. Palihog i-print ang bag-o nga bersyon, papirmahi, kag i-upload liwat.'),
        Icons.warning_amber_rounded,
        tr('Go to documents', 'Pumunta sa dokumento', 'Kadto sa dokumento'),
        () => _go(2),
      ));
    }
    if (tanods.length > kQuota) {
      out.add(_Alert(
        tr('More tanods than allowed', 'Sobra ang tanod', 'Sobra ang tanod'),
        tr('OPPDC allows $kQuota. Remove ${tanods.length - kQuota}.', 'Hanggang $kQuota lang ang puwede. Magtanggal ng ${tanods.length - kQuota}.', 'Tubtob $kQuota lang ang gintugot sang OPPDC. Palihog kuhaa ang ${tanods.length - kQuota}.'),
        Icons.block_rounded,
        tr('Open list', 'Buksan ang listahan', 'Buksan ang listahan'),
        () => _go(1),
        red: true,
      ));
    }
    return out;
  }

  // ---------- actions ----------
  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

  void _signOut() => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AuthPage()));

  void _go(int i) => setState(() {
        navIndex = i;
        if (i == _messagesTab) rec.unreadBrgy = 0;
      });

  void _sync() => setState(() {
        online = true;
        pendingSync = 0;
      });

  // The tanod list or signatories changed: signed copies no longer match.
  void _markChanged() {
    pendingSync++;
    online = false;
    for (final f in rec.files.values) {
      if (f.uploaded) f.outdated = true;
    }
  }

  void _quotaToast() => _toast(tr('Limit reached: OPPDC allows $kQuota tanods for Brgy. $kBarangay this year.',
      'Puno na: $kQuota tanod lang ang puwede sa Brgy. $kBarangay ngayong taon.', 'Puno na ang listahan: $kQuota ka tanod lang ang gintugot sang OPPDC para sa Brgy. $kBarangay subong nga tuig.'));

  void _lockedToast() => _toast(tr('Your set is with $kMunicipality, so the tanod list is locked for now.',
      'Nasa $kMunicipality ang inyong set kaya naka-lock muna ang listahan.', 'Ara pa sa $kMunicipality ang inyo set, gani naka-lock anay ang listahan sang tanod.'));

  // MERGE: opens the real, filled PDF (print / share / save)
  void _downloadPdf(DocKind k) => showOfficialPdf(context, rec, k);

  Future<void> _upload(DocKind k) async {
    final f = rec.files[k]!;
    final wasFix = f.correction;
    final up = await showUploadSheet(context, docTitle: k.title, correction: wasFix);
    if (up == null || !mounted) return;
    setState(() {
      f.version++;
      f.uploadedOn = nowLabel();
      f.via = up.via;
      // The new upload replaces the previous copy
      f.bytes = up.bytes;
      f.fileName = up.name;
      f.isPdf = up.isPdf;
      f.outdated = false;
      if (wasFix) {
        f.correction = false;
        rec.post(
          fromMunicipality: false,
          system: true,
          doc: k,
          text: 'Uploaded the corrected ${k.title} (version ${f.version}).',
        );
      }
      pendingSync++;
      online = false;
    });
    _toast(wasFix
        ? tr('Corrected ${k.title} uploaded. Bring the corrected paper to $kMunicipality too.',
            'Na-upload ang naitamang ${k.title}. Dalhin din ang naitamang papel sa $kMunicipality.', 'Na-upload na ang natadlong nga ${k.title}. Palihog dal-a man ang natadlong nga papel sa $kMunicipality.')
        : tr('Signed ${k.title} uploaded. It replaces the file and is your backup.',
            'Na-upload ang pirmadong ${k.title}. Papalitan nito ang file at ito ang inyong backup.', 'Na-upload na ang may pirma nga ${k.title}. Amo na ini ang inyo backup.'));
  }

  Future<void> _scanId() async {
    if (locked) {
      _lockedToast();
      return;
    }
    if (tanods.length >= kQuota) {
      _quotaToast();
      return;
    }
    final added = await Navigator.of(context).push<List<Tanod>>(
      MaterialPageRoute(
        builder: (_) => ScanFlowPage(startCount: tanods.length, slotsLeft: kQuota - tanods.length),
      ),
    );
    if (!mounted || added == null || added.isEmpty) return;
    setState(() {
      tanods.addAll(added);
      _markChanged();
    });
    _toast(tr('Added ${added.length} tanod${added.length == 1 ? '' : 's'} from scanned IDs.',
        'Naidagdag ang ${added.length} tanod mula sa na-scan na ID.', 'Nadugang ang ${added.length} ka tanod halin sa na-scan nga ID.'));
  }

  // Demo only: jump between statuses for the pitch.
  void _setDemo(String key) => setState(() {
        store.setAbatDemo(key);
        if (key != 'pending' && key != 'preparing') {
          for (final i in issues) {
            resolved.add(i.id);
          }
        }
      });

  Future<void> _addManually() async {
    if (locked) {
      _lockedToast();
      return;
    }
    if (tanods.length >= kQuota) {
      _quotaToast();
      return;
    }
    final first = TextEditingController();
    final middle = TextEditingController();
    final last = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var idType = kIdTypes.first;

    final added = await showDialog<Tanod>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Add a tanod', 'Magdagdag ng tanod', 'Magdugang sang tanod'), style: serif(24)),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    tr('They will get award no. ${awardNo(tanods.length)}. ${kQuota - tanods.length - 1} slots left after this.',
                        'Award no. ${awardNo(tanods.length)} ang ibibigay. ${kQuota - tanods.length - 1} pa ang matitira.', 'Award no. ${awardNo(tanods.length)} ang ihatag. ${kQuota - tanods.length - 1} pa ang mabilin pagkatapos sini.'),
                    style: sans(14.5, color: C.muted, h: 1.5)),
                const SizedBox(height: 18),
                AppField(
                  label: tr('First name', 'Pangalan', 'Ngalan'),
                  icon: Icons.person_outline,
                  controller: first,
                  hint: 'Juan',
                  validator: (v) => (v ?? '').trim().isEmpty ? tr('Enter the first name.', 'Ilagay ang pangalan.', 'Palihog isulat ang ngalan.') : null,
                ),
                const SizedBox(height: 14),
                AppField(
                  label: tr('Middle initial', 'Gitnang inisyal', 'Inisyal sang tunga nga ngalan'),
                  icon: Icons.short_text,
                  controller: middle,
                  hint: 'S',
                  maxLength: 1,
                  required: false,
                  optional: true,
                ),
                const SizedBox(height: 14),
                AppField(
                  label: tr('Last name', 'Apelyido', 'Apelyido'),
                  icon: Icons.person_outline,
                  controller: last,
                  hint: 'Dela Cruz',
                  validator: (v) => (v ?? '').trim().isEmpty ? tr('Enter the last name.', 'Ilagay ang apelyido.', 'Palihog isulat ang apelyido.') : null,
                ),
                const SizedBox(height: 14),
                Align(alignment: Alignment.centerLeft, child: FieldLabel(tr('ID type', 'Uri ng ID', 'Klase sang ID'))),
                DropdownButtonFormField<String>(
                  initialValue: idType,
                  isExpanded: true,
                  style: sans(15),
                  dropdownColor: Colors.white,
                  decoration: fieldDecoration('', Icons.badge_outlined),
                  items: kIdTypes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => idType = v ?? idType,
                ),
              ]),
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Cancel', 'Kanselahin', 'Kanselaha'), style: sans(14.5, w: FontWeight.w600, color: C.muted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: C.navy, foregroundColor: Colors.white),
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(
                ctx,
                Tanod(first.text.trim(), middle.text.trim().toUpperCase(), last.text.trim(), idType),
              );
            },
            child: Text(tr('Add tanod', 'Idagdag', 'Idugang ang tanod')),
          ),
        ],
      ),
    );

    // Dispose after the dialog's closing animation finishes.
    Future.delayed(const Duration(milliseconds: 400), () {
      first.dispose();
      middle.dispose();
      last.dispose();
    });

    if (added == null || !mounted) return;
    setState(() {
      tanods.add(added);
      _markChanged();
    });
    _toast(tr('Added ${added.fullName} as award no. ${awardNo(tanods.length - 1)}.',
        'Naidagdag si ${added.fullName} bilang award no. ${awardNo(tanods.length - 1)}.', 'Nadugang si ${added.fullName} bilang award no. ${awardNo(tanods.length - 1)}.'));
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: serif(24)),
        content: Text(body, style: sans(15.5, color: C.muted, h: 1.5)),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Not yet', 'Hindi pa', 'Indi pa'), style: sans(14.5, w: FontWeight.w600, color: C.muted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: C.navy, foregroundColor: Colors.white, minimumSize: const Size(0, 46)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _submit() async {
    final ok = await _confirm(
      tr('Submit to $kMunicipality?', 'Ipasa sa $kMunicipality?', 'Ipasa sa $kMunicipality?'),
      tr('Your 4 signed copies are uploaded as the backup. Bring the signed paper set to the MLGOO office in $kMunicipality. '
              'The reviewer checks the paper and will message you here if anything needs fixing.',
          'Na-upload na ang 4 na pirmadong kopya bilang backup. Dalhin ang pirmadong papel sa tanggapan ng MLGOO sa $kMunicipality. '
              'Susuriin ng reviewer ang papel at magme-message dito kung may kailangang ayusin.', 'Na-upload na ang 4 ka may pirma nga kopya bilang backup. Palihog dal-a ang may pirma nga papel sa opisina sang MLGOO sa $kMunicipality. ' 'Usisaon sang reviewer ang papel kag magmensahe sila diri kon may kinahanglan tadlungon.'),
      tr('Submit', 'Ipasa', 'Ipasa'),
    );
    if (!ok || !mounted) return;
    setState(() {
      rec.status = BrgyStatus.submitted;
      rec.post(fromMunicipality: false, system: true, text: 'Submitted. The paper set will be brought to the municipal office.');
    });
    _toast(tr('Submitted. Bring the paper set to $kMunicipality.', 'Naipasa. Dalhin ang papel sa $kMunicipality.', 'Napasa na. Palihog dal-a ang papel sa $kMunicipality.'));
  }

  Future<void> _sendBack() async {
    final ok = await _confirm(
      tr('Corrections done?', 'Tapos na ang pagtatama?', 'Natapos na ang pagtadlong?'),
      tr('Bring the corrected paper pages to the MLGOO office. Your corrected copies are already uploaded, so the backup matches the paper.',
          'Dalhin ang naitamang papel sa tanggapan ng MLGOO. Na-upload na ang naitamang kopya kaya tugma ang backup sa papel.', 'Palihog dal-a ang natadlong nga papel sa opisina sang MLGOO. Na-upload na ang natadlong nga kopya, gani pareho na ang backup kag ang papel.'),
      tr('Tell $kMunicipality', 'Sabihan ang $kMunicipality', 'Ipahibalo sa $kMunicipality'),
    );
    if (!ok || !mounted) return;
    setState(() {
      rec.status = BrgyStatus.submitted;
      rec.post(
        fromMunicipality: false,
        system: true,
        text: 'Corrections done. The corrected paper pages will be brought to the municipal office.',
      );
    });
    _toast(tr('Sent. $kMunicipality will check the corrected paper.', 'Naipadala. Susuriin ng $kMunicipality ang naitamang papel.', 'Napadala na. Usisaon sang $kMunicipality ang natadlong nga papel.'));
  }

  // ---------- layout ----------
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final wide = w >= 1000;
    final page = switch (navIndex) {
      1 => _tanodsPage(),
      2 => _documentsPage(),
      _messagesTab => _messagesPage(),
      _accountTab => _accountPage(),
      _helpTab => _helpPage(),
      _ => _overviewPage(),
    };

    if (wide) {
      return Scaffold(
        backgroundColor: C.mist,
        body: Row(children: [
          _Sidebar(index: navIndex, unread: rec.unreadBrgy, onSelect: _go, onSignOut: _signOut),
          Expanded(child: Column(children: [_topBar(true), Expanded(child: page)])),
        ]),
      );
    }

    // Phones show five tabs; Help is in the account menu.
    return Scaffold(
      backgroundColor: C.mist,
      body: SafeArea(child: Column(children: [_topBar(false), Expanded(child: page)])),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navIndex > _accountTab ? _accountTab : navIndex,
        onDestinationSelected: _go,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        indicatorColor: C.yellow.withValues(alpha: .4),
        height: 68,
        destinations: [
          for (var i = 0; i < _helpTab; i++)
            NavigationDestination(
              icon: _badged(i, Icon(_nav[i].icon)),
              selectedIcon: _badged(i, Icon(_nav[i].activeIcon, color: C.navy)),
              label: _nav[i].label,
            ),
        ],
      ),
    );
  }

  Widget _badged(int i, Widget icon) =>
      i == _messagesTab && rec.unreadBrgy > 0 ? Badge(label: Text('${rec.unreadBrgy}'), child: icon) : icon;

  Widget _scroll(List<Widget> children) {
    final w = MediaQuery.of(context).size.width;
    final pad = w < 600 ? 16.0 : 28.0;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    );
  }

  Widget _topBar(bool wide) {
    return Container(
      height: 68,
      padding: EdgeInsets.symmetric(horizontal: wide ? 28 : 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: C.line)),
      ),
      child: Row(children: [
        if (!wide) ...[_logoMark(34), const SizedBox(width: 10)],
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(wide ? _nav[navIndex].label : 'Gawad',
                overflow: TextOverflow.ellipsis, style: sans(wide ? 20 : 17, w: FontWeight.w700, color: C.navy)),
            Text('Brgy. $kBarangay, $kMunicipality · $kYear',
                overflow: TextOverflow.ellipsis, style: sans(13.5, color: C.muted)),
          ]),
        ),
        if (kDemoMode) ...[_demoMenu(), const SizedBox(width: 6)],
        Flexible(child: _syncChip(compact: !wide)), // FIX: was overflowing on phones
        const SizedBox(width: 10),
        PopupMenuButton<String>(
          tooltip: tr('Account', 'Account', 'Account'),
          offset: const Offset(0, 48),
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (v) => v == 'out' ? _signOut() : _go(v == 'help' ? _helpTab : _accountTab),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'acct', child: Text(tr('My account & settings', 'Account at settings', 'Akon account kag settings'), style: sans(15))),
            PopupMenuItem(value: 'help', child: Text(tr('Help', 'Tulong', 'Bulig'), style: sans(15))),
            PopupMenuItem(value: 'out', child: Text(tr('Sign out', 'Mag-sign out', 'Mag-sign out'), style: sans(15, color: C.red))),
          ],
          child: CircleAvatar(
            radius: 19,
            backgroundColor: C.yellow,
            child: Text('MD', style: sans(14, w: FontWeight.w700, color: C.navy)),
          ),
        ),
      ]),
    );
  }

  Widget _demoMenu() {
    const items = [
      ('pending', 'Account waiting for approval'),
      ('preparing', 'Preparing'),
      ('submitted', 'Paper set with the municipality'),
      ('corrections', 'Municipality asked for corrections'),
      ('checked', 'Checked by the municipality'),
      ('oppdc', 'With OPPDC'),
      ('released', 'Released'),
    ];
    return PopupMenuButton<String>(
      tooltip: 'Demo: switch status',
      offset: const Offset(0, 46),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: _setDemo,
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text('DEMO · SHOW STATUS', style: sans(12, w: FontWeight.w700, color: C.muted).copyWith(letterSpacing: .6)),
        ),
        for (final (key, label) in items) PopupMenuItem<String>(value: key, child: Text(label, style: sans(15))),
      ],
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: C.mist, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.tune_rounded, size: 19, color: C.muted),
      ),
    );
  }

  Widget _syncChip({required bool compact}) {
    final bg = online ? C.greenSoft : const Color(0xFFFFF4CC);
    final fg = online ? const Color(0xFF14583D) : const Color(0xFF7A5B00);
    final label = online
        ? tr('All synced', 'Naka-sync lahat', 'Naka-sync tanan')
        : (compact
            ? tr('$pendingSync not synced', '$pendingSync di pa naka-sync', '$pendingSync wala pa na-sync')
            : tr('Saved on phone · $pendingSync not synced', 'Naka-save sa phone · $pendingSync di pa naka-sync', 'Naka-save sa phone · $pendingSync wala pa na-sync'));
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: _syncInfo,
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(online ? Icons.cloud_done_outlined : Icons.phone_android_rounded, size: 17, color: fg),
          const SizedBox(width: 6),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: sans(14, w: FontWeight.w600, color: fg))),
        ]),
      ),
    );
  }

  void _syncInfo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Icon(online ? Icons.cloud_done_outlined : Icons.phone_android_rounded,
            size: 30, color: online ? C.green : C.yellowDark),
        title: Text(online ? tr('Everything is synced', 'Naka-sync na ang lahat', 'Naka-sync na ang tanan') : tr('Saved on this phone', 'Naka-save sa phone na ito', 'Naka-save sa sini nga phone'),
            textAlign: TextAlign.center, style: serif(22)),
        content: Text(
          online
              ? tr('Your municipality can see your latest changes and uploads.',
                  'Nakikita na ng munisipyo ang pinakabagong pagbabago at upload.', 'Makita na sang inyo munisipyo ang pinakabag-o nga pagbag-o kag upload.')
              : tr(
                  'Your work is safe on this phone. $pendingSync change${pendingSync == 1 ? '' : 's'} will sync by '
                      'themselves when you have internet. You can keep working offline.',
                  'Ligtas ang inyong trabaho sa phone na ito. Kusang magsi-sync ang $pendingSync pagbabago kapag may '
                      'internet. Puwede kayong magpatuloy kahit offline.', 'Luwas ang inyo obra sa sini nga phone. Kusa nga ma-sync ang $pendingSync ka pagbag-o ' 'kon may internet na. Pwede kamo magpadayon bisan offline.'),
          style: sans(15.5, color: C.ink, h: 1.55),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          if (!online)
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
              onPressed: () {
                Navigator.pop(ctx);
                _sync();
              },
              child: Text(tr('Sync now', 'I-sync ngayon', 'I-sync subong')),
            ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: C.navy, foregroundColor: Colors.white, minimumSize: const Size(0, 46)),
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('OK', 'Sige', 'Sige')),
          ),
        ],
      ),
    );
  }

  // ================= Overview =================
  Widget _overviewPage() {
    return LayoutBuilder(builder: (context, box) {
      final two = box.maxWidth >= 900;
      const gap = SizedBox(height: 20);
      final banner = _statusBanner();
      final next = _nextStepCard();
      return _scroll([
        if (banner != null) ...[banner, gap],
        _welcome(),
        gap,
        if (next != null) ...[next, gap],
        _statusPanel(),
        gap,
        _stats(),
        gap,
        if (two)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: _backupPanel()),
            const SizedBox(width: 20),
            Expanded(flex: 2, child: Column(children: [_alertsPanel(), gap, _messagesPreview()])),
          ])
        else ...[
          _backupPanel(),
          gap,
          _alertsPanel(),
          gap,
          _messagesPreview(),
        ],
        gap,
        _tanodPanel(limit: 6),
        gap,
        _submitPanel(),
      ]);
    });
  }

  // ---------- "Your next step" ----------
  Widget _bigButton(String label, IconData icon, VoidCallback onTap, {bool outlined = false}) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(13));
    const pad = EdgeInsets.symmetric(horizontal: 20, vertical: 16);
    return outlined
        ? OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: C.navy,
              side: const BorderSide(color: C.line, width: 1.5),
              padding: pad,
              minimumSize: const Size(0, 52),
              shape: shape,
              textStyle: sans(15.5, w: FontWeight.w600),
            ),
            onPressed: onTap,
            icon: Icon(icon, size: 20),
            label: Text(label),
          )
        : FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: C.yellow,
              foregroundColor: C.navy,
              padding: pad,
              minimumSize: const Size(0, 52),
              shape: shape,
              textStyle: sans(15.5, w: FontWeight.w700),
            ),
            onPressed: onTap,
            icon: Icon(icon, size: 20),
            label: Text(label),
          );
  }

  Widget? _nextStepCard() {
    // The corrections and released banners take over at those points.
    if (corrections || rec.status == BrgyStatus.released) return null;

    final unconfirmed = [for (var i = 0; i < tanods.length; i++) if (!tanods[i].confirmed) i];
    final lookAlikes = issues.where((x) => x.id.startsWith('dup-')).toList();
    final notDone = rec.files.values.where((f) => !f.done).toList();
    final steps = [tanods.isNotEmpty, unconfirmed.isEmpty, lookAlikes.isEmpty, for (final f in rec.files.values) f.done];
    final done = steps.where((x) => x).length;

    var icon = Icons.flag_outlined;
    var title = '';
    var body = '';
    var actions = <Widget>[];

    if (locked) {
      icon = Icons.hourglass_top_rounded;
      title = tr('Nothing to do right now', 'Wala pang kailangang gawin', 'Wala pa sang himuon subong');
      body = switch (rec.status) {
        BrgyStatus.submitted => tr(
            '$kMunicipality is checking your paper set. If something needs fixing, you’ll get a message here.',
            'Sinusuri ng $kMunicipality ang inyong papel. Makakatanggap kayo ng mensahe dito kung may kailangang ayusin.', 'Ginausisa pa sang $kMunicipality ang inyo papel. Kon may kinahanglan tadlungon, magmensahe sila diri.'),
        BrgyStatus.checked => tr(
            'Your paper set was checked. $kMunicipality will bring all barangays’ sets to OPPDC together.',
            'Nasuri na ang inyong papel. Sabay-sabay na dadalhin ng $kMunicipality sa OPPDC ang set ng lahat ng barangay.', 'Nausisa na ang inyo papel. Dungan nga dal-on sang $kMunicipality sa OPPDC ang set sang tanan nga barangay.'),
        _ => tr('Your set is with OPPDC. OPPDC can also open your uploaded copies.',
            'Nasa OPPDC na ang inyong set. Mabubuksan din ng OPPDC ang inyong na-upload na kopya.', 'Ara na sa OPPDC ang inyo set. Mabuksan man sang OPPDC ang inyo na-upload nga kopya.'),
      };
      actions = [_bigButton(tr('Open messages', 'Buksan ang mensahe', 'Buksan ang mensahe'), Icons.chat_bubble_outline_rounded, () => _go(_messagesTab), outlined: true)];
    } else if (tanods.isEmpty) {
      icon = Icons.document_scanner_outlined;
      title = tr('Add your first tanod', 'Idagdag ang unang tanod', 'Idugang ang una nga tanod');
      body = tr('Scan their PhilSys ID, or type their details if they have a different ID.',
          'I-scan ang kanilang PhilSys ID, o i-type ang detalye kung iba ang kanilang ID.', 'Pwede ninyo i-scan ang ila PhilSys ID, ukon i-type ang ila detalye kon lain ang ila ID.');
      actions = [
        _bigButton(tr('Scan PhilSys ID', 'I-scan ang PhilSys ID', 'I-scan ang PhilSys ID'), Icons.document_scanner_outlined, _scanId),
        _bigButton(tr('Type details', 'I-type ang detalye', 'I-type ang detalye'), Icons.keyboard_outlined, _addManually, outlined: true),
      ];
    } else if (unconfirmed.isNotEmpty) {
      final t = tanods[unconfirmed.first];
      icon = Icons.spellcheck_rounded;
      title = tr('Check the spelling of ${t.fullName}', 'Suriin ang baybay ng ${t.fullName}', 'Usisaa ang spelling sang ${t.fullName}');
      body = tr('The scan wasn’t sure about some letters. Compare the name with their ID, then save.',
          'Hindi sigurado ang scan sa ilang letra. Ikumpara ang pangalan sa kanilang ID, saka i-save.', 'Indi sigurado ang scan sa pila ka letra. Palihog ikumpara ang ngalan sa ila ID, dayon i-save.');
      actions = [_bigButton(tr('Check name', 'Suriin ang pangalan', 'Usisaa ang ngalan'), Icons.edit_outlined, () => _editTanod(unconfirmed.first))];
    } else if (lookAlikes.isNotEmpty) {
      icon = Icons.people_alt_outlined;
      title = tr('Are these two the same person?', 'Iisang tao ba ang dalawang ito?', 'Isa lang bala ka tawo ining duha?');
      body = lookAlikes.first.body;
      actions = [
        _bigButton(tr('Compare names', 'Ikumpara ang mga pangalan', 'Ikumpara ang mga ngalan'), Icons.compare_arrows_rounded,
            () => _reviewDuplicate(lookAlikes.first)),
      ];
    } else if (notDone.isNotEmpty) {
      final f = notDone.first;
      final k = f.kind;
      icon = f.outdated ? Icons.warning_amber_rounded : Icons.print_outlined;
      title = f.outdated
          ? tr('Print the new ${k.title} and have it signed again', 'I-print ang bagong ${k.title} at papirmahan ulit', 'I-print ang bag-o nga ${k.title} kag papirmahi liwat')
          : tr('Print the ${k.title} and have it signed', 'I-print ang ${k.title} at papirmahan', 'I-print ang ${k.title} kag papirmahi');
      body = tr('Download it, print it, and have it signed by hand. Then take a photo or upload a scan of the signed paper. '
              'It replaces the file here and becomes your backup.',
          'I-download, i-print, at papirmahan. Saka kunan ng litrato o i-upload ang scan ng pirmadong papel. '
              'Papalitan nito ang file dito at magiging backup ninyo.', 'Palihog i-download, i-print, kag papirmahi. Dayon kuhai sang litrato ukon i-upload ang scan sang may pirma nga papel. ' 'Ilisan sini ang file diri kag amo na ini ang inyo backup.');
      actions = [
        _bigButton(tr('Upload signed copy', 'I-upload ang pirmadong kopya', 'I-upload ang may pirma nga kopya'), Icons.photo_camera_outlined, () => _upload(k)),
        _bigButton(tr('Download to print', 'I-download para i-print', 'I-download para i-print'), Icons.download_rounded, () => _downloadPdf(k), outlined: true),
      ];
    } else if (pending) {
      icon = Icons.hourglass_top_rounded;
      title = tr('Wait for $kMunicipality to approve your account', 'Hintayin ang pag-apruba ng $kMunicipality', 'Hulat anay sa aprobasyon sang $kMunicipality sa inyo account');
      body = tr('Everything else is ready. You can submit as soon as your account is approved.',
          'Handa na ang lahat. Maipapasa ninyo kapag naaprubahan na ang inyong account.', 'Handa na ang tanan. Mapasa ninyo dayon kon maaprobahan na ang inyo account.');
    } else {
      icon = Icons.send_outlined;
      title = tr('Submit and bring the paper set to $kMunicipality', 'Ipasa at dalhin ang papel sa $kMunicipality', 'Ipasa kag dal-a ang papel sa $kMunicipality');
      body = tr('All four signed copies are uploaded. Submit here, then bring the signed papers to the MLGOO office.',
          'Na-upload na ang apat na pirmadong kopya. Ipasa dito, saka dalhin ang mga pirmadong papel sa tanggapan ng MLGOO.', 'Na-upload na ang apat ka may pirma nga kopya. Pwede na kamo magpasa diri, dayon dal-a ang may pirma nga papel sa opisina sang MLGOO.');
      actions = [_bigButton(tr('Submit to $kMunicipality', 'Ipasa sa $kMunicipality', 'Ipasa sa $kMunicipality'), Icons.send_outlined, _submit)];
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: C.yellow, width: 2),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: C.yellowDark.withValues(alpha: .18), blurRadius: 24, spreadRadius: -6, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          // FIX: shrinks with "…" instead of overflowing with large text
          Expanded(child: Text(tr('YOUR NEXT STEP', 'SUSUNOD NA HAKBANG', 'SUNOD NINYO NGA LAKANG'),
              style: sans(14, w: FontWeight.w800, color: const Color(0xFF8A6A00)).copyWith(letterSpacing: .8), overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          if (!locked)
            Text(tr('$done of ${steps.length} done', '$done sa ${steps.length} tapos na', '$done sa ${steps.length} tapos na'),
                style: sans(14.5, w: FontWeight.w600, color: C.muted)),
        ]),
        if (!locked) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: done / steps.length,
              minHeight: 6,
              backgroundColor: const Color(0xFFF1EBD6),
              valueColor: const AlwaysStoppedAnimation(C.yellowDark),
            ),
          ),
        ],
        const SizedBox(height: 18),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: const Color(0xFFFFF4CC), borderRadius: BorderRadius.circular(15)),
            child: Icon(icon, size: 26, color: C.navy),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: serif(23)),
              const SizedBox(height: 6),
              Text(body, style: sans(15.5, color: C.ink, h: 1.5)),
            ]),
          ),
        ]),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 18),
          Wrap(spacing: 10, runSpacing: 10, children: actions),
        ],
      ]),
    );
  }

  Future<void> _reviewDuplicate(_Issue issue) async {
    final key = issue.id.substring(4);
    final idx = [for (var i = 0; i < tanods.length; i++) if (tanods[i].nameKey == key) i];
    if (idx.length < 2) return;

    Widget entry(int i) => Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: C.mist, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Text(awardNo(i), style: sans(15, w: FontWeight.w800, color: C.navy)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tanods[i].fullName, style: sans(16, w: FontWeight.w700)),
                Text(tanods[i].idType, style: sans(14, color: C.muted)),
              ]),
            ),
          ]),
        );

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Same person?', 'Iisang tao ba?', 'Isa lang ka tawo?'), style: serif(24)),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              tr('These two names look alike. Check their IDs. A tanod can only be listed once.',
                  'Magkahawig ang dalawang pangalang ito. Tingnan ang kanilang ID. Isang beses lang maililista ang isang tanod.', 'Daw pareho ining duha ka ngalan. Palihog tan-awa ang ila ID. Isa lang ka beses malista ang isa ka tanod.'),
              style: sans(15, color: C.muted, h: 1.5),
            ),
            entry(idx[0]),
            entry(idx[1]),
          ]),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
            onPressed: () => Navigator.pop(ctx, 'different'),
            child: Text(tr('Different people', 'Magkaibang tao', 'Lain-lain nga tawo')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: C.red, foregroundColor: Colors.white, minimumSize: const Size(0, 46)),
            onPressed: () => Navigator.pop(ctx, 'same'),
            child: Text(tr('Same person: remove No. ${awardNo(idx[1])}', 'Iisa: tanggalin ang No. ${awardNo(idx[1])}', 'Isa lang: kuhaon ang No. ${awardNo(idx[1])}')),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'different') {
      setState(() {
        resolved.add(issue.id);
        pendingSync++;
        online = false;
      });
      _toast(tr('Marked as different people.', 'Itinala bilang magkaibang tao.', 'Ginmarkahan nga lain-lain nga tawo.'));
    } else {
      final name = tanods[idx[1]].fullName;
      setState(() {
        tanods.removeAt(idx[1]);
        _markChanged();
      });
      _toast(tr('Removed the second $name. Award numbers were updated.',
          'Tinanggal ang ikalawang $name. Na-update ang mga award number.', 'Ginkuha na ang ikaduha nga $name. Na-update na ang mga award number.'));
    }
  }

  Widget _welcome() {
    final h = DateTime.now().hour;
    final greet = h < 12
        ? tr('Good morning', 'Magandang umaga', 'Maayong aga')
        : (h < 18 ? tr('Good afternoon', 'Magandang hapon', 'Maayong hapon') : tr('Good evening', 'Magandang gabi', 'Maayong gab-i'));
    final now = DateTime.now();
    final days = DateTime(now.year, 12, 1).difference(DateTime(now.year, now.month, now.day)).inDays;

    final countdown = Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        border: Border.all(color: Colors.white.withValues(alpha: .16)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(days > 0 ? tr('$days days', '$days araw', '$days ka adlaw') : tr('December', 'Disyembre', 'Disyembre'), style: serif(30, color: C.yellow)),
        const SizedBox(height: 4),
        Text(days > 0 ? tr('until the December release', 'bago ang release sa Disyembre', 'antes ang release sa Disyembre') : tr('Release month is here', 'Buwan na ng release', 'Ari na ang bulan sang release'),
            style: sans(14.5, color: const Color(0xFFD3E0EE))),
      ]),
    );

    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: C.yellow.withValues(alpha: .18),
          border: Border.all(color: C.yellow.withValues(alpha: .5)),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text('Brgy. $kBarangay · $kMunicipality · $kRepPosition',
            style: sans(13.5, w: FontWeight.w600, color: const Color(0xFFFFE9A6))),
      ),
      const SizedBox(height: 14),
      Text('$greet, $kRepFirstName', style: serif(30, color: Colors.white)),
      const SizedBox(height: 8),
      Text(
        tr('You’re preparing the $kYear tanod incentive. Enter each tanod once and all four documents fill in by themselves.',
            'Inihahanda ninyo ang $kYear tanod incentive. Ilagay ang bawat tanod nang isang beses at kusang mapupunan ang apat na dokumento.', 'Ginahanda ninyo ang $kYear tanod incentive. Isulod lang ang kada tanod sing makaisa kag kusa na nga mapun-an ang apat ka dokumento.'),
        style: sans(15, color: const Color(0xFFD3E0EE), h: 1.5),
      ),
      const SizedBox(height: 20),
      Wrap(spacing: 10, runSpacing: 10, children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: C.yellow,
            foregroundColor: C.navy,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: sans(15, w: FontWeight.w700),
          ),
          onPressed: _scanId,
          icon: const Icon(Icons.document_scanner_outlined, size: 18),
          label: Text(tr('Scan PhilSys ID', 'I-scan ang PhilSys ID', 'I-scan ang PhilSys ID')),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: .35)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: sans(15, w: FontWeight.w600),
          ),
          onPressed: _addManually,
          icon: const Icon(Icons.keyboard_outlined, size: 18),
          label: Text(tr('Type details (other ID)', 'I-type (ibang ID)', 'I-type ang detalye (iban nga ID)')),
        ),
      ]),
    ]);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [C.navy, Color(0xFF173E66)],
          ),
        ),
        child: Stack(children: [
          Positioned(
            right: -30,
            top: -30,
            child: Icon(Icons.shield_outlined, size: 220, color: Colors.white.withValues(alpha: .05)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 26, 26, 30),
            child: LayoutBuilder(builder: (context, box) {
              if (box.maxWidth < 640) {
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  text,
                  const SizedBox(height: 20),
                  countdown,
                ]);
              }
              return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(child: text),
                const SizedBox(width: 28),
                countdown,
              ]);
            }),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 5,
            child: Row(children: [
              Expanded(flex: 34, child: ColoredBox(color: C.yellow)),
              Expanded(flex: 33, child: ColoredBox(color: C.green)),
              Expanded(flex: 33, child: ColoredBox(color: C.blue)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget? _statusBanner() {
    if (corrections) return _correctionsBanner();
    if (pending) {
      return _notice(
        const Color(0xFFFFF8E1),
        const Color(0xFFF3DE9A),
        C.yellowDark,
        const Color(0xFF5C4400),
        Icons.hourglass_top_rounded,
        tr('Waiting for $kMunicipality to approve your account', 'Hinihintay ang pag-apruba ng $kMunicipality sa inyong account', 'Ginahulat nga aprobahan sang $kMunicipality ang inyo account'),
        tr('You can already encode tanods, print and upload. Submitting unlocks once the municipality checks your proof of designation.',
            'Puwede na kayong maglagay ng tanod, mag-print at mag-upload. Mabubuksan ang pagpasa kapag nasuri na ng munisipyo ang inyong patunay.', 'Pwede na kamo magsulod sang tanod, mag-print kag mag-upload. Mabuksan ang pagpasa kon nausisa na sang munisipyo ang inyo pamatuod sang designation.'),
      );
    }
    return switch (rec.status) {
      BrgyStatus.checked => _notice(C.greenSoft, const Color(0xFFBFE5D1), C.green, const Color(0xFF14583D), Icons.verified_outlined,
          tr('Checked by $kMunicipality', 'Nasuri na ng $kMunicipality', 'Nausisa na sang $kMunicipality'),
          tr('Your paper set is complete and correct. $kMunicipality will bring all barangays’ paper sets to OPPDC together.',
              'Kumpleto at tama ang inyong papel. Sabay-sabay na dadalhin ng $kMunicipality sa OPPDC ang set ng lahat ng barangay.', 'Kompleto kag husto ang inyo papel. Dungan nga dal-on sang $kMunicipality sa OPPDC ang papel sang tanan nga barangay.')),
      BrgyStatus.sentToOppdc => _notice(C.blueSoft, const Color(0xFFC9DBEF), C.blue, const Color(0xFF1B3F68), Icons.local_shipping_outlined,
          tr('Your paper set is with OPPDC', 'Nasa OPPDC na ang inyong papel', 'Ara na sa OPPDC ang inyo papel'),
          tr('$kMunicipality brought every barangay’s paper set to OPPDC. OPPDC can also open your uploaded copies as a backup.',
              'Dinala ng $kMunicipality sa OPPDC ang papel ng bawat barangay. Mabubuksan din ng OPPDC ang inyong na-upload na kopya bilang backup.', 'Gindala sang $kMunicipality sa OPPDC ang papel sang kada barangay. Mabuksan man sang OPPDC ang inyo na-upload nga kopya bilang backup.')),
      BrgyStatus.released => _notice(C.greenSoft, const Color(0xFFBFE5D1), C.green, const Color(0xFF14583D), Icons.celebration_outlined,
          tr('Incentive released', 'Na-release na ang incentive', 'Na-release na ang incentive'),
          tr('${tanods.length} tanods received ${peso(kAmountEach)} each for $kYear. Thank you for a clean submission.',
              '${tanods.length} tanod ang nakatanggap ng ${peso(kAmountEach)} bawat isa para sa $kYear. Salamat sa maayos na pagpasa.', '${tanods.length} ka tanod ang nakabaton sang ${peso(kAmountEach)} kada isa para sa $kYear. Salamat sa matinlo nga pagpasa.')),
      _ => null,
    };
  }

  Widget _notice(Color bg, Color border, Color iconColor, Color textColor, IconData icon, String title, String body) =>
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .7), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: sans(16.5, w: FontWeight.w700, color: textColor)),
              const SizedBox(height: 3),
              Text(body, style: sans(14.5, color: textColor, h: 1.45)),
            ]),
          ),
        ]),
      );

  // The municipality found mistakes on the paper copy.
  Widget _correctionsBanner() {
    const red = Color(0xFF8E2A22);
    final asked = [for (final f in rec.files.values) if (rec.lastAbout(f.kind) != null && (f.correction || f.version > 1)) f];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFDF0EE),
        border: Border.all(color: const Color(0xFFF0C7C3)),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.assignment_return_outlined, color: C.red, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('$kMunicipality found mistakes on your paper copy', 'May nakitang mali ang $kMunicipality sa inyong papel', 'May nakita nga sala ang $kMunicipality sa inyo papel nga kopya'),
                  style: sans(17.5, w: FontWeight.w700, color: red)),
              const SizedBox(height: 3),
              Text(
                  tr('Fix only what’s listed. Correct the paper, upload the corrected copy so the backup matches, then tell $kMunicipality.',
                      'Ang nakalista lang ang aayusin. Itama ang papel, i-upload ang naitamang kopya para tugma ang backup, saka sabihan ang $kMunicipality.', 'Ang nalista lang ang tadlungon. Palihog tadlunga ang papel, i-upload ang natadlong nga kopya para pareho ang backup, dayon ipahibalo sa $kMunicipality.'),
                  style: sans(14.5, color: red, h: 1.45)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        for (final f in asked)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: f.correction ? const Color(0xFFF0C7C3) : const Color(0xFFBFE5D1)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: LayoutBuilder(builder: (context, box) {
              final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _pill(f.kind.title, f.correction ? const Color(0xFFFDF0EE) : C.greenSoft,
                    f.correction ? C.red : const Color(0xFF14583D), icon: f.kind.icon),
                const SizedBox(height: 6),
                Text(rec.lastAbout(f.kind)?.text ?? '', style: sans(14.5, color: C.ink, h: 1.45)),
              ]);
              final action = f.correction
                  ? FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: C.yellow,
                        foregroundColor: C.navy,
                        minimumSize: const Size(0, 46),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                      ),
                      onPressed: () => _upload(f.kind),
                      icon: const Icon(Icons.upload_rounded, size: 18),
                      label: Text(tr('Upload corrected copy', 'I-upload ang naitamang kopya', 'I-upload ang natadlong nga kopya'),
                          style: sans(14.5, w: FontWeight.w700, color: C.navy)),
                    )
                  : _pill(tr('Corrected copy uploaded', 'Na-upload ang naitama', 'Na-upload ang natadlong nga kopya'), C.greenSoft, const Color(0xFF14583D),
                      icon: Icons.check);
              if (box.maxWidth < 560) {
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [info, const SizedBox(height: 10), action]);
              }
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: info),
                const SizedBox(width: 10),
                action,
              ]);
            }),
          ),
        const SizedBox(height: 6),
        Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: C.navy,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE3EAF2),
              disabledForegroundColor: const Color(0xFF97A5B5),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              minimumSize: const Size(0, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: sans(15, w: FontWeight.w700),
            ),
            onPressed: canSendBack ? _sendBack : null,
            icon: const Icon(Icons.send_outlined, size: 18),
            label: Text(canSendBack
                ? tr('Corrections done: tell $kMunicipality', 'Tapos na: sabihan ang $kMunicipality', 'Tapos na ang pagtadlong: ipahibalo sa $kMunicipality')
                : tr('Upload every corrected copy first', 'I-upload muna ang lahat ng naitama', 'Palihog i-upload anay ang tanan nga natadlong nga kopya')),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: C.navy,
              side: const BorderSide(color: C.line, width: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              minimumSize: const Size(0, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _go(_messagesTab),
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
            label: Text(tr('Open messages', 'Buksan ang mensahe', 'Buksan ang mensahe'), style: sans(15, w: FontWeight.w600, color: C.navy)),
          ),
        ]),
      ]),
    );
  }

  Widget _statusPanel() {
    final notes = [
      tr('Nothing has been sent yet. Follow “Your next step” at the top.', 'Wala pang naipapasa. Sundan ang “Susunod na hakbang” sa itaas.', 'Wala pa sang ginpadala. Sunda lang ang “Sunod ninyo nga lakang” sa ibabaw.'),
      tr('$kMunicipality is checking your paper set. Mistakes they find will come as messages.',
          'Sinusuri ng $kMunicipality ang inyong papel. Darating bilang mensahe ang anumang mali.', 'Ginausisa sang $kMunicipality ang inyo papel. Ang mga sala nga makita nila maabot bilang mensahe.'),
      tr('Checked by $kMunicipality. It will bring all barangays’ paper sets to OPPDC together.',
          'Nasuri na ng $kMunicipality. Sabay-sabay nitong dadalhin sa OPPDC ang papel ng lahat ng barangay.', 'Nausisa na sang $kMunicipality. Dungan nga dal-on ini sa OPPDC upod ang papel sang tanan nga barangay.'),
      tr('OPPDC has the paper sets. It can also open your uploaded copies as a backup.',
          'Nasa OPPDC na ang mga papel. Mabubuksan din nito ang inyong na-upload na kopya bilang backup.', 'Ara sa OPPDC ang papel. Mabuksan man sini ang inyo na-upload nga kopya bilang backup.'),
      tr('The incentive has been released.', 'Na-release na ang incentive.', 'Na-release na ang incentive.'),
    ];
    return _Panel(
      title: tr('Submission Status', 'Kalagayan ng Pagpasa', 'Status sang imo Pagpasa'),
      icon: Icons.route_outlined,
      help: tr(
          'You prepare the documents, upload the signed copies, and bring the paper set to $kMunicipality. The municipality '
              'checks the paper and messages you about any mistake. When every barangay is checked, $kMunicipality brings all '
              'the paper sets to OPPDC together. Your uploaded copies are the backup everyone can open.',
          'Ihahanda ninyo ang dokumento, ia-upload ang pirmadong kopya, at dadalhin ang papel sa $kMunicipality. Susuriin ng '
              'munisipyo ang papel at magme-message kung may mali. Kapag nasuri na ang lahat ng barangay, sabay-sabay itong dadalhin '
              'ng $kMunicipality sa OPPDC. Ang na-upload na kopya ang backup na mabubuksan ng lahat.', 'Kamo ang maghanda sang dokumento, mag-upload sang may pirma nga kopya, kag magdala sang papel sa $kMunicipality. Usisaon sang munisipyo ' 'ang papel kag magmensahe sa inyo kon may sala. Kon nausisa na ang tanan nga barangay, dungan nga dal-on sang $kMunicipality ' 'ang tanan nga papel sa OPPDC. Ang inyo na-upload nga kopya ang backup nga mabuksan sang tanan.'),
      trailing: corrections
          ? _pill(tr('Corrections', 'May itatama', 'Pagtadlong'), const Color(0xFFFDF0EE), C.red, icon: Icons.assignment_return_outlined)
          : pending
              ? _pill(tr('Awaiting approval', 'Hinihintay ang apruba', 'Ginahulat ang aprobasyon'), const Color(0xFFFFF4CC), const Color(0xFF7A5B00))
              : stage == 4
                  ? _pill(tr('Released', 'Na-release', 'Na-release'), C.greenSoft, const Color(0xFF14583D), icon: Icons.check)
                  : _pill(_stepName(stage), const Color(0xFFFFF4CC), const Color(0xFF7A5B00)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _StatusTracker(current: stage, correctionsAt: corrections ? 1 : null),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: C.blueSoft, borderRadius: BorderRadius.circular(12)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 1), child: Icon(Icons.info_outline, size: 18, color: C.blue)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                corrections
                    ? tr('$kMunicipality asked for corrections. Editing and uploading are open until you send them back.',
                        'Humiling ng pagtatama ang $kMunicipality. Bukas ang pag-edit at pag-upload hanggang maipasa ulit.', 'Nagpangayo ang $kMunicipality sang pagtadlong. Bukas ang pag-edit kag pag-upload tubtob ipadala ninyo liwat.')
                    : pending
                        ? tr('Your account is waiting for $kMunicipality’s approval. You can prepare everything in the meantime.',
                            'Hinihintay ang apruba ng $kMunicipality sa inyong account. Puwede na kayong maghanda.', 'Ginahulat ang aprobasyon sang $kMunicipality sa inyo account. Pwede ninyo mahanda ang tanan samtang.')
                        : notes[stage],
                style: sans(14.5, color: const Color(0xFF1B3F68), h: 1.45),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _stats() {
    final count = tanods.length;
    final alertCount = alerts.length;
    final tiles = [
      _StatTile(
        icon: Icons.groups_outlined,
        tint: C.blue,
        value: '$count / $kQuota',
        label: tr('Tanods listed', 'Nakalistang tanod', 'Nalista nga tanod'),
        note: tr('Up to $kQuota allowed', 'Hanggang $kQuota ang puwede', 'Tubtob $kQuota ang gintugot'),
        help: tr('OPPDC sets how many tanods each barangay can list this year. For Brgy. $kBarangay it’s $kQuota. '
                'Gawad stops you from adding more.',
            'Ang OPPDC ang nagtatakda kung ilang tanod ang puwedeng ilista ng bawat barangay ngayong taon. '
                'Sa Brgy. $kBarangay, $kQuota ito. Hindi na kayo makakapagdagdag lampas dito.', 'Ang OPPDC ang nagatakda kon pila ka tanod ang malista sang kada barangay subong nga tuig. Sa Brgy. $kBarangay, $kQuota ini. ' 'Indi na makadugang ang Gawad kon puno na.'),
        progress: count / kQuota,
      ),
      _StatTile(
        icon: Icons.payments_outlined,
        tint: C.green,
        value: peso(count * kAmountEach),
        label: tr('Payroll total', 'Kabuuang payroll', 'Kabilugan sang payroll'),
        note: tr('${peso(kAmountEach)} each × $count', '${peso(kAmountEach)} bawat isa × $count', '${peso(kAmountEach)} kada isa × $count'),
      ),
      _StatTile(
        icon: Icons.inventory_2_outlined,
        tint: C.yellowDark,
        value: '${rec.backupCount} / 4',
        label: tr('Signed copies uploaded', 'Na-upload na pirmadong kopya', 'Na-upload nga may pirma nga kopya'),
        note: tr('Backup of the signed paper', 'Backup ng pirmadong papel', 'Backup sang may pirma nga papel'),
        progress: rec.backupCount / 4,
      ),
      _StatTile(
        icon: alertCount == 0 ? Icons.verified_outlined : Icons.error_outline,
        tint: alertCount == 0 ? C.green : C.red,
        value: '$alertCount',
        label: tr('Alerts', 'Mga paalala', 'Mga pahanumdom'),
        note: alertCount == 0 ? tr('All clear', 'Ayos na lahat', 'Wala sang problema') : tr('See the alerts below', 'Tingnan sa ibaba', 'Palihog tan-awa ang mga pahanumdom sa idalom'),
      ),
    ];
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 900 ? 4 : (box.maxWidth >= 480 ? 2 : 1);
      final tw = ((box.maxWidth - 16 * (cols - 1)) / cols).floorToDouble();
      return Wrap(spacing: 16, runSpacing: 16, children: [for (final t in tiles) SizedBox(width: tw, child: t)]);
    });
  }

  // ---------- Signed copies (backup) checklist ----------
  Widget _backupPanel() {
    return _Panel(
      title: tr('Signed copies (backup)', 'Pirmadong kopya (backup)', 'May pirma nga kopya (backup)'),
      icon: Icons.inventory_2_outlined,
      help: tr(
          'After the paper is signed, upload a photo or scan of it. The upload replaces the file in Gawad and is the backup '
              'copy. $kMunicipality checks the paper you bring; it and OPPDC can open these backups any time.',
          'Kapag napirmahan na ang papel, i-upload ang litrato o scan nito. Papalitan nito ang file sa Gawad at ito ang backup. '
              'Ang papel na dala ninyo ang susuriin ng $kMunicipality; mabubuksan nito at ng OPPDC ang backup anumang oras.', 'Pagkatapos mapirmahan ang papel, palihog i-upload ang litrato ukon scan sini. Ilisan sini ang file sa Gawad kag amo ini ang backup ' 'nga kopya. Usisaon sang $kMunicipality ang papel nga dal-on ninyo; mabuksan nila kag sang OPPDC ining backup bisan san-o.'),
      trailing: Text(tr('${rec.backupCount} of 4 done', '${rec.backupCount} sa 4 tapos', '${rec.backupCount} sa 4 tapos na'),
          style: sans(14.5, w: FontWeight.w600, color: C.muted)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Download → print → sign → upload a photo. Each upload is your backup of the signed paper.',
                'I-download → i-print → papirmahan → i-upload ang litrato. Ang bawat upload ang backup ng pirmadong papel.', 'I-download → i-print → papirmahi → i-upload ang litrato. Ang kada upload amo ang inyo backup sang may pirma nga papel.'),
            style: sans(14.5, color: C.muted, h: 1.5)),
        const SizedBox(height: 16),
        for (final f in rec.files.values) ...[_backupRow(f), const SizedBox(height: 10)],
      ]),
    );
  }

  Widget _backupRow(DocFile f) {
    final k = f.kind;
    final (Color bg, Color border, Color tint, IconData icon, String status) = f.correction
        ? (const Color(0xFFFDF0EE), const Color(0xFFF0C7C3), C.red, Icons.assignment_return_outlined,
            tr('$kMunicipality asked for a corrected copy', 'Humiling ang $kMunicipality ng naitamang kopya', 'Nagpangayo ang $kMunicipality sang natadlong nga kopya'))
        : f.outdated
            ? (const Color(0xFFFFF8E1), const Color(0xFFF3DE9A), C.yellowDark, Icons.warning_amber_rounded,
                tr('Out of date: print, sign and upload again', 'Luma na: i-print, papirmahan at i-upload ulit', 'Daan na: palihog i-print, papirmahi kag i-upload liwat'))
            : f.uploaded
                ? (const Color(0xFFF4FBF7), const Color(0xFFBFE5D1), C.green, Icons.check_rounded,
                    tr('Uploaded ${f.uploadedOn}${f.version > 1 ? ' · version ${f.version}' : ''}',
                        'Na-upload ${f.uploadedOn}${f.version > 1 ? ' · bersyon ${f.version}' : ''}', 'Na-upload ${f.uploadedOn}${f.version > 1 ? ' · bersyon ${f.version}' : ''}'))
                : (Colors.white, C.line, C.navy, k.icon,
                    tr('Ready to print for signing', 'Handa nang i-print para pirmahan', 'Handa na i-print para pirmahan'));
    final canUpload = !locked || f.correction;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: f.done ? C.green : tint.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 21, color: f.done ? Colors.white : tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(k.title, style: sans(16, w: FontWeight.w700, color: C.navy)),
              const SizedBox(height: 2),
              Text(status, style: sans(14, color: f.done ? const Color(0xFF14583D) : (f.uploaded || f.correction ? tint : C.muted))),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: C.navy,
              side: const BorderSide(color: C.line, width: 1.5),
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
            ),
            onPressed: () => _downloadPdf(k),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(tr('Download', 'I-download', 'I-download'), style: sans(14.5, w: FontWeight.w600, color: C.navy)),
          ),
          if (f.uploaded)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: C.navy,
                side: const BorderSide(color: C.line, width: 1.5),
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
              ),
              onPressed: () => showBackupCopy(context, rec: rec, kind: k),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: Text(tr('View backup', 'Tingnan ang backup', 'Tan-awa ang backup'), style: sans(14.5, w: FontWeight.w600, color: C.navy)),
            ),
          if (!f.done)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: f.correction || f.outdated ? C.yellow : C.navy,
                foregroundColor: f.correction || f.outdated ? C.navy : Colors.white,
                disabledBackgroundColor: const Color(0xFFE3EAF2),
                disabledForegroundColor: const Color(0xFF97A5B5),
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                textStyle: sans(14.5, w: FontWeight.w700),
              ),
              onPressed: canUpload ? () => _upload(k) : null,
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: Text(f.correction
                  ? tr('Upload corrected copy', 'I-upload ang naitamang kopya', 'I-upload ang natadlong nga kopya')
                  : tr('Upload signed copy', 'I-upload ang pirmadong kopya', 'I-upload ang may pirma nga kopya')),
            ),
        ]),
      ]),
    );
  }

  // ---------- Alerts (only what is wrong) ----------
  Widget _alertsPanel() {
    final list = alerts;
    return _Panel(
      title: tr('Alerts', 'Mga paalala', 'Mga pahanumdom'),
      icon: Icons.notifications_active_outlined,
      help: tr(
          'Gawad warns you about mistakes that would get the whole municipality’s set returned, like look-alike names, '
              'unchecked spelling, too many tanods, and signed copies that no longer match the list. Fix these before you submit.',
          'Nagbababala ang Gawad sa mga maling magpapabalik sa buong set ng munisipyo, gaya ng magkahawig na pangalan, '
              'hindi pa nasusuring baybay, sobrang tanod, at pirmadong kopyang hindi na tugma. Ayusin ito bago magpasa.', 'Ginapahibalo kamo sang Gawad sa mga sala nga basi makapabalik sang set sang bug-os nga munisipyo, pareho sang daw pareho nga ngalan, ' 'wala nausisa nga spelling, sobra nga tanod, kag may pirma nga kopya nga indi na pareho sa listahan. Palihog tadlunga ini antes magpasa.'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (list.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: C.greenSoft, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.verified_outlined, color: C.green, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(tr('No problems found.', 'Walang nakitang problema.', 'Wala sang nakita nga problema.'),
                    style: sans(15, w: FontWeight.w600, color: const Color(0xFF14583D))),
              ),
            ]),
          ),
        for (final a in list) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            decoration: BoxDecoration(
              color: a.red ? const Color(0xFFFDF0EE) : const Color(0xFFFFF8E1),
              border: Border.all(color: a.red ? const Color(0xFFF0C7C3) : const Color(0xFFF3DE9A)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(a.icon, size: 20, color: a.red ? C.red : const Color(0xFF7A5B00)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.title, style: sans(15, w: FontWeight.w700, color: a.red ? const Color(0xFF8E2A22) : const Color(0xFF5C4400))),
                    const SizedBox(height: 2),
                    Text(a.body, style: sans(14, color: a.red ? const Color(0xFF8E2A22) : const Color(0xFF6B5A2A), h: 1.4)),
                  ]),
                ),
              ]),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: a.onAction,
                  child: Text(a.action, style: sans(14.5, w: FontWeight.w700, color: a.onAction == null ? C.muted : C.blue)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
        ],
      ]),
    );
  }

  // ---------- Latest messages ----------
  Widget _messagesPreview() {
    final recent = rec.chat.length <= 2 ? rec.chat : rec.chat.sublist(rec.chat.length - 2);
    return _Panel(
      title: tr('Messages from $kMunicipality', 'Mensahe mula sa $kMunicipality', 'Mensahe halin sa $kMunicipality'),
      icon: Icons.chat_bubble_outline_rounded,
      trailing: TextButton(
        style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
        onPressed: () => _go(_messagesTab),
        child: Text(
          rec.unreadBrgy > 0 ? tr('Open (${rec.unreadBrgy} new)', 'Buksan (${rec.unreadBrgy} bago)', 'Buksan (${rec.unreadBrgy} bag-o)') : tr('Open', 'Buksan', 'Buksan'),
          style: sans(14.5, w: FontWeight.w700, color: C.blue),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (recent.isEmpty) Text(tr('No messages yet.', 'Wala pang mensahe.', 'Wala pa sang mensahe.'), style: sans(14.5, color: C.muted)),
        for (final m in recent)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE9EFF5)))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: m.fromMunicipality ? C.navy : C.yellow,
                child: Icon(m.system ? Icons.info_outline : (m.fromMunicipality ? Icons.account_balance_outlined : Icons.person_outline),
                    size: 16, color: m.fromMunicipality ? Colors.white : C.navy),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    '${m.fromMunicipality ? tr('$kMunicipality reviewer', 'Reviewer ng $kMunicipality', 'Reviewer sang $kMunicipality') : tr('You', 'Kayo', 'Kamo')} · ${m.time}',
                    style: sans(13, w: FontWeight.w600, color: C.muted),
                  ),
                  const SizedBox(height: 2),
                  Text(m.doc == null ? m.text : '${m.doc!.title}: ${m.text}',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: sans(14.5, color: C.ink, h: 1.4)),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _tanodPanel({int? limit}) {
    final shown = limit == null ? tanods : tanods.take(limit).toList();
    final slots = kQuota - tanods.length;
    return _Panel(
      title: tr('Tanods', 'Mga Tanod', 'Mga Tanod'),
      icon: Icons.groups_outlined,
      help: tr(
          'Each tanod gets an award number (001, 002…) in the order they’re listed. Gawad assigns it and '
              'renumbers by itself when someone is removed. You can list up to $kQuota tanods this year.',
          'Bawat tanod ay may award number (001, 002…) ayon sa pagkakasunod sa listahan. Kusang inaayos ito ng '
              'Gawad kapag may tinanggal. Hanggang $kQuota tanod ang puwedeng ilista ngayong taon.', 'Ang kada tanod may award number (001, 002…) suno sa pagkasunod sang listahan. Ang Gawad ang maghatag sini kag ' 'kusa nga magilis sang numero kon may ginkuha. Tubtob $kQuota ka tanod ang malista ninyo subong nga tuig.'),
      trailing: limit != null
          ? TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => _go(1),
              child: Text(tr('See all ${tanods.length}', 'Tingnan lahat (${tanods.length})', 'Tan-awa ang tanan nga ${tanods.length}'),
                  style: sans(14.5, w: FontWeight.w700, color: C.blue)),
            )
          : Text(slots > 0 ? tr('$slots more allowed', '$slots pa ang puwede', '$slots pa ang pwede') : tr('Limit reached', 'Puno na', 'Puno na'),
              style: sans(14.5, w: FontWeight.w600, color: slots > 0 ? C.muted : C.red)),
      child: LayoutBuilder(builder: (context, box) {
        final actions = limit == null; // Edit / Remove only on the Tanods page
        final table = box.maxWidth >= (actions ? 800 : 620);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (table)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: C.mist, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                SizedBox(width: 64, child: Text(tr('NO.', 'BLG.', 'NO.'), style: _th)),
                Expanded(flex: 3, child: Text(tr('NAME', 'PANGALAN', 'NGALAN'), style: _th)),
                Expanded(flex: 2, child: Text(tr('ID PRESENTED', 'ID NA IPINAKITA', 'ID NGA GINPAKITA'), style: _th)),
                SizedBox(width: 150, child: Text(tr('STATUS', 'KALAGAYAN', 'KAHIMTANGAN'), style: _th)),
                if (actions) SizedBox(width: 230, child: Text('', style: _th)),
              ]),
            ),
          for (var i = 0; i < shown.length; i++)
            table ? _tanodRow(i, shown[i], actions) : _tanodTile(i, shown[i], actions),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: C.navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: locked ? null : _scanId,
              icon: const Icon(Icons.document_scanner_outlined, size: 18),
              label: Text(tr('Scan PhilSys ID', 'I-scan ang PhilSys ID', 'I-scan ang PhilSys ID'), style: sans(15, w: FontWeight.w600, color: Colors.white)),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: C.navy,
                side: const BorderSide(color: C.line, width: 1.5),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: locked ? null : _addManually,
              icon: const Icon(Icons.keyboard_outlined, size: 18),
              label: Text(tr('Type details (other ID)', 'I-type (ibang ID)', 'I-type ang detalye (iban nga ID)'), style: sans(15, w: FontWeight.w600, color: C.navy)),
            ),
          ]),
        ]);
      }),
    );
  }

  TextStyle get _th => sans(12.5, w: FontWeight.w700, color: C.muted).copyWith(letterSpacing: .6);

  Widget _statusPill(Tanod t) => t.confirmed
      ? _pill(tr('Checked', 'Nasuri na', 'Nausisa na'), C.greenSoft, const Color(0xFF14583D), icon: Icons.check)
      : _pill(tr('Check spelling', 'Suriin ang baybay', 'Usisaa ang spelling'), const Color(0xFFFFF4CC), const Color(0xFF7A5B00), icon: Icons.error_outline);

  Widget _avatar(Tanod t) => CircleAvatar(
        radius: 17,
        backgroundColor: C.blueSoft,
        child: Text(t.initials, style: sans(13, w: FontWeight.w700, color: C.blue)),
      );

  Widget _tanodRow(int i, Tanod t, bool actions) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE9EFF5)))),
        child: Row(children: [
          SizedBox(width: 64, child: Text(awardNo(i), style: sans(14.5, w: FontWeight.w700, color: C.navy))),
          Expanded(
            flex: 3,
            child: Row(children: [
              _avatar(t),
              const SizedBox(width: 10),
              Expanded(child: Text(t.fullName, overflow: TextOverflow.ellipsis, style: sans(15, w: FontWeight.w600))),
            ]),
          ),
          Expanded(flex: 2, child: Text(t.idType, overflow: TextOverflow.ellipsis, style: sans(14.5, color: C.muted))),
          SizedBox(
            width: 150,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: _statusPill(t)),
            ),
          ),
          if (actions)
            SizedBox(
              width: 230,
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                _rowButton(tr('Edit', 'Baguhin', 'I-edit'), Icons.edit_outlined, C.blue, locked ? null : () => _editTanod(i)),
                _rowButton(tr('Remove', 'Tanggalin', 'Kuhaon'), Icons.delete_outline, C.red, locked ? null : () => _removeTanod(i)),
              ]),
            ),
        ]),
      );

  Widget _rowButton(String label, IconData icon, Color color, VoidCallback? onPressed) => TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: color,
          backgroundColor: onPressed == null ? null : color.withValues(alpha: .08),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: const Size(0, 42),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label, style: sans(14.5, w: FontWeight.w600, color: onPressed == null ? C.muted : color)),
      );

  Widget _tanodTile(int i, Tanod t, bool actions) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE9EFF5)))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            _avatar(t),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.fullName, overflow: TextOverflow.ellipsis, style: sans(15.5, w: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('No. ${awardNo(i)} · ${t.idType}', overflow: TextOverflow.ellipsis, style: sans(14.5, color: C.muted)),
              ]),
            ),
            const SizedBox(width: 8),
            FittedBox(fit: BoxFit.scaleDown, child: _statusPill(t)),
          ]),
          if (actions) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 46),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                _rowButton(tr('Edit', 'Baguhin', 'I-edit'), Icons.edit_outlined, C.blue, locked ? null : () => _editTanod(i)),
                _rowButton(tr('Remove', 'Tanggalin', 'Kuhaon'), Icons.delete_outline, C.red, locked ? null : () => _removeTanod(i)),
              ]),
            ),
          ],
        ]),
      );

  Future<void> _editTanod(int i) async {
    final t = tanods[i];
    final first = TextEditingController(text: t.first);
    final middle = TextEditingController(text: t.middle);
    final last = TextEditingController(text: t.last);
    final formKey = GlobalKey<FormState>();
    var idType = kIdTypes.contains(t.idType) ? t.idType : kIdTypes.first;
    final signedAlready = rec.files.values.any((f) => f.uploaded);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Edit tanod', 'Baguhin ang tanod', 'I-edit ang tanod'), style: serif(24)),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    tr('Award no. ${awardNo(i)}. Changes update the Payroll, Masterlist, Certification and ID sheet.',
                        'Award no. ${awardNo(i)}. Maa-update ang Payroll, Masterlist, Certification at ID sheet.', 'Award no. ${awardNo(i)}. Ang pagbag-o ma-update sa Payroll, Masterlist, Certification kag ID sheet.'),
                    style: sans(14.5, color: C.muted, h: 1.5)),
                if (!t.confirmed) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(10)),
                    child: Text(
                        tr('Compare with the original ID. Saving marks this name as checked.',
                            'Ikumpara sa orihinal na ID. Kapag na-save, itatalang nasuri na ang pangalan.', 'Palihog ikumpara sa orihinal nga ID. Kon i-save, mamarkahan ini nga ngalan nga nausisa na.'),
                        style: sans(14.5, color: const Color(0xFF5C4400), h: 1.4)),
                  ),
                ],
                if (signedAlready) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(10)),
                    child: Text(
                        tr('Signed copies are already uploaded. After this change, print the new versions, have them signed, and upload them again.',
                            'May na-upload nang pirmadong kopya. Pagkatapos nito, i-print ang bagong bersyon, papirmahan, at i-upload ulit.', 'May na-upload na nga may pirma nga kopya. Pagkatapos sini nga pagbag-o, palihog i-print ang bag-o nga bersyon, papirmahi, kag i-upload liwat.'),
                        style: sans(14.5, color: const Color(0xFF5C4400), h: 1.4)),
                  ),
                ],
                const SizedBox(height: 18),
                AppField(
                  label: tr('First name', 'Pangalan', 'Ngalan'),
                  icon: Icons.person_outline,
                  controller: first,
                  validator: (v) => (v ?? '').trim().isEmpty ? tr('Enter the first name.', 'Ilagay ang pangalan.', 'Palihog isulat ang ngalan.') : null,
                ),
                const SizedBox(height: 14),
                AppField(
                  label: tr('Middle initial', 'Gitnang inisyal', 'Inisyal sang tunga nga ngalan'),
                  icon: Icons.short_text,
                  controller: middle,
                  maxLength: 1,
                  required: false,
                  optional: true,
                ),
                const SizedBox(height: 14),
                AppField(
                  label: tr('Last name', 'Apelyido', 'Apelyido'),
                  icon: Icons.person_outline,
                  controller: last,
                  validator: (v) => (v ?? '').trim().isEmpty ? tr('Enter the last name.', 'Ilagay ang apelyido.', 'Palihog isulat ang apelyido.') : null,
                ),
                const SizedBox(height: 14),
                FieldLabel(tr('ID type', 'Uri ng ID', 'Klase sang ID')),
                DropdownButtonFormField<String>(
                  initialValue: idType,
                  isExpanded: true,
                  style: sans(15),
                  dropdownColor: Colors.white,
                  decoration: fieldDecoration('', Icons.badge_outlined),
                  items: kIdTypes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => idType = v ?? idType,
                ),
              ]),
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancel', 'Kanselahin', 'Kanselaha'), style: sans(14.5, w: FontWeight.w600, color: C.muted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: C.navy, foregroundColor: Colors.white),
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: Text(tr('Save changes', 'I-save', 'I-save ang pagbag-o')),
          ),
        ],
      ),
    );

    if (saved == true && mounted) {
      final changedName = t.first != first.text.trim() ||
          t.middle != middle.text.trim().toUpperCase() ||
          t.last != last.text.trim() ||
          t.idType != idType;
      setState(() {
        t
          ..first = first.text.trim()
          ..middle = middle.text.trim().toUpperCase()
          ..last = last.text.trim()
          ..idType = idType
          ..confirmed = true;
        if (changedName) {
          _markChanged();
        } else {
          pendingSync++;
          online = false;
        }
      });
      _toast(tr('Saved ${t.fullName}. All documents were updated.', 'Na-save si ${t.fullName}. Na-update ang lahat ng dokumento.', 'Na-save si ${t.fullName}. Na-update ang tanan nga dokumento.'));
    }

    Future.delayed(const Duration(milliseconds: 400), () {
      first.dispose();
      middle.dispose();
      last.dispose();
    });
  }

  Future<void> _removeTanod(int i) async {
    final t = tanods[i];
    final after = tanods.length - i - 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Remove ${t.fullName}?', 'Tanggalin si ${t.fullName}?', 'Kuhaon si ${t.fullName}?'), style: serif(22)),
        content: Text(
          tr(
              'They will be taken off the Payroll, Masterlist, Certification and ID sheet.'
                  '${after > 0 ? ' The $after tanod${after == 1 ? '' : 's'} after award no. ${awardNo(i)} will move up one number.' : ''}',
              'Matatanggal siya sa Payroll, Masterlist, Certification at ID sheet.'
                  '${after > 0 ? ' Aakyat ng isang numero ang $after tanod pagkatapos ng award no. ${awardNo(i)}.' : ''}', 'Kuhaon sia sa Payroll, Masterlist, Certification kag ID sheet.' '${after > 0 ? ' Ang $after ka tanod pagkatapos sang award no. ${awardNo(i)} magasaka sing isa ka numero.' : ''}'),
          style: sans(15.5, color: C.muted, h: 1.5),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancel', 'Kanselahin', 'Kanselaha'), style: sans(14.5, w: FontWeight.w600, color: C.muted)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: C.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(tr('Remove', 'Tanggalin', 'Kuhaon')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      tanods.removeAt(i);
      _markChanged();
    });
    _toast(tr('Removed ${t.fullName}. Award numbers were updated.', 'Tinanggal si ${t.fullName}. Na-update ang award number.', 'Gin-kuha si ${t.fullName}. Na-update ang mga award number.'));
  }

  Widget _submitPanel() {
    final missing = 4 - rec.backupCount;
    final alertCount = issues.length + rec.outdatedFiles.length;
    final reasons = <String>[
      if (missing > 0)
        tr('Upload $missing more signed cop${missing == 1 ? 'y' : 'ies'}', 'Mag-upload pa ng $missing pirmadong kopya', 'I-upload pa ang $missing ka may pirma nga kopya'),
      if (alertCount > 0) tr('fix $alertCount alert${alertCount == 1 ? '' : 's'}', 'ayusin ang $alertCount paalala', 'tadlungon ang $alertCount ka pahanumdom'),
    ];
    final and = tr(' and ', ' at ', ' kag ');
    final String title;
    final String body;
    VoidCallback? onPressed;
    String label = tr('Submit to $kMunicipality', 'Ipasa sa $kMunicipality', 'Ipasa sa $kMunicipality');
    var buttonIcon = Icons.send_outlined;

    if (corrections) {
      title = canSendBack ? tr('Corrections are done', 'Tapos na ang pagtatama', 'Tapos na ang pagtadlong') : tr('Fix the corrections first', 'Ayusin muna ang mga itatama', 'Tadlungon anay ang mga sala');
      body = canSendBack
          ? tr('Tell $kMunicipality, then bring the corrected paper pages.', 'Sabihan ang $kMunicipality, saka dalhin ang naitamang papel.', 'Ipahibalo sa $kMunicipality, dayon dal-a ang natadlong nga papel.')
          : tr('Upload the corrected copy of every document $kMunicipality asked about.',
              'I-upload ang naitamang kopya ng bawat dokumentong binanggit ng $kMunicipality.', 'Palihog i-upload ang natadlong nga kopya sang kada dokumento nga ginpangayo sang $kMunicipality.');
      label = tr('Corrections done', 'Tapos na ang pagtatama', 'Tapos na ang pagtadlong');
      onPressed = canSendBack ? _sendBack : null;
    } else if (pending) {
      title = tr('Submitting is locked for now', 'Hindi pa puwedeng magpasa', 'Naka-lock anay ang pagpasa');
      body = tr('Your account needs $kMunicipality’s approval first. Keep working in the meantime.',
          'Kailangan munang aprubahan ng $kMunicipality ang inyong account. Magpatuloy muna sa paghahanda.', 'Kinahanglan anay sang aprobasyon sang $kMunicipality ang inyo account. Pwede kamo magpadayon sa pag-obra samtang.');
    } else if (locked) {
      title = switch (rec.status) {
        BrgyStatus.submitted => tr('With $kMunicipality', 'Nasa $kMunicipality', 'Ara sa $kMunicipality'),
        BrgyStatus.checked => tr('Checked by $kMunicipality', 'Nasuri na ng $kMunicipality', 'Nausisa na sang $kMunicipality'),
        BrgyStatus.sentToOppdc => tr('With OPPDC', 'Nasa OPPDC', 'Ara sa OPPDC'),
        _ => tr('Released', 'Na-release na', 'Na-release'),
      };
      body = switch (rec.status) {
        BrgyStatus.submitted => tr('The reviewer is checking your paper set. Mistakes come as messages.',
            'Sinusuri ng reviewer ang inyong papel. Darating bilang mensahe ang anumang mali.', 'Ginausisa sang reviewer ang inyo papel. Ang mga sala maabot bilang mensahe.'),
        BrgyStatus.checked => tr('Waiting for the other barangays. Then $kMunicipality brings every paper set to OPPDC together.',
            'Hinihintay ang ibang barangay. Saka sabay-sabay na dadalhin ng $kMunicipality sa OPPDC.', 'Ginahulat ang iban nga barangay. Dayon dungan nga dal-on sang $kMunicipality sa OPPDC ang tanan nga papel.'),
        BrgyStatus.sentToOppdc => tr('OPPDC has the paper set and can open your uploaded backup.',
            'Nasa OPPDC na ang papel at mabubuksan nito ang inyong backup.', 'Ara sa OPPDC ang papel kag mabuksan nila ang inyo na-upload nga backup.'),
        _ => tr('This year is done. Next year starts with the same tanod list.',
            'Tapos na ngayong taon. Magsisimula ang susunod na taon sa parehong listahan.', 'Tapos na ini nga tuig. Ang masunod nga tuig magsugod sa amo man nga listahan sang tanod.'),
      };
      label = tr('Submitted', 'Naipasa na', 'Napasa na');
      buttonIcon = Icons.check;
    } else if (canSubmit) {
      title = tr('Ready to submit', 'Handa nang ipasa', 'Handa na ipasa');
      body = tr('All signed copies are uploaded. Submit here, then bring the signed paper set to $kMunicipality.',
          'Na-upload na ang lahat ng pirmadong kopya. Ipasa dito, saka dalhin ang pirmadong papel sa $kMunicipality.', 'Na-upload na ang tanan nga may pirma nga kopya. Ipasa diri, dayon dal-a ang may pirma nga papel sa $kMunicipality.');
      onPressed = _submit;
    } else {
      title = tr('Not ready to submit yet', 'Hindi pa handang ipasa', 'Indi pa handa ipasa');
      body = '${reasons.join(and)}.';
    }

    final good = onPressed != null || locked;
    final button = FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: C.yellow,
        foregroundColor: C.navy,
        disabledBackgroundColor: const Color(0xFFE3EAF2),
        disabledForegroundColor: const Color(0xFF97A5B5),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        minimumSize: const Size(0, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        textStyle: sans(16, w: FontWeight.w700),
      ),
      onPressed: onPressed,
      icon: Icon(buttonIcon, size: 18),
      label: Text(label),
    );

    final info = Row(children: [
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: good ? C.greenSoft : (corrections ? const Color(0xFFFDF0EE) : C.mist),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          locked ? Icons.mark_email_read_outlined : (corrections ? Icons.assignment_return_outlined : Icons.outbox_outlined),
          color: good ? C.green : (corrections ? C.red : C.muted),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: sans(16.5, w: FontWeight.w700, color: C.navy)),
          const SizedBox(height: 3),
          Text(body, style: sans(14.5, color: C.muted, h: 1.45)),
        ]),
      ),
    ]);

    return _Panel(
      child: LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < 620) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            info,
            const SizedBox(height: 16),
            button,
          ]);
        }
        return Row(children: [Expanded(child: info), const SizedBox(width: 20), button]);
      }),
    );
  }

  // ================= Other pages =================
  Widget _tanodsPage() => _scroll([
        _pageIntro(
          tr('Tanods', 'Mga Tanod', 'Mga Tanod'),
          tr('This is the one list behind all four documents. Changes here update the Payroll, Masterlist, '
                  'Certification and ID sheet automatically.',
              'Ito ang iisang listahan sa likod ng apat na dokumento. Kusang naa-update ang Payroll, Masterlist, '
                  'Certification at ID sheet kapag may binago rito.', 'Amo ini ang isa ka listahan sa likod sang apat ka dokumento. Ang pagbag-o diri kusa nga ma-update sa Payroll, Masterlist, ' 'Certification kag ID sheet.'),
        ),
        const SizedBox(height: 20),
        _tanodPanel(),
      ]);

  Widget _documentsPage() => _scroll([
        _pageIntro(
          tr('Documents', 'Mga Dokumento', 'Dokumento'),
          tr('Download the filled documents, print them for signing, then upload a photo of each signed paper as your backup.',
              'I-download ang may lamang dokumento, i-print para pirmahan, saka i-upload ang litrato ng bawat pirmadong papel bilang backup.', 'I-download ang napun-an nga dokumento, i-print para pirmahan, dayon i-upload ang litrato sang kada may pirma nga papel bilang backup.'),
        ),
        const SizedBox(height: 20),
        DocumentsView(
          rec: rec,
          locked: locked,
          issueCount: issues.length,
          onToast: _toast,
          onChanged: () => setState(_markChanged),
          onUpload: _upload,
          onOpenMessages: () => _go(_messagesTab),
        ),
        const SizedBox(height: 28),
        _alertsPanel(),
        const SizedBox(height: 20),
        _submitPanel(),
      ]);

  Widget _messagesPage() => _scroll([
        _pageIntro(
          tr('Messages', 'Mga Mensahe', 'Mensahe'),
          tr('Your conversation with the $kMunicipality reviewer. They check your paper copy and tell you here what to fix.',
              'Ang usapan ninyo ng reviewer ng $kMunicipality. Sinusuri nila ang inyong papel at sinasabi dito kung ano ang itatama.', 'Ang inyo istoryahanay sang reviewer sang $kMunicipality. Ginausisa nila ang inyo papel kag ginasugid diri kon ano ang tadlungon.'),
        ),
        const SizedBox(height: 20),
        _Panel(
          child: ChatThread(
            rec: rec,
            asMunicipality: false,
            height: 460,
            onSend: (text, doc) => setState(() => rec.post(fromMunicipality: false, text: text, doc: doc)),
            onUploadFix: _upload,
          ),
        ),
      ]);

  Widget _accountPage() {
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(children: [
            SizedBox(width: 140, child: Text(k, style: sans(15, color: C.muted))),
            Expanded(child: Text(v, style: sans(15.5, w: FontWeight.w600))),
          ]),
        );

    Widget choice<T>(String label, String hint, T current, List<(T, String)> options, void Function(T) onPick) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: sans(15.5, w: FontWeight.w700, color: C.navy)),
          const SizedBox(height: 2),
          Text(hint, style: sans(14, color: C.muted)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (value, text) in options)
              ChoiceChip(
                label: Text(text, style: sans(15, w: FontWeight.w600, color: value == current ? Colors.white : C.navy)),
                selected: value == current,
                showCheckmark: false,
                selectedColor: C.navy,
                backgroundColor: Colors.white,
                side: BorderSide(color: value == current ? C.navy : C.line, width: 1.5),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                onSelected: (_) => onPick(value),
              ),
          ]),
        ]);

    return _scroll([
      _pageIntro(tr('Account', 'Account', 'Account'), tr('Your details and how Gawad looks for you.', 'Ang inyong detalye at kung paano lumalabas ang Gawad.', 'Ang inyo detalye kag kon paano makita ang Gawad.')),
      const SizedBox(height: 20),
      _Panel(
        title: tr('Display', 'Itsura', 'Itsura'),
        icon: Icons.text_fields_rounded,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          choice<double>(
            tr('Text size', 'Laki ng letra', 'Kadako sang letra'),
            tr('Make words bigger if they’re hard to read.', 'Palakihin ang letra kung mahirap basahin.', 'Padakua ang letra kon budlay basahon.'),
            textSize.value,
            [(1.0, tr('Normal', 'Normal', 'Normal')), (1.15, tr('Large', 'Malaki', 'Dako')), (1.3, tr('Larger', 'Mas malaki', 'Mas dako'))],
            (v) => textSize.value = v,
          ),
          const SizedBox(height: 22),
          choice<String>(
            tr('Language', 'Wika', 'Pinulongan'),
            tr('Filipino is a first draft; some screens are still in English.',
                'Unang bersyon pa lang ang Filipino; may mga screen na English pa.', 'Una nga bersyon pa lang ang Filipino kag Hiligaynon; may mga screen nga English pa.'),
            appLang.value,
            [('en', 'English'), ('fil', 'Filipino'), ('hil', 'Hiligaynon')],
            (v) => setState(() => appLang.value = v), // redraw this screen in the new language
          ),
        ]),
      ),
      const SizedBox(height: 20),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: C.yellow,
              child: Text('MD', style: serif(22)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(kRepName, style: serif(24)),
                const SizedBox(height: 4),
                pending
                    ? _pill(tr('Waiting for $kMunicipality’s approval', 'Hinihintay ang apruba ng $kMunicipality', 'Ginahulat ang aprobasyon sang $kMunicipality'),
                        const Color(0xFFFFF4CC), const Color(0xFF7A5B00),
                        icon: Icons.hourglass_top_rounded)
                    : _pill(tr('Approved by $kMunicipality', 'Inaprubahan ng $kMunicipality', 'Gin-aprobahan sang $kMunicipality'), C.greenSoft,
                        const Color(0xFF14583D), icon: Icons.verified_outlined),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          const Divider(color: Color(0xFFE3EAF2)),
          row(tr('Position', 'Posisyon', 'Posisyon'), kRepPosition),
          row('Barangay', 'Brgy. $kBarangay, $kMunicipality'),
          row(tr('Year', 'Taon', 'Tuig'), '$kYear'),
          row(tr('Tanod limit', 'Limit ng tanod', 'Limit sang tanod'), tr('$kQuota (set by OPPDC)', '$kQuota (itinakda ng OPPDC)', '$kQuota (gintakda sang OPPDC)')),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: C.red,
                side: const BorderSide(color: Color(0xFFF0C7C3), width: 1.5),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _signOut,
              icon: const Icon(Icons.logout, size: 18),
              label: Text(tr('Sign out', 'Mag-sign out', 'Mag-sign out'), style: sans(15, w: FontWeight.w600, color: C.red)),
            ),
          ),
        ]),
      ),
    ]);
  }

  // ================= Help =================
  Widget _helpPage() {
    final steps = [
      (
        Icons.document_scanner_outlined,
        tr('Add each tanod once', 'Ilagay ang bawat tanod nang isang beses', 'Idugang ang kada tanod sing makaisa'),
        tr('Scan their PhilSys ID. If they have a different ID, type their details instead.',
            'I-scan ang kanilang PhilSys ID. Kung iba ang ID nila, i-type na lang ang detalye.', 'Palihog i-scan ang ila PhilSys ID. Kon lain ang ila ID, pwede i-type na lang ang ila detalye.'),
      ),
      (
        Icons.spellcheck_rounded,
        tr('Check the names', 'Suriin ang mga pangalan', 'Usisaa ang mga ngalan'),
        tr('Fix anything marked in yellow. Each name must match the ID exactly.',
            'Ayusin ang may dilaw na marka. Dapat eksaktong tugma ang pangalan sa ID.', 'Palihog tadlunga ang may marka nga dalag. Ang kada ngalan dapat pareho gid sa ID.'),
      ),
      (
        Icons.print_outlined,
        tr('Download, print and sign', 'I-download, i-print at papirmahan', 'I-download, i-print kag papirmahi'),
        tr('The four filled documents are ready to print. Print them and have the papers signed by hand. Each ID copy needs 3 signatures.',
            'Handa nang i-print ang apat na dokumento. I-print at papirmahan ang mga papel. Kailangan ng 3 pirma sa bawat kopya ng ID.', 'Handa na i-print ang apat ka napun-an nga dokumento. Palihog i-print kag papirmahi. Ang kada kopya sang ID kinahanglan sang 3 ka pirma.'),
      ),
      (
        Icons.photo_camera_outlined,
        tr('Upload a photo of each signed paper', 'I-upload ang litrato ng bawat pirmadong papel', 'I-upload ang litrato sang kada may pirma nga papel'),
        tr('Take a photo or upload a scan. It replaces the file in Gawad and becomes the backup copy.',
            'Kumuha ng litrato o mag-upload ng scan. Papalitan nito ang file sa Gawad at magiging backup.', 'Pwede magkuha sang litrato ukon mag-upload sang scan. Ilisan sini ang file sa Gawad kag mangin backup nga kopya.'),
      ),
      (
        Icons.send_outlined,
        tr('Submit and bring the paper set', 'Ipasa at dalhin ang papel', 'Ipasa kag dal-a ang papel'),
        tr('Submit here and bring the signed papers to $kMunicipality. If they find a mistake, they message you: fix the paper, upload the corrected copy, and tap “Corrections done”.',
            'Ipasa dito at dalhin ang pirmadong papel sa $kMunicipality. Kapag may mali, magme-message sila: itama ang papel, i-upload ang naitama, at pindutin ang “Tapos na ang pagtatama”.', 'Ipasa diri kag dal-a ang may pirma nga papel sa $kMunicipality. Kon may makita sila nga sala, magmensahe sila: tadlungon ang papel, i-upload ang natadlong nga kopya, kag pinduta ang “Tapos na ang pagtadlong”.'),
      ),
    ];
    final words = [
      (tr('Award number', 'Award number', 'Award number'),
          tr('The tanod’s number on the Payroll and Masterlist (001, 002…). Gawad gives it and renumbers by itself.',
              'Ang numero ng tanod sa Payroll at Masterlist (001, 002…). Kusa itong ibinibigay at inaayos ng Gawad.', 'Ang numero sang tanod sa Payroll kag Masterlist (001, 002…). Ang Gawad ang maghatag kag kusa nga magilis sini.')),
      (tr('Tanod limit', 'Limit ng tanod', 'Limit sang tanod'),
          tr('The most tanods your barangay can list this year. OPPDC sets it.',
              'Ang pinakamaraming tanod na puwedeng ilista ng barangay ngayong taon. Ang OPPDC ang nagtatakda.', 'Ang pinakamadamo nga tanod nga malista sang inyo barangay subong nga tuig. Ang OPPDC ang nagatakda sini.')),
      (tr('Backup / signed copy', 'Backup / pirmadong kopya', 'Backup / may pirma nga kopya'),
          tr('The photo or scan of the signed paper you upload. The paper is what gets checked; the upload is the backup that $kMunicipality and OPPDC can open.',
              'Ang litrato o scan ng pirmadong papel na ina-upload ninyo. Ang papel ang sinusuri; ang upload ang backup na mabubuksan ng $kMunicipality at OPPDC.', 'Ang litrato ukon scan sang may pirma nga papel nga gin-upload ninyo. Ang papel ang ginausisa; ang upload amo ang backup nga mabuksan sang $kMunicipality kag OPPDC.')),
      (tr('Not synced', 'Hindi pa naka-sync', 'Wala pa na-sync'),
          tr('Your work is saved on the phone but not sent online yet. It syncs by itself when you have internet.',
              'Naka-save sa phone ang trabaho pero hindi pa naipapadala online. Kusa itong magsi-sync kapag may internet.', 'Naka-save ang inyo obra sa phone pero wala pa napadala online. Kusa ini nga ma-sync kon may internet na kamo.')),
      (tr('Corrections', 'Pagtatama', 'Pagtadlong'),
          tr('$kMunicipality found a mistake on the paper. Fix only the documents they mention, and upload the corrected copies.',
              'May nakitang mali ang $kMunicipality sa papel. Ang binanggit lang na dokumento ang itatama, at i-upload ang naitamang kopya.', 'May nakita nga sala ang $kMunicipality sa papel. Ang mga dokumento lang nga ginsiling nila ang tadlungon, dayon i-upload ang natadlong nga kopya.')),
      (tr('Out of date', 'Luma na', 'Daan na'),
          tr('You changed the tanod list after a document was signed. Print the new version, sign it, and upload it again.',
              'Binago ang listahan matapos pirmahan ang dokumento. I-print ang bagong bersyon, papirmahan, at i-upload ulit.', 'Nabag-o ang listahan sang tanod pagkatapos mapirmahan ang dokumento. Palihog i-print ang bag-o nga bersyon, papirmahi, kag i-upload liwat.')),
    ];

    return _scroll([
      _pageIntro(tr('Help', 'Tulong', 'Bulig'), tr('How Gawad works, in five steps.', 'Paano gumagana ang Gawad, sa limang hakbang.', 'Paano mag-obra ang Gawad, sa lima ka lakang.')),
      const SizedBox(height: 20),
      _Panel(
        title: tr('Quick guide', 'Mabilis na gabay', 'Madasig nga giya'),
        icon: Icons.map_outlined,
        child: Column(children: [
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: const Color(0xFFFFF4CC), borderRadius: BorderRadius.circular(13)),
                  child: Text('${i + 1}', style: serif(20)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(steps[i].$1, size: 18, color: C.navy),
                      const SizedBox(width: 8),
                      Expanded(child: Text(steps[i].$2, style: sans(16.5, w: FontWeight.w700, color: C.navy))),
                    ]),
                    const SizedBox(height: 4),
                    Text(steps[i].$3, style: sans(15, color: C.ink, h: 1.5)),
                  ]),
                ),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 20),
      _Panel(
        title: tr('Words used in Gawad', 'Mga salitang ginagamit', 'Mga tinaga nga gamit sa Gawad'),
        icon: Icons.menu_book_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (word, meaning) in words)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE9EFF5)))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(word, style: sans(16, w: FontWeight.w700, color: C.navy)),
                const SizedBox(height: 3),
                Text(meaning, style: sans(15, color: C.ink, h: 1.5)),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 20),
      _Panel(
        title: tr('Need help from a person?', 'Kailangan ng tulong ng tao?', 'Kinahanglan sang bulig halin sa tawo?'),
        icon: Icons.support_agent_rounded,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            tr('Your municipal reviewer in $kMunicipality can answer questions about your set.',
                'Masasagot ng inyong reviewer sa $kMunicipality ang mga tanong tungkol sa inyong set.', 'Masabat sang inyo municipal reviewer sa $kMunicipality ang mga pamangkot parte sa inyo set.'),
            style: sans(15, color: C.ink, h: 1.5),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _bigButton(tr('Message the $kMunicipality reviewer', 'Mag-message sa reviewer ng $kMunicipality', 'Magmensahe sa reviewer sang $kMunicipality'),
                Icons.chat_bubble_outline_rounded, () => _go(_messagesTab)),
            _bigButton(tr('Text size & language', 'Laki ng letra at wika', 'Kadako sang letra kag pinulongan'), Icons.text_fields_rounded,
                () => _go(_accountTab), outlined: true),
          ]),
        ]),
      ),
    ]);
  }

  Widget _pageIntro(String title, String sub) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: serif(28)),
        const SizedBox(height: 6),
        Text(sub, style: sans(15.5, color: C.muted, h: 1.5)),
      ]);
}

// ================= Small shared pieces =================

Widget _logoMark(double s) => Container(
      width: s,
      height: s,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: C.yellow, borderRadius: BorderRadius.circular(s * .3)),
            child: ClipRRect(
        borderRadius: BorderRadius.circular(s * .3),
        child: Image.asset('assets/logo.png', width: s, height: s, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Text('G', style: serif(s * .55))),
      ),
    );

Widget _pill(String text, Color bg, Color fg, {IconData? icon}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 5)],
        Text(text, style: sans(14, w: FontWeight.w600, color: fg)),
      ]),
    );

class _Panel extends StatelessWidget {
  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;
  final String? help; // shows a "what's this?" button next to the title
  const _Panel({this.title, this.icon, this.trailing, required this.child, this.help});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1E9F2)),
        boxShadow: [
          BoxShadow(color: C.navy.withValues(alpha: .06), blurRadius: 24, spreadRadius: -8, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null) ...[
          Row(children: [
            if (icon != null) ...[Icon(icon, size: 20, color: C.navy), const SizedBox(width: 10)],
            Flexible(child: Text(title!, style: sans(17.5, w: FontWeight.w700, color: C.navy))),
            if (help != null)
              IconButton(
                tooltip: tr('What’s this?', 'Ano ito?', 'Ano ini?'),
                visualDensity: VisualDensity.compact,
                onPressed: () => explain(context, title!, help!),
                icon: const Icon(Icons.help_outline_rounded, size: 20, color: C.blue),
              ),
            const Spacer(),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 16),
        ],
        child,
      ]),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String value, label, note;
  final double? progress;
  final String? help;
  const _StatTile({
    required this.icon,
    required this.tint,
    required this.value,
    required this.label,
    required this.note,
    this.progress,
    this.help,
  });

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: tint.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 21, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: sans(15, w: FontWeight.w600, color: C.muted))),
          if (help != null)
            IconButton(
              tooltip: tr('What’s this?', 'Ano ito?', 'Ano ini?'),
              visualDensity: VisualDensity.compact,
              onPressed: () => explain(context, label, help!),
              icon: const Icon(Icons.help_outline_rounded, size: 20, color: C.blue),
            ),
        ]),
        const SizedBox(height: 16),
        Text(value, style: sans(28, w: FontWeight.w700, color: C.navy, h: 1.1)),
        const SizedBox(height: 6),
        Text(note, style: sans(14, color: C.muted)),
        if (progress != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress!.clamp(0, 1).toDouble(),
              minHeight: 6,
              backgroundColor: const Color(0xFFE3EAF2),
              valueColor: AlwaysStoppedAnimation(tint),
            ),
          ),
        ],
      ]),
    );
  }
}

class _StatusTracker extends StatelessWidget {
  final int current;
  final int? correctionsAt;
  const _StatusTracker({required this.current, this.correctionsAt});

  Widget _dot(int i) {
    final done = i < current;
    final now = i == current;
    if (i == correctionsAt) {
      return Container(
        width: 30,
        height: 30,
        decoration: const BoxDecoration(color: C.red, shape: BoxShape.circle),
        child: const Icon(Icons.edit_note_rounded, size: 18, color: Colors.white),
      );
    }
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done ? C.green : (now ? C.yellow : Colors.white),
        shape: BoxShape.circle,
        border: Border.all(color: done ? C.green : (now ? C.yellowDark : C.line), width: 2),
      ),
      child: done
          ? const Icon(Icons.check, size: 16, color: Colors.white)
          : Text('${i + 1}', style: sans(14, w: FontWeight.w700, color: now ? C.navy : C.muted)),
    );
  }

  TextStyle _label(int i) => sans(
        13.5,
        w: i == current ? FontWeight.w700 : FontWeight.w500,
        color: i == correctionsAt ? C.red : (i <= current ? C.navy : C.muted),
      );

  String _name(int i) => i == correctionsAt ? tr('Corrections', 'Pagtatama', 'Pagtadlong') : _stepName(i);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth >= 600) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < _stepCount; i++)
            Expanded(
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: Container(height: 3, color: i == 0 ? Colors.transparent : (i <= current ? C.green : C.line)),
                  ),
                  _dot(i),
                  Expanded(
                    child: Container(
                      height: 3,
                      color: i == _stepCount - 1 ? Colors.transparent : (i < current ? C.green : C.line),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(_name(i), textAlign: TextAlign.center, style: _label(i)),
              ]),
            ),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < _stepCount; i++) ...[
          Row(children: [
            _dot(i),
            const SizedBox(width: 12),
            Text(_name(i), style: _label(i)),
          ]),
          if (i < _stepCount - 1)
            Container(
              width: 3,
              height: 14,
              margin: const EdgeInsets.only(left: 13.5),
              color: i < current ? C.green : C.line,
            ),
        ],
      ]);
    });
  }
}

class _Sidebar extends StatelessWidget {
  final int index;
  final int unread;
  final void Function(int) onSelect;
  final VoidCallback onSignOut;
  const _Sidebar({required this.index, required this.unread, required this.onSelect, required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 252,
      color: C.navy,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Row(children: [
            _logoMark(38),
            const SizedBox(width: 12),
            Text('Gawad', style: sans(20, w: FontWeight.w700, color: Colors.white)),
          ]),
        ),
        const SizedBox(height: 26),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .06),
            border: Border.all(color: Colors.white.withValues(alpha: .1)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('BARANGAY', style: sans(12, w: FontWeight.w700, color: const Color(0xFF8FA6BF)).copyWith(letterSpacing: .8)),
            const SizedBox(height: 4),
            Text('$kBarangay, $kMunicipality', style: sans(16, w: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 2),
            Text(tr('Incentive year $kYear', 'Taon ng incentive: $kYear', 'Tuig sang incentive $kYear'), style: sans(14, color: const Color(0xFFB9C9DA))),
          ]),
        ),
        const SizedBox(height: 22),
        for (var i = 0; i < _nav.length; i++) _item(i),
        const Spacer(),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: C.yellow.withValues(alpha: .1),
            border: Border.all(color: C.yellow.withValues(alpha: .25)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.wifi_off_rounded, size: 18, color: C.yellow),
            const SizedBox(width: 10),
            Expanded(
              child: Text(tr('Works without internet. Your work syncs when you’re back online.', 'Gumagana kahit walang internet. Magsi-sync kapag may internet na.', 'Nagaobra bisan wala internet. Ma-sync ang inyo obra kon online na kamo liwat.'),
                  style: sans(14, color: const Color(0xFFE3ECF6), h: 1.45)),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        InkWell(
          onTap: onSignOut,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: Row(children: [
              const Icon(Icons.logout, size: 19, color: Color(0xFFB9C9DA)),
              const SizedBox(width: 12),
              Text(tr('Sign out', 'Mag-sign out', 'Mag-sign out'), style: sans(15.5, w: FontWeight.w500, color: const Color(0xFFB9C9DA))),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        const SizedBox(
          height: 4,
          child: Row(children: [
            Expanded(flex: 34, child: ColoredBox(color: C.yellow)),
            Expanded(flex: 33, child: ColoredBox(color: C.green)),
            Expanded(flex: 33, child: ColoredBox(color: C.blue)),
          ]),
        ),
      ]),
    );
  }

  Widget _item(int i) {
    final n = _nav[i];
    final on = i == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: on ? Colors.white.withValues(alpha: .1) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onSelect(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(on ? n.activeIcon : n.icon, size: 20, color: on ? C.yellow : const Color(0xFFB9C9DA)),
              const SizedBox(width: 14),
              Expanded(
                child: Text(n.label,
                    style: sans(16, w: on ? FontWeight.w700 : FontWeight.w500, color: on ? Colors.white : const Color(0xFFB9C9DA))),
              ),
              if (i == _messagesTab && unread > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: C.yellow, borderRadius: BorderRadius.circular(99)),
                  child: Text('$unread', style: sans(13, w: FontWeight.w800, color: C.navy)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}