import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/gallery_picker.dart';
import 'crop_screen.dart';

/// Live camera preview with a capture button. A captured photo is handed to
/// [CropScreen], which auto-detects the crop.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  static const routeName = '/camera';

  static Route<void> route() => MaterialPageRoute(
        settings: const RouteSettings(name: routeName),
        builder: (_) => const CameraScreen(),
      );

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  CameraController? _controller;
  FlashMode _flash = FlashMode.off;
  bool _capturing = false;
  String? _error;

  /// True while a later step (crop, enhance, ...) is on top. The camera is
  /// released then, so it is not running (or using battery) in the background.
  bool _away = false;

  /// Guards against two overlapping starts (e.g. a resume event while the
  /// first start is still waiting on the permission dialog).
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_away || _cameras.isEmpty) return;
    if (state == AppLifecycleState.inactive) {
      _stopCamera();
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _startCamera(_cameras[_cameraIndex]);
    }
  }

  Future<void> _stopCamera() async {
    final controller = _controller;
    if (controller == null) return;
    _controller = null;
    if (mounted) setState(() {});
    await controller.dispose();
  }

  Future<void> _setup() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _error = 'No camera found on this device.');
        return;
      }
      final back = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      _cameraIndex = back >= 0 ? back : 0;
      await _startCamera(_cameras[_cameraIndex]);
    } on CameraException catch (e) {
      setState(() => _error = _describe(e));
    }
  }

  Future<void> _startCamera(CameraDescription camera) async {
    if (_starting) return;
    _starting = true;
    try {
      await _stopCamera();

      final controller = CameraController(
        camera,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      try {
        await controller.initialize();
        await controller.setFlashMode(_flash);
        // Left the screen (or went to the next step) while starting.
        if (!mounted || _away) {
          await controller.dispose();
          return;
        }
        setState(() {
          _controller = controller;
          _error = null;
        });
      } on CameraException catch (e) {
        await controller.dispose();
        if (mounted) setState(() => _error = _describe(e));
      }
    } finally {
      _starting = false;
    }
  }

  String _describe(CameraException e) => switch (e.code) {
        'CameraAccessDenied' ||
        'CameraAccessDeniedWithoutPrompt' ||
        'CameraAccessRestricted' =>
          'Camera permission is required. Enable it in system settings.',
        _ => 'Camera error: ${e.description ?? e.code}',
      };

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      await _openCrop(bytes);
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_describe(e))));
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      final bytes = await GalleryPicker.pick(context);
      if (bytes == null || !mounted) return;
      await _openCrop(bytes);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// Goes to step 2 with [bytes]. The camera is turned off while away and
  /// restarted on return ("Scan another", or back from step 2).
  Future<void> _openCrop(Uint8List bytes) async {
    _away = true;
    await _stopCamera();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CropScreen(photoBytes: bytes)),
    );
    _away = false;
    if (mounted && _cameras.isNotEmpty) {
      await _startCamera(_cameras[_cameraIndex]);
    }
  }

  Future<void> _toggleFlash() async {
    final next = _flash == FlashMode.off ? FlashMode.torch : FlashMode.off;
    try {
      await _controller?.setFlashMode(next);
      setState(() => _flash = next);
    } on CameraException catch (_) {
      // Front cameras often have no flash; ignore.
    }
  }

  void _switchCamera() {
    if (_cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    _startCamera(_cameras[_cameraIndex]);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: 'Back',
                  color: Colors.white,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                ),
                IconButton(
                  tooltip: 'Flash',
                  color: Colors.white,
                  onPressed: controller == null ? null : _toggleFlash,
                  icon: Icon(_flash == FlashMode.off ? Icons.flash_off : Icons.flash_on),
                ),
              ],
            ),
            Expanded(
              child: Center(
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      )
                    : controller == null || !controller.value.isInitialized
                        ? const CircularProgressIndicator()
                        : _Preview(controller: controller),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: 'Choose from gallery',
                    color: Colors.white,
                    iconSize: 30,
                    // Works even without a camera (e.g. permission denied).
                    onPressed: _capturing ? null : _pickFromGallery,
                    icon: const Icon(Icons.photo_library),
                  ),
                  _ShutterButton(busy: _capturing, onPressed: controller == null ? null : _capture),
                  IconButton(
                    tooltip: 'Switch camera',
                    color: Colors.white,
                    iconSize: 30,
                    onPressed: _cameras.length < 2 ? null : _switchCamera,
                    icon: const Icon(Icons.cameraswitch),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        CameraPreview(controller),
        // Framing hint only; detection runs on the full photo.
        IgnorePointer(
          child: FractionallySizedBox(
            widthFactor: 0.85,
            heightFactor: 0.7,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white54, width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const Positioned(
          top: 12,
          child: Text(
            'Place the document on a contrasting background',
            style: TextStyle(color: Colors.white, shadows: [Shadow(blurRadius: 4)]),
          ),
        ),
      ],
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onPressed,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        padding: const EdgeInsets.all(5),
        child: busy
            ? const CircularProgressIndicator(color: Colors.white)
            : const DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white),
              ),
      ),
    );
  }
}
