import 'dart:typed_data';

import 'package:camera/camera.dart' show XFile;
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import 'package:tanod_incentives/theme.dart';
import 'package:tanod_incentives/data/demo_data.dart' show kIdType;
import 'package:tanod_incentives/widgets/app_field.dart' show FieldLabel;
import 'package:tanod_incentives/widgets/upload_sheet.dart' show hasCamera, chooseFileUpload;
import 'package:tanod_incentives/widgets/notify.dart';
import 'package:tanod_incentives/Scanner/id_camera_screen.dart' show IdCameraScreen, cropToGuide;

// Shared pieces for the "type details" and "edit tanod" boxes.

/// Fixed, read-only "ID type: PhilSys National ID" (Gawad accepts PhilSys only).
class PhilSysIdField extends StatelessWidget {
  const PhilSysIdField({super.key});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FieldLabel(tr('ID type', 'Uri ng ID', 'Klase sang ID'), required: false),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: C.mist,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: C.line, width: 1.5),
          ),
          child: Row(children: [
            const Icon(Icons.badge_outlined, size: 20, color: C.muted),
            const SizedBox(width: 12),
            Expanded(child: Text(kIdType, style: sans(15, w: FontWeight.w600, color: C.ink))),
            const Icon(Icons.lock_outline_rounded, size: 18, color: C.muted),
          ]),
        ),
        const SizedBox(height: 4),
        Text(tr('Only the PhilSys ID is accepted.', 'PhilSys ID lang ang tinatanggap.', 'PhilSys ID lang ang ginabaton.'),
            style: sans(12.5, color: C.muted)),
      ]);
}

/// Front + back photo of the PhilSys ID, used for the ID photocopy sheet.
/// Take a photo (phones, with the alignment guide) or choose a picture file.
/// [required] (default on): the surrounding Form won't validate until BOTH
/// photos are added, so the tanod can't be added without the ID.
class IdPhotoPicker extends StatefulWidget {
  final Uint8List? front, back;
  final bool required;
  final void Function(Uint8List? front, Uint8List? back) onChanged;
  const IdPhotoPicker({super.key, this.front, this.back, this.required = true, required this.onChanged});

  @override
  State<IdPhotoPicker> createState() => _IdPhotoPickerState();
}

class _IdPhotoPickerState extends State<IdPhotoPicker> {
  late Uint8List? _front = widget.front;
  late Uint8List? _back = widget.back;
  bool _busy = false;
  final _fieldKey = GlobalKey<FormFieldState<bool>>();

  // Flag: are both sides of the ID uploaded?
  bool get _hasBoth => _front != null && _back != null;

  String _sideName(bool front) => front ? tr('Front', 'Harap', 'Atubangan') : tr('Back', 'Likod', 'Likod');

  void _set(bool front, Uint8List? bytes) {
    setState(() => front ? _front = bytes : _back = bytes);
    widget.onChanged(_front, _back);
    // Update the form's flag; clear the red error once both photos are in
    final field = _fieldKey.currentState;
    if (field != null) {
      field.didChange(_hasBoth);
      if (field.hasError) field.validate();
    }
  }

  Future<void> _take(bool front) async {
    final photo = await Navigator.push<XFile>(
      context,
      MaterialPageRoute(
          builder: (_) => IdCameraScreen(
              title: front ? tr('Front of the ID', 'Harap ng ID', 'Atubangan sang ID') : tr('Back of the ID', 'Likod ng ID', 'Likod sang ID'))),
    );
    if (photo == null || !mounted) return;
    setState(() => _busy = true);
    final card = await compute(cropToGuide, await photo.readAsBytes());
    if (!mounted) return;
    setState(() => _busy = false);
    _set(front, card);
    _saved(front);
  }

  Future<void> _choose(bool front) async {
    try {
      final f = await chooseFileUpload();
      if (f == null || !mounted) return;
      if (f.isPdf) {
        notify(
            context,
            tr('Please choose a picture (JPG or PNG) of the ID, not a PDF.', 'Pumili ng litrato (JPG o PNG) ng ID, hindi PDF.',
                'Palihog pilia ang litrato (JPG ukon PNG) sang ID, indi PDF.'),
            type: NotifyType.warning,
            title: tr('Picture needed', 'Litrato ang kailangan', 'Litrato ang kinahanglan'));
        return;
      }
      _set(front, f.bytes);
      _saved(front);
    } catch (e) {
      if (mounted) notify(context, tr('Couldn’t open that: $e', 'Hindi mabuksan: $e', 'Indi mabuksan: $e'), type: NotifyType.error);
    }
  }

  void _saved(bool front) => notify(
        context,
        front
            ? tr('Front of the ID saved.', 'Na-save ang harap ng ID.', 'Na-save ang atubangan sang ID.')
            : tr('Back of the ID saved.', 'Na-save ang likod ng ID.', 'Na-save ang likod sang ID.'),
        title: tr('Photo saved', 'Na-save ang litrato', 'Na-save ang litrato'),
      );

  Widget _slot(bool front, {bool error = false}) {
    final bytes = front ? _front : _back;
    final missing = error && bytes == null;
    final btn = OutlinedButton.styleFrom(
      foregroundColor: C.navy,
      side: const BorderSide(color: C.line, width: 1.5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      minimumSize: const Size(0, 38),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bytes == null ? Colors.white : C.greenSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: missing ? C.red : (bytes == null ? C.line : const Color(0xFFBFE5D1)), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(bytes == null ? Icons.credit_card_outlined : Icons.check_circle, size: 18, color: bytes == null ? C.muted : C.green),
          const SizedBox(width: 6),
          Expanded(child: Text(_sideName(front), style: sans(14.5, w: FontWeight.w700, color: C.navy))),
          if (bytes != null)
            InkWell(
              onTap: () {
                _set(front, null);
                notify(context, tr('${_sideName(front)} photo removed.', 'Inalis ang litrato (${_sideName(front)}).', 'Ginkuha ang litrato (${_sideName(front)}).'),
                    type: NotifyType.info);
              },
              child: const Icon(Icons.close_rounded, size: 18, color: C.muted),
            ),
        ]),
        const SizedBox(height: 8),
        if (bytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(aspectRatio: 85.6 / 54, child: Image.memory(bytes, fit: BoxFit.cover)),
          )
        else
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (hasCamera)
              OutlinedButton.icon(
                style: btn,
                onPressed: _busy ? null : () => _take(front),
                icon: const Icon(Icons.photo_camera_outlined, size: 16),
                label: Text(tr('Take photo', 'Kunan', 'Kuhai'), style: sans(13.5, w: FontWeight.w600, color: C.navy)),
              ),
            OutlinedButton.icon(
              style: btn,
              onPressed: _busy ? null : () => _choose(front),
              icon: const Icon(Icons.upload_file_rounded, size: 16),
              label: Text(tr('Upload', 'I-upload', 'I-upload'), style: sans(13.5, w: FontWeight.w600, color: C.navy)),
            ),
          ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => FormField<bool>(
        key: _fieldKey,
        initialValue: _hasBoth,
        validator: (_) => widget.required && !_hasBoth
            ? (_front == null && _back == null
                ? tr('Upload the front and back of the PhilSys ID.', 'I-upload ang harap at likod ng PhilSys ID.',
                    'I-upload ang atubangan kag likod sang PhilSys ID.')
                : _front == null
                    ? tr('Upload the front of the ID too.', 'I-upload din ang harap ng ID.', 'I-upload man ang atubangan sang ID.')
                    : tr('Upload the back of the ID too.', 'I-upload din ang likod ng ID.', 'I-upload man ang likod sang ID.'))
            : null,
        builder: (state) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FieldLabel(tr('Photo of the PhilSys ID', 'Litrato ng PhilSys ID', 'Litrato sang PhilSys ID'), required: widget.required),
          Text(
            tr('Front and back, for the ID photocopy sheet.', 'Harap at likod, para sa ID photocopy sheet.',
                'Atubangan kag likod, para sa ID photocopy sheet.'),
            style: sans(13, color: C.muted, h: 1.4),
          ),
          const SizedBox(height: 8),
          if (_busy) const LinearProgressIndicator(minHeight: 3),
          LayoutBuilder(builder: (context, box) {
            final two = box.maxWidth >= 340;
            final err = state.hasError;
            return two
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: _slot(true, error: err)),
                    const SizedBox(width: 10),
                    Expanded(child: _slot(false, error: err)),
                  ])
                : Column(children: [_slot(true, error: err), const SizedBox(height: 10), _slot(false, error: err)]);
          }),
          if (state.hasError) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.error_outline_rounded, size: 16, color: C.red),
              const SizedBox(width: 6),
              Expanded(child: Text(state.errorText!, style: sans(13, w: FontWeight.w600, color: C.red))),
            ]),
          ],
        ]),
      );
}