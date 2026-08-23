import 'package:flutter/material.dart';

import '../app_state.dart';
import '../screens/email_auth_screen.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../theme/icons.dart';
import 'common.dart';

/// Guest-first gating.
///
/// The app is fully usable without an account: browsing, planning and logging
/// a workout all run on the local store. Only the things that genuinely need a
/// server — anything that leaves this device or belongs to a person — ask for
/// a sign-in, and they ask *at the moment of the action* rather than behind a
/// wall at launch.
///
/// Call [requireSignIn] right before performing such an action:
///
/// ```dart
/// if (!await requireSignIn(context, reason: AuthReason.community)) return;
/// ```
///
/// It returns true immediately when a user is already signed in, otherwise it
/// explains why the account is needed and returns whether sign-in succeeded.
enum AuthReason {
  community('커뮤니티에 흔적을 남기려면', '남긴 글·댓글·좋아요가 계정에 연결돼요.'),
  coaching('트레이너 상담을 신청하려면', '상담 내용과 답변을 계정으로 주고받아요.'),
  share('루틴을 공유하려면', '공유 링크는 내 계정으로 발급돼요.'),
  membership('이용권을 확인하려면', '센터가 발급한 회원권은 계정에 연결돼요.'),
  pro('트레이너 화면을 쓰려면', '회원 관리와 정산은 승인된 계정만 접근할 수 있어요.'),
  backup('기록을 백업하려면', '기기를 바꿔도 기록이 따라와요.');

  const AuthReason(this.title, this.detail);

  /// Completes the sentence "<title> 로그인이 필요해요".
  final String title;
  final String detail;
}

/// True when the action may proceed. Opens the sign-in sheet when it may not.
Future<bool> requireSignIn(
  BuildContext context, {
  required AuthReason reason,
}) async {
  if (Auth.instance.hasAuthenticatedUser) return true;
  final signedIn = await showSetflowSheet<bool>(
    context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _SignInPrompt(reason: reason),
  );
  if (signedIn != true) return false;
  if (!context.mounted) return false;
  // The shell keys off role, and without a live business repository nothing
  // else promotes a fresh guest.
  final state = AppScope.of(context);
  if (state.role == UserRole.guest) state.chooseRole(UserRole.member);
  return true;
}

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt({required this.reason});

  final AuthReason reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SetflowSpacing.xxl,
          0,
          SetflowSpacing.xxl,
          SetflowSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              SetflowIcons.signIn,
              size: 32,
              color: theme.colorScheme.onSurface,
            ),
            const SizedBox(height: SetflowSpacing.lg),
            Text(
              '${reason.title}\n로그인이 필요해요',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1.3,
              ),
            ),
            const SizedBox(height: SetflowSpacing.sm),
            Text(
              reason.detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SetflowSpacing.xl),
            AppButton(
              key: const ValueKey('auth-gate-sign-in'),
              label: '로그인',
              onPressed: () => _open(context, EmailAuthMode.signIn),
            ),
            const SizedBox(height: SetflowSpacing.sm),
            AppButton(
              key: const ValueKey('auth-gate-sign-up'),
              label: '이메일로 회원가입',
              variant: AppButtonVariant.outlined,
              onPressed: () => _open(context, EmailAuthMode.signUp),
            ),
            const SizedBox(height: SetflowSpacing.xs),
            TextButton(
              key: const ValueKey('auth-gate-dismiss'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('나중에 하기'),
            ),
            const SizedBox(height: SetflowSpacing.sm),
            Text(
              '로그인하지 않아도 운동 기록과 루틴은 계속 쓸 수 있어요.',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, EmailAuthMode mode) async {
    final navigator = Navigator.of(context);
    final authenticated = await navigator.push<bool>(
      MaterialPageRoute(builder: (_) => EmailAuthScreen(initialMode: mode)),
    );
    if (!context.mounted) return;
    navigator.pop(authenticated == true);
  }
}
