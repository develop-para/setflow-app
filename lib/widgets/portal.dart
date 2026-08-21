import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../theme.dart';
import 'brand.dart';

/// Header control that swaps the whole product surface, OKX "Exchange | Wallet"
/// style. It is deliberately not a TabBar: the two segments own different
/// shells, so selecting one runs [PortalTransitionOverlay] over the swap.
class PortalSwitcher extends StatelessWidget {
  const PortalSwitcher({this.width = 208, super.key});

  final double width;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final selected = state.portal;
    final trainerLabel = switch (state.portalTrainerRole) {
      UserRole.gym => '헬스장',
      UserRole.admin => '운영',
      _ => '트레이너',
    };

    return SizedBox(
      width: width,
      height: 40,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dark ? SetflowNeutral.n800 : SetflowNeutral.n100,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Stack(
            children: [
              AnimatedAlign(
                duration: SetflowMotion.standard,
                curve: SetflowMotion.standardCurve,
                alignment: selected == AppPortal.client
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: .5,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: dark ? SetflowNeutral.n900 : SetflowColors.surface,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: dark ? null : SetflowShadows.level1,
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _PortalSegment(
                      key: const ValueKey('portal-segment-client'),
                      label: '일반인',
                      active: selected == AppPortal.client,
                      onTap: () => _switch(state, AppPortal.client),
                    ),
                  ),
                  Expanded(
                    child: _PortalSegment(
                      key: const ValueKey('portal-segment-trainer'),
                      label: trainerLabel,
                      active: selected == AppPortal.trainer,
                      onTap: () => _switch(state, AppPortal.trainer),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _switch(AppState state, AppPortal target) {
    if (state.portal == target) return;
    HapticFeedback.selectionClick();
    state.switchPortal(target);
  }
}

class _PortalSegment extends StatelessWidget {
  const _PortalSegment({
    required this.label,
    required this.active,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: active,
      label: '$label 포탈',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: SetflowMotion.standard,
            curve: SetflowMotion.standardCurve,
            // Must start from the text theme: AnimatedDefaultTextStyle
            // *replaces* the ambient style, so a bare TextStyle here would drop
            // the app font and render these two labels in the system face.
            style: (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
              fontSize: 14,
              fontWeight: active ? FontWeight.w900 : FontWeight.w600,
              color: active
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
            ),
            child: Text(label, maxLines: 1),
          ),
        ),
      ),
    );
  }
}

/// The switcher row every shell puts above its content.
class PortalHeaderBar extends StatelessWidget {
  const PortalHeaderBar({this.trailing, super.key});

  /// Optional shell-specific actions on the right edge.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 52,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Center(child: PortalSwitcher()),
            if (trailing != null)
              Positioned(right: SetflowSpacing.sm, child: trailing!),
          ],
        ),
      ),
    );
  }
}

/// Full-screen brand hold shown while the shell underneath is swapped. Reads as
/// "a different product is opening", which a route transition cannot convey.
class PortalTransitionOverlay extends StatefulWidget {
  const PortalTransitionOverlay({super.key});

  @override
  State<PortalTransitionOverlay> createState() =>
      _PortalTransitionOverlayState();
}

class _PortalTransitionOverlayState extends State<PortalTransitionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // One-shot on purpose: a repeating pulse would keep the widget tree from
    // ever settling, which stalls every pumpAndSettle in the test suite.
    _controller = AnimationController(vsync: this, duration: SetflowMotion.page)
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '포탈을 전환하는 중',
      liveRegion: true,
      child: ColoredBox(
        color: theme.scaffoldBackgroundColor,
        child: Center(
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _controller,
              curve: Curves.easeOut,
            ),
            child: ScaleTransition(
              scale: Tween(begin: .82, end: 1.0).animate(
                CurvedAnimation(
                  parent: _controller,
                  curve: SetflowMotion.kineticCurve,
                ),
              ),
              child: const ExcludeSemantics(
                child: SetflowWordmark(
                  key: ValueKey('portal-transition-logo'),
                  fontSize: 30,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
