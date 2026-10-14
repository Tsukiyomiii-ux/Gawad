import 'package:flutter/material.dart';

import 'package:tanod_incentives/theme.dart';
import 'package:tanod_incentives/data/areas.dart';
import 'package:tanod_incentives/widgets/app_field.dart';
import 'package:tanod_incentives/widgets/yellow_button.dart';

// ---------------- Register ----------------
class RegisterForm extends StatefulWidget {
  final VoidCallback onSignIn;
  final void Function(String name, String pos, String brgy, String muni) onSubmitted;
  const RegisterForm({super.key, required this.onSignIn, required this.onSubmitted});
  @override
  State<RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<RegisterForm> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _pos = TextEditingController();
  final _mob = TextEditingController();
  final _note = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  String? muni, brgy;
  int strength = 0;

  @override
  void dispose() {
    for (final c in [_name, _pos, _mob, _note, _pw, _pw2]) {
      c.dispose();
    }
    super.dispose();
  }

  int _score(String v) {
    if (v.isEmpty) return 0;
    var s = 0;
    if (v.length >= 6) s++;
    if (v.length >= 9) s++;
    if (RegExp(r'[A-Z]').hasMatch(v) && RegExp(r'[a-z]').hasMatch(v)) s++;
    if (RegExp(r'\d').hasMatch(v) && RegExp(r'[A-Za-z]|[^A-Za-z0-9]').hasMatch(v) && v.length >= 8) s++;
    return s;
  }

  void _submit() {
    if (!_key.currentState!.validate()) return;
    widget.onSubmitted(_name.text.trim(), _pos.text.trim(), brgy!, muni!);
  }

  Widget _dropdown({
    Key? key,
    required String label,
    required IconData icon,
    required String hint,
    required String? value,
    required List<String> items,
    required void Function(String?)? onChanged,
    required String error,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FieldLabel(label),
      DropdownButtonFormField<String>(
        key: key,
        initialValue: value,
        isExpanded: true,
        icon: const Icon(Icons.keyboard_arrow_down, color: C.muted),
        style: sans(15),
        dropdownColor: Colors.white,
        borderRadius: BorderRadius.circular(12),
        hint: Text(hint, style: sans(15, color: const Color(0xFF97A5B5))),
        decoration: fieldDecoration('', icon).copyWith(
          fillColor: onChanged == null ? C.mist : Colors.white,
        ),
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: onChanged,
        validator: (v) => v == null ? error : null,
      ),
    ]);
  }

  // Two columns on wide cards, single column on narrow ones.
  Widget _pair(bool two, Widget a, Widget b) {
    if (!two) return Column(children: [a, const SizedBox(height: 18), b]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: a),
      const SizedBox(width: 18),
      Expanded(child: b),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    const meterColors = <int, Color>{
      1: C.red,
      2: C.yellowDark,
      3: Color(0xFF7CC24B),
      4: C.green,
    };
    final meterTxt = _pw.text.isEmpty
        ? 'Use 6 or more characters.'
        : ['Too short', 'Weak', 'Okay', 'Good', 'Strong'][strength];

    return LayoutBuilder(builder: (context, box) {
      final two = box.maxWidth >= 460;
      return Form(
        key: _key,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Request barangay access', style: serif(MediaQuery.of(context).size.width <= 560 ? 25 : 29)),
          const SizedBox(height: 8),
          Text('Choose your area from OPPDC’s list. Your municipality reviews every request.',
              style: sans(15, color: C.muted, h: 1.5)),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: C.blueSoft,
              border: Border(left: BorderSide(color: C.blue, width: 4)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                  padding: EdgeInsets.only(top: 2), child: Icon(Icons.info_outline, size: 18, color: C.blue)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'You can sign in right away. Submitting documents unlocks once your municipality approves you.',
                  style: sans(14, color: const Color(0xFF1B3F68), h: 1.5),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 22),

          const SectionTitle(Icons.place_outlined, 'Your area'),
          const SizedBox(height: 16),
          _pair(
            two,
            _dropdown(
              label: 'Municipality',
              icon: Icons.location_city_outlined,
              hint: 'Choose municipality',
              value: muni,
              items: (kAreas.keys.toList()..sort()),
              error: 'Choose your municipality.',
              onChanged: (v) => setState(() {
                muni = v;
                brgy = null;
              }),
            ),
            _dropdown(
              // New key per municipality so the barangay field resets when the municipality changes.
              key: ValueKey('brgy-$muni'),
              label: 'Barangay',
              icon: Icons.place_outlined,
              hint: muni == null ? 'Choose municipality first' : 'Choose barangay',
              value: brgy,
              items: muni == null ? const [] : kAreas[muni]!,
              error: 'Choose your barangay.',
              onChanged: muni == null ? null : (v) => setState(() => brgy = v),
            ),
          ),

          const SizedBox(height: 26),
          const SectionTitle(Icons.person_outline, 'About you'),
          const SizedBox(height: 16),
          _pair(
            two,
            AppField(
              label: 'Full name',
              icon: Icons.person_outline,
              controller: _name,
              hint: 'Melanie Dela Cruz',
              autofill: const [AutofillHints.name],
              validator: (v) => (v ?? '').trim().length > 1 ? null : 'Enter your full name.',
            ),
            AppField(
              label: 'Position',
              icon: Icons.badge_outlined,
              controller: _pos,
              hint: 'Treasurer',
              validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your barangay position.' : null,
            ),
          ),
          const SizedBox(height: 18),
          _pair(
            two,
            AppField(
              label: 'Mobile number',
              icon: Icons.smartphone,
              controller: _mob,
              hint: '09XXXXXXXXX',
              keyboard: TextInputType.number,
              maxLength: 11,
              autofill: const [AutofillHints.telephoneNumber],
              onChanged: (v) {
                final digits = v.replaceAll(RegExp(r'\D'), '');
                if (digits != v) {
                  _mob.value = TextEditingValue(
                      text: digits, selection: TextSelection.collapsed(offset: digits.length));
                }
              },
              validator: (v) => RegExp(r'^09\d{9}$').hasMatch(v ?? '') ? null : 'Use 11 digits starting with 09.',
            ),
            AppField(
              label: 'Designation or proof',
              icon: Icons.description_outlined,
              controller: _note,
              hint: 'e.g. Appointed January 2026',
              required: false,
              optional: true,
            ),
          ),

          const SizedBox(height: 26),
          const SectionTitle(Icons.lock_outline, 'Secure your account'),
          const SizedBox(height: 16),
          _pair(
            two,
            AppField(
              label: 'Password or PIN',
              icon: Icons.lock_outline,
              controller: _pw,
              hint: 'At least 6 characters',
              password: true,
              autofill: const [AutofillHints.newPassword],
              onChanged: (v) => setState(() => strength = _score(v)),
              validator: (v) => (v ?? '').length >= 6 ? null : 'Use at least 6 characters.',
              below: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 8),
                Row(
                    children: List.generate(4, (i) {
                  final on = i < strength;
                  final col = on ? meterColors[strength]! : const Color(0xFFE3EAF2);
                  return Expanded(
                    child: Container(
                      height: 5,
                      margin: EdgeInsets.only(right: i < 3 ? 5 : 0),
                      decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(9)),
                    ),
                  );
                })),
                const SizedBox(height: 4),
                Text(meterTxt, style: sans(12.5, color: C.muted)),
              ]),
            ),
            AppField(
              label: 'Confirm password',
              icon: Icons.lock_outline,
              controller: _pw2,
              hint: 'Re-enter password',
              password: true,
              autofill: const [AutofillHints.newPassword],
              validator: (v) => (v ?? '').isNotEmpty && v == _pw.text ? null : 'Passwords don’t match.',
            ),
          ),

          const SizedBox(height: 28),
          YellowButton(label: 'Send request', icon: Icons.send_outlined, onPressed: _submit),
          const SizedBox(height: 20),
          Center(
            child: Wrap(alignment: WrapAlignment.center, children: [
              Text('Already approved? ', style: sans(14, color: C.muted)),
              GestureDetector(
                onTap: widget.onSignIn,
                child: Text('Sign in', style: sans(14, w: FontWeight.w600, color: C.blue)),
              ),
            ]),
          ),
        ]),
      );
    });
  }
}
