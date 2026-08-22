import 'package:flutter/material.dart';

import '../theme.dart';

/// Setflow brand mark — the "Rep Stack": three ascending rounded bars that
/// read as accumulating sets and rising progress.
class SetflowMark extends StatelessWidget {
  const SetflowMark({
    this.size = 96,
    this.color,
    this.background,
    this.radius,
    super.key,
  });

  final double size;
  final Color? color;
  final Color? background;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final barColor = color ?? SetflowColors.ink;
    final tileRadius = radius ?? size * 0.28;
    final mark = CustomPaint(
      size: Size.square(size),
      painter: _RepStackPainter(barColor),
    );
    if (background == null) return mark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(tileRadius),
      ),
      child: mark,
    );
  }
}

class _RepStackPainter extends CustomPainter {
  const _RepStackPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final inset = s * 0.24;
    final left = inset;
    final right = s - inset;
    final bottom = s - inset;
    final contentW = right - left;
    final contentH = s - 2 * inset;
    final barW = contentW * 0.24;
    final gap = (contentW - 3 * barW) / 2;
    const heights = [0.46, 0.72, 1.0];
    final corner = Radius.circular(barW * 0.46);
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;

    for (var i = 0; i < 3; i++) {
      final x = left + i * (barW + gap);
      final top = bottom - contentH * heights[i];
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTRB(x, top, x + barW, bottom),
        corner,
      );
      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RepStackPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Compact wordmark used by the current screen layout.
class SetflowWordmark extends StatelessWidget {
  const SetflowWordmark({this.fontSize = 22, this.color, super.key});

  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      'SETFLOW',
      style: TextStyle(
        color: color ?? theme.colorScheme.onSurface,
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        letterSpacing: fontSize * .12,
        height: 1.0,
      ),
    );
  }
}
