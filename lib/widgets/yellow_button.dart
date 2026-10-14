import 'package:flutter/material.dart';

import 'package:tanod_incentives/theme.dart';

class YellowButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final bool ghost;
  const YellowButton({required this.label, required this.onPressed, this.icon, this.ghost = false});
  @override
  State<YellowButton> createState() => _YellowButtonState();
}

class _YellowButtonState extends State<YellowButton> {
  bool down = false;
  @override
  Widget build(BuildContext context) {
    final ghost = widget.ghost;
    return GestureDetector(
      onTapDown: (_) => setState(() => down = true),
      onTapCancel: () => setState(() => down = false),
      onTapUp: (_) => setState(() => down = false),
      onTap: widget.onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: 52,
        transform: Matrix4.translationValues(0, down && !ghost ? 3 : 0, 0),
        decoration: BoxDecoration(
          color: ghost ? Colors.white : C.yellow,
          borderRadius: BorderRadius.circular(13),
          border: ghost ? Border.all(color: C.line, width: 1.5) : null,
          boxShadow: ghost || down ? null : const [BoxShadow(color: C.yellowDark, offset: Offset(0, 3))],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (widget.icon != null) ...[Icon(widget.icon, size: 18, color: C.navy), const SizedBox(width: 9)],
          Text(widget.label, style: sans(16, w: ghost ? FontWeight.w600 : FontWeight.w700, color: C.navy)),
        ]),
      ),
    );
  }
}
