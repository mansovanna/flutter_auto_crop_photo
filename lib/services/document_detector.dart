import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:image/image.dart' as img;

import 'quad.dart';

/// Finds the four corners of a document (page, receipt, card, ...) in a photo.
///
/// Pure Dart; run it in a background isolate.
///
///  1. Downscale, convert to luminance, blur.
///  2. Mark strong edges (Sobel + Otsu threshold). If the photo border has a
///     fairly uniform colour, also mark pixels whose colour differs from it.
///  3. Grow the mask a little and keep the largest connected region, so
///     clutter elsewhere in the photo is ignored.
///  4. Take the convex hull of that region and find the largest-area
///     quadrilateral whose corners lie on the hull: those are the page corners.
abstract final class DocumentDetector {
  /// Returns corners in [source] pixel coordinates (`[TL, TR, BR, BL]`), or
  /// null when no document-like shape was found.
  static List<Offset>? detect(img.Image source, {int analysisSize = 400}) {
    final scale = math.min(1.0, analysisSize / math.max(source.width, source.height));
    final small = scale < 1.0
        ? img.copyResize(
            source,
            width: math.max(1, (source.width * scale).round()),
            height: math.max(1, (source.height * scale).round()),
            interpolation: img.Interpolation.average,
          )
        : source;
    final w = small.width;
    final h = small.height;
    if (w < 16 || h < 16) return null;

    final mask = _foregroundMask(small);
    if (mask == null) return null;

    final region = _largestRegion(mask, w, h);
    if (region == null) return null;

    // Row extremes of the region are enough to build its convex hull.
    final points = <Offset>[];
    for (var y = 0; y < h; y++) {
      var minX = -1, maxX = -1;
      for (var x = 0; x < w; x++) {
        if (region[y * w + x] == 1) {
          if (minX < 0) minX = x;
          maxX = x;
        }
      }
      if (minX >= 0) {
        points.add(Offset(minX.toDouble(), y.toDouble()));
        if (maxX != minX) points.add(Offset(maxX.toDouble(), y.toDouble()));
      }
    }
    if (points.length < 4) return null;

    var hull = _convexHull(points);
    if (hull.length < 4) return null;
    if (hull.length > 160) {
      final step = hull.length / 160;
      hull = [for (var i = 0; i < 160; i++) hull[(i * step).floor()]];
    }

    final quad = _maxAreaQuad(hull);
    if (quad == null) return null;
    final ordered = Quad.order(quad);
    if (!Quad.isValid(ordered, minArea: w * h * 0.08)) return null;
    if (!_edgesSeparateSurfaces(small, ordered)) return null;

    // The edge response sits slightly outside the paper; pull each corner
    // ~2 analysis pixels toward the centre so no background strip survives.
    final cx = ordered.fold(0.0, (s, p) => s + p.dx) / 4;
    final cy = ordered.fold(0.0, (s, p) => s + p.dy) / 4;
    final inset = [
      for (final p in ordered)
        () {
          final toCenter = Offset(cx, cy) - p;
          final len = toCenter.distance;
          return len < 1 ? p : p + toCenter / len * 2.0;
        }(),
    ];

    // Back to source resolution (pixel centres), clamped to the image.
    final sx = source.width / w;
    final sy = source.height / h;
    return [
      for (final p in inset)
        Offset(
          ((p.dx + 0.5) * sx).clamp(0, source.width.toDouble()),
          ((p.dy + 0.5) * sy).clamp(0, source.height.toDouble()),
        ),
    ];
  }

  /// A real page edge separates two different surfaces: background outside,
  /// paper inside, all the way round. A table or block of text printed *on*
  /// a page that fills the image (screenshots, PDF exports, close-ups) has
  /// the same white paper on both sides of most of its edges.
  ///
  /// For each edge, compares the colour a few pixels outside with a few
  /// pixels inside at points along it, and takes the median difference
  /// (robust to text touching the edge). All four edges must separate.
  /// Edges lying along the image border (page cut off by the frame) pass.
  static bool _edgesSeparateSurfaces(img.Image small, List<Offset> quad) {
    final w = small.width, h = small.height;
    List<double>? colour(double x, double y) {
      final xi = x.round(), yi = y.round();
      if (xi < 0 || yi < 0 || xi >= w || yi >= h) return null;
      final p = small.getPixel(xi, yi);
      return [p.rNormalized * 255.0, p.gNormalized * 255.0, p.bNormalized * 255.0];
    }

    for (var e = 0; e < 4; e++) {
      final a = quad[e], b = quad[(e + 1) % 4];
      final d = b - a;
      final len = d.distance;
      if (len < 1) return false;
      final inward = Offset(-d.dy, d.dx) / len; // clockwise quad, y down
      final diffs = <double>[];
      for (var i = 1; i < 20; i++) {
        final p = Offset.lerp(a, b, i / 20)!;
        var dSum = 0.0, n = 0;
        for (final k in const [3.0, 5.0]) {
          final o = colour(p.dx - inward.dx * k, p.dy - inward.dy * k);
          final iC = colour(p.dx + inward.dx * k, p.dy + inward.dy * k);
          if (o == null || iC == null) continue;
          final dr = o[0] - iC[0], dg = o[1] - iC[1], db = o[2] - iC[2];
          dSum += math.sqrt(dr * dr + dg * dg + db * db);
          n++;
        }
        if (n > 0) diffs.add(dSum / n);
      }
      if (diffs.length < 5) continue; // along the image border
      diffs.sort();
      if (diffs[diffs.length ~/ 2] < 22) return false;
    }
    return true;
  }

  /// 1 = edge or "differs from background", 0 = background.
  static Uint8List? _foregroundMask(img.Image small) {
    final w = small.width;
    final h = small.height;
    final n = w * h;
    final lum = Float32List(n);
    final rgb = Float32List(n * 3);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = small.getPixel(x, y);
        final r = p.rNormalized * 255, g = p.gNormalized * 255, b = p.bNormalized * 255;
        final i = y * w + x;
        lum[i] = (0.299 * r + 0.587 * g + 0.114 * b).toDouble();
        rgb[i * 3] = r.toDouble();
        rgb[i * 3 + 1] = g.toDouble();
        rgb[i * 3 + 2] = b.toDouble();
      }
    }
    final blurred = _boxBlur(_boxBlur(lum, w, h), w, h);

    final mag = Float32List(n);
    var maxMag = 0.0;
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final i = y * w + x;
        final tl = blurred[i - w - 1], t = blurred[i - w], tr = blurred[i - w + 1];
        final l = blurred[i - 1], r = blurred[i + 1];
        final bl = blurred[i + w - 1], b = blurred[i + w], br = blurred[i + w + 1];
        final gx = (tr + 2 * r + br) - (tl + 2 * l + bl);
        final gy = (bl + 2 * b + br) - (tl + 2 * t + tr);
        final m = math.sqrt(gx * gx + gy * gy);
        mag[i] = m;
        if (m > maxMag) maxMag = m;
      }
    }
    if (maxMag < 1e-3) return null;
    final edgeThreshold = math.max(_otsu(mag, maxMag), 40.0);

    final mask = Uint8List(n);
    for (var i = 0; i < n; i++) {
      if (mag[i] >= edgeThreshold) mask[i] = 1;
    }

    // Plain background? Then colour difference is a strong cue too.
    final ring = math.max(2, (math.min(w, h) * 0.04).round());
    bool inRing(int x, int y) => x < ring || y < ring || x >= w - ring || y >= h - ring;
    var count = 0;
    var mr = 0.0, mg = 0.0, mb = 0.0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (!inRing(x, y)) continue;
        final i = (y * w + x) * 3;
        mr += rgb[i];
        mg += rgb[i + 1];
        mb += rgb[i + 2];
        count++;
      }
    }
    mr /= count;
    mg /= count;
    mb /= count;
    var variance = 0.0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (!inRing(x, y)) continue;
        final i = (y * w + x) * 3;
        final dr = rgb[i] - mr, dg = rgb[i + 1] - mg, db = rgb[i + 2] - mb;
        variance += dr * dr + dg * dg + db * db;
      }
    }
    final borderStd = math.sqrt(variance / count);
    if (borderStd < 25) {
      // Camera photos need a wide margin for sensor noise and uneven light.
      // A nearly flat border (digital image, scan, mock-up) has no noise, so
      // even a subtle page-vs-background difference is reliable — e.g. a
      // white page on light grey (difference ~40).
      final t = borderStd < 6 ? math.max(15.0, borderStd * 4) : math.max(45.0, borderStd * 3);
      final t2 = t * t;
      for (var i = 0; i < n; i++) {
        final dr = rgb[i * 3] - mr, dg = rgb[i * 3 + 1] - mg, db = rgb[i * 3 + 2] - mb;
        if (dr * dr + dg * dg + db * db > t2) mask[i] = 1;
      }
    }

    // Lens vignetting and filter boundaries create false edges at the border.
    final margin = math.max(2, (math.min(w, h) * 0.015).round());
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (x < margin || y < margin || x >= w - margin || y >= h - margin) {
          mask[y * w + x] = 0;
        }
      }
    }
    return mask;
  }

  /// Dilates [mask], picks the largest 4-connected region and returns the
  /// original (undilated) mask pixels that belong to it.
  static Uint8List? _largestRegion(Uint8List mask, int w, int h) {
    final n = w * h;
    var grown = mask;
    for (var k = 0; k < 2; k++) {
      final horiz = Uint8List(n);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = y * w + x;
          if (grown[i] == 1 || (x > 0 && grown[i - 1] == 1) || (x < w - 1 && grown[i + 1] == 1)) {
            horiz[i] = 1;
          }
        }
      }
      final out = Uint8List(n);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = y * w + x;
          if (horiz[i] == 1 || (y > 0 && horiz[i - w] == 1) || (y < h - 1 && horiz[i + w] == 1)) {
            out[i] = 1;
          }
        }
      }
      grown = out;
    }

    final labels = Int32List(n);
    final queue = Int32List(n);
    var label = 0, bestLabel = 0, bestCount = 0;
    for (var start = 0; start < n; start++) {
      if (grown[start] == 0 || labels[start] != 0) continue;
      label++;
      var head = 0, tail = 0, size = 0;
      queue[tail++] = start;
      labels[start] = label;
      while (head < tail) {
        final i = queue[head++];
        size++;
        final x = i % w;
        void visit(int j) {
          if (grown[j] == 1 && labels[j] == 0) {
            labels[j] = label;
            queue[tail++] = j;
          }
        }

        if (x > 0) visit(i - 1);
        if (x < w - 1) visit(i + 1);
        if (i >= w) visit(i - w);
        if (i < n - w) visit(i + w);
      }
      if (size > bestCount) {
        bestCount = size;
        bestLabel = label;
      }
    }
    if (bestCount < n * 0.01) return null;

    final region = Uint8List(n);
    var pixels = 0;
    for (var i = 0; i < n; i++) {
      if (labels[i] == bestLabel && mask[i] == 1) {
        region[i] = 1;
        pixels++;
      }
    }
    return pixels < 8 ? null : region;
  }

  /// Andrew's monotone chain; returns hull vertices in order.
  static List<Offset> _convexHull(List<Offset> pts) {
    final p = [...pts]
      ..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
    double cross(Offset o, Offset a, Offset b) =>
        (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
    final lower = <Offset>[];
    for (final q in p) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, q) <= 0) {
        lower.removeLast();
      }
      lower.add(q);
    }
    final upper = <Offset>[];
    for (final q in p.reversed) {
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, q) <= 0) {
        upper.removeLast();
      }
      upper.add(q);
    }
    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  /// Largest-area quadrilateral with vertices on the hull: try every diagonal
  /// (i, j) and pick the farthest hull vertex on each side of it.
  static List<Offset>? _maxAreaQuad(List<Offset> hull) {
    final n = hull.length;
    double tri(Offset a, Offset b, Offset c) =>
        ((b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx)).abs();
    var best = -1.0;
    List<Offset>? result;
    for (var i = 0; i < n; i++) {
      for (var j = i + 2; j <= i + n - 2 && j < n; j++) {
        var bestK = -1, areaK = -1.0;
        for (var k = i + 1; k < j; k++) {
          final a = tri(hull[i], hull[k], hull[j]);
          if (a > areaK) {
            areaK = a;
            bestK = k;
          }
        }
        var bestL = -1, areaL = -1.0;
        for (var l = j + 1; l < i + n; l++) {
          final a = tri(hull[j], hull[l % n], hull[i]);
          if (a > areaL) {
            areaL = a;
            bestL = l % n;
          }
        }
        if (bestK < 0 || bestL < 0) continue;
        final total = areaK + areaL;
        if (total > best) {
          best = total;
          result = [hull[i], hull[bestK], hull[j], hull[bestL]];
        }
      }
    }
    return result;
  }

  static Float32List _boxBlur(Float32List src, int w, int h) {
    final tmp = Float32List(w * h);
    final out = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final xl = x > 0 ? x - 1 : x, xr = x < w - 1 ? x + 1 : x;
        tmp[y * w + x] = (src[y * w + xl] + src[y * w + x] + src[y * w + xr]) / 3;
      }
    }
    for (var y = 0; y < h; y++) {
      final yt = y > 0 ? y - 1 : y, yb = y < h - 1 ? y + 1 : y;
      for (var x = 0; x < w; x++) {
        out[y * w + x] = (tmp[yt * w + x] + tmp[y * w + x] + tmp[yb * w + x]) / 3;
      }
    }
    return out;
  }

  static double _otsu(Float32List values, double maxValue) {
    final hist = Int32List(256);
    for (final v in values) {
      hist[(v / maxValue * 255).clamp(0, 255).toInt()]++;
    }
    final total = values.length;
    var sum = 0.0;
    for (var i = 0; i < 256; i++) {
      sum += i * hist[i];
    }
    var sumB = 0.0, wB = 0, best = 0.0, threshold = 0;
    for (var i = 0; i < 256; i++) {
      wB += hist[i];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;
      sumB += i * hist[i];
      final mB = sumB / wB;
      final mF = (sum - sumB) / wF;
      final between = wB * wF * (mB - mF) * (mB - mF);
      if (between > best) {
        best = between;
        threshold = i;
      }
    }
    return threshold / 255 * maxValue;
  }
}
