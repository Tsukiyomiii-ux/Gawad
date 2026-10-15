import 'package:flutter/material.dart';
import 'package:tanod_incentives/screens/archive/archive_page.dart'; // ARCHIVE

import 'package:tanod_incentives/theme.dart';
import 'package:tanod_incentives/data/admin_data.dart';
import 'package:tanod_incentives/data/doc_kind.dart';
import 'package:tanod_incentives/data/store.dart';
import 'package:tanod_incentives/widgets/ui.dart';
import 'package:tanod_incentives/widgets/save_file.dart';
import 'package:tanod_incentives/widgets/pdf_pages.dart';
import 'package:tanod_incentives/services/database_service.dart' show Status;

// OPPDC: one barangay's four documents (preview, download, signed copy)
// and its tanod list. Read-only.
class AdminDocsPage extends StatefulWidget {
  final AdminBrgy brgy;
  const AdminDocsPage({super.key, required this.brgy});

  @override
  State<AdminDocsPage> createState() => _AdminDocsPageState();
}

class _AdminDocsPageState extends State<AdminDocsPage> {
  BrgyRecord? rec;
  Object? error;

  AdminBrgy get b => widget.brgy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      rec = null;
      error = null;
    });
    try {
      final r = await admin.loadRecord(b);
      if (mounted) setState(() => rec = r);
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  String _fileName(DocKind k) => '${k.title} - Brgy ${b.name} - ${b.muniName} - ${admin.year}.pdf';

  void _download(BrgyRecord r, DocKind k) =>
      downloadPdf(context, () => admin.buildPdf(b, r, k), _fileName(k));

  void _preview(BrgyRecord r, DocKind k) {
    showDialog(
      context: context,
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        return Dialog(
          backgroundColor: C.mist,
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 760, maxHeight: size.height * .92),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
                child: Row(children: [
                  Icon(k.icon, color: C.navy),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${k.title} · Brgy ${b.name}',
                        style: sans(17, w: FontWeight.w700, color: C.navy), overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                ]),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: PdfPages(cacheKey: admin.pdfKey(b, r, k), build: () => admin.buildPdf(b, r, k)),
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
                      _download(r, k);
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
    final r = rec;
    return Scaffold(
      backgroundColor: C.mist,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: C.navy,
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Brgy ${b.name}', style: sans(18, w: FontWeight.w700, color: C.navy)),
          Text('${b.muniName} · ${admin.year}', style: sans(13.5, color: C.muted)),
        ]),
        actions: [
          Padding(padding: const EdgeInsets.only(right: 8), child: _statusPill(b)),
          IconButton(tooltip: 'Reload', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off_rounded, size: 40, color: C.red),
                  const SizedBox(height: 12),
                  Text('Could not open the documents.', style: sans(17, w: FontWeight.w700, color: C.navy)),
                  const SizedBox(height: 6),
                  Text('$error', textAlign: TextAlign.center, style: sans(14, color: C.muted)),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _load, child: const Text('Try again')),
                ]),
              ),
            )
          : r == null
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(builder: (context, c) {
                  final cols = c.maxWidth >= 620 ? 2 : 1; // Certification + ID sheet
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1300),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          _summary(r),
                          const SizedBox(height: 16),
                          Wrap(spacing: 16, runSpacing: 16, children: [
                            for (final k in kBarangayDocs)
                              SizedBox(
                                width: (c.maxWidth.clamp(0, 1300) - 32 - 16 * (cols - 1)) / cols,
                                child: _docCard(r, k),
                              ),
                          ]),
                          const SizedBox(height: 16),
                          _tanodList(r),
                        ]),
                      ),
                    ),
                  );
                }),
    );
  }

  Widget _summary(BrgyRecord r) {
    Widget item(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: sans(13, color: C.muted)),
          const SizedBox(height: 2),
          Text(value, style: sans(16, w: FontWeight.w700, color: C.navy)),
        ]);
    return Panel(
      child: Wrap(spacing: 36, runSpacing: 14, children: [
        item('Punong Barangay', r.captain.isEmpty ? '—' : r.captain),
        item('Tanods', '${r.tanods.length} of ${b.limit}'),
        item('Award numbers', b.awardStart > 0 ? '${b.awardStart}–${b.awardEnd}' : '—'),
        if (b.reviewNote.isNotEmpty) item('Last note', b.reviewNote),
      ]),
    );
  }

  Widget _docCard(BrgyRecord r, DocKind k) {
    return Panel(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(k.icon, size: 20, color: C.navy),
          const SizedBox(width: 8),
          Expanded(child: Text(k.title, style: sans(16, w: FontWeight.w700, color: C.navy), overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => _preview(r, k),
          child: Container(
            height: 220,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: C.line), borderRadius: BorderRadius.circular(8)),
            child: PdfPages(cacheKey: admin.pdfKey(b, r, k), build: () => admin.buildPdf(b, r, k), thumbnail: true),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: () => _preview(r, k),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('Preview'),
          ),
          OutlinedButton.icon(
            onPressed: () => _download(r, k),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Download'),
          ),
        ]),
      ]),
    );
  }

  Widget _tanodList(BrgyRecord r) {
    final list = [...r.tanods]..sort((a, z) => (a.awardNumber ?? 1 << 30).compareTo(z.awardNumber ?? 1 << 30));
    return Panel(
      title: 'Tanods (${list.length})',
      icon: Icons.groups_2_outlined,
      child: list.isEmpty
          ? Text('No tanods listed yet.', style: sans(15, color: C.muted))
          : Column(children: [
              Row(children: [
                SizedBox(width: 90, child: Text('AWARD NO.', style: sans(12.5, w: FontWeight.w700, color: C.muted))),
                Expanded(child: Text('NAME', style: sans(12.5, w: FontWeight.w700, color: C.muted))),
                SizedBox(width: 90, child: Center(child: Text('ID PHOTO', style: sans(12.5, w: FontWeight.w700, color: C.muted)))),
              ]),
              const Divider(),
              for (var i = 0; i < list.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(children: [
                    SizedBox(width: 90, child: Text('${list[i].awardNumber ?? i + 1}', style: sans(15, color: C.ink))),
                    Expanded(child: Text(list[i].fullName, style: sans(15, w: FontWeight.w600, color: C.ink))),
                    SizedBox(
                      width: 90,
                      child: Center(
                        child: list[i].idFront != null
                            ? const Icon(Icons.check_circle_rounded, color: C.green, size: 20)
                            : const Icon(Icons.remove_circle_outline_rounded, color: C.muted, size: 20),
                      ),
                    ),
                  ]),
                ),
              ],
            ]),
    );
  }
}

// ======================= MUNICIPAL LEVEL: one Payroll + one Masterlist =======================

/// Preview + download of a municipality's Payroll or Masterlist (all its barangays).
void showMuniDoc(BuildContext context, AdminMuni m, DocKind k) {
  final name = '${k.title} - ${m.name} (all barangays) - ${admin.year}.pdf';
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
                Icon(k.icon, color: C.navy),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${k.title} · ${m.name} (all barangays)',
                      style: sans(17, w: FontWeight.w700, color: C.navy), overflow: TextOverflow.ellipsis),
                ),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: PdfPages(cacheKey: admin.muniPdfKey(m, k), build: () => admin.buildMuniPdf(m, k)),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    archivePdf(
                      context,
                      kind: k,
                      year: admin.year,
                      municipalityId: m.id,
                      municipalityName: m.name,
                      tanodCount: m.tanods,
                      fileName: name,
                      build: () => admin.buildMuniPdf(m, k),
                    );
                  },
                  icon: const Icon(Icons.archive_outlined, size: 18),
                  label: const Text('Archive'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: C.navy, foregroundColor: Colors.white, minimumSize: const Size(0, 46)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    downloadPdf(context, () => admin.buildMuniPdf(m, k), name);
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

/// Status label of a barangay: same 5 stages as the barangay's Submission status.
Widget _statusPill(AdminBrgy b) {
  final i = brgyStage(b);
  final (Color bg, Color fg) = switch (i) {
    1 => (const Color(0xFFFFF4CC), const Color(0xFF7A5B00)),
    2 => (C.blueSoft, C.blue),
    3 => (const Color(0xFFE6E9FB), const Color(0xFF3A4BB0)),
    4 => (C.greenSoft, const Color(0xFF14583D)),
    _ => (const Color(0xFFEDF1F5), C.muted),
  };
  return pill(kStageNames[i], bg, fg);
}