import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/auth_gate.dart';
import '../widgets/common.dart';
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
    final signedIn = Auth.instance.hasAuthenticatedUser;
    return Scaffold(
      appBar: AppBar(title: const Text('마이')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          SetflowSpacing.gutter,
          8,
          SetflowSpacing.gutter,
          28,
        ),
        children: [
          // 회색 카드가 아니라 **이름 + 내 숫자 셋**이다. 마이는 메뉴가 아니라
          // "내가 얼마나 했나"부터 답해야 하고, 그 답은 기록에 이미 있다.
          _ProfileBlock(signedIn: signedIn),
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
            subtitle: '계정 · 알림 · 운동 환경 · 개인정보',
            builder: (_) => const SettingsScreen(),
          ),
        ],
      ),
    );
  }
}

class _ProfileBlock extends StatelessWidget {
  const _ProfileBlock({required this.signedIn});

  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = AppScope.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final sessions = state.sessions.values
        .where((s) => s.completedSets > 0)
        .toList();
    final days = sessions.length;
    final volume = sessions.fold<double>(0, (sum, s) => sum + s.volume);
    final sets = sessions.fold<int>(0, (sum, s) => sum + s.completedSets);
    final volumeText = volume >= 1000
        ? (volume / 1000).toStringAsFixed(1)
        : volume.round().toString();
    final volumeUnit = volume >= 1000 ? 't' : state.weightUnit;
    final name = state.memberDisplayName.isEmpty
        ? '게스트'
        : state.memberDisplayName;

    return Padding(
      padding: const EdgeInsets.only(
        top: SetflowSpacing.sm,
        bottom: SetflowSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                      // "동기화 중"은 영원히 안 끝나는 작업처럼 읽힌다 — 상태가
                      // 아니라 사실을 적는다.
                      signedIn ? '기록이 계정에 백업돼요' : '로그인하면 기록이 백업돼요',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
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
          const SizedBox(height: SetflowSpacing.xl),
          // 숫자 셋 — 전부 기기의 기록에서 센다. 0이어도 숨기지 않는다: "아직 0"은
          // 시작 전이라는 사실이고, 마이에서 그 사실을 감출 이유가 없다.
          Row(
            children: [
              _ProfileFigure(value: '$days', unit: '일', label: '운동한 날'),
              const SizedBox(width: SetflowSpacing.section),
              _ProfileFigure(value: '$sets', unit: '세트', label: '완료'),
              const SizedBox(width: SetflowSpacing.section),
              _ProfileFigure(
                value: volumeText,
                unit: volumeUnit,
                label: '총 볼륨',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileFigure extends StatelessWidget {
  const _ProfileFigure({
    required this.value,
    required this.unit,
    required this.label,
  });

  final String value;
  final String unit;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          maxLines: 1,
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              TextSpan(
                text: unit,
                style: theme.textTheme.labelMedium?.copyWith(color: muted),
              ),
            ],
          ),
        ),
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: muted)),
      ],
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
