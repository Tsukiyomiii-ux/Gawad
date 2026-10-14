import 'package:flutter/material.dart';

import 'package:tanod_incentives/theme.dart';

// Bottom sheet for uploading the signed paper copy of a document.
// GUI only: the camera and file picker are simulated.
// Returns 'photo' or 'file', or null if cancelled.
Future<String?> showUploadSheet(BuildContext context, {required String docTitle, bool correction = false}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => _UploadSheet(docTitle: docTitle, correction: correction),
  );
}

class _UploadSheet extends StatefulWidget {
  final String docTitle;
  final bool correction;
  const _UploadSheet({required this.docTitle, required this.correction});

  @override
  State<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<_UploadSheet> {
  String? busy; // 'photo' or 'file' while "uploading"

  void _pick(String via) {
    setState(() => busy = via);
    Future.delayed(const Duration(milliseconds: 1300), () {
      if (mounted) Navigator.pop(context, via);
    });
  }

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
            tr('Take a clear photo of every page of the signed paper, or choose a scan. It replaces the file in Gawad '
                    'and becomes the backup copy your municipality and OPPDC can open.',
                'Kunan ng malinaw na litrato ang bawat pahina ng pirmadong papel, o pumili ng scan. Papalitan nito ang file '
                    'sa Gawad at magiging backup na mabubuksan ng munisipyo at OPPDC.',
                'Kuhai sang maathag nga litrato ang kada pahina sang may pirma nga papel, ukon pilia ang scan. Ilisan sini '
                    'ang file sa Gawad kag mangin backup nga mabuksan sang munisipyo kag OPPDC.'),
            style: sans(15, color: C.muted, h: 1.5),
          ),
          const SizedBox(height: 18),
          if (busy != null) ...[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: C.mist, borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: C.blue)),
                  const SizedBox(width: 12),
                  Text(tr('Uploading…', 'Nag-a-upload…', 'Ginaupload…'), style: sans(16, w: FontWeight.w700, color: C.navy)),
                ]),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: const LinearProgressIndicator(
                    minHeight: 6,
                    backgroundColor: Color(0xFFE3EAF2),
                    valueColor: AlwaysStoppedAnimation(C.blue),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  tr('No internet? It’s saved on the phone and uploads later.',
                      'Walang internet? Naka-save ito sa phone at mag-a-upload mamaya.',
                      'Wala internet? Naka-save ini sa phone kag ma-upload ini sa ulihi.'),
                  style: sans(13.5, color: C.muted),
                ),
              ]),
            ),
          ] else ...[
            _option(
              'photo',
              Icons.photo_camera_outlined,
              tr('Take a photo', 'Kumuha ng litrato', 'Magkuha sang litrato'),
              tr('Use the phone camera. Lay the paper flat in good light.',
                  'Gamitin ang camera ng phone. Ilapag ang papel sa maliwanag na lugar.',
                  'Gamita ang camera sang phone. Ibutang ang papel sa masanag nga lugar.'),
            ),
            const SizedBox(height: 10),
            _option(
              'file',
              Icons.upload_file_outlined,
              tr('Choose a file', 'Pumili ng file', 'Magpili sang file'),
              tr('A PDF or picture from a scanner.', 'PDF o larawan mula sa scanner.', 'PDF ukon litrato halin sa scanner.'),
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
