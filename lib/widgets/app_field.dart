import 'package:flutter/material.dart';

import 'package:tanod_incentives/theme.dart';

// ---------------- Reusable bits ----------------
class AppField extends StatefulWidget {
  final String label;
  final IconData icon;
  final TextEditingController controller;
  final String hint;
  final bool required;
  final bool optional;
  final bool password;
  final TextInputType? keyboard;
  final int? maxLength;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final List<String>? autofill;
  final Widget? below;

  const AppField({
    super.key,
    required this.label,
    required this.icon,
    required this.controller,
    this.hint = '',
    this.required = true,
    this.optional = false,
    this.password = false,
    this.keyboard,
    this.maxLength,
    this.validator,
    this.onChanged,
    this.autofill,
    this.below,
  });

  @override
  State<AppField> createState() => _AppFieldState();
}

class _AppFieldState extends State<AppField> {
  bool hidden = true;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FieldLabel(widget.label, required: widget.required, optional: widget.optional),
      TextFormField(
        controller: widget.controller,
        obscureText: widget.password && hidden,
        keyboardType: widget.keyboard,
        autofillHints: widget.autofill,
        maxLength: widget.maxLength,
        onChanged: widget.onChanged,
        validator: widget.validator,
        style: sans(15),
        cursorColor: C.blue,
        decoration: fieldDecoration(widget.hint, widget.icon).copyWith(
          counterText: '',
          suffixIcon: widget.password
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: C.blueSoft,
                      foregroundColor: C.blue,
                      minimumSize: const Size(52, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => setState(() => hidden = !hidden),
                    child: Text(hidden ? 'Show' : 'Hide', style: sans(13, w: FontWeight.w600, color: C.blue)),
                  ),
                )
              : null,
        ),
      ),
      if (widget.below != null) widget.below!,
    ]);
  }
}

class FieldLabel extends StatelessWidget {
  final String text;
  final bool required, optional;
  const FieldLabel(this.text, {this.required = true, this.optional = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: text, style: sans(14, w: FontWeight.w600, color: C.navy)),
          if (required) TextSpan(text: ' *', style: sans(14, color: C.red)),
          if (optional) TextSpan(text: ' (optional)', style: sans(12.5, color: C.muted)),
        ])),
      );
}

class SectionTitle extends StatelessWidget {
  final IconData icon;
  final String text;
  const SectionTitle(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 18, color: C.navy),
        const SizedBox(width: 8),
        Text(text, style: sans(15, w: FontWeight.w700, color: C.navy)),
        const SizedBox(width: 8),
        const Expanded(child: Divider(height: 1, color: Color(0xFFE3EAF2))),
      ]);
}
