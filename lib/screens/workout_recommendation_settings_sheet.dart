import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

Future<void> showWorkoutRecommendationSettings(
  BuildContext context,
  DateTime date,
) => showSetflowSheet<void>(
  context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _RecommendationSettingsSheet(date: date),
);

class _RecommendationSettingsSheet extends StatefulWidget {
  const _RecommendationSettingsSheet({required this.date});
  final DateTime date;

  @override
  State<_RecommendationSettingsSheet> createState() =>
      _RecommendationSettingsSheetState();
}

class _RecommendationSettingsSheetState
    extends State<_RecommendationSettingsSheet> {
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final session = state.sessionFor(widget.date);
    final theme = Theme.of(context);
    final excluded = {
      ...state.recommendationPreferences.excludedExerciseIds,
      ...session.skippedRecommendationIds,
    }.toList()..sort();
    return SingleChildScrollView(
      child: Padding(
        padding: SetflowInsets.pageForm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('시간·추천 설정', style: theme.textTheme.titleLarge),
            const SizedBox(height: SetflowSpacing.md),
            Text('오늘 운동 시간', style: theme.textTheme.titleSmall),
            const SizedBox(height: SetflowSpacing.sm),
            Wrap(
              spacing: SetflowSpacing.sm,
              runSpacing: SetflowSpacing.xs,
              children: [
                for (final minutes in <int?>[null, 15, 30, 45, 60, 90])
                  ChoiceChip(
                    key: ValueKey(
                      'recommendation-time-${minutes ?? 'unlimited'}',
                    ),
                    label: Text(minutes == null ? '제한 없음' : '$minutes분'),
                    selected: session.timeBudgetMinutes == minutes,
                    onSelected: (_) => setState(
                      () => state.setWorkoutTimeBudget(widget.date, minutes),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: SetflowSpacing.sm),
            Text(
              '새 추천에만 적용해요. 이미 추가한 운동과 완료 기록은 그대로 남아요. 준비·휴식까지 포함한 예상 시간입니다.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: SetflowSpacing.md),
            Text('추천에서 제외한 운동', style: theme.textTheme.titleSmall),
            const SizedBox(height: SetflowSpacing.sm),
            if (excluded.isEmpty) const Text('제외한 운동이 없어요.'),
            for (final id in excluded)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  state.exercises
                          .where((exercise) => exercise.id == id)
                          .firstOrNull
                          ?.name ??
                      '이전 운동',
                ),
                subtitle: Text(
                  state.recommendationPreferences.excludedExerciseIds.contains(
                        id,
                      )
                      ? '앞으로 제외'
                      : '오늘만 제외',
                ),
                trailing: TextButton(
                  key: ValueKey('recommendation-restore-$id'),
                  onPressed: () => setState(() {
                    state.setExerciseExcludedFromRecommendations(id, false);
                    state.restoreSkippedRecommendation(widget.date, id);
                  }),
                  child: const Text('다시 추천'),
                ),
              ),
            const SizedBox(height: SetflowSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
