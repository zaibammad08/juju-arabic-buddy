// In-app camera for the Magic World games (Detective, Feed Juju, Playdough).
//
// Why: ImagePicker opens the phone's own camera app. On Android that can make
// the system close our app while the camera is open, so after the photo the
// child lands back on the Home screen. This page keeps the camera inside the
// app (same `camera` package as Treasure Hunt), so that can't happen.
//
// Golden rule 7: the photo file is deleted at once; only bytes stay in memory.
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Opens the in-app camera. Returns the photo bytes, or null if cancelled
/// or no camera is available.
Future<Uint8List?> snapPhoto(BuildContext context) {
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(
        fullscreenDialog: true, builder: (_) => const _QuickCamera()),
  );
}

class _QuickCamera extends StatefulWidget {
  const _QuickCamera();
  @override
  State<_QuickCamera> createState() => _QuickCameraState();
}

class _QuickCameraState extends State<_QuickCamera>
    with WidgetsBindingObserver {
  CameraController? _cam;
  bool _failed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw CameraException('none', 'No camera');
      final back = cams.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cams.first);
      final c = CameraController(back, ResolutionPreset.medium,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await c.initialize();
      try {
        await c.setFlashMode(FlashMode.off);
      } catch (_) {}
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() => _cam = c);
    } catch (e) {
      debugPrint('QuickCamera init failed: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  // Release the camera when the app goes to the background, re-open on return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _cam;
    if (state == AppLifecycleState.inactive && c != null) {
      _cam = null;
      c.dispose();
    } else if (state == AppLifecycleState.resumed && _cam == null && !_failed) {
      _init();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cam?.dispose();
    super.dispose();
  }

  Future<void> _shoot() async {
    final c = _cam;
    if (c == null || _busy || !c.value.isInitialized) return;
    setState(() => _busy = true);
    try {
      final shot = await c.takePicture();
      final bytes = await shot.readAsBytes();
      try {
        await File(shot.path).delete();
      } catch (_) {}
      if (mounted) Navigator.of(context).pop(bytes);
    } catch (e) {
      debugPrint('QuickCamera takePicture failed: $e');
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _cam;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          Positioned.fill(
            child: _failed
                ? const Center(
                    child: Text('The camera is not available.',
                        style: TextStyle(color: Colors.white, fontSize: 18)))
                : c == null || !c.value.isInitialized
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white))
                    : Center(
                        child: AspectRatio(
                          aspectRatio: 1 / c.value.aspectRatio,
                          child: CameraPreview(c),
                        ),
                      ),
          ),
          // close
          Positioned(
            top: 12,
            left: 12,
            child: Semantics(
              button: true,
              label: 'Close camera',
              child: IconButton.filled(
                style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    minimumSize: const Size(56, 56)),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded,
                    color: Colors.black, size: 30),
              ),
            ),
          ),
          // big shutter button for small hands
          if (c != null && !_failed)
            Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: Center(
                child: Semantics(
                  button: true,
                  label: 'Take the photo',
                  child: GestureDetector(
                    onTap: _shoot,
                    child: Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _busy ? Colors.white54 : Colors.white,
                        border: Border.all(
                            color: const Color(0xFF1FA97A), width: 7),
                      ),
                      child: _busy
                          ? const Padding(
                              padding: EdgeInsets.all(26),
                              child: CircularProgressIndicator(strokeWidth: 4))
                          : const Icon(Icons.photo_camera_rounded,
                              size: 40, color: Color(0xFF1FA97A)),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
