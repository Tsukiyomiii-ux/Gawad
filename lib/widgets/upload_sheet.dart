import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:tanod_incentives/theme.dart';
import 'package:tanod_incentives/widgets/notify.dart'; // top pop-ups

/// What the person picked in the upload sheet.
class UploadedFile {
  final String via; // 'photo' or 'file'
  final Uint8List bytes;
  final String name;
  final bool isPdf;
  const UploadedFile({required this.via, required this.bytes, required this.name, required this.isPdf});
}

// Bottom sheet for uploading the signed paper copy of a document.
// "Take a photo" opens the camera (phones only); "Choose a file" picks a
// PDF or picture from the phone or computer. Returns null if cancelled.
Future<UploadedFile?> showUploadSheet(BuildContext context, {required String docTitle, bool correction = false}) {
  return showModalBottomSheet<UploadedFile>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => _UploadSheet(docTitle: docTitle, correction: correction),
  );
}

/// Opens the camera and returns the photo, or null if cancelled.
/// Also used by the Request access form (proof of designation).
Future<UploadedFile?> takePhotoUpload() async {
  final x = await ImagePicker().pickImage(
    source: ImageSource.camera,
    maxWidth: 2200, // sharp enough to read, small enough to store
    imageQuality: 85,
  );
  if (x == null) return null;
  return UploadedFile(via: 'photo', bytes: await x.readAsBytes(), name: x.name, isPdf: false);
}

/// Lets the person pick a PDF / JPG / PNG, or null if cancelled.
/// Also used by the Request access form (proof of designation).
Future<UploadedFile?> chooseFileUpload() async {
  const types = XTypeGroup(
    label: 'PDF or picture',
    extensions: ['pdf', 'jpg', 'jpeg', 'png'],
    mimeTypes: ['application/pdf', 'image/jpeg', 'image/png'], // needed on Android
    uniformTypeIdentifiers: ['com.adobe.pdf', 'public.jpeg', 'public.png'], // needed on iOS/macOS
  );
  final f = await openFile(acceptedTypeGroups: const [types]);
  if (f == null) return null;
  return UploadedFile(
    via: 'file',
    bytes: await f.readAsBytes(),
    name: f.name,
    isPdf: f.name.toLowerCase().endsWith('.pdf'),
  );
}

/// The camera only works on phones; desktops choose a file instead.
bool get hasCamera =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

class _UploadSheet extends StatefulWidget {
  final String docTitle;
  final bool correction;
  const _UploadSheet({required this.docTitle, required this.correction});

  @override
  State<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<_UploadSheet> {
  String? busy; // 'photo' or 'file' while reading the picked file

  Future<void> _pick(String via) async {
    setState(() => busy = via);
    try {
      final picked = via == 'photo' ? await _takePhoto() : await _chooseFile();
      if (!mounted) return;
      if (picked == null) {
        setState(() => busy = null); // cancelled: stay on the sheet
        return;
      }
      Navigator.pop(context, picked);
    } catch (e) {
      if (!mounted) return;
      setState(() => busy = null);
      notify(context, tr('Couldn’t open that: $e', 'Hindi mabuksan: $e', 'Indi mabuksan: $e'), type: NotifyType.error);
    }
  }

  Future<UploadedFile?> _takePhoto() => takePhotoUpload();
  Future<UploadedFile?> _chooseFile() => chooseFileUpload();

  Widget _option(String via, IconData icon, String title, String sub) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: C.line, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: busy == null ? () => _pick(via) : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(color: C.blueSoft, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: C.blue, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: sans(16.5, w: FontWeight.w700, color: C.navy)),
                const SizedBox(height: 2),
                Text(sub, style: sans(14, color: C.muted, h: 1.4)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: C.muted),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.correction
        ? tr('Upload the corrected ${widget.docTitle}', 'I-upload ang naitamang ${widget.docTitle}',
            'I-upload ang natadlong nga ${widget.docTitle}')
        : tr('Upload the signed ${widget.docTitle}', 'I-upload ang pirmadong ${widget.docTitle}',
            'I-upload ang may pirma nga ${widget.docTitle}');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(9)),
            ),
          ),
          const SizedBox(height: 18),
          Text(title, style: serif(23)),
          const SizedBox(height: 6),
          Text(
            tr('Take a clear photo of the signed paper, or choose a PDF or picture. It replaces the old copy in Gawad '
                    'and becomes the backup your municipality and OPPDC can open.',
                'Kunan ng malinaw na litrato ang pirmadong papel, o pumili ng PDF o larawan. Papalitan nito ang lumang kopya '
                    'sa Gawad at magiging backup na mabubuksan ng munisipyo at OPPDC.',
                'Palihog kuhai sang maathag nga litrato ang may pirma nga papel, ukon magpili sang PDF ukon litrato. Ilisan sini '
                    'ang daan nga kopya sa Gawad kag mangin backup nga mabuksan sang munisipyo kag OPPDC.'),
            style: sans(15, color: C.muted, h: 1.5),
          ),
          const SizedBox(height: 18),
          if (busy != null) ...[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: C.mist, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: C.blue)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    busy == 'photo'
                        ? tr('Waiting for the camera…', 'Hinihintay ang camera…', 'Ginahulat ang camera…')
                        : tr('Waiting for you to pick a file…', 'Hinihintay ang pipiliing file…', 'Ginahulat ang pilion nga file…'),
                    style: sans(16, w: FontWeight.w700, color: C.navy),
                  ),
                ),
              ]),
            ),
          ] else ...[
            if (hasCamera) ...[
              _option(
                'photo',
                Icons.photo_camera_outlined,
                tr('Take a photo', 'Kumuha ng litrato', 'Magkuha sang litrato'),
                tr('Use the phone camera. Lay the paper flat in good light.',
                    'Gamitin ang camera ng phone. Ilapag ang papel sa maliwanag na lugar.',
                    'Gamita ang camera sang phone. Ibutang ang papel sa masanag nga lugar.'),
              ),
              const SizedBox(height: 10),
            ],
            _option(
              'file',
              Icons.upload_file_outlined,
              tr('Choose a file', 'Pumili ng file', 'Magpili sang file'),
              tr('A PDF or picture (JPG, PNG) from this phone or computer.',
                  'PDF o larawan (JPG, PNG) mula sa phone o computer na ito.',
                  'PDF ukon litrato (JPG, PNG) halin sa sini nga phone ukon computer.'),
            ),
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => Navigator.pop(context),
              child: Text(tr('Cancel', 'Kanselahin', 'Kanselaha'), style: sans(15, w: FontWeight.w600, color: C.muted)),
            ),
          ],
        ]),
      ),
    );
  }
}