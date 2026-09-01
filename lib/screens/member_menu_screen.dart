import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/auth_gate.dart';
import '../widgets/common.dart';
import '../widgets/portal.dart';
import '../widgets/pro_access_gate.dart';
import 'detail_screens.dart';
import 'member_membership_screen.dart';
import 'member_screens.dart';
import 'welcome_screen.dart';
import 'workout_screens.dart';

/// 전체 메뉴 — 홈 왼쪽 위 그리드 버튼이 여는 서랍. OKX의 서랍과 같은 문법:
/// 큰 화면 제목 없이(이름이 곧 제목) 프로필이 먼저 서고, 기능은 섹션
/// 컨테이너 안의 **아이콘 그리드**다 — 설정처럼 줄로 세우면 목록이지 서랍이
/// 아니다(실기기 보고: "사진처럼 하라고 했는데 설정 페이지처럼 만들어놨네").
class MemberMenuScreen extends StatelessWidget {
  const MemberMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = AppScope.of(context);
    final signedIn = Auth.instance.hasAuthenticatedUser;
    final name = state.memberDisplayName.isEmpty
        ? '게스트'
        : state.memberDisplayName;
    final today = state.dateOnly(DateTime.now());

    return Scaffold(
      // 제목 없는 앱바 — 뒤로가기 하나면 된다. 서랍의 제목은 아래 이름이다.
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          SetflowSpacing.gutter,
          0,
          SetflowSpacing.gutter,
          28,
        ),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.headlineLarge),
                    const SizedBox(height: SetflowSpacing.xxs),
                    Text(
                      signedIn ? '기록이 계정에 백업돼요' : '로그인하면 기록이 백업돼요',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!signedIn)
                TextButton(
                  key: const ValueKey('menu-sign-in'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                  ),
                  child: const Text('로그인'),
                ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.xl),
          _MenuSection(
            title: '운동',
            items: [
              _MenuItem(
                keyValue: 'menu-routines',
                icon: SetflowIcons.routine,
                label: '내 루틴',
                builder: (_) => const RoutinesScreen(),
              ),
              _MenuItem(
                keyValue: 'menu-market',
                icon: SetflowIcons.market,
                label: '전문가 루틴',
                builder: (_) => const MarketScreen(),
              ),
              _MenuItem(
                keyValue: 'menu-library',
                icon: SetflowIcons.exerciseSearch,
                label: '운동 찾기',
                builder: (_) => ExerciseLibraryScreen(date: today),
              ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.md),
          _MenuSection(
            title: '데이터',
            items: [
              _MenuItem(
                keyValue: 'menu-stats',
                icon: SetflowIcons.stats,
                label: '대시보드',
                builder: (_) => const DashboardScreen(),
              ),
              _MenuItem(
                keyValue: 'menu-body',
                icon: SetflowIcons.goal,
                label: '체성분',
                builder: (_) => const BodyCompositionScreen(),
              ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.md),
          _MenuSection(
            title: '코칭·센터',
            items: [
              _MenuItem(
                keyValue: 'menu-coaching',
                icon: SetflowIcons.coaching,
                label: '코칭',
                builder: (_) => const CoachingScreen(),
              ),
              _MenuItem(
                keyValue: 'menu-membership',
                icon: SetflowIcons.membership,
                label: '운동 장소',
                reason: AuthReason.membership,
                builder: (_) => const MemberMembershipScreen(),
              ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.md),
          _MenuSection(
            title: '계정',
            items: [
              _MenuItem(
                keyValue: 'menu-settings',
                icon: SetflowIcons.settings,
                label: '설정',
                builder: (_) => const SettingsScreen(),
              ),
              // 트레이너 전환은 헤더 세그먼트가 아니라 이 서랍의 타일이다 —
              // 승인된 계정에게만 보인다(없는 문은 그리지 않는다).
              if (proPortalAvailable(state))
                _MenuItem(
                  keyValue: 'menu-portal-trainer',
                  icon: SetflowIcons.pro,
                  label: '${proPortalLabel(state)} 화면',
                  onTap: _switchToPro,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _switchToPro(BuildContext context) async {
    final state = AppScope.of(context);
    // 승인 게이트: 로그인만으로는 부족하다 — 관리자 승인이 문의 열쇠다.
    if (!await requireProAccess(context)) return;
    if (!context.mounted) return;
    // 전환은 셸을 통째로 갈아끼운다 — 이 메뉴 라우트가 위에 남으면 새 셸을 덮는다.
    Navigator.of(context).pop();
    await state.switchPortal(AppPortal.trainer);
  }
}

class _MenuItem {
  const _MenuItem({
    required this.keyValue,
    required this.icon,
    required this.label,
    this.reason,
    this.builder,
    this.onTap,
  });

  final String keyValue;
  final IconData icon;
  final String label;

  /// Set when the destination cannot work for a guest.
  final AuthReason? reason;
  final WidgetBuilder? builder;
  final Future<void> Function(BuildContext context)? onTap;
}

/// OKX 서랍의 섹션 — 컨테이너 안에 제목과 아이콘 그리드(아이콘 위, 라벨 아래).
class _MenuSection extends StatelessWidget {
  const _MenuSection({required this.title, required this.items});

  final String title;
  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SetflowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: SetflowSpacing.lg),
          // 폭만 4열로 고정하고 높이는 내용이 정한다 — 고정 높이 그리드는
          // 시스템 글자 배율에서 어김없이 모자란다(AGENTS.md 8절).
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth =
                  (constraints.maxWidth - SetflowSpacing.sm * 3) / 4;
              return Wrap(
                spacing: SetflowSpacing.sm,
                runSpacing: SetflowSpacing.lg,
                children: [
                  for (final item in items)
                    SizedBox(
                      width: itemWidth,
                      child: _MenuGridItem(item: item),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MenuGridItem extends StatelessWidget {
  const _MenuGridItem({required this.item});

  final _MenuItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      key: ValueKey(item.keyValue),
      borderRadius: BorderRadius.circular(SetflowRadii.sm),
      onTap: () => _open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SetflowSpacing.xs),
        child: Column(
          children: [
            Icon(item.icon, size: 26),
            const SizedBox(height: SetflowSpacing.sm),
            Text(
              item.label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final custom = item.onTap;
    if (custom != null) {
      await custom(context);
      return;
    }
    final gate = item.reason;
    if (gate != null && !await requireSignIn(context, reason: gate)) return;
    if (!context.mounted) return;
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: item.builder!));
  }
}
