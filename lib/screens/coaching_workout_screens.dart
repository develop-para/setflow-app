import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../app_state.dart';
import '../data/coaching_workout_repository.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/common.dart';
import 'workout_screens.dart' show showNumberDial;

String _requestId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

WorkoutSetEntry _cloneSet(WorkoutSetEntry set) => WorkoutSetEntry(
  number: set.number,
  weight: set.weight,
  reps: set.reps,
  completed: set.completed,
  type: set.type,
  restSeconds: set.restSeconds,
  durationSeconds: set.durationSeconds,
  distanceKm: set.distanceKm,
  intensityRpe: set.intensityRpe,
  rir: set.rir,
);

WorkoutSession _cloneSession(WorkoutSession session) => WorkoutSession(
  date: session.date,
  startedAt: session.startedAt,
  endedAt: session.endedAt,
  exercises: [
    for (final exercise in session.exercises)
      WorkoutExercise(
        id: exercise.id,
        template: exercise.template,
        sets: exercise.sets.map(_cloneSet).toList(),
      ),
  ],
);

String? _actorId(AppState state) =>
    Auth.instance.currentUser?.id ?? state.businessAccess?.userId;

/// 계정 변경 시 내부 State도 제거해 이전 초안과 늦은 응답을 차단한다.
class _CoachingAccountBoundary extends StatefulWidget {
  const _CoachingAccountBoundary({required this.child});
  final Widget child;

  @override
  State<_CoachingAccountBoundary> createState() =>
      _CoachingAccountBoundaryState();
}

class _CoachingAccountBoundaryState extends State<_CoachingAccountBoundary> {
  bool _bound = false;
  bool _expired = false;
  String? _initialActor;
  bool _initialSignedIn = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final actor = _actorId(AppScope.of(context));
    final signedIn = Auth.instance.hasAuthenticatedUser;
    if (!_bound) {
      _bound = true;
      _initialActor = actor;
      _initialSignedIn = signedIn;
    } else if (!_expired &&
        (actor != _initialActor || signedIn != _initialSignedIn)) {
      _expired = true;
      // 다이얼·비교 팝업 역시 이전 계정의 입력을 담는다.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).popUntil((route) => route is! PopupRoute);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => !_expired
      ? widget.child
      : Scaffold(
          key: const ValueKey('coaching-account-expired'),
          appBar: AppBar(title: const Text('코칭')),
          body: SafeArea(
            child: ListView(
              padding: SetflowInsets.pageForm,
              children: [
                const Text('계정이 바뀌어 이 화면을 닫았어요. 현재 계정의 코칭에서 다시 열어주세요.'),
                const SizedBox(height: SetflowSpacing.lg),
                OutlinedButton(
                  onPressed: () => Navigator.maybePop(context),
                  child: const Text('돌아가기'),
                ),
              ],
            ),
          ),
        );
}

String _dateLabel(DateTime date) => '${date.month}월 ${date.day}일';

String _timeLabel(DateTime date) {
  final local = date.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _statusLabel(CoachingWorkout workout) => switch (workout.status) {
  CoachingWorkoutStatus.assigned => '예정',
  CoachingWorkoutStatus.inProgress => '진행 중',
  CoachingWorkoutStatus.completed => '완료',
  CoachingWorkoutStatus.cancelled => '취소됨',
};

/// 수업 대리 기록과 회원 과제를 같은 세트 조작으로 수행한다.
/// 로컬 개인 일지가 아닌 별도 원본만 수정하며 서버가 매번 편집 권한을 확인한다.
class CoachingWorkoutScreen extends StatelessWidget {
  const CoachingWorkoutScreen({this.workoutId, this.scheduleId, super.key})
    : assert((workoutId == null) != (scheduleId == null));

  final String? workoutId;
  final String? scheduleId;

  @override
  Widget build(BuildContext context) => _CoachingAccountBoundary(
    child: _CoachingWorkoutPage(workoutId: workoutId, scheduleId: scheduleId),
  );
}

class _CoachingWorkoutPage extends StatefulWidget {
  const _CoachingWorkoutPage({this.workoutId, this.scheduleId});
  final String? workoutId;
  final String? scheduleId;
  @override
  State<_CoachingWorkoutPage> createState() => _CoachingWorkoutScreenState();
}

class _CoachingWorkoutScreenState extends State<_CoachingWorkoutPage>
    with WidgetsBindingObserver {
  CoachingWorkout? _workout;
  WorkoutSession? _draft;
  Timer? _clock;
  bool _requested = false;
  bool _loading = true;
  bool _saving = false;
  bool _failed = false;
  bool _dirty = false;
  bool _refreshing = false;
  bool _allowLeave = false;
  int _loadGeneration = 0;
  String? _pendingRequestId;
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_workout?.kind == CoachingWorkoutKind.lesson) setState(() {});
      if (timer.tick % 15 == 0 &&
          !_dirty &&
          !_saving &&
          !_loading &&
          !_refreshing) {
        _load(silent: true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_dirty && !_saving) _load();
  }

  @override
  void dispose() {
    _clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  CoachingWorkoutRepository get _repository =>
      AppScope.of(context).coachingWorkoutRepository!;

  bool get _inWindow {
    final workout = _workout;
    if (workout == null) return false;
    if (workout.kind != CoachingWorkoutKind.lesson) return true;
    final now = DateTime.now();
    return workout.startsAt != null &&
        workout.endsAt != null &&
        !now.isBefore(workout.startsAt!) &&
        now.isBefore(workout.endsAt!);
  }

  bool get _editable =>
      _workout?.canEdit == true &&
      _inWindow &&
      !_saving &&
      !_dirty &&
      !_loading;

  Future<void> _load({bool silent = false}) async {
    if (!mounted || _dirty || _saving) return;
    final generation = ++_loadGeneration;
    final version = _workout?.version;
    final actor = _actorId(AppScope.of(context));
    _refreshing = true;
    if (!silent) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    try {
      if (AppScope.of(context).coachingWorkoutRepository == null) {
        throw StateError('Coaching unavailable');
      }
      final workout = widget.scheduleId != null
          ? await _repository.openLessonWorkout(widget.scheduleId!)
          : (await _repository.listCoachingWorkouts())
                .where((item) => item.id == widget.workoutId)
                .firstOrNull;
      if (workout == null) throw StateError('Workout unavailable');
      if (!mounted || generation != _loadGeneration) return;
      if (silent && (_dirty || _saving || version != _workout?.version)) return;
      if (actor != _actorId(AppScope.of(context))) return;
      setState(() {
        _workout = workout;
        _draft = _cloneSession(workout.session);
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      if (silent && (_dirty || _saving || version != _workout?.version)) return;
      setState(() {
        _workout = null;
        _draft = null;
        _loading = false;
        _failed = true;
      });
    } finally {
      if (generation == _loadGeneration) _refreshing = false;
    }
  }

  Future<bool> _save([WorkoutSession? next]) async {
    final workout = _workout;
    if (workout == null || _saving) return false;
    if (next != null && !_editable) return false;
    setState(() {
      if (next != null) _draft = next;
      _dirty = true;
      _saving = true;
      _failed = false;
      _pendingRequestId ??= _requestId();
    });
    try {
      final saved = await _repository.saveCoachingWorkout(
        workoutId: workout.id,
        expectedVersion: workout.version,
        session: _cloneSession(_draft!),
        requestId: _pendingRequestId!,
      );
      if (!mounted) return true;
      setState(() {
        _workout = saved;
        _draft = _cloneSession(saved.session);
        _dirty = false;
        _saving = false;
        _pendingRequestId = null;
      });
      // 이미 저장된 기록은 목록 갱신 실패로 미저장 상태로 되돌리지 않는다.
      unawaited(
        AppScope.of(context).refreshCoachingWorkouts().catchError((_) {}),
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      setState(() {
        _saving = false;
        _failed = true;
      });
      return false;
    }
  }

  Future<void> _leaveWithDraft() async {
    if (_saving) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('아직 저장 전이에요'),
        content: const Text('입력한 기록이 이 화면에 남아 있어요. 연결을 확인한 뒤 다시 저장해주세요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('기록 확인'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _save();
            },
            child: const Text('저장 재시도'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _discardAndLeave();
            },
            child: const Text('입력 버리고 나가기'),
          ),
        ],
      ),
    );
  }

  Future<void> _discardAndLeave() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('입력을 버릴까요?'),
        content: const Text('이 화면의 미저장 입력이 지워집니다. 서버에 이미 저장된 기록은 그대로 남습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('입력 유지'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('버리고 나가기'),
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
    if (_saving || _workout == null) return;
    setState(() => _saving = true);
    try {
      final latest = (await _repository.listCoachingWorkouts())
          .where((item) => item.id == _workout!.id)
          .firstOrNull;
      if (!mounted) return;
      setState(() => _saving = false);
      if (latest == null) {
        AppSnackbar.error(context, '최신 기록을 열 수 없어요. 입력한 기록은 계속 남겨둘게요.');
        return;
      }
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('최신 기록 확인'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('다른 기기에서 수정했거나 수업 권한이 바뀌었을 수 있어요.'),
                const SizedBox(height: SetflowSpacing.md),
                Text(
                  '이 화면의 입력 · ${_draft!.completedSets}/${_draft!.totalSets}세트',
                ),
                for (final exercise in _draft!.exercises)
                  Text(
                    '${exercise.template.name}: ${exercise.sets.map((set) => _setSummary(exercise.template, set)).join(' / ')}',
                  ),
                const SizedBox(height: SetflowSpacing.md),
                Text(
                  '서버의 최신 기록 · ${latest.session.completedSets}/${latest.session.totalSets}세트',
                ),
                for (final exercise in latest.session.exercises)
                  Text(
                    '${exercise.template.name}: ${exercise.sets.map((set) => _setSummary(exercise.template, set)).join(' / ')}',
                  ),
                const SizedBox(height: SetflowSpacing.md),
                const Text('최신 기록으로 전환하면 이 화면의 미저장 입력은 지워집니다.'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('입력 유지'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('최신 기록으로 전환'),
            ),
          ],
        ),
      );
      if (replace == true && mounted) {
        setState(() {
          _workout = latest;
          _draft = _cloneSession(latest.session);
          _dirty = false;
          _failed = false;
          _pendingRequestId = null;
          _expanded.clear();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        AppSnackbar.error(context, '최신 기록을 불러오지 못했어요. 입력은 그대로 남아 있어요.');
      }
    }
  }

  Future<void> _setConsent(bool allowed) async {
    if (_saving || _workout?.scheduleId == null) return;
    setState(() => _saving = true);
    try {
      await _repository.setLessonRecordingConsent(
        _workout!.scheduleId!,
        allowed,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      await _load();
      if (!mounted) return;
      unawaited(
        AppScope.of(context).refreshCoachingWorkouts().catchError((_) {}),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppSnackbar.error(context, '기록 허용 설정을 저장하지 못했어요. 다시 시도해주세요.');
    }
  }

  Future<void> _addExercise() async {
    final template = await _pickExercise(context);
    if (template == null || !mounted || !_editable) return;
    final next = _cloneSession(_draft!);
    next.exercises.add(_newExercise(template));
    await _save(next);
  }

  Future<void> _complete(int exerciseIndex, int setIndex) async {
    if (!_editable) return;
    final before = _cloneSession(_draft!);
    final next = _cloneSession(_draft!);
    final exercise = next.exercises[exerciseIndex];
    final set = exercise.sets[setIndex];
    set.completed = !set.completed;
    var propagated = false;
    if (set.completed) {
      next.startedAt ??= DateTime.now();
      for (var index = setIndex + 1; index < exercise.sets.length; index++) {
        final pending = exercise.sets[index];
        if (pending.completed) continue;
        if (pending.weight != set.weight ||
            pending.reps != set.reps ||
            pending.durationSeconds != set.durationSeconds ||
            pending.distanceKm != set.distanceKm ||
            pending.intensityRpe != set.intensityRpe ||
            pending.restSeconds != set.restSeconds) {
          propagated = true;
          pending.weight = set.weight;
          pending.reps = set.reps;
          pending.durationSeconds = set.durationSeconds;
          pending.distanceKm = set.distanceKm;
          pending.intensityRpe = set.intensityRpe;
          pending.restSeconds = set.restSeconds;
        }
      }
      next.endedAt = next.isComplete ? DateTime.now() : null;
    } else {
      next.endedAt = null;
    }
    final success = await _save(next);
    if (!mounted || !success) return;
    setState(() => _expanded.remove('${exercise.id}:$setIndex'));
    if (set.completed && set.restSeconds > 0 && !next.isComplete) {
      final following = next.exercises
          .skip(exerciseIndex + 1)
          .where((item) => item.sets.any((set) => !set.completed))
          .firstOrNull;
      AppScope.of(context).startRestTimer(
        set.restSeconds,
        focus: RestFocus(
          exerciseName: exercise.template.name,
          setsLeft: exercise.sets.where((set) => !set.completed).length,
          nextExercise: following?.template.name,
        ),
      );
    }
    if (propagated) {
      final version = _workout!.version;
      AppSnackbar.undoable(
        context,
        '남은 세트에도 기록한 값을 적용했어요.',
        actionLabel: '되돌리기',
        onAction: () {
          if (!mounted || !_editable || _workout?.version != version) return;
          final undo = _cloneSession(_draft!);
          for (
            var index = setIndex + 1;
            index < exercise.sets.length;
            index++
          ) {
            if (!undo.exercises[exerciseIndex].sets[index].completed) {
              undo.exercises[exerciseIndex].sets[index] = _cloneSet(
                before.exercises[exerciseIndex].sets[index],
              );
            }
          }
          _save(undo);
        },
      );
    }
  }

  Future<void> _deleteSet(int exerciseIndex, int setIndex) async {
    if (!_editable) return;
    final next = _cloneSession(_draft!);
    final sets = next.exercises[exerciseIndex].sets;
    sets.removeAt(setIndex);
    for (var index = 0; index < sets.length; index++) {
      sets[index].number = index + 1;
    }
    if (sets.isEmpty) next.exercises.removeAt(exerciseIndex);
    await _save(next);
  }

  @override
  Widget build(BuildContext context) {
    final workout = _workout;
    final session = _draft;
    final state = AppScope.of(context);
    final isMember = workout?.memberUserId == _actorId(state);
    final lesson = workout?.kind == CoachingWorkoutKind.lesson;
    return PopScope(
      canPop: _allowLeave || (!_dirty && !_saving),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leaveWithDraft();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(lesson ? '수업 운동 기록' : '운동 과제'),
          actions: [
            IconButton(
              tooltip: '기록 새로고침',
              onPressed: _dirty || _saving || _loading ? null : _load,
              icon: const Icon(SetflowIcons.undo),
            ),
          ],
        ),
        body: _loading && session == null
            ? const Center(child: CircularProgressIndicator())
            : workout == null || session == null
            ? _Unavailable(onRetry: _load)
            : ListView(
                padding: SetflowInsets.pageList,
                children: [
                  Text(
                    isMember
                        ? '${workout.trainerName} 트레이너의 ${lesson ? '수업' : '과제'}'
                        : lesson && _editable
                        ? '${workout.memberName} 회원님 대신 기록 중'
                        : '${workout.memberName} 회원님의 ${lesson ? '수업 기록' : '운동 과제'}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: SetflowSpacing.sm),
                  Text(
                    workout.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: SetflowSpacing.sm),
                  Text(
                    '${_dateLabel(workout.date)} · ${_statusLabel(workout)}'
                    '${workout.startsAt == null || workout.endsAt == null ? '' : ' · ${_timeLabel(workout.startsAt!)}–${_timeLabel(workout.endsAt!)}'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (workout.instruction.isNotEmpty) ...[
                    const SizedBox(height: SetflowSpacing.md),
                    Text(workout.instruction),
                  ],
                  const SizedBox(height: SetflowSpacing.md),
                  if (lesson && isMember)
                    SwitchListTile(
                      key: const ValueKey('lesson-recording-consent'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('트레이너 기록 허용'),
                      subtitle: const Text(
                        '예약된 수업 시간 동안 이 수업의 운동을 대신 기록해요. 언제든 끌 수 있어요.',
                      ),
                      value: workout.recordingAllowed,
                      onChanged: _saving || workout.isCancelled
                          ? null
                          : _setConsent,
                    ),
                  if (!_editable && !_saving && !_dirty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: SetflowSpacing.md,
                      ),
                      child: Text(
                        lesson && !_inWindow
                            ? '예약된 수업 시간에만 트레이너가 기록할 수 있어요.'
                            : workout.editBlockedReason ??
                                  '현재 이 기록을 확인할 수 있어요.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  if (_saving)
                    const Text(
                      '회원 일지에 저장 중…',
                      key: ValueKey('coaching-save-status'),
                    )
                  else if (_dirty && _failed) ...[
                    Text(
                      '저장하지 못했어요. 입력은 이 화면에 남아 있어요. 연결·수업 시간·기록 허용 상태를 확인해주세요.',
                      key: const ValueKey('coaching-save-error'),
                      style: TextStyle(color: context.setflowColors.error),
                    ),
                    OutlinedButton(
                      key: const ValueKey('coaching-save-retry'),
                      onPressed: () => _save(),
                      child: const Text('저장 재시도'),
                    ),
                    TextButton(
                      key: const ValueKey('coaching-review-latest'),
                      onPressed: _reviewLatest,
                      child: const Text('최신 기록 불러오기'),
                    ),
                  ] else
                    Text(
                      '회원 일지에 저장됨${workout.lastEditorName == null ? '' : ' · ${workout.lastEditorName} 기록'}',
                      key: const ValueKey('coaching-save-status'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: SetflowSpacing.xl),
                  Text(
                    '${session.completedSets} / ${session.totalSets}세트',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: SetflowSpacing.md),
                  if (_editable && session.totalSets > 0)
                    const Padding(
                      padding: EdgeInsets.only(bottom: SetflowSpacing.md),
                      child: Text('오른쪽으로 밀어 완료 · 왼쪽으로 밀어 삭제'),
                    ),
                  if (session.exercises.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: SetflowSpacing.xl,
                      ),
                      child: Text('종목을 추가하면 첫 세트부터 기록할 수 있어요.'),
                    ),
                  for (
                    var exerciseIndex = 0;
                    exerciseIndex < session.exercises.length;
                    exerciseIndex++
                  )
                    _exerciseCard(exerciseIndex),
                  if (_editable)
                    OutlinedButton.icon(
                      key: const ValueKey('coaching-add-exercise'),
                      onPressed: _addExercise,
                      icon: const Icon(SetflowIcons.addExercise),
                      label: const Text('종목 추가'),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _exerciseCard(int exerciseIndex) {
    final exercise = _draft!.exercises[exerciseIndex];
    final firstPending = exercise.sets.indexWhere((set) => !set.completed);
    return Padding(
      padding: const EdgeInsets.only(bottom: SetflowSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            exercise.template.name,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: SetflowSpacing.sm),
          for (var index = 0; index < exercise.sets.length; index++) ...[
            _CoachingSetRow(
              key: ValueKey('${exercise.id}:$index'),
              template: exercise.template,
              set: exercise.sets[index],
              enabled: _editable,
              live:
                  _editable &&
                  (exercise.sets[index].completed || index == firstPending),
              expanded: _expanded.contains('${exercise.id}:$index'),
              onExpand: () =>
                  setState(() => _expanded.add('${exercise.id}:$index')),
              onComplete: () => _complete(exerciseIndex, index),
              onDelete: () => _deleteSet(exerciseIndex, index),
              onEdit: (update) async {
                if (!_editable) return;
                final next = _cloneSession(_draft!);
                update(next.exercises[exerciseIndex].sets[index]);
                await _save(next);
              },
            ),
            const SizedBox(height: SetflowSpacing.sm),
          ],
          if (_editable)
            TextButton.icon(
              onPressed: () {
                final next = _cloneSession(_draft!);
                final sets = next.exercises[exerciseIndex].sets;
                final set = sets.isEmpty
                    ? _defaultSet(exercise.template)
                    : sets.last.copy();
                set.number = sets.length + 1;
                sets.add(set);
                _save(next);
              },
              icon: const Icon(SetflowIcons.addExercise),
              label: const Text('세트 추가'),
            ),
        ],
      ),
    );
  }
}

typedef _SetMutation = void Function(WorkoutSetEntry set);

class _CoachingSetRow extends StatefulWidget {
  const _CoachingSetRow({
    required this.template,
    required this.set,
    required this.enabled,
    required this.live,
    required this.expanded,
    required this.onExpand,
    required this.onComplete,
    required this.onDelete,
    required this.onEdit,
    super.key,
  });

  final ExerciseTemplate template;
  final WorkoutSetEntry set;
  final bool enabled;
  final bool live;
  final bool expanded;
  final VoidCallback onExpand;
  final Future<void> Function() onComplete;
  final Future<void> Function() onDelete;
  final Future<void> Function(_SetMutation) onEdit;

  @override
  State<_CoachingSetRow> createState() => _CoachingSetRowState();
}

class _CoachingSetRowState extends State<_CoachingSetRow> {
  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    final set = widget.set;
    final theme = Theme.of(context);
    final collapsed = set.completed && !widget.expanded;
    final child = Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(SetflowSpacing.md),
        child: collapsed
            ? InkWell(
                onTap: widget.onExpand,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: SetflowSpacing.sm,
                  ),
                  child: Text(
                    '${set.number}세트  ${_setSummary(widget.template, set)} · 완료',
                  ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${set.number}세트${set.completed
                        ? ' · 완료'
                        : widget.live
                        ? ' · 지금 할 세트'
                        : ''}',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: SetflowSpacing.sm),
                  _SetValues(
                    template: widget.template,
                    set: set,
                    enabled: widget.enabled,
                    onEdit: widget.onEdit,
                  ),
                ],
              ),
      ),
    );
    return Semantics(
      label: '${widget.template.name} ${set.number}세트',
      customSemanticsActions: widget.live
          ? {
              CustomSemanticsAction(
                label: set.completed ? '완료 되돌리기' : '완료',
              ): () {
                widget.onComplete();
              },
              const CustomSemanticsAction(label: '세트 삭제'): () {
                widget.onDelete();
              },
            }
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SetflowRadii.md),
        child: Dismissible(
          key: ValueKey('swipe-${widget.key}'),
          direction: widget.live
              ? DismissDirection.horizontal
              : DismissDirection.none,
          dismissThresholds: const {
            DismissDirection.startToEnd: .4,
            DismissDirection.endToStart: .4,
          },
          onUpdate: (details) => setState(() => _progress = details.progress),
          background: _track(context, false),
          secondaryBackground: _track(context, true),
          confirmDismiss: (direction) async {
            if (!widget.live) return false;
            if (direction == DismissDirection.startToEnd) {
              await widget.onComplete();
            } else {
              await widget.onDelete();
            }
            return false;
          },
          child: child,
        ),
      ),
    );
  }

  Widget _track(BuildContext context, bool deletion) {
    final color = deletion
        ? context.setflowColors.error
        : context.setflowColors.brandDeep;
    return Align(
      alignment: deletion ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: _progress.clamp(0, 1),
        heightFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12 + .24 * _progress.clamp(0, 1)),
            borderRadius: BorderRadius.circular(SetflowRadii.md),
          ),
          child: Center(
            child: Icon(
              deletion ? SetflowIcons.delete : SetflowIcons.setComplete,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

String _number(double value) => value.toStringAsFixed(value % 1 == 0 ? 0 : 1);

String _setSummary(ExerciseTemplate template, WorkoutSetEntry set) =>
    template.isCardio
    ? '${_number(set.durationSeconds / 60)}분 · ${_number(set.distanceKm)}km'
    : template.isDurationHold
    ? '${set.durationSeconds}초'
    : template.usesWeight
    ? '${_number(set.weight)}kg × ${set.reps}회'
    : '${set.reps}회';

class _SetValues extends StatelessWidget {
  const _SetValues({
    required this.template,
    required this.set,
    required this.enabled,
    required this.onEdit,
  });
  final ExerciseTemplate template;
  final WorkoutSetEntry set;
  final bool enabled;
  final Future<void> Function(_SetMutation) onEdit;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: SetflowSpacing.sm,
    runSpacing: SetflowSpacing.sm,
    children: [
      if (template.usesWeight)
        _value(
          context,
          '무게',
          'kg',
          set.weight,
          0,
          500,
          .5,
          (s, v) => s.weight = v,
        ),
      if (!template.isCardio && !template.isDurationHold)
        _value(
          context,
          '횟수',
          '회',
          set.reps.toDouble(),
          1,
          200,
          1,
          (s, v) => s.reps = v.round(),
        ),
      if (template.isCardio)
        _value(
          context,
          '시간',
          '분',
          set.durationSeconds / 60,
          1,
          300,
          1,
          (s, v) => s.durationSeconds = (v * 60).round(),
        ),
      if (template.isDurationHold)
        _value(
          context,
          '시간',
          '초',
          set.durationSeconds.toDouble(),
          1,
          3600,
          1,
          (s, v) => s.durationSeconds = v.round(),
        ),
      if (template.isCardio) ...[
        _value(
          context,
          '거리',
          'km',
          set.distanceKm,
          0,
          100,
          .1,
          (s, v) => s.distanceKm = v,
        ),
        _value(
          context,
          '강도',
          'RPE',
          set.intensityRpe,
          0,
          10,
          .5,
          (s, v) => s.intensityRpe = v,
        ),
      ],
      _value(
        context,
        '휴식',
        '초',
        set.restSeconds.toDouble(),
        0,
        600,
        5,
        (s, v) => s.restSeconds = v.round(),
      ),
    ],
  );

  Widget _value(
    BuildContext context,
    String title,
    String suffix,
    double value,
    double min,
    double max,
    double step,
    void Function(WorkoutSetEntry, double) apply,
  ) => OutlinedButton(
    key: ValueKey('coaching-value-${template.id}-${set.number}-$title'),
    onPressed: !enabled
        ? null
        : () async {
            final result = await showNumberDial(
              context,
              title: title,
              suffix: suffix,
              initialValue: value,
              min: min,
              max: max,
              step: step,
            );
            if (result == null || !context.mounted) return;
            await onEdit((set) => apply(set, result));
          },
    child: Text('$title ${_number(value)}$suffix'),
  );
}

WorkoutSetEntry _defaultSet(ExerciseTemplate template) => WorkoutSetEntry(
  number: 1,
  weight: 0,
  reps: template.isCardio || template.isDurationHold ? 0 : 10,
  durationSeconds: template.isCardio
      ? 1200
      : template.isDurationHold
      ? 30
      : 0,
  restSeconds: template.isCardio ? 0 : 90,
);

WorkoutExercise _newExercise(ExerciseTemplate template) => WorkoutExercise(
  id: _requestId(),
  template: template,
  sets: [_defaultSet(template)],
);

Future<ExerciseTemplate?> _pickExercise(BuildContext context) =>
    showSetflowSheet<ExerciseTemplate>(
      context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ExercisePicker(catalog: AppScope.of(context).exercises),
    );

class _ExercisePicker extends StatefulWidget {
  const _ExercisePicker({required this.catalog});
  final List<ExerciseTemplate> catalog;
  @override
  State<_ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends State<_ExercisePicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final items = widget.catalog
        .where((item) => '${item.name} ${item.muscle}'.contains(_query))
        .take(80)
        .toList();
    return Padding(
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
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
            ),
            Expanded(
              child: ListView(
                padding: SetflowInsets.pageList,
                children: [
                  if (items.isEmpty) const Text('검색 결과가 없어요.'),
                  for (final item in items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.name),
                      subtitle: Text(item.muscle),
                      onTap: () => Navigator.pop(context, item),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CoachingAssignmentsScreen extends StatelessWidget {
  const CoachingAssignmentsScreen({this.memberUserId, super.key});
  final String? memberUserId;
  @override
  Widget build(BuildContext context) => _CoachingAccountBoundary(
    child: _CoachingAssignmentsPage(memberUserId: memberUserId),
  );
}

class _CoachingAssignmentsPage extends StatefulWidget {
  const _CoachingAssignmentsPage({this.memberUserId});
  final String? memberUserId;
  @override
  State<_CoachingAssignmentsPage> createState() =>
      _CoachingAssignmentsScreenState();
}

class _CoachingAssignmentsScreenState extends State<_CoachingAssignmentsPage> {
  List<CoachingWorkout> _items = const [];
  bool _requested = false;
  bool _loading = true;
  bool _failed = false;
  String? _cancelling;
  final Map<String, String> _cancelRequests = {};
  bool get _trainer =>
      widget.memberUserId != null &&
      AppScope.of(
            context,
          ).businessAccess?.availableRoles.contains(UserRole.trainer) ==
          true &&
      widget.memberUserId != _actorId(AppScope.of(context));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final repository = AppScope.of(context).coachingWorkoutRepository;
      if (repository == null) throw StateError('Coaching unavailable');
      final items = await repository.listCoachingWorkouts(
        memberUserId: widget.memberUserId,
      );
      if (!mounted) return;
      setState(() {
        _items =
            items
                .where((w) => w.kind == CoachingWorkoutKind.assignment)
                .toList()
              ..sort((a, b) => b.date.compareTo(a.date));
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
          _items = const [];
        });
      }
    }
  }

  Future<void> _cancel(CoachingWorkout workout) async {
    if (_cancelling != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_trainer ? '과제를 취소할까요?' : '이번 과제를 건너뛸까요?'),
        content: const Text('이미 수행한 기록은 일지에 남고, 이 과제의 알림은 멈춥니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('돌아가기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_trainer ? '과제 취소' : '건너뛰기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _cancelling = workout.id);
    try {
      await AppScope.of(
        context,
      ).coachingWorkoutRepository!.cancelWorkoutAssignment(
        workoutId: workout.id,
        expectedVersion: workout.version,
        requestId: _cancelRequests.putIfAbsent(workout.id, _requestId),
      );
      _cancelRequests.remove(workout.id);
      if (!mounted) return;
      unawaited(
        AppScope.of(context).refreshCoachingWorkouts().catchError((_) {}),
      );
      await _load();
    } catch (_) {
      if (mounted) AppSnackbar.error(context, '과제를 변경하지 못했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _cancelling = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('운동 과제'),
      actions: [
        if (!_trainer)
          IconButton(
            tooltip: '과제 알림 설정',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const _CoachingAccountBoundary(
                  child: _CoachingReminderScreen(),
                ),
              ),
            ),
            icon: const Icon(SetflowIcons.notifications),
          ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: SetflowInsets.pageList,
        children: [
          Text(_trainer ? '회원의 수업 밖 운동까지 이어가요.' : '트레이너가 준비한 운동을 내 속도로 이어가요.'),
          const SizedBox(height: SetflowSpacing.lg),
          if (_trainer && widget.memberUserId != null)
            FilledButton.icon(
              key: const ValueKey('coaching-create-assignment'),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => CoachingAssignmentComposerScreen(
                      memberUserId: widget.memberUserId!,
                    ),
                  ),
                );
                if (context.mounted) _load();
              },
              icon: const Icon(SetflowIcons.addExercise),
              label: const Text('운동 과제 만들기'),
            ),
          if (_loading) const LinearProgressIndicator(),
          if (_failed) _Unavailable(onRetry: _load),
          if (!_loading && !_failed && _items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: SetflowSpacing.section),
              child: Text('아직 받은 운동 과제가 없어요.'),
            ),
          for (final workout in _items) ...[
            const SizedBox(height: SetflowSpacing.md),
            SetflowCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${_dateLabel(workout.date)} · ${_statusLabel(workout)}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: SetflowSpacing.sm),
                  Text(
                    workout.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    _trainer
                        ? '${workout.memberName} 회원님'
                        : '${workout.trainerName} 트레이너',
                  ),
                  if (workout.instruction.isNotEmpty) ...[
                    const SizedBox(height: SetflowSpacing.sm),
                    Text(workout.instruction),
                  ],
                  const SizedBox(height: SetflowSpacing.md),
                  Text(
                    '${workout.session.completedSets} / ${workout.session.totalSets}세트',
                  ),
                  const SizedBox(height: SetflowSpacing.sm),
                  FilledButton(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              CoachingWorkoutScreen(workoutId: workout.id),
                        ),
                      );
                      if (context.mounted) _load();
                    },
                    child: Text(
                      workout.canEdit && !workout.session.isComplete
                          ? '운동 시작'
                          : '기록 보기',
                    ),
                  ),
                  if (!workout.isCancelled &&
                      workout.status != CoachingWorkoutStatus.completed)
                    TextButton(
                      onPressed: _cancelling != null
                          ? null
                          : () => _cancel(workout),
                      child: Text(
                        _cancelling == workout.id
                            ? '저장 중…'
                            : _trainer
                            ? '과제 취소'
                            : '이번 과제 건너뛰기',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class CoachingAssignmentComposerScreen extends StatelessWidget {
  const CoachingAssignmentComposerScreen({
    required this.memberUserId,
    super.key,
  });
  final String memberUserId;
  @override
  Widget build(BuildContext context) => _CoachingAccountBoundary(
    child: _CoachingAssignmentComposerPage(memberUserId: memberUserId),
  );
}

class _CoachingAssignmentComposerPage extends StatefulWidget {
  const _CoachingAssignmentComposerPage({required this.memberUserId});
  final String memberUserId;
  @override
  State<_CoachingAssignmentComposerPage> createState() =>
      _CoachingAssignmentComposerScreenState();
}

class _CoachingAssignmentComposerScreenState
    extends State<_CoachingAssignmentComposerPage> {
  final _title = TextEditingController();
  final _instruction = TextEditingController();
  final _form = GlobalKey<FormState>();
  late DateTime _date;
  late WorkoutSession _session;
  bool _saving = false;
  bool _failed = false;
  String? _request;
  bool _allowLeave = false;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _date = DateTime(today.year, today.month, today.day);
    _session = WorkoutSession(date: _date, exercises: []);
  }

  @override
  void dispose() {
    _title.dispose();
    _instruction.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    if (_session.totalSets == 0) {
      AppSnackbar.info(context, '운동 종목을 하나 이상 추가해주세요.');
      return;
    }
    setState(() {
      _saving = true;
      _failed = false;
      _request ??= _requestId();
    });
    try {
      final repository = AppScope.of(context).coachingWorkoutRepository;
      if (repository == null) throw StateError('Coaching unavailable');
      final workout = await repository.createWorkoutAssignment(
        memberUserId: widget.memberUserId,
        date: _date,
        title: _title.text.trim(),
        instruction: _instruction.text.trim(),
        session: WorkoutSession(
          date: _date,
          exercises: _cloneSession(_session).exercises,
        ),
        requestId: _request!,
      );
      if (!mounted) return;
      unawaited(
        AppScope.of(context).refreshCoachingWorkouts().catchError((_) {}),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CoachingWorkoutScreen(workoutId: workout.id),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _confirmLeave() async {
    if (_saving) return;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('과제를 남겨둘까요?'),
        content: const Text(
          '전달 결과를 확인하지 못했어요. 입력을 유지하고 다시 시도하거나, 이 화면의 초안을 지우고 과제함에서 확인할 수 있어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('입력 유지'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('초안 버리고 나가기'),
          ),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    setState(() => _allowLeave = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowLeave || (!_saving && !_failed),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _confirmLeave();
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('새 운동 과제')),
      body: Form(
        key: _form,
        child: ListView(
          padding: SetflowInsets.pageForm,
          children: [
            const Text('날짜와 운동을 정하면 회원의 과제함에 전달돼요. 반복 알림은 회원이 직접 선택합니다.'),
            const SizedBox(height: SetflowSpacing.lg),
            TextFormField(
              controller: _title,
              enabled: !_saving && !_failed,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: '과제 이름',
                hintText: '예: 화요일 하체 운동',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? '과제 이름을 입력해주세요.'
                  : null,
            ),
            OutlinedButton.icon(
              onPressed: _saving || _failed
                  ? null
                  : () async {
                      final now = DateTime.now();
                      final today = DateTime(now.year, now.month, now.day);
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _date.isBefore(today) ? today : _date,
                        firstDate: today,
                        lastDate: today.add(const Duration(days: 90)),
                      );
                      if (date != null && mounted) setState(() => _date = date);
                    },
              icon: const Icon(SetflowIcons.calendar),
              label: Text('운동할 날짜 · ${_dateLabel(_date)}'),
            ),
            const SizedBox(height: SetflowSpacing.md),
            TextField(
              controller: _instruction,
              enabled: !_saving && !_failed,
              minLines: 2,
              maxLines: 5,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: '회원에게 전할 말',
                hintText: '순서, 운동 강도, 주의할 점을 알려주세요.',
              ),
            ),
            const SizedBox(height: SetflowSpacing.lg),
            for (var i = 0; i < _session.exercises.length; i++)
              _plannedExercise(i),
            OutlinedButton.icon(
              key: const ValueKey('assignment-add-exercise'),
              onPressed: _saving || _failed
                  ? null
                  : () async {
                      final template = await _pickExercise(context);
                      if (template != null && mounted) {
                        setState(
                          () => _session.exercises.add(_newExercise(template)),
                        );
                      }
                    },
              icon: const Icon(SetflowIcons.addExercise),
              label: const Text('종목 추가'),
            ),
            const SizedBox(height: SetflowSpacing.lg),
            if (_failed)
              Text(
                '전달하지 못했어요. 입력한 과제는 남아 있습니다. 다시 시도해주세요.',
                style: TextStyle(color: context.setflowColors.error),
              ),
            FilledButton(
              key: const ValueKey('assignment-send'),
              onPressed: _saving ? null : _save,
              child: Text(
                _saving
                    ? '전달 중…'
                    : _failed
                    ? '전달 재시도'
                    : '회원에게 과제 보내기',
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _plannedExercise(int index) {
    final exercise = _session.exercises[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: SetflowSpacing.lg),
      child: SetflowCard(
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
                IconButton(
                  tooltip: '종목 삭제',
                  onPressed: _saving || _failed
                      ? null
                      : () =>
                            setState(() => _session.exercises.removeAt(index)),
                  icon: const Icon(SetflowIcons.delete),
                ),
              ],
            ),
            for (var i = 0; i < exercise.sets.length; i++) ...[
              Row(
                children: [
                  Expanded(child: Text('${i + 1}세트')),
                  IconButton(
                    tooltip: '${i + 1}세트 삭제',
                    onPressed: _saving || _failed || exercise.sets.length == 1
                        ? null
                        : () => setState(() {
                            exercise.sets.removeAt(i);
                            for (var n = 0; n < exercise.sets.length; n++) {
                              exercise.sets[n].number = n + 1;
                            }
                          }),
                    icon: const Icon(SetflowIcons.delete),
                  ),
                ],
              ),
              _SetValues(
                template: exercise.template,
                set: exercise.sets[i],
                enabled: !_saving && !_failed,
                onEdit: (update) async {
                  if (!_saving && !_failed) {
                    setState(() => update(exercise.sets[i]));
                  }
                },
              ),
              const SizedBox(height: SetflowSpacing.sm),
            ],
            TextButton.icon(
              onPressed: _saving || _failed
                  ? null
                  : () => setState(() {
                      final set = exercise.sets.last.copy();
                      set.number = exercise.sets.length + 1;
                      exercise.sets.add(set);
                    }),
              icon: const Icon(SetflowIcons.addExercise),
              label: const Text('세트 추가'),
            ),
          ],
        ),
      ),
    );
  }
}

class MemberCoachingTasksCard extends StatelessWidget {
  const MemberCoachingTasksCard({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final actor = _actorId(state);
    if (actor == null || state.coachingWorkoutRepository == null) {
      return const SizedBox.shrink();
    }
    final assignments = state.coachingWorkouts
        .where(
          (workout) =>
              workout.memberUserId == actor &&
              workout.kind == CoachingWorkoutKind.assignment,
        )
        .toList();
    final pending =
        assignments
            .where(
              (w) =>
                  w.memberUserId == actor &&
                  w.kind == CoachingWorkoutKind.assignment &&
                  !w.isCancelled &&
                  w.status != CoachingWorkoutStatus.completed,
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    if (assignments.isEmpty && state.coachingWorkoutsError == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: SetflowSpacing.lg),
      child: SetflowCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('트레이너의 운동 과제', style: Theme.of(context).textTheme.titleMedium),
            if (state.coachingWorkoutsError != null)
              const Text('최신 과제를 확인하지 못했어요. 과제함에서 다시 확인해주세요.')
            else if (pending.isEmpty)
              const Text('오늘 남은 과제가 없어요.'),
            for (final workout in pending.take(2)) ...[
              const SizedBox(height: SetflowSpacing.md),
              Text(
                '${_dateLabel(workout.date)} · ${workout.trainerName} 트레이너',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(workout.title),
              Text(
                '${workout.session.completedSets} / ${workout.session.totalSets}세트',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              FilledButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        CoachingWorkoutScreen(workoutId: workout.id),
                  ),
                ),
                child: Text(workout.canEdit ? '과제 시작' : '과제 확인'),
              ),
            ],
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const CoachingAssignmentsScreen(),
                ),
              ),
              child: const Text('전체 과제와 알림 설정'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoachingReminderScreen extends StatefulWidget {
  const _CoachingReminderScreen();
  @override
  State<_CoachingReminderScreen> createState() =>
      _CoachingReminderScreenState();
}

class _CoachingReminderScreenState extends State<_CoachingReminderScreen> {
  bool _requested = false;
  bool _loading = true;
  bool _failed = false;
  bool _saving = false;
  bool _enabled = false;
  int _hour = 19;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final preferences = await AppScope.of(
        context,
      ).coachingWorkoutRepository!.loadMyCoachingReminder();
      if (mounted) {
        setState(() {
          _enabled = preferences.enabled;
          _hour = preferences.hour;
          _loading = false;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await AppScope.of(
        context,
      ).coachingWorkoutRepository!.setMyCoachingReminder(_enabled, _hour);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        AppSnackbar.error(context, '알림 설정을 저장하지 못했어요.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('과제 알림')),
    body: ListView(
      padding: SetflowInsets.pageForm,
      children: [
        const Text('미완료 과제가 있을 때만 하루 한 번 알려드려요. 완료하거나 건너뛰면 해당 과제의 알림은 멈춥니다.'),
        const SizedBox(height: SetflowSpacing.lg),
        if (_loading)
          const LinearProgressIndicator()
        else if (_failed)
          _Unavailable(onRetry: _load)
        else ...[
          SwitchListTile(
            key: const ValueKey('coaching-reminder-enabled'),
            contentPadding: EdgeInsets.zero,
            title: const Text('매일 과제 알림 받기'),
            value: _enabled,
            onChanged: _saving
                ? null
                : (value) => setState(() => _enabled = value),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('알림 시간 (한국 시각)'),
            subtitle: Text('매일 $_hour시'),
            onTap: !_enabled || _saving
                ? null
                : () async {
                    final value = await showNumberDial(
                      context,
                      title: '알림 시간',
                      suffix: '시',
                      initialValue: _hour.toDouble(),
                      min: 6,
                      max: 22,
                      step: 1,
                    );
                    if (value != null && mounted) {
                      setState(() => _hour = value.round());
                    }
                  },
          ),
          const SizedBox(height: SetflowSpacing.lg),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '저장 중…' : '알림 설정 저장'),
          ),
        ],
      ],
    ),
  );
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onRetry});
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: SetflowSpacing.xl),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('기록을 불러오지 못했어요. 연결과 코칭 권한을 확인해주세요.'),
        TextButton(onPressed: onRetry, child: const Text('다시 불러오기')),
      ],
    ),
  );
}
