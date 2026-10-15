import 'package:flutter/material.dart';
import 'package:tanod_incentives/screens/archive/archive_page.dart'; // ARCHIVE

import 'package:tanod_incentives/theme.dart';
import 'package:tanod_incentives/data/demo_data.dart';
import 'package:tanod_incentives/data/doc_kind.dart';
import 'package:tanod_incentives/data/store.dart';
import 'package:tanod_incentives/widgets/ui.dart';
import 'package:tanod_incentives/screens/auth/auth_page.dart';
import 'package:tanod_incentives/screens/municipal/check_page.dart';
import 'package:tanod_incentives/screens/municipal/muni_docs_page.dart'; // a barangay's 4 documents
import 'package:tanod_incentives/data/cloud.dart'; // FIREBASE: live barangays + saving

// Municipality (MLGOO / municipal reviewer) dashboard, in English, Filipino
// and Hiligaynon.
// The reviewer checks each barangay's PAPER set, sends mistakes as messages,
// and, once every barangay is checked, brings all the paper sets to OPPDC
// together. The uploaded copies are a backup that OPPDC can open.
// Pages: Overview, Barangays, Messages, Account requests, Account.

class MunicipalPage extends StatefulWidget {
  const MunicipalPage({super.key});
  @override
  State<MunicipalPage> createState() => _MunicipalPageState();
}

class _Nav {
  final IconData icon, activeIcon;
  final String en, fil, hil;
  const _Nav(this.icon, this.activeIcon, this.en, this.fil, this.hil);
  String get label => tr(en, fil, hil);
}

const _nav = [
  _Nav(Icons.space_dashboard_outlined, Icons.space_dashboard, 'Overview', 'Buod', 'Sumaryo'),
  _Nav(Icons.holiday_village_outlined, Icons.holiday_village, 'Barangays', 'Mga Barangay', 'Mga Barangay'),
  _Nav(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Messages', 'Mga Mensahe', 'Mga Mensahe'),
  _Nav(Icons.folder_copy_outlined, Icons.folder_copy, 'Documents', 'Mga Dokumento', 'Mga Dokumento'),
  _Nav(Icons.person_outline, Icons.person, 'Account', 'Account', 'Account'),
];

const _messagesTab = 2;
const _docsTab = 3; // every barangay's 4 documents
const _accountTab = 4;
const _requestsTab = 5; // account requests: no tab, opened from "Needs your attention"

String _reviewerRole() => tr('Municipal reviewer (MLGOO)', 'Municipal reviewer (MLGOO)', 'Municipal reviewer (MLGOO)');

class _MunicipalPageState extends State<MunicipalPage> {
  int navIndex = 0;
  BrgyStatus? filter; // Barangays page filter
  String search = '';

  // ---------- derived ----------
  List<BrgyRecord> get brgys => store.brgys;
  List<AccountRequest> get requests => store.requests;
  List<BrgyRecord> by(BrgyStatus s) => brgys.where((b) => muniStage(b.status) == muniStage(s)).toList();
  List<BrgyRecord> get notChecked =>
      brgys.where((b) => b.status != BrgyStatus.checked && b.status != BrgyStatus.sentToOppdc && b.status != BrgyStatus.released).toList();
  int get checkedCount => brgys.length - notChecked.length;
  bool get allChecked => notChecked.isEmpty;
  int get tanodsTotal => brgys.fold(0, (a, b) => a + b.tanods.length);
  int get payrollTotal => brgys.fold(0, (a, b) => a + b.payroll);
  int get unreadTotal => brgys.fold(0, (a, b) => a + b.unreadMuni);
  int get backupsComplete => brgys.where((b) => b.backupComplete).length;

  String peso(int v) {
    final s = v.toString();
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return '₱$out';
  }

  String _repLine(BrgyRecord b) => b.rep == '—'
      ? tr('No representative yet', 'Wala pang kinatawan', 'Wala pa sang representante')
      : '${b.rep}${b.position.isEmpty ? '' : ' · ${b.position}'}';

  // FIREBASE: redraw when online data arrives; show background save errors
  // Per barangay: messages already seen (for "new message" pop-ups)
  final Map<BrgyRecord, int> _chatSeen = {};
  bool _chatReady = false; // false until the first pop-up check after opening

  void _onCloudChange() {
    if (!mounted) return;
    setState(() {});
    // FIREBASE: pop-up when a barangay sends a message (tap → open its chat)
    for (final b in brgys) {
      final n = b.chat.length;
      final before = _chatSeen[b];
      _chatSeen[b] = n;
      if (!_chatReady || before == null || n <= before) continue;
      final last = b.chat.last;
      if (last.fromMunicipality || cloud.viewingBarangay == b.id) continue;
      final text = last.text.length > 90 ? '${last.text.substring(0, 90)}…' : last.text;
      notify(
        context,
        text,
        type: NotifyType.info,
        title: tr('New message from Brgy. ${b.name}', 'Bagong mensahe mula sa Brgy. ${b.name}', 'Bag-o nga mensahe halin sa Brgy. ${b.name}'),
        onTap: () {
          if (mounted) _open(b);
        },
      );
    }
  }

  void _onCloudError() {
    final m = cloud.errors.value;
    if (m == null || !mounted) return;
    toast(context, m, type: NotifyType.error, title: tr('Not saved online', 'Hindi na-save online', 'Wala na-save online'));
    cloud.errors.value = null;
  }

  /// Runs a Firebase action; shows a red pop-up if it fails. Returns false on failure.
  Future<bool> _cloud(Future<void> Function() action) async {
    if (!cloud.isMunicipal) return true;
    try {
      await action();
      return true;
    } catch (e) {
      if (mounted) toast(context, Cloud.friendly(e), type: NotifyType.error, title: tr('Not saved online', 'Hindi na-save online', 'Wala na-save online'));
      return false;
    }
  }

  @override
  void dispose() {
    cloud.changes.removeListener(_onCloudChange);
    cloud.errors.removeListener(_onCloudError);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    cloud.changes.addListener(_onCloudChange);
    cloud.errors.addListener(_onCloudError);
    // New messages from barangays: tap the pop-up to open that barangay's messages.
    // With Firebase, wait a moment so the messages have arrived.
    Future.delayed(Duration(milliseconds: cloud.isMunicipal ? 2500 : 0), () {
      // From now on, new messages get their own pop-up
      for (final b in brgys) {
        _chatSeen[b] = b.chat.length;
      }
      _chatReady = true;
      if (!mounted || unreadTotal == 0) return;
      final from = brgys.where((b) => b.unreadMuni > 0).toList()..sort((a, b) => b.unreadMuni.compareTo(a.unreadMuni));
      final one = from.length == 1;
      notify(
        context,
        one
            ? tr('Brgy. ${from.first.name} sent you $unreadTotal new message${unreadTotal == 1 ? '' : 's'}.',
                'May $unreadTotal bagong mensahe mula sa Brgy. ${from.first.name}.', 'May $unreadTotal ka bag-o nga mensahe halin sa Brgy. ${from.first.name}.')
            : tr('$unreadTotal new messages from ${from.length} barangays.', '$unreadTotal bagong mensahe mula sa ${from.length} barangay.',
                '$unreadTotal ka bag-o nga mensahe halin sa ${from.length} ka barangay.'),
        type: NotifyType.info,
        title: tr('New message', 'Bagong mensahe', 'Bag-o nga mensahe'),
        onTap: () {
          if (mounted) _open(from.first); // the barangay with the most new messages
        },
      );
    });
  }

  // ---------- actions ----------
  Future<void> _signOut() async {
    final ok = await confirmAction(
      context,
      title: tr('Sign out?', 'Mag-sign out?', 'Mag-sign out?'),
      message: tr('You can sign back in any time.', 'Puwede kang mag-sign in ulit kahit kailan.', 'Puwede ka liwat mag-sign in bisan san-o.'),
      confirmLabel: tr('Sign out', 'Mag-sign out', 'Mag-sign out'),
      icon: Icons.logout_rounded,
      danger: true,
    );
    if (!ok || !mounted) return;
    await cloud.signOut();
    if (!mounted) return;
    toast(context, tr('You have signed out.', 'Naka-sign out ka na.', 'Naka-sign out ka na.'), type: NotifyType.info,
        title: tr('Signed out', 'Naka-sign out', 'Naka-sign out'));
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AuthPage()));
  }

  void _go(int i) => setState(() => navIndex = i);

  Future<void> _open(BrgyRecord b) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CheckPage(rec: b)));
    if (mounted) setState(() {});
  }

  Future<void> _remind(List<BrgyRecord> list) async {
    final names = list.map((b) => b.name).join(', ');
    final ok = await confirmAction(
      context,
      title: tr('Send a reminder?', 'Magpadala ng paalala?', 'Magpadala sang pahanumdom?'),
      message: tr('A message will be sent to Brgy. $names asking them to finish and bring their paper set.',
          'Magpapadala ng mensahe sa Brgy. $names para tapusin at dalhin ang kanilang papel.',
          'Magapadala sang mensahe sa Brgy. $names para tapuson kag dal-on ang ila papel.'),
      confirmLabel: tr('Send reminder', 'Ipadala', 'Ipadala'),
      icon: Icons.notifications_active_outlined,
    );
    if (!ok || !mounted) return;
    const text = 'Reminder: please finish your documents, upload the signed copies, and bring the paper set to the MLGOO office.';
    if (cloud.isMunicipal) {
      if (!await _cloud(() => cloud.remind(list, text)) || !mounted) return; // FIREBASE: arrives through the live chat
    } else {
      setState(() {
        for (final b in list) {
          b.post(fromMunicipality: true, text: text);
        }
      });
    }
    toast(
      context,
      tr('Reminder sent to ${list.length} barangay${list.length == 1 ? '' : 's'}.',
          'Naipadala ang paalala sa ${list.length} barangay.', 'Napadala ang pahanumdom sa ${list.length} ka barangay.'),
      title: tr('Reminder sent', 'Naipadala ang paalala', 'Napadala ang pahanumdom'),
    );
  }

  Future<void> _approveRequest(AccountRequest r) async {
    final ok = await confirmAction(
      context,
      title: tr('Approve ${r.name}?', 'Aprubahan si ${r.name}?', 'Aprobahan si ${r.name}?'),
      message: tr('Make sure their proof of designation is valid. They will be able to submit for Brgy. ${r.barangay}.',
          'Siguraduhing tama ang kanilang patunay. Makakapagpasa na sila para sa Brgy. ${r.barangay}.',
          'Siguraduha nga husto ang ila pamatuod. Makapasa na sila para sa Brgy. ${r.barangay}.'),
      confirmLabel: tr('Approve', 'Aprubahan', 'Aprobahan'),
      icon: Icons.how_to_reg_outlined,
    );
    if (!ok || !mounted) return;
    setState(() {
      requests.remove(r);
      for (final b in brgys) {
        if (b.name == r.barangay) {
          b.accountPending = false;
          if (b.rep == '—') {
            b.rep = r.name;
            b.position = r.position;
          }
          if (b.status == BrgyStatus.notStarted) b.status = BrgyStatus.preparing;
        }
      }
    });
    toast(context, tr('${r.name} can now submit for Brgy. ${r.barangay}.', 'Puwede nang magpasa si ${r.name} para sa Brgy. ${r.barangay}.',
        'Puede na magpasa si ${r.name} para sa Brgy. ${r.barangay}.'),
        title: tr('Request approved', 'Naaprubahan', 'Naaprobahan'));
  }

  Future<void> _declineRequest(AccountRequest r) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Decline ${r.name}?', 'Tanggihan si ${r.name}?', 'Balibaran si ${r.name}?'), style: serif(24)),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              tr('Tell them why, so they know what to send next time.', 'Sabihin kung bakit, para alam nila ang ipapadala sa susunod.',
                  'Isugid kon ngaa, para mahibal-an nila ang ipadala sa sunod.'),
              style: sans(15.5, color: C.muted, h: 1.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              minLines: 2,
              maxLines: 4,
              style: sans(15.5),
              decoration: fieldDecoration(
                  tr('e.g. Please attach your designation letter.', 'hal. Pakilakip ang inyong designation letter.',
                      'pananglitan: Palihog ilakip ang inyo designation letter.'),
                  Icons.edit_note_rounded),
            ),
          ]),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancel', 'Kanselahin', 'Kanselaha'), style: sans(15, w: FontWeight.w600, color: C.muted)),
          ),
          FilledButton(
            style: primaryStyle(bg: C.red, fg: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Decline', 'Tanggihan', 'Balibaran')),
          ),
        ],
      ),
    );
    Future.delayed(const Duration(milliseconds: 400), reason.dispose);
    if (ok != true || !mounted) return;
    setState(() => requests.remove(r));
    toast(context, tr('Declined. ${r.name} will see your reason.', 'Tinanggihan. Makikita ni ${r.name} ang dahilan.',
        'Ginbalibaran. Makita ni ${r.name} ang rason.'),
        type: NotifyType.info, title: tr('Request declined', 'Tinanggihan', 'Ginbalibaran'));
  }

  // All barangays go to OPPDC together, as one physical set.
  Future<void> _sendToOppdc() async {
    var delivered = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(tr('Submit $kMunicipality to OPPDC', 'Ipasa ang $kMunicipality sa OPPDC', 'Ipasa ang $kMunicipality sa OPPDC'),
              style: serif(24)),
          content: SizedBox(
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                tr('All ${brgys.length} barangays go to OPPDC together, as paper. The uploaded copies stay in Gawad as the backup OPPDC can open.',
                    'Sabay-sabay na ipapasa sa OPPDC ang ${brgys.length} barangay, bilang papel. Mananatili sa Gawad ang na-upload na kopya bilang backup na mabubuksan ng OPPDC.',
                    'Dungan nga ipasa sa OPPDC ang ${brgys.length} ka barangay, bilang papel. Magapabilin sa Gawad ang na-upload nga kopya bilang backup nga mabuksan sang OPPDC.'),
                style: sans(15.5, color: C.muted, h: 1.5),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: C.mist, borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _kv(tr('Barangays', 'Mga barangay', 'Mga barangay'), '${brgys.length}'),
                  _kv(tr('Tanods', 'Mga tanod', 'Mga tanod'), '$tanodsTotal'),
                  _kv(tr('Payroll total', 'Kabuuang payroll', 'Kabilugan nga payroll'), peso(payrollTotal)),
                ]),
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                value: delivered,
                activeColor: C.green,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  tr('The paper sets of all ${brgys.length} barangays are bundled and brought to OPPDC.',
                      'Pinagsama at dinala sa OPPDC ang papel ng ${brgys.length} barangay.',
                      'Ginhugpong kag gindala sa OPPDC ang papel sang ${brgys.length} ka barangay.'),
                  style: sans(15, w: FontWeight.w600),
                ),
                onChanged: (v) => setD(() => delivered = v ?? false),
              ),
            ]),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Not yet', 'Hindi pa', 'Indi pa'), style: sans(15, w: FontWeight.w600, color: C.muted)),
            ),
            FilledButton.icon(
              style: primaryStyle(bg: C.green, fg: Colors.white),
              onPressed: delivered ? () => Navigator.pop(ctx, true) : null,
              icon: const Icon(Icons.local_shipping_outlined, size: 18),
              label: Text(tr('Mark as submitted', 'Markahang naipasa', 'Markahan nga napasa')),
            ),
          ],
        );
      }),
    );
    if (ok != true || !mounted) return;
    if (!await _cloud(cloud.submitToOppdc) || !mounted) return; // FIREBASE: needs every barangay verified
    setState(() {
      store.sentToOppdc = true;
      store.sentOn = nowLabel();
      for (final b in brgys) {
        b.status = BrgyStatus.sentToOppdc;
        if (!cloud.isMunicipal) b.post(
          fromMunicipality: true,
          system: true,
          text: 'All barangays’ paper sets were brought to OPPDC. OPPDC can also open your uploaded copies.',
        );
      }
    });
    toast(context, tr('Submitted to OPPDC. OPPDC can open every barangay’s backup copies.',
        'Naipasa sa OPPDC. Mabubuksan ng OPPDC ang backup ng bawat barangay.',
        'Napasa sa OPPDC. Mabuksan sang OPPDC ang backup sang kada barangay.'),
        title: tr('Submitted to OPPDC', 'Naipasa sa OPPDC', 'Napasa sa OPPDC'));
  }

  void _demo(String key) => setState(() {
        if (key == 'reset') {
          store.reset();
        } else {
          store.checkAllForDemo();
        }
      });

  // ---------- shell ----------
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final wide = w >= 1000;
    final page = switch (navIndex) {
      1 => _barangaysPage(),
      _messagesTab => _messagesPage(),
      _docsTab => _docsPage(),
      _requestsTab => _requestsPage(),
      _accountTab => _accountPage(),
      _ => _overviewPage(),
    };

    if (wide) {
      return Scaffold(
        backgroundColor: C.mist,
        body: Row(children: [
          _sidebar(),
          Expanded(child: Column(children: [_topBar(true), Expanded(child: page)])),
        ]),
      );
    }
    return Scaffold(
      backgroundColor: C.mist,
      body: SafeArea(child: Column(children: [_topBar(false), Expanded(child: page)])),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navIndex < _nav.length ? navIndex : 0,
        onDestinationSelected: _go,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        indicatorColor: C.yellow.withValues(alpha: .4),
        height: 68,
        destinations: [
          for (var i = 0; i < _nav.length; i++)
            NavigationDestination(
              icon: _badge(i, Icon(_nav[i].icon)),
              selectedIcon: _badge(i, Icon(_nav[i].activeIcon, color: C.navy)),
              label: _nav[i].label,
            ),
        ],
      ),
    );
  }

  int _count(int i) => i == _docsTab ? by(BrgyStatus.submitted).length : (i == _messagesTab ? unreadTotal : 0);

  Widget _badge(int i, Widget icon) => _count(i) > 0 ? Badge(label: Text('${_count(i)}'), child: icon) : icon;

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
        if (!wide) ...[logoMark(34), const SizedBox(width: 10)],
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(wide ? _nav[navIndex].label : 'Gawad',
                overflow: TextOverflow.ellipsis, style: sans(wide ? 20 : 17, w: FontWeight.w700, color: C.navy)),
            Text(tr('Municipality of $kMunicipality · $kYear', 'Munisipyo ng $kMunicipality · $kYear', 'Banwa sang $kMunicipality · $kYear'),
                overflow: TextOverflow.ellipsis, style: sans(13.5, color: C.muted)),
          ]),
        ),
        if (kDemoMode && !cloud.isMunicipal) ...[
          PopupMenuButton<String>(
            tooltip: 'Demo',
            offset: const Offset(0, 46),
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: _demo,
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Text('DEMO', style: sans(12, w: FontWeight.w700, color: C.muted).copyWith(letterSpacing: .6)),
              ),
              PopupMenuItem<String>(value: 'all', child: Text('Mark every barangay checked', style: sans(15))),
              PopupMenuItem<String>(value: 'reset', child: Text('Reset the demo', style: sans(15))),
            ],
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: C.mist, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.tune_rounded, size: 19, color: C.muted),
            ),
          ),
          const SizedBox(width: 10),
        ],
        PopupMenuButton<String>(
          tooltip: tr('Account', 'Account', 'Account'),
          offset: const Offset(0, 48),
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (v) => v == 'out' ? _signOut() : _go(_accountTab),
          itemBuilder: (_) => [
            PopupMenuItem(
                value: 'acct',
                child: Text(tr('My account & settings', 'Account at settings', 'Account kag settings'), style: sans(15))),
            PopupMenuItem(value: 'out', child: Text(tr('Sign out', 'Mag-sign out', 'Mag-sign out'), style: sans(15, color: C.red))),
          ],
          child: CircleAvatar(
            radius: 19,
            backgroundColor: C.yellow,
            child: Text('LT', style: sans(14, w: FontWeight.w700, color: C.navy)),
          ),
        ),
      ]),
    );
  }

  Widget _sidebar() {
    Widget item(int i) {
      final n = _nav[i];
      final on = i == navIndex;
      final count = _count(i);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Material(
          color: on ? Colors.white.withValues(alpha: .1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _go(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Icon(on ? n.activeIcon : n.icon, size: 20, color: on ? C.yellow : const Color(0xFFB9C9DA)),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(n.label,
                      style: sans(16, w: on ? FontWeight.w700 : FontWeight.w500, color: on ? Colors.white : const Color(0xFFB9C9DA))),
                ),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: C.yellow, borderRadius: BorderRadius.circular(99)),
                    child: Text('$count', style: sans(13, w: FontWeight.w800, color: C.navy)),
                  ),
              ]),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 270,
      color: C.navy,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Row(children: [
            logoMark(38),
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
            Text(tr('MUNICIPALITY', 'MUNISIPYO', 'BANWA'),
                style: sans(12, w: FontWeight.w700, color: const Color(0xFF8FA6BF)).copyWith(letterSpacing: .8)),
            const SizedBox(height: 4),
            Text(kMunicipality, style: sans(16.5, w: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 2),
            Text(tr('${brgys.length} barangays · $kYear', '${brgys.length} barangay · $kYear', '${brgys.length} ka barangay · $kYear'),
                style: sans(14, color: const Color(0xFFB9C9DA))),
          ]),
        ),
        const SizedBox(height: 22),
        for (var i = 0; i < _nav.length; i++) item(i),
        const Spacer(),
        InkWell(
          onTap: _signOut,
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

  // ================= Overview =================
  Widget _overviewPage() {
    const gap = SizedBox(height: 20);
    return _scroll([
      _welcome(),
      gap,
      _attention(),
      gap,
      _stats(),
      gap,
      _progressBoard(),
      gap,
      _barangayTable(brgys, title: tr('All barangays', 'Lahat ng barangay', 'Tanan nga barangay')),
    ]);
  }

  Widget _welcome() {
    final h = DateTime.now().hour;
    final greet = h < 12
        ? tr('Good morning', 'Magandang umaga', 'Maayong aga')
        : (h < 18 ? tr('Good afternoon', 'Magandang hapon', 'Maayong hapon') : tr('Good evening', 'Magandang gabi', 'Maayong gab-i'));
    final now = DateTime.now();
    final days = DateTime(now.year, 12, 1).difference(DateTime(now.year, now.month, now.day)).inDays;
    final toCheck = by(BrgyStatus.submitted).length;

    final countdown = Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        border: Border.all(color: Colors.white.withValues(alpha: .16)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(days > 0 ? tr('$days days', '$days araw', '$days ka adlaw') : tr('December', 'Disyembre', 'Disyembre'),
            style: serif(30, color: C.yellow)),
        const SizedBox(height: 4),
        Text(
            days > 0
                ? tr('until the December release', 'bago ang release sa Disyembre', 'antes sang release sa Disyembre')
                : tr('Release month is here', 'Buwan na ng release', 'Bulan na sang release'),
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
        child: Text('${_reviewerRole()} · $kMunicipality', style: sans(13.5, w: FontWeight.w600, color: const Color(0xFFFFE9A6))),
      ),
      const SizedBox(height: 14),
      Text('$greet, $kReviewerFirstName', style: serif(30, color: Colors.white)),
      const SizedBox(height: 8),
      Text(
        store.sentToOppdc
            ? tr('All ${brgys.length} barangays were submitted to OPPDC.', 'Naipasa na sa OPPDC ang ${brgys.length} barangay.',
                'Napasa na sa OPPDC ang ${brgys.length} ka barangay.')
            : tr(
                '$checkedCount of ${brgys.length} barangays are checked. '
                    '${toCheck == 0 ? 'No paper set is waiting for you.' : '$toCheck paper set${toCheck == 1 ? ' is' : 's are'} waiting for you.'}',
                '$checkedCount sa ${brgys.length} barangay ang nasuri na. '
                    '${toCheck == 0 ? 'Walang papel na naghihintay.' : '$toCheck papel ang naghihintay sa inyo.'}',
                '$checkedCount sa ${brgys.length} ka barangay ang nausisa na. '
                    '${toCheck == 0 ? 'Wala sang papel nga nagahulat.' : '$toCheck ka papel ang nagahulat sa inyo.'}'),
        style: sans(16, color: const Color(0xFFD3E0EE), h: 1.5),
      ),
    ]);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [C.navy, Color(0xFF173E66)]),
        ),
        child: Stack(children: [
          Positioned(
            right: -30,
            top: -30,
            child: Icon(Icons.account_balance_outlined, size: 220, color: Colors.white.withValues(alpha: .05)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 26, 26, 30),
            child: LayoutBuilder(builder: (context, box) {
              if (box.maxWidth < 640) {
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [text, const SizedBox(height: 20), countdown]);
              }
              return Row(children: [Expanded(child: text), const SizedBox(width: 28), countdown]);
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

  // "Needs your attention": the reviewer's to-do list, most urgent first.
  Widget _attention() {
    final toCheck = by(BrgyStatus.submitted);
    final late = brgys.where((b) => b.status == BrgyStatus.notStarted || b.status == BrgyStatus.preparing).toList();
    final fixing = <BrgyRecord>[]; // no separate "fixing" stage on this side any more

    Widget task({
      required IconData icon,
      required Color tint,
      required String title,
      required String body,
      required Widget action,
    }) =>
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: C.line),
            borderRadius: BorderRadius.circular(14),
          ),
          child: LayoutBuilder(builder: (context, box) {
            final info = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: tint.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: tint, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: sans(17, w: FontWeight.w700, color: C.navy)),
                  const SizedBox(height: 3),
                  Text(body, style: sans(15, color: C.muted, h: 1.45)),
                ]),
              ),
            ]);
            if (box.maxWidth < 560) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                info,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: action),
              ]);
            }
            return Row(children: [Expanded(child: info), const SizedBox(width: 14), action]);
          }),
        );

    final tasks = <Widget>[
      if (allChecked && !store.sentToOppdc)
        task(
          icon: Icons.local_shipping_outlined,
          tint: C.green,
          title: tr('Every barangay is checked', 'Nasuri na ang lahat ng barangay', 'Nausisa na ang tanan nga barangay'),
          body: tr('Bring all the paper sets to OPPDC together, then mark them as submitted here.',
              'Dalhin nang sabay-sabay sa OPPDC ang lahat ng papel, saka markahang naipasa dito.',
              'Dal-a nga dungan sa OPPDC ang tanan nga papel, dayon markahan nga napasa diri.'),
          action: FilledButton.icon(
            style: primaryStyle(bg: C.green, fg: Colors.white),
            onPressed: _sendToOppdc,
            icon: const Icon(Icons.send_outlined, size: 18),
            label: Text(tr('Submit to OPPDC', 'Ipasa sa OPPDC', 'Ipasa sa OPPDC')),
          ),
        ),
      for (final b in toCheck)
        task(
          icon: Icons.fact_check_outlined,
          tint: C.yellowDark,
          title: tr('Documents on the way from Brgy. ${b.name}', 'Papunta na ang dokumento ng Brgy. ${b.name}',
              'Padulong na ang dokumento sang Brgy. ${b.name}'),
          body: tr('${b.tanods.length} tanods · shared ${b.updated}. Press Receive when the signed papers arrive at your office.',
              '${b.tanods.length} tanod · naibahagi ${b.updated}. Pindutin ang Tanggapin kapag dumating na ang pirmadong papel.',
              '${b.tanods.length} ka tanod · napaambit ${b.updated}. Pinduta ang Batunon kon nag-abot na ang may pirma nga papel.'),
          action: FilledButton.icon(
            style: primaryStyle(bg: C.green, fg: Colors.white),
            onPressed: () => _receive(b),
            icon: const Icon(Icons.move_to_inbox_rounded, size: 19),
            label: Text(tr('Receive', 'Tanggapin', 'Batunon')),
          ),
        ),
      if (unreadTotal > 0)
        task(
          icon: Icons.mark_chat_unread_outlined,
          tint: C.blue,
          title: tr('$unreadTotal new message${unreadTotal == 1 ? '' : 's'}', '$unreadTotal bagong mensahe', '$unreadTotal ka bag-o nga mensahe'),
          body: tr('Barangays replied or uploaded corrected copies.', 'Sumagot o nag-upload ng naitamang kopya ang mga barangay.',
              'Nagsabat ukon nag-upload sang natadlong nga kopya ang mga barangay.'),
          action: OutlinedButton.icon(
            style: outlineStyle(),
            onPressed: () => _go(_messagesTab),
            icon: const Icon(Icons.arrow_forward_rounded, size: 19),
            label: Text(tr('Open messages', 'Buksan ang mensahe', 'Buksan ang mensahe')),
          ),
        ),
      if (requests.isNotEmpty)
        task(
          icon: Icons.how_to_reg_outlined,
          tint: C.blue,
          title: tr('${requests.length} account request${requests.length == 1 ? '' : 's'}', '${requests.length} hiling na account',
              '${requests.length} ka hangyo sa account'),
          body: tr('New representatives can’t submit until you check their proof of designation.',
              'Hindi makakapagpasa ang bagong kinatawan hangga’t hindi nasusuri ang kanilang patunay.',
              'Indi makapasa ang bag-o nga representante samtang wala pa nausisa ang ila pamatuod.'),
          action: OutlinedButton.icon(
            style: outlineStyle(),
            onPressed: () => _go(_requestsTab),
            icon: const Icon(Icons.arrow_forward_rounded, size: 19),
            label: Text(tr('Check requests', 'Suriin ang hiling', 'Usisaa ang hangyo')),
          ),
        ),
      if (late.isNotEmpty)
        task(
          icon: Icons.notifications_active_outlined,
          tint: C.red,
          title: tr('${late.length} barangay${late.length == 1 ? ' hasn’t' : 's haven’t'} submitted',
              '${late.length} barangay ang hindi pa nakakapagpasa', '${late.length} ka barangay ang wala pa nakapasa'),
          body: tr('${late.map((b) => b.name).join(', ')}. OPPDC needs every barangay before $kMunicipality can submit.',
              '${late.map((b) => b.name).join(', ')}. Kailangan ng OPPDC ang lahat ng barangay bago makapagpasa ang $kMunicipality.',
              '${late.map((b) => b.name).join(', ')}. Kinahanglan sang OPPDC ang tanan nga barangay antes makapasa ang $kMunicipality.'),
          action: OutlinedButton.icon(
            style: outlineStyle(),
            onPressed: () => _remind(late),
            icon: const Icon(Icons.send_outlined, size: 18),
            label: Text(tr('Send reminder', 'Magpadala ng paalala', 'Magpadala sang pahanumdom')),
          ),
        ),
      if (fixing.isNotEmpty)
        task(
          icon: Icons.assignment_return_outlined,
          tint: C.muted,
          title: tr('${fixing.length} fixing corrections', '${fixing.length} ang nagtatama', '${fixing.length} ang nagatadlong'),
          body: tr('${fixing.map((b) => b.name).join(', ')}. They’ll upload the corrected copies and bring the paper back.',
              '${fixing.map((b) => b.name).join(', ')}. Mag-a-upload sila ng naitamang kopya at ibabalik ang papel.',
              '${fixing.map((b) => b.name).join(', ')}. Mag-upload sila sang natadlong nga kopya kag ibalik ang papel.'),
          action: TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(0, 46)),
            onPressed: () => _viewStatus(BrgyStatus.corrections),
            child: Text(tr('See', 'Tingnan', 'Tan-awa'), style: sans(15.5, w: FontWeight.w700, color: C.blue)),
          ),
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        border: Border.all(color: C.yellow, width: 2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('NEEDS YOUR ATTENTION', 'KAILANGAN NG INYONG PANSIN', 'KINAHANGLAN SANG IMO ATENSYON'),
            style: sans(14, w: FontWeight.w800, color: const Color(0xFF8A6A00)).copyWith(letterSpacing: .8)),
        const SizedBox(height: 14),
        if (tasks.isEmpty)
          Text(tr('You’re all caught up.', 'Wala nang natitirang gagawin.', 'Wala ka na sang nabilin nga himuon.'), style: serif(22))
        else
          for (final t in tasks) ...[t, const SizedBox(height: 10)],
      ]),
    );
  }

  // Status colours for the pop-ups: done = blue, to check = yellow, corrections = red
  NotifyType _statusType(BrgyStatus? s) => switch (s) {
        BrgyStatus.submitted => NotifyType.warning,
        BrgyStatus.corrections => NotifyType.error,
        _ => NotifyType.info,
      };

  void _setFilter(BrgyStatus? s) {
    setState(() => filter = s);
    final n = s == null ? brgys.length : by(s).length;
    toast(
      context,
      s == null
          ? tr('Showing all ${brgys.length} barangays.', 'Ipinapakita ang lahat ng ${brgys.length} barangay.', 'Ginapakita ang tanan nga ${brgys.length} ka barangay.')
          : tr('$n barangay${n == 1 ? '' : 's'}: ${statusLabel(s)}.', '$n barangay: ${statusLabel(s)}.', '$n ka barangay: ${statusLabel(s)}.'),
      type: _statusType(s),
      title: s == null ? tr('Filter cleared', 'Inalis ang filter', 'Ginkuha ang filter') : tr('Filter applied', 'Na-filter', 'Na-filter'),
    );
  }

  // "View" on a tile: open the Barangays page filtered to that status
  void _viewStatus(BrgyStatus s) {
    setState(() => navIndex = 1);
    _setFilter(s);
  }

  // 5 tiles, one per stage. Colours match the "Where every barangay is" bar below.
  Widget _stats() {
    final n = brgys.length;
    final onTheWay = by(BrgyStatus.submitted).length;
    final notStarted = by(BrgyStatus.notStarted).length;
    return Grid(maxCols: 3, minWidth: 220, children: [
      StatTile(
        icon: Icons.verified_outlined,
        tint: statusBar(BrgyStatus.checked),
        value: '$checkedCount / $n',
        label: tr('Barangays complete', 'Kumpletong barangay', 'Kompleto nga barangay'),
        note: tr('Documents received', 'Natanggap na ang dokumento', 'Nabaton na ang dokumento'),
        progress: n == 0 ? 0 : checkedCount / n,
        onView: () => _viewStatus(BrgyStatus.checked),
      ),
      StatTile(
        icon: Icons.local_shipping_outlined,
        tint: statusBar(BrgyStatus.submitted),
        value: '$onTheWay',
        label: tr('Documents on the way', 'Papunta na ang dokumento', 'Padulong na ang dokumento'),
        note: onTheWay == 0
            ? tr('Nothing shared yet', 'Wala pang naibahagi', 'Wala pa sang napaambit')
            : tr('Shared by the barangay. Press Receive when the papers arrive.',
                'Naibahagi ng barangay. Pindutin ang Tanggapin pagdating ng papel.',
                'Napaambit sang barangay. Pinduta ang Batunon kon mag-abot ang papel.'),
        onView: () => _viewStatus(BrgyStatus.submitted),
      ),
      StatTile(
        icon: Icons.hourglass_empty_rounded,
        tint: C.muted, // the bar's light grey is too pale for text, so a darker grey here
        value: '$notStarted',
        label: tr('Not started', 'Hindi pa nagsisimula', 'Wala pa nagsugod'),
        note: tr('No documents yet', 'Wala pang dokumento', 'Wala pa sang dokumento'),
        onView: () => _viewStatus(BrgyStatus.notStarted),
      ),
    ]);
  }

  // Compact "line" version: title + bar on one row, small legend underneath
  Widget _progressBoard() {
    final order = [BrgyStatus.checked, BrgyStatus.submitted, BrgyStatus.notStarted];
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 10,
        child: Row(children: [
          for (final s in order)
            if (by(s).isNotEmpty) Expanded(flex: by(s).length, child: ColoredBox(color: statusBar(s))),
        ]),
      ),
    );
    final title = Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.stacked_bar_chart_rounded, size: 18, color: C.navy),
      const SizedBox(width: 8),
      Text(tr('Where every barangay is', 'Nasaan na ang bawat barangay', 'Diin na ang kada barangay'),
          style: sans(15, w: FontWeight.w700, color: C.navy)),
    ]);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: C.line), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, box) => box.maxWidth >= 620
            ? Row(children: [title, const SizedBox(width: 16), Expanded(child: bar)])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [title, const SizedBox(height: 8), bar])),
        const SizedBox(height: 8),
        Wrap(spacing: 14, runSpacing: 4, children: [
          for (final s in order)
            if (by(s).isNotEmpty)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 9, height: 9, decoration: BoxDecoration(color: statusBar(s), borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 5),
                Text('${statusLabel(s)} · ${by(s).length}', style: sans(13, color: C.muted)),
              ]),
        ]),
      ]),
    );
  }

  // ---------- barangay table / list ----------
  Widget _barangayTable(List<BrgyRecord> list, {String? title}) {
    return Panel(
      title: title,
      icon: title == null ? null : Icons.holiday_village_outlined,
      trailing: title == null
          ? null
          : TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => _go(1),
              child: Text(tr('Filter & search', 'Salain at hanapin', 'Salaa kag pangitaa'), style: sans(15, w: FontWeight.w700, color: C.blue)),
            ),
      child: LayoutBuilder(builder: (context, box) {
        final table = box.maxWidth >= 900;
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(tr('No barangays here.', 'Walang barangay dito.', 'Wala sang barangay diri.'),
                textAlign: TextAlign.center, style: sans(15.5, color: C.muted)),
          );
        }
        final th = sans(13, w: FontWeight.w700, color: C.muted).copyWith(letterSpacing: .6);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (table)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: C.mist, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Expanded(flex: 3, child: Text(tr('BARANGAY', 'BARANGAY', 'BARANGAY'), style: th)),
                Expanded(flex: 3, child: Text(tr('STATUS', 'KALAGAYAN', 'KAHIMTANGAN'), style: th)),
                Expanded(flex: 2, child: Text(tr('TANODS', 'TANOD', 'TANOD'), style: th)),
                Expanded(flex: 3, child: Text(tr('BACKUP COPIES', 'BACKUP', 'BACKUP'), style: th)),
                const SizedBox(width: 160),
              ]),
            ),
          for (final b in list) table ? _row(b) : _tile(b),
        ]);
      }),
    );
  }

  Widget _statusPill(BrgyRecord b) {
    final g = muniStage(b.status);
    final (bg, fg) = statusColors(g);
    return pill(statusLabel(g), bg, fg);
  }

  // Four squares, one per document: green done, red correction, yellow out of date, grey none.
  Widget _dots(BrgyRecord b) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (final k in kBarangayDocs)
          Tooltip(
            message: k.title,
            child: Container(
              width: 15,
              height: 15,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                color: b.files[k]!.correction
                    ? C.red
                    : b.files[k]!.outdated
                        ? C.yellowDark
                        : b.files[k]!.uploaded
                            ? C.green
                            : const Color(0xFFE3EAF2),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        const SizedBox(width: 4),
        Text('${b.backupCount}/${kBarangayDocs.length}', style: sans(14.5, color: C.muted)),
      ]);

  // Each barangay: Remind (not shared yet) and Receive (documents on the way)
  Widget _action(BrgyRecord b) {
    const size = WidgetStatePropertyAll(Size(140, 42));
    final complete = !notChecked.contains(b);
    if (complete) {
      return OutlinedButton.icon(
        style: outlineStyle().copyWith(minimumSize: size),
        onPressed: () => _openDocs(b),
        icon: const Icon(Icons.folder_open_outlined, size: 18),
        label: Text(tr('Documents', 'Dokumento', 'Dokumento')),
      );
    }
    final onTheWay = b.status == BrgyStatus.submitted;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      if (!onTheWay)
        OutlinedButton.icon(
          style: outlineStyle().copyWith(minimumSize: size),
          onPressed: () => _remind([b]),
          icon: const Icon(Icons.notifications_none_rounded, size: 18),
          label: Text(tr('Remind', 'Paalalahanan', 'Pahanumdumi')),
        ),
      if (!onTheWay) const SizedBox(height: 6),
      FilledButton.icon(
        style: primaryStyle(bg: C.green, fg: Colors.white).copyWith(minimumSize: size),
        onPressed: onTheWay ? () => _receive(b) : null,
        icon: const Icon(Icons.move_to_inbox_rounded, size: 18),
        label: Text(tr('Receive', 'Tanggapin', 'Batunon')),
      ),
    ]);
  }

  /// The barangay's signed papers arrived: it becomes "Complete".
  Future<void> _receive(BrgyRecord b) async {
    final ok = await confirmAction(
      context,
      title: tr('Receive the documents of Brgy. ${b.name}?', 'Tanggapin ang dokumento ng Brgy. ${b.name}?',
          'Batunon ang dokumento sang Brgy. ${b.name}?'),
      message: tr('Confirm that the signed papers of Brgy. ${b.name} arrived at your office. The barangay will be marked Complete.',
          'Kumpirmahin na dumating na sa opisina ang pirmadong papel ng Brgy. ${b.name}. Mamarkahan itong Kumpleto.',
          'Kumpirmaha nga nag-abot na sa opisina ang may pirma nga papel sang Brgy. ${b.name}. Markahan ini nga Kompleto.'),
      confirmLabel: tr('Receive', 'Tanggapin', 'Batunon'),
      icon: Icons.move_to_inbox_rounded,
    );
    if (!ok || !mounted) return;
    if (!await _cloud(() => cloud.markChecked(b)) || !mounted) return; // FIREBASE: verified
    setState(() {
      b.status = BrgyStatus.checked;
      if (!cloud.isMunicipal) b.post(fromMunicipality: true, system: true, text: 'Documents received. Thank you!');
    });
    toast(context, tr('Brgy. ${b.name} is complete.', 'Kumpleto na ang Brgy. ${b.name}.', 'Kompleto na ang Brgy. ${b.name}.'),
        title: tr('Documents received', 'Natanggap ang dokumento', 'Nabaton ang dokumento'));
  }

  Future<void> _openDocs(BrgyRecord b) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MuniDocsPage(rec: b)));
    if (mounted) setState(() {});
  }

  // ================= Documents tab =================
  Widget _docsPage() {
    final order = [
      ...by(BrgyStatus.submitted),
      ...brgys.where((b) => !notChecked.contains(b)),
      ...brgys.where((b) => notChecked.contains(b) && b.status != BrgyStatus.submitted),
    ];
    return _scroll([
      Row(children: [
        Expanded(child: Text(tr('Documents', 'Mga Dokumento', 'Mga Dokumento'), style: serif(28))),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: C.navy, foregroundColor: Colors.white, minimumSize: const Size(0, 46)),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ArchivePage(municipalityId: archiveMuniId(kMunicipality), title: 'Municipality of $kMunicipality'))),
          icon: const Icon(Icons.inventory_2_outlined, size: 18),
          label: Text(tr('Open archive', 'Buksan ang archive', 'Buksan ang archive')),
        ),
      ]),
      const SizedBox(height: 6),
      Text(
          tr('One Payroll and one Masterlist for all of $kMunicipality, made from every barangay’s tanod list in the database. '
                  'Each barangay’s Certification and ID photocopy sheet are inside its folder below.',
              'Iisang Payroll at Masterlist para sa buong $kMunicipality, mula sa listahan ng bawat barangay. '
                  'Nasa folder ng bawat barangay ang Certification at ID photocopy sheet nito.',
              'Isa ka Payroll kag Masterlist para sa bug-os nga $kMunicipality, halin sa listahan sang kada barangay. '
                  'Ara sa folder sang kada barangay ang Certification kag ID photocopy sheet sini.'),
          style: sans(15.5, color: C.muted, h: 1.5)),
      const SizedBox(height: 18),
      const MunicipalDocs(), // ONE Payroll + ONE Masterlist
      const SizedBox(height: 24),
      Text(tr('Per barangay: Certification & ID photocopy sheet', 'Bawat barangay: Certification at ID photocopy sheet',
              'Kada barangay: Certification kag ID photocopy sheet'),
          style: sans(18, w: FontWeight.w700, color: C.navy)),
      const SizedBox(height: 10),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final b in order)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE9EFF5)))),
              child: Row(children: [
                const Icon(Icons.folder_outlined, color: C.navy),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Brgy. ${b.name}', style: sans(16.5, w: FontWeight.w700, color: C.navy)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      _statusPill(b),
                      Text(tr('${b.tanods.length} tanods', '${b.tanods.length} tanod', '${b.tanods.length} ka tanod'),
                          style: sans(14, color: C.muted)),
                    ]),
                  ]),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: outlineStyle(),
                  onPressed: b.tanods.isEmpty ? null : () => _openDocs(b),
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: Text(tr('Open', 'Buksan', 'Buksan')),
                ),
              ]),
            ),
        ]),
      ),
    ]);
  }

  Widget _unread(BrgyRecord b) => b.unreadMuni == 0
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Badge(
            label: Text('${b.unreadMuni}'),
            child: const Icon(Icons.chat_bubble_outline_rounded, size: 20, color: C.blue),
          ),
        );

  Widget _row(BrgyRecord b) => InkWell(
        onTap: () => _open(b),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE9EFF5)))),
          child: Row(children: [
            Expanded(
              flex: 3,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(b.name, overflow: TextOverflow.ellipsis, style: sans(16.5, w: FontWeight.w700, color: C.navy))),
                  _unread(b),
                ]),
                Text(
                  b.accountPending
                      ? '${_repLine(b)} · ${tr('account pending', 'naghihintay ang account', 'nagahulat ang account')}'
                      : _repLine(b),
                  overflow: TextOverflow.ellipsis,
                  style: sans(14, color: b.accountPending ? const Color(0xFF7A5B00) : C.muted),
                ),
              ]),
            ),
            Expanded(
              flex: 3,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _statusPill(b),
                const SizedBox(height: 3),
                Text(tr('Updated ${b.updated}', 'Na-update ${b.updated}', 'Na-update ${b.updated}'), style: sans(13.5, color: C.muted)),
              ]),
            ),
            Expanded(flex: 2, child: Text('${b.tanods.length} / ${b.quota}', style: sans(16, w: FontWeight.w600))),
            Expanded(flex: 3, child: _dots(b)),
            SizedBox(width: 160, child: Align(alignment: Alignment.centerRight, child: _action(b))),
          ]),
        ),
      );

  Widget _tile(BrgyRecord b) => InkWell(
        onTap: () => _open(b),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE9EFF5)))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(b.name, style: sans(17, w: FontWeight.w700, color: C.navy))),
              _unread(b),
              const SizedBox(width: 8),
              _statusPill(b),
            ]),
            const SizedBox(height: 4),
            Text(
              b.accountPending
                  ? '${_repLine(b)} · ${tr('account pending', 'naghihintay ang account', 'nagahulat ang account')}'
                  : _repLine(b),
              style: sans(14.5, color: b.accountPending ? const Color(0xFF7A5B00) : C.muted),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 16, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(tr('${b.tanods.length} / ${b.quota} tanods', '${b.tanods.length} / ${b.quota} tanod', '${b.tanods.length} / ${b.quota} ka tanod'),
                  style: sans(15, w: FontWeight.w600)),
              _dots(b),
            ]),
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: _action(b)),
          ]),
        ),
      );

  // ================= Barangays page =================
  Widget _barangaysPage() {
    final q = search.toLowerCase();
    final list = brgys
        .where((b) => filter == null || muniStage(b.status) == filter)
        .where((b) => q.isEmpty || b.name.toLowerCase().contains(q) || b.rep.toLowerCase().contains(q))
        .toList();

    Widget chip(BrgyStatus? s) {
      final on = filter == s;
      final count = s == null ? brgys.length : by(s).length;
      return ChoiceChip(
        label: Text('${s == null ? tr('All', 'Lahat', 'Tanan') : statusLabel(s)} ($count)',
            style: sans(15, w: FontWeight.w600, color: on ? Colors.white : C.navy)),
        selected: on,
        showCheckmark: false,
        selectedColor: C.navy,
        backgroundColor: Colors.white,
        side: BorderSide(color: on ? C.navy : C.line, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        onSelected: (_) => _setFilter(s),
      );
    }

    return _scroll([
      Text(tr('Barangays', 'Mga Barangay', 'Mga Barangay'), style: serif(28)),
      const SizedBox(height: 6),
      Text(tr('Every barangay in $kMunicipality and where its paper set is.', 'Bawat barangay sa $kMunicipality at kung nasaan na ang papel nito.',
          'Kada barangay sa $kMunicipality kag kon diin na ang papel sini.'), style: sans(16, color: C.muted, h: 1.5)),
      const SizedBox(height: 18),
      TextField(
        style: sans(16),
        onChanged: (v) => setState(() => search = v),
        decoration: fieldDecoration(tr('Search barangay or representative', 'Hanapin ang barangay o kinatawan',
            'Pangitaa ang barangay ukon representante'), Icons.search_rounded),
      ),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: [
        chip(null),
        chip(BrgyStatus.checked),
        chip(BrgyStatus.submitted),
        chip(BrgyStatus.notStarted),
      ]),
      const SizedBox(height: 18),
      _barangayTable(list),
    ]);
  }

  // ================= Messages =================
  Widget _messagesPage() {
    final list = [...brgys.where((b) => b.chat.isNotEmpty)]..sort((a, b) => b.unreadMuni.compareTo(a.unreadMuni));
    return _scroll([
      Text(tr('Messages', 'Mga Mensahe', 'Mga Mensahe'), style: serif(28)),
      const SizedBox(height: 6),
      Text(
        tr('One conversation per barangay. Tell them what’s wrong on the paper copy; they fix it and upload the corrected copy.',
            'Isang usapan bawat barangay. Sabihin ang mali sa papel; itatama nila ito at ia-upload ang naitamang kopya.',
            'Isa ka istoryahanay kada barangay. Isugid ang sala sa papel; tadlungon nila ini kag i-upload ang natadlong nga kopya.'),
        style: sans(16, color: C.muted, h: 1.5),
      ),
      const SizedBox(height: 20),
      Panel(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(children: [
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(tr('No messages yet.', 'Wala pang mensahe.', 'Wala pa sang mensahe.'), style: sans(15.5, color: C.muted)),
            ),
          for (final b in list)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () => _open(b),
              leading: CircleAvatar(
                radius: 22,
                backgroundColor: C.blueSoft,
                child: Text(b.name.substring(0, 2).toUpperCase(), style: sans(15, w: FontWeight.w700, color: C.blue)),
              ),
              title: Row(children: [
                Expanded(child: Text('Brgy. ${b.name}', style: sans(16.5, w: FontWeight.w700, color: C.navy))),
                Text(b.last?.time ?? '', style: sans(13.5, color: C.muted)),
              ]),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  b.last == null
                      ? ''
                      : '${b.last!.fromMunicipality ? tr('You: ', 'Kayo: ', 'Ikaw: ') : ''}${b.last!.doc == null ? '' : '${b.last!.doc!.title}: '}${b.last!.text}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: sans(15, color: b.unreadMuni > 0 ? C.ink : C.muted, w: b.unreadMuni > 0 ? FontWeight.w600 : FontWeight.w400),
                ),
              ),
              trailing: b.unreadMuni > 0
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(color: C.yellow, borderRadius: BorderRadius.circular(99)),
                      child: Text('${b.unreadMuni}', style: sans(13.5, w: FontWeight.w800, color: C.navy)),
                    )
                  : const Icon(Icons.chevron_right_rounded, color: C.muted),
            ),
        ]),
      ),
    ]);
  }

  // ================= Account requests =================
  Widget _requestsPage() {
    return _scroll([
      Text(tr('Account requests', 'Mga hiling na account', 'Mga hangyo sa account'), style: serif(28)),
      const SizedBox(height: 6),
      Text(
          tr('Barangay representatives who registered. Check their proof of designation before they can submit.',
              'Mga kinatawan ng barangay na nagparehistro. Suriin ang kanilang patunay bago sila makapagpasa.',
              'Mga representante sang barangay nga nagparehistro. Usisaa ang ila pamatuod antes sila makapasa.'),
          style: sans(16, color: C.muted, h: 1.5)),
      const SizedBox(height: 20),
      if (requests.isEmpty)
        Panel(
          child: Column(children: [
            const Icon(Icons.inbox_outlined, size: 40, color: C.muted),
            const SizedBox(height: 10),
            Text(tr('No requests right now.', 'Walang hiling ngayon.', 'Wala sang hangyo subong.'), style: serif(22)),
            const SizedBox(height: 4),
            Text(tr('New sign-ups from your barangays will show up here.', 'Lalabas dito ang bagong nagparehistro.',
                'Diri magguwa ang bag-o nga nagparehistro.'), style: sans(15.5, color: C.muted)),
          ]),
        ),
      for (final r in [...requests]) ...[
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: C.blueSoft,
                child: Text(r.name.split(' ').where((p) => p.isNotEmpty).take(2).map((p) => p[0]).join(),
                    style: sans(15, w: FontWeight.w700, color: C.blue)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.name, style: sans(18, w: FontWeight.w700, color: C.navy)),
                  Text('${r.position} · Brgy. ${r.barangay}', style: sans(15.5, color: C.muted)),
                ]),
              ),
              Text(tr('Sent ${r.sent}', 'Ipinadala ${r.sent}', 'Ginpadala ${r.sent}'), style: sans(14, color: C.muted)),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: C.mist, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _kv(tr('Mobile', 'Mobile', 'Mobile'), r.mobile),
                _kv(tr('Proof of designation', 'Patunay ng pagkatalaga', 'Pamatuod sang pagkatalaga'), r.proof),
              ]),
            ),
            const SizedBox(height: 14),
            Wrap(alignment: WrapAlignment.end, spacing: 10, runSpacing: 10, children: [
              OutlinedButton.icon(
                style: outlineStyle(fg: C.red, border: const Color(0xFFF0C7C3)),
                onPressed: () => _declineRequest(r),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: Text(tr('Decline', 'Tanggihan', 'Balibaran')),
              ),
              FilledButton.icon(
                style: primaryStyle(bg: C.green, fg: Colors.white),
                onPressed: () => _approveRequest(r),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(tr('Approve', 'Aprubahan', 'Aprobahan')),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
      ],
    ]);
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 180, child: Text(k, style: sans(15, color: C.muted))),
          Expanded(child: Text(v, style: sans(15.5, w: FontWeight.w600))),
        ]),
      );

  // ================= Account =================
  Widget _accountPage() {
    // [colors]: optional colour per option (same order), like the barangay Account page
    Widget choices<T>(String label, T current, List<(T, String)> options, void Function(T) onPick, {List<Color>? colors}) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: sans(16, w: FontWeight.w700, color: C.navy)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < options.length; i++)
              Builder(builder: (context) {
                final (v, text) = options[i];
                final on = current == v;
                final c = colors == null ? C.navy : colors[i];
                final onText = c == C.yellowDark ? C.navy : Colors.white; // dark text on yellow
                return ChoiceChip(
                  label: Text(text, style: sans(15.5, w: FontWeight.w600, color: on ? onText : (colors == null ? C.navy : c))),
                  selected: on,
                  showCheckmark: false,
                  selectedColor: c,
                  backgroundColor: colors == null ? Colors.white : c.withValues(alpha: .08),
                  side: BorderSide(color: on ? c : (colors == null ? C.line : c.withValues(alpha: .45)), width: 1.5),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  onSelected: (_) => onPick(v),
                );
              }),
          ]),
        ]);

    return _scroll([
      Text(tr('Account', 'Account', 'Account'), style: serif(28)),
      const SizedBox(height: 6),
      Text(tr('Your details and display settings.', 'Ang inyong detalye at settings.', 'Ang imo detalye kag settings.'),
          style: sans(16, color: C.muted, h: 1.5)),
      const SizedBox(height: 20),
      // Account details first, then display settings (same order as the barangay side)
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CircleAvatar(radius: 30, backgroundColor: C.yellow, child: Text('LT', style: serif(22))),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(kReviewerName, style: serif(24)),
                const SizedBox(height: 4),
                pill(_reviewerRole(), C.blueSoft, C.blue, icon: Icons.verified_user_outlined),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          const Divider(color: Color(0xFFE3EAF2)),
          _kv(tr('Municipality', 'Munisipyo', 'Banwa'), kMunicipality),
          _kv(tr('Barangays', 'Mga barangay', 'Mga barangay'), '${brgys.length}'),
          _kv(tr('Account from', 'Account mula sa', 'Account halin sa'),
              tr('OPPDC (username and temporary password)', 'OPPDC (username at pansamantalang password)',
                  'OPPDC (username kag temporaryo nga password)')),
          // Sign out is in the side menu / profile menu (same as the barangay side)
        ]),
      ),
      const SizedBox(height: 20),
      Panel(
        title: tr('Display', 'Itsura', 'Itsura'),
        icon: Icons.text_fields_rounded,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          choices<double>(
            tr('Text size', 'Laki ng letra', 'Kadako sang letra'),
            textSize.value,
            [
              (1.0, tr('Normal', 'Normal', 'Normal')),
              (1.15, tr('Large', 'Malaki', 'Dako')),
              (1.3, tr('Larger', 'Mas malaki', 'Mas dako')),
            ],
            (v) {
              textSize.value = v;
              toast(context, tr('Text size changed.', 'Napalitan ang laki ng letra.', 'Nabag-o ang kadakuon sang letra.'), type: NotifyType.info,
                  title: tr('Display updated', 'Na-update ang itsura', 'Na-update ang itsura'));
            },
            colors: const [C.blue, C.green, C.yellowDark], // Normal, Large, Larger
          ),
          const SizedBox(height: 22),
          choices<String>(
            tr('Language', 'Wika', 'Pinulongan'),
            appLang.value,
            const [('en', 'English'), ('fil', 'Filipino'), ('hil', 'Hiligaynon')],
            (v) {
              setState(() => appLang.value = v); // redraw this screen in the new language
              toast(context, tr('Language set to English.', 'Filipino na ang wika.', 'Hiligaynon na ang lenggwahe.'), type: NotifyType.info,
                  title: tr('Language changed', 'Napalitan ang wika', 'Nabag-o ang lenggwahe'));
            },
          ),
          const SizedBox(height: 8),
          Text(
            tr('Filipino and Hiligaynon are first drafts.', 'Unang bersyon pa lang ang Filipino at Hiligaynon.',
                'Una pa lang nga bersyon ang Filipino kag Hiligaynon.'),
            style: sans(14, color: C.muted),
          ),
        ]),
      ),
    ]);
  }
}