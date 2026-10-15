import 'package:flutter/material.dart';

import 'package:tanod_incentives/theme.dart';
import 'login_form.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final mobile = w <= 560;
    final heroH = mobile ? 370.0 : 400.0; // FIX: was 340 on phones
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
                // Sign in only (Request access removed: OPPDC creates every account)
                LoginForm(key: const ValueKey('login'), onRequestAccess: () {}),
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
                          // Logo from assets/logo.png (falls back to "G" if it can't load)
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              'assets/logo.png',
                              width: 40,
                              height: 40,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Text('G', style: serif(22)),
                            ),
                          ),
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
                // FIX: on short phones (or with large text) the welcome text was 44 px
                // too tall for the header. It now shrinks to fit instead of overflowing.
                child: LayoutBuilder(
                  builder: (context, box) => Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: box.maxWidth,
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
                      child: Text('Sign in with the account given by OPPDC.',
                          textAlign: TextAlign.center,
                          style: sans(16, color: const Color(0xFFD3E0EE), h: 1.5)),
                    ),
                        ]),
                      ),
                    ),
                  ),
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