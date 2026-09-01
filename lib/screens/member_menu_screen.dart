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

/// 전체 메뉴 — 홈 왼쪽 위 그리드 버튼이 여는 바로가기 서랍.
///
/// OKX의 왼쪽 상단 버튼과 같은 발상이다: 바텀바는 다섯 자리뿐이라 자리를 잃은
/// 화면들(통계·체성분·코칭·설정…)이 전부 여기 모인다. 마이 탭과의 역할 구분:
/// 마이는 "내가 얼마나 했나"(프로필·숫자), 여기는 "어디로 갈까"(바로가기)다.
/// 껍데기는 카드 그리드가 아니라 섹션 제목 + 헤어라인 목록 — 설정·마이와 같은
/// 언어를 쓴다.
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
      appBar: AppBar(title: const Text('전체 메뉴')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          SetflowSpacing.gutter,
          SetflowSpacing.sm,
          SetflowSpacing.gutter,
          28,
        ),
        children: [
          // 프로필은 한 줄이면 된다 — 숫자 셋은 마이 탭의 것이다.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.headlineSmall),
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
          const SectionTitle('운동'),
          _MenuEntry(
            key: const ValueKey('menu-routines'),
            icon: SetflowIcons.routine,
            title: '내 루틴',
            subtitle: '루틴 만들기와 공유',
            builder: (_) => const RoutinesScreen(),
          ),
          _MenuEntry(
            key: const ValueKey('menu-market'),
            icon: SetflowIcons.market,
            title: '전문가 루틴',
            subtitle: '트레이너가 만든 루틴 둘러보기',
            builder: (_) => const MarketScreen(),
          ),
          _MenuEntry(
            key: const ValueKey('menu-library'),
            icon: SetflowIcons.exerciseSearch,
            title: '운동 찾기',
            subtitle: '운동을 골라 오늘에 추가',
            builder: (_) => ExerciseLibraryScreen(date: today),
          ),
          const Divider(height: SetflowSpacing.section),
          const SectionTitle('데이터'),
          _MenuEntry(
            key: const ValueKey('menu-stats'),
            icon: SetflowIcons.stats,
            title: '운동 대시보드',
            subtitle: '주간 볼륨과 세트 흐름',
            builder: (_) => const DashboardScreen(),
          ),
          _MenuEntry(
            key: const ValueKey('menu-body'),
            icon: SetflowIcons.goal,
            title: '체성분',
            subtitle: '체중과 신체 변화 기록',
            builder: (_) => const BodyCompositionScreen(),
          ),
          const Divider(height: SetflowSpacing.section),
          const SectionTitle('코칭·센터'),
          _MenuEntry(
            key: const ValueKey('menu-coaching'),
            icon: SetflowIcons.coaching,
            title: '코칭',
            subtitle: '트레이너 상담 신청과 진행 상황',
            builder: (_) => const CoachingScreen(),
          ),
          _MenuEntry(
            key: const ValueKey('menu-membership'),
            icon: SetflowIcons.membership,
            title: '운동 장소 및 센터',
            subtitle: '여러 헬스장과 센터 연결 관리',
            reason: AuthReason.membership,
            builder: (_) => const MemberMembershipScreen(),
          ),
          const Divider(height: SetflowSpacing.section),
          const SectionTitle('계정'),
          _MenuEntry(
            key: const ValueKey('menu-settings'),
            icon: SetflowIcons.settings,
            title: '설정',
            subtitle: '계정 · 알림 · 운동 환경 · 개인정보',
            builder: (_) => const SettingsScreen(),
          ),
          // 트레이너 전환은 헤더 세그먼트가 아니라 여기의 한 줄이다(2026-09-01).
          // OKX의 Exchange|Wallet은 모두가 양쪽을 쓰기에 성립하는 세그먼트지만,
          // 회원과 트레이너를 오가는 사람은 극소수다 — 승인된 계정에게만 문이 보인다.
          if (proPortalAvailable(state)) ...[
            const Divider(height: SetflowSpacing.section),
            const SectionTitle('전문가'),
            ListTile(
              key: const ValueKey('menu-portal-trainer'),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: SetflowSpacing.sm,
              ),
              leading: const Icon(SetflowIcons.pro),
              title: Text(
                '${proPortalLabel(state)} 화면으로 전환',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('회원 관리 · 상담 · 운영'),
              trailing: const Icon(SetflowIcons.forward),
              onTap: () => _switchToPro(context),
            ),
          ],
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

class _MenuEntry extends StatelessWidget {
  const _MenuEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.builder,
    this.reason,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;

  /// Set when the destination cannot work for a guest.
  final AuthReason? reason;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: SetflowSpacing.sm),
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle),
      trailing: const Icon(SetflowIcons.forward),
      onTap: () => _open(context),
    );
  }

  Future<void> _open(BuildContext context) async {
    final gate = reason;
    if (gate != null && !await requireSignIn(context, reason: gate)) return;
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: builder));
  }
}
