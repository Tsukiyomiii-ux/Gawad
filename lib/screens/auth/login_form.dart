import 'package:flutter/material.dart';

import 'package:tanod_incentives/theme.dart';
import 'package:tanod_incentives/widgets/app_field.dart';
import 'package:tanod_incentives/widgets/yellow_button.dart';
import 'package:tanod_incentives/screens/dashboard/dashboard_page.dart';
import 'package:tanod_incentives/screens/municipal/municipal_page.dart';
import 'package:tanod_incentives/data/demo_data.dart';

// ---------------- Login ----------------
class LoginForm extends StatefulWidget {
  final VoidCallback onRequestAccess;
  const LoginForm({super.key, required this.onRequestAccess});
  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _key = GlobalKey<FormState>();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool keep = false;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_key.currentState!.validate()) return;
    // Demo: any password works. A username with "reviewer" or "mlgoo" opens the
    // municipality side; anything else opens the barangay side.
    // TODO: connect to your sign-in endpoint and use the account's real role.
    final u = _user.text.toLowerCase();
    final municipal = u.contains('reviewer') || u.contains('mlgoo');
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => municipal ? const MunicipalPage() : const DashboardPage(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _key,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Sign in', style: serif(29)),
        const SizedBox(height: 8),
        Text('Use the username or mobile number linked to your account.',
            style: sans(15, color: C.muted, h: 1.5)),
        const SizedBox(height: 22),
        AppField(
          label: 'Username or mobile number',
          icon: Icons.person_outline,
          controller: _user,
          hint: 'mina.reviewer or 09171234567',
          autofill: const [AutofillHints.username],
          validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your username or mobile number.' : null,
        ),
        const SizedBox(height: 18),
        AppField(
          label: 'Password or PIN',
          icon: Icons.lock_outline,
          controller: _pass,
          hint: 'Enter your password',
          password: true,
          autofill: const [AutofillHints.password],
          validator: (v) => (v ?? '').isEmpty ? 'Enter your password or PIN.' : null,
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 4,
          children: [
            InkWell(
              onTap: () => setState(() => keep = !keep),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: keep,
                    activeColor: C.green,
                    onChanged: (v) => setState(() => keep = v ?? false),
                  ),
                ),
                const SizedBox(width: 8),
                Text('Keep me signed in', style: sans(14)),
              ]),
            ),
            TextButton(
              onPressed: () {},
              child: Text('Forgot password?', style: sans(14, w: FontWeight.w600, color: C.blue)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        YellowButton(label: 'Sign in', icon: Icons.login, onPressed: _submit),
        if (kDemoMode) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: C.mist, borderRadius: BorderRadius.circular(10)),
            child: Text(
              'Demo: any password works. Type mina.reviewer to open the municipality side, or any other username for the barangay side.',
              style: sans(13.5, color: C.muted, h: 1.45),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Center(
          child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('Barangay representative without an account? ', style: sans(14, color: C.muted)),
            GestureDetector(
              onTap: widget.onRequestAccess,
              child: Text('Request access', style: sans(14, w: FontWeight.w600, color: C.blue)),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          decoration: BoxDecoration(color: C.greenSoft, borderRadius: BorderRadius.circular(12)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.location_city_outlined, size: 18, color: C.green),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(TextSpan(style: sans(13.5, color: const Color(0xFF14583D), h: 1.5), children: [
                TextSpan(
                    text: 'Municipal staff: ',
                    style: sans(13.5, w: FontWeight.w700, color: const Color(0xFF14583D))),
                const TextSpan(
                    text: 'OPPDC gives you your username and temporary password. You don’t need to register.'),
              ])),
            ),
          ]),
        ),
      ]),
    );
  }
}
