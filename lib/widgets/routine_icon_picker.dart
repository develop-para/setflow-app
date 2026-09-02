import 'package:flutter/material.dart';

import '../theme.dart';
import '../theme/muscle_illustrations.dart';
import 'exercise_muscle_map.dart';

/// 루틴의 대표 아이콘(부위 근육 지도) 선택 줄 — 생성 시트와 편집기가 같이 쓴다.
/// null은 "자동": 구성 종목의 지배 부위로 화면이 정한다. 선택은 부위 면 색을
/// 루틴 color로 저장하는 방식이라 서버 스키마 변경 없이 기기 간에 보존된다.
class RoutineIconPicker extends StatelessWidget {
  const RoutineIconPicker({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: SetflowSpacing.sm,
      runSpacing: SetflowSpacing.sm,
      children: [
        _Option(
          key: const ValueKey('routine-icon-auto'),
          selected: selected == null,
          label: '자동',
          onTap: () => onChanged(null),
          child: Text(
            '자동',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final muscle in SetflowMuscleIllustrations.muscles)
          _Option(
            key: ValueKey('routine-icon-$muscle'),
            selected: selected == muscle,
            label: muscle,
            fill: SetflowMuscleIllustrations.fillForMuscle(muscle),
            onTap: () => onChanged(muscle),
            child: ExerciseMuscleMap.forCategory(
              category: muscle,
              size: 40,
              decorative: true,
            ),
          ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.selected,
    required this.label,
    required this.child,
    required this.onTap,
    this.fill,
    super.key,
  });

  final bool selected;
  final String label;
  final Widget child;
  final VoidCallback onTap;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '대표 아이콘 $label',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SetflowRadii.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color:
                    fill?.withValues(alpha: .16) ??
                    context.setflowColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(SetflowRadii.md),
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.outlineVariant,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Center(child: child),
            ),
            const SizedBox(height: SetflowSpacing.xxs),
            Text(label, style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}
