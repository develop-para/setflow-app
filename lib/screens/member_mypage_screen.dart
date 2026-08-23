import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/auth_gate.dart';
import '../widgets/common.dart';
import 'member_goal_screen.dart';
import 'member_membership_screen.dart';
import 'member_screens.dart';
import 'password_screens.dart';
import 'welcome_screen.dart';

/// The "마이" tab: the account hub the bottom bar's last slot points at.
///
/// It exists because the bar reserves its center for logging a workout, which
/// leaves four destinations for five surfaces. Coaching and the report moved
/// here rather than losing their entry point entirely.
class MyPageScreen extends StatelessWidget {
  const MyPageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final signedIn = Auth.instance.hasAuthenticatedUser;
    return Scaffold(
      appBar: AppBar(title: const Text('마이')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          SetflowCard(
            child: Row(
              children: [
                Icon(SetflowIcons.myActive, color: SetflowColors.ink, size: 30),
                const SizedBox(width: SetflowSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.memberDisplayName.isEmpty
                            ? '게스트'
                            : state.memberDisplayName,
                        style: const TextStyle(
                          fontSize: SetflowFontSize.titleLarge,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        signedIn ? '클라우드 동기화 중' : '로그인하면 기록이 백업돼요',
                        style: const TextStyle(
                          fontSize: SetflowFontSize.caption,
                          color: SetflowColors.secondaryText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!signedIn)
                  TextButton(
                    key: const ValueKey('mypage-sign-in'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                    ),
                    child: const Text('로그인'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.xl),
          _MyPageEntry(
            key: const ValueKey('mypage-routines'),
            icon: SetflowIcons.routine,
            title: '내 루틴',
            subtitle: '루틴 만들기와 공유',
            builder: (_) => const RoutinesScreen(),
          ),
          _MyPageEntry(
            key: const ValueKey('mypage-coaching'),
            icon: SetflowIcons.coaching,
            title: '코칭',
            subtitle: '트레이너 상담 신청과 진행 상황',
            builder: (_) => const CoachingScreen(),
          ),
          _MyPageEntry(
            icon: SetflowIcons.goal,
            title: '운동 목표',
            subtitle: '추천 구성에 반영되는 목표',
            builder: (_) => const MemberGoalScreen(),
          ),
          _MyPageEntry(
            icon: SetflowIcons.membership,
            title: '이용권',
            subtitle: '센터 회원권과 잔여 세션',
            // A membership belongs to a person, so it cannot resolve for a
            // guest — gate it instead of showing a permanently empty screen.
            reason: AuthReason.membership,
            builder: (_) => const MemberMembershipScreen(),
          ),
          const Divider(height: SetflowSpacing.section),
          // Only an email account has a password to change. Social sign-ins
          // authenticate elsewhere, so offering it would open a form that can
          // never succeed.
          if (Auth.instance.currentUser?.email?.isNotEmpty ?? false)
            _MyPageEntry(
              key: const ValueKey('mypage-change-password'),
              icon: SetflowIcons.password,
              title: '비밀번호 변경',
              subtitle: Auth.instance.currentUser?.email ?? '',
              builder: (_) =>
                  const NewPasswordScreen(requiresCurrentPassword: true),
              onResult: (context, changed) {
                if (changed == true) {
                  AppSnackbar.success(context, '비밀번호를 변경했어요.');
                }
              },
            ),
          _MyPageEntry(
            icon: SetflowIcons.settings,
            title: '설정',
            subtitle: '알림 · 운동 환경 · 계정',
            builder: (_) => const SettingsScreen(),
          ),
        ],
      ),
    );
  }
}

class _MyPageEntry extends StatelessWidget {
  const _MyPageEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.builder,
    this.reason,
    this.onResult,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;

  /// Set when the destination cannot work for a guest.
  final AuthReason? reason;

  /// Runs with whatever the pushed route popped, for destinations that report
  /// back (a password change confirming it took effect).
  final void Function(BuildContext context, Object? result)? onResult;

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
    final result = await Navigator.of(
      context,
    ).push<Object?>(MaterialPageRoute(builder: builder));
    if (!context.mounted) return;
    onResult?.call(context, result);
  }
}
