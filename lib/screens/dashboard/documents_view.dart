import 'package:flutter/material.dart';

import 'package:tanod_incentives/theme.dart';
import 'package:tanod_incentives/data/demo_data.dart';
import 'package:tanod_incentives/data/doc_kind.dart';
import 'package:tanod_incentives/data/store.dart';
import 'package:tanod_incentives/widgets/app_field.dart';
import 'package:tanod_incentives/Templates/gawad_pdf.dart'; // MERGE: real PDFs
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:tanod_incentives/widgets/notify.dart'; // top pop-ups

export 'package:tanod_incentives/data/doc_kind.dart';

// Documents tab on the barangay side.
//   Blank templates: the layout with the barangay and year only.
//   Filled documents: the same layout filled from the tanod list, ready to
//   download and print for signing. After signing, the barangay uploads a
//   photo or scan of the signed paper; it replaces the file here and is the
//   backup copy the municipality and OPPDC can open.

String _group(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

String _no(int i) => (i + 1).toString().padLeft(3, '0');

// ================= Shared: viewing a document or its backup copy =================

DocumentPaper paperFor(BrgyRecord rec, DocKind k, {bool signed = false}) => DocumentPaper(
      kind: k,
      tanods: rec.tanods,
      barangay: rec.name,
      preparedBy: rec.rep,
      preparedRole: rec.position.isEmpty ? 'Barangay representative' : 'Barangay ${rec.position}',
      certifiedBy: rec.captain,
      signed: signed,
    );

// The page on a grey desk. scroll: false when it sits inside another scroll view.
Widget documentDesk(Widget paper, {bool scroll = true, bool photo = false}) {
  final page = LayoutBuilder(builder: (context, box) {
    final w = box.maxWidth < 720 ? box.maxWidth : 720.0;
    Widget sheet = Container(
      width: w,
      decoration: BoxDecoration(boxShadow: [
        BoxShadow(color: C.navy.withValues(alpha: .18), blurRadius: 20, offset: const Offset(0, 6)),
      ]),
      child: FittedBox(
        fit: BoxFit.fitWidth,
        alignment: Alignment.topCenter,
        child: SizedBox(width: 720, child: paper),
      ),
    );
    if (photo) {
      // A photo of paper: slightly warm and a little tilted.
      sheet = Transform.rotate(
        angle: -0.006,
        child: ColorFiltered(
          colorFilter: const ColorFilter.mode(Color(0x1AB08A50), BlendMode.multiply),
          child: sheet,
        ),
      );
    }
    return Center(child: sheet);
  });
  return Container(
    color: photo ? const Color(0xFF4A5562) : const Color(0xFFE9EEF4),
    child: scroll
        ? SingleChildScrollView(padding: const EdgeInsets.all(20), child: page)
        : Padding(padding: const EdgeInsets.all(16), child: page),
  );
}

String signedFileName(BrgyRecord rec, DocKind k) {
  final f = rec.files[k]!;
  return '${k.title} - Brgy ${rec.name} - $kYear - signed v${f.version}.${f.bytes != null && !f.isPdf ? 'jpg' : 'pdf'}';
}

/// The uploaded signed copy itself (photo or chosen file), or null when there
/// is only demo data. Used by the backup viewer and the card thumbnails.
Widget? uploadedCopyView(DocFile f, {bool thumbnail = false}) {
  final bytes = f.bytes;
  if (bytes == null) return null;
  if (!f.isPdf) {
    return thumbnail
        ? Image.memory(bytes, fit: BoxFit.cover, width: 720)
        : InteractiveViewer(maxScale: 5, child: Center(child: Image.memory(bytes)));
  }
  if (thumbnail) {
    return Container(
      width: 720,
      height: 480,
      color: Colors.white,
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.picture_as_pdf_rounded, size: 140, color: C.red),
        const SizedBox(height: 12),
        Text(f.fileName ?? 'PDF', style: sans(34, w: FontWeight.w700, color: C.navy)),
      ]),
    );
  }
  return PdfPreview(
    build: (_) => bytes,
    useActions: false,
    canChangePageFormat: false,
    canChangeOrientation: false,
    canDebug: false,
  );
}

/// Download / share the uploaded signed copy. Pictures are wrapped in a
/// one-page PDF so they can be saved and printed the same way.
Future<void> shareSignedCopy(BuildContext context, BrgyRecord rec, DocKind k) async {
  final f = rec.files[k]!;
  final bytes = f.bytes;
  if (bytes == null) {
    notify(context, tr('This is demo data. Upload a real copy first.', 'Demo data ito. Mag-upload muna ng totoong kopya.',
        'Demo data ini. Palihog mag-upload anay sang matuod nga kopya.'), type: NotifyType.warning);
    return;
  }
  var pdfBytes = bytes;
  if (!f.isPdf) {
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(20),
      build: (_) => pw.Center(child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain)),
    ));
    pdfBytes = await doc.save();
  }
  final name = signedFileName(rec, k).replaceAll(RegExp(r'\.jpg$'), '.pdf');
  await Printing.sharePdf(bytes: pdfBytes, filename: name);
}

// Opens a document's backup copy (the uploaded signed paper). When nothing is
// uploaded yet, shows the ready-to-print version instead.
Future<void> showBackupCopy(
  BuildContext context, {
  required BrgyRecord rec,
  required DocKind kind,
  List<Widget> Function(BuildContext dialogContext)? actions,
}) {
  final f = rec.files[kind]!;
  return showDialog(
    context: context,
    builder: (ctx) {
      final size = MediaQuery.of(ctx).size;
      final status = !f.uploaded
          ? tr('No signed copy uploaded yet. Showing the ready-to-print version.',
              'Wala pang na-upload na pirmadong kopya. Ipinapakita ang bersyong handang i-print.',
              'Wala pa sang na-upload nga may pirma nga kopya. Ginapakita ang bersyon nga handa na i-print.')
          : f.correction
              ? tr('A corrected copy was asked for. This is the copy that needs fixing.',
                  'May hiniling na naitamang kopya. Ito ang kopyang kailangang itama.',
                  'May ginpangayo nga natadlong nga kopya. Amo ini ang kopya nga kinahanglan tadlungon.')
              : f.outdated
                  ? tr('The tanod list changed after this was signed. A new signed copy is needed.',
                      'Nagbago ang listahan ng tanod matapos itong pirmahan. Kailangan ng bagong pirmadong kopya.',
                      'Nagbag-o ang listahan sang tanod pagkatapos ini napirmahan. Kinahanglan sang bag-o nga may pirma nga kopya.')
                  : tr('Backup of the signed paper · uploaded ${f.uploadedOn}${f.version > 1 ? ' · version ${f.version}' : ''}',
                      'Backup ng pirmadong papel · na-upload ${f.uploadedOn}${f.version > 1 ? ' · bersyon ${f.version}' : ''}',
                      'Backup sang may pirma nga papel · na-upload ${f.uploadedOn}${f.version > 1 ? ' · bersyon ${f.version}' : ''}');
      final (bg, fg) = !f.uploaded
          ? (C.blueSoft, const Color(0xFF1B3F68))
          : (f.correction
              ? (const Color(0xFFFDF0EE), C.red)
              : (f.outdated ? (const Color(0xFFFFF8E1), const Color(0xFF5C4400)) : (C.greenSoft, const Color(0xFF14583D))));
      final buttons = actions?.call(ctx) ?? const <Widget>[];

      return Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 880, maxHeight: size.height * .92),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 10, 10),
              child: Row(children: [
                Icon(kind.icon, color: C.navy),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${kind.title} · Brgy. ${rec.name}',
                      overflow: TextOverflow.ellipsis, style: sans(17, w: FontWeight.w700, color: C.navy)),
                ),
                IconButton(
                  tooltip: tr('Close', 'Isara', 'Sirhan'),
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close_rounded, color: C.muted),
                ),
              ]),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Icon(f.uploaded ? Icons.photo_camera_back_outlined : Icons.picture_as_pdf_outlined, size: 18, color: fg),
                const SizedBox(width: 8),
                Expanded(child: Text(status, style: sans(14, color: fg, h: 1.4))),
              ]),
            ),
            const Divider(height: 1, color: C.line),
            Flexible(
              child: f.bytes != null
                  ? SizedBox(height: size.height * .62, child: uploadedCopyView(f)!) // the real upload
                  : documentDesk(paperFor(rec, kind, signed: f.uploaded), photo: f.uploaded),
            ),
            if (buttons.isNotEmpty) ...[
              const Divider(height: 1, color: C.line),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Wrap(alignment: WrapAlignment.end, spacing: 10, runSpacing: 10, children: buttons),
              ),
            ],
          ]),
        ),
      );
    },
  );
}

// ================= Barangay: Documents view =================

class DocumentsView extends StatefulWidget {
  final BrgyRecord rec;
  final bool locked; // the set is with the municipality / OPPDC
  final int issueCount;
  final void Function(String message) onToast;
  final VoidCallback onChanged; // the tanod list or signatories changed
  final void Function(DocKind kind) onUpload;
  final VoidCallback onOpenMessages;

  const DocumentsView({
    super.key,
    required this.rec,
    required this.locked,
    required this.issueCount,
    required this.onToast,
    required this.onChanged,
    required this.onUpload,
    required this.onOpenMessages,
  });

  @override
  State<DocumentsView> createState() => _DocumentsViewState();
}

class _DocumentsViewState extends State<DocumentsView> {
  bool filledTab = true;
  late final _prep = TextEditingController(text: widget.rec.rep);
  late final _cert = TextEditingController(text: widget.rec.captain);

  BrgyRecord get rec => widget.rec;
  List<Tanod> get tanods => rec.tanods;

  @override
  void dispose() {
    _prep.dispose();
    _cert.dispose();
    super.dispose();
  }

  String _pdfName(DocKind k, bool filled) =>
      '${k.title} - ${filled ? 'Brgy ${rec.name}' : 'Blank template'} - $kYear.pdf';

  void _saved(String name) => widget.onToast(tr('Saved “$name” (demo: real files come with the backend).',
      'Na-save ang “$name” (demo: darating ang totoong file kasama ng backend).', 'Na-save ang “$name” (demo: maabot ang matuod nga file upod sang backend).'));

  DocumentPaper _paper(DocKind k, bool filled) => DocumentPaper(
        kind: k,
        tanods: filled ? tanods : null,
        barangay: rec.name,
        preparedBy: _prep.text,
        certifiedBy: _cert.text,
      );

  // ---------- downloads ----------
  void _download(DocKind k, bool filled) {
    final f = rec.files[k]!;
    if (!filled) {
      _saved(_pdfName(k, filled)); // blank templates: still demo
      return;
    }
    if (!f.uploaded) {
      showOfficialPdf(context, rec, k); // MERGE
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(tr('Download ${k.title}', 'I-download ang ${k.title}', 'I-download ang ${k.title}'), style: serif(22)),
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined, color: C.blue),
              title: Text(tr('Ready-to-print PDF', 'PDF na handang i-print', 'PDF nga handa na i-print'), style: sans(16, w: FontWeight.w600)),
              subtitle: Text(tr('No signatures. Print this for signing.', 'Walang pirma. Ito ang ipi-print para pirmahan.', 'Wala sang pirma. Amo ini ang i-print para pirmahan.'),
                  style: sans(14, color: C.muted)),
              onTap: () {
                Navigator.pop(ctx);
                showOfficialPdf(context, rec, k); // MERGE
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_back_outlined, color: C.green),
              title: Text(tr('Signed copy (backup)', 'Pirmadong kopya (backup)', 'May pirma nga kopya (backup)'), style: sans(16, w: FontWeight.w600)),
              subtitle: Text(tr('The photo or scan you uploaded on ${f.uploadedOn}.', 'Ang litrato o scan na na-upload noong ${f.uploadedOn}.', 'Ang litrato ukon scan nga gin-upload ninyo sang ${f.uploadedOn}.'),
                  style: sans(14, color: C.muted)),
              onTap: () {
                Navigator.pop(ctx);
                shareSignedCopy(context, rec, k);
              },
            ),
          ]),
        ),
      ),
    );
  }

  void _viewBackup(DocKind k) {
    final f = rec.files[k]!;
    showBackupCopy(
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
        if (!widget.locked || f.correction)
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: C.navy, foregroundColor: Colors.white, minimumSize: const Size(0, 46)),
            onPressed: () {
              Navigator.pop(ctx);
              widget.onUpload(k);
            },
            icon: const Icon(Icons.upload_rounded, size: 18),
            label: Text(f.correction
                ? tr('Upload corrected copy', 'I-upload ang naitamang kopya', 'I-upload ang natadlong nga kopya')
                : tr('Replace with a new photo', 'Palitan ng bagong litrato', 'Ilisan sang bag-o nga litrato')),
          ),
      ],
    );
  }

  // ---------- blank template preview ----------
  void _preview(DocKind k) {
    showDialog(
      context: context,
      builder: (ctx) => _shell(ctx, 860, [
        _dialogHeader(ctx, k, k.title, tr('Blank template · tanod rows left empty', 'Blangkong template · walang laman ang hanay ng tanod', 'Blangko nga template · wala sulod ang mga linya sang tanod'), false),
        const Divider(height: 1, color: C.line),
        Flexible(child: documentDesk(_paper(k, false))),
      ]),
    );
  }

  Widget _dialogHeader(BuildContext ctx, DocKind k, String title, String sub, bool filled) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 10, 14),
        child: Row(children: [
          Icon(k.icon, color: C.navy),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, overflow: TextOverflow.ellipsis, style: sans(17, w: FontWeight.w700, color: C.navy)),
              Text(sub, overflow: TextOverflow.ellipsis, style: sans(14, color: C.muted)),
            ]),
          ),
          IconButton(
            tooltip: tr('Download', 'I-download', 'I-download'),
            onPressed: () => filled ? showOfficialPdf(context, rec, k) : _saved(_pdfName(k, filled)),
            icon: const Icon(Icons.download_rounded, color: C.navy),
          ),
          IconButton(
            tooltip: tr('Close', 'Isara', 'Sirhan'),
            onPressed: () => Navigator.pop(ctx),
            icon: const Icon(Icons.close_rounded, color: C.muted),
          ),
        ]),
      );

  Dialog _shell(BuildContext ctx, double maxWidth, List<Widget> children) {
    final size = MediaQuery.of(ctx).size;
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: size.height * .92),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  // ---------- edit (filled documents) ----------
  void _edit(DocKind k) {
    if (widget.locked) {
      showDialog(
        context: context,
        builder: (ctx) => _shell(ctx, 860, [
          _dialogHeader(ctx, k, k.title, tr('Your set is being checked, so editing is locked.', 'Sinusuri ang inyong set kaya naka-lock ang pag-edit.', 'Ginausisa pa ang inyo set, gani naka-lock anay ang pag-edit.'), true),
          const Divider(height: 1, color: C.line),
          Flexible(child: documentDesk(_paper(k, true))),
        ]),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        void changed() {
          setD(() {});
          setState(() {});
          widget.onChanged();
        }

        final wide = MediaQuery.of(ctx).size.width >= 900;
        final editor = _editorPanel(ctx, changed);
        return _shell(ctx, 1200, [
          _dialogHeader(ctx, k, tr('Edit ${k.title}', 'Baguhin ang ${k.title}', 'I-edit ang ${k.title}'),
              tr('Changes update all four documents', 'Maa-update ang apat na dokumento', 'Ma-update ang apat ka dokumento'), true),
          const Divider(height: 1, color: C.line),
          Flexible(
            child: wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SizedBox(
                      width: 370,
                      child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: editor),
                    ),
                    const VerticalDivider(width: 1, color: C.line),
                    Expanded(child: documentDesk(_paper(k, true))),
                  ])
                : SingleChildScrollView(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Padding(padding: const EdgeInsets.all(18), child: editor),
                      documentDesk(_paper(k, true), scroll: false),
                    ]),
                  ),
          ),
        ]);
      }),
    );
  }

  Widget _editorTitle(String text) =>
      Text(text.toUpperCase(), style: sans(13, w: FontWeight.w700, color: C.muted).copyWith(letterSpacing: .7));

  Widget _signatoryField(String label, TextEditingController c, VoidCallback changed) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: sans(15, w: FontWeight.w600, color: C.navy)),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          style: sans(15),
          cursorColor: C.blue,
          onChanged: (_) {
            rec.rep = _prep.text;
            rec.captain = _cert.text;
            changed();
          },
          decoration: fieldDecoration(tr('Full name', 'Buong pangalan', 'Bilog nga ngalan'), Icons.draw_outlined),
        ),
      ]);

  Widget _editorPanel(BuildContext ctx, VoidCallback changed) {
    final anySigned = rec.files.values.any((f) => f.uploaded);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: C.blueSoft, borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, size: 18, color: C.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                tr('Edits here also change your Tanods list and all four documents. It’s the same list, so you only fix things once.',
                    'Ang binago rito ay magbabago rin sa listahan ng Tanod at sa apat na dokumento. Iisang listahan ito, kaya isang beses lang mag-aayos.', 'Ang ginbag-o diri magabag-o man sa inyo listahan sang Tanod kag sa apat ka dokumento. Isa lang ini ka listahan, gani makaisa lang kamo magtadlong.'),
                style: sans(14.5, color: const Color(0xFF1B3F68), h: 1.45)),
          ),
        ]),
      ),
      if (anySigned) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(12)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.warning_amber_rounded, size: 18, color: C.yellowDark),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  tr('Some documents already have signed copies. If you change anything, print the new version, have it signed, and upload it again.',
                      'May pirmadong kopya na ang ilang dokumento. Kapag may binago, i-print ang bagong bersyon, papirmahan, at i-upload ulit.', 'May pirma na nga kopya ang pila ka dokumento. Kon may bag-uhon kamo, palihog i-print ang bag-o nga bersyon, papirmahi, kag i-upload liwat.'),
                  style: sans(14.5, color: const Color(0xFF5C4400), h: 1.45)),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 20),
      _editorTitle(tr('Signatories · $kYear', 'Mga pipirma · $kYear', 'Mga pipirma · $kYear')),
      const SizedBox(height: 10),
      _signatoryField(tr('Prepared by (Barangay ${rec.position})', 'Inihanda ni (Barangay ${rec.position})', 'Ginhanda ni (Barangay ${rec.position})'), _prep, changed),
      const SizedBox(height: 12),
      _signatoryField(tr('Certified correct (Punong Barangay)', 'Pinatunayan ni (Punong Barangay)', 'Ginpamatud-an ni (Punong Barangay)'), _cert, changed),
      const SizedBox(height: 22),
      Row(children: [
        Expanded(child: _editorTitle(tr('Tanods (${tanods.length} of ${rec.quota})', 'Mga tanod (${tanods.length} sa ${rec.quota})', 'Mga tanod (${tanods.length} sa ${rec.quota})'))),
        Text(tr('Tap to edit', 'Pindutin para baguhin', 'Pinduta para i-edit'), style: sans(13.5, color: C.muted)),
      ]),
      const SizedBox(height: 8),
      for (var i = 0; i < tanods.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: tanods[i].confirmed ? Colors.white : const Color(0xFFFFF8E1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: tanods[i].confirmed ? C.line : const Color(0xFFF3DE9A)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _editTanod(ctx, i, changed),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(children: [
                  SizedBox(width: 38, child: Text(_no(i), style: sans(14.5, w: FontWeight.w700, color: C.navy))),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tanods[i].fullName, overflow: TextOverflow.ellipsis, style: sans(15, w: FontWeight.w600)),
                      Text(tanods[i].confirmed ? tanods[i].idType : '${tanods[i].idType} · ${tr('check spelling', 'suriin ang baybay', 'usisaa ang spelling')}',
                          overflow: TextOverflow.ellipsis,
                          style: sans(13.5, color: tanods[i].confirmed ? C.muted : const Color(0xFF7A5B00))),
                    ]),
                  ),
                  const Icon(Icons.edit_outlined, size: 18, color: C.muted),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  Future<void> _editTanod(BuildContext ctx, int i, VoidCallback changed) async {
    final t = tanods[i];
    final first = TextEditingController(text: t.first);
    final middle = TextEditingController(text: t.middle);
    final last = TextEditingController(text: t.last);
    final formKey = GlobalKey<FormState>();
    var idType = kIdTypes.contains(t.idType) ? t.idType : kIdTypes.first;

    final action = await showDialog<String>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Award no. ${_no(i)}', style: serif(22)),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (!t.confirmed) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(10)),
                    child: Text(
                        tr('Compare with the original ID. Saving marks this name as checked.',
                            'Ikumpara sa orihinal na ID. Kapag na-save, itatalang nasuri na ang pangalan.', 'Ikumpara sa orihinal nga ID. Kon i-save, markahan ini nga ngalan nga nausisa na.'),
                        style: sans(14.5, color: const Color(0xFF5C4400), h: 1.4)),
                  ),
                  const SizedBox(height: 14),
                ],
                AppField(
                  label: tr('First name', 'Pangalan', 'Ngalan'),
                  icon: Icons.person_outline,
                  controller: first,
                  validator: (v) => (v ?? '').trim().isEmpty ? tr('Enter the first name.', 'Ilagay ang pangalan.', 'Isulat ang ngalan.') : null,
                ),
                const SizedBox(height: 12),
                AppField(
                  label: tr('Middle initial', 'Gitnang inisyal', 'Inisyal sang tunga nga ngalan'),
                  icon: Icons.short_text,
                  controller: middle,
                  maxLength: 1,
                  required: false,
                  optional: true,
                ),
                const SizedBox(height: 12),
                AppField(
                  label: tr('Last name', 'Apelyido', 'Apelyido'),
                  icon: Icons.person_outline,
                  controller: last,
                  validator: (v) => (v ?? '').trim().isEmpty ? tr('Enter the last name.', 'Ilagay ang apelyido.', 'Isulat ang apelyido.') : null,
                ),
                const SizedBox(height: 12),
                FieldLabel(tr('ID type', 'Uri ng ID', 'Klase sang ID')),
                DropdownButtonFormField<String>(
                  initialValue: idType,
                  isExpanded: true,
                  style: sans(15),
                  dropdownColor: Colors.white,
                  decoration: fieldDecoration('', Icons.badge_outlined),
                  items: kIdTypes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => idType = v ?? idType,
                ),
              ]),
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 20, 18),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(dctx, 'remove'),
            icon: const Icon(Icons.delete_outline, size: 18, color: C.red),
            label: Text(tr('Remove', 'Tanggalin', 'Kuhaon'), style: sans(14.5, w: FontWeight.w600, color: C.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: Text(tr('Cancel', 'Kanselahin', 'Kanselaha'), style: sans(14.5, w: FontWeight.w600, color: C.muted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: C.navy, foregroundColor: Colors.white),
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(dctx, 'save');
            },
            child: Text(tr('Save', 'I-save', 'I-save')),
          ),
        ],
      ),
    );

    if (action == 'save') {
      t
        ..first = first.text.trim()
        ..middle = middle.text.trim().toUpperCase()
        ..last = last.text.trim()
        ..idType = idType
        ..confirmed = true;
      changed();
    } else if (action == 'remove') {
      final name = t.fullName;
      tanods.removeAt(i);
      changed();
      widget.onToast(tr('Removed $name. Award numbers were renumbered.', 'Tinanggal si $name. Inayos ang mga award number.', 'Ginkuha na si $name. Na-ilis na ang mga award number.'));
    }

    Future.delayed(const Duration(milliseconds: 400), () {
      first.dispose();
      middle.dispose();
      last.dispose();
    });
  }

  // ---------- layout ----------
  @override
  Widget build(BuildContext context) {
    final unconfirmed = tanods.where((x) => !x.confirmed).length;
    final fixes = rec.toFix;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _tabs(),
      const SizedBox(height: 16),
      if (!filledTab)
        _banner(
          C.blueSoft,
          C.blue,
          const Color(0xFF1B3F68),
          Icons.description_outlined,
          tr('Empty forms to fill in by hand. The barangay and year are already printed; the tanod rows are blank.',
              'Blangkong form na pupunan nang mano-mano. Nakalimbag na ang barangay at taon; blangko ang mga hanay ng tanod.', 'Blangko nga form nga pun-an sa kamot. Naka-imprinta na ang barangay kag tuig; blangko ang mga linya sang tanod.'),
        )
      else ...[
        _banner(
          C.greenSoft,
          C.green,
          const Color(0xFF14583D),
          Icons.assignment_turned_in_outlined,
          tr('Filled in with your ${tanods.length} tanods. Download and print each one for signing, then upload a photo or scan '
                  'of the signed paper. The upload replaces the file here and becomes your backup copy.',
              'May laman na ng inyong ${tanods.length} tanod. I-download at i-print ang bawat isa para pirmahan, saka i-upload ang '
                  'litrato o scan ng pirmadong papel. Papalitan nito ang file dito at magiging backup ninyo.', 'Napun-an na sang inyo ${tanods.length} ka tanod. Palihog i-download kag i-print ang kada isa para pirmahan, dayon i-upload ang litrato ukon scan ' 'sang may pirma nga papel. Ilisan sang upload ang file diri kag mangin backup ninyo.'),
        ),
        if (fixes.isNotEmpty) ...[
          const SizedBox(height: 10),
          _banner(
            const Color(0xFFFDF0EE),
            C.red,
            const Color(0xFF8E2A22),
            Icons.assignment_return_outlined,
            tr('$kMunicipality asked for corrections on: ${fixes.map((f) => f.kind.title).join(', ')}. '
                    'Fix the paper copy, then upload the corrected copy so the backup matches.',
                'Humiling ang $kMunicipality ng pagtatama sa: ${fixes.map((f) => f.kind.title).join(', ')}. '
                    'Itama ang papel, saka i-upload ang naitamang kopya para tugma ang backup.', 'Nagpangayo ang $kMunicipality sang pagtadlong sa: ${fixes.map((f) => f.kind.title).join(', ')}. ' 'Palihog tadlunga ang papel, dayon i-upload ang natadlong nga kopya para pareho ang backup.'),
            action: TextButton(
              onPressed: widget.onOpenMessages,
              child: Text(tr('Open messages', 'Buksan ang mensahe', 'Buksan ang mensahe'), style: sans(14.5, w: FontWeight.w700, color: C.red)),
            ),
          ),
        ],
        if (widget.issueCount > 0 || unconfirmed > 0) ...[
          const SizedBox(height: 10),
          _banner(
            const Color(0xFFFFF8E1),
            C.yellowDark,
            const Color(0xFF5C4400),
            Icons.error_outline,
            tr('${widget.issueCount} thing${widget.issueCount == 1 ? '' : 's'} still to check. Rows in yellow need a second look before you print.',
                '${widget.issueCount} pa ang susuriin. Tingnan muli ang mga hanay na dilaw bago mag-print.', '${widget.issueCount} pa ang usisaon. Palihog tan-awa liwat ang mga linya nga dalag antes mag-print.'),
          ),
        ],
      ],
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth >= 900 ? 4 : (box.maxWidth >= 520 ? 2 : 1);
        final cw = ((box.maxWidth - 16 * (cols - 1)) / cols).floorToDouble();
        return Wrap(spacing: 16, runSpacing: 16, children: [
          for (final k in DocKind.values) SizedBox(width: cw, child: filledTab ? _filledCard(k) : _blankCard(k)),
        ]);
      }),
    ]);
  }

  Widget _tabs() {
    Widget tab(String label, IconData icon, bool on, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: on ? C.navy : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 18, color: on ? C.yellow : C.muted),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: sans(15, w: FontWeight.w600, color: on ? Colors.white : C.muted)),
                ),
              ]),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.line),
      ),
      child: Row(children: [
        tab(tr('Filled documents', 'May lamang dokumento', 'Napun-an nga dokumento'), Icons.assignment_turned_in_outlined, filledTab,
            () => setState(() => filledTab = true)),
        const SizedBox(width: 6),
        tab(tr('Blank templates', 'Blangkong template', 'Blangko nga template'), Icons.description_outlined, !filledTab,
            () => setState(() => filledTab = false)),
      ]),
    );
  }

  Widget _banner(Color bg, Color iconColor, Color textColor, IconData icon, String text, {Widget? action}) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 19, color: iconColor)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: sans(14.5, color: textColor, h: 1.45))),
          if (action != null) action,
        ]),
      );

  // Paper thumbnail at the top of each card.
  Widget _thumb({required Widget paper, required String badge, required Color badgeColor, required VoidCallback onTap, bool photo = false}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 190,
        color: photo ? const Color(0xFF4A5562) : const Color(0xFFE9EEF4),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
        child: Stack(children: [
          Positioned.fill(
            child: Transform.rotate(
              angle: photo ? -0.012 : 0.0,
              child: Container(
                decoration: BoxDecoration(boxShadow: [
                  BoxShadow(color: C.navy.withValues(alpha: .15), blurRadius: 10, offset: const Offset(0, 3)),
                ]),
                child: ClipRect(
                  child: IgnorePointer(
                    child: FittedBox(
                      fit: BoxFit.fitWidth,
                      alignment: Alignment.topCenter,
                      child: SizedBox(width: 720, child: paper),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(99)),
              child: Text(badge, style: sans(11.5, w: FontWeight.w800, color: Colors.white).copyWith(letterSpacing: .6)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _cardShell(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE1E9F2)),
          boxShadow: [
            BoxShadow(color: C.navy.withValues(alpha: .06), blurRadius: 24, spreadRadius: -8, offset: const Offset(0, 10)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      );

  Widget _titleRow(DocKind k) => Row(children: [
        Icon(k.icon, size: 19, color: C.navy),
        const SizedBox(width: 8),
        Expanded(child: Text(k.title, overflow: TextOverflow.ellipsis, style: sans(16, w: FontWeight.w700, color: C.navy))),
      ]);

  ButtonStyle get _outlined => OutlinedButton.styleFrom(
        foregroundColor: C.navy,
        side: const BorderSide(color: C.line, width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 12),
        minimumSize: const Size(0, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );

  Widget _blankCard(DocKind k) => _cardShell([
        _thumb(paper: _paper(k, false), badge: 'BLANK', badgeColor: C.navy, onTap: () => _preview(k)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _titleRow(k),
            const SizedBox(height: 4),
            Text(k.blurb, maxLines: 2, overflow: TextOverflow.ellipsis, style: sans(14, color: C.muted, h: 1.4)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: _outlined,
                  onPressed: () => _preview(k),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: Text(tr('Preview', 'Tingnan', 'Tan-awa'), style: sans(15, w: FontWeight.w600, color: C.navy)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: C.navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _download(k, false),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(tr('Download', 'I-download', 'I-download'), style: sans(15, w: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ]),
          ]),
        ),
      ]);

  Widget _filledCard(DocKind k) {
    final f = rec.files[k]!;
    final remark = rec.lastAbout(k);

    // Status line under the title.
    final (IconData sIcon, Color sBg, Color sFg, String sText) = f.correction
        ? (
            Icons.assignment_return_outlined,
            const Color(0xFFFDF0EE),
            C.red,
            tr('$kMunicipality asked for a corrected copy${remark == null ? '.' : ': “${remark.text}”'}',
                'Humiling ang $kMunicipality ng naitamang kopya${remark == null ? '.' : ': “${remark.text}”'}', 'Nagpangayo ang $kMunicipality sang natadlong nga kopya${remark == null ? '.' : ': “${remark.text}”'}'),
          )
        : f.outdated
            ? (
                Icons.warning_amber_rounded,
                const Color(0xFFFFF8E1),
                const Color(0xFF5C4400),
                tr('Changed after signing. Print the new version, have it signed, and upload it again.',
                    'Nabago matapos pirmahan. I-print ang bagong bersyon, papirmahan, at i-upload ulit.', 'Nabag-o pagkatapos mapirmahan. Palihog i-print ang bag-o nga bersyon, papirmahi, kag i-upload liwat.'),
              )
            : f.uploaded
                ? (
                    Icons.cloud_done_outlined,
                    C.greenSoft,
                    const Color(0xFF14583D),
                    tr('Signed copy uploaded ${f.uploadedOn}${f.version > 1 ? ' (version ${f.version})' : ''}. This is your backup.',
                        'Na-upload ang pirmadong kopya ${f.uploadedOn}${f.version > 1 ? ' (bersyon ${f.version})' : ''}. Ito ang inyong backup.', 'Na-upload ang may pirma nga kopya ${f.uploadedOn}${f.version > 1 ? ' (bersyon ${f.version})' : ''}. Amo ini ang inyo backup.'),
                  )
                : (
                    Icons.print_outlined,
                    C.blueSoft,
                    const Color(0xFF1B3F68),
                    tr('Ready to download and print for signing.', 'Handa nang i-download at i-print para pirmahan.', 'Handa na i-download kag i-print para pirmahan.'),
                  );

    final canUpload = !widget.locked || f.correction;
    final String upLabel;
    final IconData upIcon;
    final bool upPrimary;
    if (f.correction) {
      upLabel = tr('Upload corrected copy', 'I-upload ang naitamang kopya', 'I-upload ang natadlong nga kopya');
      upIcon = Icons.upload_rounded;
      upPrimary = true;
    } else if (f.outdated) {
      upLabel = tr('Upload new signed copy', 'I-upload ang bagong pirmadong kopya', 'I-upload ang bag-o nga may pirma nga kopya');
      upIcon = Icons.upload_rounded;
      upPrimary = true;
    } else if (f.uploaded) {
      upLabel = tr('Replace signed copy', 'Palitan ang pirmadong kopya', 'Ilisan ang may pirma nga kopya');
      upIcon = Icons.sync_rounded;
      upPrimary = false;
    } else {
      upLabel = tr('Upload / take photo of signed copy', 'I-upload / kunan ng litrato ang pirmadong kopya', 'I-upload / kuhai sang litrato ang may pirma nga kopya');
      upIcon = Icons.photo_camera_outlined;
      upPrimary = true;
    }

    return _cardShell([
      _thumb(
        paper: f.uploaded ? (uploadedCopyView(f, thumbnail: true) ?? paperFor(rec, k, signed: true)) : _paper(k, true),
        badge: f.uploaded ? (f.outdated ? 'OLD SIGNED COPY' : 'SIGNED COPY') : 'READY TO PRINT',
        badgeColor: f.uploaded ? (f.outdated ? C.yellowDark : C.green) : C.blue,
        photo: f.uploaded && f.bytes == null, // real uploads are shown as they are
        onTap: () => f.uploaded ? _viewBackup(k) : _edit(k),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _titleRow(k),
          const SizedBox(height: 4),
          Text(
            k == DocKind.certification
                ? tr('${tanods.length} tanods certified · signatories set', '${tanods.length} tanod · may pipirma na', '${tanods.length} ka tanod · may pipirma na')
                : tr('${tanods.length} names · award nos. 001–${_no(tanods.isEmpty ? 0 : tanods.length - 1)}',
                    '${tanods.length} pangalan · award no. 001–${_no(tanods.isEmpty ? 0 : tanods.length - 1)}', '${tanods.length} ka ngalan · award no. 001–${_no(tanods.isEmpty ? 0 : tanods.length - 1)}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sans(14, color: C.muted),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: sBg, borderRadius: BorderRadius.circular(10)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 1), child: Icon(sIcon, size: 17, color: sFg)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(sText, maxLines: 4, overflow: TextOverflow.ellipsis, style: sans(13.5, color: sFg, h: 1.4)),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: _outlined,
                onPressed: () => _edit(k),
                icon: Icon(widget.locked ? Icons.visibility_outlined : Icons.edit_outlined, size: 18),
                label: Text(widget.locked ? tr('View', 'Tingnan', 'Tan-awa') : tr('Edit', 'Baguhin', 'I-edit'),
                    style: sans(15, w: FontWeight.w600, color: C.navy)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: _outlined,
                onPressed: () => _download(k, true),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text(tr('Download', 'I-download', 'I-download'), style: sans(15, w: FontWeight.w600, color: C.navy)),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          upPrimary
              ? FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: f.correction || f.outdated ? C.yellow : C.navy,
                    foregroundColor: f.correction || f.outdated ? C.navy : Colors.white,
                    disabledBackgroundColor: const Color(0xFFE3EAF2),
                    disabledForegroundColor: const Color(0xFF97A5B5),
                    padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    textStyle: sans(14.5, w: FontWeight.w700),
                  ),
                  onPressed: canUpload ? () => widget.onUpload(k) : null,
                  icon: Icon(upIcon, size: 19),
                  label: Text(upLabel, textAlign: TextAlign.center),
                )
              : TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: C.blue, minimumSize: const Size(0, 46)),
                  onPressed: canUpload ? () => widget.onUpload(k) : null,
                  icon: Icon(upIcon, size: 18),
                  label: Text(upLabel, style: sans(14.5, w: FontWeight.w600, color: canUpload ? C.blue : C.muted)),
                ),
        ]),
      ),
    ]);
  }
}

// ================= The printed page =================
// tanods == null → blank template. Otherwise filled with every tanod.
// signed: true draws handwritten signatures, for the photo of the signed paper.

class DocumentPaper extends StatelessWidget {
  final DocKind kind;
  final List<Tanod>? tanods;
  final String? preparedBy, certifiedBy;
  final String barangay; // whose documents these are (the municipality views many)
  final String preparedRole;
  final bool signed;

  const DocumentPaper({
    super.key,
    required this.kind,
    this.tanods,
    this.preparedBy,
    this.certifiedBy,
    this.barangay = kBarangay,
    this.preparedRole = 'Barangay $kRepPosition',
    this.signed = false,
  });

  bool get filled => tanods != null;
  bool get _sign => signed && filled;

  static const _ink = Color(0xFF111111);
  static const _grey = Color(0xFF555555);
  static const _flag = Color(0xFFFFF1B8);

  TextStyle _t(double size, {FontWeight w = FontWeight.w400, Color color = _ink, bool serifFont = false}) => TextStyle(
        fontFamily: serifFont ? 'serif' : null,
        fontFamilyFallback: serifFont ? const ['Georgia', 'Times New Roman'] : null,
        fontSize: size,
        fontWeight: w,
        color: color,
        height: 1.35,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(48, 40, 48, 44),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _letterhead(),
        const SizedBox(height: 18),
        _title(),
        const SizedBox(height: 18),
        _body(),
        const SizedBox(height: 34),
        _signatories(),
      ]),
    );
  }

  Widget _letterhead() => Column(children: [
        Text('Republic of the Philippines', style: _t(11, color: _grey)),
        Text('Province of Iloilo', style: _t(11, color: _grey)),
        Text('Municipality of $kMunicipality', style: _t(11, color: _grey)),
        const SizedBox(height: 4),
        Text('BARANGAY ${barangay.toUpperCase()}', style: _t(14, w: FontWeight.w700, serifFont: true)),
        const SizedBox(height: 10),
        Container(height: 2, color: _ink),
        const SizedBox(height: 2),
        Container(height: .8, color: _ink),
      ]);

  Widget _title() {
    final (title, sub) = switch (kind) {
      DocKind.payroll => ('PAYROLL', 'Financial assistance for barangay tanods · Calendar year $kYear'),
      DocKind.masterlist => ('MASTERLIST OF BARANGAY TANODS', 'Calendar year $kYear'),
      DocKind.certification => ('CERTIFICATION', 'Barangay tanods who served in $kYear'),
      DocKind.idSheet => ('PHOTOCOPIES OF IDENTIFICATION CARDS', 'Each copy signed three (3) times by the tanod'),
    };
    return Column(children: [
      Text(title, textAlign: TextAlign.center, style: _t(17, w: FontWeight.w700, serifFont: true).copyWith(letterSpacing: 1)),
      const SizedBox(height: 3),
      Text(sub, textAlign: TextAlign.center, style: _t(11.5, color: _grey)),
      if (kind == DocKind.payroll || kind == DocKind.masterlist)
        Text('Provincial Ordinance No. 2020-240, Sec. 7(C)', textAlign: TextAlign.center, style: _t(10.5, color: _grey)),
    ]);
  }

  Widget _body() => switch (kind) {
        DocKind.payroll => _payroll(),
        DocKind.masterlist => _masterlist(),
        DocKind.certification => _certification(),
        DocKind.idSheet => _idSheet(),
      };

  // ---------- tables ----------
  Widget _cell(String text, {bool bold = false, TextAlign align = TextAlign.left, bool header = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        child: Text(
          text,
          textAlign: align,
          style: _t(header ? 10.5 : 11.5, w: bold || header ? FontWeight.w700 : FontWeight.w400),
        ),
      );

  Widget _table({
    required List<String> headers,
    required List<double> flex,
    required List<List<String>> rows,
    List<bool>? flagged,
    List<String>? footer,
    Set<int> rightAligned = const {},
    int? signCol,
  }) {
    return Table(
      border: TableBorder.all(color: const Color(0xFF333333), width: .8),
      columnWidths: {for (var i = 0; i < flex.length; i++) i: FlexColumnWidth(flex[i])},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFFEDEDED)),
          children: [
            for (var i = 0; i < headers.length; i++)
              _cell(headers[i], header: true, align: rightAligned.contains(i) ? TextAlign.right : TextAlign.left),
          ],
        ),
        for (var r = 0; r < rows.length; r++)
          TableRow(
            decoration: BoxDecoration(color: (flagged != null && flagged[r]) ? _flag : null),
            children: [
              for (var i = 0; i < rows[r].length; i++)
                SizedBox(
                  height: 26,
                  child: (_sign && i == signCol)
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          child: CustomPaint(size: Size.infinite, painter: _Signature(r * 7 + 3)),
                        )
                      : Align(
                          alignment: rightAligned.contains(i) ? Alignment.centerRight : Alignment.centerLeft,
                          child: _cell(rows[r][i], align: rightAligned.contains(i) ? TextAlign.right : TextAlign.left),
                        ),
                ),
            ],
          ),
        if (footer != null)
          TableRow(children: [
            for (var i = 0; i < footer.length; i++)
              _cell(footer[i], bold: true, align: rightAligned.contains(i) ? TextAlign.right : TextAlign.left),
          ]),
      ],
    );
  }

  int get _rowCount => filled ? tanods!.length : kQuota;
  // Unchecked names are highlighted on screen, never on the signed paper.
  List<bool>? get _flags => filled && !signed ? [for (final t in tanods!) !t.confirmed] : null;

  Widget _payroll() {
    final rows = [
      for (var i = 0; i < _rowCount; i++)
        filled ? [_no(i), tanods![i].fullName, '${_group(kAmountEach)}.00', ''] : ['', '', '', ''],
    ];
    return _table(
      headers: ['NO.', 'NAME OF TANOD', 'AMOUNT (₱)', 'SIGNATURE OF PAYEE'],
      flex: [1, 4, 2, 3],
      rows: rows,
      flagged: _flags,
      footer: ['', 'TOTAL', filled ? '${_group(tanods!.length * kAmountEach)}.00' : '', ''],
      rightAligned: {2},
      signCol: 3,
    );
  }

  Widget _masterlist() {
    final rows = [
      for (var i = 0; i < _rowCount; i++)
        filled
            ? [
                _no(i),
                tanods![i].middle.isEmpty
                    ? '${tanods![i].last}, ${tanods![i].first}'
                    : '${tanods![i].last}, ${tanods![i].first} ${tanods![i].middle}.',
                tanods![i].idType,
                '',
              ]
            : ['', '', '', ''],
    ];
    return _table(
      headers: ['NO.', 'NAME (LAST, FIRST M.I.)', 'ID PRESENTED', 'SIGNATURE'],
      flex: [1, 4, 3, 3],
      rows: rows,
      flagged: _flags,
      signCol: 3,
    );
  }

  Widget _line() => Container(
        margin: const EdgeInsets.only(left: 4),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _ink, width: .8))),
        child: const Text(' '),
      );

  Widget _signedLine(int seed) => Container(
        height: 18,
        margin: const EdgeInsets.only(left: 4),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _ink, width: .8))),
        child: CustomPaint(size: Size.infinite, painter: _Signature(seed)),
      );

  Widget _certification() {
    final n = filled ? '${tanods!.length}' : '________';
    final body = _t(13, serifFont: true).copyWith(height: 1.8);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('TO WHOM IT MAY CONCERN:', style: _t(12, w: FontWeight.w700)),
      const SizedBox(height: 14),
      Text.rich(
        TextSpan(style: body, children: [
          const TextSpan(text: '        This is to certify that the following '),
          TextSpan(text: n, style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(
              text: ' persons are bona fide barangay tanods of Barangay $barangay, $kMunicipality, Iloilo, who '
                  'rendered service for calendar year $kYear and are entitled to the financial assistance under '
                  'Provincial Ordinance No. 2020-240.'),
        ]),
        textAlign: TextAlign.justify,
      ),
      const SizedBox(height: 16),
      if (filled)
        Wrap(runSpacing: 2, children: [
          for (var i = 0; i < tanods!.length; i++)
            SizedBox(
              width: 312,
              child: Container(
                color: (tanods![i].confirmed || signed) ? null : _flag,
                child: Text('${_no(i)}  ${tanods![i].fullName}', style: _t(12)),
              ),
            ),
        ])
      else
        Wrap(runSpacing: 10, children: [
          for (var i = 0; i < 10; i++)
            SizedBox(
              width: 300,
              child: Row(children: [
                SizedBox(width: 22, child: Text('${i + 1}.', style: _t(12))),
                Expanded(child: _line()),
              ]),
            ),
        ]),
      const SizedBox(height: 18),
      Text(
        '        Issued this ______ day of ______________ $kYear at Barangay $barangay, $kMunicipality, Iloilo.',
        style: body,
      ),
    ]);
  }

  Widget _idSheet() {
    final count = filled ? tanods!.length : 6;
    return Wrap(spacing: 12, runSpacing: 12, children: [
      for (var i = 0; i < count; i++) _idBox(filled ? tanods![i] : null, i),
    ]);
  }

  Widget _idBox(Tanod? t, int i) => Container(
        width: 200,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: (t != null && !t.confirmed && !signed) ? _flag : null,
          border: Border.all(color: const Color(0xFF333333), width: .8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: 92,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F3F3),
              border: Border.all(color: const Color(0xFFBBBBBB), width: .8),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.badge_outlined, size: 26, color: Color(0xFF999999)),
              const SizedBox(height: 4),
              Text(t == null ? 'Attach ID photocopy' : t.idType, style: _t(9.5, color: _grey)),
            ]),
          ),
          const SizedBox(height: 8),
          Text(t == null ? 'Name: ____________________' : '${_no(i)}  ${t.fullName}',
              overflow: TextOverflow.ellipsis, style: _t(10.5, w: t == null ? FontWeight.w400 : FontWeight.w700)),
          const SizedBox(height: 6),
          for (var s = 1; s <= 3; s++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Text('$s.', style: _t(9.5, color: _grey)),
                Expanded(child: (_sign && t != null) ? _signedLine(i * 3 + s) : _line()),
              ]),
            ),
        ]),
      );

  // ---------- signatures ----------
  Widget _signatories() {
    Widget block(String label, String? name, String role, int seed) => SizedBox(
          width: 250,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: _t(11, color: _grey)),
            SizedBox(
              width: double.infinity,
              height: 26,
              child: _sign ? Padding(padding: const EdgeInsets.fromLTRB(40, 2, 40, 0), child: CustomPaint(size: Size.infinite, painter: _Signature(seed))) : null,
            ),
            Container(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _ink, width: .8))),
              padding: const EdgeInsets.only(bottom: 2),
              child: Text((name == null || name.trim().isEmpty) ? ' ' : name,
                  textAlign: TextAlign.center, style: _t(12, w: FontWeight.w700)),
            ),
            const SizedBox(height: 3),
            Center(child: Text(role, style: _t(11, color: _grey))),
          ]),
        );
    return Wrap(spacing: 60, runSpacing: 24, alignment: WrapAlignment.spaceBetween, children: [
      block('Prepared by:', filled ? (preparedBy ?? kRepName).toUpperCase() : null, preparedRole, 91),
      block('Certified correct:', filled ? (certifiedBy ?? kCaptain).toUpperCase() : null, 'Punong Barangay', 57),
    ]);
  }
}

// A handwritten-looking signature in blue ink. The seed varies the shape.
class _Signature extends CustomPainter {
  final int seed;
  const _Signature(this.seed);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = ((seed * 37) % 100) / 100.0;
    final paint = Paint()
      ..color = const Color(0xFF1F3A8A)
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(w * .08, h * (.7 - r * .2))
      ..cubicTo(w * .18, h * .05, w * (.26 + r * .06), h * .95, w * .36, h * .45)
      ..cubicTo(w * .44, h * .05, w * .5, h * .85, w * (.58 + r * .06), h * .4)
      ..quadraticBezierTo(w * .7, h * (.1 + r * .3), w * .9, h * .6);
    canvas.drawPath(path, paint);
    canvas.drawLine(Offset(w * (.3 + r * .1), h * .78), Offset(w * (.7 + r * .1), h * .72), paint..strokeWidth = .9);
  }

  @override
  bool shouldRepaint(covariant _Signature oldDelegate) => oldDelegate.seed != seed;
}