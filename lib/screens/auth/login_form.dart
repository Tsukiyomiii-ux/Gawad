import 'package:flutter/material.dart';

import 'package:tanod_incentives/theme.dart';
import 'package:tanod_incentives/widgets/app_field.dart';
import 'package:tanod_incentives/widgets/yellow_button.dart';
import 'package:tanod_incentives/screens/dashboard/dashboard_page.dart';
import 'package:tanod_incentives/screens/municipal/municipal_page.dart';
import 'package:tanod_incentives/screens/admin/admin_page.dart';
import 'package:tanod_incentives/data/admin_data.dart'; // OPPDC (province) data
import 'package:tanod_incentives/data/demo_data.dart';
import 'package:tanod_incentives/data/cloud.dart'; // FIREBASE sign-in
import 'package:tanod_incentives/widgets/notify.dart';

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
  bool busy = false; // signing in

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (busy || !_key.currentState!.validate()) return;
    final u = _user.text.trim().toLowerCase();

    // DEMO accounts (no Firebase needed): "demo" opens the barangay side,
    // a username with "reviewer" or "mlgoo" opens the municipality side.
    // "oppdc" opens the OPPDC (province) dashboard with demo data.
    if (u == 'oppdc') {
      admin.openDemo();
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AdminPage()));
      return;
    }
    final municipalDemo = u.contains('reviewer') || u.contains('mlgoo');
    if (!firebaseReady || u == 'demo' || municipalDemo) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => municipalDemo ? const MunicipalPage() : const DashboardPage(),
      ));
      return;
    }

    // REAL accounts from Firebase (e.g. brgy-ungka1 / mun-pavia)
    setState(() => busy = true);
    notify(context, tr('Signing in…', 'Nagsa-sign in…', 'Nagasign in…'), type: NotifyType.info, title: 'Gawad');
    try {
      final role = await cloud.signIn(u, _pass.text);
      if (!mounted) return;
      if (role == 'admin') {
        await admin.openLive(); // live data for every municipality and barangay
        if (!mounted) return;
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AdminPage()));
        return;
      }
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => role == 'barangay' ? const DashboardPage() : const MunicipalPage(),
      ));
    } catch (e) {
      if (mounted) {
        notify(context, '$e', type: NotifyType.error, title: tr('Sign-in failed', 'Hindi naka-sign in', 'Wala naka-sign in'));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
          hint: 'brgy-ungka1',
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
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.verified_user_outlined, size: 18, color: C.green),
              const SizedBox(width: 8),
              Text('You stay signed in until you sign out', style: sans(14, color: C.muted)),
            ]),
            TextButton(
              onPressed: () {},
              child: Text('Forgot password?', style: sans(14, w: FontWeight.w600, color: C.blue)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        YellowButton(label: busy ? 'Signing in…' : 'Sign in', icon: busy ? Icons.hourglass_top_rounded : Icons.login, onPressed: _submit),
        if (kDemoMode) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: C.mist, borderRadius: BorderRadius.circular(10)),
            child: Text(
              'Real accounts: use the login ID from OPPDC (e.g. brgy-ungka1). '
              'Demo (no internet needed): type demo for the barangay side or mina.reviewer for the municipality side, with any password.',
              style: sans(13.5, color: C.muted, h: 1.45),
            ),
          ),
        ],
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