import 'package:flutter/material.dart';

import 'package:tanod_incentives/theme.dart';
import 'package:tanod_incentives/data/demo_data.dart';
import 'package:tanod_incentives/widgets/app_field.dart';
// MERGE: real scanners instead of the mock reader
import 'package:tanod_incentives/Scanner/id_capture.dart';
import 'package:tanod_incentives/Scanner/ocr_files/id_parser.dart' show IdSanitizer;
import 'package:tanod_incentives/Templates/payroll_template.dart' show TanodPerson;
import 'package:tanod_incentives/data/tanod_bridge.dart';

// ID scan flow. MERGE: "Take photo" now runs the real scanners — PhilSys QR
// when online, OCR photo scan when offline (Scanner/id_capture.dart).
// Only the PhilSys National ID can be scanned. Other IDs are typed in by hand.
// Steps: privacy notice (first time) → capture → reading → confirm.
// Returns the list of tanods saved during this session.

class ScanFlowPage extends StatefulWidget {
  final int startCount; // tanods already listed (for award numbers)
  final int slotsLeft; // remaining OPPDC quota
  const ScanFlowPage({super.key, required this.startCount, required this.slotsLeft});

  static bool privacyAccepted = false; // shown once per app run (demo)

  @override
  State<ScanFlowPage> createState() => _ScanFlowPageState();
}

enum _Step { privacy, capture, reading, confirm }

const kScannableId = 'PhilSys National ID';

class _Sample {
  final String first, middleName, last;
  final Set<String> hardToRead; // fields the reader was unsure about
  const _Sample(this.first, this.middleName, this.last, this.hardToRead);
  String get middleInitial => middleName.isEmpty ? '' : middleName[0];
}

// MERGE: only used as the faded illustration in the viewfinder now.
const _samples = [
  _Sample('Juan', 'Santos', 'Dela Cruz', {}),
];

class _ScanFlowPageState extends State<ScanFlowPage> with SingleTickerProviderStateMixin {
  late _Step step = ScanFlowPage.privacyAccepted ? _Step.capture : _Step.privacy;
  final List<Tanod> saved = [];
  static const int _sampleIndex = 0;

  bool privacyTicked = false;
  bool checked = false; // "I checked this against the original ID"
  bool manual = false; // typed by hand, no photo
  String manualType = kIdTypes.firstWhere((t) => t != kScannableId); // for typed entries
  String get idType => manual ? manualType : kScannableId;
  _Sample? sample;

  // MERGE: the real scan result (null when typed by hand)
  TanodPerson? scanned;
  String scanSource = ''; // 'QR code' or 'photo scan (offline)'

  final _first = TextEditingController();
  final _middle = TextEditingController();
  final _last = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  late final AnimationController _scanLine =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  int get slotsLeft => widget.slotsLeft - saved.length;
  int get nextIndex => widget.startCount + saved.length;

  @override
  void dispose() {
    _first.dispose();
    _middle.dispose();
    _last.dispose();
    _scanLine.dispose();
    super.dispose();
  }

  void _close() => Navigator.pop(context, saved);

  // MERGE: real capture. [method] auto = QR when online, OCR when offline.
  Future<void> _capture([ScanMethod method = ScanMethod.auto]) async {
    setState(() {
      manual = false;
      step = _Step.reading; // shown while checking the connection
    });
    _scanLine.repeat(reverse: true);

    final person = await captureId(
      context,
      method: method,
      barangay: kBarangay,
      municipality: kMunicipality,
    );
    if (!mounted) return;
    _scanLine.stop();

    if (person == null) {
      setState(() => step = _Step.capture);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('No ID was read. Try again, or type the details instead.'),
          behavior: SnackBarBehavior.floating,
        ));
      return;
    }

    final t = tanodFromPerson(person);
    setState(() {
      scanned = person;
      scanSource = person.scannedByOcr ? 'photo scan (offline)' : 'QR code';
      sample = null;
      _first.text = t.first;
      _middle.text = t.middle;
      _last.text = t.last;
      checked = false;
      step = _Step.confirm;
    });
  }

  // Barangay named on the ID's address, if it could be read.
  String get _idBarangay =>
      scanned == null ? '' : IdSanitizer.splitAddress(scanned!.rawAddress.toUpperCase()).barangay;

  void _typeInstead() => setState(() {
        manual = true;
        sample = null;
        scanned = null;
        _first.clear();
        _middle.clear();
        _last.clear();
        checked = false;
        step = _Step.confirm;
      });

  void _save({required bool next}) {
    if (!_formKey.currentState!.validate()) return;
    final s = scanned;
    final t = Tanod(
      _first.text.trim(),
      _middle.text.trim().toUpperCase(),
      _last.text.trim(),
      idType,
      // MERGE: keep what the scanner gave us (photos for the ID photocopy sheet)
      suffix: manual || s == null ? '' : s.suffix.trim().toUpperCase(),
      scannedAddress: manual || s == null ? '' : s.rawAddress,
      idFront: manual ? null : s?.idFront,
      idBack: manual ? null : s?.idBack,
    );
    final msg = 'Saved ${t.fullName} as award no. ${nextIndex.toString().padLeft(3, '0')}.';
    setState(() => saved.add(t));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
    if (next && slotsLeft > 0) {
      setState(() => step = _Step.capture);
    } else {
      _close();
    }
  }

  // ---------------- layout ----------------
  @override
  Widget build(BuildContext context) {
    final stepNo = switch (step) {
      _Step.privacy => 0,
      _Step.capture || _Step.reading => 1,
      _Step.confirm => 2,
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: C.mist,
        body: SafeArea(
          child: Column(children: [
            _header(stepNo),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: KeyedSubtree(key: ValueKey(step), child: _body()),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _header(int stepNo) {
    const labels = ['Photo', 'Confirm'];
    return Container(
      color: C.navy,
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 14),
      child: Column(children: [
        Row(children: [
          IconButton(
            tooltip: 'Close',
            onPressed: _close,
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Scan PhilSys ID', style: sans(18, w: FontWeight.w700, color: Colors.white)),
              Text(
                saved.isEmpty
                    ? 'Brgy. $kBarangay · $slotsLeft of $kQuota slots left'
                    : '${saved.length} saved this session · $slotsLeft slots left',
                style: sans(13.5, color: const Color(0xFFB9C9DA)),
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.wifi_off_rounded, size: 14, color: C.yellow),
              const SizedBox(width: 6),
              Text('Works offline', style: sans(13, w: FontWeight.w600, color: Colors.white)),
            ]),
          ),
        ]),
        if (stepNo > 0) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              for (var i = 0; i < 2; i++) ...[
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: 4,
                      decoration: BoxDecoration(
                        color: i < stepNo ? C.yellow : Colors.white.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('${i + 1}. ${labels[i]}',
                        style: sans(13, w: i == stepNo - 1 ? FontWeight.w700 : FontWeight.w500,
                            color: i < stepNo ? Colors.white : const Color(0xFF8FA6BF))),
                  ]),
                ),
                if (i < 1) const SizedBox(width: 8),
              ],
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _body() => switch (step) {
        _Step.privacy => _privacy(),
        _Step.capture => _captureView(),
        _Step.reading => _reading(),
        _Step.confirm => _confirm(),
      };

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(24)}) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE1E9F2)),
          boxShadow: [
            BoxShadow(color: C.navy.withValues(alpha: .06), blurRadius: 24, spreadRadius: -8, offset: const Offset(0, 10)),
          ],
        ),
        child: child,
      );

  Widget _primary(String label, IconData icon, VoidCallback? onPressed) => FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: C.yellow,
          foregroundColor: C.navy,
          disabledBackgroundColor: const Color(0xFFE3EAF2),
          disabledForegroundColor: const Color(0xFF97A5B5),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          textStyle: sans(15, w: FontWeight.w700),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
        label: Text(label),
      );

  Widget _secondary(String label, IconData icon, VoidCallback? onPressed) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: C.navy,
          side: const BorderSide(color: C.line, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          textStyle: sans(14.5, w: FontWeight.w600),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );

  // ---------------- 0. Privacy ----------------
  Widget _privacy() {
    Widget point(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: C.blueSoft, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 20, color: C.blue),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: sans(15, w: FontWeight.w700, color: C.navy)),
                const SizedBox(height: 2),
                Text(body, style: sans(14, color: C.muted, h: 1.45)),
              ]),
            ),
          ]),
        );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: _card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: C.greenSoft, borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.shield_outlined, size: 28, color: C.green),
            ),
            const SizedBox(height: 16),
            Text('Before you scan', style: serif(28)),
            const SizedBox(height: 6),
            Text('IDs carry personal data. Here’s how Gawad handles it.',
                style: sans(15, color: C.muted, h: 1.5)),
            const SizedBox(height: 22),
            point(Icons.text_fields_rounded, 'Only what the documents need',
                'The name and ID type are kept. The address is only used to check the barangay. '
                    'The PhilSys number and birth date are not kept.'),
            point(Icons.phone_android_rounded, 'Photos stay on this phone',
                'ID photos are not uploaded unless your municipality approves it.'),
            point(Icons.fact_check_outlined, 'You always check first',
                'Nothing goes into a document until you confirm it against the original ID.'),
            point(Icons.gavel_rounded, 'Data Privacy Act of 2012',
                'Access is limited by role, and records follow the province’s retention policy.'),
            const SizedBox(height: 4),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => privacyTicked = !privacyTicked),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Checkbox(
                    value: privacyTicked,
                    activeColor: C.green,
                    onChanged: (v) => setState(() => privacyTicked = v ?? false),
                  ),
                  Expanded(
                    child: Text('The tanods know their IDs are being scanned for the incentive documents.',
                        style: sans(14, color: C.ink, h: 1.4)),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            _primary(
              'Continue',
              Icons.arrow_forward_rounded,
              privacyTicked
                  ? () => setState(() {
                        ScanFlowPage.privacyAccepted = true;
                        step = _Step.capture;
                      })
                  : null,
            ),
          ]),
        ),
      ),
    );
  }

  // ---------------- 2. Capture ----------------
  Widget _viewfinder({Widget? child}) => AspectRatio(
        aspectRatio: 4 / 3,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1B2733), Color(0xFF0B1118)],
              ),
            ),
            child: Stack(alignment: Alignment.center, children: [
              if (child != null) Padding(padding: const EdgeInsets.all(48), child: child),
              const Positioned.fill(child: Padding(padding: EdgeInsets.all(28), child: _FrameGuide())),
            ]),
          ),
        ),
      );

  Widget _captureView() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Scan the PhilSys National ID', style: serif(28)),
      const SizedBox(height: 6),
      Text('Use the physical card, front side up. Not a photocopy.', style: sans(15, color: C.muted, h: 1.5)),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(color: C.blueSoft, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.info_outline, size: 18, color: C.blue),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Only the PhilSys ID can be scanned. Tanods with other IDs are typed in by hand.',
                style: sans(14.5, color: const Color(0xFF1B3F68), h: 1.4)),
          ),
          TextButton(
            onPressed: _typeInstead,
            child: Text('Other ID', style: sans(14.5, w: FontWeight.w700, color: C.blue)),
          ),
        ]),
      ),
      const SizedBox(height: 18),
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _viewfinder(
              child: Opacity(opacity: .35, child: _MockIdCard(sample: _samples[_sampleIndex % _samples.length])),
            ),
            const SizedBox(height: 14),
            Wrap(alignment: WrapAlignment.center, spacing: 18, runSpacing: 8, children: [
              _tip(Icons.crop_free_rounded, 'Fit the whole ID in the frame'),
              _tip(Icons.wb_sunny_outlined, 'Avoid glare'),
              _tip(Icons.straighten_rounded, 'Keep it flat'),
            ]),
            const SizedBox(height: 20),
            Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 12, children: [
              _primary('Scan ID', Icons.photo_camera_outlined, () => _capture()),
              _secondary('Photo scan (offline)', Icons.document_scanner_outlined, () => _capture(ScanMethod.ocr)),
            ]),
            const SizedBox(height: 10),
            Center(
              child: TextButton.icon(
                onPressed: _typeInstead,
                icon: const Icon(Icons.keyboard_outlined, size: 18, color: C.blue),
                label: Text('No PhilSys ID? Type the details instead',
                    style: sans(14, w: FontWeight.w600, color: C.blue)),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _tip(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: C.muted),
        const SizedBox(width: 6),
        Text(text, style: sans(14, color: C.muted)),
      ]);

  // ---------------- 3. Reading ----------------
  Widget _reading() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _viewfinder(
            child: Stack(children: [
              _MockIdCard(sample: _samples[_sampleIndex % _samples.length]),
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _scanLine,
                  builder: (context, _) => Align(
                    alignment: Alignment(0, -1 + 2 * _scanLine.value),
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: C.yellow,
                        boxShadow: [BoxShadow(color: C.yellow.withValues(alpha: .7), blurRadius: 14, spreadRadius: 2)],
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 22),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: C.blue)),
            const SizedBox(width: 12),
            Text('Opening the scanner…', style: sans(17, w: FontWeight.w700, color: C.navy)),
          ]),
          const SizedBox(height: 6),
          Text('QR code when online, photo scan when offline.',
              textAlign: TextAlign.center, style: sans(14, color: C.muted)),
        ]),
      ),
    );
  }

  // ---------------- 4. Confirm ----------------
  Widget _confirm() {
    final low = sample?.hardToRead ?? const <String>{};
    final noMoreSlots = slotsLeft <= 1;

    Widget field(String key, Widget input) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          input,
          if (low.contains(key))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                const Icon(Icons.error_outline, size: 15, color: Color(0xFF7A5B00)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    key == 'middle'
                        ? 'Hard to read. Type the middle initial if there is one.'
                        : 'Hard to read. Check letters like ñ against the ID.',
                    style: sans(13.5, w: FontWeight.w600, color: const Color(0xFF7A5B00)),
                  ),
                ),
              ]),
            ),
        ]);

    final photo = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: const Color(0xFF111A24), borderRadius: BorderRadius.circular(18)),
        child: manual
            ? AspectRatio(
                aspectRatio: 1.586,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.keyboard_outlined, size: 34, color: Color(0xFF8FA6BF)),
                  const SizedBox(height: 8),
                  Text('Typed by hand · no photo', style: sans(14.5, color: const Color(0xFFB9C9DA))),
                ]),
              )
            : (scanned?.idFront != null
                // MERGE: the real, straightened card photo from the OCR scan
                ? AspectRatio(
                    aspectRatio: 1.586,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(scanned!.idFront!, fit: BoxFit.cover),
                    ),
                  )
                : AspectRatio(
                    aspectRatio: 1.586,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.qr_code_2_rounded, size: 40, color: Color(0xFF8FA6BF)),
                      const SizedBox(height: 8),
                      Text('Read from the QR code · no photo', style: sans(14.5, color: const Color(0xFFB9C9DA))),
                    ]),
                  )),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: Text(manual ? 'Check the spelling with the tanod.' : 'Compare every field with the ID.',
              style: sans(14, color: C.muted)),
        ),
        TextButton.icon(
          onPressed: () => setState(() => step = _Step.capture),
          icon: const Icon(Icons.replay_rounded, size: 17, color: C.blue),
          label: Text(manual ? 'Scan instead' : 'Retake', style: sans(14.5, w: FontWeight.w600, color: C.blue)),
        ),
      ]),
    ]);

    final form = Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: C.blueSoft, borderRadius: BorderRadius.circular(99)),
            child: Text('Award no. ${nextIndex.toString().padLeft(3, '0')}',
                style: sans(13.5, w: FontWeight.w700, color: C.blue)),
          ),
          const SizedBox(width: 8),
          if (!manual)
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: C.greenSoft, borderRadius: BorderRadius.circular(99)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.document_scanner_outlined, size: 13, color: C.green),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text('Read from $kScannableId · $scanSource', overflow: TextOverflow.ellipsis,
                        style: sans(13.5, w: FontWeight.w600, color: const Color(0xFF14583D))),
                  ),
                ]),
              ),
            ),
        ]),
        if (manual) ...[
          const SizedBox(height: 18),
          const FieldLabel('ID presented'),
          DropdownButtonFormField<String>(
            initialValue: manualType,
            isExpanded: true,
            style: sans(15),
            dropdownColor: Colors.white,
            decoration: fieldDecoration('', Icons.badge_outlined),
            items: kIdTypes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (v) => setState(() => manualType = v ?? manualType),
          ),
        ],
        const SizedBox(height: 18),
        field(
          'last',
          AppField(
            label: 'Last name',
            icon: Icons.person_outline,
            controller: _last,
            hint: 'Dela Cruz',
            validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the last name.' : null,
          ),
        ),
        const SizedBox(height: 14),
        field(
          'first',
          AppField(
            label: 'First name',
            icon: Icons.person_outline,
            controller: _first,
            hint: 'Juan',
            validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the first name.' : null,
          ),
        ),
        const SizedBox(height: 14),
        field(
          'middle',
          AppField(
            label: 'Middle initial',
            icon: Icons.short_text,
            controller: _middle,
            hint: 'S',
            maxLength: 1,
            required: false,
            optional: true,
          ),
        ),
        // MERGE: compliance check — the ID's address names another barangay
        if (!manual && livesElsewhere(_idBarangay, kBarangay)) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.location_off_outlined, size: 18, color: Color(0xFF7A5B00)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'The address on this ID says Brgy. ${_title(_idBarangay)}, not Brgy. $kBarangay. '
                  'Make sure this tanod serves in $kBarangay before saving.',
                  style: sans(14, color: const Color(0xFF5C4400), h: 1.4),
                ),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => checked = !checked),
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
            decoration: BoxDecoration(
              color: checked ? C.greenSoft : C.mist,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Checkbox(
                value: checked,
                activeColor: C.green,
                onChanged: (v) => setState(() => checked = v ?? false),
              ),
              Expanded(
                child: Text(
                  manual ? 'I checked the spelling with the tanod.' : 'I checked every field against the original ID.',
                  style: sans(14, w: FontWeight.w600, color: C.ink),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 18),
        _primary('Save tanod', Icons.check_rounded, checked ? () => _save(next: false) : null),
        const SizedBox(height: 10),
        _secondary(
          noMoreSlots ? 'Quota reached after this one' : 'Save and scan next',
          Icons.document_scanner_outlined,
          checked && !noMoreSlots ? () => _save(next: true) : null,
        ),
      ]),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Check the details', style: serif(28)),
      const SizedBox(height: 6),
      Text(
        manual
            ? 'Type the name exactly as it appears on their ID.'
            : 'Compare each field with the ID and fix anything that was read wrong.',
        style: sans(15, color: C.muted, h: 1.5),
      ),
      const SizedBox(height: 20),
      _card(
        child: LayoutBuilder(builder: (context, box) {
          if (box.maxWidth < 700) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              photo,
              const SizedBox(height: 20),
              form,
            ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 5, child: photo),
            const SizedBox(width: 28),
            Expanded(flex: 4, child: form),
          ]);
        }),
      ),
    ]);
  }
}

String _title(String s) => s
    .toLowerCase()
    .split(' ')
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');

// ---------------- Mock ID card ----------------
// A generic card drawn in Flutter, standing in for the camera photo.
class _MockIdCard extends StatelessWidget {
  final _Sample sample;
  final Set<String> highlight;
  const _MockIdCard({required this.sample, this.highlight = const {}});

  @override
  Widget build(BuildContext context) {
    Widget value(String key, String label, String text) {
      final hl = highlight.contains(key);
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: sans(7.5, w: FontWeight.w600, color: const Color(0xFF6B7C8F))),
          Container(
            margin: const EdgeInsets.only(top: 1),
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: hl ? C.yellow.withValues(alpha: .35) : null,
              border: hl ? Border.all(color: C.yellowDark, width: 1.5) : null,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(text.isEmpty ? '▒▒▒▒▒▒' : text.toUpperCase(),
                style: sans(11, w: FontWeight.w700, color: const Color(0xFF16273A))),
          ),
        ]),
      );
    }

    return AspectRatio(
      aspectRatio: 1.586,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF4F7FB), Color(0xFFDCE6F2)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 18, offset: Offset(0, 8))],
        ),
        clipBehavior: Clip.antiAlias,
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: 320,
            height: 202,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                color: C.blue,
                alignment: Alignment.centerLeft,
                child: Text('PHILSYS NATIONAL ID',
                    style: sans(10, w: FontWeight.w700, color: Colors.white).copyWith(letterSpacing: 1)),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 72,
                      height: 90,
                      decoration: BoxDecoration(
                        color: const Color(0xFFC3D0DE),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.person, size: 56, color: Color(0xFF8A9BAF)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        value('last', 'APELYIDO / LAST NAME', sample.last),
                        value('first', 'MGA PANGALAN / GIVEN NAMES', sample.first),
                        value('middle', 'GITNANG APELYIDO / MIDDLE NAME', sample.middleName),
                      ]),
                    ),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Text('PCN  •••• •••• •••• ••••   (not stored)',
                    style: sans(9, w: FontWeight.w600, color: const Color(0xFF6B7C8F))),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// White corner brackets over the viewfinder.
class _FrameGuide extends StatelessWidget {
  const _FrameGuide();

  @override
  Widget build(BuildContext context) {
    const len = 34.0;
    const w = 4.0;
    Widget corner(Alignment a) {
      final top = a.y < 0;
      final left = a.x < 0;
      return Align(
        alignment: a,
        child: SizedBox(
          width: len,
          height: len,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: top ? const BorderSide(color: Colors.white, width: w) : BorderSide.none,
                bottom: !top ? const BorderSide(color: Colors.white, width: w) : BorderSide.none,
                left: left ? const BorderSide(color: Colors.white, width: w) : BorderSide.none,
                right: !left ? const BorderSide(color: Colors.white, width: w) : BorderSide.none,
              ),
            ),
          ),
        ),
      );
    }

    return Stack(children: [
      corner(Alignment.topLeft),
      corner(Alignment.topRight),
      corner(Alignment.bottomLeft),
      corner(Alignment.bottomRight),
    ]);
  }
}
