import 'package:flutter/material.dart';

import '../theme.dart';

/// The cinnabar qalam rhombus: the imam's current Quranic position. The only
/// shape in the product drawn in `rubric`.
///
/// Filled = following (engine `tracking`, freshly confirmed); hollow = held
/// without fresh confirmation. When there is no trustworthy position, do not
/// show a marker at all: it has no disabled, loading or error state.
/// Filled ↔ hollow is a [RubricMotion.quick] fill crossfade in place; it never
/// pulses or blinks. Decorative for screen readers: the words next to it carry
/// the meaning.
class PositionMarker extends StatelessWidget {
  const PositionMarker({super.key, required this.filled, this.size = 14});

  final bool filled;

  /// 14px in the status line; 28px only in documentation and onboarding.
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.rubric;
    return ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: filled ? 1 : 0),
        duration: RubricMotion.quick,
        curve: RubricMotion.standard,
        builder: (context, fill, _) => CustomPaint(
          size: Size.square(size),
          painter: _MarkerPainter(color: color, fill: fill),
        ),
      ),
    );
  }
}

class _MarkerPainter extends CustomPainter {
  _MarkerPainter({required this.color, required this.fill});

  final Color color;

  /// 0 = hollow, 1 = filled.
  final double fill;

  /// The rhombic dot of Amiri's ف (`dotabove-ar`), on a 24-unit grid, from
  /// the handoff's `logo/svg/position-marker.svg`.
  static final Path _rhombus = Path()
    ..moveTo(9.9378, 5.7116)
    ..quadraticBezierTo(10.5107, 4.9479, 11.5608, 5.2343)
    ..quadraticBezierTo(13.4702, 5.9026, 15.2363, 6.9527)
    ..quadraticBezierTo(17.0025, 8.0029, 18.5300, 9.3394)
    ..quadraticBezierTo(19.2937, 10.1032, 18.8164, 11.0579)
    ..lineTo(14.2339, 18.3135)
    ..quadraticBezierTo(13.5656, 19.2681, 12.5155, 18.5044)
    ..quadraticBezierTo(11.5608, 17.7406, 5.6418, 14.2083)
    ..quadraticBezierTo(4.5916, 13.5400, 5.2599, 12.5853)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    if (fill > 0) {
      canvas.drawPath(_rhombus, Paint()..color = color.withValues(alpha: color.a * fill));
    }
    canvas.drawPath(
      _rhombus,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_MarkerPainter old) => old.color != color || old.fill != fill;
}
