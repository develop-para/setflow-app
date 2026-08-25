import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../theme/icons.dart';

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

    final interaction = Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? .98 : 1,
        duration: SetflowMotion.micro,
        curve: Curves.easeOut,
        child: button,
      ),
    );
    final scaled = widget.semanticLabel == null
        ? interaction
        : Semantics(
            label: widget.semanticLabel,
            button: true,
            enabled: _enabled,
            excludeSemantics: true,
            child: interaction,
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
    this.scrollPadding = const EdgeInsets.fromLTRB(20, 20, 20, 104),
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
  final EdgeInsets scrollPadding;

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
      scrollPadding: scrollPadding,
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

/// Keeps compact form sheets usable while the software keyboard is visible.
///
/// The keyboard inset is consumed here exactly once. The child becomes
/// scrollable when the remaining viewport is shorter than its content.
class KeyboardSafeBottomSheet extends StatelessWidget {
  const KeyboardSafeBottomSheet({
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      SetflowSpacing.xl,
      SetflowSpacing.xs,
      SetflowSpacing.xl,
      SetflowSpacing.xxl,
    ),
    this.maxHeightFactor = .94,
    super.key,
  }) : assert(maxHeightFactor > 0 && maxHeightFactor <= 1);

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final availableHeight =
        (media.size.height - media.viewInsets.bottom - media.padding.top)
            .clamp(0.0, media.size.height)
            .toDouble();
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: availableHeight * maxHeightFactor,
          ),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// App-wide scroll behavior: dragging a vertical form/list dismisses the
/// keyboard without changing desktop mouse or trackpad scrolling semantics.
class SetflowScrollBehavior extends MaterialScrollBehavior {
  const SetflowScrollBehavior();

  @override
  ScrollViewKeyboardDismissBehavior getKeyboardDismissBehavior(
    BuildContext context,
  ) => ScrollViewKeyboardDismissBehavior.onDrag;
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
    this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final String? suffix;
  final IconData icon;
  final Color tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: SetflowCard(
        onTap: onTap,
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
            // 아이콘 뒤에 판을 깔지 않는다. 회색 사각형 안의 회색 아이콘은
            // 아직 안 불러온 자리처럼 보이고, 빈 화면에서 제일 먼저 눈에 띄는
            // 것이 "없다"는 사실이 아니라 그 상자가 된다.
            Icon(icon, size: 40, color: context.setflowColors.disabled),
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

/// The rest countdown, as a slim bar that lives under the header.
///
/// It used to be a tall card floating above the bottom bar, which is exactly
/// where the set rows are — so the thing telling you to wait covered the thing
/// you were waiting to edit. Up top it is out of the thumb's way, out of the
/// list's way, and still visible from every screen.
///
/// Collapsed it is 44px: how far along the rest is, the label, the clock, and
/// the way out. Tapping opens the one action that is not urgent enough to sit
/// there permanently (+30초).
/// 휴식 중에 화면을 덮는 판. 타이머와 끝내기 버튼 말고는 아무것도 못 누른다.
///
/// 세트 사이에 폰을 들면 딴짓이 시작되고, 그러다 휴식이 끝난 줄도 모른다. 쉬는 동안은
/// 쉬는 것만 보이게 하고, 대신 **지금 어디쯤인지**(남은 세트, 다음 종목)를 같이 적어 둔다 —
/// 화면을 막았으면 궁금해질 것을 미리 답해 줘야 한다.
///
/// 막되 가두지는 않는다. "화면 보기"로 접으면 타이머는 계속 가면서 슬림 바로 돌아간다.
/// 방금 잘못 누른 숫자를 고치러 갈 길은 남아 있어야 한다.
class RestFocusOverlay extends StatelessWidget {
  const RestFocusOverlay({
    required this.seconds,
    required this.totalSeconds,
    required this.exerciseName,
    required this.setsLeft,
    required this.nextExercise,
    required this.onAddTime,
    required this.onFinish,
    required this.onCollapse,
    super.key,
  });

  final int seconds;
  final int totalSeconds;
  final String? exerciseName;
  final int setsLeft;
  final String? nextExercise;
  final VoidCallback onAddTime;
  final VoidCallback onFinish;
  final VoidCallback onCollapse;

  String get _clock {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final rest = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$rest';
  }

  /// 지금 어디쯤인지. 세트가 남았으면 그 수를, 종목을 끝냈으면 다음 종목을 말한다.
  String get _whereYouAre {
    if (setsLeft > 0) {
      final name = exerciseName;
      return name == null ? '$setsLeft세트 남음' : '$name · $setsLeft세트 남음';
    }
    final next = nextExercise;
    if (next != null) return '이 종목 끝 · 다음은 $next';
    return '마지막 종목까지 끝냈어요';
  }

  @override
  Widget build(BuildContext context) {
    final progress = totalSeconds <= 0
        ? 0.0
        : (seconds / totalSeconds).clamp(0.0, 1.0);

    return Semantics(
      label: '휴식 중 $_clock 남음. $_whereYouAre',
      liveRegion: true,
      // Material이어야 한다: 이 오버레이는 내비게이터 위 Stack에 살아서
      // Material 조상이 없고, 그러면 모든 Text에 노란 이중 밑줄이 붙는다
      // (기기에서 실제로 그렇게 보였다).
      child: Material(
        // 아래를 완전히 덮는다 — 94% 투명도로는 뒤 화면의 라임 버튼이
        // 비쳐 보였다. 반쯤 보이는 화면은 누르고 싶어질 뿐이다.
        color: SetflowColors.ink,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(SetflowSpacing.section),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '휴식 중',
                  style: TextStyle(
                    fontSize: SetflowFontSize.caption,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: Colors.white.withValues(alpha: .55),
                  ),
                ),
                const SizedBox(height: SetflowSpacing.md),
                Text(
                  _clock,
                  style: const TextStyle(
                    fontSize: SetflowFontSize.hero,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: SetflowSpacing.xxl),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(SetflowRadii.full),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      // 잉크 위에서 읽히는 건 흰색뿐이다.
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: SetflowSpacing.xxl),
                Text(
                  _whereYouAre,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: SetflowFontSize.label,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                    color: Colors.white.withValues(alpha: .72),
                  ),
                ),
                const SizedBox(height: SetflowSpacing.section),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      key: const ValueKey('rest-focus-add'),
                      onPressed: onAddTime,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                      ),
                      child: const Text('+30초'),
                    ),
                    const SizedBox(width: SetflowSpacing.md),
                    FilledButton(
                      key: const ValueKey('rest-focus-finish'),
                      onPressed: onFinish,
                      child: const Text('휴식 끝내기'),
                    ),
                  ],
                ),
                const SizedBox(height: SetflowSpacing.lg),
                TextButton(
                  key: const ValueKey('rest-focus-collapse'),
                  onPressed: onCollapse,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white.withValues(alpha: .6),
                  ),
                  child: const Text('화면 보기'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GlobalRestTimerOverlay extends StatefulWidget {
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
  State<GlobalRestTimerOverlay> createState() => _GlobalRestTimerOverlayState();
}

class _GlobalRestTimerOverlayState extends State<GlobalRestTimerOverlay> {
  static const _barHeight = 44.0;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final minutes = (widget.seconds ~/ 60).toString().padLeft(2, '0');
    final remainder = (widget.seconds % 60).toString().padLeft(2, '0');
    final progress = widget.totalSeconds <= 0
        ? 0.0
        : (widget.seconds / widget.totalSeconds).clamp(0.0, 1.0);

    return Semantics(
      label: '휴식 타이머 $minutes분 $remainder초 남음',
      liveRegion: true,
      child: Material(
        color: SetflowColors.ink,
        elevation: 8,
        borderRadius: BorderRadius.circular(SetflowRadii.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: AnimatedSize(
            duration: SetflowMotion.standard,
            curve: SetflowMotion.standardCurve,
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: _barHeight,
                  child: Stack(
                    children: [
                      // The bar drains as the rest runs out. On an ink bar the
                      // only readable "colour" is light, so progress is a
                      // lighter wash — never SetflowColors.primary, which is
                      // black on black here.
                      Positioned.fill(
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress,
                          child: const ColoredBox(color: Colors.white12),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          SetflowSpacing.lg,
                          0,
                          4,
                          0,
                        ),
                        child: Row(
                          children: [
                            const Text(
                              '휴식 중',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '$minutes:$remainder',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: SetflowFontSize.titleLarge,
                                fontWeight: FontWeight.w900,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            Semantics(
                              button: true,
                              label: '휴식 종료',
                              child: IconButton(
                                onPressed: widget.onCancel,
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(
                                  SetflowIcons.close,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_expanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      SetflowSpacing.sm,
                      0,
                      SetflowSpacing.sm,
                      SetflowSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: widget.onAddTime,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            minimumSize: const Size(48, 40),
                          ),
                          child: const Text('+30초'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

abstract final class AppSnackbar {
  /// Where the toast's top edge sits, as a fraction of the screen height.
  static const topFraction = .3;

  static void success(BuildContext context, String message) {
    _show(
      context,
      message,
      Icons.check_circle_rounded,
      context.setflowColors.success,
    );
  }

  static void error(BuildContext context, String message) {
    _show(context, message, Icons.error_rounded, context.setflowColors.error);
  }

  static void info(BuildContext context, String message) {
    _show(context, message, Icons.info_rounded, context.setflowColors.info);
  }

  /// A message the user can take back on the spot.
  ///
  /// For things the app decided on its own — propagating a logged set's numbers
  /// onto the sets still ahead of it, say. Announcing that without a way back
  /// would make the app's guess cost more to undo than it saved.
  static void undoable(
    BuildContext context,
    String message, {
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    _show(
      context,
      message,
      Icons.check_circle_rounded,
      context.setflowColors.success,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static OverlayEntry? _current;

  static void _show(
    BuildContext context,
    String message,
    IconData icon,
    Color color, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    // The root overlay is inside the web app frame (the frame wraps the
    // Navigator in MaterialApp.builder), so the toast keeps the phone width
    // instead of stretching across the browser.
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    dismiss();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _Toast(
        message: message,
        icon: icon,
        iconColor: color,
        actionLabel: actionLabel,
        onAction: onAction,
        onDismiss: () {
          if (identical(_current, entry)) _current = null;
          entry.remove();
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }

  /// Takes the visible toast down early — a new one replacing it, or a screen
  /// that no longer wants it around.
  static void dismiss() {
    _current?.remove();
    _current = null;
  }
}

class _Toast extends StatefulWidget {
  const _Toast({
    required this.message,
    required this.icon,
    required this.iconColor,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onDismiss;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  static const _visible = Duration(seconds: 3);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SetflowMotion.standard,
    reverseDuration: SetflowMotion.micro,
  );

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    // The timer lives with the widget, not with the entry: when the tree is
    // torn down (a test ending, the app closing) dispose cancels it, which is
    // what keeps a pending timer from outliving the binding.
    _timer = Timer(_visible, _close);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    _timer?.cancel();
    if (!mounted) return;
    await _controller.reverse();
    if (!mounted) return;
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    // Measured off the overlay itself rather than MediaQuery: the overlay is
    // what the toast is actually laid out in, and on web that box is the app
    // frame, not the window.
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) => Padding(
          padding: EdgeInsets.only(
            top: constraints.maxHeight * AppSnackbar.topFraction,
            left: SetflowSpacing.lg,
            right: SetflowSpacing.lg,
          ),
          child: Align(alignment: Alignment.topCenter, child: _body(context)),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final snack = Theme.of(context).snackBarTheme;

    return FadeTransition(
      opacity: _controller,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, -.25), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _controller,
            curve: SetflowMotion.standardCurve,
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Semantics(
            liveRegion: true,
            child: Material(
              color: snack.backgroundColor ?? SetflowColors.ink,
              elevation: 8,
              borderRadius: BorderRadius.circular(SetflowRadii.sm),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                // Tapping gets rid of it — a message sitting in the middle of
                // the screen has to be dismissible on the spot.
                onTap: _close,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SetflowSpacing.lg,
                    vertical: 14,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.icon, color: widget.iconColor, size: 21),
                      const SizedBox(width: SetflowSpacing.md),
                      Flexible(
                        child: Text(
                          widget.message,
                          style: snack.contentTextStyle,
                        ),
                      ),
                      if (widget.onAction != null) ...[
                        const SizedBox(width: SetflowSpacing.sm),
                        TextButton(
                          onPressed: () {
                            widget.onAction!();
                            _close();
                          },
                          style: TextButton.styleFrom(
                            // The toast paints on ink, where the only readable
                            // foreground is white.
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: SetflowSpacing.sm,
                            ),
                            minimumSize: const Size(0, 36),
                          ),
                          child: Text(widget.actionLabel ?? '되돌리기'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void showMessage(BuildContext context, String message) {
  AppSnackbar.info(context, message);
}

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
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: SetflowWeight.medium,
            ),
          ),
        ],
      ),
    );
  }
}

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
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

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

/// Every modal sheet in the app opens through here.
///
/// `showModalBottomSheet` leaves the bottom inset to the caller: with
/// `useSafeArea: true` Flutter wraps the sheet in `SafeArea(bottom: false)` so
/// the sheet's own background can still paint under the gesture bar. Callers
/// kept forgetting to put that inset back on the *content*, and the action row
/// ended up under the system navigation bar — on the number dial that meant the
/// only 적용 that writes a set was unreachable.
///
/// So the inset is added once, here. Nesting costs nothing: a sheet that already
/// wraps itself in `SafeArea` sees the padding as consumed and adds none of its
/// own. Keyboard insets stay with the content — `SafeArea` does not consume
/// `MediaQuery.viewInsets`, so the two compose instead of doubling up.
Future<T?> showSetflowSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool showDragHandle = true,
  bool isDismissible = true,
  bool enableDrag = true,
  Color? backgroundColor,
  BoxConstraints? constraints,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    showDragHandle: showDragHandle,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: backgroundColor,
    // 머티리얼3는 넓은 화면에서 시트를 640px 가운데 섬으로 만든다 — 앱이
    // 폴드/태블릿에서 풀폭으로 가기로 한 결정(432 프레임 제거)과 어긋난다.
    // 시트도 화면 폭을 그대로 쓴다.
    constraints: constraints ?? const BoxConstraints(maxWidth: double.infinity),
    // Keeps the sheet clear of the status bar; the bottom half is ours below.
    useSafeArea: true,
    builder: (sheetContext) =>
        SafeArea(top: false, child: builder(sheetContext)),
  );
}

Future<T?> showAppActionSheet<T>(
  BuildContext context, {
  String? title,
  String? subtitle,
  required List<SheetAction<T>> actions,
}) {
  return showSetflowSheet<T>(
    context,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
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
                        style: theme.textTheme.titleMedium?.copyWith(),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
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
                    style: theme.textTheme.bodyLarge?.copyWith(
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
                          style: theme.textTheme.bodySmall?.copyWith(
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
                  child: _SetflowNavDestination(
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

class _SetflowNavDestination extends StatelessWidget {
  const _SetflowNavDestination({
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
                  const SizedBox(height: SetflowSpacing.xs),
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: EdgeInsets.only(
                right: i == items.length - 2 ? 0 : SetflowSpacing.sm,
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
                      style: theme.textTheme.labelMedium?.copyWith(
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
