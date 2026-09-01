import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import 'brand.dart';
import 'pro_access_gate.dart';

/// Whether this account has a second surface (the pro portal) to switch to.
///
/// The pro side belongs to accounts an admin has approved, so a guest or a
/// plain member has nothing behind that door — offering it and then refusing
/// at the gate is worse than never showing it. The door itself is no longer a
/// header segment: 회원과 트레이너를 오가는 사람은 극소수라, OKX의
/// Exchange|Wallet처럼 **모두가 양쪽을 쓰는** 경우에만 성립하는 세그먼트를
/// 걷어내고 전체 메뉴의 한 줄(`menu-portal-trainer`)로 옮겼다(2026-09-01).
///
/// The escape hatch matters as much as the gate: whoever is already standing in
/// the pro shell keeps the control that takes them back, even while access is
/// still loading (or in the demo build, which has no access to load).
bool proPortalAvailable(AppState state) =>
    state.portal == AppPortal.trainer ||
    proAccessStateOf(state) == ProAccessState.approved;

/// 계정이 pro 쪽에서 서는 문의 이름 — 트레이너·헬스장·운영은 문 하나를 나눠
/// 쓰는 같은 자격이라, 화면이 아니라 라벨만 갈린다.
String proPortalLabel(AppState state) => switch (state.portalTrainerRole) {
  UserRole.gym => '헬스장',
  UserRole.admin => '운영',
  _ => '트레이너',
};

/// The header row every shell puts above its content.
class PortalHeaderBar extends StatelessWidget {
  const PortalHeaderBar({this.leading, this.trailing, super.key});

  /// Optional shell-specific context on the left edge.
  final Widget? leading;

  /// Optional shell-specific actions on the right edge.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    // The SafeArea stays even with nothing to show: the pages below strip their
    // own top inset because this bar already ate it, so collapsing the whole
    // widget would slide the first page under the status bar.
    if (leading == null && trailing == null) {
      return const SafeArea(bottom: false, child: SizedBox.shrink());
    }
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (leading != null)
              Positioned(left: SetflowSpacing.sm, child: leading!),
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
