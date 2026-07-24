import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// ── Setflow data visualization ─────────────────────────────────────────────
/// Hand-drawn CustomPainter charts that turn the app from a stack of text
/// cards into a training data product. All are theme-agnostic — pass the
/// colors so they sit on dark hero blocks or light surfaces alike.

/// Smoothed area sparkline with a gradient fill and an accented end dot.
class SparkArea extends StatelessWidget {
  const SparkArea({
    required this.values,
    required this.color,
    this.height = 56,
    this.fillOpacity = 0.18,
    this.showDot = true,
    super.key,
  });

  final List<double> values;
  final Color color;
  final double height;
  final double fillOpacity;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 800),
        curve: SetflowMotion.kineticCurve,
        builder: (context, p, _) => CustomPaint(
          painter: _SparkAreaPainter(values, color, fillOpacity, showDot, p),
        ),
      ),
    );
  }
}

class _SparkAreaPainter extends CustomPainter {
  _SparkAreaPainter(
    this.values,
    this.color,
    this.fillOpacity,
    this.showDot,
    this.progress,
  );

  final List<double> values;
  final Color color;
  final double fillOpacity;
  final bool showDot;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    if (progress < 1) {
      canvas.clipRect(
        Rect.fromLTWH(0, 0, size.width * progress, size.height),
      );
    }
    final maxV = values.reduce(math.max);
    final minV = values.reduce(math.min);
    final range = (maxV - minV).abs() < 1e-6 ? 1.0 : (maxV - minV);
    const pad = 4.0;
    final w = size.width;
    final h = size.height - pad * 2;

    Offset pointAt(int i) {
      final x = w * (i / (values.length - 1));
      final y = pad + h * (1 - (values[i] - minV) / range);
      return Offset(x, y);
    }

    final pts = [for (var i = 0; i < values.length; i++) pointAt(i)];

    // Smooth line via Catmull-Rom → cubic beziers.
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = pts[i == 0 ? 0 : i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = pts[i + 2 >= pts.length ? pts.length - 1 : i + 2];
      final c1 = Offset(p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6);
      final c2 = Offset(p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6);
      line.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }

    final fill = Path.from(line)
      ..lineTo(w, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: fillOpacity),
            color.withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
    if (showDot) {
      canvas.drawCircle(pts.last, 3.6, Paint()..color = color);
      canvas.drawCircle(
        pts.last,
        3.6,
        Paint()
          ..color = color.withValues(alpha: .25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparkAreaPainter old) =>
      old.values != values ||
      old.color != color ||
      old.progress != progress;
}

/// Rounded weekly bar chart. One bar is highlighted (e.g. today); the rest use
/// a muted tone. Values are normalized to the tallest bar.
class MiniBars extends StatelessWidget {
  const MiniBars({
    required this.values,
    required this.activeColor,
    required this.mutedColor,
    this.highlightIndex,
    this.height = 64,
    this.labels,
    this.labelColor,
    super.key,
  });

  final List<double> values;
  final Color activeColor;
  final Color mutedColor;
  final int? highlightIndex;
  final double height;
  final List<String>? labels;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final maxV = values.isEmpty ? 1.0 : values.reduce(math.max);
    final safeMax = maxV <= 0 ? 1.0 : maxV;
    return Column(
      children: [
        SizedBox(
          height: height,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 720),
            curve: SetflowMotion.kineticCurve,
            builder: (context, grow, _) => Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < values.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: FractionallySizedBox(
                        alignment: Alignment.bottomCenter,
                        heightFactor:
                            (values[i] / safeMax).clamp(0.06, 1.0) * grow,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: i == highlightIndex
                                ? activeColor
                                : mutedColor,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(5),
                              bottom: Radius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (labels != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < labels!.length; i++)
                Expanded(
                  child: Text(
                    labels![i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 10,
                      fontWeight: i == highlightIndex
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: i == highlightIndex
                          ? (labelColor ?? activeColor)
                          : (labelColor ?? mutedColor).withValues(alpha: .7),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Circular progress ring with a value label in the middle.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    required this.value,
    required this.color,
    required this.trackColor,
    this.size = 72,
    this.stroke = 8,
    this.center,
    super.key,
  });

  final double value; // 0..1
  final Color color;
  final Color trackColor;
  final double size;
  final double stroke;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0, 1)),
        duration: const Duration(milliseconds: 900),
        curve: SetflowMotion.kineticCurve,
        builder: (context, v, child) => CustomPaint(
          painter: _RingPainter(v, color, trackColor, stroke),
          child: child,
        ),
        child: Center(child: center),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.trackColor, this.stroke);

  final double value;
  final Color color;
  final Color trackColor;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * value,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.color != color;
}

/// GitHub-style training heatmap. `weeks` columns × 7 rows; each intensity is
/// 0..1 and maps to the accent's opacity. The signature "serious data" motif.
class ContributionGrid extends StatelessWidget {
  const ContributionGrid({
    required this.intensities,
    required this.color,
    required this.emptyColor,
    this.cell = 13,
    this.gap = 4,
    super.key,
  });

  /// Column-major: intensities[week][day], day 0=Mon..6=Sun. 0 = no session.
  final List<List<double>> intensities;
  final Color color;
  final Color emptyColor;
  final double cell;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 7 * cell + 6 * gap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final week in intensities) ...[
            Column(
              children: [
                for (var d = 0; d < week.length; d++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: d == week.length - 1 ? 0 : gap,
                    ),
                    child: Container(
                      width: cell,
                      height: cell,
                      decoration: BoxDecoration(
                        color: week[d] <= 0
                            ? emptyColor
                            : color.withValues(
                                alpha: (0.28 + 0.72 * week[d]).clamp(0.0, 1.0),
                              ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(width: gap),
          ],
        ],
      ),
    );
  }
}

/// Horizontal split bar — a labelled proportion row (e.g. muscle-group volume).
class SplitBar extends StatelessWidget {
  const SplitBar({
    required this.label,
    required this.value,
    required this.fraction,
    required this.color,
    required this.trackColor,
    super.key,
  });

  final String label;
  final String value;
  final double fraction; // 0..1
  final Color color;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                value,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(SetflowRadii.full),
            child: Stack(
              children: [
                Container(height: 7, color: trackColor),
                FractionallySizedBox(
                  widthFactor: fraction.clamp(0.0, 1.0),
                  child: Container(
                    height: 7,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(SetflowRadii.full),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
