import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

class SetflowCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? context.setflowColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(SetflowRadii.lg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: isDark ? null : SetflowShadows.level1,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SetflowRadii.lg),
        child: Material(
          color: Colors.transparent,
          child: onTap == null
              ? Padding(padding: padding, child: child)
              : InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onTap?.call();
                  },
                  child: Padding(padding: padding, child: child),
                ),
        ),
      ),
    );
    return Semantics(button: onTap != null, child: card);
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
          borderRadius: BorderRadius.circular(SetflowRadii.md),
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
    return Expanded(
      child: SetflowCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: tint, size: 20),
            const SizedBox(height: SetflowSpacing.md),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: SetflowSpacing.xs),
            RichText(
              text: TextSpan(
                style: TextStyle(color: theme.colorScheme.onSurface),
                children: [
                  TextSpan(text: value, style: theme.textTheme.headlineLarge),
                  if (suffix != null)
                    TextSpan(
                      text: ' $suffix',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
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
          color: SetflowColors.ink,
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
