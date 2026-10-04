import 'package:flutter/material.dart';

import '../app_state.dart';
import '../domain/custom_exercise_recommendation_rules.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/common.dart';

class CustomExerciseRecommendationsScreen extends StatelessWidget {
  const CustomExerciseRecommendationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('내 운동 추천 정보')),
      body: state.customExercises.isEmpty
          ? const EmptyState(
              icon: SetflowIcons.addExercise,
              title: '만든 운동이 없어요',
              message: '운동 선택에서 새 운동을 만들면 여기서 추천 정보를 작성할 수 있어요.',
            )
          : ListView.separated(
              padding: SetflowInsets.pageList,
              itemCount: state.customExercises.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (_, index) {
                final exercise = state.customExercises[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(exercise.name),
                  subtitle: Text(
                    CustomExerciseRecommendationRules.participates(exercise)
                        ? '자동 추천 참여 중'
                        : '직접 추가해서 사용하는 운동',
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CustomExerciseRecommendationScreen(
                        exerciseId: exercise.id,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class CustomExerciseRecommendationScreen extends StatefulWidget {
  const CustomExerciseRecommendationScreen({
    required this.exerciseId,
    super.key,
  });
  final String exerciseId;

  @override
  State<CustomExerciseRecommendationScreen> createState() =>
      _CustomExerciseRecommendationScreenState();
}

class _CustomExerciseRecommendationScreenState
    extends State<CustomExerciseRecommendationScreen> {
  final formKey = GlobalKey<FormState>();
  bool initialized = false;
  bool enabled = false;
  TrainingMuscle? primary;
  CustomExerciseMovement? movement;
  TrainingExperienceLevel? experience;
  String? cardioDefinitionId;
  final equipment = <TrainingEquipment>{};
  final secondary = <TrainingMuscle>{};
  final additionalMovements = <TrainingMovementRestriction>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialized) return;
    initialized = true;
    final exercise = AppScope.of(
      context,
    ).customExercises.where((item) => item.id == widget.exerciseId).firstOrNull;
    final info = exercise == null
        ? null
        : CustomExerciseRecommendationRules.infoFor(exercise);
    if (info == null) return;
    enabled = info.enabled;
    primary = info.primaryMuscle;
    movement = info.movement;
    experience = info.minimumExperience;
    cardioDefinitionId = info.cardioDefinitionId;
    equipment.addAll(info.requiredEquipment);
    secondary.addAll(info.secondaryMuscles);
    additionalMovements.addAll(info.additionalMovements);
  }

  void save(ExerciseTemplate exercise) {
    final state = AppScope.of(context);
    if (!enabled) {
      state.saveCustomExerciseRecommendation(
        exercise.id,
        CustomExerciseRecommendationRules.infoFor(exercise)?.withEnabled(false),
      );
    } else {
      if (!(formKey.currentState?.validate() ?? false)) return;
      final info = CustomExerciseRecommendation(
        enabled: true,
        primaryMuscle: exercise.isCardio ? null : primary,
        movement: exercise.isCardio ? null : movement,
        requiredEquipment: equipment,
        minimumExperience: experience!,
        secondaryMuscles: movement?.isCompound == true && !exercise.isCardio
            ? secondary
            : const {},
        additionalMovements: additionalMovements,
        cardioDefinitionId: exercise.isCardio ? cardioDefinitionId : null,
      );
      if (!CustomExerciseRecommendationRules.isValid(exercise, info)) {
        AppSnackbar.error(context, '주로 쓰는 부위와 동작을 확인해주세요.');
        return;
      }
      state.saveCustomExerciseRecommendation(exercise.id, info);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final exercise = state.customExercises
        .where((item) => item.id == widget.exerciseId)
        .firstOrNull;
    if (exercise == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('추천 정보 설정')),
        body: const Center(child: Text('운동을 찾을 수 없어요.')),
      );
    }
    final theme = Theme.of(context);
    final primaryOptions = TrainingMuscle.values
        .where(
          (muscle) =>
              exercise.muscle == '기타' ||
              muscle.exerciseCategory == exercise.muscle,
        )
        .toList();
    final movementOptions = CustomExerciseMovement.values
        .where(
          (item) =>
              primary != null &&
              item.allowedMuscles.contains(primary) &&
              (!exercise.isDurationHold ||
                  item == CustomExerciseMovement.coreHold ||
                  item == CustomExerciseMovement.other),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('추천 정보 설정')),
      body: SafeArea(
        top: false,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            padding: SetflowInsets.pageForm,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exercise.name, style: theme.textTheme.titleLarge),
                const SizedBox(height: SetflowSpacing.sm),
                const Text(
                  '운동 추가는 그대로 간단하게 할 수 있어요. 이 정보는 내 자동 추천에 함께 포함할 때만 필요해요.',
                ),
                SwitchListTile(
                  key: const ValueKey('custom-recommendation-enabled'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('자동 추천에 포함'),
                  value: enabled,
                  onChanged: (value) => setState(() => enabled = value),
                ),
                if (enabled) ...[
                  if (!exercise.isCardio) ...[
                    DropdownButtonFormField<TrainingMuscle>(
                      key: const ValueKey('custom-recommendation-primary'),
                      initialValue: primary,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '주로 쓰는 부위'),
                      items: [
                        for (final item in primaryOptions)
                          DropdownMenuItem(
                            value: item,
                            child: Text(item.label),
                          ),
                      ],
                      onChanged: (value) => setState(() {
                        primary = value;
                        if (movement?.allowedMuscles.contains(value) != true) {
                          movement = null;
                          secondary.clear();
                        }
                        secondary.remove(value);
                      }),
                      validator: (value) =>
                          value == null ? '주로 쓰는 부위를 선택해주세요.' : null,
                    ),
                    const SizedBox(height: SetflowSpacing.md),
                    DropdownButtonFormField<CustomExerciseMovement>(
                      key: ValueKey(
                        'custom-recommendation-movement-${primary?.name ?? 'none'}',
                      ),
                      initialValue: movement,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '동작 유형'),
                      items: [
                        for (final item in movementOptions)
                          DropdownMenuItem(
                            value: item,
                            child: Text(item.label),
                          ),
                      ],
                      onChanged: (value) => setState(() {
                        movement = value;
                        if (value?.isCompound != true) secondary.clear();
                      }),
                      validator: (value) =>
                          value == null ? '동작 유형을 선택해주세요.' : null,
                    ),
                  ] else
                    DropdownButtonFormField<String>(
                      key: const ValueKey('custom-recommendation-cardio'),
                      initialValue: cardioDefinitionId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '유산소 종류'),
                      items: [
                        for (final entry in cardioExerciseDefinitions.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(_cardioLabel(entry.value.modality)),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => cardioDefinitionId = value),
                      validator: (value) =>
                          value == null ? '유산소 종류를 선택해주세요.' : null,
                    ),
                  const SizedBox(height: SetflowSpacing.lg),
                  Text('필요한 장비', style: theme.textTheme.titleSmall),
                  const SizedBox(height: SetflowSpacing.sm),
                  FormField<Set<TrainingEquipment>>(
                    initialValue: equipment,
                    validator: (value) => value == null || value.isEmpty
                        ? '필요한 장비를 선택해주세요. 맨몸이면 운동 공간을 선택하세요.'
                        : null,
                    builder: (field) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: SetflowSpacing.sm,
                          runSpacing: SetflowSpacing.xs,
                          children: [
                            for (final item in TrainingEquipment.values)
                              FilterChip(
                                key: ValueKey(
                                  'custom-recommendation-equipment-${item.name}',
                                ),
                                label: Text(item.label),
                                selected: equipment.contains(item),
                                onSelected: (value) => setState(() {
                                  value
                                      ? equipment.add(item)
                                      : equipment.remove(item);
                                  field.didChange(Set.of(equipment));
                                }),
                              ),
                          ],
                        ),
                        if (field.errorText != null)
                          Text(
                            field.errorText!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: context.setflowColors.error,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: SetflowSpacing.md),
                  DropdownButtonFormField<TrainingExperienceLevel>(
                    key: const ValueKey('custom-recommendation-experience'),
                    initialValue: experience,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '필요한 운동 경험'),
                    items: [
                      for (final item in TrainingExperienceLevel.values)
                        DropdownMenuItem(value: item, child: Text(item.label)),
                    ],
                    onChanged: (value) => setState(() => experience = value),
                    validator: (value) =>
                        value == null ? '필요한 운동 경험을 선택해주세요.' : null,
                  ),
                  const SizedBox(height: SetflowSpacing.md),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('추가 동작·보조 부위'),
                    children: [
                      const Text('함께 들어가는 동작을 표시하면 내 정밀 추천의 제외 동작 설정도 반영해요.'),
                      const SizedBox(height: SetflowSpacing.sm),
                      Wrap(
                        spacing: SetflowSpacing.sm,
                        runSpacing: SetflowSpacing.xs,
                        children: [
                          for (final item in TrainingMovementRestriction.values)
                            FilterChip(
                              label: Text(item.label),
                              selected: additionalMovements.contains(item),
                              onSelected: (value) => setState(
                                () => value
                                    ? additionalMovements.add(item)
                                    : additionalMovements.remove(item),
                              ),
                            ),
                        ],
                      ),
                      if (!exercise.isCardio &&
                          movement?.isCompound == true) ...[
                        const SizedBox(height: SetflowSpacing.md),
                        const Text('보조로 쓰는 부위는 선택한 것만 운동량에 절반으로 반영해요.'),
                        const SizedBox(height: SetflowSpacing.sm),
                        Wrap(
                          spacing: SetflowSpacing.sm,
                          runSpacing: SetflowSpacing.xs,
                          children: [
                            for (final item in TrainingMuscle.values.where(
                              (item) => item != primary,
                            ))
                              FilterChip(
                                label: Text(item.label),
                                selected: secondary.contains(item),
                                onSelected: (value) => setState(
                                  () => value
                                      ? secondary.add(item)
                                      : secondary.remove(item),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: SetflowSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('custom-recommendation-save'),
                    onPressed: () => save(exercise),
                    child: const Text('저장'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _cardioLabel(CardioModality modality) => switch (modality) {
  CardioModality.treadmillRunning => '트레드밀 달리기',
  CardioModality.outdoorRunning => '야외 달리기',
  CardioModality.briskWalking => '빠르게 걷기',
  CardioModality.stationaryCycling => '실내 자전거',
  CardioModality.outdoorCycling => '야외 자전거',
  CardioModality.stairClimber => '계단 오르기',
  CardioModality.rowingErgometer => '로잉 머신',
  CardioModality.elliptical => '일립티컬',
  CardioModality.jumpRope => '줄넘기',
};
