import 'package:flutter/material.dart';

import '../theme.dart';

/// The brand is the word, nothing else.
///
/// There is deliberately no glyph, no drawn mark and no tinted tile behind it:
/// a monochrome system says the name in type and lets whitespace do the rest.
/// If a logo ever comes back it belongs in one place — here — not re-drawn per
/// screen.
class SetflowWordmark extends StatelessWidget {
  const SetflowWordmark({this.fontSize = 22, this.color, super.key});

  final double fontSize;

  /// Defaults to the current onSurface ink.
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

/// Square lockup for places that cannot take a horizontal wordmark — the
/// launcher icon and the OS splash. Still typography: one letter of the same
/// face on a flat black field, no drawn shape.
class SetflowMonogram extends StatelessWidget {
  const SetflowMonogram({
    required this.size,
    this.background,
    this.color,
    this.radius,
    super.key,
  });

  final double size;

  /// Null renders the letter alone on a transparent field (adaptive-icon
  /// foreground), otherwise it fills a tile.
  final Color? background;
  final Color? color;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final letter = Center(
      child: Text(
        'S',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Pretendard',
          color:
              color ?? (background == null ? SetflowColors.ink : Colors.white),
          fontSize: size * .62,
          fontWeight: FontWeight.w900,
          height: 1.0,
        ),
      ),
    );
    if (background == null) {
      return SizedBox(width: size, height: size, child: letter);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius ?? 0),
      ),
      child: letter,
    );
  }
}
