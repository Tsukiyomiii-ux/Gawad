import 'package:flutter/material.dart';

import 'package:tanod_incentives/theme.dart';
import 'package:tanod_incentives/data/doc_kind.dart';
import 'package:tanod_incentives/data/store.dart';
import 'package:tanod_incentives/widgets/ui.dart';
import 'package:tanod_incentives/widgets/chat_thread.dart';
import 'package:tanod_incentives/screens/dashboard/documents_view.dart' show showBackupCopy, shareSignedCopy;

// The municipal reviewer checks one barangay's PAPER set.
// Mistakes are sent to the barangay as messages, tagged to a document. The
// barangay fixes the paper and uploads the corrected copy, so the backup
// stays the same as the paper. When the paper set is complete and correct,
// the reviewer marks it as checked.

// Common mistakes as ready-made messages: (chip label, message, document).
List<(String, String, DocKind?)> quickMistakes() => [
      (
        tr('Name doesn’t match ID', 'Hindi tugma sa ID', 'Indi pareho sa ID'),
        tr('A name on the paper doesn’t match the tanod’s ID. Please correct the spelling.',
            'May pangalan sa papel na hindi tugma sa ID ng tanod. Pakitama ang baybay.',
            'May ngalan sa papel nga indi pareho sa ID sang tanod. Palihog tadlunga ang spelling.'),
        DocKind.masterlist,
      ),
      (
        tr('Missing signature', 'Kulang ang pirma', 'Kulang ang pirma'),
        tr('A signature is missing on the paper copy.', 'May kulang na pirma sa papel na kopya.',
            'May kulang nga pirma sa papel nga kopya.'),
        null,
      ),
      (
        tr('ID copy needs 3 signatures', 'Kulang sa 3 pirma ang ID', 'Kulang sa 3 ka pirma ang ID'),
        tr('An ID photocopy has fewer than 3 signatures.', 'May kopya ng ID na kulang sa 3 pirma.',
            'May ID photocopy nga kulang sa 3 ka pirma.'),
        DocKind.idSheet,
      ),
      (
        tr('Wrong year in title', 'Mali ang taon', 'Sayop ang tuig'),
        tr('The year in the overhead title is wrong.', 'Mali ang taon sa pamagat sa itaas.',
            'Sayop ang tuig sa titulo sa ibabaw.'),
        DocKind.payroll,
      ),
      (
        tr('Numbers don’t match', 'Hindi tugma ang numero', 'Indi pareho ang numero'),
        tr('An award number on the Payroll doesn’t match the Masterlist.',
            'May award number sa Payroll na hindi tugma sa Masterlist.',
            'May award number sa Payroll nga indi pareho sa Masterlist.'),
        DocKind.payroll,
      ),
      (
        tr('Missing document', 'Kulang na dokumento', 'Kulang nga dokumento'),
        tr('A document is missing from the paper set.', 'May kulang na dokumento sa papel na set.',
            'May kulang nga dokumento sa papel nga set.'),
        null,
      ),
      (
        tr('Too many tanods', 'Sobra ang tanod', 'Sobra ang tanod'),
        tr('There are more tanods than the limit allowed.', 'Sobra ang tanod sa limitang pinapayagan.',
            'Sobra ang tanod sa limit nga gintugot.'),
        DocKind.masterlist,
      ),
      (
        tr('Signatory spelled differently', 'Iba ang baybay ng pumirma', 'Lain ang spelling sang pumirma'),
        tr('A signatory’s name is spelled differently from the other documents.',
            'Iba ang baybay ng pangalan ng pumirma kumpara sa ibang dokumento.',
            'Lain ang spelling sang ngalan sang pumirma kumpara sa iban nga dokumento.'),
        DocKind.certification,
      ),
    ];

class CheckPage extends StatefulWidget {
  final BrgyRecord rec;
  const CheckPage({super.key, required this.rec});

  @override
  State<CheckPage> createState() => _CheckPageState();
}

class _CheckPageState extends State<CheckPage> {
  BrgyRecord get b => widget.rec;

  @override
  void initState() {
    super.initState();
    b.unreadMuni = 0;
  }

  // The paper set is at the municipal office and can be checked.
  bool get canReview => b.status == BrgyStatus.submitted || b.status == BrgyStatus.corrections;

  List<String> get _dupNames {
    final seen = <String>{};
    final out = <String>[];
    for (final t in b.tanods) {
      if (!seen.add(t.nameKey)) out.add(t.fullName);
    }
    return out;
  }

  int get _unchecked => b.tanods.where((t) => !t.confirmed).length;

  bool get _blocking => b.tanods.length > b.quota || _dupNames.isNotEmpty || _unchecked > 0;

  bool get canMarkChecked =>
      canReview && b.paperOk.length == DocKind.values.length && b.toFix.isEmpty && b.backupComplete && !_blocking;

  // ---------- actions ----------
  void _send(String text, DocKind? doc) {
    setState(() {
      b.post(fromMunicipality: true, text: text, doc: doc);
      if (doc != null) {
        b.files[doc]!.correction = true;
        b.paperOk.remove(doc);
        if (b.status == BrgyStatus.submitted || b.status == BrgyStatus.checked) {
          b.status = BrgyStatus.corrections;
        }
      }
    });
    if (doc != null) {
      toast(
        context,
        tr('Sent. Brgy. ${b.name} will correct the ${doc.title} and upload the corrected copy.',
            'Naipadala. Itatama ng Brgy. ${b.name} ang ${doc.title} at ia-upload ang naitamang kopya.',
            'Napadala. Tadlungon sang Brgy. ${b.name} ang ${doc.title} kag i-upload ang natadlong nga kopya.'),
      );
    }
  }

  Future<void> _reportProblem(DocKind k) async {
    final text = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(tr('What’s wrong on the paper ${k.title}?', 'Ano ang mali sa papel na ${k.title}?',
              'Ano ang sala sa papel nga ${k.title}?'), style: serif(23)),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(
                    tr('This goes to Brgy. ${b.name} as a message. They fix only what you write, then upload the corrected copy.',
                        'Mapupunta ito sa Brgy. ${b.name} bilang mensahe. Ang isinulat lang ninyo ang itatama nila, saka ia-upload ang naitamang kopya.',
                        'Makadto ini sa Brgy. ${b.name} bilang mensahe. Ang ginsulat lang ninyo ang tadlungon nila, dayon i-upload ang natadlong nga kopya.'),
                    style: sans(15, color: C.muted, h: 1.5),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: text,
                    minLines: 3,
                    maxLines: 5,
                    style: sans(15.5),
                    cursorColor: C.blue,
                    decoration: fieldDecoration(
                        tr('e.g. No. 004 has only 2 of 3 signatures.', 'hal. Ang No. 004 ay may 2 lang sa 3 pirma.',
                            'pananglitan: Ang No. 004 may 2 lang sa 3 ka pirma.'),
                        Icons.edit_note_rounded),
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? tr('Write what needs fixing.', 'Isulat kung ano ang itatama.', 'Isulat kon ano ang tadlungon.')
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(tr('Common mistakes (tap to fill in)', 'Karaniwang mali (pindutin para punan)',
                      'Kasagaran nga sala (pinduta para pun-on)'), style: sans(14, w: FontWeight.w600, color: C.muted)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final (label, msg, _) in quickMistakes())
                      ActionChip(
                        label: Text(label, style: sans(14, color: C.navy)),
                        backgroundColor: C.mist,
                        side: const BorderSide(color: C.line),
                        onPressed: () => setD(() => text.text = msg),
                      ),
                  ]),
                ]),
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Cancel', 'Kanselahin', 'Kanselaha'), style: sans(15, w: FontWeight.w600, color: C.muted)),
            ),
            FilledButton.icon(
              style: primaryStyle(bg: C.red, fg: Colors.white),
              onPressed: () {
                if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
              },
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text(tr('Send to barangay', 'Ipadala sa barangay', 'Ipadala sa barangay')),
            ),
          ],
        );
      }),
    );
    final msg = text.text.trim();
    Future.delayed(const Duration(milliseconds: 400), text.dispose);
    if (send == true && mounted) _send(msg, k);
  }

  Future<void> _markChecked() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Mark Brgy. ${b.name} as checked?', 'Markahang nasuri na ang Brgy. ${b.name}?',
            'Markahan nga nausisa na ang Brgy. ${b.name}?'), style: serif(23)),
        content: Text(
          tr('The paper set is complete and correct, and the backup copies match. It goes with the other barangays to OPPDC.',
              'Kumpleto at tama ang papel, at tugma ang backup. Isasama ito sa ibang barangay papunta sa OPPDC.',
              'Kompleto kag husto ang papel, kag pareho ang backup. Iupod ini sa iban nga barangay pakadto sa OPPDC.'),
          style: sans(15.5, color: C.muted, h: 1.5),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Not yet', 'Hindi pa', 'Indi pa'), style: sans(15, w: FontWeight.w600, color: C.muted)),
          ),
          FilledButton(
            style: primaryStyle(bg: C.green, fg: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Mark as checked', 'Markahang nasuri', 'Markahan nga nausisa')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      b.status = BrgyStatus.checked;
      b.post(fromMunicipality: true, system: true, text: 'Paper set checked. Nothing to fix. Thank you!');
    });
    toast(context, tr('Brgy. ${b.name} is checked.', 'Nasuri na ang Brgy. ${b.name}.', 'Nausisa na ang Brgy. ${b.name}.'));
  }

  // ---------- layout ----------
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 1050;
    final left = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _howTo(),
      const SizedBox(height: 20),
      _alerts(),
      const SizedBox(height: 20),
      _paperChecklist(),
      const SizedBox(height: 20),
      _decision(),
    ]);
    final chat = Panel(
      title: tr('Messages with Brgy. ${b.name}', 'Mensahe sa Brgy. ${b.name}', 'Mensahe sa Brgy. ${b.name}'),
      icon: Icons.chat_bubble_outline_rounded,
      help: tr(
          'Tell the barangay what is wrong on the paper copy. Pick the document under “About” so it is marked for correction. '
              'They fix the paper and upload the corrected copy, so the backup matches.',
          'Sabihin sa barangay kung ano ang mali sa papel. Piliin ang dokumento sa “Tungkol sa” para mamarkahan itong itatama. '
              'Itatama nila ang papel at ia-upload ang naitamang kopya para tugma ang backup.',
          'Isugid sa barangay kon ano ang sala sa papel. Pilia ang dokumento sa “Parte sa” para mamarkahan ini nga tadlungon. '
              'Tadlungon nila ang papel kag i-upload ang natadlong nga kopya para pareho ang backup.'),
      child: ChatThread(
        rec: b,
        asMunicipality: true,
        height: wide ? 430 : 380,
        quickMessages: quickMistakes(),
        onSend: _send,
      ),
    );

    return Scaffold(
      backgroundColor: C.mist,
      body: SafeArea(
        child: Column(children: [
          _header(),
          Expanded(
            child: wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(28), child: left)),
                    SizedBox(
                      width: 460,
                      child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(0, 28, 28, 28), child: chat),
                    ),
                  ])
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      left,
                      const SizedBox(height: 20),
                      chat,
                    ]),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _header() {
    final (bg, fg) = statusColors(b.status);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 10, 20, 12),
      child: Row(children: [
        IconButton(
          tooltip: tr('Back', 'Bumalik', 'Balik'),
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, color: C.navy),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Brgy. ${b.name}', overflow: TextOverflow.ellipsis, style: serif(24)),
            Text(
              '${b.rep == '—' ? tr('No representative yet', 'Wala pang kinatawan', 'Wala pa sang representante') : b.rep}'
              '${b.position.isEmpty ? '' : ' · ${b.position}'} · ${b.tanods.length}/${b.quota} tanods',
              overflow: TextOverflow.ellipsis,
              style: sans(14.5, color: C.muted),
            ),
          ]),
        ),
        pill(statusLabel(b.status), bg, fg),
      ]),
    );
  }

  Widget _howTo() {
    Widget step(int n, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Text('$n', style: sans(14, w: FontWeight.w800, color: C.blue)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: sans(15, color: const Color(0xFF1B3F68), h: 1.45))),
          ]),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      decoration: BoxDecoration(color: C.blueSoft, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('How to check', 'Paano suriin', 'Paano mag-usisa'), style: sans(16.5, w: FontWeight.w700, color: C.navy)),
        const SizedBox(height: 10),
        step(1, tr('Go through the paper set the barangay brought, one document at a time.',
            'Isa-isahin ang papel na dinala ng barangay.', 'Isa-isaha ang papel nga gindala sang barangay.')),
        step(2, tr('If the paper is correct, tap “Paper is correct”. If not, tap “Something’s wrong” and write what to fix.',
            'Kung tama ang papel, pindutin ang “Tama ang papel”. Kung hindi, pindutin ang “May mali” at isulat ang itatama.',
            'Kon husto ang papel, pinduta ang “Husto ang papel”. Kon indi, pinduta ang “May sala” kag isulat ang tadlungon.')),
        step(3, tr('When all four are correct and every backup is uploaded, mark the barangay as checked.',
            'Kapag tama ang apat at na-upload ang lahat ng backup, markahang nasuri na ang barangay.',
            'Kon husto ang apat kag na-upload ang tanan nga backup, markahan nga nausisa na ang barangay.')),
      ]),
    );
  }

  // Warnings from Gawad, shown only when something is wrong.
  Widget _alerts() {
    final items = <(IconData, String, bool)>[];
    if (b.status == BrgyStatus.notStarted || b.status == BrgyStatus.preparing) {
      items.add((
        Icons.hourglass_empty_rounded,
        tr('Brgy. ${b.name} hasn’t submitted its paper set yet.', 'Hindi pa naipapasa ng Brgy. ${b.name} ang papel.',
            'Wala pa napasa sang Brgy. ${b.name} ang papel.'),
        false,
      ));
    }
    if (b.tanods.length > b.quota) {
      items.add((
        Icons.block_rounded,
        tr('More tanods than allowed: ${b.tanods.length} of ${b.quota}.', 'Sobra ang tanod: ${b.tanods.length} sa ${b.quota}.',
            'Sobra ang tanod: ${b.tanods.length} sa ${b.quota}.'),
        true,
      ));
    }
    if (_dupNames.isNotEmpty) {
      items.add((
        Icons.people_alt_outlined,
        tr('Listed twice: ${_dupNames.join(', ')}.', 'Dalawang beses nakalista: ${_dupNames.join(', ')}.',
            'Duha ka beses nalista: ${_dupNames.join(', ')}.'),
        true,
      ));
    }
    if (_unchecked > 0) {
      items.add((
        Icons.spellcheck_rounded,
        tr('$_unchecked name${_unchecked == 1 ? '' : 's'} not checked against the ID by the barangay.',
            '$_unchecked pangalan ang hindi pa naikumpara sa ID ng barangay.',
            '$_unchecked ka ngalan ang wala pa naikumpara sa ID sang barangay.'),
        false,
      ));
    }
    final missing = [for (final f in b.files.values) if (!f.uploaded) f.kind.title];
    if (missing.isNotEmpty && b.status != BrgyStatus.notStarted) {
      items.add((
        Icons.cloud_off_outlined,
        tr('No backup uploaded yet for: ${missing.join(', ')}.', 'Wala pang backup para sa: ${missing.join(', ')}.',
            'Wala pa sang backup para sa: ${missing.join(', ')}.'),
        false,
      ));
    }
    final old = [for (final f in b.files.values) if (f.outdated) f.kind.title];
    if (old.isNotEmpty) {
      items.add((
        Icons.warning_amber_rounded,
        tr('Backup out of date (the list changed after signing): ${old.join(', ')}.',
            'Luma na ang backup (nagbago ang listahan matapos pirmahan): ${old.join(', ')}.',
            'Daan na ang backup (nagbag-o ang listahan pagkatapos pirmahan): ${old.join(', ')}.'),
        true,
      ));
    }
    if (b.toFix.isNotEmpty) {
      items.add((
        Icons.assignment_return_outlined,
        tr('Waiting for the corrected copy of: ${b.toFix.map((f) => f.kind.title).join(', ')}.',
            'Hinihintay ang naitamang kopya ng: ${b.toFix.map((f) => f.kind.title).join(', ')}.',
            'Ginahulat ang natadlong nga kopya sang: ${b.toFix.map((f) => f.kind.title).join(', ')}.'),
        false,
      ));
    }

    return Panel(
      title: tr('Alerts', 'Mga paalala', 'Mga pahanumdom'),
      icon: Icons.notifications_active_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (items.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: C.greenSoft, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.verified_outlined, color: C.green, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(tr('No warnings from Gawad.', 'Walang babala mula sa Gawad.', 'Wala sang paandam halin sa Gawad.'),
                    style: sans(15, w: FontWeight.w600, color: const Color(0xFF14583D))),
              ),
            ]),
          ),
        for (final (icon, text, red) in items)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: red ? const Color(0xFFFDF0EE) : const Color(0xFFFFF8E1),
              border: Border.all(color: red ? const Color(0xFFF0C7C3) : const Color(0xFFF3DE9A)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 20, color: red ? C.red : const Color(0xFF7A5B00)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text, style: sans(15, color: red ? const Color(0xFF8E2A22) : const Color(0xFF5C4400), h: 1.4)),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _paperChecklist() {
    return Panel(
      title: tr('Paper set checklist', 'Checklist ng papel', 'Checklist sang papel'),
      icon: Icons.fact_check_outlined,
      help: tr(
          'You check the paper copy. The uploaded copy is the barangay’s backup of that paper; open it to compare, or to '
              'look something up later. OPPDC can open the same backups.',
          'Ang papel ang sinusuri ninyo. Ang na-upload na kopya ang backup ng barangay sa papel na iyon; buksan ito para '
              'ikumpara o tingnan mamaya. Mabubuksan din ito ng OPPDC.',
          'Ang papel ang ginausisa ninyo. Ang na-upload nga kopya ang backup sang barangay sang amo nga papel; buksan ini '
              'para ikumpara ukon tan-awon sa ulihi. Mabuksan man ini sang OPPDC.'),
      trailing: Text(
        tr('${b.paperOk.length} of 4 correct', '${b.paperOk.length} sa 4 tama', '${b.paperOk.length} sa 4 husto'),
        style: sans(14.5, w: FontWeight.w600, color: C.muted),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final k in DocKind.values) ...[_docRow(k), const SizedBox(height: 10)],
      ]),
    );
  }

  Widget _docRow(DocKind k) {
    final f = b.files[k]!;
    final ok = b.paperOk.contains(k);
    final remark = b.lastAbout(k);

    final (String backupText, Color backupColor) = !f.uploaded
        ? (tr('Backup: not uploaded yet', 'Backup: hindi pa na-upload', 'Backup: wala pa na-upload'), C.muted)
        : f.correction
            ? (tr('Waiting for the corrected copy', 'Hinihintay ang naitamang kopya', 'Ginahulat ang natadlong nga kopya'), C.red)
            : f.outdated
                ? (tr('Backup out of date', 'Luma na ang backup', 'Daan na ang backup'), const Color(0xFF7A5B00))
                : (
                    tr('Backup uploaded ${f.uploadedOn}${f.version > 1 ? ' · version ${f.version}' : ''}',
                        'Na-upload ang backup ${f.uploadedOn}${f.version > 1 ? ' · bersyon ${f.version}' : ''}',
                        'Na-upload ang backup ${f.uploadedOn}${f.version > 1 ? ' · bersyon ${f.version}' : ''}'),
                    const Color(0xFF14583D)
                  );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: f.correction ? const Color(0xFFFDF0EE) : (ok ? const Color(0xFFF4FBF7) : Colors.white),
        border: Border.all(color: f.correction ? const Color(0xFFF0C7C3) : (ok ? const Color(0xFFBFE5D1) : C.line)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: ok ? C.green : (f.correction ? C.red : C.mist),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(ok ? Icons.check_rounded : (f.correction ? Icons.flag_outlined : k.icon),
                size: 22, color: ok || f.correction ? Colors.white : C.navy),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(k.title, style: sans(16.5, w: FontWeight.w700, color: C.navy)),
              const SizedBox(height: 2),
              Text(backupText, style: sans(14, w: FontWeight.w600, color: backupColor)),
              if (f.correction && remark != null) ...[
                const SizedBox(height: 4),
                Text('“${remark.text}”', maxLines: 3, overflow: TextOverflow.ellipsis, style: sans(14, color: C.ink, h: 1.4)),
              ],
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            style: outlineStyle(),
            onPressed: () => showBackupCopy(
              context,
              rec: b,
              kind: k,
              actions: f.uploaded
                  ? (ctx) => [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                          onPressed: () {
                            Navigator.pop(ctx);
                            shareSignedCopy(context, b, k); // the real uploaded copy
                          },
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: Text(tr('Download', 'I-download', 'I-download')),
                        ),
                      ]
                  : null,
            ),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: Text(tr('View backup', 'Tingnan ang backup', 'Tan-awa ang backup')),
          ),
          if (canReview && !ok)
            OutlinedButton.icon(
              style: outlineStyle(fg: C.red, border: const Color(0xFFF0C7C3)),
              onPressed: () => _reportProblem(k),
              icon: const Icon(Icons.flag_outlined, size: 18),
              label: Text(tr('Something’s wrong', 'May mali', 'May sala')),
            ),
          if (canReview && !ok)
            FilledButton.icon(
              style: primaryStyle(bg: C.green, fg: Colors.white),
              onPressed: f.correction ? null : () => setState(() => b.paperOk.add(k)),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(f.correction
                  ? tr('Waiting for correction', 'Hinihintay ang pagtatama', 'Ginahulat ang pagtadlong')
                  : tr('Paper is correct', 'Tama ang papel', 'Husto ang papel')),
            ),
          if (canReview && ok)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: C.muted, minimumSize: const Size(0, 48)),
              onPressed: () => setState(() => b.paperOk.remove(k)),
              icon: const Icon(Icons.undo_rounded, size: 18),
              label: Text(tr('Undo', 'Ibalik', 'Balik'), style: sans(15, w: FontWeight.w600, color: C.muted)),
            ),
        ]),
      ]),
    );
  }

  Widget _decision() {
    final String reason;
    if (b.status == BrgyStatus.checked || b.status == BrgyStatus.sentToOppdc || b.status == BrgyStatus.released) {
      reason = tr('This barangay is already checked.', 'Nasuri na ang barangay na ito.', 'Nausisa na ini nga barangay.');
    } else if (!canReview) {
      reason = tr('Waiting for the barangay to submit its paper set.', 'Hinihintay na ipasa ng barangay ang papel.',
          'Ginahulat nga ipasa sang barangay ang papel.');
    } else if (b.toFix.isNotEmpty) {
      reason = tr('Waiting for the corrected copies.', 'Hinihintay ang naitamang kopya.', 'Ginahulat ang natadlong nga kopya.');
    } else if (_blocking) {
      reason = tr('Gawad found a mistake in the list. Message the barangay about it.',
          'May nakitang mali ang Gawad sa listahan. I-message ang barangay.',
          'May nakita nga sala ang Gawad sa listahan. I-message ang barangay.');
    } else if (!b.backupComplete) {
      reason = tr('Every document needs an up-to-date backup first.', 'Kailangan munang may bagong backup ang bawat dokumento.',
          'Kinahanglan anay may bag-o nga backup ang kada dokumento.');
    } else if (b.paperOk.length < 4) {
      reason = tr('Check all four documents on paper.', 'Suriin ang apat na dokumento sa papel.', 'Usisaa ang apat ka dokumento sa papel.');
    } else {
      reason = tr('Everything is correct. You can mark it as checked.', 'Tama ang lahat. Puwede nang markahang nasuri.',
          'Husto ang tanan. Puede na markahan nga nausisa.');
    }

    return Panel(
      title: tr('Finish checking', 'Tapusin ang pagsuri', 'Tapuson ang pag-usisa'),
      icon: Icons.task_alt_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: b.paperOk.length / 4,
                minHeight: 8,
                backgroundColor: const Color(0xFFE3EAF2),
                valueColor: const AlwaysStoppedAnimation(C.green),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(tr('${b.paperOk.length}/4 correct', '${b.paperOk.length}/4 tama', '${b.paperOk.length}/4 husto'),
              style: sans(15, w: FontWeight.w700, color: C.navy)),
        ]),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: primaryStyle(bg: C.green, fg: Colors.white),
          onPressed: canMarkChecked ? _markChecked : null,
          icon: const Icon(Icons.verified_outlined, size: 19),
          label: Text(tr('Mark as checked', 'Markahang nasuri', 'Markahan nga nausisa')),
        ),
        const SizedBox(height: 10),
        Text(reason, textAlign: TextAlign.center, style: sans(14.5, color: C.muted, h: 1.4)),
      ]),
    );
  }
}

// Status colors: (background, text). Shared with the municipality dashboard.
(Color, Color) statusColors(BrgyStatus s) => switch (s) {
      BrgyStatus.checked || BrgyStatus.released => (C.greenSoft, const Color(0xFF14583D)),
      BrgyStatus.sentToOppdc => (const Color(0xFFE4ECF6), C.navy),
      BrgyStatus.submitted => (const Color(0xFFFFF4CC), const Color(0xFF7A5B00)),
      BrgyStatus.corrections => (const Color(0xFFFDF0EE), C.red),
      BrgyStatus.preparing => (C.blueSoft, C.blue),
      BrgyStatus.notStarted => (const Color(0xFFEDF1F5), C.muted),
    };

Color statusBar(BrgyStatus s) => switch (s) {
      BrgyStatus.checked || BrgyStatus.released => C.green,
      BrgyStatus.sentToOppdc => C.navy,
      BrgyStatus.submitted => C.yellowDark,
      BrgyStatus.corrections => C.red,
      BrgyStatus.preparing => C.blue,
      BrgyStatus.notStarted => const Color(0xFFB4C2D1),
    };