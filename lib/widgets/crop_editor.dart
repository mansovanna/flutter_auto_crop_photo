import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/quad.dart';

enum _HandleKind { corner, edge }

class _Handle {
  const _Handle(this.kind, this.index);
  final _HandleKind kind;

  /// Corner index, or for an edge the index of its first corner.
  final int index;
}

/// Shows a photo with four draggable document corners.
///
/// * Drag a corner to move it.
/// * Drag the handle in the middle of a side to move that whole side.
/// * A magnifier appears while dragging for precise placement.
///
/// [corners] are `[TL, TR, BR, BL]` in image pixel coordinates. The widget is
/// controlled: the parent stores the corners and rebuilds on [onChanged].
class CropEditor extends StatefulWidget {
  const CropEditor({
    super.key,
    required this.imageBytes,
    required this.imageSize,
    required this.corners,
    required this.onChanged,
  });

  final Uint8List imageBytes;
  final Size imageSize;
  final List<Offset> corners;
  final ValueChanged<List<Offset>> onChanged;

  @override
  State<CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<CropEditor> {
  static const double _cornerHitRadius = 40;
  static const double _edgeHitRadius = 32;
  static const double _magnifierSize = 110;

  _Handle? _active;
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final img = widget.imageSize;
        _scale = math.min(
          constraints.maxWidth / img.width,
          constraints.maxHeight / img.height,
        );
        final displaySize = Size(img.width * _scale, img.height * _scale);
        final points = [for (final c in widget.corners) c * _scale];
        final valid = Quad.isValid(widget.corners);
        final colors = Theme.of(context).colorScheme;

        return Center(
          child: SizedBox.fromSize(
            size: displaySize,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) =>
                  setState(() => _active = _hitTest(d.localPosition, points)),
              onPanUpdate: (d) => _onDrag(d.delta / _scale),
              onPanEnd: (_) => setState(() => _active = null),
              onPanCancel: () => setState(() => _active = null),
              child: Stack(
                clipBehavior: Clip.none,
                fit: StackFit.expand,
                children: [
                  Image.memory(
                    widget.imageBytes,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                  ),
                  CustomPaint(
                    painter: _QuadPainter(
                      points: points,
                      color: valid ? colors.primary : colors.error,
                      active: _active,
                    ),
                  ),
                  if (_active != null)
                    _buildMagnifier(points, displaySize, colors.primary),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMagnifier(List<Offset> points, Size area, Color color) {
    final active = _active!;
    final focus = active.kind == _HandleKind.corner
        ? points[active.index]
        : Offset.lerp(
            points[active.index],
            points[(active.index + 1) % 4],
            0.5,
          )!;

    // Above the finger, or below it when too close to the top.
    const gap = _magnifierSize / 2 + 48;
    final dy = focus.dy > _magnifierSize + 48 ? -gap : gap;
    final center = Offset(
      focus.dx.clamp(
        _magnifierSize / 2,
        math.max(_magnifierSize / 2, area.width - _magnifierSize / 2),
      ),
      focus.dy + dy,
    );

    return Positioned(
      left: center.dx - _magnifierSize / 2,
      top: center.dy - _magnifierSize / 2,
      child: IgnorePointer(
        child: RawMagnifier(
          size: const Size.square(_magnifierSize),
          magnificationScale: 2.2,
          focalPointOffset: focus - center,
          decoration: MagnifierDecoration(
            shape: CircleBorder(side: BorderSide(color: color, width: 3)),
            shadows: const [BoxShadow(blurRadius: 8, color: Colors.black54)],
          ),
          child: Center(child: Icon(Icons.add, color: color, size: 22)),
        ),
      ),
    );
  }

  _Handle? _hitTest(Offset p, List<Offset> pts) {
    _Handle? best;
    var bestDist = double.infinity;
    for (var i = 0; i < 4; i++) {
      final d = (pts[i] - p).distance;
      if (d < _cornerHitRadius && d < bestDist) {
        best = _Handle(_HandleKind.corner, i);
        bestDist = d;
      }
    }
    if (best != null) return best;
    for (var i = 0; i < 4; i++) {
      final mid = Offset.lerp(pts[i], pts[(i + 1) % 4], 0.5)!;
      final d = (mid - p).distance;
      if (d < _edgeHitRadius && d < bestDist) {
        best = _Handle(_HandleKind.edge, i);
        bestDist = d;
      }
    }
    return best;
  }

  void _onDrag(Offset delta) {
    final active = _active;
    if (active == null) return;
    final w = widget.imageSize.width, h = widget.imageSize.height;
    final c = [...widget.corners];

    if (active.kind == _HandleKind.corner) {
      final p = c[active.index] + delta;
      c[active.index] = Offset(p.dx.clamp(0.0, w), p.dy.clamp(0.0, h));
    } else {
      final a = active.index, b = (active.index + 1) % 4;
      // Move both ends by the same amount, keeping both inside the image.
      final double dx = delta.dx.clamp(
        math.max(-c[a].dx, -c[b].dx),
        math.min(w - c[a].dx, w - c[b].dx),
      );
      final double dy = delta.dy.clamp(
        math.max(-c[a].dy, -c[b].dy),
        math.min(h - c[a].dy, h - c[b].dy),
      );
      c[a] += Offset(dx, dy);
      c[b] += Offset(dx, dy);
    }
    widget.onChanged(c);
  }
}

class _QuadPainter extends CustomPainter {
  _QuadPainter({
    required this.points,
    required this.color,
    required this.active,
  });

  final List<Offset> points;
  final Color color;
  final _Handle? active;

  @override
  void paint(Canvas canvas, Size size) {
    final quad = Path()..addPolygon(points, true);

    // Dim outside the document.
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addPath(quad, Offset.zero),
      Paint()..color = Colors.black54,
    );
    canvas.drawPath(quad, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawPath(
      quad,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );

    final fill = Paint()..color = Colors.white;
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // Edge handles: short bars along each side's midpoint.
    for (var i = 0; i < 4; i++) {
      final a = points[i], b = points[(i + 1) % 4];
      final mid = Offset.lerp(a, b, 0.5)!;
      final dir = b - a;
      final len = dir.distance;
      if (len < 1) continue;
      final unit = dir / len;
      final isActive = active?.kind == _HandleKind.edge && active?.index == i;
      final half = isActive ? 16.0 : 12.0;
      canvas.drawLine(
        mid - unit * half,
        mid + unit * half,
        Paint()
          ..color = color
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        mid - unit * half,
        mid + unit * half,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
    }

    // Corner handles.
    for (var i = 0; i < 4; i++) {
      final isActive = active?.kind == _HandleKind.corner && active?.index == i;
      final r = isActive ? 14.0 : 11.0;
      canvas.drawCircle(points[i], r, fill);
      canvas.drawCircle(points[i], r, ring);
    }
  }

  @override
  bool shouldRepaint(_QuadPainter old) =>
      old.color != color ||
      old.active?.kind != active?.kind ||
      old.active?.index != active?.index ||
      !_samePoints(old.points, points);

  static bool _samePoints(List<Offset> a, List<Offset> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
