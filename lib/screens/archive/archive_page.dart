import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:tanod_incentives/theme.dart';
import 'package:tanod_incentives/data/doc_kind.dart';
import 'package:tanod_incentives/data/archive_service.dart';
import 'package:tanod_incentives/data/cloud.dart';
import 'package:tanod_incentives/widgets/ui.dart';
import 'package:tanod_incentives/widgets/save_file.dart';
import 'package:tanod_incentives/widgets/pdf_pages.dart';

/// The signed-in town's id for the archive (demo: made from the name).
String archiveMuniId(String municipalityName) =>
    cloud.isMunicipal ? cloud.municipalityId : 'demo-${municipalityName.toLowerCase()}';

// ARCHIVE screen: every archived document, newest first, by year.
// Municipal accounts see their own town; OPPDC (municipalityId: null) sees all.

/// Makes the PDF and saves it to the archive, with pop-ups for each step.
Future<void> archivePdf(
  BuildContext context, {
  required DocKind kind,
  required int year,
  required String municipalityId,
  required String municipalityName,
  String barangayId = '',
  String barangayName = '',
  required int tanodCount,
  required String fileName,
  required Future<Uint8List> Function() build,
}) async {
  final place = barangayId.isEmpty ? municipalityName : 'Brgy. $barangayName';
  final ok = await confirmAction(
    context,
    title: 'Save to archive?',
    message: 'A permanent copy of the ${kind.title} of $place ($year) will be kept in the archive. '
        'Archiving again later makes a new copy; old copies are never replaced.',
    confirmLabel: 'Save to archive',
    icon: Icons.archive_outlined,
  );
  if (!ok || !context.mounted) return;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Row(children: [
          const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(width: 18),
          Expanded(child: Text('Archiving the ${kind.title}…', style: sans(16, w: FontWeight.w600, color: C.navy))),
        ]),
      ),
    ),
  );
  Object? failure;
  try {
    final pdf = await build();
    await archive.save(
      kind: kind,
      year: year,
      municipalityId: municipalityId,
      municipalityName: municipalityName,
      barangayId: barangayId,
      barangayName: barangayName,
      tanodCount: tanodCount,
      fileName: fileName,
      pdf: pdf,
    );
  } catch (e) {
    failure = e;
  }
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop(); // close "Archiving…"
  if (failure != null) {
    notify(context, Cloud.friendly(failure), type: NotifyType.error, title: 'Not archived');
  } else {
    notify(context, 'The ${kind.title} of $place is in the archive${archive.online ? '' : ' (demo: this session only)'}.',
        type: NotifyType.success, title: 'Archived');
  }
}

/// Small "Archive" button used on the document cards.
Widget archiveButton(VoidCallback? onPressed) => OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.archive_outlined, size: 18),
      label: const Text('Archive'),
    );

class ArchivePage extends StatefulWidget {
  /// null = every municipality (OPPDC)
  final String? municipalityId;
  final String title;
  const ArchivePage({super.key, this.municipalityId, required this.title});

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  late final Stream<List<ArchiveEntry>> _stream = archive.watch(municipalityId: widget.municipalityId);
  DocKind? _kind; // filter
  int? _year; // filter
  String _search = '';

  String _when(DateTime? t) {
    if (t == null) return 'saving…';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '${m[t.month - 1]} ${t.day}, ${t.year} · $h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  void _open(ArchiveEntry e) {
    showDialog(
      context: context,
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        return Dialog(
          backgroundColor: C.mist,
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 900, maxHeight: size.height * .92),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
                child: Row(children: [
                  Icon(e.kind.icon, color: C.navy),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${e.kind.title} · ${e.place} · ${e.year}',
                          style: sans(17, w: FontWeight.w700, color: C.navy), overflow: TextOverflow.ellipsis),
                      Text('Archived ${_when(e.savedAt)}${e.savedBy.isEmpty ? '' : ' by ${e.savedBy}'}', style: sans(13.5, color: C.muted)),
                    ]),
                  ),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                ]),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: PdfPages(cacheKey: 'archive|${e.id}', build: () => archive.loadPdf(e)),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: C.navy, foregroundColor: Colors.white, minimumSize: const Size(0, 46)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      downloadPdf(context, () => archive.loadPdf(e), e.fileName);
                    },
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Download PDF'),
                  ),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.mist,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: C.navy,
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Archive', style: sans(18, w: FontWeight.w700, color: C.navy)),
          Text(widget.title, style: sans(13.5, color: C.muted)),
        ]),
        actions: [
          if (!archive.online)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: pill('Demo: not saved online', const Color(0xFFFFF8E1), const Color(0xFF7A5B00)),
            ),
        ],
      ),
      body: StreamBuilder<List<ArchiveEntry>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return _message(Icons.lock_outline_rounded, 'Can’t open the archive',
                '${Cloud.friendly(snap.error!)}\n\nCheck the Firebase rules for the "archives" collection.');
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final all = snap.data!;
          final years = {for (final e in all) e.year}.toList()..sort((a, b) => b.compareTo(a));
          final q = _search.toLowerCase();
          final list = all
              .where((e) => _kind == null || e.kind == _kind)
              .where((e) => _year == null || e.year == _year)
              .where((e) => q.isEmpty || e.place.toLowerCase().contains(q) || e.fileName.toLowerCase().contains(q))
              .toList();

          Widget chip(String label, bool on, VoidCallback tap) => ChoiceChip(
                label: Text(label, style: sans(14.5, w: FontWeight.w600, color: on ? Colors.white : C.navy)),
                selected: on,
                showCheckmark: false,
                selectedColor: C.navy,
                backgroundColor: Colors.white,
                side: BorderSide(color: on ? C.navy : C.line, width: 1.5),
                onSelected: (_) => tap(),
              );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Archived documents', style: serif(28)),
                  const SizedBox(height: 6),
                  Text('Permanent copies of the Payroll, Masterlist, Certification and ID photocopy sheet, kept by year.',
                      style: sans(15.5, color: C.muted, h: 1.5)),
                  const SizedBox(height: 14),
                  TextField(
                    onChanged: (v) => setState(() => _search = v),
                    style: sans(16),
                    decoration: InputDecoration(
                      hintText: 'Search town or barangay',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.line)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    chip('All documents', _kind == null, () => setState(() => _kind = null)),
                    for (final k in DocKind.values) chip(k.title, _kind == k, () => setState(() => _kind = k)),
                  ]),
                  if (years.length > 1) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      chip('All years', _year == null, () => setState(() => _year = null)),
                      for (final y in years) chip('$y', _year == y, () => setState(() => _year = y)),
                    ]),
                  ],
                  const SizedBox(height: 16),
                  if (list.isEmpty)
                    _message(Icons.archive_outlined, 'Nothing archived yet',
                        'Open Documents and press "Archive" on a Payroll, Masterlist, Certification or ID photocopy sheet.')
                  else
                    Panel(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Column(children: [
                        for (final e in list)
                          InkWell(
                            onTap: () => _open(e),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE9EFF5)))),
                              child: Row(children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(color: C.blueSoft, borderRadius: BorderRadius.circular(12)),
                                  child: Icon(e.kind.icon, color: C.blue),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('${e.kind.title} · ${e.place}', style: sans(16, w: FontWeight.w700, color: C.navy)),
                                    const SizedBox(height: 2),
                                    Text(
                                        'CY ${e.year} · ${e.tanodCount} tanods · archived ${_when(e.savedAt)}'
                                        '${e.savedBy.isEmpty ? '' : ' · ${e.savedBy}'}',
                                        style: sans(13.5, color: C.muted)),
                                  ]),
                                ),
                                IconButton(
                                  tooltip: 'Download',
                                  onPressed: () => downloadPdf(context, () => archive.loadPdf(e), e.fileName),
                                  icon: const Icon(Icons.download_rounded, color: C.navy),
                                ),
                                const Icon(Icons.chevron_right_rounded, color: C.muted),
                              ]),
                            ),
                          ),
                      ]),
                    ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _message(IconData icon, String title, String body) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 40, color: C.muted),
          const SizedBox(height: 10),
          Text(title, style: sans(18, w: FontWeight.w700, color: C.navy), textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(body, style: sans(15, color: C.muted, h: 1.45), textAlign: TextAlign.center),
        ]),
      );
}