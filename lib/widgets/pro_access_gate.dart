import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/business_repository.dart';
import '../screens/welcome_screen.dart';
import '../theme.dart';
import '../theme/icons.dart';
import 'auth_gate.dart';
import 'common.dart';

/// The trainer side is *approved*, not merely signed in.
///
/// Two different policies are easy to confuse:
/// * A **member** signs up and is immediately done — nothing to review.
/// * A **trainer** signs up the same way, then submits an application that an
///   admin approves by hand. Until that happens the account exists and the
///   client side works, but the pro portal stays shut.
///
/// The server already enforces this: `BusinessAccess.availableRoles` only
/// contains [UserRole.trainer] once `trainers.status == approved`. This gate is
/// the app telling the truth about it — and, more usefully, telling the person
/// which of the four states they are in and what to do next.
enum ProAccessState {
  /// Not signed in at all.
  signedOut,

  /// Signed in, never applied.
  notApplied,

  /// Applied, waiting on an admin.
  pending,

  /// Reviewed and turned down. [BusinessAccess.rejectReason] says why.
  rejected,

  /// Approved — the portal opens.
  approved,
}

ProAccessState proAccessStateOf(AppState state) {
  final access = state.businessAccess;
  if (access == null) return ProAccessState.signedOut;
  if (access.canUse(UserRole.trainer) || access.canUse(UserRole.gym)) {
    return ProAccessState.approved;
  }
  return switch (access.trainerApplication?.status) {
    BusinessApplicationStatus.pending => ProAccessState.pending,
    BusinessApplicationStatus.rejected => ProAccessState.rejected,
    BusinessApplicationStatus.approved => ProAccessState.approved,
    _ => ProAccessState.notApplied,
  };
}

/// True when the pro portal may open. Otherwise explains the current state and
/// offers the one action that moves it forward.
Future<bool> requireProAccess(BuildContext context) async {
  // Signing in is a prerequisite, not the whole answer.
  if (!await requireSignIn(context, reason: AuthReason.pro)) return false;
  if (!context.mounted) return false;

  final state = AppScope.of(context);
  // A fresh sign-in may not have loaded access yet; without this the gate would
  // report "not applied" to someone who is actually approved.
  if (state.businessAccess == null && state.usesLiveBusinessData) {
    await state.refreshBusinessAccess();
    if (!context.mounted) return false;
  }

  final access = proAccessStateOf(state);
  if (access == ProAccessState.approved) return true;

  await showSetflowSheet<void>(
    context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) =>
        _ProAccessSheet(state: access, reason: state.businessAccess),
  );
  return false;
}

class _ProAccessSheet extends StatelessWidget {
  const _ProAccessSheet({required this.state, required this.reason});

  final ProAccessState state;
  final BusinessAccess? reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, detail) = switch (state) {
      ProAccessState.pending => (
        '심사 중이에요',
        '제출한 서류를 관리자가 확인하고 있어요. 승인되면 트레이너 화면이 열려요.',
      ),
      ProAccessState.rejected => (
        '승인되지 않았어요',
        reason?.rejectReason ?? '제출 정보를 보완해 다시 신청해주세요.',
      ),
      _ => (
        '트레이너 등록이 필요해요',
        '회원 화면은 지금처럼 쓰시고, 트레이너 기능은 등록 정보를 제출하고 승인받은 뒤 열려요.',
      ),
    };
    final canApply = state != ProAccessState.pending;

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
              state == ProAccessState.pending
                  ? SetflowIcons.pending
                  : SetflowIcons.pro,
              size: 32,
              color: theme.colorScheme.onSurface,
            ),
            const SizedBox(height: SetflowSpacing.lg),
            Text(
              title,
              key: const ValueKey('pro-gate-title'),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: SetflowSpacing.sm),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SetflowSpacing.xl),
            if (canApply)
              AppButton(
                key: const ValueKey('pro-gate-apply'),
                label: state == ProAccessState.rejected
                    ? '다시 신청하기'
                    : '트레이너 등록하기',
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  await navigator.push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const BusinessSetupScreen(role: UserRole.trainer),
                    ),
                  );
                },
              ),
            const SizedBox(height: SetflowSpacing.xs),
            TextButton(
              key: const ValueKey('pro-gate-dismiss'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('닫기'),
            ),
          ],
        ),
      ),
    );
  }
}
