import 'package:flutter/material.dart';

import '../data/exercise_guides.dart';
import '../data/exercise_visuals.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';
import 'exercise_visual_viewer.dart';

/// 실제 설명이나 영상이 있는 정확한 종목 ID에만 수행 방법을 제공한다.
bool hasExerciseGuide(ExerciseTemplate template) =>
    exerciseGuides.containsKey(template.id) ||
    exerciseVisuals.containsKey(template.id);

/// 선택·기록·코칭·함께 운동이 같은 종목의 설명과 데모를 열도록 공유한다.
void showExerciseGuide(BuildContext context, ExerciseTemplate template) {
  final steps = exerciseGuides[template.id];
  final visual = exerciseVisuals[template.id];
  if (steps == null && visual == null) return;
  showSetflowSheet<void>(
    context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          SetflowSpacing.gutter,
          0,
          SetflowSpacing.gutter,
          SetflowSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(template.name, style: theme.textTheme.titleLarge),
            const SizedBox(height: SetflowSpacing.xxs),
            Text(
              steps == null
                  ? template.muscle
                  : '${template.muscle} · ${steps.length}단계',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SetflowSpacing.xl),
            if (visual != null) ...[
              ExerciseVisualViewer(exerciseName: template.name, visual: visual),
              const SizedBox(height: SetflowSpacing.xl),
            ],
            for (var i = 0; i < (steps?.length ?? 0); i++)
              Padding(
                padding: const EdgeInsets.only(bottom: SetflowSpacing.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 번호는 순서가 정보라서 붙인다 — 이 문장들은 따라 하는 차례다.
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${i + 1}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(steps![i], style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}
