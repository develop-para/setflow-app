import 'package:flutter/material.dart';

import '../app_state.dart';
import '../domain/personal_coaching.dart';
import '../services/resistance_prescription_engine.dart';
import '../theme.dart';
import '../widgets/auth_gate.dart';
import '../widgets/common.dart';
import 'member_goal_screen.dart';
import 'recommendation_profile_screen.dart';

class PersonalCoachingScreen extends StatelessWidget {
  const PersonalCoachingScreen({required this.date, super.key});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final plan = state.personalCoachingPreviewForDate(date);
    final session =
        state.sessions[ResistancePrescriptionEngine.day(date)] ??
        WorkoutSession(date: date, exercises: []);
    final volume = plan == null
        ? const <TrainingMuscle, double>{}
        : ResistancePrescriptionEngine.volume(
            history: state.sessions.values,
            session: session,
            since: plan.weekStart,
          );
    final recent =
        state.sessions.values
            .where(
              (item) =>
                  ResistancePrescriptionEngine.day(
                    item.date,
                  ).isBefore(ResistancePrescriptionEngine.day(date)) &&
                  !ResistancePrescriptionEngine.day(
                    item.date,
                  ).isBefore(DateTime(date.year, date.month, date.day - 28)),
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    final practiced = <String, ExerciseTemplate>{};
    for (final item in recent) {
      for (final exercise in item.exercises) {
        if (!exercise.id.startsWith('seed_') &&
            !exercise.template.isCardio &&
            exercise.sets.any((set) => set.completed && set.type == '일반')) {
          practiced.putIfAbsent(exercise.template.id, () => exercise.template);
        }
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          state.personalCoachingBetaAvailable ? '개인 코칭 (베타)' : '개인 코칭',
        ),
      ),
      body: ListView(
        padding: SetflowInsets.pageForm,
        children: [
          Text('내 기록으로 다음 운동을 조정해요', style: theme.textTheme.titleLarge),
          const SizedBox(height: SetflowSpacing.sm),
          Text(
            state.personalCoachingBetaAvailable
                ? '베타 기간에는 계정과 결제 없이 사용할 수 있어요. 지난 3주 기록으로 이번 주 부위별 운동량과 새 종목의 세트 수를 제안합니다.'
                : '개인 코칭 이용권으로 주간 운동량과 종목별 진행 계획을 조정합니다.',
          ),
          const SizedBox(height: SetflowSpacing.md),
          if (!state.canUsePersonalCoaching) ...[
            const Text('개인 코칭 이용권을 확인해주세요. 기본 운동 추천은 계속 사용할 수 있어요.'),
            if (state.personalCoachingAccessError != null)
              const Text('이용권을 확인하지 못했어요. 다시 확인해주세요.'),
            TextButton(
              onPressed: state.personalCoachingAccessLoading
                  ? null
                  : () async {
                      if (!await requireSignIn(
                        context,
                        reason: AuthReason.personalCoaching,
                      )) {
                        return;
                      }
                      await state.refreshPersonalCoachingAccess();
                    },
              child: Text(
                state.personalCoachingAccessLoading ? '확인 중' : '이용권 다시 확인',
              ),
            ),
          ] else ...[
            SwitchListTile(
              key: const ValueKey('personal-coaching-enabled'),
              contentPadding: EdgeInsets.zero,
              title: const Text('개인 코칭 추천 사용'),
              subtitle: const Text('새 추천부터 적용하며 기존 계획과 기록은 보존합니다.'),
              value: state.recommendationPreferences.personalCoachingEnabled,
              onChanged: (value) => state.setPersonalCoaching(enabled: value),
            ),
            const SizedBox(height: SetflowSpacing.md),
            Text('일주일에 운동할 날', style: theme.textTheme.titleSmall),
            const SizedBox(height: SetflowSpacing.sm),
            Wrap(
              spacing: SetflowSpacing.sm,
              runSpacing: SetflowSpacing.xs,
              children: [
                for (var days = 1; days <= 7; days++)
                  ChoiceChip(
                    key: ValueKey('personal-coaching-days-$days'),
                    label: Text('$days일'),
                    selected:
                        state.recommendationPreferences.plannedTrainingDays ==
                        days,
                    onSelected: (_) =>
                        state.setPersonalCoaching(trainingDays: days),
                  ),
              ],
            ),
            const SizedBox(height: SetflowSpacing.sm),
            const Text(
              '실제 부위별 운동 빈도를 참고합니다. 하루·전체 운동량과 남은 시간도 함께 제한하므로 모든 부위 목표를 한 번에 채우는 계획은 아닙니다.',
            ),
            SwitchListTile(
              key: const ValueKey('personal-coaching-rir'),
              contentPadding: EdgeInsets.zero,
              title: const Text('세트에 RIR 기록'),
              subtitle: const Text(
                '끝낸 뒤 몇 회 더 할 수 있었는지 기록해요. 입력하지 않은 값은 추측하지 않습니다.',
              ),
              value: state.useRir,
              onChanged: state.setUseRir,
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RecommendationProfileScreen(),
                ),
              ),
              child: const Text('장비·경험·오늘 회복 상태 설정'),
            ),
            const SizedBox(height: SetflowSpacing.md),
            if (plan == null) ...[
              const Text('운동 목표를 선택하면 개인 코칭 계획을 볼 수 있어요.'),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MemberGoalScreen(),
                  ),
                ),
                child: const Text('운동 목표 선택'),
              ),
            ] else ...[
              Text('이번 주 운동량', style: theme.textTheme.titleMedium),
              const SizedBox(height: SetflowSpacing.sm),
              const Text(
                '월요일부터 일요일까지입니다. 이번 주 완료 세트와 오늘 미완료 계획을 함께 표시하며, 지난주 기록으로 목표를 정합니다.',
              ),
              if (state
                      .recommendationProfile
                      ?.shouldPauseAutomaticRecommendation ??
                  false)
                const Text('통증 응답으로 자동 추천이 중단된 상태입니다.'),
              const SizedBox(height: SetflowSpacing.sm),
              for (final target in plan.targets.values) ...[
                SetflowCard(
                  key: ValueKey(
                    'personal-coaching-target-${target.muscle.name}',
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        target.muscle.label,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: SetflowSpacing.xs),
                      Text(
                        '${PerformanceEngine.formatWeight(volume[target.muscle] ?? 0)} / ${target.weeklySets}세트 · 주 ${target.trainingDays}회',
                        style: theme.textTheme.titleSmall,
                      ),
                      Text('부위별 하루 예산 ${target.dailySets}세트'),
                      const SizedBox(height: SetflowSpacing.sm),
                      Text(
                        _adjustmentLabel(target.adjustment),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: context.setflowColors.brandDeep,
                        ),
                      ),
                      const SizedBox(height: SetflowSpacing.xs),
                      Text(target.reason),
                    ],
                  ),
                ),
                const SizedBox(height: SetflowSpacing.sm),
              ],
              const SizedBox(height: SetflowSpacing.md),
              Text('종목별 진행 계획', style: theme.textTheme.titleMedium),
              if (practiced.isEmpty)
                const Text('최근 완료한 종목이 없어요. 기록이 쌓이면 다음 중량과 반복 목표를 보여드립니다.'),
              for (final template in practiced.values)
                if (state.recommendationFor(template, before: date)
                    case final recommendation?)
                  ExpansionTile(
                    key: ValueKey('personal-coaching-exercise-${template.id}'),
                    tilePadding: EdgeInsets.zero,
                    title: Text(template.name),
                    subtitle: Text(
                      recommendation.prescriptionSummary(state.weightUnit),
                    ),
                    children: [
                      Text(recommendation.reason),
                      const SizedBox(height: SetflowSpacing.sm),
                      Text(
                        recommendation.progressionCondition(state.weightUnit),
                      ),
                      const SizedBox(height: SetflowSpacing.sm),
                    ],
                  ),
              const SizedBox(height: SetflowSpacing.md),
              const Text(
                '목표는 연구 원칙과 개인 기록을 적용한 앱 제안이며 개인의 최적 운동량을 확정한 값은 아닙니다. RIR 없이 최근 수행량보다 추가로 늘리지 않습니다. 오늘 피로는 새 추천을 줄이는 데 반영합니다.',
              ),
            ],
          ],
        ],
      ),
    );
  }

  static String _adjustmentLabel(CoachingAdjustment adjustment) =>
      switch (adjustment) {
        CoachingAdjustment.insufficient => '기록 부족 · 기본값',
        CoachingAdjustment.maintain => '최근 수행량 유지',
        CoachingAdjustment.increase => '점진적 증가 검토',
        CoachingAdjustment.reduce => '운동량 감소',
      };
}
