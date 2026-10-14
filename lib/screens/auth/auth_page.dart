import 'package:flutter/material.dart';

import 'package:tanod_incentives/theme.dart';
import 'login_form.dart';
import 'register_form.dart';
import 'success_view.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool showRegister = false;
  bool submitted = false; // registration success view

  // register summary
  String sName = '', sPos = '', sArea = '', sMuni = '';

  void goTo(bool reg) => setState(() {
        showRegister = reg;
        if (reg) submitted = false;
      });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final mobile = w <= 560;
    final heroH = mobile ? 340.0 : 400.0;
    const overlap = 92.0;

    return Scaffold(
      body: SingleChildScrollView(
        child: Stack(
          children: [
            Positioned(
                top: 0, left: 0, right: 0, height: heroH, child: _Hero(mobile: mobile)),
            Column(
              children: [
                SizedBox(height: heroH - overlap),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(children: [
                        _card(mobile),
                        const SizedBox(height: 22),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.verified_user_outlined, size: 18, color: C.green),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Each account sees only its own area, so personal data stays protected.',
                              textAlign: TextAlign.center,
                              style: sans(13.5, color: C.muted),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 36),
                      ]),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 36),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: 'Gawad', style: sans(13, w: FontWeight.w700, color: C.navy)),
                    TextSpan(text: ' · Iloilo', style: sans(13, color: C.muted)),
                  ])),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(bool mobile) {
    final radius = BorderRadius.circular(mobile ? 20 : 24);
    // Flutter can't round a border whose sides have different colors,
    // so the yellow top strip is drawn as a bar inside a clipped card.
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: radius,
        boxShadow: [
          BoxShadow(color: C.navy.withValues(alpha: .05), blurRadius: 4, offset: const Offset(0, 2)),
          BoxShadow(color: C.navy.withValues(alpha: .30), blurRadius: 60, spreadRadius: -24, offset: const Offset(0, 28)),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: const Color(0xFFE1E9F2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(height: 5, color: C.yellow),
            Padding(
              padding: EdgeInsets.fromLTRB(mobile ? 18 : 40, mobile ? 20 : 28, mobile ? 18 : 40, mobile ? 26 : 34),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _Tabs(showRegister: showRegister, onChanged: goTo),
                const SizedBox(height: 28),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: showRegister
                      ? (submitted
                          ? SuccessView(
                              key: const ValueKey('done'),
                              name: sName,
                              pos: sPos,
                              area: sArea,
                              muni: sMuni,
                              onSignIn: () => goTo(false),
                              onAgain: () => setState(() => submitted = false),
                            )
                          : RegisterForm(
                              key: const ValueKey('reg'),
                              onSignIn: () => goTo(false),
                              onSubmitted: (n, p, a, m) => setState(() {
                                sName = n;
                                sPos = p;
                                sArea = a;
                                sMuni = m;
                                submitted = true;
                              }),
                            ))
                      : LoginForm(key: const ValueKey('login'), onRequestAccess: () => goTo(true)),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------- Hero ----------------
class _Hero extends StatelessWidget {
  final bool mobile;
  const _Hero({required this.mobile});
  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(fit: StackFit.expand, children: [
        Container(color: C.navy),
        Image.asset('assets/iloilo.jpg',
            fit: BoxFit.cover,
            alignment: const Alignment(0, .24),
            errorBuilder: (context, error, stackTrace) => const SizedBox.shrink()),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, .38, .82, 1],
              colors: [Color(0xC7091C32), Color(0x850E2A47), Color(0xE00E2A47), C.navy],
            ),
          ),
        ),
        // tri-color bottom stripe
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
        SafeArea(
          bottom: false,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: SizedBox(
                    height: 76,
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Row(children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: C.yellow,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 6), spreadRadius: -6)
                            ],
                          ),
                          child: Text('G', style: serif(22)),
                        ),
                        const SizedBox(width: 12),
                        Text('Gawad', style: sans(19, w: FontWeight.w700, color: Colors.white)),
                      ]),
                      _HelpPill(mobile: mobile),
                    ]),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 18, 24, mobile ? 112 : 128),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: C.yellow.withValues(alpha: .18),
                        border: Border.all(color: C.yellow.withValues(alpha: .55)),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: C.yellow, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Text('Barangay tanod records',
                            style: sans(13, w: FontWeight.w600, color: const Color(0xFFFFE9A6))),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    Text('Welcome to Gawad',
                        textAlign: TextAlign.center,
                        style: serif(mobile ? 30 : 48, color: Colors.white).copyWith(
                            shadows: const [Shadow(color: Colors.black38, blurRadius: 18, offset: Offset(0, 2))])),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Text('Sign in to your account, or request access for your barangay.',
                          textAlign: TextAlign.center,
                          style: sans(16, color: const Color(0xFFD3E0EE), h: 1.5)),
                    ),
                  ]),
                ),
              ),
            ),
          ]),
        ),
        if (!mobile)
          Positioned(
            right: 20,
            bottom: 16,
            child: Row(children: [
              const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFFC9D8E8)),
              const SizedBox(width: 6),
              Text('Iloilo Provincial Capitol', style: sans(12, color: const Color(0xFFC9D8E8))),
            ]),
          ),
      ]),
    );
  }
}

class _HelpPill extends StatelessWidget {
  final bool mobile;
  const _HelpPill({required this.mobile});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: () {},
      child: Container(
        padding: EdgeInsets.symmetric(vertical: mobile ? 9 : 8, horizontal: mobile ? 9 : 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .12),
          border: Border.all(color: Colors.white.withValues(alpha: .2)),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.help_outline, size: 18, color: Color(0xFFE3ECF6)),
          if (!mobile) ...[
            const SizedBox(width: 8),
            Text('Need help?', style: sans(14, w: FontWeight.w500, color: const Color(0xFFE3ECF6))),
          ],
        ]),
      ),
    );
  }
}

// ---------------- Tabs ----------------
class _Tabs extends StatelessWidget {
  final bool showRegister;
  final void Function(bool reg) onChanged;
  const _Tabs({required this.showRegister, required this.onChanged});

  Widget _tab(String label, IconData icon, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? C.navy : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: C.navy.withValues(alpha: .5),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                        spreadRadius: -4)
                  ]
                : null,
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 18, color: selected ? C.yellow : C.muted),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: sans(15, w: FontWeight.w600, color: selected ? Colors.white : C.muted)),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: C.mist,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.line),
      ),
      child: Row(children: [
        _tab('Sign in', Icons.login, !showRegister, () => onChanged(false)),
        const SizedBox(width: 6),
        _tab('Request access', Icons.badge_outlined, showRegister, () => onChanged(true)),
      ]),
    );
  }
}
