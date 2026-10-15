// ID camera with an alignment guide.
//
// Shows an ID-card-shaped frame over the live camera. A few times a second it
// checks the camera image for the card's 4 edges sitting on the frame's 4
// edges. Only when all 4 line up (and stay lined up for a moment) does the
// frame turn green and the shutter button unlock.
//
// Returns the photo as an XFile (same type image_picker returns), or null if
// the person backs out.
//
// Tip for best results: put the ID on a plain, darker surface (table, folder)
// so its edges stand out.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:image/image.dart' as img;
import 'package:tanod_incentives/widgets/notify.dart'; // top pop-ups

/// Set to true to show a small "Take anyway" button after a while, for
/// demos where the edge check struggles (e.g. a white card on a white table).
const bool kAllowCaptureAnyway = false;

/// Crops a photo taken with [IdCameraScreen] to the guide frame (plus a small
/// margin), so the result is just the card: used for the ID photocopy.
/// Top-level so it can run with compute() in the background.
Uint8List cropToGuide(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final photo = img.bakeOrientation(decoded); // apply the camera's rotation
  final w = photo.width, h = photo.height;
  final cw = math.min(w.toDouble(), w * _guideWidth * 1.04); // 4% margin around the frame
  final ch = math.min(h.toDouble(), cw / _cardRatio);
  final card = img.copyCrop(
    photo,
    x: ((w - cw) / 2).round(),
    y: ((h - ch) / 2).round(),
    width: cw.round(),
    height: ch.round(),
  );
  return Uint8List.fromList(img.encodeJpg(card, quality: 92));
}

/// PhilID is an ID-1 card: 85.6 x 54 mm.
const double _cardRatio = 85.6 / 54;

/// How wide the guide is, as a share of the preview width.
const double _guideWidth = 0.86;

class IdCameraScreen extends StatefulWidget {
  /// Shown at the top, e.g. "Front of the ID".
  final String title;
  const IdCameraScreen({super.key, this.title = 'Scan the ID'});

  @override
  State<IdCameraScreen> createState() => _IdCameraScreenState();
}

class _IdCameraScreenState extends State<IdCameraScreen> {
  CameraController? _cam;
  String? _error;

  // Alignment state
  List<bool> _edges = [false, false, false, false]; // top, right, bottom, left
  int _alignedFrames = 0; // consecutive frames with all 4 edges found
  bool _busy = false; // analysing a frame
  bool _taking = false; // taking the picture
  DateTime _lastCheck = DateTime.fromMillisecondsSinceEpoch(0);
  final DateTime _openedAt = DateTime.now();

  bool get _ready => _alignedFrames >= 3; // ≈ half a second of steady alignment

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final cam = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await cam.initialize();
      await cam.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted) {
        await cam.dispose();
        return;
      }
      setState(() => _cam = cam);
      await cam.startImageStream(_onFrame);
    } catch (e) {
      if (mounted) setState(() => _error = 'Camera not available: $e');
    }
  }

  @override
  void dispose() {
    final cam = _cam;
    _cam = null;
    if (cam != null) {
      if (cam.value.isStreamingImages) cam.stopImageStream().catchError((_) {});
      cam.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Frame analysis
  // ---------------------------------------------------------------------------

  void _onFrame(CameraImage img) {
    final now = DateTime.now();
    if (_busy || _taking || now.difference(_lastCheck).inMilliseconds < 150) return;
    _busy = true;
    _lastCheck = now;
    try {
      final edges = _findEdges(img, _cam!.description.sensorOrientation);
      final all = edges.every((e) => e);
      if (!mounted) return;
      setState(() {
        _edges = edges;
        _alignedFrames = all ? _alignedFrames + 1 : 0;
      });
    } catch (_) {
      // A bad frame is simply skipped
    } finally {
      _busy = false;
    }
  }

  /// Checks the camera image for strong edges along each side of the guide.
  /// Returns [top, right, bottom, left] as seen on the (portrait) screen.
  List<bool> _findEdges(CameraImage img, int sensorOrientation) {
    final plane = img.planes.first;
    final bytes = plane.bytes;
    final stride = plane.bytesPerRow;
    final px = plane.bytesPerPixel ?? 1; // 1 for Android Y plane, 4 for iOS BGRA
    final lumaOffset = px == 4 ? 1 : 0; // use green as brightness on iOS
    final w = img.width, h = img.height;

    int lum(int x, int y) {
      x = x.clamp(0, w - 1);
      y = y.clamp(0, h - 1);
      return bytes[y * stride + x * px + lumaOffset];
    }

    // The preview is shown in portrait. On most phones the sensor image is
    // landscape (rotated 90°), so screen-horizontal = image-vertical.
    final rotated = sensorOrientation == 90 || sensorOrientation == 270;
    final previewAspect = rotated ? w / h : h / w; // preview height / width on screen

    // Guide rectangle in screen-normalised coordinates (0..1), centred
    final gw = _guideWidth;
    final gh = _guideWidth / _cardRatio / previewAspect;

    // Convert a screen-normalised point (u across, v down) to image pixels.
    // The guide is centred and symmetric, so mirror direction doesn't matter.
    (int, int) toImg(double u, double v) =>
        rotated ? ((v * w).round(), (u * h).round()) : ((u * w).round(), (v * h).round());

    // Search band around each guide edge, and the contrast needed
    const samples = 22;
    const band = 0.035; // how far off the guide line the card edge may be (share of screen)
    const minContrast = 22; // brightness jump that counts as an edge
    const needShare = 0.6; // share of samples that must hit

    bool edgeAlong({required bool horizontal, required double fixed, required double from, required double to}) {
      var hits = 0;
      for (var i = 0; i < samples; i++) {
        final t = from + (to - from) * (i + 0.5) / samples;
        var best = 0;
        // Walk across the guide line and look for the strongest brightness jump
        for (var k = -band; k <= band; k += band / 8) {
          final (ax, ay) = horizontal ? toImg(t, fixed + k - 0.006) : toImg(fixed + k - 0.006, t);
          final (bx, by) = horizontal ? toImg(t, fixed + k + 0.006) : toImg(fixed + k + 0.006, t);
          final d = (lum(ax, ay) - lum(bx, by)).abs();
          if (d > best) best = d;
        }
        if (best >= minContrast) hits++;
      }
      return hits >= samples * needShare;
    }

    final left = 0.5 - gw / 2, right = 0.5 + gw / 2;
    final top = 0.5 - gh / 2, bottom = 0.5 + gh / 2;
    // Sample the middle 70% of each side (corners are rounded on the card)
    final ix = gw * 0.15, iy = gh * 0.15;

    return [
      edgeAlong(horizontal: true, fixed: top, from: left + ix, to: right - ix),
      edgeAlong(horizontal: false, fixed: right, from: top + iy, to: bottom - iy),
      edgeAlong(horizontal: true, fixed: bottom, from: left + ix, to: right - ix),
      edgeAlong(horizontal: false, fixed: left, from: top + iy, to: bottom - iy),
    ];
  }

  // ---------------------------------------------------------------------------
  // Capture
  // ---------------------------------------------------------------------------

  Future<void> _take() async {
    final cam = _cam;
    if (cam == null || _taking) return;
    setState(() => _taking = true);
    try {
      if (cam.value.isStreamingImages) await cam.stopImageStream();
      final photo = await cam.takePicture();
      if (mounted) Navigator.pop(context, photo);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _taking = false;
        _alignedFrames = 0;
      });
      notify(context, 'Could not take the photo: $e', type: NotifyType.error);
      // Resume checking
      if (!cam.value.isStreamingImages) cam.startImageStream(_onFrame);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  String get _hint {
    if (_ready) return 'Hold still… ready';
    final found = _edges.where((e) => e).length;
    if (found == 0) return 'Place the ID inside the frame';
    if (found < 4) {
      const names = ['top', 'right', 'bottom', 'left'];
      final missing = [for (var i = 0; i < 4; i++) if (!_edges[i]) names[i]];
      return 'Line up the ${missing.join(', ')} edge${missing.length == 1 ? '' : 's'} with the frame';
    }
    return 'Hold still…';
  }

  @override
  Widget build(BuildContext context) {
    final cam = _cam;
    final showAnyway = kAllowCaptureAnyway && DateTime.now().difference(_openedAt).inSeconds > 12;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
              ),
            )
          : cam == null || !cam.value.isInitialized
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : Column(children: [
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        // Portrait preview: height / width = camera aspect
                        aspectRatio: 1 / cam.value.aspectRatio,
                        child: Stack(fit: StackFit.expand, children: [
                          CameraPreview(cam),
                          CustomPaint(painter: _GuidePainter(edges: _edges, ready: _ready)),
                        ]),
                      ),
                    ),
                  ),
                  Container(
                    color: Colors.black,
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                    child: Column(children: [
                      Text(
                        _hint,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _ready ? const Color(0xFF7CE0A8) : Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tip: put the ID on a plain dark surface, avoid glare.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60, fontSize: 12.5),
                      ),
                      const SizedBox(height: 16),
                      // Shutter: locked until the card is aligned
                      GestureDetector(
                        onTap: _ready && !_taking ? _take : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 74,
                          height: 74,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _ready ? Colors.white : Colors.white24,
                            border: Border.all(color: _ready ? const Color(0xFF1E9E6A) : Colors.white38, width: 5),
                          ),
                          child: _taking
                              ? const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: CircularProgressIndicator(strokeWidth: 3),
                                )
                              : Icon(_ready ? Icons.camera_alt_rounded : Icons.lock_outline_rounded,
                                  color: _ready ? Colors.black87 : Colors.white54),
                        ),
                      ),
                      if (showAnyway)
                        TextButton(
                          onPressed: _taking ? null : _take,
                          child: const Text('Take anyway', style: TextStyle(color: Colors.white54)),
                        ),
                    ]),
                  ),
                ]),
    );
  }
}

/// Darkens everything outside the card frame and draws the frame.
/// Each side turns green when its edge is found; all green = ready.
class _GuidePainter extends CustomPainter {
  final List<bool> edges; // top, right, bottom, left
  final bool ready;
  _GuidePainter({required this.edges, required this.ready});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * _guideWidth;
    final h = w / _cardRatio;
    final rect = Rect.fromCenter(center: size.center(Offset.zero), width: w, height: h);
    final r = RRect.fromRectAndRadius(rect, Radius.circular(w * 0.04));

    // Dim outside the frame
    final shade = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(r)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(shade, Paint()..color = Colors.black.withValues(alpha: .55));

    // Grid inside the frame (thirds)
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .25)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = rect.left + rect.width * i / 3;
      final y = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), grid);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
    }

    // Frame sides
    const green = Color(0xFF2BD47F);
    final stroke = math.max(3.0, size.width * 0.009);
    Paint side(bool ok) => Paint()
      ..color = ready ? green : (ok ? green : Colors.white)
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(rect.topLeft, rect.topRight, side(edges[0]));
    canvas.drawLine(rect.topRight, rect.bottomRight, side(edges[1]));
    canvas.drawLine(rect.bottomLeft, rect.bottomRight, side(edges[2]));
    canvas.drawLine(rect.topLeft, rect.bottomLeft, side(edges[3]));
  }

  @override
  bool shouldRepaint(covariant _GuidePainter old) =>
      old.ready != ready || !listEquals(old.edges, edges);
}