import 'dart:math';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/trainer_client_repository.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/common.dart';
import '../widgets/exercise_guide_sheet.dart';
import 'coaching_workout_screens.dart'
    show CoachingAccountBoundary, CoachingSetRow;

String _newId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

WorkoutSession _copySession(WorkoutSession session) => WorkoutSession(
  date: session.date,
  startedAt: session.startedAt,
  endedAt: session.endedAt,
  trainingFocus: session.trainingFocus == null
      ? null
      : Set.of(session.trainingFocus!),
  timeBudgetMinutes: session.timeBudgetMinutes,
  skippedRecommendationIds: session.skippedRecommendationIds,
  unavailableEquipmentExerciseIds: session.unavailableEquipmentExerciseIds,
  correctionVersions: session.correctionVersions,
  exercises: [for (final exercise in session.exercises) exercise.copy()],
);

/// 트레이너의 개인 일지를 건드리지 않고 관리 회원의 날짜별 기록을 편집한다.
class TrainerClientWorkoutScreen extends StatelessWidget {
  const TrainerClientWorkoutScreen({
    required this.client,
    required this.date,
    this.workout,
    super.key,
  });

  final TrainerManagedClient client;
  final DateTime date;
  final TrainerClientWorkout? workout;

  @override
  Widget build(BuildContext context) => CoachingAccountBoundary(
    requiredRole: UserRole.trainer,
    child: _ClientWorkoutPage(client: client, date: date, workout: workout),
  );
}

class _ClientWorkoutPage extends StatefulWidget {
  const _ClientWorkoutPage({
    required this.client,
    required this.date,
    this.workout,
  });
  final TrainerManagedClient client;
  final DateTime date;
  final TrainerClientWorkout? workout;

  @override
  State<_ClientWorkoutPage> createState() => _ClientWorkoutPageState();
}

class _ClientWorkoutPageState extends State<_ClientWorkoutPage> {
  late WorkoutSession _draft;
  TrainerClientWorkout? _workout;
  late final TextEditingController _notes;
  late String _workoutId;
  late int _version;
  final Set<WorkoutSetEntry> _expanded = {};
  bool _dirty = false;
  bool _saving = false;
  bool _allowLeave = false;
  bool _conflict = false;
  bool _reviewing = false;
  int _revision = 0;
  _PendingSave? _pending;

  @override
  void initState() {
    super.initState();
    _workout = widget.workout;
    _draft = widget.workout == null
        ? WorkoutSession(date: DateUtils.dateOnly(widget.date), exercises: [])
        : _copySession(widget.workout!.session);
    _notes = TextEditingController(text: widget.workout?.notes ?? '');
    _notes.addListener(_onNotesChanged);
    _workoutId = widget.workout?.id ?? _newId();
    _version = widget.workout?.version ?? 0;
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  TrainerClientRepository? get _repository {
    final Object? business = AppScope.of(context).businessRepository;
    return business is TrainerClientRepository ? business : null;
  }

  bool get _canEdit =>
      _repository != null &&
      AppScope.of(context).role == UserRole.trainer &&
      AppScope.of(
            context,
          ).businessAccess?.availableRoles.contains(UserRole.trainer) ==
          true &&
      (_workout == null ||
          (_workout!.source == TrainerClientWorkoutSource.trainer &&
              _workout!.canEdit &&
              (_workout!.clientId == null ||
                  _workout!.clientId == widget.client.id)));

  bool get _editable => _canEdit && !_saving && _pending == null && !_reviewing;

  void _onNotesChanged() {
    if (!mounted || !_editable) return;
    setState(() {
      _dirty = true;
      _revision++;
    });
  }

  void _change(VoidCallback change) {
    if (!_editable) return;
    setState(() {
      change();
      _dirty = true;
      _revision++;
    });
  }

  Future<void> _save() async {
    if (!_canEdit || _saving || _reviewing || (!_dirty && _pending == null)) {
      return;
    }
    setState(() {
      _pending ??= _PendingSave(
        requestId: _newId(),
        session: _copySession(_draft),
        notes: _notes.text.trim(),
        version: _version,
      );
      _saving = true;
    });
    final pending = _pending!;
    try {
      final saved = await _repository!.saveTrainerClientWorkout(
        clientId: widget.client.id,
        workoutId: _workoutId,
        expectedVersion: pending.version,
        session: _copySession(pending.session),
        notes: pending.notes,
        requestId: pending.requestId,
      );
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
        _pending = null;
        _allowLeave = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, saved);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _conflict = error is TrainerClientWorkoutConflict;
      });
    }
  }

  Future<void> _leave() async {
    if (_saving || _reviewing) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('아직 저장 전이에요'),
        content: const Text('입력한 운동과 메모가 이 화면에 남아 있어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('계속 기록'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('버리고 나가기'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext, false);
              _save();
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    setState(() => _allowLeave = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _reviewLatest() async {
    if (_saving || _reviewing || _repository == null) return;
    setState(() => _reviewing = true);
    try {
      final workouts = await _repository!.listTrainerClientWorkouts(
        widget.client.id,
      );
      final latest =
          workouts
              .where(
                (item) =>
                    item.id == _workoutId &&
                    item.source == TrainerClientWorkoutSource.trainer,
              )
              .firstOrNull ??
          workouts
              .where(
                (item) =>
                    item.source == TrainerClientWorkoutSource.trainer &&
                    DateUtils.isSameDay(item.session.date, widget.date),
              )
              .firstOrNull;
      if (!mounted) return;
      if (latest == null) {
        AppSnackbar.error(context, '최신 기록을 불러올 수 없어요. 입력은 이 화면에 남아 있어요.');
        return;
      }
      final replace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('최신 기록 확인'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('이 화면의 입력'),
                ..._reviewLines(_draft, _notes.text),
                const SizedBox(height: SetflowSpacing.lg),
                const Text('서버의 최신 기록'),
                ..._reviewLines(latest.session, latest.notes),
                const SizedBox(height: SetflowSpacing.lg),
                const Text('전환하면 이 화면의 미저장 입력이 지워집니다.'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('입력 유지'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('최신 기록으로 전환'),
            ),
          ],
        ),
      );
      if (!mounted || replace != true) return;
      setState(() {
        _workout = latest;
        _workoutId = latest.id;
        _draft = _copySession(latest.session);
        _notes.text = latest.notes;
        _version = latest.version;
        _dirty = false;
        _pending = null;
        _conflict = false;
        _expanded.clear();
        _revision++;
      });
    } catch (_) {
      if (mounted) {
        AppSnackbar.error(context, '최신 기록을 불러오지 못했어요. 입력은 그대로 남아 있어요.');
      }
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  List<Widget> _reviewLines(WorkoutSession session, String notes) => [
    for (final exercise in session.exercises)
      for (final set in exercise.sets)
        Text(
          '${exercise.template.name} ${set.number}세트 · ${set.completed ? '완료' : '계획'} · '
          '${exercise.template.isCardio || exercise.template.isDurationHold ? '${set.durationSeconds}초 · ${set.distanceKm}km' : '${set.weight}kg × ${set.reps}회'}',
        ),
    if (notes.isNotEmpty) Text(notes),
  ];

  Future<void> _addExercise() async {
    if (!_editable) return;
    final template = await showSetflowSheet<ExerciseTemplate>(
      context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ClientExercisePicker(
        catalog: <String, ExerciseTemplate>{
          for (final exercise in AppScope.of(context).selectableExercises)
            exercise.id: exercise,
          for (final exercise in _draft.exercises)
            exercise.template.id: exercise.template,
        }.values.toList(growable: false),
      ),
    );
    if (template == null || !mounted) return;
    _change(() {
      _draft.exercises.add(
        WorkoutExercise(
          id: _newId(),
          template: template,
          sets: [
            WorkoutSetEntry(
              number: 1,
              weight: 0,
              reps: template.isCardio || template.isDurationHold ? 0 : 10,
              durationSeconds: template.isCardio
                  ? 1200
                  : template.isDurationHold
                  ? 30
                  : 0,
              restSeconds: template.isCardio ? 0 : 90,
            ),
          ],
        ),
      );
    });
  }

  Future<void> _complete(WorkoutExercise exercise, WorkoutSetEntry set) async {
    if (!_editable) return;
    final index = exercise.sets.indexOf(set);
    if (!set.completed &&
        index != exercise.sets.indexWhere((entry) => !entry.completed)) {
      return;
    }
    final original = <WorkoutSetEntry, WorkoutSetEntry>{};
    _change(() {
      set.completed = !set.completed;
      _expanded.remove(set);
      if (!set.completed) return;
      for (final pending in exercise.sets.skip(index + 1)) {
        if (pending.completed ||
            (!exercise.template.isCardio &&
                (set.type != '일반' || pending.type != '일반')) ||
            (exercise.template.usesWeight && pending.weight > set.weight) ||
            (pending.weight == set.weight &&
                pending.reps == set.reps &&
                pending.durationSeconds == set.durationSeconds &&
                pending.distanceKm == set.distanceKm &&
                pending.restSeconds == set.restSeconds)) {
          continue;
        }
        original[pending] = pending.copy();
        // 미래 세트의 계획만 갱신한다. 관찰한 RIR·RPE를 수행한 것처럼 복사하지 않는다.
        pending.weight = set.weight;
        pending.reps = set.reps;
        pending.durationSeconds = set.durationSeconds;
        pending.distanceKm = set.distanceKm;
        pending.restSeconds = set.restSeconds;
      }
    });
    if (original.isEmpty || !mounted) return;
    final revision = _revision;
    AppSnackbar.undoable(
      context,
      '남은 세트에도 기록한 값을 적용했어요.',
      actionLabel: '되돌리기',
      onAction: () {
        if (!mounted || !_editable || revision != _revision) return;
        _change(() {
          for (final entry in original.entries) {
            final position = exercise.sets.indexOf(entry.key);
            if (position >= 0 && !entry.key.completed) {
              exercise.sets[position] = entry.value;
            }
          }
        });
      },
    );
  }

  Future<void> _deleteSet(WorkoutExercise exercise, WorkoutSetEntry set) async {
    _change(() {
      _expanded.remove(set);
      exercise.sets.remove(set);
      for (var index = 0; index < exercise.sets.length; index++) {
        exercise.sets[index].number = index + 1;
      }
      if (exercise.sets.isEmpty) _draft.exercises.remove(exercise);
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowLeave || (!_dirty && !_saving && !_reviewing),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(title: Text('${widget.client.name} 운동 기록')),
      body: ListView(
        padding: SetflowInsets.pageList,
        children: [
          Text(
            '${widget.date.year}년 ${widget.date.month}월 ${widget.date.day}일',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: SetflowSpacing.sm),
          Text(
            _workout?.source == TrainerClientWorkoutSource.member
                ? '회원이 직접 기록한 운동'
                : '${widget.client.name} 회원님의 운동과 메모',
          ),
          if (_workout != null)
            Text(
              '${_workout!.authorName} 기록',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: SetflowSpacing.lg),
          Text(
            '${_draft.completedSets} / ${_draft.totalSets}세트',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: SetflowSpacing.md),
          if (_canEdit && _draft.totalSets > 0) ...[
            const Text('오른쪽으로 밀어 완료 · 왼쪽으로 밀어 삭제'),
            const SizedBox(height: SetflowSpacing.md),
          ],
          if (_draft.exercises.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: SetflowSpacing.xl),
              child: Text('종목을 추가하고 실제 수행한 세트를 완료해주세요. 메모만 남길 수도 있어요.'),
            ),
          for (final exercise in _draft.exercises) _exerciseCard(exercise),
          if (_canEdit)
            OutlinedButton.icon(
              key: const ValueKey('client-workout-add-exercise'),
              onPressed: _editable ? _addExercise : null,
              icon: const Icon(SetflowIcons.addExercise),
              label: const Text('종목 추가'),
            ),
          const SizedBox(height: SetflowSpacing.lg),
          TextField(
            key: const ValueKey('client-workout-notes'),
            controller: _notes,
            readOnly: !_editable,
            maxLength: 10000,
            minLines: 3,
            maxLines: null,
            decoration: const InputDecoration(
              labelText: '운동 메모 · 회원 공유',
              hintText: '수업 내용과 회원 상태를 남겨주세요.',
            ),
          ),
          if (_pending != null && !_saving) ...[
            const SizedBox(height: SetflowSpacing.lg),
            Text(
              _conflict
                  ? '다른 곳에서 기록이 바뀌었어요. 입력을 유지한 채 최신 기록을 확인해주세요.'
                  : '저장하지 못했어요. 입력은 이 화면에 남아 있어요. 같은 내용으로 저장을 다시 시도해주세요.',
              key: const ValueKey('client-workout-save-error'),
              style: TextStyle(color: context.setflowColors.error),
            ),
            TextButton(
              onPressed: _reviewing ? null : _reviewLatest,
              child: const Text('최신 기록 확인'),
            ),
          ],
          if (!_canEdit) ...[
            const SizedBox(height: SetflowSpacing.md),
            const Text('이 기록은 확인만 할 수 있어요.'),
          ],
        ],
      ),
      bottomNavigationBar: _canEdit
          ? SafeArea(
              child: Padding(
                padding: SetflowInsets.bottomAction,
                child: FilledButton(
                  key: const ValueKey('client-workout-save'),
                  onPressed: _saving || _reviewing || !_dirty ? null : _save,
                  child: Text(
                    _saving
                        ? '저장 중…'
                        : _pending != null
                        ? '저장 재시도'
                        : '회원 기록 저장',
                  ),
                ),
              ),
            )
          : null,
    ),
  );

  Widget _exerciseCard(WorkoutExercise exercise) {
    final firstPending = exercise.sets.indexWhere((set) => !set.completed);
    return Padding(
      padding: const EdgeInsets.only(bottom: SetflowSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  exercise.template.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (hasExerciseGuide(exercise.template))
                IconButton(
                  tooltip: '수행 방법',
                  onPressed: () =>
                      showExerciseGuide(context, exercise.template),
                  icon: const Icon(SetflowIcons.guide),
                ),
              if (_canEdit)
                IconButton(
                  tooltip: '${exercise.template.name} 삭제',
                  onPressed: _editable
                      ? () => _change(() => _draft.exercises.remove(exercise))
                      : null,
                  icon: const Icon(SetflowIcons.delete),
                ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.sm),
          for (var index = 0; index < exercise.sets.length; index++) ...[
            CoachingSetRow(
              key: ObjectKey(exercise.sets[index]),
              template: exercise.template,
              set: exercise.sets[index],
              enabled: _editable,
              live:
                  _editable &&
                  (exercise.sets[index].completed || index == firstPending),
              expanded: _expanded.contains(exercise.sets[index]),
              onExpand: () =>
                  setState(() => _expanded.add(exercise.sets[index])),
              onComplete: () => _complete(exercise, exercise.sets[index]),
              onDelete: () => _deleteSet(exercise, exercise.sets[index]),
              onEdit: (update) async =>
                  _change(() => update(exercise.sets[index])),
            ),
            const SizedBox(height: SetflowSpacing.sm),
          ],
          if (_canEdit)
            TextButton.icon(
              onPressed: !_editable
                  ? null
                  : () => _change(() {
                      final set = exercise.sets.last.copy(asPlan: true);
                      set.number = exercise.sets.length + 1;
                      exercise.sets.add(set);
                    }),
              icon: const Icon(SetflowIcons.addExercise),
              label: const Text('세트 추가'),
            ),
        ],
      ),
    );
  }
}

class _PendingSave {
  const _PendingSave({
    required this.requestId,
    required this.session,
    required this.notes,
    required this.version,
  });
  final String requestId;
  final WorkoutSession session;
  final String notes;
  final int version;
}

class _ClientExercisePicker extends StatefulWidget {
  const _ClientExercisePicker({required this.catalog});
  final List<ExerciseTemplate> catalog;
  @override
  State<_ClientExercisePicker> createState() => _ClientExercisePickerState();
}

class _ClientExercisePickerState extends State<_ClientExercisePicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .65,
      child: Column(
        children: [
          Padding(
            padding: SetflowInsets.pageHeader,
            child: TextField(
              decoration: const InputDecoration(
                labelText: '종목 검색',
                prefixIcon: Icon(SetflowIcons.exerciseSearch),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: ListView(
              padding: SetflowInsets.pageList,
              children: [
                if (!widget.catalog.any(
                  (item) => item.matchesCatalogQuery(_query),
                ))
                  const Text('검색 결과가 없어요.'),
                for (final template
                    in widget.catalog
                        .where((item) => item.matchesCatalogQuery(_query))
                        .take(80))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(template.name),
                    subtitle: Text(template.muscle),
                    onTap: () => Navigator.pop(context, template),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
