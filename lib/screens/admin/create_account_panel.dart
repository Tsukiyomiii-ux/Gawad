import 'package:flutter/material.dart';

import 'package:tanod_incentives/theme.dart';
import 'package:tanod_incentives/data/admin_data.dart';
import 'package:tanod_incentives/data/cloud.dart';
import 'package:tanod_incentives/widgets/ui.dart';

/// OPPDC: create a barangay login (uses the team's AuthService.createAccount,
/// which does not sign the admin out). Put `const CreateAccountPanel()` anywhere
/// on the admin Account page.
class CreateAccountPanel extends StatefulWidget {
  const CreateAccountPanel({super.key});

  @override
  State<CreateAccountPanel> createState() => _CreateAccountPanelState();
}

class _CreateAccountPanelState extends State<CreateAccountPanel> {
  String? _brgyId;
  final _login = TextEditingController();
  final _pass = TextEditingController(text: 'gawad2026');
  bool _busy = false;

  @override
  void dispose() {
    _login.dispose();
    _pass.dispose();
    super.dispose();
  }

  String _loginFor(AdminBrgy b) => 'brgy-${b.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '')}';

  Future<void> _create(List<AdminBrgy> brgys) async {
    final b = brgys.where((x) => x.id == _brgyId).firstOrNull;
    final login = _login.text.trim().toLowerCase();
    final pass = _pass.text.trim();
    if (b == null || login.isEmpty || pass.length < 6) {
      toast(context, 'Pick a barangay, a login ID, and a password of at least 6 characters.', type: NotifyType.warning);
      return;
    }
    setState(() => _busy = true);
    try {
      await cloud.auth.createAccount(
        loginId: login,
        password: pass,
        role: 'barangay',
        displayName: 'Barangay ${b.name}',
        municipalityId: b.muniId,
        barangayId: b.id,
      );
      if (!mounted) return;
      toast(context, 'Login ID: $login  ·  Password: $pass', title: 'Account created for Brgy. ${b.name}');
      setState(() {
        _brgyId = null;
        _login.clear();
      });
    } catch (e) {
      if (mounted) toast(context, Cloud.friendly(e), type: NotifyType.error, title: 'Account not created');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!admin.live) {
      return Panel(
        title: 'Create a barangay account',
        icon: Icons.person_add_alt_1_outlined,
        child: Text('Sign in with the real OPPDC (admin) account to create accounts.', style: sans(15, color: C.muted)),
      );
    }
    final brgys = [...admin.allBrgys]..sort((a, b) => '${a.muniName} ${a.name}'.compareTo('${b.muniName} ${b.name}'));
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(12));
    return Panel(
      title: 'Create a barangay account',
      icon: Icons.person_add_alt_1_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<String>(
          value: brgys.any((b) => b.id == _brgyId) ? _brgyId : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: 'Barangay', border: border),
          items: [
            for (final b in brgys)
              DropdownMenuItem(value: b.id, child: Text('${b.muniName} · Brgy. ${b.name}', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (id) => setState(() {
            _brgyId = id;
            final b = brgys.where((x) => x.id == id).firstOrNull;
            if (b != null) _login.text = _loginFor(b);
          }),
        ),
        const SizedBox(height: 12),
        TextField(controller: _login, decoration: InputDecoration(labelText: 'Login ID', border: border)),
        const SizedBox(height: 12),
        TextField(controller: _pass, decoration: InputDecoration(labelText: 'Password (at least 6)', border: border)),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: C.navy, foregroundColor: Colors.white, minimumSize: const Size(0, 48)),
            onPressed: _busy ? null : () => _create(brgys),
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: Text(_busy ? 'Creating…' : 'Create account'),
          ),
        ),
      ]),
    );
  }
}