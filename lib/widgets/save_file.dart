import 'dart:io' show Directory, File, Platform;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'package:tanod_incentives/theme.dart';
import 'package:tanod_incentives/widgets/notify.dart';

// Downloads a PDF straight away, no preview:
//   Web      -> the browser downloads it (like any download link)
//   Desktop  -> saved in the Downloads folder
//   Android  -> saved in the phone's Download folder
//   iPhone   -> no Downloads folder, so the "Save to Files" sheet opens
// A top pop-up says where it went.

Future<void> downloadPdfBytes(BuildContext context, Uint8List bytes, String fileName) async {
  final name = _safeName(fileName);
  try {
    if (kIsWeb) {
      await XFile.fromData(bytes, mimeType: 'application/pdf', name: name).saveTo(name);
      if (context.mounted) _done(context, name, tr('your browser’s Downloads', 'Downloads ng browser', 'Downloads sang browser'));
      return;
    }

    final dir = _downloadsDir();
    if (dir == null) {
      // iPhone (or unknown): let the person pick where to save it
      await Printing.sharePdf(bytes: bytes, filename: name);
      return;
    }

    final path = _freePath(dir, name);
    await File(path).writeAsBytes(bytes, flush: true);
    if (context.mounted) _done(context, path.split(Platform.pathSeparator).last, tr('Downloads', 'Downloads', 'Downloads'));
  } catch (_) {
    // e.g. older Android blocks the Download folder: fall back to the share/save sheet
    try {
      await Printing.sharePdf(bytes: bytes, filename: name);
    } catch (e) {
      if (context.mounted) {
        notify(context, tr('Couldn’t save the file: $e', 'Hindi ma-save ang file: $e', 'Indi ma-save ang file: $e'),
            type: NotifyType.error, title: tr('Download failed', 'Hindi na-download', 'Wala na-download'));
      }
    }
  }
}

/// Builds the PDF first (shows "Downloading…"), then saves it.
Future<void> downloadPdf(BuildContext context, Future<Uint8List> Function() build, String fileName) async {
  notify(context, fileName, type: NotifyType.info, title: tr('Downloading…', 'Dina-download…', 'Gina-download…'));
  final bytes = await build();
  if (!context.mounted) return;
  await downloadPdfBytes(context, bytes, fileName);
}

void _done(BuildContext context, String name, String where) => notify(
      context,
      tr('$name was saved to $where.', 'Na-save ang $name sa $where.', 'Na-save ang $name sa $where.'),
      title: tr('Downloaded', 'Na-download', 'Na-download'),
    );

String? _downloadsDir() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      const d = '/storage/emulated/0/Download';
      return Directory(d).existsSync() ? d : null;
    case TargetPlatform.windows:
      final home = Platform.environment['USERPROFILE'];
      return home == null ? null : '$home\\Downloads';
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
      final home = Platform.environment['HOME'];
      return home == null ? null : '$home/Downloads';
    default:
      return null; // iOS
  }
}

// "Payroll.pdf" -> "Payroll (1).pdf" if it already exists, so nothing is overwritten
String _freePath(String dir, String name) {
  final sep = Platform.pathSeparator;
  Directory(dir).createSync(recursive: true);
  var path = '$dir$sep$name';
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  for (var i = 1; File(path).existsSync(); i++) {
    path = '$dir$sep$base ($i)$ext';
  }
  return path;
}

String _safeName(String n) => n.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');