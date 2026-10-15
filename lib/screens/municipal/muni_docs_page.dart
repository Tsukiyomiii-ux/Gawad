import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tanod_incentives/screens/archive/archive_page.dart'; // ARCHIVE

import 'package:tanod_incentives/theme.dart';
import 'package:tanod_incentives/data/doc_kind.dart';
import 'package:tanod_incentives/data/demo_data.dart';
import 'package:tanod_incentives/data/store.dart';
import 'package:tanod_incentives/data/cloud.dart';
import 'package:tanod_incentives/widgets/ui.dart';
import 'package:tanod_incentives/widgets/save_file.dart';
import 'package:tanod_incentives/widgets/pdf_pages.dart';
import 'package:tanod_incentives/Templates/gawad_pdf.dart' show buildOfficialPdf, officialPdfName;
import 'package:tanod_incentives/screens/dashboard/documents_view.dart' show officialPdfKey, showBackupCopy, shareSignedCopy;
import 'package:tanod_incentives/screens/municipal/check_page.dart' show statusColors, muniStage;
import 'package:tanod_incentives/data/tanod_bridge.dart' show personsFor;
import 'package:tanod_incentives/Templates/payroll_template.dart'
    show generatePayrollPdf, payrollOfficials, kDefaultPayrollOfficials, kPayrollOfficialRoles;
import 'package:tanod_incentives/Templates/masterlist_template.dart' show generateMasterlistPdf;

// ================= ONE Payroll + ONE Masterlist for the whole municipality =================
// Every barangay's tanods (from the database, live) in a single document.
// The Payroll gets one page per barangay, numbered across the municipality.

int _num(int? n) => n ?? (1 << 30);

/// Lowest award number in a barangay (its block of numbers).
int _firstNumber(BrgyRecord b) => b.tanods.map((t) => _num(t.awardNumber)).fold(1 << 30, (a, n) => n < a ? n : a);

/// Barangays that have tanods, in award-number order (then A → Z).
List<BrgyRecord> _withTanods() => [...store.brgys.where((b) => b.tanods.isNotEmpty)]
  ..sort((a, b) {
    final c = _firstNumber(a).compareTo(_firstNumber(b));
    return c != 0 ? c : a.name.compareTo(b.name);
  });

/// Payroll and Masterlist open only when EVERY barangay is complete.
bool get municipalDocsReady => store.brgys.isNotEmpty && store.brgys.every((b) => muniStage(b.status) == BrgyStatus.checked);

Future<Uint8List> buildMunicipalPdf(DocKind k) {
  // Each tanod keeps the award number saved in the database (Novee no. 1 is
  // no. 1 on both documents, Gelyn no. 88 is no. 88), so the list is in that order.
  final listed = [for (final b in _withTanods()) ...personsFor(b)];
  // Stable sort: tanods without a number (demo data) keep their list order
  final order = List<int>.generate(listed.length, (i) => i)
    ..sort((i, j) {
      final c = _num(listed[i].awardNumber).compareTo(_num(listed[j].awardNumber));
      return c != 0 ? c : i.compareTo(j);
    });
  final people = [for (final i in order) listed[i]];
  return switch (k) {
    DocKind.payroll => generatePayrollPdf(
        tanodList: people,
        period: 'For the period CY $kYear',
        municipality: 'MUNICIPALITY OF ${kMunicipality.toUpperCase()}',
        defaultAmount: kAmountEach.toDouble(),
      ),
    _ => generateMasterlistPdf(tanodList: people, calendarYear: '$kYear'),
  };
}

/// Changes whenever any barangay's list changes (so the preview redraws).
String municipalPdfKey(DocKind k) => [
      'muni',
      k.name,
      kMunicipality,
      kYear,
      kAmountEach,
      if (k == DocKind.payroll) ...payrollOfficials.values,
      for (final b in _withTanods()) ...[b.name, for (final t in b.tanods) '${t.awardNumber}|${t.fullName}|${t.scannedAddress}'],
    ].join('~');

String municipalPdfName(DocKind k) => '${k.title} - $kMunicipality (all barangays) - $kYear.pdf';

/// The two unified documents, side by side, for the Documents tab.
class MunicipalDocs extends StatefulWidget {
  const MunicipalDocs({super.key});

  @override
  State<MunicipalDocs> createState() => _MunicipalDocsState();
}

class _MunicipalDocsState extends State<MunicipalDocs> {
  // Edit the officials printed on the Payroll. Saved only when "Save" is pressed.
  Future<void> _editSignatories() async {
    final ctrls = {for (final k in kPayrollOfficialRoles.keys) k: TextEditingController(text: payrollOfficials[k] ?? '')};
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Payroll signatories', 'Mga pipirma sa Payroll', 'Mga mapirma sa Payroll'),
            style: sans(19, w: FontWeight.w700, color: C.navy)),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final e in kPayrollOfficialRoles.entries) ...[
                TextField(
                  controller: ctrls[e.key],
                  textCapitalization: TextCapitalization.characters,
                  style: sans(15.5),
                  decoration: InputDecoration(
                    labelText: e.value,
                    hintText: kDefaultPayrollOfficials[e.key]!.isEmpty ? 'Full name' : kDefaultPayrollOfficials[e.key],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel', 'Kanselahin', 'Kanselahon'))),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: C.navy, foregroundColor: Colors.white, minimumSize: const Size(0, 46)),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.save_outlined, size: 18),
            label: Text(tr('Save changes', 'I-save', 'I-save')),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    final values = {for (final e in ctrls.entries) e.key: e.value.text.trim().toUpperCase()};
    setState(() => payrollOfficials.addAll(values));
    try {
      await cloud.savePayrollOfficials(values); // FIREBASE
      if (mounted) {
        toast(context, tr('The Payroll now shows the new names.', 'Na-update ang mga pangalan sa Payroll.', 'Na-update ang mga ngalan sa Payroll.'),
            title: tr('Signatories saved', 'Na-save ang pipirma', 'Na-save ang mapirma'));
      }
    } catch (e) {
      if (mounted) toast(context, Cloud.friendly(e), type: NotifyType.error, title: tr('Not saved online', 'Hindi na-save online', 'Wala na-save online'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final brgys = _withTanods();
    final tanods = brgys.fold<int>(0, (a, b) => a + b.tanods.length);
    final complete = store.brgys.where((b) => muniStage(b.status) == BrgyStatus.checked).length;
    if (!municipalDocsReady) {
      return Panel(
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: C.mist, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.lock_outline_rounded, color: C.muted),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Payroll and Masterlist are locked', 'Naka-lock ang Payroll at Masterlist', 'Naka-lock ang Payroll kag Masterlist'),
                  style: sans(17, w: FontWeight.w700, color: C.navy)),
              const SizedBox(height: 3),
              Text(
                  tr('They are made once every barangay is Complete ($complete of ${store.brgys.length} so far). '
                          'Press Receive on each barangay when its documents arrive.',
                      'Gagawin ito kapag Kumpleto na ang lahat ng barangay ($complete sa ${store.brgys.length}).',
                      'Himuon ini kon Kompleto na ang tanan nga barangay ($complete sa ${store.brgys.length}).'),
                  style: sans(14.5, color: C.muted, h: 1.45)),
            ]),
          ),
        ]),
      );
    }
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 620 ? 2 : 1;
      final w = (c.maxWidth - 16 * (cols - 1)) / cols;
      return Wrap(spacing: 16, runSpacing: 16, children: [
        for (final k in const [DocKind.payroll, DocKind.masterlist])
          SizedBox(width: w, child: _unifiedCard(context, k, brgys.length, tanods)),
      ]);
    });
  }

  Widget _unifiedCard(BuildContext context, DocKind k, int brgyCount, int tanods) {
    final empty = tanods == 0;
    void preview() => showDialog(
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
                        child: Text('${k.title} · $kMunicipality (all barangays)',
                            style: sans(17, w: FontWeight.w700, color: C.navy), overflow: TextOverflow.ellipsis),
                      ),
                      IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                    ]),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(18),
                      child: PdfPages(cacheKey: municipalPdfKey(k), build: () => buildMunicipalPdf(k)),
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
                          downloadPdf(context, () => buildMunicipalPdf(k), municipalPdfName(k));
                        },
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: Text(tr('Download PDF', 'I-download ang PDF', 'I-download ang PDF')),
                      ),
                    ]),
                  ),
                ]),
              ),
            );
          },
        );

    return Panel(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(k.icon, size: 22, color: C.navy),
          const SizedBox(width: 8),
          Expanded(child: Text('${k.title} · $kMunicipality', style: sans(17, w: FontWeight.w700, color: C.navy))),
        ]),
        const SizedBox(height: 4),
        Text(
            tr('All barangays in one document · $brgyCount barangay${brgyCount == 1 ? '' : 's'} · $tanods tanods',
                'Lahat ng barangay sa iisang dokumento · $brgyCount barangay · $tanods tanod',
                'Tanan nga barangay sa isa ka dokumento · $brgyCount ka barangay · $tanods ka tanod'),
            style: sans(14, color: C.muted)),
        const SizedBox(height: 12),
        InkWell(
          onTap: empty ? null : preview,
          child: Container(
            height: 240,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: C.line), borderRadius: BorderRadius.circular(8)),
            child: empty
                ? Center(child: Text(tr('No tanods yet', 'Wala pang tanod', 'Wala pa sang tanod'), style: sans(15, color: C.muted)))
                : PdfPages(cacheKey: municipalPdfKey(k), build: () => buildMunicipalPdf(k), thumbnail: true),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (k == DocKind.payroll)
            OutlinedButton.icon(
              onPressed: _editSignatories,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(tr('Edit signatories', 'I-edit ang pipirma', 'I-edit ang mapirma')),
            ),
          OutlinedButton.icon(
            onPressed: empty ? null : preview,
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: Text(tr('Preview', 'Tingnan', 'Tan-awa')),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: C.navy, foregroundColor: Colors.white),
            onPressed: empty ? null : () => downloadPdf(context, () => buildMunicipalPdf(k), municipalPdfName(k)),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(tr('Download', 'I-download', 'I-download')),
          ),
          archiveButton(empty
              ? null
              : () => archivePdf(
                    context,
                    kind: k,
                    year: kYear,
                    municipalityId: archiveMuniId(kMunicipality),
                    municipalityName: kMunicipality,
                    tanodCount: tanods,
                    fileName: municipalPdfName(k),
                    build: () => buildMunicipalPdf(k),
                  )),
        ]),
      ]),
    );
  }
}


// MUNICIPAL: one barangay's own documents (Certification + ID photocopy sheet).
// The Payroll and Masterlist are one document for the whole municipality (above).
// Preview, download, and the signed copy when the barangay uploaded one.
class MuniDocsPage extends StatefulWidget {
  final BrgyRecord rec;
  const MuniDocsPage({super.key, required this.rec});

  @override
  State<MuniDocsPage> createState() => _MuniDocsPageState();
}

class _MuniDocsPageState extends State<MuniDocsPage> {
  BrgyRecord get rec => widget.rec;
  bool loadingIds = false;

  @override
  void initState() {
    super.initState();
    _loadIdPhotos();
  }

  // FIREBASE: the ID photos are only fetched when needed (for the ID sheet)
  Future<void> _loadIdPhotos() async {
    if (!cloud.isMunicipal) return;
    final missing = rec.tanods.where((t) => t.id != null && t.idFront == null).toList();
    if (missing.isEmpty) return;
    setState(() => loadingIds = true);
    await Future.wait([
      for (final t in missing)
        cloud.db.getIdScan(t.id!).then((s) {
          if (s != null) {
            t.idFront = s.front;
            t.idBack = s.back;
          }
        }).catchError((Object _) {}),
    ]);
    if (mounted) setState(() => loadingIds = false);
  }

  void _download(DocKind k) => downloadPdf(context, () => buildOfficialPdf(rec, k), officialPdfName(rec, k));

  void _preview(DocKind k) {
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
                    child: Text('${k.title} · Brgy. ${rec.name}',
                        style: sans(17, w: FontWeight.w700, color: C.navy), overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                ]),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: PdfPages(cacheKey: officialPdfKey(rec, k), build: () => buildOfficialPdf(rec, k)),
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
                      _download(k);
                    },
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text(tr('Download PDF', 'I-download ang PDF', 'I-download ang PDF')),
                  ),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }

  void _signed(DocKind k) => showBackupCopy(
        context,
        rec: rec,
        kind: k,
        actions: (ctx) => [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
            onPressed: () {
              Navigator.pop(ctx);
              shareSignedCopy(context, rec, k);
            },
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(tr('Download', 'I-download', 'I-download')),
          ),
        ],
      );

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
          Text('Brgy. ${rec.name}', style: sans(18, w: FontWeight.w700, color: C.navy)),
          Text('${tr('Documents', 'Mga Dokumento', 'Mga Dokumento')} · $kMunicipality · $kYear', style: sans(13.5, color: C.muted)),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: pill(statusLabel(muniStage(rec.status)), statusColors(muniStage(rec.status)).$1, statusColors(muniStage(rec.status)).$2),
          ),
        ],
      ),
      body: rec.tanods.isEmpty
          ? Center(
              child: Text(tr('This barangay has no tanods yet, so there are no documents.', 'Wala pang tanod ang barangay na ito.',
                  'Wala pa sang tanod ini nga barangay.'), textAlign: TextAlign.center, style: sans(16, color: C.muted)),
            )
          : LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth >= 620 ? 2 : 1;
              final w = (c.maxWidth.clamp(0, 1300) - 32 - 16 * (cols - 1)) / cols;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1300),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (loadingIds)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(tr('Loading ID photos…', 'Kinukuha ang litrato ng ID…', 'Ginakuha ang litrato sang ID…'),
                              style: sans(14, color: C.muted)),
                        ),
                      Wrap(spacing: 16, runSpacing: 16, children: [
                        for (final k in kBarangayDocs) SizedBox(width: w, child: _card(k)),
                      ]),
                    ]),
                  ),
                ),
              );
            }),
    );
  }

  Widget _card(DocKind k) {
    final f = rec.files[k]!;
    final signedKind = kBarangayDocs.contains(k);
    return Panel(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(k.icon, size: 20, color: C.navy),
          const SizedBox(width: 8),
          Expanded(child: Text(k.title, style: sans(16, w: FontWeight.w700, color: C.navy), overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: !signedKind
              ? pill(tr('Made by the system', 'Gawa ng sistema', 'Ginhimo sang sistema'), C.blueSoft, C.blue)
              : f.uploaded
                  ? pill(tr('Signed copy uploaded', 'May pirmadong kopya', 'May may pirma nga kopya'), C.greenSoft, C.green,
                      icon: Icons.check_circle_rounded)
                  : pill(tr('No signed copy yet', 'Wala pang pirmadong kopya', 'Wala pa sang may pirma nga kopya'), C.mist, C.muted),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => _preview(k),
          child: Container(
            height: 220,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: C.line), borderRadius: BorderRadius.circular(8)),
            child: loadingIds && k == DocKind.idSheet
                ? const Center(child: CircularProgressIndicator())
                : PdfPages(cacheKey: officialPdfKey(rec, k), build: () => buildOfficialPdf(rec, k), thumbnail: true),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: () => _preview(k),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: Text(tr('Preview', 'Tingnan', 'Tan-awa')),
          ),
          OutlinedButton.icon(
            onPressed: () => _download(k),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(tr('Download', 'I-download', 'I-download')),
          ),
          if (signedKind && f.uploaded)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: C.green, foregroundColor: Colors.white),
              onPressed: () => _signed(k),
              icon: const Icon(Icons.photo_camera_back_outlined, size: 18),
              label: Text(tr('Signed copy', 'Pirmadong kopya', 'May pirma nga kopya')),
            ),
        ]),
      ]),
    );
  }
}