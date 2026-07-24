import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'kinetic.dart';

class SetflowCard extends StatefulWidget {
  const SetflowCard({
    required this.child,
    this.padding = const EdgeInsets.all(SetflowSpacing.lg),
    this.color,
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;

  @override
  State<SetflowCard> createState() => _SetflowCardState();
}

class _SetflowCardState extends State<SetflowCard> {
  bool _pressed = false;

  void _set(bool v) {
    if (widget.onTap == null || _pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: widget.color ?? context.setflowColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(SetflowRadii.lg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: isDark ? null : SetflowShadows.level1,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SetflowRadii.lg),
        child: Material(
          color: Colors.transparent,
          child: widget.onTap == null
              ? Padding(padding: widget.padding, child: widget.child)
              : InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onTap?.call();
                  },
                  child: Padding(padding: widget.padding, child: widget.child),
                ),
        ),
      ),
    );
    // Tactile press: a subtle scale-down on any tappable card, app-wide.
    final scaled = widget.onTap == null
        ? card
        : Listener(
            onPointerDown: (_) => _set(true),
            onPointerUp: (_) => _set(false),
            onPointerCancel: (_) => _set(false),
            child: AnimatedScale(
              scale: _pressed ? 0.98 : 1,
              duration: SetflowMotion.micro,
              curve: Curves.easeOut,
              child: card,
            ),
          );
    return Semantics(button: widget.onTap != null, child: scaled);
  }
}

enum AppButtonVariant { primary, tonal, outlined, text }

class AppButton extends StatefulWidget {
  const AppButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.expanded = true,
    this.isLoading = false,
    this.semanticLabel,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonVariant variant;
  final bool expanded;
  final bool isLoading;
  final String? semanticLabel;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.isLoading;

  void _setPressed(bool value) {
    if (!_enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = widget.isLoading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: widget.variant == AppButtonVariant.primary
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.primary,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 20),
                const SizedBox(width: SetflowSpacing.sm),
              ],
              Flexible(child: Text(widget.label, overflow: TextOverflow.fade)),
            ],
          );

    final onPressed = _enabled
        ? () {
            HapticFeedback.lightImpact();
            widget.onPressed?.call();
          }
        : null;
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 52)),
      tapTargetSize: MaterialTapTargetSize.padded,
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SetflowRadii.sm),
        ),
      ),
    );

    final Widget button = switch (widget.variant) {
      AppButtonVariant.primary => FilledButton(
        onPressed: onPressed,
        style: style,
        child: content,
      ),
      AppButtonVariant.tonal => FilledButton.tonal(
        onPressed: onPressed,
        style: style,
        child: content,
      ),
      AppButtonVariant.outlined => OutlinedButton(
        onPressed: onPressed,
        style: style,
        child: content,
      ),
      AppButtonVariant.text => TextButton(
        onPressed: onPressed,
        style: style.copyWith(
          minimumSize: const WidgetStatePropertyAll(Size(48, 44)),
        ),
        child: content,
      ),
    };

    final scaled = Semantics(
      label: widget.semanticLabel,
      button: true,
      enabled: _enabled,
      child: Listener(
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: AnimatedScale(
          scale: _pressed ? .98 : 1,
          duration: SetflowMotion.micro,
          curve: Curves.easeOut,
          child: button,
        ),
      ),
    );
    return widget.expanded
        ? SizedBox(width: double.infinity, child: scaled)
        : scaled;
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: label,
      onPressed: onPressed,
      icon: icon,
      expanded: expanded,
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    this.controller,
    this.focusNode,
    this.label,
    this.hint,
    this.helperText,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.autofillHints,
    this.inputFormatters,
    super.key,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? label;
  final String? hint;
  final String? helperText;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final bool enabled;
  final bool autofocus;
  final int? maxLines;
  final int? minLines;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      enabled: enabled,
      autofocus: autofocus,
      maxLines: obscureText ? 1 : maxLines,
      minLines: minLines,
      autofillHints: autofillHints,
      inputFormatters: inputFormatters,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: Theme.of(context).textTheme.bodyLarge,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {this.action, this.onAction, super.key});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
    this.suffix,
    super.key,
  });

  final String label;
  final String value;
  final String? suffix;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Editorial metric: kicker label with a small tinted mark, then a giant
    // tabular numeral. The number is the hero; the icon just tags the category.
    return Expanded(
      child: SetflowCard(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 7),
                  decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                ),
                Expanded(
                  child: KineticLabel(
                    label,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Icon(icon, color: tint, size: 15),
              ],
            ),
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
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (suffix != null) ...[
                  const SizedBox(width: 3),
                  Text(
                    suffix!,
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
    );
  }
}

class LoadingState extends StatefulWidget {
  const LoadingState({
    this.message,
    this.itemCount = 3,
    this.compact = false,
    super.key,
  });

  final String? message;
  final int itemCount;
  final bool compact;

  @override
  State<LoadingState> createState() => _LoadingStateState();
}

class _LoadingStateState extends State<LoadingState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.setflowColors.surfaceContainer;
    final highlight = context.setflowColors.surfaceContainerHigh;
    if (widget.compact) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SetflowSpacing.xxl),
          child: CircularProgressIndicator(
            semanticsLabel: widget.message ?? '불러오는 중',
          ),
        ),
      );
    }
    return Semantics(
      label: widget.message ?? '콘텐츠를 불러오는 중',
      liveRegion: true,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final color = Color.lerp(base, highlight, _controller.value)!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 156,
                  height: 22,
                  decoration: _skeletonDecoration(color, SetflowRadii.sm),
                ),
                const SizedBox(height: SetflowSpacing.lg),
                for (var index = 0; index < widget.itemCount; index++) ...[
                  Container(
                    width: double.infinity,
                    height: 84,
                    decoration: _skeletonDecoration(color, SetflowRadii.md),
                  ),
                  if (index < widget.itemCount - 1)
                    const SizedBox(height: SetflowSpacing.md),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  BoxDecoration _skeletonDecoration(Color color, double radius) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SetflowSpacing.section),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: context.setflowColors.surfaceContainer,
                borderRadius: BorderRadius.circular(SetflowRadii.lg),
              ),
              child: Icon(
                icon,
                size: 34,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SetflowSpacing.lg),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SetflowSpacing.sm),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: SetflowSpacing.xl),
              AppButton(
                label: actionLabel!,
                onPressed: onAction,
                expanded: false,
                variant: AppButtonVariant.tonal,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({
    this.title = '문제가 발생했어요',
    required this.message,
    this.retryLabel = '다시 시도',
    this.onRetry,
    super.key,
  });

  final String title;
  final String message;
  final String retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline_rounded,
      title: title,
      message: message,
      actionLabel: onRetry == null ? null : retryLabel,
      onAction: onRetry,
    );
  }
}

class GlobalRestTimerOverlay extends StatelessWidget {
  const GlobalRestTimerOverlay({
    required this.seconds,
    required this.totalSeconds,
    required this.onAddTime,
    required this.onCancel,
    super.key,
  });

  final int seconds;
  final int totalSeconds;
  final VoidCallback onAddTime;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    final progress = totalSeconds <= 0
        ? 0.0
        : (seconds / totalSeconds).clamp(0.0, 1.0);
    return Semantics(
      label: '휴식 타이머 $minutes분 $remainder초 남음',
      liveRegion: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: .96, end: 1),
        duration: SetflowMotion.micro,
        curve: SetflowMotion.emphasisCurve,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Material(
          // Always-dark chip so the volt progress and white numerals read
          // identically over both themes.
          color: SetflowSemanticColors.dark.surfaceContainerLow,
          elevation: 12,
          borderRadius: BorderRadius.circular(SetflowRadii.lg),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                color: SetflowColors.primary,
                backgroundColor: Colors.white12,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.timer_outlined,
                      color: SetflowColors.primary,
                    ),
                    const SizedBox(width: SetflowSpacing.sm),
                    const Expanded(
                      child: Text(
                        '휴식 중',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '$minutes:$remainder',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    TextButton(
                      onPressed: onAddTime,
                      style: TextButton.styleFrom(
                        foregroundColor: SetflowColors.primary,
                        minimumSize: const Size(48, 44),
                      ),
                      child: const Text('+30초'),
                    ),
                    Semantics(
                      button: true,
                      label: '휴식 종료',
                      child: IconButton(
                        onPressed: onCancel,
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

abstract final class AppSnackbar {
  static void success(BuildContext context, String message) {
    _show(context, message, Icons.check_circle_rounded, SetflowColors.green);
  }

  static void error(BuildContext context, String message) {
    _show(context, message, Icons.error_rounded, SetflowColors.red);
  }

  static void info(BuildContext context, String message) {
    _show(context, message, Icons.info_rounded, context.setflowColors.info);
  }

  static void _show(
    BuildContext context,
    String message,
    IconData icon,
    Color color,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: color, size: 21),
              const SizedBox(width: SetflowSpacing.md),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }
}

void showMessage(BuildContext context, String message) {
  AppSnackbar.info(context, message);
}

/// Small tinted pill for statuses, grades, severities, and categories.
class StatusChip extends StatelessWidget {
  const StatusChip({
    required this.label,
    required this.color,
    this.icon,
    super.key,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SetflowSpacing.sm,
        vertical: SetflowSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(SetflowRadii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: SetflowSpacing.xs),
          ],
          Text(
            label,
            style: text.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon centered on a low-alpha tinted circle or rounded square.
class TintedIconBadge extends StatelessWidget {
  const TintedIconBadge({
    required this.icon,
    required this.color,
    this.size = 44,
    this.square = false,
    this.iconSize,
    super.key,
  });

  final IconData icon;
  final Color color;
  final double size;
  final bool square;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        shape: square ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: square ? BorderRadius.circular(SetflowRadii.sm) : null,
      ),
      child: Icon(icon, color: color, size: iconSize ?? size * .48),
    );
  }
}

/// Inline notice banner: tinted container with an icon and message.
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.color,
    super.key,
  });

  final String message;
  final IconData icon;

  /// Accent for icon and tint; defaults to a neutral surface container.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(SetflowSpacing.md),
      decoration: BoxDecoration(
        color:
            color?.withValues(alpha: .1) ??
            context.setflowColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(SetflowRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: SetflowSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.labelMedium?.copyWith(height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bold field label stacked above any form control.
class LabeledField extends StatelessWidget {
  const LabeledField({required this.label, required this.child, super.key});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: SetflowSpacing.sm),
        child,
      ],
    );
  }
}

/// Solid brand-color summary banner: caption, large value, optional note.
class HeroStatBanner extends StatelessWidget {
  const HeroStatBanner({
    required this.caption,
    required this.value,
    required this.color,
    this.note,
    this.foreground = Colors.white,
    super.key,
  });

  final String caption;
  final String value;
  final Color color;
  final String? note;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SetflowSpacing.xl),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(SetflowRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            caption,
            style: text.labelMedium?.copyWith(
              color: foreground.withValues(alpha: .7),
            ),
          ),
          const SizedBox(height: SetflowSpacing.xs),
          Text(
            value,
            style: text.displayMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: SetflowSpacing.xs),
            Text(
              note!,
              style: text.bodySmall?.copyWith(
                color: foreground.withValues(alpha: .7),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 38px bordered surface icon button — the standard header action control.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.color,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final button = Material(
      color: context.setflowColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(SetflowRadii.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(SetflowRadii.sm),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap?.call();
              },
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SetflowRadii.sm),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Icon(
            icon,
            size: 19,
            color: color ?? theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// One row inside [showAppActionSheet].
class SheetAction<T> {
  const SheetAction({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final T value;
  final String? subtitle;
  final bool destructive;
}

/// Branded contextual action sheet — replaces web-flavored popup menus.
/// Returns the tapped action's value, or null when dismissed.
Future<T?> showAppActionSheet<T>(
  BuildContext context, {
  String? title,
  String? subtitle,
  required List<SheetAction<T>> actions,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final text = theme.textTheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            SetflowSpacing.lg,
            0,
            SetflowSpacing.lg,
            SetflowSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SetflowSpacing.sm,
                    0,
                    SetflowSpacing.sm,
                    SetflowSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle,
                            style: text.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              for (final action in actions)
                ListTile(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.pop(sheetContext, action.value);
                  },
                  leading: Icon(
                    action.icon,
                    color: action.destructive
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  title: Text(
                    action.label,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: action.destructive
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  subtitle: action.subtitle == null
                      ? null
                      : Text(
                          action.subtitle!,
                          style: text.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// One destination in [SetflowNavBar].
class SetflowNavItem {
  const SetflowNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Theme-adaptive bottom navigation: a surface-colored bar with a hairline top
/// border. The active destination is marked by a volt indicator bar up top,
/// while its icon and label stay high-contrast ink/white (yellow text would
/// fail contrast on the light surface). Replaces the stock black NavigationBar.
class SetflowNavBar extends StatelessWidget {
  const SetflowNavBar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final List<SetflowNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavItem(
                    item: items[i],
                    selected: i == selectedIndex,
                    onTap: () {
                      if (i != selectedIndex) HapticFeedback.selectionClick();
                      onSelected(i);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final SetflowNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            // Volt indicator bar, flush to the top edge of the bar.
            AnimatedContainer(
              duration: SetflowMotion.standard,
              curve: SetflowMotion.kineticCurve,
              height: 3,
              width: selected ? 24 : 0,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(3),
                ),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    selected ? item.selectedIcon : item.icon,
                    size: 24,
                    color: color,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      letterSpacing: .1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pill segmented control from the athletic mockup (내 루틴 / 최근 / 보관함).
class SegPills extends StatelessWidget {
  const SegPills({
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
    super.key,
  });

  final List<String> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: EdgeInsets.only(
                right: i == items.length - 1 ? 0 : SetflowSpacing.sm,
              ),
              child: Material(
                color: i == selectedIndex
                    ? theme.colorScheme.primary
                    : context.setflowColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(SetflowRadii.full),
                child: InkWell(
                  borderRadius: BorderRadius.circular(SetflowRadii.full),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onChanged(i);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SetflowSpacing.lg,
                      vertical: SetflowSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(SetflowRadii.full),
                      border: Border.all(
                        color: i == selectedIndex
                            ? Colors.transparent
                            : theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Text(
                      items[i],
                      style: text.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: i == selectedIndex
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
