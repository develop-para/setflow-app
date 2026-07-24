import 'package:flutter/material.dart';

import '../theme.dart';
import 'charts.dart';

/// ── Kinetic design language ────────────────────────────────────────────────
/// Athletic-editorial signatures shared across every screen: small-caps
/// kickers, giant tabular numerals, black/yellow stat blocks, and hairline
/// data strips. Import this alongside `common.dart`.

/// Editorial kicker label — a short, uppercased, letter-spaced caption that
/// sits above sections and stats. Optional leading accent tick.
class KineticLabel extends StatelessWidget {
  const KineticLabel(
    this.text, {
    this.color,
    this.tick = false,
    this.tickColor,
    super.key,
  });

  final String text;
  final Color? color;

  /// Draw a short brand-yellow marker before the label (section header accent).
  final bool tick;
  final Color? tickColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolved = color ?? theme.colorScheme.onSurfaceVariant;
    final label = Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: resolved,
        letterSpacing: 1.2,
      ),
    );
    if (!tick) return label;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 3,
          margin: const EdgeInsets.only(right: SetflowSpacing.sm),
          decoration: BoxDecoration(
            color: tickColor ?? theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        label,
      ],
    );
  }
}

enum KineticStatStyle { dark, brand, plain }

/// The hero stat: a flat color field with a kicker, a giant tabular number,
/// optional unit, and an optional delta chip. The athletic-editorial anchor.
class KineticStatBlock extends StatelessWidget {
  const KineticStatBlock({
    required this.label,
    required this.value,
    this.unit,
    this.delta,
    this.deltaUp = true,
    this.style = KineticStatStyle.dark,
    this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final String? unit;

  /// e.g. "8%" — rendered with an up/down arrow.
  final String? delta;
  final bool deltaUp;
  final KineticStatStyle style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg, sub) = switch (style) {
      KineticStatStyle.dark => (
        SetflowColors.inkBlock,
        Colors.white,
        Colors.white60,
      ),
      KineticStatStyle.brand => (
        theme.colorScheme.primary,
        SetflowColors.ink,
        SetflowColors.ink.withValues(alpha: .64),
      ),
      KineticStatStyle.plain => (
        context.setflowColors.surfaceContainerLow,
        theme.colorScheme.onSurface,
        theme.colorScheme.onSurfaceVariant,
      ),
    };
    final deltaColor = style == KineticStatStyle.brand
        ? SetflowColors.ink
        : (deltaUp ? const Color(0xFF34D399) : const Color(0xFFFB7185));

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(SetflowRadii.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KineticLabel(label, color: sub),
              const SizedBox(height: SetflowSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: theme.textTheme.displayMedium?.copyWith(color: fg),
                    ),
                  ),
                  if (unit != null) ...[
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(
                        unit!,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: sub,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (delta != null) ...[
                const SizedBox(height: SetflowSpacing.sm),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      deltaUp
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 15,
                      color: deltaColor,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      delta!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: deltaColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '지난주 대비',
                      style: theme.textTheme.bodySmall?.copyWith(color: sub),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A single cell inside [KineticStatStrip].
class KineticStat {
  const KineticStat(this.label, this.value, {this.unit});
  final String label;
  final String value;
  final String? unit;
}

/// Hairline-separated horizontal data strip — several stats read as one
/// editorial row (e.g. 1RM · 볼륨 · 세트). Bordered, flat, printed feel.
class KineticStatStrip extends StatelessWidget {
  const KineticStatStrip({required this.stats, super.key});

  final List<KineticStat> stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: context.setflowColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(SetflowRadii.lg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.symmetric(vertical: SetflowSpacing.lg),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0)
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: theme.colorScheme.outlineVariant,
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SetflowSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      KineticLabel(stats[i].label),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              stats[i].value,
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: theme.textTheme.headlineMedium,
                            ),
                          ),
                          if (stats[i].unit != null) ...[
                            const SizedBox(width: 3),
                            Text(
                              stats[i].unit!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Editorial screen header: kicker + big display title, optional trailing
/// widget. Use at the top of scroll views instead of a plain AppBar title
/// where a stronger first impression is wanted.
class KineticScreenHeader extends StatelessWidget {
  const KineticScreenHeader({
    required this.title,
    this.kicker,
    this.trailing,
    this.titleStyle,
    super.key,
  });

  final String title;
  final String? kicker;
  final Widget? trailing;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (kicker != null) ...[
                KineticLabel(kicker!, tick: true),
                const SizedBox(height: SetflowSpacing.sm),
              ],
              Text(
                title,
                style: titleStyle ?? theme.textTheme.displaySmall,
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: SetflowSpacing.md),
          trailing!,
        ],
      ],
    );
  }
}

/// The flagship hero: a dark, layered "training summary" card. Gradient depth,
/// a ghost background numeral (the editorial signature), a live trend
/// sparkline, a goal ring, and the week's bar chart — the moment that reads as
/// a real data product rather than a text card.
class TrainingHeroCard extends StatelessWidget {
  const TrainingHeroCard({
    required this.kicker,
    required this.value,
    this.unit,
    this.delta,
    this.deltaUp = true,
    this.deltaCaption = '지난주 대비',
    this.streak,
    this.streakIcon = Icons.local_fire_department_rounded,
    this.spark = const [],
    this.weekValues = const [],
    this.weekLabels,
    this.weekHighlight,
    this.ringValue,
    this.ringTop,
    this.ringBottom,
    this.animateValue = true,
    super.key,
  });

  final String kicker;
  final String value;
  final String? unit;

  /// Count up to a numeric [value] (training stats). Set false for preformatted
  /// values like currency ("2,480,000") that should render verbatim.
  final bool animateValue;
  final String? delta;
  final bool deltaUp;
  final String deltaCaption;
  final String? streak;
  final IconData streakIcon;
  final List<double> spark;
  final List<double> weekValues;
  final List<String>? weekLabels;
  final int? weekHighlight;
  final double? ringValue;
  final String? ringTop;
  final String? ringBottom;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const yellow = SetflowColors.primary;
    final deltaColor = deltaUp ? const Color(0xFF34D399) : const Color(0xFFFB7185);

    return ClipRRect(
      borderRadius: BorderRadius.circular(SetflowRadii.xl),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1815), Color(0xFF0E0E0F)],
          ),
        ),
        child: Stack(
          children: [
            // Editorial signature: an oversized ghost numeral bleeding off-edge.
            Positioned(
              right: -18,
              top: -30,
              child: Text(
                value.replaceAll(RegExp(r'[^0-9.]'), ''),
                style: text.displayLarge?.copyWith(
                  fontSize: 190,
                  height: 1,
                  color: Colors.white.withValues(alpha: .035),
                ),
              ),
            ),
            // Volt top-edge accent.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(height: 3, color: yellow),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: KineticLabel(kicker, color: Colors.white60)),
                      if (streak != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: yellow.withValues(alpha: .16),
                            borderRadius: BorderRadius.circular(
                              SetflowRadii.full,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(streakIcon, size: 13, color: yellow),
                              const SizedBox(width: 4),
                              Text(
                                streak!,
                                style: text.bodySmall?.copyWith(
                                  color: yellow,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: SetflowSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Flexible(
                                  child: animateValue
                                      ? KineticNumber(
                                          double.tryParse(
                                                value.replaceAll(
                                                  RegExp(r'[^0-9.]'),
                                                  '',
                                                ),
                                              ) ??
                                              0,
                                          fractionDigits:
                                              value.contains('.') ? 1 : 0,
                                          style: text.displayLarge?.copyWith(
                                            color: Colors.white,
                                            fontSize: 46,
                                          ),
                                        )
                                      : Text(
                                          value,
                                          maxLines: 1,
                                          overflow: TextOverflow.fade,
                                          softWrap: false,
                                          style: text.displayLarge?.copyWith(
                                            color: Colors.white,
                                            fontSize: 40,
                                          ),
                                        ),
                                ),
                                if (unit != null) ...[
                                  const SizedBox(width: 5),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 7),
                                    child: Text(
                                      unit!,
                                      style: text.titleMedium?.copyWith(
                                        color: Colors.white60,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (delta != null) ...[
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    deltaUp
                                        ? Icons.arrow_upward_rounded
                                        : Icons.arrow_downward_rounded,
                                    size: 14,
                                    color: deltaColor,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    '$delta $deltaCaption',
                                    style: text.bodySmall?.copyWith(
                                      color: deltaColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (ringValue != null)
                        ProgressRing(
                          value: ringValue!,
                          color: yellow,
                          trackColor: Colors.white12,
                          size: 66,
                          stroke: 7,
                          center: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                ringTop ?? '',
                                style: text.labelLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (ringBottom != null)
                                Text(
                                  ringBottom!,
                                  style: text.bodySmall?.copyWith(
                                    color: Colors.white54,
                                    fontSize: 9,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (spark.length >= 2) ...[
                    const SizedBox(height: SetflowSpacing.md),
                    SparkArea(values: spark, color: yellow, height: 44),
                  ],
                  if (weekValues.isNotEmpty) ...[
                    const SizedBox(height: SetflowSpacing.md),
                    MiniBars(
                      values: weekValues,
                      activeColor: yellow,
                      mutedColor: Colors.white.withValues(alpha: .14),
                      highlightIndex: weekHighlight,
                      labels: weekLabels,
                      labelColor: Colors.white70,
                      height: 40,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Count-up tabular number for stat reveals. Snaps in with the kinetic curve.
class KineticNumber extends StatelessWidget {
  const KineticNumber(
    this.value, {
    this.style,
    this.fractionDigits = 0,
    this.prefix = '',
    this.suffix = '',
    this.duration = const Duration(milliseconds: 650),
    super.key,
  });

  final double value;
  final TextStyle? style;
  final int fractionDigits;
  final String prefix;
  final String suffix;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final resolved =
        style ?? Theme.of(context).textTheme.displayMedium;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: duration,
      curve: SetflowMotion.kineticCurve,
      builder: (context, v, _) => Text(
        '$prefix${v.toStringAsFixed(fractionDigits)}$suffix',
        style: resolved,
      ),
    );
  }
}
