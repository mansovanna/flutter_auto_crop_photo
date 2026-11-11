import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import '../services/quad.dart';
import '../services/scan_processor.dart';
import '../widgets/crop_editor.dart';
import '../widgets/filter_strip.dart';
import 'saved_screen.dart';

/// The scan editor: everything after taking or picking a photo happens here.
///
/// * The page's corners are detected automatically; drag to fine-tune.
/// * Pick a filter (previewed on the photo).
/// * Rotate left / right.
/// * Save: the page is flattened, filtered and saved to the gallery.
class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.photoBytes});

  final Uint8List photoBytes;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  final FilterPreviews _filters = FilterPreviews();

  /// The photo (in its current rotation) with its detected corners.
  ScanAnalysis? _scan;
  Object? _error;

  /// Corners as adjusted by the user; null = use the detected ones.
  List<Offset>? _corners;
  bool _busy = false; // rotating or saving

  @override
  void initState() {
    super.initState();
    _filters.addListener(_onFiltersChanged);
    _analyze();
  }

  @override
  void dispose() {
    _filters
      ..removeListener(_onFiltersChanged)
      ..dispose();
    super.dispose();
  }

  void _onFiltersChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _analyze() async {
    try {
      final scan = await ScanJobs.analyze(widget.photoBytes);
      if (!mounted) return;
      setState(() => _scan = scan);
      _filters.load(scan.preview, originalJpeg: scan.previewJpeg);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _rotate({required bool clockwise}) async {
    final scan = _scan;
    if (scan == null || _busy) return;
    setState(() => _busy = true);
    try {
      final rotated = await ScanJobs.rotate(scan, clockwise: clockwise);
      if (!mounted) return;
      setState(() {
        // Keep the user's adjustments: rotate them along with the photo.
        _corners = _corners == null
            ? null
            : Quad.rotate(_corners!, scan.size, clockwise: clockwise);
        _scan = rotated;
      });
      _filters.load(rotated.preview, originalJpeg: rotated.previewJpeg);
    } catch (e) {
      _snack('Could not rotate: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(ScanAnalysis scan, List<Offset> corners) async {
    setState(() => _busy = true);
    try {
      final jpg = await ScanJobs.cropAndRender(scan.image, corners, _filters.selected);

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/scan_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(jpg);
      if (!await Gal.hasAccess()) {
        await Gal.requestAccess();
      }
      await Gal.putImage(file.path, album: 'AutoCrop');

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SavedScreen(bytes: jpg)),
      );
    } on GalException catch (e) {
      _snack('Could not save to gallery: ${e.type.message}');
    } catch (e) {
      _snack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Adjust & enhance'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Text(
          'Could not process photo:\n$_error',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
      );
    }
    final scan = _scan;
    if (scan == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Detecting document edges…', style: TextStyle(color: Colors.white)),
          ],
        ),
      );
    }

    final corners = _corners ?? scan.corners;
    final valid = Quad.isValid(corners, minArea: 100);
    final colors = Theme.of(context).colorScheme;

    final String message;
    final Color messageColor;
    if (!valid) {
      message = 'Corners overlap — drag them back to the page corners.';
      messageColor = colors.error;
    } else if (!scan.detected) {
      message = 'Using the whole image — drag the corners to crop.';
      messageColor = Colors.amber;
    } else {
      message = 'Document detected. Drag corners or edges to fine-tune.';
      messageColor = Colors.white70;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(message, textAlign: TextAlign.center, style: TextStyle(color: messageColor)),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Stack(
              alignment: Alignment.center,
              children: [
                CropEditor(
                  imageBytes: _filters.shown ?? scan.previewJpeg,
                  imageSize: scan.size,
                  corners: corners,
                  onChanged: (c) => setState(() => _corners = c),
                ),
                if (_busy || _filters.isComputingSelected)
                  const IgnorePointer(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ),
        FilterStrip(previews: _filters),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 16, 16),
            child: Row(
              children: [
                _ToolButton(
                  icon: Icons.auto_fix_high,
                  label: 'Auto',
                  onPressed: () => setState(() => _corners = null),
                ),
                _ToolButton(
                  icon: Icons.fullscreen,
                  label: 'All',
                  onPressed: () => setState(() => _corners = Quad.fullImage(scan.size)),
                ),
                _ToolButton(
                  icon: Icons.rotate_left,
                  label: 'Left',
                  onPressed: _busy ? null : () => _rotate(clockwise: false),
                ),
                _ToolButton(
                  icon: Icons.rotate_right,
                  label: 'Right',
                  onPressed: _busy ? null : () => _rotate(clockwise: true),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: !valid || _busy ? null : () => _save(scan, corners),
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_alt),
                  label: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(52, 48),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon), const SizedBox(height: 2), Text(label, style: const TextStyle(fontSize: 12))],
      ),
    );
  }
}
