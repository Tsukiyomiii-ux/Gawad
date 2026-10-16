import 'package:flutter/material.dart';
import 'package:tanod_incentives/screens/archive/archive_page.dart'; // ARCHIVE

import 'package:tanod_incentives/theme.dart';
import 'package:tanod_incentives/data/admin_data.dart';
import 'package:tanod_incentives/data/doc_kind.dart';
import 'package:tanod_incentives/data/cloud.dart';
import 'package:tanod_incentives/services/database_service.dart' show Status;
import 'package:tanod_incentives/widgets/ui.dart';
import 'package:tanod_incentives/screens/auth/auth_page.dart';
import 'package:tanod_incentives/screens/admin/admin_docs_page.dart';

// ADMIN (OPPDC) dashboard: the provincial level.
// Pages: Overview, Municipalities, Documents, Analytics, Account.
// Data: data/admin_data.dart (live Firebase, or demo when signed in as "oppdc").

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _NavItem {
  final IconData icon, activeIcon;
  final String label;
  const _NavItem(this.icon, this.activeIcon, this.label);
}

const _nav = [
  _NavItem(Icons.space_dashboard_outlined, Icons.space_dashboard, 'Overview'),
  _NavItem(Icons.location_city_outlined, Icons.location_city, 'Municipalities'),
  _NavItem(Icons.folder_open_outlined, Icons.folder, 'Documents'),
  _NavItem(Icons.insights_outlined, Icons.insights, 'Analytics'),
  _NavItem(Icons.person_outline, Icons.person, 'Account'),
];

// ---------------- status look (shared with the docs page) ----------------

/// Barangay status → (label, background, text colour)
/// Same 5 stages as the barangay's "Submission status"
(String, Color, Color) brgyLook(AdminBrgy b) {
  final i = brgyStage(b);
  return switch (i) {
    1 => (kStageNames[i], const Color(0xFFFFF4CC), const Color(0xFF7A5B00)),
    2 => (kStageNames[i], C.blueSoft, C.blue),
    3 => (kStageNames[i], const Color(0xFFE6E9FB), const Color(0xFF3A4BB0)),
    4 => (kStageNames[i], C.greenSoft, const Color(0xFF14583D)),
    _ => (kStageNames[0], const Color(0xFFEDF1F5), C.muted),
  };
}

/// Municipality status (with OPPDC) → (label, background, text colour)
(String, Color, Color) muniLook(AdminMuni m) => switch (m.status) {
      Status.verified => ('Verified by OPPDC', C.greenSoft, const Color(0xFF14583D)),
      Status.submitted => ('Waiting for OPPDC', const Color(0xFFFFF4CC), const Color(0xFF7A5B00)),
      Status.returned => ('Returned', const Color(0xFFFDF0EE), C.red),
      _ => ('Checking barangays', C.blueSoft, C.blue),
    };

Color brgyBar(AdminBrgy b) => _stageColors[brgyStage(b)];

const _stageColors = [Color(0xFFB4C2D1), C.yellowDark, C.blue, Color(0xFF3A4BB0), C.green];

String peso(num v) {
  final s = v.round().toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return '₱$out';
}

Widget statusPill((String, Color, Color) look) => pill(look.$1, look.$2, look.$3);

class _AdminPageState extends State<AdminPage> {
  int navIndex = 0;
  String search = '';
  final Set<String> _open = {}; // expanded municipalities
  String _docsFilter = 'all'; // all / verified / submitted
  int? _year; // Analytics: selected year

  @override
  void initState() {
    super.initState();
    admin.changes.addListener(_redraw);
    cloud.errors.addListener(_onError);
  }

  @override
  void dispose() {
    admin.changes.removeListener(_redraw);
    cloud.errors.removeListener(_onError);
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  void _onError() {
    final m = cloud.errors.value;
    if (m == null || !mounted) return;
    toast(context, m, type: NotifyType.error, title: 'Firebase');
    cloud.errors.value = null;
  }

  void _go(int i) => setState(() => navIndex = i);

  Future<void> _signOut() async {
    final ok = await confirmAction(
      context,
      title: 'Sign out?',
      message: 'You can sign back in any time.',
      confirmLabel: 'Sign out',
      icon: Icons.logout_rounded,
      danger: true,
    );
    if (!ok || !mounted) return;
    await admin.close();
    await cloud.signOut();
    if (!mounted) return;
    toast(context, 'You have signed out.', type: NotifyType.info, title: 'Signed out');
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AuthPage()));
  }

  // ======================= ACTIONS =======================

  Future<void> _editLimit(AdminBrgy b) async {
    final ctrl = TextEditingController(text: '${b.limit}');
    final note = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        int value() => int.tryParse(ctrl.text.trim()) ?? b.limit;
        void bump(int d) => setD(() => ctrl.text = '${(value() + d).clamp(1, 999)}');
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Tanod limit · Brgy. ${b.name}', style: serif(22)),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('${b.muniName} · ${b.tanods} tanods listed this year. The limit can’t go below that.',
                    style: sans(14.5, color: C.muted, h: 1.45)),
                const SizedBox(height: 16),
                Row(children: [
                  IconButton.filledTonal(onPressed: () => bump(-1), icon: const Icon(Icons.remove_rounded)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: ctrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: sans(22, w: FontWeight.w700, color: C.navy),
                      decoration: fieldDecoration('', Icons.groups_outlined),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        if (n == null || n < 1) return 'Enter a number (1 or more).';
                        if (n < b.tanods) return 'Below the ${b.tanods} tanods already listed.';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(onPressed: () => bump(1), icon: const Icon(Icons.add_rounded)),
                ]),
                const SizedBox(height: 14),
                TextFormField(
                  controller: note,
                  style: sans(15),
                  decoration: fieldDecoration('Reason, e.g. Ordinance No. 2026-15', Icons.edit_note_rounded),
                  validator: (v) => admin.live && (v ?? '').trim().isEmpty ? 'Write the reason (e.g. the ordinance number).' : null,
                ),
                const SizedBox(height: 8),
                Text('If this town already gave out award numbers this year, the new limit starts next year so nobody’s number changes.',
                    style: sans(13, color: C.muted, h: 1.4)),
              ]),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton.icon(
              style: primaryStyle(bg: C.navy, fg: Colors.white),
              onPressed: () {
                if (formKey.currentState!.validate()) Navigator.pop(ctx, value());
              },
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save limit'),
            ),
          ],
        );
      }),
    );
    final reason = note.text.trim();
    Future.delayed(const Duration(milliseconds: 400), () {
      ctrl.dispose();
      note.dispose();
    });
    if (saved == null || saved == b.limit || !mounted) return;
    try {
      final now = await admin.setLimit(b, saved, reason.isEmpty ? 'Changed by OPPDC' : reason);
      if (!mounted) return;
      toast(
        context,
        now
            ? 'Brgy. ${b.name} can now list up to $saved tanods this year.'
            : 'Saved. Award numbers are already in use in ${b.muniName}, so the new limit of $saved starts next year.',
        type: now ? NotifyType.success : NotifyType.info,
        title: 'Limit updated',
      );
    } catch (e) {
      if (mounted) toast(context, Cloud.friendly(e), type: NotifyType.error, title: 'Not saved');
    }
  }

  Future<void> _review(AdminMuni m, {required bool approve}) async {
    var note = '';
    if (approve) {
      final ok = await confirmAction(
        context,
        title: 'Verify ${m.name}?',
        message: 'All ${m.brgys.length} barangays’ paper sets were received and are correct.',
        confirmLabel: 'Verify',
        icon: Icons.verified_outlined,
      );
      if (!ok) return;
    } else {
      final ctrl = TextEditingController();
      final send = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Return ${m.name}?', style: serif(22)),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Write what needs fixing. It is sent to the municipality’s messages.', style: sans(14.5, color: C.muted, h: 1.45)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                minLines: 2,
                maxLines: 4,
                style: sans(15),
                decoration: fieldDecoration('e.g. Brgy. Ungka I payroll is missing 2 signatures.', Icons.edit_note_rounded),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: primaryStyle(bg: C.red, fg: Colors.white),
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim().isNotEmpty),
              child: const Text('Return'),
            ),
          ],
        ),
      );
      note = ctrl.text.trim();
      Future.delayed(const Duration(milliseconds: 400), ctrl.dispose);
      if (send != true) {
        if (mounted && send == false && note.isEmpty) return;
        if (mounted && note.isEmpty) toast(context, 'Write what needs fixing first.', type: NotifyType.warning);
        return;
      }
    }
    try {
      await admin.reviewMuni(m, approve: approve, note: note);
      if (!mounted) return;
      toast(context, approve ? '${m.name} is verified.' : '${m.name} was returned. They’ll see your note in their messages.',
          type: approve ? NotifyType.success : NotifyType.info, title: approve ? 'Municipality verified' : 'Returned');
    } catch (e) {
      if (mounted) toast(context, Cloud.friendly(e), type: NotifyType.error, title: 'Not saved');
    }
  }

  void _openDocs(AdminBrgy b) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminDocsPage(brgy: b)));

  // ======================= SHELL =======================

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 1000;
    final page = switch (navIndex) {
      1 => _municipalitiesPage(),
      2 => _documentsPage(),
      3 => _analyticsPage(),
      4 => _accountPage(),
      _ => _overviewPage(),
    };
    final waiting = admin.munis.where((m) => m.status == Status.submitted).length;
    return Scaffold(
      backgroundColor: C.mist,
      body: SafeArea(
        child: Row(children: [
          if (wide) _sidebar(waiting),
          Expanded(
            child: Column(children: [
              _topBar(wide),
              Expanded(child: page),
            ]),
          ),
        ]),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: navIndex,
              onDestinationSelected: _go,
              backgroundColor: Colors.white,
              indicatorColor: C.yellow,
              destinations: [
                for (var i = 0; i < _nav.length; i++)
                  NavigationDestination(
                    icon: i == 0 && waiting > 0 ? Badge(label: Text('$waiting'), child: Icon(_nav[i].icon)) : Icon(_nav[i].icon),
                    selectedIcon: Icon(_nav[i].activeIcon),
                    label: _nav[i].label,
                  ),
              ],
            ),
    );
  }

  Widget _topBar(bool wide) => Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
        child: Row(children: [
          if (!wide) ...[logoMark(34), const SizedBox(width: 10)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_nav[navIndex].label, overflow: TextOverflow.ellipsis, style: sans(20, w: FontWeight.w700, color: C.navy)),
              Text('Province of Iloilo · OPPDC · $kYearLabel', overflow: TextOverflow.ellipsis, style: sans(14, color: C.muted)),
            ]),
          ),
          if (!admin.live)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFFFF4CC), borderRadius: BorderRadius.circular(99)),
              child: Text('Demo data', style: sans(13.5, w: FontWeight.w700, color: const Color(0xFF7A5B00))),
            ),
          const SizedBox(width: 10),
          PopupMenuButton<String>(
            tooltip: 'Account',
            color: Colors.white,
            onSelected: (v) => v == 'out' ? _signOut() : _go(4),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'account', child: Text('Account')),
              PopupMenuItem(value: 'out', child: Text('Sign out', style: sans(15, color: C.red))),
            ],
            child: CircleAvatar(
              radius: 20,
              backgroundColor: C.yellow,
              child: Text(_initials(admin.adminName), style: sans(14, w: FontWeight.w800, color: C.navy)),
            ),
          ),
        ]),
      );

  String get kYearLabel => '${admin.year}';

  String _initials(String n) {
    final p = n.split(' ').where((s) => s.isNotEmpty && s[0].toUpperCase() == s[0]).take(2).map((s) => s[0]).join();
    return p.isEmpty ? 'OP' : p.toUpperCase();
  }

  Widget _sidebar(int waiting) {
    Widget item(int i) {
      final n = _nav[i];
      final on = i == navIndex;
      final count = i == 0 ? waiting : 0;
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
            Text('PROVINCE', style: sans(12, w: FontWeight.w700, color: const Color(0xFF8FA6BF)).copyWith(letterSpacing: .8)),
            const SizedBox(height: 4),
            Text('Iloilo · OPPDC', style: sans(16.5, w: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 2),
            Text('${admin.munis.length} municipalities · ${admin.year}', style: sans(14, color: const Color(0xFFB9C9DA))),
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
              Text('Sign out', style: sans(15.5, w: FontWeight.w500, color: const Color(0xFFB9C9DA))),
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

  Widget _scroll(List<Widget> children) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      );

  Widget _empty(String text) => Panel(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(children: [
            const Icon(Icons.hourglass_empty_rounded, size: 36, color: C.muted),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center, style: sans(15.5, color: C.muted)),
          ]),
        ),
      );

  // ======================= OVERVIEW =======================

  Widget _overviewPage() {
    final munis = admin.munis;
    final brgys = admin.allBrgys;
    if (munis.isEmpty) {
      return _scroll([_welcome(), const SizedBox(height: 20), _empty('Loading the municipalities…')]);
    }
    final verifiedB = brgys.where((b) => b.status == Status.verified).length;
    final verifiedM = munis.where((m) => m.status == Status.verified).length;
    return _scroll([
      _welcome(),
      const SizedBox(height: 20),
      _attention(),
      const SizedBox(height: 20),
      Grid(maxCols: 4, minWidth: 220, children: [
        StatTile(
          icon: Icons.location_city_outlined,
          tint: C.green,
          value: '$verifiedM / ${munis.length}',
          label: 'Municipalities verified',
          note: 'Every barangay checked and accepted by OPPDC',
          progress: munis.isEmpty ? 0 : verifiedM / munis.length,
          onView: () => _go(1),
        ),
        StatTile(
          icon: Icons.holiday_village_outlined,
          tint: C.blue,
          value: '$verifiedB / ${brgys.length}',
          label: 'Barangays verified',
          note: 'Paper set checked by their municipality',
          progress: brgys.isEmpty ? 0 : verifiedB / brgys.length,
          onView: () => _go(1),
        ),
        StatTile(
          icon: Icons.groups_outlined,
          tint: C.yellowDark,
          value: '${admin.tanods} / ${admin.slots}',
          label: 'Tanods listed',
          note: 'Out of the slots allowed by OPPDC',
          progress: admin.slots == 0 ? 0 : admin.tanods / admin.slots,
        ),
        StatTile(
          icon: Icons.payments_outlined,
          tint: C.green,
          value: peso(admin.totalAmount),
          label: 'Total incentive',
          note: '${peso(admin.amountPerTanod)} per tanod',
          onView: () => _go(3),
        ),
      ]),
      const SizedBox(height: 20),
      _provinceBar(),
      const SizedBox(height: 20),
      _muniTable(),
    ]);
  }

  Widget _welcome() {
    final h = DateTime.now().hour;
    final greet = h < 12 ? 'Good morning' : (h < 18 ? 'Good afternoon' : 'Good evening');
    final first = admin.adminName.split(' ').first;
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [C.navy, Color(0xFF173A63)]),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: C.yellow.withValues(alpha: .18),
            border: Border.all(color: C.yellow.withValues(alpha: .5)),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text('OPPDC · Province of Iloilo', style: sans(13.5, w: FontWeight.w600, color: const Color(0xFFFFE9A6))),
        ),
        const SizedBox(height: 14),
        Text('$greet, $first', style: serif(30, color: Colors.white)),
        const SizedBox(height: 8),
        Text('Tanod incentive ${admin.year}: every municipality and barangay in one place.',
            style: sans(16, color: const Color(0xFFD5E1EE), h: 1.5)),
      ]),
    );
  }

  Widget _attention() {
    final waiting = admin.munis.where((m) => m.status == Status.submitted).toList();
    final returned = admin.munis.where((m) => m.status == Status.returned).toList();
    final notStarted = admin.allBrgys.where((b) => !b.started).toList();
    final rows = <Widget>[
      for (final m in waiting)
        _task(
          Icons.inbox_outlined,
          C.yellowDark,
          '${m.name} submitted to OPPDC',
          '${m.brgys.length} barangays · ${m.tanods} tanods${m.submittedOn == null ? '' : ' · ${m.submittedOn}'}',
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(
              style: outlineStyle(fg: C.red, border: const Color(0xFFF0C7C3)),
              onPressed: () => _review(m, approve: false),
              child: const Text('Return'),
            ),
            FilledButton(
              style: primaryStyle(bg: C.green, fg: Colors.white),
              onPressed: () => _review(m, approve: true),
              child: const Text('Verify'),
            ),
          ]),
        ),
      for (final m in returned)
        _task(Icons.assignment_return_outlined, C.red, '${m.name} is fixing corrections',
            m.reviewNote.isEmpty ? 'Returned by OPPDC.' : '“${m.reviewNote}”', const SizedBox.shrink()),
      if (notStarted.isNotEmpty)
        _task(
          Icons.hourglass_empty_rounded,
          C.muted,
          '${notStarted.length} barangay${notStarted.length == 1 ? ' hasn’t' : 's haven’t'} started',
          notStarted.take(6).map((b) => '${b.name} (${b.muniName})').join(', ') + (notStarted.length > 6 ? '…' : ''),
          TextButton(onPressed: () => _go(1), child: const Text('See')),
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
        Text('NEEDS YOUR ATTENTION', style: sans(14, w: FontWeight.w800, color: const Color(0xFF8A6A00)).copyWith(letterSpacing: .8)),
        const SizedBox(height: 14),
        if (rows.isEmpty) Text('You’re all caught up.', style: serif(22)) else for (final r in rows) ...[r, const SizedBox(height: 10)],
      ]),
    );
  }

  Widget _task(IconData icon, Color tint, String title, String body, Widget action) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: C.line), borderRadius: BorderRadius.circular(14)),
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
          if (box.maxWidth < 600) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              info,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: action),
            ]);
          }
          return Row(children: [Expanded(child: info), const SizedBox(width: 14), action]);
        }),
      );

  /// Thin bar: every barangay in the province by stage
  Widget _provinceBar() {
    final brgys = admin.allBrgys;
    final groups = <(String, Color, int)>[
      for (final i in const [4, 3, 2, 1, 0]) (kStageNames[i], _stageColors[i], brgys.where((b) => brgyStage(b) == i).length),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: C.line), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.stacked_bar_chart_rounded, size: 18, color: C.navy),
          const SizedBox(width: 8),
          Text('All ${brgys.length} barangays in the province', style: sans(15, w: FontWeight.w700, color: C.navy)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 10,
            child: Row(children: [
              for (final g in groups)
                if (g.$3 > 0) Expanded(flex: g.$3, child: ColoredBox(color: g.$2)),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 14, runSpacing: 4, children: [
          for (final g in groups)
            if (g.$3 > 0)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 9, height: 9, decoration: BoxDecoration(color: g.$2, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 5),
                Text('${g.$1} · ${g.$3}', style: sans(13, color: C.muted)),
              ]),
        ]),
      ]),
    );
  }

  Widget _muniTable() => Panel(
        title: 'Municipalities',
        icon: Icons.location_city_outlined,
        trailing: TextButton(onPressed: () => _go(1), child: const Text('Open all')),
        child: Column(children: [
          for (final m in admin.munis)
            InkWell(
              onTap: () => setState(() {
                _open.add(m.id);
                navIndex = 1;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE9EFF5)))),
                child: LayoutBuilder(builder: (context, box) {
                  final wide = box.maxWidth >= 700;
                  final progress = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${m.verified}/${m.brgys.length} barangays verified · ${m.tanods}/${m.slots} tanods',
                        style: sans(14, color: C.muted)),
                    const SizedBox(height: 6),
                    _segBar(m),
                  ]);
                  return wide
                      ? Row(children: [
                          SizedBox(width: 180, child: Text(m.name, style: sans(16.5, w: FontWeight.w700, color: C.navy))),
                          SizedBox(width: 190, child: Align(alignment: Alignment.centerLeft, child: statusPill(muniLook(m)))),
                          Expanded(child: progress),
                          const Icon(Icons.chevron_right_rounded, color: C.muted),
                        ])
                      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(m.name, style: sans(16.5, w: FontWeight.w700, color: C.navy))),
                            statusPill(muniLook(m)),
                          ]),
                          const SizedBox(height: 8),
                          progress,
                        ]);
                }),
              ),
            ),
        ]),
      );

  /// One small segment per barangay, coloured by stage
  Widget _segBar(AdminMuni m) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: SizedBox(
          height: 8,
          child: Row(children: [
            for (final b in m.brgys)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 2),
                  color: brgyBar(b),
                ),
              ),
            if (m.brgys.isEmpty) const Expanded(child: ColoredBox(color: Color(0xFFE3EAF2))),
          ]),
        ),
      );

  // ======================= MUNICIPALITIES =======================

  Widget _municipalitiesPage() {
    final q = search.toLowerCase();
    final list = admin.munis
        .where((m) => q.isEmpty || m.name.toLowerCase().contains(q) || m.brgys.any((b) => b.name.toLowerCase().contains(q)))
        .toList();
    return _scroll([
      Text('Municipalities', style: serif(28)),
      const SizedBox(height: 6),
      Text('Every municipality and its barangays. Tap a municipality to see its barangays, change tanod limits, or open documents.',
          style: sans(16, color: C.muted, h: 1.5)),
      const SizedBox(height: 18),
      TextField(
        style: sans(16),
        onChanged: (v) => setState(() => search = v),
        decoration: fieldDecoration('Search municipality or barangay', Icons.search_rounded),
      ),
      const SizedBox(height: 16),
      if (list.isEmpty) _empty(admin.munis.isEmpty ? 'Loading the municipalities…' : 'Nothing matches “$search”.'),
      for (final m in list) ...[_muniCard(m, forceOpen: q.isNotEmpty), const SizedBox(height: 14)],
    ]);
  }

  Widget _muniCard(AdminMuni m, {bool forceOpen = false}) {
    final open = forceOpen || _open.contains(m.id);
    final q = search.toLowerCase();
    final brgys = q.isEmpty || m.name.toLowerCase().contains(q) ? m.brgys : m.brgys.where((b) => b.name.toLowerCase().contains(q)).toList();
    return Panel(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => open ? _open.remove(m.id) : _open.add(m.id)),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(children: [
              Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: C.navy),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.name, style: sans(18.5, w: FontWeight.w700, color: C.navy)),
                  const SizedBox(height: 2),
                  Text('${m.brgys.length} barangays · ${m.verified} verified · ${m.tanods}/${m.slots} tanods',
                      style: sans(14, color: C.muted)),
                ]),
              ),
              statusPill(muniLook(m)),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        _segBar(m),
        if (m.status == Status.submitted) ...[
          const SizedBox(height: 12),
          Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              style: outlineStyle(fg: C.red, border: const Color(0xFFF0C7C3)),
              onPressed: () => _review(m, approve: false),
              icon: const Icon(Icons.assignment_return_outlined, size: 18),
              label: const Text('Return'),
            ),
            FilledButton.icon(
              style: primaryStyle(bg: C.green, fg: Colors.white),
              onPressed: () => _review(m, approve: true),
              icon: const Icon(Icons.verified_outlined, size: 18),
              label: const Text('Verify municipality'),
            ),
          ]),
        ],
        if (open) ...[
          const SizedBox(height: 12),
          const Divider(height: 1, color: C.line),
          for (final b in brgys) _brgyRow(b),
          if (brgys.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('No barangays loaded for this municipality yet.', style: sans(15, color: C.muted)),
            ),
        ],
      ]),
    );
  }

  Widget _brgyRow(AdminBrgy b) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE9EFF5)))),
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 760;
          final limit = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${b.tanods} / ${b.limit} tanods', style: sans(15, w: FontWeight.w600, color: C.ink)),
            if (b.nextLimit != null) Text('Next year: ${b.nextLimit}', style: sans(13, color: C.blue)),
            if (b.awardEnd > 0) Text('Award nos. ${_n(b.awardStart)}–${_n(b.awardEnd)}', style: sans(13, color: C.muted)),
          ]);
          final buttons = Wrap(spacing: 6, runSpacing: 6, children: [
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: C.blue, backgroundColor: C.blue.withValues(alpha: .08)),
              onPressed: () => _editLimit(b),
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('Limit'),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: C.navy, backgroundColor: C.navy.withValues(alpha: .06)),
              onPressed: b.tanods == 0 ? null : () => _openDocs(b),
              icon: const Icon(Icons.description_outlined, size: 16),
              label: const Text('Documents'),
            ),
          ]);
          if (wide) {
            return Row(children: [
              Expanded(flex: 3, child: Text(b.name, style: sans(15.5, w: FontWeight.w600, color: C.navy))),
              Expanded(flex: 3, child: Align(alignment: Alignment.centerLeft, child: statusPill(brgyLook(b)))),
              Expanded(flex: 3, child: limit),
              buttons,
            ]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(b.name, style: sans(15.5, w: FontWeight.w600, color: C.navy))),
              statusPill(brgyLook(b)),
            ]),
            const SizedBox(height: 6),
            limit,
            const SizedBox(height: 6),
            Align(alignment: Alignment.centerRight, child: buttons),
          ]);
        }),
      );

  String _n(int v) => v.toString().padLeft(3, '0');

  // ======================= DOCUMENTS =======================

  Widget _documentsPage() {
    final passed = admin.allBrgys.where((b) => b.passed && b.tanods > 0).where((b) => switch (_docsFilter) {
          'verified' => const [2, 4].contains(brgyStage(b)), // Received by the municipality or by OPPDC
          'submitted' => const [1, 3].contains(brgyStage(b)), // Enroute to the municipality or to OPPDC
          _ => true,
        });
    final byTown = <String, List<AdminBrgy>>{};
    for (final b in passed) {
      byTown.putIfAbsent(b.muniName, () => []).add(b);
    }
    Widget chip(String key, String label) => ChoiceChip(
          label: Text(label, style: sans(15, w: FontWeight.w600, color: _docsFilter == key ? Colors.white : C.navy)),
          selected: _docsFilter == key,
          showCheckmark: false,
          selectedColor: C.navy,
          backgroundColor: Colors.white,
          side: BorderSide(color: _docsFilter == key ? C.navy : C.line, width: 1.5),
          onSelected: (_) => setState(() => _docsFilter = key),
        );
    return _scroll([
      Row(children: [
        Expanded(child: Text('Documents', style: serif(28))),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: C.navy, foregroundColor: Colors.white, minimumSize: const Size(0, 46)),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const ArchivePage(title: 'Province of Iloilo · all municipalities'))),
          icon: const Icon(Icons.inventory_2_outlined, size: 18),
          label: const Text('Open archive'),
        ),
      ]),
      const SizedBox(height: 6),
      Text('Each municipality has ONE Payroll and ONE Masterlist for all its barangays (ready once every barangay is verified). '
          'Each barangay folder holds its Barangay Certification and ID photocopy sheet.', style: sans(16, color: C.muted, h: 1.5)),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        chip('all', 'All passed'),
        chip('verified', 'Received'),
        chip('submitted', 'Enroute'),
      ]),
      const SizedBox(height: 16),
      if (byTown.isEmpty) _empty('No barangay has passed its documents yet.'),
      for (final e in byTown.entries) ...[
        Panel(
          title: e.key,
          icon: Icons.location_city_outlined,
          trailing: Text('${e.value.length} barangay${e.value.length == 1 ? '' : 's'}', style: sans(14.5, color: C.muted)),
          child: Column(children: [
            _muniDocsRow(e.key),
            for (final b in e.value)
              InkWell(
                onTap: () => _openDocs(b),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE9EFF5)))),
                  child: Row(children: [
                    const Icon(Icons.folder_outlined, color: C.navy),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Brgy. ${b.name}', style: sans(16, w: FontWeight.w700, color: C.navy)),
                        Text('${b.tanods} tanods · Certification & ID photocopy sheet', style: sans(14, color: C.muted)),
                      ]),
                    ),
                    statusPill(brgyLook(b)),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right_rounded, color: C.muted),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 14),
      ],
    ]);
  }

  // Municipal level: one Payroll + one Masterlist (locked until every barangay is verified)
  Widget _muniDocsRow(String muniName) {
    final m = admin.munis.where((x) => x.name == muniName).firstOrNull;
    if (m == null) return const SizedBox.shrink();
    final ready = admin.muniDocsReady(m);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: ready ? C.blueSoft : C.mist, borderRadius: BorderRadius.circular(12)),
      child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Icon(ready ? Icons.inventory_2_outlined : Icons.lock_outline_rounded, size: 20, color: ready ? C.blue : C.muted),
        Text(
            ready
                ? 'Municipal documents · ${m.name}'
                : 'Payroll & Masterlist unlock when all ${m.brgys.length} barangays are verified (${m.verified} so far)',
            style: sans(15, w: FontWeight.w600, color: ready ? C.navy : C.muted)),
        for (final k in const [DocKind.payroll, DocKind.masterlist])
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: C.navy, foregroundColor: Colors.white),
            onPressed: ready ? () => showMuniDoc(context, m, k) : null,
            icon: Icon(k.icon, size: 18),
            label: Text(k.title),
          ),
      ]),
    );
  }

  // ======================= ANALYTICS =======================

  Widget _analyticsPage() {
    final years = admin.allYears;
    final sel = years.firstWhere((y) => y.year == (_year ?? admin.year), orElse: () => years.last);
    final idx = years.indexOf(sel);
    final prev = idx > 0 ? years[idx - 1] : null;
    final hasSample = years.any((y) => y.sample);

    String delta(num now, num? before) {
      if (before == null || before == 0) return '';
      final d = (now - before) / before * 100;
      return '${d >= 0 ? '▲' : '▼'} ${d.abs().toStringAsFixed(0)}% vs ${prev!.year}';
    }

    return _scroll([
      Text('Analytics', style: serif(28)),
      const SizedBox(height: 6),
      Text('How the tanod incentive went each year, across the province.', style: sans(16, color: C.muted, h: 1.5)),
      if (hasSample) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.info_outline, size: 18, color: Color(0xFF7A5B00)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${years.where((y) => y.sample).map((y) => y.year).join(', ')} are SAMPLE numbers for the presentation. '
                '${admin.year} is ${admin.live ? 'live from Firebase' : 'demo data'}.',
                style: sans(14.5, color: const Color(0xFF5C4400), h: 1.4),
              ),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final y in years)
          ChoiceChip(
            label: Text('${y.year}${y.sample ? ' (sample)' : ''}',
                style: sans(15, w: FontWeight.w600, color: y == sel ? Colors.white : C.navy)),
            selected: y == sel,
            showCheckmark: false,
            selectedColor: C.navy,
            backgroundColor: Colors.white,
            side: BorderSide(color: y == sel ? C.navy : C.line, width: 1.5),
            onSelected: (_) => setState(() => _year = y.year),
          ),
      ]),
      const SizedBox(height: 16),
      Grid(maxCols: 4, minWidth: 220, children: [
        StatTile(
          icon: Icons.groups_outlined,
          tint: C.blue,
          value: '${sel.tanods}',
          label: 'Tanods given the incentive',
          note: delta(sel.tanods, prev?.tanods).isEmpty ? 'of ${sel.slots} slots' : delta(sel.tanods, prev?.tanods),
        ),
        StatTile(
          icon: Icons.payments_outlined,
          tint: C.green,
          value: peso(sel.total),
          label: 'Total incentive',
          note: delta(sel.total, prev?.total).isEmpty ? '${peso(sel.amountPerTanod)} per tanod' : delta(sel.total, prev?.total),
        ),
        StatTile(
          icon: Icons.pie_chart_outline_rounded,
          tint: C.yellowDark,
          value: '${(sel.fill * 100).round()}%',
          label: 'Slots filled',
          note: '${sel.tanods} of ${sel.slots} allowed',
          progress: sel.fill,
        ),
        StatTile(
          icon: Icons.task_alt_rounded,
          tint: C.navy,
          value: '${(sel.completion * 100).round()}%',
          label: 'Barangays completed',
          note: '${sel.verifiedBarangays} of ${sel.barangays} verified',
          progress: sel.completion,
        ),
      ]),
      const SizedBox(height: 20),
      LayoutBuilder(builder: (context, box) {
        final charts = [
          _chart('Tanods per year', Icons.groups_outlined, C.blue, [for (final y in years) (y.year, y.tanods.toDouble(), y.sample)], (v) => '${v.round()}'),
          _chart('Total incentive per year', Icons.payments_outlined, C.green, [for (final y in years) (y.year, y.total.toDouble(), y.sample)],
              (v) => v >= 1000 ? '₱${(v / 1000).toStringAsFixed(v >= 100000 ? 0 : 1)}k' : peso(v)),
          _chart('Barangays completed', Icons.task_alt_rounded, C.yellowDark,
              [for (final y in years) (y.year, y.completion * 100, y.sample)], (v) => '${v.round()}%', max: 100),
        ];
        if (box.maxWidth >= 1000) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < charts.length; i++) ...[if (i > 0) const SizedBox(width: 16), Expanded(child: charts[i])],
          ]);
        }
        return Column(children: [for (final c in charts) ...[c, const SizedBox(height: 16)]]);
      }),
      const SizedBox(height: 20),
      _muniBreakdown(sel),
    ]);
  }

  /// Simple bar chart: one bar per year (sample years lighter, with a dot)
  Widget _chart(String title, IconData icon, Color color, List<(int, double, bool)> data, String Function(double) label,
      {double? max}) {
    final top = max ?? data.fold<double>(0, (a, d) => d.$2 > a ? d.$2 : a);
    return Panel(
      title: title,
      icon: icon,
      padding: const EdgeInsets.all(18),
      child: SizedBox(
        height: 210,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final d in data)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text(label(d.$2), style: sans(13, w: FontWeight.w700, color: C.navy)),
                  const SizedBox(height: 4),
                  Flexible(
                    child: FractionallySizedBox(
                      heightFactor: top == 0 ? 0.02 : (d.$2 / top).clamp(0.02, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: d.$3 ? color.withValues(alpha: .35) : color,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                          border: d.$3 ? Border.all(color: color, width: 1.2) : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('${d.$1}', style: sans(13.5, w: FontWeight.w600, color: C.ink)),
                  Text(d.$3 ? 'sample' : (d.$1 == admin.year ? 'now' : ''), style: sans(11.5, color: C.muted)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  /// Per municipality: tanods and (this year) how full the slots are
  Widget _muniBreakdown(YearStat sel) {
    final isNow = sel.year == admin.year;
    final rows = isNow
        ? [for (final m in admin.munis) (m.name, m.tanods, m.slots)]
        : [for (final e in sel.muniTanods.entries) (e.key, e.value, 0)];
    final top = rows.fold<int>(0, (a, r) => (isNow ? r.$3 : r.$2) > a ? (isNow ? r.$3 : r.$2) : a);
    return Panel(
      title: 'By municipality · ${sel.year}${sel.sample ? ' (sample)' : ''}',
      icon: Icons.location_city_outlined,
      child: Column(children: [
        if (rows.isEmpty) Text('No data for this year.', style: sans(15, color: C.muted)),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(children: [
              SizedBox(width: 130, child: Text(r.$1, overflow: TextOverflow.ellipsis, style: sans(15, w: FontWeight.w600, color: C.navy))),
              Expanded(
                child: LayoutBuilder(builder: (context, box) {
                  final full = top == 0 ? 0.0 : box.maxWidth * ((isNow ? r.$3 : r.$2) / top);
                  final filled = top == 0 ? 0.0 : box.maxWidth * (r.$2 / top);
                  return Stack(children: [
                    Container(height: 14, width: full, decoration: BoxDecoration(color: const Color(0xFFE3EAF2), borderRadius: BorderRadius.circular(99))),
                    Container(height: 14, width: filled, decoration: BoxDecoration(color: C.blue, borderRadius: BorderRadius.circular(99))),
                  ]);
                }),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 110,
                child: Text(isNow ? '${r.$2} / ${r.$3} tanods' : '${r.$2} tanods',
                    textAlign: TextAlign.right, style: sans(14, color: C.muted)),
              ),
            ]),
          ),
        if (isNow && rows.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Grey = slots allowed, blue = tanods listed.', style: sans(13, color: C.muted)),
        ],
      ]),
    );
  }

  // ======================= ACCOUNT =======================

  Widget _accountPage() => _scroll([
        Text('Account', style: serif(28)),
        const SizedBox(height: 20),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              CircleAvatar(radius: 30, backgroundColor: C.yellow, child: Text(_initials(admin.adminName), style: serif(22))),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(admin.adminName, style: serif(24)),
                  const SizedBox(height: 4),
                  pill('OPPDC · Provincial admin', C.blueSoft, C.blue, icon: Icons.admin_panel_settings_outlined),
                ]),
              ),
            ]),
            const SizedBox(height: 18),
            const Divider(color: Color(0xFFE3EAF2)),
            _kv('Province', 'Iloilo'),
            _kv('Municipalities', '${admin.munis.length}'),
            _kv('Barangays', '${admin.allBrgys.length}'),
            _kv('Incentive year', '${admin.year} · ${peso(admin.amountPerTanod)} per tanod'),
            _kv('Data', admin.live ? 'Live from Firebase' : 'Demo data (no internet needed)'),
          ]),
        ),
      ]);

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 150, child: Text(k, style: sans(15, color: C.muted))),
          Expanded(child: Text(v, style: sans(15.5, w: FontWeight.w600))),
        ]),
      );
}