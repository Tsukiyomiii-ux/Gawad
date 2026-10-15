import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'package:tanod_incentives/theme.dart';

// Shows the REAL PDF (the same file the Download button saves) as page images,
// so the preview always matches the printed document.
//
//   PdfPages(cacheKey: 'payroll|…', build: () => buildOfficialPdf(rec, k))
//   PdfPages(..., thumbnail: true)   → first page only, small (document cards)
//
// [cacheKey] must change whenever the content changes (tanods, names, year…).
// Pages already drawn for a key are reused, so redraws are instant.

final Map<String, List<Uint8List>> _cache = {};

class PdfPages extends StatefulWidget {
  final String cacheKey;
  final Future<Uint8List> Function() build;
  final bool thumbnail;

  const PdfPages({super.key, required this.cacheKey, required this.build, this.thumbnail = false});

  @override
  State<PdfPages> createState() => _PdfPagesState();
}

class _PdfPagesState extends State<PdfPages> {
  List<Uint8List>? _pages;
  bool _failed = false;
  String? _wanted; // the key being drawn now (older results are ignored)

  String get _key => '${widget.cacheKey}|${widget.thumbnail ? 'thumb' : 'full'}';

  @override
  void initState() {
    super.initState();
    _pages = _cache[_key];
    if (_pages == null) _draw(delay: false);
  }

  @override
  void didUpdateWidget(covariant PdfPages old) {
    super.didUpdateWidget(old);
    if (old.cacheKey != widget.cacheKey || old.thumbnail != widget.thumbnail) {
      final hit = _cache[_key];
      if (hit != null) {
        _pages = hit;
        _wanted = null;
      } else {
        _draw(delay: true); // keep showing the old pages until the new ones are ready
      }
    }
  }

  Future<void> _draw({required bool delay}) async {
    final key = _key;
    _wanted = key;
    // While typing, wait a moment so we don't redraw on every letter
    if (delay) await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted || _wanted != key) return;
    try {
      final bytes = await widget.build();
      final out = <Uint8List>[];
      await for (final page in Printing.raster(
        bytes,
        pages: widget.thumbnail ? const [0] : null,
        dpi: widget.thumbnail ? 50 : 130,
      )) {
        out.add(await page.toPng());
      }
      if (_cache.length > 60) _cache.clear(); // keep memory small
      _cache[key] = out;
      if (mounted && _wanted == key) {
        setState(() {
          _pages = out;
          _failed = false;
        });
      }
    } catch (e) {
      debugPrint('PDF preview failed: $e');
      if (mounted && _wanted == key) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    if (pages == null || pages.isEmpty) {
      // Same size as a page, so the layout doesn't jump while loading
      return AspectRatio(
        aspectRatio: 210 / 297,
        child: Container(
          color: Colors.white,
          alignment: Alignment.center,
          child: _failed
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr('Preview not available. Download the PDF to see it.', 'Hindi ma-preview. I-download ang PDF.',
                      'Indi ma-preview. I-download ang PDF.'), textAlign: TextAlign.center, style: sans(16, color: C.muted)),
                )
              : const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3)),
        ),
      );
    }
    if (widget.thumbnail) {
      return Image.memory(pages.first, fit: BoxFit.fitWidth, alignment: Alignment.topCenter, gaplessPlayback: true);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < pages.length; i++) ...[
        if (i > 0) const SizedBox(height: 18),
        Container(
          decoration: BoxDecoration(color: Colors.white, boxShadow: [
            BoxShadow(color: C.navy.withValues(alpha: .12), blurRadius: 8, offset: const Offset(0, 2)),
          ]),
          child: Image.memory(pages[i], fit: BoxFit.fitWidth, gaplessPlayback: true),
        ),
      ],
    ]);
  }
}