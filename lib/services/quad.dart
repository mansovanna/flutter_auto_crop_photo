import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

/// Helpers for document corners.
///
/// Corners are always a list of 4 points in image pixel coordinates, ordered
/// clockwise (on screen) starting at the top-left:
/// `[topLeft, topRight, bottomRight, bottomLeft]`.
abstract final class Quad {
  static List<Offset> fullImage(Size size) => [
        Offset.zero,
        Offset(size.width, 0),
        Offset(size.width, size.height),
        Offset(0, size.height),
      ];

  /// Maps corners on an image of [size] to the same spots after the image is
  /// rotated 90° ([clockwise] or not), re-ordered so index 0 is top-left.
  static List<Offset> rotate(List<Offset> corners, Size size, {required bool clockwise}) => order([
        for (final p in corners)
          clockwise ? Offset(size.height - p.dy, p.dx) : Offset(p.dy, size.width - p.dx),
      ]);

  /// Puts 4 arbitrary points into `[TL, TR, BR, BL]` order.
  static List<Offset> order(List<Offset> points) {
    assert(points.length == 4);
    final cx = points.fold(0.0, (s, p) => s + p.dx) / 4;
    final cy = points.fold(0.0, (s, p) => s + p.dy) / 4;
    // Ascending angle with y pointing down = clockwise on screen.
    final sorted = [...points]
      ..sort((a, b) => math
          .atan2(a.dy - cy, a.dx - cx)
          .compareTo(math.atan2(b.dy - cy, b.dx - cx)));
    var first = 0;
    for (var i = 1; i < 4; i++) {
      if (sorted[i].dx + sorted[i].dy < sorted[first].dx + sorted[first].dy) {
        first = i;
      }
    }
    return [for (var i = 0; i < 4; i++) sorted[(first + i) % 4]];
  }

  /// True when the corners form a convex quadrilateral in the expected
  /// clockwise order (no crossed edges, no corner dragged "inside out").
  static bool isValid(List<Offset> c, {double minArea = 1}) {
    for (var i = 0; i < 4; i++) {
      final a = c[i], b = c[(i + 1) % 4], d = c[(i + 2) % 4];
      final cross = (b.dx - a.dx) * (d.dy - b.dy) - (b.dy - a.dy) * (d.dx - b.dx);
      if (cross <= 0) return false;
    }
    return area(c) >= minArea;
  }

  static double area(List<Offset> c) {
    var s = 0.0;
    for (var i = 0; i < c.length; i++) {
      final a = c[i], b = c[(i + 1) % c.length];
      s += a.dx * b.dy - b.dx * a.dy;
    }
    return s.abs() / 2;
  }
}
