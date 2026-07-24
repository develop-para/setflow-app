import 'package:flutter/material.dart';

import '../theme.dart';

/// Setflow brand mark — the "Rep Stack": three ascending rounded bars that
/// read as accumulating sets / rising progress. This is the app's single
/// owned glyph; it replaces every stock icon that used to stand in for a logo.
///
/// Draw it three ways:
/// * as a filled brand tile (pass [background]) — the app-icon lockup used on
///   splash / welcome,
/// * as a bare glyph on any surface (leave [background] null),
/// * inline next to the wordmark via [SetflowWordmark].
class SetflowMark extends StatelessWidget {
  const SetflowMark({
    this.size = 96,
    this.color,
    this.background,
    this.radius,
    super.key,
  });

  /// Edge length of the (square) mark.
  final double size;

  /// Bar color. Defaults to brand ink so it reads on the yellow tile.
  final Color? color;

  /// When set, a rounded tile is painted behind the bars (app-icon form).
  final Color? background;

  /// Tile corner radius. Defaults to a size-proportional squircle.
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
    // Generous inset so the glyph breathes inside a tile.
    final inset = s * 0.24;
    final left = inset;
    final right = s - inset;
    final bottom = s - inset;
    final contentW = right - left;
    final contentH = s - 2 * inset;

    // Three bars: 24% width each, evenly gapped.
    final barW = contentW * 0.24;
    final gap = (contentW - 3 * barW) / 2;
    // Ascending heights — the "sets stack up" signature.
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

/// Horizontal brand lockup: the mini app-icon tile + the "Setflow" wordmark.
/// Used in app bars and the auth/onboarding headers.
class SetflowWordmark extends StatelessWidget {
  const SetflowWordmark({
    this.markSize = 28,
    this.fontSize = 22,
    this.color,
    super.key,
  });

  final double markSize;
  final double fontSize;

  /// Wordmark text color. Defaults to the current onSurface ink.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SetflowMark(
          size: markSize,
          background: theme.colorScheme.primary,
          color: SetflowColors.ink,
          radius: markSize * 0.3,
        ),
        SizedBox(width: markSize * 0.42),
        Text(
          'Setflow',
          style: TextStyle(
            color: color ?? theme.colorScheme.onSurface,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}
