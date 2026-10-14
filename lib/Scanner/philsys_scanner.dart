import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';

// --- FIXED RELATIVE PATHS ---
// 1. Go up one level to lib/, then down into Templates/
import '../Templates/payroll_template.dart'; 
// 2. Go down into the local ocr_files/ folder
import 'ocr_files/id_parser.dart'; 
import 'ocr_files/id_image_tools.dart'; 
// ----------------------------

class PhilsysScannerView extends StatefulWidget {
  const PhilsysScannerView({super.key});

  @override
  State<PhilsysScannerView> createState() => _PhilsysScannerViewState();
}

class _PhilsysScannerViewState extends State<PhilsysScannerView> {
  final MobileScannerController _cameraController = MobileScannerController();
  final ImagePicker _picker = ImagePicker();
  
  bool _isProcessing = false;
  String _statusText = '';

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_isProcessing) return;
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? rawValue = barcodes.first.rawValue;
    if (rawValue == null || !rawValue.contains('{')) return;

    setState(() {
      _isProcessing = true;
      _statusText = 'QR Read! Opening Camera...';
    });

    try {
      await _cameraController.stop();
      await Future.delayed(const Duration(milliseconds: 500));

      Uint8List? frontBytes;
      Uint8List? backBytes;

      // 1. CAPTURE FRONT
      final XFile? frontPhoto = await _picker.pickImage(
        source: ImageSource.camera, 
        maxWidth: 1600, 
        maxHeight: 1600,
      );
      
      if (frontPhoto != null) {
        setState(() => _statusText = 'AI is cropping Front ID...');
        
        // --- TEAMMATE'S AI CROP LOGIC FOR FRONT ---
        final rawFront = await frontPhoto.readAsBytes();
        final normFront = await compute(normalizePhoto, rawFront);
        final geminiFront = await IdParser.readWithGemini(normFront);
        frontBytes = await compute(flattenCard, (normFront, geminiFront?.check.corners));
        // ------------------------------------------

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Now capture the ID Back.'), backgroundColor: Colors.blue),
          );
        }

        // 2. CAPTURE BACK
        final XFile? backPhoto = await _picker.pickImage(
          source: ImageSource.camera, 
          maxWidth: 1600, 
          maxHeight: 1600,
        );
        
        if (backPhoto != null) {
          setState(() => _statusText = 'AI is cropping Back ID...');
          
          // --- TEAMMATE'S AI CROP LOGIC FOR BACK ---
          final rawBack = await backPhoto.readAsBytes();
          final normBack = await compute(normalizePhoto, rawBack);
          final geminiBack = await IdParser.checkBackWithGemini(normBack);
          backBytes = await compute(flattenCard, (normBack, geminiBack?.corners));
          // -----------------------------------------
        }
      }

      // Create the final person with perfectly cropped photos
      final person = TanodPerson.fromJsonString(
        rawValue,
        idFront: frontBytes,
        idBack: backBytes,
      );

      if (mounted) {
        Navigator.pop(context, person);
      }
      
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan PhilSys QR'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _cameraController,
            onDetect: _handleBarcode,
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 16),
                    Text(
                      _statusText,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}