import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'scan_image.dart';

/// Flattens the document inside four corners into an upright rectangle.
abstract final class PerspectiveWarp {
  /// [corners] are `[TL, TR, BR, BL]` in [src] pixel coordinates. The output
  /// size follows the longest opposite edges, capped at [maxSide].
  static ScanImage warp(ScanImage src, List<Offset> corners, {int maxSide = 3500}) {
    final tl = corners[0], tr = corners[1], br = corners[2], bl = corners[3];
    final w = math.max((tr - tl).distance, (br - bl).distance);
    final h = math.max((bl - tl).distance, (br - tr).distance);
    final s = math.min(1.0, maxSide / math.max(w, h));
    final outW = math.max(1, (w * s).round());
    final outH = math.max(1, (h * s).round());

    // Maps output pixel (u, v) -> source point (x, y).
    final m = _homography(
      [
        Offset.zero,
        Offset(outW.toDouble(), 0),
        Offset(outW.toDouble(), outH.toDouble()),
        Offset(0, outH.toDouble()),
      ],
      corners,
    );

    final sw = src.width, sh = src.height, srcRgb = src.rgb;
    final maxX = sw - 1.0, maxY = sh - 1.0;
    final out = Uint8List(outW * outH * 3);
    var o = 0;
    for (var v = 0; v < outH; v++) {
      final vc = v + 0.5;
      // Numerators/denominator are linear in u, so step them per pixel.
      var nx = m[0] * 0.5 + m[1] * vc + m[2];
      var ny = m[3] * 0.5 + m[4] * vc + m[5];
      var d = m[6] * 0.5 + m[7] * vc + 1;
      for (var u = 0; u < outW; u++) {
        var x = nx / d - 0.5;
        var y = ny / d - 0.5;
        x = x < 0 ? 0 : (x > maxX ? maxX : x);
        y = y < 0 ? 0 : (y > maxY ? maxY : y);
        final x0 = x.floor(), y0 = y.floor();
        final x1 = x0 < sw - 1 ? x0 + 1 : x0;
        final y1 = y0 < sh - 1 ? y0 + 1 : y0;
        final ax = x - x0, ay = y - y0;
        final i00 = (y0 * sw + x0) * 3, i10 = (y0 * sw + x1) * 3;
        final i01 = (y1 * sw + x0) * 3, i11 = (y1 * sw + x1) * 3;
        for (var c = 0; c < 3; c++) {
          final top = srcRgb[i00 + c] + (srcRgb[i10 + c] - srcRgb[i00 + c]) * ax;
          final bot = srcRgb[i01 + c] + (srcRgb[i11 + c] - srcRgb[i01 + c]) * ax;
          out[o++] = (top + (bot - top) * ay).round();
        }
        nx += m[0];
        ny += m[3];
        d += m[6];
      }
    }
    return ScanImage(outW, outH, out);
  }

  /// 3x3 homography (h8 = 1) taking each `from[i]` to `to[i]`.
  static List<double> _homography(List<Offset> from, List<Offset> to) {
    final a = List.generate(8, (_) => List<double>.filled(8, 0));
    final b = List<double>.filled(8, 0);
    for (var i = 0; i < 4; i++) {
      final u = from[i].dx, v = from[i].dy, x = to[i].dx, y = to[i].dy;
      a[i * 2] = [u, v, 1, 0, 0, 0, -u * x, -v * x];
      b[i * 2] = x;
      a[i * 2 + 1] = [0, 0, 0, u, v, 1, -u * y, -v * y];
      b[i * 2 + 1] = y;
    }
    return _solve(a, b);
  }

  // Gaussian elimination with partial pivoting.
  static List<double> _solve(List<List<double>> a, List<double> b) {
    const n = 8;
    for (var col = 0; col < n; col++) {
      var pivot = col;
      for (var r = col + 1; r < n; r++) {
        if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
      }
      if (a[pivot][col].abs() < 1e-12) {
        throw StateError('Corners are degenerate (three points on a line?)');
      }
      if (pivot != col) {
        final t = a[col];
        a[col] = a[pivot];
        a[pivot] = t;
        final tb = b[col];
        b[col] = b[pivot];
        b[pivot] = tb;
      }
      for (var r = col + 1; r < n; r++) {
        final f = a[r][col] / a[col][col];
        if (f == 0) continue;
        for (var c = col; c < n; c++) {
          a[r][c] -= f * a[col][c];
        }
        b[r] -= f * b[col];
      }
    }
    final x = List<double>.filled(n, 0);
    for (var r = n - 1; r >= 0; r--) {
      var s = b[r];
      for (var c = r + 1; c < n; c++) {
        s -= a[r][c] * x[c];
      }
      x[r] = s / a[r][r];
    }
    return x;
  }
}
