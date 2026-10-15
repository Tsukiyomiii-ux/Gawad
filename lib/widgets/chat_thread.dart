import 'package:flutter/material.dart';

import 'package:tanod_incentives/theme.dart';
import 'package:tanod_incentives/data/demo_data.dart';
import 'package:tanod_incentives/data/doc_kind.dart';
import 'package:tanod_incentives/data/store.dart';

// The conversation between one barangay and the municipal reviewer.
// Used on both sides. A message can be tagged to one document; a tagged
// message from the municipality is a correction request for that document.

class ChatThread extends StatefulWidget {
  final BrgyRecord rec;
  final bool asMunicipality;
  final void Function(String text, DocKind? doc) onSend;
  final void Function(DocKind doc)? onUploadFix; // barangay: upload the corrected copy
  final List<(String, String, DocKind?)> quickMessages; // (chip label, message, document)
  final double height;

  const ChatThread({
    super.key,
    required this.rec,
    required this.asMunicipality,
    required this.onSend,
    this.onUploadFix,
    this.quickMessages = const [],
    this.height = 420,
  });

  @override
  State<ChatThread> createState() => ChatThreadState();
}

class ChatThreadState extends State<ChatThread> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  DocKind? about;
  int _seen = 0;

  @override
  void initState() {
    super.initState();
    _seen = widget.rec.chat.length;
    _toBottom(animate: false);
  }

  @override
  void didUpdateWidget(covariant ChatThread oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rec.chat.length != _seen) {
      _seen = widget.rec.chat.length;
      _toBottom();
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(end, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      } else {
        _scroll.jumpTo(end);
      }
    });
  }

  // Start a message about a document, optionally with text already filled in.
  void compose(DocKind? doc, [String text = '']) => setState(() {
        about = doc;
        if (text.isNotEmpty) _text.text = text;
      });

  void _send() {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    widget.onSend(t, about);
    _text.clear();
    setState(() => about = null);
  }

  String get _reviewer => tr('$kMunicipality reviewer', 'Reviewer ng $kMunicipality', 'Reviewer sang $kMunicipality');

  @override
  Widget build(BuildContext context) {
    final msgs = widget.rec.chat;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: widget.height,
        decoration: BoxDecoration(color: C.mist, borderRadius: BorderRadius.circular(16)),
        child: msgs.isEmpty
            ? Center(
                child: Text(tr('No messages yet.', 'Wala pang mensahe.', 'Wala pa sang mensahe.'),
                    style: sans(15, color: C.muted)),
              )
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(14),
                itemCount: msgs.length,
                itemBuilder: (context, i) => _bubble(msgs[i]),
              ),
      ),
      const SizedBox(height: 12),
      if (widget.quickMessages.isNotEmpty) ...[
        Text(tr('Quick messages', 'Mabilis na mensahe', 'Madasig nga mensahe'),
            style: sans(14, w: FontWeight.w700, color: C.muted)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (label, text, doc) in widget.quickMessages)
            ActionChip(
              label: Text(label, style: sans(14, color: C.navy)),
              backgroundColor: Colors.white,
              side: const BorderSide(color: C.line),
              onPressed: () => compose(null, text), // fills in the text only
            ),
        ]),
        const SizedBox(height: 12),
      ],
      // ("About" document chips removed: corrections are sent from each document's
      //  "Something's wrong" button on the checking page instead)
      const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: TextField(
            controller: _text,
            minLines: 1,
            maxLines: 4,
            style: sans(15.5),
            cursorColor: C.blue,
            textInputAction: TextInputAction.newline,
            decoration: fieldDecoration(
              tr('Type a message', 'Mag-type ng mensahe', 'Magsulat sang mensahe'),
              Icons.chat_bubble_outline_rounded,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: C.navy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _send,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: Text(tr('Send', 'Ipadala', 'Ipadala'), style: sans(15, w: FontWeight.w700, color: Colors.white)),
          ),
        ),
      ]),
    ]);
  }

  Widget _bubble(ChatMsg m) {
    if (m.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: C.line),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(m.doc == null ? Icons.info_outline : m.doc!.icon, size: 15, color: C.muted),
              const SizedBox(width: 7),
              Flexible(child: Text('${m.text} · ${m.time}', style: sans(13.5, color: C.muted, h: 1.35))),
            ]),
          ),
        ),
      );
    }

    final mine = m.fromMunicipality == widget.asMunicipality;
    final who = m.fromMunicipality ? _reviewer : 'Brgy. ${widget.rec.name}';
    final f = m.doc == null ? null : widget.rec.files[m.doc];
    final isLatest = m.doc != null && widget.rec.lastAbout(m.doc!) == m;
    final stillOpen = m.fromMunicipality && f != null && f.correction && isLatest;
    final fixed = m.fromMunicipality && f != null && !f.correction && isLatest;
    final bg = mine ? C.navy : Colors.white;
    final fg = mine ? Colors.white : C.ink;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: Text('$who · ${m.time}', style: sans(12.5, w: FontWeight.w600, color: C.muted)),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              decoration: BoxDecoration(
                color: bg,
                border: mine ? null : Border.all(color: stillOpen ? const Color(0xFFF0C7C3) : C.line),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(mine ? 16 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 16),
                ),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (m.doc != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: mine ? Colors.white.withValues(alpha: .14) : (stillOpen ? const Color(0xFFFDF0EE) : C.mist),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(m.doc!.icon, size: 14, color: mine ? Colors.white : (stillOpen ? C.red : C.navy)),
                      const SizedBox(width: 5),
                      Text(m.doc!.title,
                          style: sans(13, w: FontWeight.w700, color: mine ? Colors.white : (stillOpen ? C.red : C.navy))),
                    ]),
                  ),
                  const SizedBox(height: 6),
                ],
                Text(m.text, style: sans(15.5, color: fg, h: 1.45)),
                if (stillOpen && !widget.asMunicipality && widget.onUploadFix != null) ...[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: C.yellow,
                      foregroundColor: C.navy,
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                    ),
                    onPressed: () => widget.onUploadFix!(m.doc!),
                    icon: const Icon(Icons.upload_rounded, size: 18),
                    label: Text(tr('Upload corrected copy', 'I-upload ang naitamang kopya', 'I-upload ang natadlong nga kopya'),
                        style: sans(14.5, w: FontWeight.w700, color: C.navy)),
                  ),
                ],
                if (stillOpen && widget.asMunicipality) ...[
                  const SizedBox(height: 6),
                  Text(tr('Waiting for the corrected copy', 'Hinihintay ang naitamang kopya', 'Ginahulat ang natadlong nga kopya'),
                      style: sans(13, w: FontWeight.w600, color: Colors.white70)),
                ],
                if (fixed) ...[
                  const SizedBox(height: 8),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle, size: 16, color: mine ? const Color(0xFF8FE3BE) : C.green),
                    const SizedBox(width: 5),
                    Text(tr('Corrected copy uploaded', 'Na-upload ang naitamang kopya', 'Na-upload ang natadlong nga kopya'),
                        style: sans(13.5, w: FontWeight.w600, color: mine ? const Color(0xFF8FE3BE) : C.green)),
                  ]),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}