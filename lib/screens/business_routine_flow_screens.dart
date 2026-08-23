import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../data/business_repository.dart';
import '../theme.dart';
import '../widgets/common.dart';

class BusinessRoutineEditorScreen extends StatefulWidget {
  const BusinessRoutineEditorScreen({
    required this.ownerRole,
    this.routine,
    this.readOnly = false,
    super.key,
  });

  final UserRole ownerRole;
  final OwnedCoachingRoutine? routine;
  final bool readOnly;

  @override
  State<BusinessRoutineEditorScreen> createState() =>
      _BusinessRoutineEditorScreenState();
}

class _BusinessRoutineEditorScreenState
    extends State<BusinessRoutineEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _introController;
  late final TextEditingController _priceController;
  late BusinessRoutineDifficulty _difficulty;
  final List<_RoutineExerciseDraft> _exercises = [];
  bool _saving = false;

  OwnedCoachingRoutine? get _editableRoutine {
    final routine = widget.routine;
    if (routine == null) return null;
    return switch (routine.status) {
      BusinessRoutineStatus.draft || BusinessRoutineStatus.rejected => routine,
      _ => null,
    };
  }

  bool get _createsRevision =>
      widget.routine?.status == BusinessRoutineStatus.approved;

  bool get _readOnly =>
      widget.readOnly || widget.routine?.status == BusinessRoutineStatus.review;

  @override
  void initState() {
    super.initState();
    final source = widget.routine;
    _titleController = TextEditingController(
      text: _createsRevision ? '${source?.title ?? ''} 개정' : source?.title,
    );
    _introController = TextEditingController(text: source?.intro);
    _priceController = TextEditingController(
      text: source?.price == null ? '' : _numberText(source!.price!),
    );
    _difficulty = source?.difficulty ?? BusinessRoutineDifficulty.intermediate;
    for (final exercise
        in source?.exercises ?? const <OwnedRoutineExercise>[]) {
      _exercises.add(_RoutineExerciseDraft.fromRecord(exercise));
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _introController.dispose();
    _priceController.dispose();
    for (final exercise in _exercises) {
      exercise.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.routine;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _readOnly
              ? '루틴 상세'
              : source == null
              ? '새 루틴'
              : _createsRevision
              ? '새 개정본 만들기'
              : '루틴 수정',
        ),
      ),
      body: ListView(
        padding: SetflowInsets.pageList,
        children: [
          if (_createsRevision)
            Padding(
              padding: const EdgeInsets.only(bottom: SetflowSpacing.lg),
              child: _InfoBanner(
                icon: Icons.call_split_rounded,
                message: '배포 중인 승인본은 유지하고, 수정 내용은 새 초안으로 저장합니다.',
              ),
            ),
          if (source?.status == BusinessRoutineStatus.rejected &&
              source?.rejectReason?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(bottom: SetflowSpacing.lg),
              child: _InfoBanner(
                icon: Icons.info_outline_rounded,
                message: '반려 사유: ${source!.rejectReason}',
                isError: true,
              ),
            ),
          SetflowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '기본 정보',
                  style: TextStyle(
                    fontSize: SetflowFontSize.titleLarge,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: SetflowSpacing.lg),
                TextField(
                  controller: _titleController,
                  enabled: !_readOnly,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: '루틴 이름',
                    hintText: '예: 상체 근비대 A',
                  ),
                ),
                const SizedBox(height: SetflowSpacing.sm),
                TextField(
                  controller: _introController,
                  enabled: !_readOnly,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: '설명',
                    hintText: '대상, 목표, 주의사항을 적어주세요.',
                  ),
                ),
                const SizedBox(height: SetflowSpacing.sm),
                DropdownButtonFormField<BusinessRoutineDifficulty>(
                  initialValue: _difficulty,
                  decoration: const InputDecoration(labelText: '난이도'),
                  items: const [
                    DropdownMenuItem(
                      value: BusinessRoutineDifficulty.beginner,
                      child: Text('초급'),
                    ),
                    DropdownMenuItem(
                      value: BusinessRoutineDifficulty.intermediate,
                      child: Text('중급'),
                    ),
                    DropdownMenuItem(
                      value: BusinessRoutineDifficulty.advanced,
                      child: Text('고급'),
                    ),
                  ],
                  onChanged: _readOnly
                      ? null
                      : (value) => setState(
                          () => _difficulty =
                              value ?? BusinessRoutineDifficulty.intermediate,
                        ),
                ),
                const SizedBox(height: SetflowSpacing.md),
                TextField(
                  controller: _priceController,
                  enabled: !_readOnly,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: '판매 가격 (선택)',
                    suffixText: '원',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.xl),
          Row(
            children: [
              Expanded(
                child: Text(
                  '운동 구성 ${_exercises.length}개',
                  style: const TextStyle(
                    fontSize: SetflowFontSize.titleLarge,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (!_readOnly)
                TextButton.icon(
                  onPressed: _showExercisePicker,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('운동 추가'),
                ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.sm),
          if (_exercises.isEmpty)
            EmptyState(
              icon: Icons.playlist_add_rounded,
              title: '운동을 추가해주세요',
              message: '저항운동은 중량·횟수·휴식, 유산소는 시간·거리·RPE를 설정할 수 있어요.',
              actionLabel: _readOnly ? null : '운동 추가',
              onAction: _readOnly ? null : _showExercisePicker,
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _exercises.length,
              buildDefaultDragHandles: false,
              onReorderItem: _readOnly
                  ? (_, _) {}
                  : (oldIndex, newIndex) {
                      setState(() {
                        final item = _exercises.removeAt(oldIndex);
                        _exercises.insert(newIndex, item);
                      });
                    },
              itemBuilder: (context, index) {
                final exercise = _exercises[index];
                return Padding(
                  key: ValueKey(exercise.keyId),
                  padding: const EdgeInsets.only(bottom: SetflowSpacing.md),
                  child: _RoutineExerciseEditorCard(
                    index: index,
                    exercise: exercise,
                    readOnly: _readOnly,
                    onChanged: () => setState(() {}),
                    onDelete: () {
                      setState(() => _exercises.removeAt(index));
                      exercise.dispose();
                    },
                  ),
                );
              },
            ),
          if (!_readOnly) ...[
            const SizedBox(height: SetflowSpacing.lg),
            AppButton(
              label: _createsRevision ? '새 초안 저장' : '초안 저장',
              icon: Icons.save_outlined,
              isLoading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showExercisePicker() async {
    final state = AppScope.of(context);
    final selectedNames = _exercises.map((item) => item.name).toSet();
    final selected = await showSetflowSheet<ExerciseTemplate>(
      context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SetflowSpacing.lg,
                ),
                child: Row(
                  children: [
                    Text(
                      '운동 선택',
                      style: Theme.of(sheetContext).textTheme.headlineSmall,
                    ),
                    const Spacer(),
                    Text(
                      '${state.exercises.length}개',
                      style: const TextStyle(
                        color: SetflowColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SetflowSpacing.sm),
              Expanded(
                child: ListView.builder(
                  itemCount: state.exercises.length,
                  itemBuilder: (context, index) {
                    final exercise = state.exercises[index];
                    final alreadyAdded = selectedNames.contains(exercise.name);
                    return ListTile(
                      enabled: !alreadyAdded,
                      leading: Icon(exercise.icon, size: 20),
                      title: Text(exercise.name),
                      subtitle: Text(exercise.muscle),
                      trailing: alreadyAdded
                          ? const Icon(Icons.check_rounded)
                          : const Icon(Icons.add_rounded),
                      onTap: alreadyAdded
                          ? null
                          : () => Navigator.pop(sheetContext, exercise),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(
      () => _exercises.add(_RoutineExerciseDraft.fromTemplate(selected)),
    );
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      AppSnackbar.error(context, '루틴 이름을 입력해주세요.');
      return;
    }
    if (_exercises.isEmpty) {
      AppSnackbar.error(context, '운동을 한 개 이상 추가해주세요.');
      return;
    }
    for (final exercise in _exercises) {
      if (exercise.sets.isEmpty) {
        AppSnackbar.error(context, '${exercise.name}에 세트를 추가해주세요.');
        return;
      }
      if (exercise.isCardio) {
        if (exercise.sets.any(
          (set) =>
              set.durationSeconds == null ||
              set.durationSeconds! < 60 ||
              set.durationSeconds! > 86400,
        )) {
          AppSnackbar.error(
            context,
            '${exercise.name}의 운동 시간을 1~1,440분으로 입력해주세요.',
          );
          return;
        }
        if (exercise.sets.any(
          (set) =>
              set.distanceKm != null &&
              (set.distanceKm! < 0 || set.distanceKm! > 999.99),
        )) {
          AppSnackbar.error(
            context,
            '${exercise.name}의 거리를 0~999.99km로 입력해주세요.',
          );
          return;
        }
        if (exercise.sets.any(
          (set) =>
              set.intensityRpe == null ||
              set.intensityRpe! < 1 ||
              set.intensityRpe! > 10,
        )) {
          AppSnackbar.error(context, '${exercise.name}의 RPE를 1~10으로 입력해주세요.');
          return;
        }
      } else if (exercise.sets.any(
        (set) => set.reps == null || set.reps! < 1,
      )) {
        AppSnackbar.error(context, '${exercise.name}의 목표 횟수를 확인해주세요.');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      await AppScope.of(context).saveBusinessRoutineDraft(
        ownerRole: widget.ownerRole,
        title: title,
        description: _introController.text.trim(),
        difficulty: _difficulty,
        price: double.tryParse(_priceController.text.trim()),
        existing: _editableRoutine,
        routineExercises: [
          for (final exercise in _exercises)
            CreateOwnedRoutineExerciseInput(
              baseExerciseId: _uuidOrNull(exercise.baseExerciseId),
              name: exercise.name,
              targetMuscle: exercise.targetMuscle,
              sets: [
                for (var index = 0; index < exercise.sets.length; index++)
                  CreateOwnedRoutineSetInput(
                    setNumber: index + 1,
                    type: exercise.sets[index].type,
                    targetWeight: exercise.isCardio
                        ? null
                        : exercise.sets[index].weight,
                    targetReps: exercise.isCardio
                        ? null
                        : exercise.sets[index].reps,
                    restSeconds: exercise.isCardio
                        ? 0
                        : exercise.sets[index].restSeconds ?? 90,
                    durationSeconds: exercise.isCardio
                        ? exercise.sets[index].durationSeconds
                        : null,
                    distanceMeters:
                        exercise.isCardio &&
                            (exercise.sets[index].distanceKm ?? 0) > 0
                        ? exercise.sets[index].distanceKm! * 1000
                        : null,
                    intensityRpe: exercise.isCardio
                        ? exercise.sets[index].intensityRpe
                        : null,
                  ),
              ],
            ),
        ],
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        AppSnackbar.error(context, '루틴을 저장하지 못했어요. 입력값을 확인해주세요.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _RoutineExerciseEditorCard extends StatelessWidget {
  const _RoutineExerciseEditorCard({
    required this.index,
    required this.exercise,
    required this.readOnly,
    required this.onChanged,
    required this.onDelete,
  });

  final int index;
  final _RoutineExerciseDraft exercise;
  final bool readOnly;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SetflowCard(
      padding: const EdgeInsets.all(SetflowSpacing.md),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: SetflowColors.primary.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(SetflowRadii.sm),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: SetflowSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      exercise.targetMuscle,
                      style: const TextStyle(
                        color: SetflowColors.secondaryText,
                        fontSize: SetflowFontSize.small,
                      ),
                    ),
                  ],
                ),
              ),
              if (!readOnly) ...[
                IconButton(
                  tooltip: '운동 삭제',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.drag_indicator_rounded),
                  ),
                ),
              ],
            ],
          ),
          const Divider(height: SetflowSpacing.xl),
          for (var index = 0; index < exercise.sets.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: SetflowSpacing.sm),
              child: _RoutineSetEditorRow(
                index: index,
                draft: exercise.sets[index],
                isCardio: exercise.isCardio,
                supportsDistance: exercise.supportsDistance,
                readOnly: readOnly,
                canDelete: exercise.sets.length > 1,
                onDelete: () {
                  final removed = exercise.sets.removeAt(index);
                  removed.dispose();
                  onChanged();
                },
              ),
            ),
          if (!readOnly)
            TextButton.icon(
              onPressed: exercise.sets.length >= 10
                  ? null
                  : () {
                      exercise.sets.add(
                        _RoutineSetDraft(
                          setNumber: exercise.sets.length + 1,
                          type: 'normal',
                          weight: exercise.sets.lastOrNull?.weight ?? 0,
                          reps: exercise.sets.lastOrNull?.reps ?? 10,
                          restSeconds:
                              exercise.sets.lastOrNull?.restSeconds ?? 90,
                          durationSeconds: exercise.isCardio
                              ? exercise.sets.lastOrNull?.durationSeconds ?? 600
                              : null,
                          distanceKm: exercise.isCardio
                              ? exercise.sets.lastOrNull?.distanceKm
                              : null,
                          intensityRpe: exercise.isCardio
                              ? exercise.sets.lastOrNull?.intensityRpe ?? 3
                              : null,
                        ),
                      );
                      onChanged();
                    },
              icon: const Icon(Icons.add_rounded),
              label: Text(exercise.isCardio ? '구간 추가' : '세트 추가'),
            ),
        ],
      ),
    );
  }
}

class _RoutineSetEditorRow extends StatelessWidget {
  const _RoutineSetEditorRow({
    required this.index,
    required this.draft,
    required this.isCardio,
    required this.supportsDistance,
    required this.readOnly,
    required this.canDelete,
    required this.onDelete,
  });

  final int index;
  final _RoutineSetDraft draft;
  final bool isCardio;
  final bool supportsDistance;
  final bool readOnly;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(SetflowSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(SetflowRadii.md),
      ),
      child: Column(
        children: [
          if (isCardio)
            Column(
              children: [
                Row(
                  children: [
                    Text(
                      '${index + 1}구간',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const Spacer(),
                    if (!readOnly)
                      IconButton(
                        tooltip: '구간 삭제',
                        onPressed: canDelete ? onDelete : null,
                        icon: const Icon(Icons.close_rounded, size: 19),
                      ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _NumberField(
                        controller: draft.durationController,
                        label: '시간',
                        suffix: '분',
                        decimal: true,
                        enabled: !readOnly,
                      ),
                    ),
                    if (supportsDistance) ...[
                      const SizedBox(width: SetflowSpacing.xs),
                      Expanded(
                        child: _NumberField(
                          controller: draft.distanceController,
                          label: '거리',
                          suffix: 'km',
                          decimal: true,
                          enabled: !readOnly,
                        ),
                      ),
                    ],
                    const SizedBox(width: SetflowSpacing.xs),
                    Expanded(
                      child: _NumberField(
                        controller: draft.rpeController,
                        label: '강도',
                        suffix: 'RPE',
                        decimal: true,
                        enabled: !readOnly,
                      ),
                    ),
                  ],
                ),
              ],
            )
          else
            Column(
              children: [
                Row(
                  children: [
                    Text(
                      '${index + 1}세트',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(width: SetflowSpacing.md),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: draft.type,
                        isDense: true,
                        decoration: const InputDecoration(
                          labelText: '유형',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'normal', child: Text('일반')),
                          DropdownMenuItem(value: 'warmup', child: Text('웜업')),
                          DropdownMenuItem(value: 'drop', child: Text('드랍')),
                          DropdownMenuItem(value: 'failure', child: Text('실패')),
                        ],
                        onChanged: readOnly
                            ? null
                            : (value) => draft.type = value ?? 'normal',
                      ),
                    ),
                    if (!readOnly)
                      IconButton(
                        tooltip: '세트 삭제',
                        onPressed: canDelete ? onDelete : null,
                        icon: const Icon(Icons.close_rounded, size: 19),
                      ),
                  ],
                ),
                const SizedBox(height: SetflowSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: _NumberField(
                        controller: draft.weightController,
                        label: '중량',
                        suffix: 'kg',
                        decimal: true,
                        enabled: !readOnly,
                      ),
                    ),
                    const SizedBox(width: SetflowSpacing.xs),
                    Expanded(
                      child: _NumberField(
                        controller: draft.repsController,
                        label: '횟수',
                        suffix: '회',
                        enabled: !readOnly,
                      ),
                    ),
                    const SizedBox(width: SetflowSpacing.xs),
                    Expanded(
                      child: _NumberField(
                        controller: draft.restController,
                        label: '휴식',
                        suffix: '초',
                        enabled: !readOnly,
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.suffix,
    required this.enabled,
    this.decimal = false,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final bool enabled;
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
        ),
      ],
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 12,
        ),
      ),
    );
  }
}

class _RoutineExerciseDraft {
  _RoutineExerciseDraft({
    required this.keyId,
    required this.name,
    required this.targetMuscle,
    required this.sets,
    this.baseExerciseId,
  });

  factory _RoutineExerciseDraft.fromTemplate(ExerciseTemplate template) =>
      _RoutineExerciseDraft(
        keyId: '${template.id}-${DateTime.now().microsecondsSinceEpoch}',
        baseExerciseId: template.id,
        name: template.name,
        targetMuscle: template.muscle,
        sets: List.generate(
          template.isCardio ? 1 : 3,
          (index) => _RoutineSetDraft(
            setNumber: index + 1,
            type: 'normal',
            weight: template.isCardio ? null : 0,
            reps: template.isCardio ? null : 10,
            restSeconds: template.isCardio ? 0 : 90,
            durationSeconds: template.isCardio ? 1800 : null,
            intensityRpe: template.isCardio ? 3 : null,
          ),
        ),
      );

  factory _RoutineExerciseDraft.fromRecord(OwnedRoutineExercise record) =>
      _RoutineExerciseDraft(
        keyId: record.id,
        baseExerciseId: record.baseExerciseId,
        name: record.name,
        targetMuscle: record.targetMuscle,
        sets: record.sets
            .map(
              (set) => _RoutineSetDraft(
                setNumber: set.setNumber,
                type: set.type,
                weight: set.targetWeight,
                reps: set.targetReps,
                restSeconds: set.restSeconds,
                durationSeconds: set.durationSeconds,
                distanceKm: set.distanceMeters == null
                    ? null
                    : set.distanceMeters! / 1000,
                intensityRpe: set.intensityRpe,
              ),
            )
            .toList(),
      );

  final String keyId;
  final String? baseExerciseId;
  final String name;
  final String targetMuscle;
  final List<_RoutineSetDraft> sets;

  bool get isCardio => targetMuscle == '유산소';

  bool get supportsDistance {
    final definition = cardioDefinitionForExercise(baseExerciseId ?? '');
    if (definition != null) {
      return definition.metrics.contains(CardioMetric.distance);
    }
    return !name.contains('스텝') && !name.contains('줄넘기');
  }

  void dispose() {
    for (final set in sets) {
      set.dispose();
    }
  }
}

class _RoutineSetDraft {
  _RoutineSetDraft({
    required int setNumber,
    required this.type,
    double? weight,
    int? reps,
    int? restSeconds,
    int? durationSeconds,
    double? distanceKm,
    double? intensityRpe,
  }) : weightController = TextEditingController(
         text: weight == null ? '' : _numberText(weight),
       ),
       repsController = TextEditingController(text: reps?.toString() ?? ''),
       restController = TextEditingController(
         text: (restSeconds ?? 90).toString(),
       ),
       durationController = TextEditingController(
         text: durationSeconds == null ? '' : _numberText(durationSeconds / 60),
       ),
       distanceController = TextEditingController(
         text: distanceKm == null ? '' : _numberText(distanceKm),
       ),
       rpeController = TextEditingController(
         text: intensityRpe == null ? '' : _numberText(intensityRpe),
       );

  String type;
  final TextEditingController weightController;
  final TextEditingController repsController;
  final TextEditingController restController;
  final TextEditingController durationController;
  final TextEditingController distanceController;
  final TextEditingController rpeController;

  double? get weight => double.tryParse(weightController.text.trim());
  int? get reps => int.tryParse(repsController.text.trim());
  int? get restSeconds => int.tryParse(restController.text.trim());
  int? get durationSeconds {
    final minutes = double.tryParse(durationController.text.trim());
    return minutes == null ? null : (minutes * 60).round();
  }

  double? get distanceKm => double.tryParse(distanceController.text.trim());
  double? get intensityRpe => double.tryParse(rpeController.text.trim());

  void dispose() {
    weightController.dispose();
    repsController.dispose();
    restController.dispose();
    durationController.dispose();
    distanceController.dispose();
    rpeController.dispose();
  }
}

Future<bool?> showRoutineMemberShareSheet(
  BuildContext context, {
  required OwnedCoachingRoutine routine,
}) {
  return showSetflowSheet<bool>(
    context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _RoutineMemberShareSheet(routine: routine),
  );
}

class _RoutineMemberShareSheet extends StatefulWidget {
  const _RoutineMemberShareSheet({required this.routine});

  final OwnedCoachingRoutine routine;

  @override
  State<_RoutineMemberShareSheet> createState() =>
      _RoutineMemberShareSheetState();
}

class _RoutineMemberShareSheetState extends State<_RoutineMemberShareSheet> {
  static const double _compactHeightBreakpoint = 440;
  static const double _landscapeHeightBreakpoint = 560;

  final Set<String> _selectedIds = {};
  final GlobalKey _messageFieldKey = GlobalKey();
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  bool _expires = true;
  bool _saving = false;

  @override
  void dispose() {
    _messageFocusNode.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final members = state.businessMembers;
    final media = MediaQuery.of(context);
    final availableHeight =
        (media.size.height -
                media.viewInsets.bottom -
                media.padding.top -
                media.padding.bottom)
            .clamp(0.0, media.size.height)
            .toDouble();
    final preferredHeight = media.size.height * .82;
    final sheetHeight = preferredHeight < availableHeight
        ? preferredHeight
        : availableHeight;
    final usesScrollableLayout =
        sheetHeight < _compactHeightBreakpoint ||
        (media.orientation == Orientation.landscape &&
            sheetHeight < _landscapeHeightBreakpoint);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: sheetHeight,
          child: usesScrollableLayout
              ? ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(
                    SetflowSpacing.lg,
                    0,
                    SetflowSpacing.lg,
                    SetflowSpacing.lg,
                  ),
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ..._buildHeader(context),
                        if (members.isEmpty)
                          const EmptyState(
                            icon: Icons.people_outline_rounded,
                            title: '담당 회원이 없어요',
                            message: '회원 배정이 완료되면 이곳에서 루틴을 바로 공유할 수 있어요.',
                          )
                        else
                          ...members.map(_buildMemberTile),
                        ..._buildFooter(),
                      ],
                    ),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SetflowSpacing.lg,
                    0,
                    SetflowSpacing.lg,
                    SetflowSpacing.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ..._buildHeader(context),
                      Expanded(
                        child: members.isEmpty
                            ? const EmptyState(
                                icon: Icons.people_outline_rounded,
                                title: '담당 회원이 없어요',
                                message: '회원 배정이 완료되면 이곳에서 루틴을 바로 공유할 수 있어요.',
                              )
                            : ListView.builder(
                                itemCount: members.length,
                                itemBuilder: (context, index) =>
                                    _buildMemberTile(members[index]),
                              ),
                      ),
                      ..._buildFooter(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  List<Widget> _buildHeader(BuildContext context) => [
    Text('회원에게 공유', style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: SetflowSpacing.xs),
    Text(
      widget.routine.title,
      style: const TextStyle(color: SetflowColors.secondaryText),
    ),
    const SizedBox(height: SetflowSpacing.md),
  ];

  Widget _buildMemberTile(BusinessMember member) {
    final linked = member.userId != null;
    return CheckboxListTile(
      value: _selectedIds.contains(member.id),
      enabled: linked && !_saving,
      title: Text(member.name),
      subtitle: Text(linked ? member.goal ?? '운동 목표 미입력' : '앱 계정 연결이 필요합니다'),
      onChanged: (checked) => setState(() {
        if (checked == true) {
          _selectedIds.add(member.id);
        } else {
          _selectedIds.remove(member.id);
        }
      }),
    );
  }

  List<Widget> _buildFooter() => [
    TextField(
      key: _messageFieldKey,
      controller: _messageController,
      focusNode: _messageFocusNode,
      enabled: !_saving,
      minLines: 2,
      maxLines: 3,
      maxLength: 300,
      decoration: const InputDecoration(labelText: '회원에게 보낼 메시지 (선택)'),
    ),
    SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      value: _expires,
      onChanged: _saving ? null : (value) => setState(() => _expires = value),
      title: const Text('14일 후 수락 만료'),
    ),
    AppButton(
      label: '${_selectedIds.length}명에게 공유',
      icon: Icons.send_rounded,
      isLoading: _saving,
      onPressed: _selectedIds.isEmpty || _saving ? null : _share,
    ),
  ];

  Future<void> _share() async {
    setState(() => _saving = true);
    try {
      await AppScope.of(context).shareBusinessRoutine(
        routineId: widget.routine.id,
        memberIds: _selectedIds.toList(growable: false),
        message: _messageController.text.trim(),
        expiresAt: _expires
            ? DateTime.now().add(const Duration(days: 14))
            : null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        AppSnackbar.error(context, '루틴을 공유하지 못했어요. 담당 회원인지 확인해주세요.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

Future<void> createAndShowRoutineShareLink(
  BuildContext context,
  OwnedCoachingRoutine routine, {
  bool confirmCreateNewAfterUncertainResult = false,
}) async {
  final state = AppScope.of(context);
  try {
    final link = await state.createBusinessRoutineShareLink(
      routine.id,
      expiresAt: DateTime.now().add(const Duration(days: 14)),
      confirmCreateNewAfterUncertainResult:
          confirmCreateNewAfterUncertainResult,
    );
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('공유 링크 생성 완료'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('링크는 14일 동안 사용할 수 있습니다.'),
            const SizedBox(height: SetflowSpacing.md),
            SelectableText(
              link.uri.toString(),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link.uri.toString()));
              if (dialogContext.mounted) {
                AppSnackbar.success(dialogContext, '공유 링크를 복사했어요.');
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('복사'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final box = dialogContext.findRenderObject() as RenderBox?;
              await Share.share(
                '${routine.title}\n${link.uri}',
                subject: '${routine.title} · Setflow 루틴',
                sharePositionOrigin: box == null
                    ? null
                    : box.localToGlobal(Offset.zero) & box.size,
              );
            },
            icon: const Icon(Icons.ios_share_rounded),
            label: const Text('공유'),
          ),
        ],
      ),
    );
  } on RoutineShareLinkResultUncertainException {
    if (!context.mounted) return;
    final createNew = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('링크 생성 결과를 확인하지 못했어요'),
        content: const Text(
          '서버에 링크가 이미 생성되었을 수 있지만, 보안상 원문 토큰은 '
          '복구할 수 없습니다. 중복 생성을 막기 위해 자동 재시도하지 '
          '않았습니다. 새 링크를 만들면 확인되지 않은 기존 링크도 만료 '
          '전까지 유효할 수 있습니다. 새 링크를 만들까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('새 링크 만들기'),
          ),
        ],
      ),
    );
    if (createNew == true && context.mounted) {
      await createAndShowRoutineShareLink(
        context,
        routine,
        confirmCreateNewAfterUncertainResult: true,
      );
    }
  } catch (_) {
    if (context.mounted) {
      AppSnackbar.error(context, '승인된 루틴만 외부 링크로 공유할 수 있어요.');
    }
  }
}

class AdminRoutineReviewCard extends StatelessWidget {
  const AdminRoutineReviewCard({required this.routine, super.key});

  final OwnedCoachingRoutine routine;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final saving = state.isReviewingBusinessRoutine(routine.id);
    final setCount = routine.exercises.fold<int>(
      0,
      (sum, exercise) => sum + exercise.sets.length,
    );
    return SetflowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.fact_check_outlined,
                color: SetflowColors.orange,
              ),
              const SizedBox(width: SetflowSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      routine.title,
                      style: const TextStyle(
                        fontSize: SetflowFontSize.title,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${routine.exercises.length}개 운동 · $setCount세트',
                      style: const TextStyle(
                        color: SetflowColors.secondaryText,
                        fontSize: SetflowFontSize.small,
                      ),
                    ),
                  ],
                ),
              ),
              const Chip(label: Text('심사 대기')),
            ],
          ),
          if (routine.intro?.isNotEmpty == true) ...[
            const SizedBox(height: SetflowSpacing.md),
            Text(routine.intro!, maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: SetflowSpacing.md),
          Wrap(
            spacing: SetflowSpacing.xs,
            runSpacing: SetflowSpacing.xs,
            children: [
              for (final exercise in routine.exercises)
                Chip(label: Text('${exercise.name} ${exercise.sets.length}세트')),
            ],
          ),
          const SizedBox(height: SetflowSpacing.md),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: '내용 보기',
                  variant: AppButtonVariant.outlined,
                  onPressed: saving
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => BusinessRoutineEditorScreen(
                              ownerRole: routine.gymId == null
                                  ? UserRole.trainer
                                  : UserRole.gym,
                              routine: routine,
                              readOnly: true,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: SetflowSpacing.sm),
              Expanded(
                child: AppButton(
                  label: '심사하기',
                  icon: Icons.rate_review_outlined,
                  isLoading: saving,
                  onPressed: saving ? null : () => _showReviewSheet(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showReviewSheet(BuildContext context) async {
    var tier = RoutineAccessTier.free;
    final reasonController = TextEditingController();
    Future<void>? sheetCompleted;
    final decision = await showSetflowSheet<_RoutineReviewDecision>(
      context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        sheetCompleted ??= ModalRoute.of(sheetContext)?.completed;
        return StatefulBuilder(
          builder: (context, setSheetState) => KeyboardSafeBottomSheet(
            padding: const EdgeInsets.fromLTRB(
              SetflowSpacing.lg,
              0,
              SetflowSpacing.lg,
              SetflowSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('루틴 심사', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: SetflowSpacing.md),
                SegmentedButton<RoutineAccessTier>(
                  segments: const [
                    ButtonSegment(
                      value: RoutineAccessTier.free,
                      icon: Icon(Icons.lock_open_rounded),
                      label: Text('무료 승인'),
                    ),
                    ButtonSegment(
                      value: RoutineAccessTier.paid,
                      icon: Icon(Icons.workspace_premium_rounded),
                      label: Text('유료 승인'),
                    ),
                  ],
                  selected: {tier},
                  onSelectionChanged: (value) =>
                      setSheetState(() => tier = value.first),
                ),
                const SizedBox(height: SetflowSpacing.md),
                TextField(
                  controller: reasonController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '반려 사유',
                    hintText: '반려할 때는 사유를 반드시 입력해주세요.',
                  ),
                ),
                const SizedBox(height: SetflowSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: '반려',
                        variant: AppButtonVariant.outlined,
                        onPressed: () {
                          final reason = reasonController.text.trim();
                          if (reason.isEmpty) {
                            AppSnackbar.error(context, '반려 사유를 입력해주세요.');
                            return;
                          }
                          Navigator.pop(
                            sheetContext,
                            _RoutineReviewDecision(
                              approve: false,
                              tier: tier,
                              reason: reason,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: SetflowSpacing.sm),
                    Expanded(
                      child: AppButton(
                        label: '승인 · 게시',
                        icon: Icons.publish_rounded,
                        onPressed: () => Navigator.pop(
                          sheetContext,
                          _RoutineReviewDecision(approve: true, tier: tier),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    await sheetCompleted;
    reasonController.dispose();
    if (decision == null || !context.mounted) return;
    try {
      await AppScope.of(context).reviewBusinessRoutine(
        routineId: routine.id,
        approve: decision.approve,
        rejectReason: decision.reason,
        accessTier: decision.tier,
      );
      if (context.mounted) {
        AppSnackbar.success(
          context,
          decision.approve ? '승인 후 마켓에 게시했어요.' : '반려 사유를 전달했어요.',
        );
      }
    } catch (_) {
      if (context.mounted) AppSnackbar.error(context, '심사 결과를 저장하지 못했어요.');
    }
  }
}

class _RoutineReviewDecision {
  const _RoutineReviewDecision({
    required this.approve,
    required this.tier,
    this.reason,
  });

  final bool approve;
  final RoutineAccessTier tier;
  final String? reason;
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.message,
    this.isError = false,
  });

  final IconData icon;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? Theme.of(context).colorScheme.error
        : SetflowColors.blue;
    return Container(
      padding: const EdgeInsets.all(SetflowSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(SetflowRadii.md),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: SetflowSpacing.sm),
          Expanded(child: Text(message, style: const TextStyle(height: 1.4))),
        ],
      ),
    );
  }
}

String? _uuidOrNull(String? value) {
  if (value == null) return null;
  final normalized = value.trim();
  return RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
      ).hasMatch(normalized)
      ? normalized
      : null;
}

String _numberText(num value) =>
    value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1);
