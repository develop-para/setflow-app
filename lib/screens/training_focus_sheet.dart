import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

Future<Set<TrainingMuscle>?> showTrainingFocusSheet(
  BuildContext context, {
  Set<TrainingMuscle>? initialFocus,
}) => showSetflowSheet<Set<TrainingMuscle>>(
  context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _TrainingFocusSheet(initialFocus: initialFocus),
);

class _TrainingFocusSheet extends StatefulWidget {
  const _TrainingFocusSheet({this.initialFocus});
  final Set<TrainingMuscle>? initialFocus;

  @override
  State<_TrainingFocusSheet> createState() => _TrainingFocusSheetState();
}

class _TrainingFocusSheetState extends State<_TrainingFocusSheet> {
  late final selected = <TrainingMuscle>{...?widget.initialFocus};

  void choose(Set<TrainingMuscle> muscles) => setState(() {
    selected
      ..clear()
      ..addAll(muscles);
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: SetflowInsets.pageForm,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('오늘 운동 부위', style: theme.textTheme.titleLarge),
          const SizedBox(height: SetflowSpacing.sm),
          Text(
            '부위를 고르면 오늘의 첫 운동과 다음 운동을 그 안에서 추천해요. 여러 부위를 함께 골라도 돼요.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: SetflowSpacing.md),
          ChoiceChip(
            key: const ValueKey('training-focus-auto'),
            label: const Text('완전 추천 · 부위 선택 없이'),
            selected: selected.isEmpty,
            onSelected: (_) => choose({}),
          ),
          const SizedBox(height: SetflowSpacing.sm),
          Wrap(
            spacing: SetflowSpacing.sm,
            runSpacing: SetflowSpacing.xs,
            children: [
              for (final muscle in TrainingMuscle.values)
                FilterChip(
                  key: ValueKey('training-focus-${muscle.name}'),
                  label: Text(muscle.label),
                  selected: selected.contains(muscle),
                  onSelected: (value) => setState(() {
                    if (value) {
                      selected.add(muscle);
                    } else {
                      selected.remove(muscle);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.sm),
          ExpansionTile(
            key: const ValueKey('training-focus-presets'),
            tilePadding: EdgeInsets.zero,
            title: const Text('분할 빠른 선택'),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text('3분할', style: theme.textTheme.titleSmall),
              ),
              const SizedBox(height: SetflowSpacing.xs),
              Wrap(
                spacing: SetflowSpacing.sm,
                runSpacing: SetflowSpacing.xs,
                children: [
                  ActionChip(
                    label: const Text('가슴 · 어깨 · 삼두'),
                    onPressed: () => choose({
                      TrainingMuscle.chest,
                      TrainingMuscle.shoulders,
                      TrainingMuscle.triceps,
                    }),
                  ),
                  ActionChip(
                    label: const Text('등 · 이두'),
                    onPressed: () =>
                        choose({TrainingMuscle.back, TrainingMuscle.biceps}),
                  ),
                  ActionChip(
                    label: const Text('하체 · 복근'),
                    onPressed: () =>
                        choose({TrainingMuscle.legs, TrainingMuscle.core}),
                  ),
                ],
              ),
              const SizedBox(height: SetflowSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('5분할', style: theme.textTheme.titleSmall),
              ),
              const SizedBox(height: SetflowSpacing.xs),
              Wrap(
                spacing: SetflowSpacing.sm,
                runSpacing: SetflowSpacing.xs,
                children: [
                  for (final muscle in [
                    TrainingMuscle.chest,
                    TrainingMuscle.back,
                    TrainingMuscle.legs,
                    TrainingMuscle.shoulders,
                  ])
                    ActionChip(
                      label: Text('${muscle.label} 날'),
                      onPressed: () => choose({muscle}),
                    ),
                  ActionChip(
                    label: const Text('팔 날'),
                    onPressed: () =>
                        choose({TrainingMuscle.biceps, TrainingMuscle.triceps}),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const ValueKey('training-focus-apply'),
              onPressed: () =>
                  Navigator.pop(context, Set<TrainingMuscle>.of(selected)),
              child: Text(selected.isEmpty ? '완전 추천으로 계속' : '선택한 부위로 계속'),
            ),
          ),
        ],
      ),
    );
  }
}
