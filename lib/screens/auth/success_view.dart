import 'package:flutter/material.dart';

import 'package:tanod_incentives/theme.dart';
import 'package:tanod_incentives/widgets/yellow_button.dart';

// ---------------- Success ----------------
class SuccessView extends StatelessWidget {
  final String name, pos, area, muni;
  final VoidCallback onSignIn, onAgain;
  const SuccessView({
    super.key,
    required this.name,
    required this.pos,
    required this.area,
    required this.muni,
    required this.onSignIn,
    required this.onAgain,
  });

  Widget _row(String k, Widget v, {bool last = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: Color(0xFFE3EAF2))),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: sans(14, color: C.muted)),
          const SizedBox(width: 16),
          Expanded(child: Align(alignment: Alignment.centerRight, child: v)),
        ]),
      );

  Widget _val(String t) => Text(t, textAlign: TextAlign.right, style: sans(14, w: FontWeight.w600));

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const SizedBox(height: 6),
      Container(
        width: 76,
        height: 76,
        decoration: const BoxDecoration(
          color: C.greenSoft,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Color(0xFFF0FAF5), spreadRadius: 10)],
        ),
        child: const Icon(Icons.check, size: 36, color: C.green),
      ),
      const SizedBox(height: 18),
      Text('Request sent', style: serif(29)),
      const SizedBox(height: 8),
      Text(
        'The $muni reviewer will check your request. You can sign in now, but you can submit documents only after approval.',
        textAlign: TextAlign.center,
        style: sans(15, color: C.muted, h: 1.5),
      ),
      Container(
        margin: const EdgeInsets.symmetric(vertical: 22),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        decoration: BoxDecoration(
          color: C.mist,
          border: Border.all(color: C.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: [
          _row('Name', _val(name)),
          _row('Position', _val(pos)),
          _row('Area', _val('$area, $muni')),
          _row(
            'Status',
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
              decoration:
                  BoxDecoration(color: const Color(0xFFFFF4CC), borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: C.yellowDark, shape: BoxShape.circle)),
                const SizedBox(width: 7),
                Flexible(
                    child: Text('Waiting for approval',
                        style: sans(13, w: FontWeight.w600, color: const Color(0xFF7A5B00)))),
              ]),
            ),
            last: true,
          ),
        ]),
      ),
      YellowButton(label: 'Go to sign in', onPressed: onSignIn),
      const SizedBox(height: 12),
      YellowButton(label: 'Submit another request', onPressed: onAgain, ghost: true),
    ]);
  }
}
