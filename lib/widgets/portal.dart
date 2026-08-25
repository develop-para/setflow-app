import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../theme.dart';
import '../theme/icons.dart';
import 'brand.dart';
import 'pro_access_gate.dart';

/// Whether this account has a second surface to switch to at all.
///
/// The pro side belongs to accounts an admin has approved, so a guest or a
/// plain member has nothing behind that segment — offering the door and then
/// refusing at the gate is worse than never showing the door.
///
/// The escape hatch matters as much as the gate: whoever is already standing in
/// the pro shell keeps the control that takes them back, even while access is
/// still loading (or in the demo build, which has no access to load).
bool portalSwitcherVisible(AppState state) =>
    state.portal == AppPortal.trainer ||
    proAccessStateOf(state) == ProAccessState.approved;

/// Header control that swaps the whole product surface, OKX "Exchange | Wallet"
/// style. It is deliberately not a TabBar: the two segments own different
/// shells, so selecting one runs [PortalTransitionOverlay] over the swap.
///
/// The segments are glyphs, not words: "일반인" was never a name anyone calls
/// themselves, and the two sides read faster as 사람 vs 자격증 than as text.
class PortalSwitcher extends StatelessWidget {
  const PortalSwitcher({this.width = 132, super.key});

  final double width;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!portalSwitcherVisible(state)) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final selected = state.portal;
    // Only screen readers still hear the role names; the glyph is one door.
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
          borderRadius: BorderRadius.circular(SetflowRadii.full),
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
                      borderRadius: BorderRadius.circular(SetflowRadii.full),
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
                      icon: SetflowIcons.my,
                      activeIcon: SetflowIcons.myActive,
                      semanticLabel: '회원',
                      active: selected == AppPortal.client,
                      onTap: () => _switch(context, state, AppPortal.client),
                    ),
                  ),
                  Expanded(
                    child: _PortalSegment(
                      key: const ValueKey('portal-segment-trainer'),
                      icon: SetflowIcons.pro,
                      activeIcon: SetflowIcons.proActive,
                      semanticLabel: trainerLabel,
                      active: selected == AppPortal.trainer,
                      onTap: () => _switch(context, state, AppPortal.trainer),
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

  Future<void> _switch(
    BuildContext context,
    AppState state,
    AppPortal target,
  ) async {
    if (state.portal == target) return;
    HapticFeedback.selectionClick();
    // The client side works fine as a guest. The pro side needs a signed-in
    // account *that an admin has approved* — signing in is not enough, so this
    // asks the approval gate rather than the auth gate.
    if (target == AppPortal.trainer && !await requireProAccess(context)) {
      return;
    }
    await state.switchPortal(target);
  }
}

class _PortalSegment extends StatelessWidget {
  const _PortalSegment({
    required this.icon,
    required this.activeIcon,
    required this.semanticLabel,
    required this.active,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final IconData activeIcon;

  /// What the glyph means, spoken. Nothing draws this.
  final String semanticLabel;

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: active,
      label: '$semanticLabel 포탈',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SetflowRadii.full),
        // Selection has to read without colour, so it rides the outline ->
        // filled swap on top of the sliding pill.
        child: Center(
          child: AnimatedSwitcher(
            duration: SetflowMotion.standard,
            switchInCurve: SetflowMotion.standardCurve,
            child: Icon(
              active ? activeIcon : icon,
              key: ValueKey(active),
              size: 20,
              color: active
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// The switcher row every shell puts above its content.
class PortalHeaderBar extends StatelessWidget {
  const PortalHeaderBar({this.trailing, this.switcher = true, super.key});

  /// Optional shell-specific actions on the right edge.
  final Widget? trailing;

  /// Whether this page is one that offers the portal switch at all.
  ///
  /// The switch belongs to the shell's home page. Every other destination —
  /// 기록 above all — needs its own full height, and a member/trainer toggle
  /// hovering over a set you are logging is noise, not navigation.
  final bool switcher;

  @override
  Widget build(BuildContext context) {
    final showSwitcher =
        switcher && portalSwitcherVisible(AppScope.of(context));
    // The SafeArea stays even with nothing to show: the pages below strip their
    // own top inset because this bar already ate it, so collapsing the whole
    // widget would slide the first page under the status bar.
    if (!showSwitcher && trailing == null) {
      return const SafeArea(bottom: false, child: SizedBox.shrink());
    }
    return SafeArea(
      bottom: false,
      child: SizedBox(
        // 40px 알약에 52는 위아래 6px씩 — 44로 줄여도 터치 타깃(40)은 그대로다.
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (showSwitcher) const Center(child: PortalSwitcher()),
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
                  fontSize: SetflowFontSize.display,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
