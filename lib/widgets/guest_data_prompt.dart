import 'package:flutter/material.dart';

import '../theme.dart';
import '../theme/icons.dart';
import 'common.dart';

/// Asks whether the records made before signing up belong to this account.
///
/// The app is usable without an account, so by the time someone signs up they
/// may already have weeks of workouts on the device. Two wrong answers are
/// possible and only one of them is recoverable:
///
/// * Silently adopting them hands one person's training log to whoever signs
///   in first on a shared phone. Nothing about "first to sign in" proves
///   ownership.
/// * Silently dropping them is what the app used to do, and it makes signing
///   up feel like a punishment.
///
/// So it asks. Declining is safe — the records stay on the device and come
/// back on sign-out — which is what the sheet says, so "아니요" is not a guess.
Future<bool> askToAdoptGuestData(
  BuildContext context, {
  required int workoutDays,
  required int routineCount,
}) async {
  final adopted = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    // Losing track of this question would leave the records stranded with no
    // second prompt, so it cannot be dismissed by tapping outside.
    isDismissible: false,
    enableDrag: false,
    builder: (_) =>
        _GuestDataSheet(workoutDays: workoutDays, routineCount: routineCount),
  );
  return adopted ?? false;
}

class _GuestDataSheet extends StatelessWidget {
  const _GuestDataSheet({
    required this.workoutDays,
    required this.routineCount,
  });

  final int workoutDays;
  final int routineCount;

  String get _summary {
    final parts = <String>[
      if (workoutDays > 0) '운동 기록 $workoutDays일치',
      if (routineCount > 0) '루틴 $routineCount개',
    ];
    return parts.join(' · ');
  }

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
              SetflowIcons.record,
              size: 32,
              color: theme.colorScheme.onSurface,
            ),
            const SizedBox(height: SetflowSpacing.lg),
            Text(
              '이 기기의 기록을 가져올까요?',
              key: const ValueKey('guest-adopt-title'),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: SetflowSpacing.sm),
            Text(
              '로그인 전에 만든 $_summary이 있어요.\n가져오면 계정에 저장돼 다른 기기에서도 보여요.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SetflowSpacing.xl),
            AppButton(
              key: const ValueKey('guest-adopt-confirm'),
              label: '가져오기',
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: SetflowSpacing.xs),
            TextButton(
              key: const ValueKey('guest-adopt-decline'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('아니요, 이 계정 기록만 볼게요'),
            ),
            const SizedBox(height: SetflowSpacing.sm),
            Text(
              // Says what happens to the data either way. Without this the
              // safe answer looks like the destructive one.
              '가져오지 않아도 기기에서 지워지지 않아요. 로그아웃하면 다시 보여요.',
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
}
