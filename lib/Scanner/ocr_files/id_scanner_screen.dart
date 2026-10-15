import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:tanod_incentives/Templates/payroll_template.dart'; // MERGE: TanodPerson
import 'id_parser.dart';
import 'id_image_tools.dart';
import 'package:tanod_incentives/Scanner/id_camera_screen.dart';
import 'package:tanod_incentives/widgets/notify.dart'; // top pop-ups
import 'package:tanod_incentives/data/scan_settings.dart'; // address / birthday on or off

/// OCR scanner (used when there is no internet).
/// Pops a [TanodPerson] back to the masterlist when "Confirm Details" is tapped.
class IdScannerScreen extends StatefulWidget {
  /// MERGE (Gawad): the signed-in barangay's area. Used when the address on
  /// the card can't be read, so the scan isn't blocked.
  final String fallbackBarangay;
  final String fallbackMunicipality;

  const IdScannerScreen({
    super.key,
    this.fallbackBarangay = '',
    this.fallbackMunicipality = '',
  });

  @override
  State<IdScannerScreen> createState() => _IdScannerScreenState();
}

class _IdScannerScreenState extends State<IdScannerScreen> {
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _middleInitialController = TextEditingController();
  final TextEditingController _birthDateController = TextEditingController(); // MERGE
  final TextEditingController _addressController = TextEditingController();   // MERGE

  // MERGE: barangay & municipality are NOT typed in. They come from the address:
  // Gemini's split when online, otherwise IdSanitizer.splitAddress.
  // _aiSplitFor remembers which address Gemini's split belongs to, so if the
  // tanod edits the address, we re-split the edited text instead.
  String _aiBarangay = '';
  String _aiMunicipality = '';
  String _aiSplitFor = '';

  ({String barangay, String municipality}) get _addressParts {
    final address = _addressController.text.trim().toUpperCase();
    if (address.isNotEmpty && address == _aiSplitFor &&
        _aiBarangay.isNotEmpty && _aiMunicipality.isNotEmpty) {
      return (barangay: _aiBarangay, municipality: _aiMunicipality);
    }
    return IdSanitizer.splitAddress(address);
  }

  // Card images cropped from each photo; shown as previews and used for the PDF
  Uint8List? _frontCard;
  Uint8List? _backCard;

  // "Was it scanned properly?" result for each side
  SideQuality? _frontQuality;
  SideQuality? _backQuality;

  // Fields to highlight for checking (the two readings disagreed)
  final Set<IdField> _needsCheck = {};

  bool _isProcessing = false;
  String _statusText = '';

  @override
  void dispose() {
    _textRecognizer.close();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _middleInitialController.dispose();
    _birthDateController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  TextEditingController _controllerFor(IdField f) => switch (f) {
        IdField.firstName => _firstNameController,
        IdField.lastName => _lastNameController,
        IdField.middleInitial => _middleInitialController,
        IdField.birthDate => _birthDateController,
        IdField.address => _addressController,
      };

  // UPGRADE: our own camera with an ID-shaped guide. The shutter only unlocks
  // when the card's 4 edges line up with the frame (Scanner/id_camera_screen.dart).
  Future<XFile?> _capture({String title = 'Scan the ID'}) {
    return Navigator.push<XFile>(
      context,
      MaterialPageRoute(builder: (_) => IdCameraScreen(title: title)),
    );
  }

  // Top pop-up; the color picks the style (green = done, orange = check, red = problem)
  /// Fields shown on this screen (birthday / address can be turned off)
  bool _shows(IdField f) => switch (f) {
        IdField.birthDate => kCollectBirthday,
        IdField.address => kCollectAddress,
        _ => true,
      };

  void _showMessage(String text, Color color) {
    if (!mounted) return;
    final type = color == Colors.green
        ? NotifyType.success
        : color == Colors.red
            ? NotifyType.error
            : NotifyType.warning;
    notify(context, text, type: type);
  }

  void _setStatus(String text) {
    if (mounted) setState(() => _statusText = text);
  }

  /// One button: front first, then straight to the back (like the PhilSys scan).
  /// Stops if the person backs out of the camera.
  Future<void> _scanBoth() async {
    final before = _frontCard;
    await _scanFront();
    if (!mounted || _frontCard == null || identical(_frontCard, before)) return; // front cancelled
    await _scanBack();
  }

  Future<void> _scanFront() async {
    final XFile? image = await _capture(title: 'Front of the ID');
    if (image == null) return;

    setState(() {
      _isProcessing = true;
      _statusText = 'Reading ID details...';
    });

    try {
      final Uint8List photo = await compute(normalizePhoto, await image.readAsBytes());

      // Gemini and on-device OCR read the same photo at the same time
      final geminiFuture = IdParser.readWithGemini(photo);
      final ocrFuture = _textRecognizer.processImage(InputImage.fromFilePath(image.path));

      final gemini = await geminiFuture;
      final ScannedIdData ocr = IdParser.readOffline(await ocrFuture);
      final ScannedIdData result = IdParser.merge(gemini?.data, ocr);

      _setStatus('Checking scan quality...');
      final Uint8List card = await compute(flattenCard, (photo, gemini?.check.corners));
      final double sharpness = await compute(sharpnessScore, card);
      print('Front sharpness score: ${sharpness.toStringAsFixed(1)}');

      final quality = IdParser.assessFront(
        check: gemini?.check,
        merged: result,
        ocr: ocr,
        sharpness: sharpness,
      );

      if (!mounted) return;

      setState(() {
        _frontCard = card;
        _frontQuality = quality;
        _needsCheck.clear();
        for (final f in IdField.values) {
          final value = result.get(f);
          if (value.isEmpty) continue; // keep anything the user already typed
          _controllerFor(f).text = value;
          if (result.needsCheck.contains(f) && _shows(f)) _needsCheck.add(f);
        }
        // MERGE: remember Gemini's barangay/municipality split for this address
        _aiBarangay = gemini?.data.barangay ?? '';
        _aiMunicipality = gemini?.data.municipality ?? '';
        _aiSplitFor = gemini?.data.address ?? '';
      });

      if (gemini == null) {
        _showMessage('Front photo saved. Read offline — please double-check all fields', Colors.orange);
      } else if (quality.ok) {
        _showMessage('Front photo saved — readable and cross-checked', Colors.green);
      } else {
        _showMessage('Front photo saved — see the scan quality notes', Colors.orange);
      }
    } catch (e) {
      _showMessage('Scan Error: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusText = '';
        });
      }
    }
  }

  Future<void> _scanBack() async {
    final XFile? image = await _capture(title: 'Back of the ID');
    if (image == null) return;

    setState(() {
      _isProcessing = true;
      _statusText = 'Checking back side...';
    });

    try {
      final Uint8List photo = await compute(normalizePhoto, await image.readAsBytes());

      final checkFuture = IdParser.checkBackWithGemini(photo);
      final ocrFuture = _textRecognizer.processImage(InputImage.fromFilePath(image.path));

      final ScanCheck? check = await checkFuture;
      final int ocrLines = IdParser.countReadableLines(await ocrFuture);

      final Uint8List card = await compute(flattenCard, (photo, check?.corners));
      final double sharpness = await compute(sharpnessScore, card);
      print('Back sharpness score: ${sharpness.toStringAsFixed(1)}');

      final quality = IdParser.assessBack(check: check, ocrLines: ocrLines, sharpness: sharpness);

      if (!mounted) return;
      setState(() {
        _backCard = card;
        _backQuality = quality;
      });

      _showMessage(
        quality.ok ? 'Back photo saved — readable' : 'Back photo saved — see the scan quality notes',
        quality.ok ? Colors.green : Colors.orange,
      );
    } catch (e) {
      _showMessage('Scan Error: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusText = '';
        });
      }
    }
  }

  /// MERGE: replaces the old per-scan photocopy button. The photocopy is now
  /// Template 4 in the PDF screen, so here we only save the tanod (with the
  /// card images) and send it back to the masterlist.
  Future<void> _confirmDetails() async {
    final first = _firstNameController.text.trim();
    final last = _lastNameController.text.trim();
    // Address off (scan_settings.dart): the signed-in account's barangay is used
    final address = kCollectAddress ? _addressController.text.trim() : '';
    final parts = kCollectAddress ? _addressParts : (barangay: '', municipality: '');
    final brgy = parts.barangay.isNotEmpty ? parts.barangay : widget.fallbackBarangay;
    final muni = parts.municipality.isNotEmpty ? parts.municipality : widget.fallbackMunicipality;

    final missing = <String>[
      if (first.isEmpty) 'First Name',
      if (last.isEmpty) 'Last Name',
      if (kCollectAddress && address.isEmpty && widget.fallbackBarangay.isEmpty) 'Address',
      if (kCollectAddress && (brgy.isEmpty || muni.isEmpty))
        'Barangay/Municipality in the address (write it like "PUROK 1, ARIPDIP, SAN RAFAEL, ILOILO")',
      if (_frontCard == null) 'Front scan',
      if (_backCard == null) 'Back scan',
    ];
    if (missing.isNotEmpty) {
      _showMessage('Missing: ${missing.join(', ')}', Colors.red);
      return;
    }

    // Same warning as before, now shown before saving
    final allReadable = (_frontQuality?.ok ?? false) && (_backQuality?.ok ?? false);
    final unchecked = _needsCheck.isNotEmpty;
    if (!allReadable || unchecked) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Some scans need attention'),
          content: Text(
            unchecked
                ? 'Some name fields are highlighted for checking. Save anyway?'
                : 'One side may not be fully readable. Retaking it gives a cleaner photocopy. Save anyway?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Go back')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save anyway')),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    Navigator.pop(
      context,
      TanodPerson.fromOcr(
        firstName: first,
        lastName: last,
        middleInitial: _middleInitialController.text,
        birthDate: kCollectBirthday ? _birthDateController.text : '',
        address: address,
        barangay: brgy,
        municipality: muni,
        idFront: _frontCard,
        idBack: _backCard,
      ),
    );
  }

  void _viewFullImage(Uint8List bytes) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: InteractiveViewer(child: Image.memory(bytes)),
      ),
    );
  }

  Widget _qualityCard(String side, Uint8List? card, SideQuality? q, VoidCallback onRetake) {
    if (card == null || q == null) return const SizedBox.shrink();
    final color = q.ok ? Colors.green : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tap to zoom in and check the scan yourself
            GestureDetector(
              onTap: () => _viewFullImage(card),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(card, width: 110, height: 70, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(side, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Icon(q.ok ? Icons.check_circle : Icons.warning_amber, color: color, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        q.ok ? 'Readable' : 'Needs attention',
                        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (final p in q.problems) _qualityLine(Icons.close, Colors.orange.shade800, p),
                  for (final p in q.passed) _qualityLine(Icons.check, Colors.green.shade700, p),
                  // Retake just this side
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                      onPressed: _isProcessing ? null : onRetake,
                      icon: const Icon(Icons.replay_rounded, size: 16),
                      label: Text('Retake $side', style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qualityLine(IconData icon, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color))),
        ],
      ),
    );
  }

  Widget _nameField(String label, IdField field, {String? hint, int maxLines = 1}) {
    final flagged = _needsCheck.contains(field);

    return TextField(
      controller: _controllerFor(field),
      textCapitalization: TextCapitalization.characters,
      maxLines: maxLines,
      minLines: 1,
      onChanged: (_) {
        // Once the user edits a flagged field, they've checked it
        if (flagged) setState(() => _needsCheck.remove(field));
        // MERGE: refresh the barangay/municipality preview under the address
        if (field == IdField.address) setState(() {});
      },
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        enabledBorder: flagged
            ? const OutlineInputBorder(borderSide: BorderSide(color: Colors.orange, width: 2))
            : null,
        helperText: flagged ? 'Please verify — the two readings did not match' : null,
        helperStyle: TextStyle(color: Colors.orange.shade800),
        suffixIcon: flagged ? const Icon(Icons.warning_amber, color: Colors.orange) : null,
      ),
    );
  }

  /// MERGE: read-only line showing how the address was split, so the tanod
  /// can see it's right without extra text fields.
  Widget _addressPreview() {
    if (_addressController.text.trim().isEmpty) return const SizedBox.shrink();
    final p = _addressParts;
    final ok = p.barangay.isNotEmpty && p.municipality.isNotEmpty;
    return Row(
      children: [
        Icon(ok ? Icons.place : Icons.help_outline,
            size: 16, color: ok ? Colors.green.shade700 : Colors.orange.shade800),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            ok
                ? 'Barangay: ${p.barangay}  •  Municipality: ${p.municipality}'
                : 'Could not find the barangay/municipality — edit the address',
            style: TextStyle(
              fontSize: 12,
              color: ok ? Colors.green.shade700 : Colors.orange.shade800,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAnyScan = _frontCard != null || _backCard != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline ID Scan (OCR)'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // One Scan button: front, then back
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _isProcessing ? null : _scanBoth,
              icon: Icon(_frontCard == null ? Icons.document_scanner_outlined : Icons.replay_rounded),
              label: Text(_frontCard == null ? 'Scan ID (front, then back)' : 'Scan again'),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tip: hold the phone sideways, fill the frame with the card, avoid glare.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (_isProcessing) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(
                _statusText,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue),
              ),
            ],
            if (hasAnyScan) ...[
              const SizedBox(height: 20),
              const Text(
                'Scan Quality:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 10),
              _qualityCard('Front', _frontCard, _frontQuality, _scanFront),
              _qualityCard('Back', _backCard, _backQuality, _scanBack),
            ],
            const SizedBox(height: 20),
            const Text(
              'Extracted Data (Verify & Correct):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),
            _nameField('First Name', IdField.firstName),
            const SizedBox(height: 12),
            _nameField('Last Name', IdField.lastName),
            const SizedBox(height: 12),
            _nameField('Middle Initial', IdField.middleInitial),
            const SizedBox(height: 12),
            // Birthday / Address only when turned on in data/scan_settings.dart
            if (kCollectBirthday) ...[
              _nameField('Birthday', IdField.birthDate, hint: 'e.g. JANUARY 15, 1990'),
              const SizedBox(height: 12),
            ],
            if (kCollectAddress) ...[
              _nameField('Address', IdField.address, maxLines: 3),
              const SizedBox(height: 6),
              _addressPreview(),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _isProcessing ? null : _confirmDetails,
              child: const Text('Confirm Details', style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}