import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tanod_incentives/theme.dart';

// App-wide pop-ups:
//   notify(context, 'Saved!')                       -> colored banner that slides down from the TOP
//   notify(context, 'No internet', type: NotifyType.error)
//   notify(context, '1 new message', onTap: () => openMessages())   -> tapping the pop-up goes there
//   await confirmAction(context, title: 'Remove?', message: '...', danger: true) -> true / false

enum NotifyType { success, info, warning, error }

({Color color, IconData icon, String title}) _look(NotifyType t) => switch (t) {
      NotifyType.success => (color: C.green, icon: Icons.check_circle_rounded, title: tr('Done', 'Tapos na', 'Human na')),
      NotifyType.info => (color: C.blue, icon: Icons.info_rounded, title: tr('Heads up', 'Paalala', 'Pahibalo')),
      NotifyType.warning => (color: C.yellowDark, icon: Icons.warning_amber_rounded, title: tr('Please check', 'Pakisuri', 'Palihog usisaa')),
      NotifyType.error => (color: C.red, icon: Icons.error_rounded, title: tr('Something went wrong', 'May problema', 'May problema')),
    };

OverlayEntry? _current;

/// Shows a banner at the top of the screen. Only one is shown at a time;
/// a new one replaces the old one. Tap or swipe it up to close early.
/// With [onTap], tapping the pop-up also runs it (e.g. opens the message).
void notify(
  BuildContext context,
  String message, {
  NotifyType type = NotifyType.success,
  String? title,
  Duration? duration,
  VoidCallback? onTap,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _current?.remove();
  _current = null;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _TopBanner(
      message: message,
      type: type,
      title: title,
      // Tappable pop-ups stay a bit longer so there's time to tap them
      duration: duration ?? Duration(seconds: onTap == null ? 3 : 6),
      onTap: onTap,
      onGone: () {
        if (_current == entry) _current = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _current = entry;
  overlay.insert(entry);
}

class _TopBanner extends StatefulWidget {
  final String message;
  final NotifyType type;
  final String? title;
  final Duration duration;
  final VoidCallback? onTap;
  final VoidCallback onGone;
  const _TopBanner(
      {required this.message, required this.type, required this.title, required this.duration, required this.onTap, required this.onGone});

  @override
  State<_TopBanner> createState() => _TopBannerState();
}

class _TopBannerState extends State<_TopBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  late final Animation<Offset> _slide =
      Tween(begin: const Offset(0, -1.3), end: Offset.zero).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack));
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _timer = Timer(widget.duration, _close);
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    await _c.reverse();
    widget.onGone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = _look(widget.type);
    final top = MediaQuery.of(context).padding.top + 12;
    return Positioned(
      top: top,
      left: 12,
      right: 12,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SlideTransition(
              position: _slide,
              child: FadeTransition(
                opacity: _c,
                child: Material(
                  color: Colors.transparent,
                  child: GestureDetector(
                    onTap: () {
                      _close();
                      widget.onTap?.call();
                    },
                    onVerticalDragEnd: (d) {
                      if ((d.primaryVelocity ?? 0) < 0) _close();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: look.color.withValues(alpha: .35)),
                        boxShadow: [
                          BoxShadow(color: look.color.withValues(alpha: .25), blurRadius: 24, offset: const Offset(0, 10)),
                          const BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 2)),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: IntrinsicHeight(
                        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Container(width: 6, color: look.color),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                            child: Container(
                              width: 38,
                              height: 38,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: look.color.withValues(alpha: .12), shape: BoxShape.circle),
                              child: Icon(look.icon, color: look.color, size: 24),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(widget.title ?? look.title,
                                      style: sans(15, w: FontWeight.w800, color: look.color)),
                                  const SizedBox(height: 2),
                                  Text(widget.message, style: sans(14.5, color: C.ink, h: 1.35)),
                                  if (widget.onTap != null) ...[
                                    const SizedBox(height: 4),
                                    Row(children: [
                                      Text(tr('Tap to open', 'Pindutin para buksan', 'Pinduta para buksan'),
                                          style: sans(13.5, w: FontWeight.w700, color: look.color)),
                                      Icon(Icons.chevron_right_rounded, size: 18, color: look.color),
                                    ]),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _close,
                            icon: const Icon(Icons.close_rounded, size: 20, color: C.muted),
                            tooltip: tr('Close', 'Isara', 'Sirhan'),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Are you sure?" box. Returns true only when the person taps the confirm button.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  String? cancelLabel,
  bool danger = false,
  IconData? icon,
}) async {
  final color = danger ? C.red : C.blue;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      icon: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color.withValues(alpha: .12), shape: BoxShape.circle),
        child: Icon(icon ?? (danger ? Icons.delete_outline_rounded : Icons.help_outline_rounded), color: color, size: 30),
      ),
      title: Text(title, textAlign: TextAlign.center, style: serif(22)),
      content: Text(message, textAlign: TextAlign.center, style: sans(15.5, color: C.ink, h: 1.5)),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(120, 46), foregroundColor: C.ink),
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel ?? tr('Cancel', 'Kanselahin', 'Kanselar')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, minimumSize: const Size(120, 46)),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel ?? tr('Yes, continue', 'Oo, ituloy', 'Huo, padayon')),
        ),
      ],
    ),
  );
  return ok ?? false;
}