import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'recommendation_profile_screen.dart';
import 'training_focus_sheet.dart';
import 'workout_recommendation_settings_sheet.dart';

String workoutRecommendationStopMessage(
  AppState state,
  DateTime date,
  ExerciseRecommendationStopReason reason,
) => switch (reason) {
  ExerciseRecommendationStopReason.missingGoal => '운동 목표를 먼저 선택해주세요.',
  ExerciseRecommendationStopReason.severePain =>
    '통증이 7/10 이상이라 자동 추천을 중단했어요. 의료 전문가의 평가를 먼저 받아주세요.',
  ExerciseRecommendationStopReason.catalogExhausted =>
    '오늘 추가한 운동 외에 더 추천할 운동이 없어요. 다른 부위를 선택하거나 직접 추가할 수 있어요.',
  ExerciseRecommendationStopReason.trainingFocus =>
    '선택한 부위에는 추천할 수 있는 운동이 없어요. 오늘 운동 부위를 바꿔주세요.',
  ExerciseRecommendationStopReason.profileConstraints =>
    state.recommendationProfile?.availableEquipment.length == 1 &&
            state.recommendationProfile!.availableEquipment.contains(
              TrainingEquipment.bodyweight,
            )
        ? '사용 장비가 맨몸으로만 설정되어 있어요. 선택한 부위에 맞는 운동이 현재 장비·숙련도·제외 동작 조건에 없어요.'
        : '선택한 부위에 맞는 운동이 현재 장비·숙련도·제외 동작 조건에 없어요. 실제 사용할 장비와 추천 정보를 확인해주세요.',
  ExerciseRecommendationStopReason.excludedExercises =>
    '오늘 또는 항상 제외한 운동과 사용할 수 없는 장비를 빼니 추천 후보가 없어요. 추천 설정에서 제외한 운동을 복원할 수 있어요.',
  ExerciseRecommendationStopReason.noAlternative =>
    '같은 동작의 가능한 대체 운동이 없어요. 다른 부위를 선택하거나 추천 설정을 확인해주세요.',
  ExerciseRecommendationStopReason.volumeReached =>
    state.recommendationVolumeStopReasonForDate(date),
  ExerciseRecommendationStopReason.timeBudget =>
    '설정한 운동 시간 안에 추가할 수 있는 운동이 없어요. 시간을 늘리거나 제한 없음으로 바꿔주세요.',
};

enum _RecoveryAction { profile, focus, settings, manual }

/// true: 조건을 수정했으므로 재추천, false: 직접 선택, null: 닫기.
Future<bool?> recoverWorkoutRecommendation(
  BuildContext context,
  DateTime date,
  ExerciseRecommendationStopReason reason,
) async {
  final state = AppScope.of(context);
  final primary = switch (reason) {
    ExerciseRecommendationStopReason.profileConstraints ||
    ExerciseRecommendationStopReason.severePain => _RecoveryAction.profile,
    ExerciseRecommendationStopReason.trainingFocus ||
    ExerciseRecommendationStopReason.catalogExhausted ||
    ExerciseRecommendationStopReason.volumeReached => _RecoveryAction.focus,
    _ => _RecoveryAction.settings,
  };
  final action = await showSetflowSheet<_RecoveryAction>(
    context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SingleChildScrollView(
      padding: SetflowInsets.pageForm,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('추천 조건 확인', style: Theme.of(sheetContext).textTheme.titleLarge),
          const SizedBox(height: SetflowSpacing.sm),
          Text(
            workoutRecommendationStopMessage(state, date, reason),
            key: const ValueKey('recommendation-stop-reason'),
          ),
          const SizedBox(height: SetflowSpacing.md),
          FilledButton(
            key: const ValueKey('recommendation-recovery-primary'),
            onPressed: () => Navigator.pop(sheetContext, primary),
            child: Text(switch (primary) {
              _RecoveryAction.profile => '장비·추천 정보 수정',
              _RecoveryAction.focus => '운동 부위 바꾸기',
              _ => '시간·제외 설정',
            }),
          ),
          if (primary != _RecoveryAction.focus)
            TextButton(
              key: const ValueKey('recommendation-recovery-focus'),
              onPressed: () =>
                  Navigator.pop(sheetContext, _RecoveryAction.focus),
              child: const Text('운동 부위 바꾸기'),
            ),
          if (primary != _RecoveryAction.settings)
            TextButton(
              key: const ValueKey('recommendation-recovery-settings'),
              onPressed: () =>
                  Navigator.pop(sheetContext, _RecoveryAction.settings),
              child: const Text('시간·제외 설정'),
            ),
          TextButton(
            key: const ValueKey('recommendation-recovery-manual'),
            onPressed: () =>
                Navigator.pop(sheetContext, _RecoveryAction.manual),
            child: const Text('직접 선택'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return null;
  switch (action) {
    case _RecoveryAction.profile:
      return await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => const RecommendationProfileScreen(),
                ),
              ) ==
              true
          ? true
          : null;
    case _RecoveryAction.focus:
      final session = state.sessionFor(date);
      final selected = await showTrainingFocusSheet(
        context,
        initialFocus: session.trainingFocus,
        initialTimeBudgetMinutes: session.timeBudgetMinutes,
        onTimeBudgetChanged: (minutes) =>
            state.setWorkoutTimeBudget(date, minutes),
      );
      if (selected == null || !context.mounted) return null;
      state.setTrainingFocus(date, selected);
      return true;
    case _RecoveryAction.settings:
      final session = state.sessionFor(date);
      final previousTime = session.timeBudgetMinutes;
      final previousProfile = state.recommendationProfile;
      final previousPreferences = state.recommendationPreferences;
      final previousSkipped = Set.of(session.skippedRecommendationIds);
      final previousEquipment = Set.of(session.unavailableEquipmentExerciseIds);
      await showWorkoutRecommendationSettings(context, date);
      if (!context.mounted) return null;
      return previousTime != session.timeBudgetMinutes ||
              previousProfile != state.recommendationProfile ||
              previousPreferences != state.recommendationPreferences ||
              !setEquals(previousSkipped, session.skippedRecommendationIds) ||
              !setEquals(
                previousEquipment,
                session.unavailableEquipmentExerciseIds,
              )
          ? true
          : null;
    case _RecoveryAction.manual:
      return false;
  }
}
