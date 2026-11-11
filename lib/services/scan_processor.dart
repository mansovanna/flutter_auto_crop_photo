import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

import 'package:image/image.dart' as img;

import 'doc_filters.dart';
import 'document_detector.dart';
import 'perspective.dart';
import 'quad.dart';
import 'scan_image.dart';

/// Result of analysing a captured photo.
class ScanAnalysis {
  const ScanAnalysis({
    required this.image,
    required this.preview,
    required this.previewJpeg,
    required this.corners,
    required this.detected,
  });

  /// Full-resolution photo with EXIF orientation applied.
  final ScanImage image;

  /// Screen-sized copy of [image] (same aspect ratio), used as the base for
  /// filter previews.
  final ScanImage preview;

  /// [preview] encoded as JPEG for display.
  final Uint8List previewJpeg;

  /// Detected corners `[TL, TR, BR, BL]` in [image] pixels, or the full image
  /// when [detected] is false.
  final List<Offset> corners;
  final bool detected;

  Size get size => Size(image.width.toDouble(), image.height.toDouble());
}

/// Runs each [ScanProcessor] step on a background isolate.
///
/// Always go through these instead of calling `Isolate.run` from a widget:
/// a closure created inside a `State` method can capture the State itself
/// (and its Futures, BuildContext, ...), which cannot be sent to another
/// isolate ("object is unsendable"). Closures created here, in static
/// methods, only capture the plain arguments.
abstract final class ScanJobs {
  static Future<ScanAnalysis> analyze(Uint8List photoBytes) =>
      Isolate.run(() => ScanProcessor.analyze(photoBytes));

  static Future<ScanImage> warp(ScanImage image, List<Offset> corners) =>
      Isolate.run(() => ScanProcessor.warp(image, corners));

  static Future<ScanImage> previewBase(ScanImage document) =>
      Isolate.run(() => ScanProcessor.previewBase(document));

  static Future<Map<DocFilter, Uint8List>> thumbnails(ScanImage base) =>
      Isolate.run(() => ScanProcessor.thumbnails(base));

  static Future<Uint8List> preview(ScanImage base, DocFilter filter) =>
      Isolate.run(() => ScanProcessor.preview(base, filter));

  static Future<Uint8List> render(ScanImage document, DocFilter filter, int quarterTurns) =>
      Isolate.run(() => ScanProcessor.render(document, filter, quarterTurns));

  static Future<ScanAnalysis> rotate(ScanAnalysis analysis, {required bool clockwise}) =>
      Isolate.run(() => ScanProcessor.rotate(analysis, clockwise: clockwise));

  static Future<Uint8List> cropAndRender(ScanImage image, List<Offset> corners, DocFilter filter) =>
      Isolate.run(() => ScanProcessor.cropAndRender(image, corners, filter));
}

/// Entry points for the scan pipeline. Each is heavy: use [ScanJobs] to run
/// them off the UI thread.
///
/// capture -> [analyze] (detect corners) -> user adjusts -> [warp] (flatten)
/// -> [previews] (filter choices) -> [render] (final JPEG).
abstract final class ScanProcessor {
  static ScanAnalysis analyze(Uint8List photoBytes) {
    final decoded = img.decodeImage(photoBytes);
    if (decoded == null) throw const FormatException('Could not decode photo');
    final oriented = img.bakeOrientation(decoded);
    final image = ScanImage.fromImage(oriented);
    final corners = DocumentDetector.detect(oriented);
    final preview = previewBase(image);
    return ScanAnalysis(
      image: image,
      preview: preview,
      previewJpeg: preview.encodeJpg(quality: 85),
      corners: corners ?? Quad.fullImage(Size(image.width.toDouble(), image.height.toDouble())),
      detected: corners != null,
    );
  }

  static ScanImage warp(ScanImage image, List<Offset> corners) =>
      PerspectiveWarp.warp(image, corners);

  /// The same analysis with the photo turned 90°: full image, preview and
  /// detected corners are all rotated together.
  static ScanAnalysis rotate(ScanAnalysis a, {required bool clockwise}) {
    final preview = a.preview.rotated(clockwise: clockwise);
    return ScanAnalysis(
      image: a.image.rotated(clockwise: clockwise),
      preview: preview,
      previewJpeg: preview.encodeJpg(quality: 85),
      corners: Quad.rotate(a.corners, a.size, clockwise: clockwise),
      detected: a.detected,
    );
  }

  /// Flattens the page inside [corners] and applies [filter]: the final JPEG.
  static Uint8List cropAndRender(ScanImage image, List<Offset> corners, DocFilter filter) =>
      render(warp(image, corners), filter, 0);

  /// Screen-sized copy of the page that filter previews are computed from.
  static ScanImage previewBase(ScanImage document, {int maxSide = 1400}) =>
      document.downscale(maxSide);

  /// Small JPEG per filter for the filter strip.
  static Map<DocFilter, Uint8List> thumbnails(ScanImage base, {int maxSide = 240}) {
    final small = base.downscale(maxSide);
    return {
      for (final f in DocFilter.values)
        f: DocFilters.apply(small, f).encodeJpg(quality: 85),
    };
  }

  /// Screen-sized JPEG of [base] with [filter] applied.
  static Uint8List preview(ScanImage base, DocFilter filter) =>
      DocFilters.apply(base, filter).encodeJpg(quality: 88);

  /// Full-resolution output with [filter] and [quarterTurns] clockwise.
  static Uint8List render(ScanImage document, DocFilter filter, int quarterTurns) {
    var out = DocFilters.apply(document, filter).toImage();
    final turns = quarterTurns % 4;
    if (turns != 0) out = img.copyRotate(out, angle: 90 * turns);
    return Uint8List.fromList(img.encodeJpg(out, quality: 92));
  }
}
