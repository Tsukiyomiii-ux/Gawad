import 'package:flutter/material.dart';

import 'package:tanod_incentives/theme.dart';
import 'package:tanod_incentives/widgets/notify.dart';

export 'package:tanod_incentives/widgets/notify.dart'; // so screens using ui.dart get notify() too

// Shared building blocks for the municipality and OPPDC screens.

Widget logoMark(double s) => Container(
      width: s,
      height: s,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: C.yellow, borderRadius: BorderRadius.circular(s * .3)),
      child: Text('G', style: serif(s * .55)),
    );

Widget pill(String text, Color bg, Color fg, {IconData? icon}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 5)],
        Text(text, style: sans(13.5, w: FontWeight.w600, color: fg)),
      ]),
    );

// "What does this mean?" box.
void showExplain(BuildContext context, String title, String body) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      icon: const Icon(Icons.lightbulb_outline_rounded, color: C.yellowDark, size: 30),
      title: Text(title, textAlign: TextAlign.center, style: serif(22)),
      content: Text(body, style: sans(15.5, color: C.ink, h: 1.55)),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: C.navy,
            foregroundColor: Colors.white,
            minimumSize: const Size(140, 46),
          ),
          onPressed: () => Navigator.pop(ctx),
          child: Text(tr('Got it', 'Sige', 'Sige')),
        ),
      ],
    ),
  );
}

// Now a colored pop-up at the TOP of the screen (see widgets/notify.dart)
void toast(BuildContext context, String message, {NotifyType type = NotifyType.success, String? title}) =>
    notify(context, message, type: type, title: title);

// White rounded card with an optional title row.
class Panel extends StatelessWidget {
  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final String? help;
  final Widget child;
  final EdgeInsets padding;
  const Panel({
    super.key,
    this.title,
    this.icon,
    this.trailing,
    this.help,
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1E9F2)),
        boxShadow: [
          BoxShadow(color: C.navy.withValues(alpha: .06), blurRadius: 24, spreadRadius: -8, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null) ...[
          Row(children: [
            if (icon != null) ...[Icon(icon, size: 20, color: C.navy), const SizedBox(width: 10)],
            Flexible(child: Text(title!, style: sans(17.5, w: FontWeight.w700, color: C.navy))),
            if (help != null)
              IconButton(
                tooltip: tr('What’s this?', 'Ano ito?', 'Ano ini?'),
                visualDensity: VisualDensity.compact,
                onPressed: () => showExplain(context, title!, help!),
                icon: const Icon(Icons.help_outline_rounded, size: 20, color: C.blue),
              ),
            const Spacer(),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 16),
        ],
        child,
      ]),
    );
  }
}

class StatTile extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String value, label, note;
  final double? progress;
  const StatTile({
    super.key,
    required this.icon,
    required this.tint,
    required this.value,
    required this.label,
    required this.note,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: tint.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 21, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: sans(15, w: FontWeight.w600, color: C.muted))),
        ]),
        const SizedBox(height: 16),
        Text(value, style: sans(28, w: FontWeight.w700, color: C.navy, h: 1.1)),
        const SizedBox(height: 6),
        Text(note, style: sans(14, color: C.muted)),
        if (progress != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress!.clamp(0, 1).toDouble(),
              minHeight: 6,
              backgroundColor: const Color(0xFFE3EAF2),
              valueColor: AlwaysStoppedAnimation(tint),
            ),
          ),
        ],
      ]),
    );
  }
}

// Lays children out in equal columns that wrap on small screens.
class Grid extends StatelessWidget {
  final List<Widget> children;
  final double gap;
  final int maxCols;
  final double minWidth;
  const Grid({super.key, required this.children, this.gap = 16, this.maxCols = 4, this.minWidth = 220});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final cols = (box.maxWidth / minWidth).floor().clamp(1, maxCols).toInt();
      final w = ((box.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
      return Wrap(spacing: gap, runSpacing: gap, children: [for (final c in children) SizedBox(width: w, child: c)]);
    });
  }
}

ButtonStyle primaryStyle({Color bg = C.yellow, Color fg = C.navy}) => FilledButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      disabledBackgroundColor: const Color(0xFFE3EAF2),
      disabledForegroundColor: const Color(0xFF97A5B5),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      minimumSize: const Size(0, 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      textStyle: sans(15.5, w: FontWeight.w700),
    );

ButtonStyle outlineStyle({Color fg = C.navy, Color border = C.line}) => OutlinedButton.styleFrom(
      foregroundColor: fg,
      side: BorderSide(color: border, width: 1.5),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      minimumSize: const Size(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: sans(15, w: FontWeight.w600),
    );