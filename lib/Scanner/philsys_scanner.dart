// PhilSys scanner (QR), now photo-based:
//   1. guided photo of the FRONT of the ID
//   2. guided photo of the BACK of the ID
//   3. the QR code is read from those photos (whichever side has it), using mobile_scanner
//   4. both photos are cropped to the card and kept for the ID photocopy
//
// Returns a TanodPerson (with idFront / idBack), or null if cancelled.
// Uses the same guided camera as the OCR scan (Scanner/id_camera_screen.dart).

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart' show XFile;
import 'package:mobile_scanner/mobile_scanner.dart' show MobileScannerController;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'package:tanod_incentives/Scanner/id_camera_screen.dart';
import 'package:tanod_incentives/theme.dart' show tr;
import 'package:tanod_incentives/widgets/notify.dart'; // top pop-ups
import 'package:tanod_incentives/data/scan_settings.dart'; // address / birthday on or off
import 'package:tanod_incentives/Scanner/ocr_files/id_parser.dart' show IdParser;
import 'package:tanod_incentives/Templates/payroll_template.dart' show TanodPerson;

class PhilsysScannerView extends StatefulWidget {
  const PhilsysScannerView({super.key});

  @override
  State<PhilsysScannerView> createState() => _PhilsysScannerViewState();
}

class _PhilsysScannerViewState extends State<PhilsysScannerView> {
  // Original photo paths (for reading the QR) and cropped cards (for the photocopy)
  String? _frontPath, _backPath;
  Uint8List? _frontCard, _backCard;

  bool _busy = false;
  String _status = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    // Go straight to the camera: front, then back, then read
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (_frontCard == null && !await _shoot(front: true)) return;
    if (_backCard == null && !await _shoot(front: false)) return;
    await _read();
  }

  /// Opens the guided camera for one side. Returns false if cancelled.
  Future<bool> _shoot({required bool front}) async {
    final photo = await Navigator.push<XFile>(
      context,
      MaterialPageRoute(builder: (_) => IdCameraScreen(title: front ? 'Front of the ID' : 'Back of the ID')),
    );
    if (photo == null || !mounted) return false;

    setState(() {
      _busy = true;
      _status = 'Preparing photo…';
      _error = null;
    });
    final card = await compute(cropToGuide, await photo.readAsBytes());
    if (!mounted) return false;
    setState(() {
      _busy = false;
      if (front) {
        _frontPath = photo.path;
        _frontCard = card;
      } else {
        _backPath = photo.path;
        _backCard = card;
      }
    });
    notify(
      context,
      front
          ? tr('Front photo saved. Next, the back of the ID.', 'Na-save ang harap. Susunod, ang likod ng ID.', 'Na-save ang atubangan. Sunod, ang likod sang ID.')
          : tr('Back photo saved. Reading the QR code…', 'Na-save ang likod. Binabasa ang QR code…', 'Na-save ang likod. Ginabasa ang QR code…'),
      title: tr('Photo saved', 'Na-save ang litrato', 'Na-save ang litrato'),
    );
    return true;
  }

  /// Finds the QR in the photos and builds the TanodPerson.
  Future<void> _read() async {
    setState(() {
      _busy = true;
      _status = 'Reading the QR code…';
      _error = null;
    });

    // mobile_scanner (already in the project) can also read a QR from a saved photo
    final scanner = MobileScannerController();
    String? raw;
    try {
      // The QR is usually on the back; check it first, then the front
      for (final path in [_backPath, _frontPath]) {
        if (path == null) continue;
        final capture = await scanner.analyzeImage(path);
        for (final c in capture?.barcodes ?? const []) {
          final v = c.rawValue?.trim() ?? '';
          if (v.isNotEmpty) {
            raw = v;
            break;
          }
        }
        if (raw != null) break;
      }
    } catch (e) {
      _fail('Could not read the photos: $e');
      return;
    } finally {
      scanner.dispose();
    }

    // Demo mode (kRequirePhilSysQr = false in data/scan_settings.dart): any ID
    // is accepted. No QR, or a QR without a name → read the name from the photo.
    if (!kRequirePhilSysQr) {
      final fromQr = raw == null ? null : TanodPerson.fromJsonString(raw, idFront: _frontCard, idBack: _backCard);
      var person = (fromQr != null && fromQr.lastName.trim().isNotEmpty) ? fromQr : await _nameFromPhoto();
      if (!kCollectAddress) person = _withAddress(person, ''); // not kept
      if (mounted) Navigator.pop(context, person);
      return;
    }

    if (raw == null) {
      _fail('No QR code found. Retake the side with the QR code: fill the frame, hold steady and avoid glare.');
      return;
    }

    var person = TanodPerson.fromJsonString(raw, idFront: _frontCard, idBack: _backCard);
    if (person.lastName.isEmpty) {
      _fail('This QR code is not a PhilSys ID. Please scan a PhilSys National ID.');
      return;
    }

    // The PhilSys QR has no address. Read it from the front photo instead
    // (offline ML Kit), so the documents show where the tanod lives.
    // (Skipped when the address is turned off in data/scan_settings.dart)
    if (kCollectAddress && person.rawAddress.replaceAll(RegExp(r'[,\s]'), '').isEmpty && _frontPath != null) {
      setState(() => _status = 'Reading the address…');
      final ocr = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final text = await ocr.processImage(InputImage.fromFilePath(_frontPath!));
        final address = IdParser.readOffline(text).address;
        if (address.isNotEmpty) person = _withAddress(person, address);
      } catch (_) {
        // No address is fine: the account's barangay is used instead
      } finally {
        ocr.close();
      }
    }

    if (!kCollectAddress) person = _withAddress(person, ''); // not kept
    if (mounted) Navigator.pop(context, person);
  }

  /// Any ID (demo): read the name printed on the front photo (offline ML Kit).
  /// Whatever it misses, the person types on the next screen.
  Future<TanodPerson> _nameFromPhoto() async {
    var first = '', middle = '', last = '';
    if (_frontPath != null) {
      setState(() => _status = 'Reading the name…');
      final ocr = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final d = IdParser.readOffline(await ocr.processImage(InputImage.fromFilePath(_frontPath!)));
        first = d.firstName;
        middle = d.middleInitial;
        last = d.lastName;
      } catch (_) {
        // name not readable: it is typed on the next screen
      } finally {
        ocr.close();
      }
    }
    return TanodPerson(
      pcn: 'N/A',
      firstName: first,
      middleName: middle,
      lastName: last,
      suffix: '',
      sex: 'N/A',
      dob: 'N/A',
      pob: 'N/A',
      rawAddress: '',
      barangay: '',
      municipality: '',
      idFront: _frontCard,
      idBack: _backCard,
    );
  }

  TanodPerson _withAddress(TanodPerson p, String address) => TanodPerson(
        pcn: p.pcn,
        firstName: p.firstName,
        middleName: p.middleName,
        lastName: p.lastName,
        suffix: p.suffix,
        sex: p.sex,
        dob: p.dob,
        pob: p.pob,
        rawAddress: address,
        barangay: p.barangay,
        municipality: p.municipality,
        idFront: p.idFront,
        idBack: p.idBack,
      );

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  // ---------------------------------------------------------------------------
  // UI: only seen while processing, or when something needs retaking
  // ---------------------------------------------------------------------------

  Widget _side(String label, Uint8List? card, VoidCallback onRetake) => Expanded(
        child: Column(children: [
          AspectRatio(
            aspectRatio: 85.6 / 54,
            child: Container(
              decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(8)),
              clipBehavior: Clip.antiAlias,
              child: card == null
                  ? const Icon(Icons.badge_outlined, color: Colors.black38, size: 36)
                  : Image.memory(card, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          TextButton.icon(
            onPressed: _busy ? null : onRetake,
            icon: const Icon(Icons.replay_rounded, size: 18),
            label: Text(card == null ? 'Take photo' : 'Retake'),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan PhilSys ID')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              _side('Front', _frontCard, () => _shoot(front: true)),
              const SizedBox(width: 12),
              _side('Back', _backCard, () => _shoot(front: false)),
            ]),
            const SizedBox(height: 16),
            if (_busy) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(_status, textAlign: TextAlign.center),
            ],
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFFDF0EE), borderRadius: BorderRadius.circular(10)),
                child: Text(_error!, style: const TextStyle(color: Color(0xFF8E2A22))),
              ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _busy || _frontCard == null || _backCard == null ? null : _read,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Read the ID'),
            ),
          ]),
        ),
      ),
    );
  }
}