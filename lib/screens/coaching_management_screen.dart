import 'dart:math';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/coaching_management_repository.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/common.dart';
import '../widgets/auth_gate.dart';
import '../widgets/pro_access_gate.dart';
import 'coaching_workout_screens.dart' show CoachingAccountBoundary;
import 'workout_screens.dart' show showNumberDial;

Future<void> openCoachingManagement(
  BuildContext context, {
  String? consultationId,
}) async {
  if (AppScope.of(context).role == UserRole.trainer) {
    if (!await requireProAccess(context)) return;
  } else if (!await requireSignIn(context, reason: AuthReason.coaching)) {
    return;
  }
  if (!context.mounted) return;
  final state = AppScope.of(context);
  final accountId = state.businessAccess?.userId;
  final role = state.role;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CoachingManagementScreen(consultationId: consultationId),
    ),
  );
  if (!context.mounted ||
      state.businessAccess?.userId != accountId ||
      state.role != role) {
    return;
  }
  if (state.usesLiveBusinessData &&
      (role == UserRole.trainer || role == UserRole.gym)) {
    try {
      await state.refreshBusinessDashboard(role);
    } catch (_) {
      if (context.mounted) {
        AppSnackbar.error(context, '회원 목록을 새로고침하지 못했어요. 다시 확인해주세요.');
      }
    }
  }
}

CoachingManagementRepository? managementRepository(BuildContext context) {
  final repository = AppScope.of(context).businessRepository;
  return repository is CoachingManagementRepository
      ? repository as CoachingManagementRepository
      : null;
}

const _consentDescription =
    '연결을 수락하면 트레이너가 이전 기록을 포함한 모든 운동 기록을 조회하고 수정할 수 있어요. '
    '수업·개인 운동 모두 종료 후 48시간이 지난 기록은 수정할 때마다 회원 승인이 필요해요. '
    '종료 시각이 없는 기록도 승인을 받아요. 언제든 연결을 해제할 수 있어요.';

String _number(double? value) => value == null
    ? '미입력'
    : value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();
String _date(DateTime value) => '${value.year}.${value.month}.${value.day}';
String _status(String status) => switch (status) {
  'pending' => '승인 대기',
  'active' => '연결됨',
  'rejected' => '거절됨',
  'ended' => '연결 해제',
  'suspended' => '연결 일시 중단',
  'applied' => '수정 반영됨',
  'conflict' => '원본 변경으로 미반영',
  'cancelled' => '요청 취소됨',
  _ => status,
};

class CoachingManagementScreen extends StatelessWidget {
  const CoachingManagementScreen({this.consultationId, super.key});
  final String? consultationId;

  @override
  Widget build(BuildContext context) => CoachingAccountBoundary(
    child: _ManagementPage(consultationId: consultationId),
  );
}

class _ManagementPage extends StatefulWidget {
  const _ManagementPage({this.consultationId});
  final String? consultationId;
  @override
  State<_ManagementPage> createState() => _ManagementPageState();
}

class _ManagementPageState extends State<_ManagementPage>
    with WidgetsBindingObserver {
  List<CoachingManagementLink> _links = [];
  List<WorkoutCorrection> _corrections = [];
  bool _loading = true;
  bool _busy = false;
  bool _failed = false;
  bool _sent = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final repository = managementRepository(context);
      if (repository == null) throw StateError('연결 관리를 사용할 수 없어요.');
      final results = await Future.wait<Object>([
        repository.listManagementLinks(),
        repository.listWorkoutCorrections(),
      ]);
      if (!mounted || generation != _generation) return;
      setState(() {
        _links = results[0] as List<CoachingManagementLink>;
        _corrections = results[1] as List<WorkoutCorrection>;
      });
      AppScope.of(context).applyConfirmedWorkoutCorrections(_corrections);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = true;
        _links = [];
        _corrections = [];
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _run(
    Future<void> Function(CoachingManagementRepository) action,
  ) async {
    if (_busy || _loading) return;
    final repository = managementRepository(context);
    if (repository == null) return;
    setState(() => _busy = true);
    try {
      await action(repository);
      if (!mounted) return;
      await _load();
    } catch (error) {
      if (mounted) {
        final message = switch (error) {
          CoachingManagementFailure(
            reason: CoachingManagementFailureReason.selfConnection,
          ) =>
            '본인 계정과는 연결할 수 없어요. 다른 회원 또는 트레이너와 상담해주세요.',
          CoachingManagementFailure(
            reason: CoachingManagementFailureReason.accessDenied,
          ) =>
            '현재 이 상담의 연결을 요청할 권한이 없어요. 상담 목록과 담당 트레이너를 다시 확인해주세요.',
          _ => '처리하지 못했어요. 연결 상태와 최신 기록을 다시 확인해주세요.',
        };
        AppSnackbar.error(context, message);
        await _load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareGym(CoachingManagementLink link) async {
    final memberships = AppScope.of(
      context,
    ).memberMemberships.where((m) => m.isActive).toList();
    final selection = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('업장 공유 설정'),
        children: [
          const Padding(
            padding: EdgeInsets.all(SetflowSpacing.lg),
            child: Text(
              '선택한 소속 업장은 모든 운동 기록, 담당 트레이너와 수정 이력을 조회할 수 있어요. '
              '기록을 직접 수정할 수는 없어요. 소속이 끝나면 접근도 종료돼요.',
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('업장과 공유하지 않기'),
          ),
          for (final member in memberships)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, member.gymId),
              child: Text(member.gymName ?? '소속 업장'),
            ),
          if (memberships.isEmpty)
            const Padding(
              padding: EdgeInsets.all(SetflowSpacing.lg),
              child: Text('등록된 소속 업장이 없어요. 센터 초대를 수락한 뒤 공유할 수 있어요.'),
            ),
        ],
      ),
    );
    if (selection == null || !mounted) return;
    await _run(
      (repository) => repository.setManagementGym(
        link.id,
        selection.isEmpty ? null : selection,
      ),
    );
  }

  Future<void> _end(CoachingManagementLink link) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(link.viewerRole == 'gym' ? '업장 공유를 끝낼까요?' : '기록 관리 해제'),
        content: Text(
          link.viewerRole == 'gym'
              ? '업장에서 이 연결의 기록을 더 이상 볼 수 없어요.'
              : '이 연결의 전체 기록 조회·수정 권한을 종료하고 대기 중인 수정 요청을 취소해요. 수업별로 따로 허용한 공유는 해당 수업에서 관리해요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('해제'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run((repository) => repository.endManagementLink(link.id));
    }
  }

  Future<void> _changeTrainer(CoachingManagementLink link) async {
    final trainers = AppScope.of(context).businessTrainers
        .where(
          (t) =>
              t.gymId == link.gymId &&
              t.status == 'active' &&
              t.trainerId != null,
        )
        .toList();
    final trainerId = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('담당 변경 요청'),
        children: [
          const Padding(
            padding: EdgeInsets.all(SetflowSpacing.lg),
            child: Text('회원과 새 트레이너가 모두 수락하면 담당이 바뀌어요. 수락 전에는 기존 연결이 유지돼요.'),
          ),
          if (trainers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(SetflowSpacing.lg),
              child: Text('배정 가능한 소속 트레이너가 없어요.'),
            ),
          for (final trainer in trainers)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, trainer.trainerId),
              child: Text(trainer.displayName ?? '트레이너'),
            ),
        ],
      ),
    );
    if (trainerId != null && mounted) {
      await _run(
        (repository) =>
            repository.requestManagementTrainerChange(link.id, trainerId),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('운동 관리 연결'),
      actions: [
        IconButton(
          tooltip: '연결과 승인 요청 새로고침',
          onPressed: _busy || _loading ? null : _load,
          icon: const Icon(SetflowIcons.undo),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: SetflowInsets.pageList,
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (_failed) ...[
                  const Text('연결 정보를 불러오지 못했어요.'),
                  OutlinedButton(onPressed: _load, child: const Text('다시 시도')),
                ] else ...[
                  if (widget.consultationId != null) ...[
                    const Text(_consentDescription),
                    const SizedBox(height: SetflowSpacing.md),
                    FilledButton(
                      key: const ValueKey('request-management-link'),
                      onPressed: _busy || _sent
                          ? null
                          : () => _run((repository) async {
                              await repository.requestManagementLink(
                                widget.consultationId!,
                              );
                              if (mounted) setState(() => _sent = true);
                            }),
                      child: Text(_sent ? '연결 목록에서 상태를 확인해주세요' : '동의하고 연결 요청'),
                    ),
                    const SizedBox(height: SetflowSpacing.lg),
                  ],
                  if (_links.isEmpty)
                    const Text('아직 운동 관리 연결이 없어요. 상담 상세에서 상대에게 연결을 요청할 수 있어요.'),
                  for (final link in _links) ...[
                    SetflowCard(
                      key: ValueKey('management-link-${link.id}'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${link.memberName} · ${link.trainerName}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(_status(link.status)),
                          if (link.status == 'pending')
                            Text(
                              link.canRespond
                                  ? '동의하고 수락하면 운동 기록 관리가 시작돼요.'
                                  : link.viewerRole == 'gym'
                                  ? '회원과 트레이너의 수락을 기다리고 있어요.'
                                  : '상대의 수락을 기다리고 있어요.',
                            ),
                          if (link.gymName != null)
                            Text('공유 업장 · ${link.gymName}'),
                          if (link.canRespond) ...[
                            const SizedBox(height: SetflowSpacing.md),
                            const Text(_consentDescription),
                            Wrap(
                              spacing: SetflowSpacing.sm,
                              children: [
                                FilledButton(
                                  key: ValueKey('accept-link-${link.id}'),
                                  onPressed: _busy
                                      ? null
                                      : () => _run(
                                          (repository) =>
                                              repository.respondManagementLink(
                                                link.id,
                                                accept: true,
                                              ),
                                        ),
                                  child: const Text('동의하고 수락'),
                                ),
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _run(
                                          (repository) =>
                                              repository.respondManagementLink(
                                                link.id,
                                                accept: false,
                                              ),
                                        ),
                                  child: const Text('거절'),
                                ),
                              ],
                            ),
                          ],
                          if (link.isActive) ...[
                            OutlinedButton(
                              key: ValueKey('management-history-${link.id}'),
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              CoachingAccountBoundary(
                                                child: _ManagedHistoryPage(
                                                  link: link,
                                                ),
                                              ),
                                        ),
                                      );
                                      if (mounted) _load();
                                    },
                              child: const Text('전체 운동 기록'),
                            ),
                            if (link.viewerRole == 'member')
                              TextButton(
                                onPressed: _busy ? null : () => _shareGym(link),
                                child: const Text('업장 공유 설정'),
                              ),
                            if (link.viewerRole == 'gym')
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _changeTrainer(link),
                                child: const Text('담당 트레이너 변경 요청'),
                              ),
                          ],
                          if (link.status == 'active' ||
                              link.status == 'pending' ||
                              link.status == 'suspended')
                            TextButton(
                              onPressed: _busy ? null : () => _end(link),
                              child: Text(
                                link.viewerRole == 'gym'
                                    ? '업장 공유 종료'
                                    : '기록 관리 해제',
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: SetflowSpacing.md),
                  ],
                  const SizedBox(height: SetflowSpacing.lg),
                  Text(
                    '기록 수정 요청과 이력',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: SetflowSpacing.md),
                  if (_corrections.isEmpty) const Text('기록 수정 요청이 없어요.'),
                  for (final correction in _corrections) ...[
                    SetflowCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${correction.memberName} · ${correction.trainerName}',
                          ),
                          Text(
                            '${_date(correction.date)} · ${correction.workoutTitle}',
                          ),
                          Text(
                            '${correction.exerciseName} ${correction.setNumber}세트',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '${correction.metric.label}: ${_number(correction.before)} → ${_number(correction.after)} ${correction.metric.unit}',
                          ),
                          Text('수정 이유: ${correction.reason}'),
                          Text(_status(correction.status)),
                          if (correction.canRespond)
                            Wrap(
                              spacing: SetflowSpacing.sm,
                              children: [
                                FilledButton(
                                  key: ValueKey(
                                    'approve-correction-${correction.id}',
                                  ),
                                  onPressed: _busy
                                      ? null
                                      : () => _run(
                                          (repository) => repository
                                              .respondWorkoutCorrection(
                                                correction.id,
                                                accept: true,
                                              ),
                                        ),
                                  child: const Text('이 수정 승인'),
                                ),
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _run(
                                          (repository) => repository
                                              .respondWorkoutCorrection(
                                                correction.id,
                                                accept: false,
                                              ),
                                        ),
                                  child: const Text('거절'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: SetflowSpacing.md),
                  ],
                ],
              ],
            ),
          ),
  );
}

class _ManagedHistoryPage extends StatefulWidget {
  const _ManagedHistoryPage({required this.link});
  final CoachingManagementLink link;
  @override
  State<_ManagedHistoryPage> createState() => _ManagedHistoryPageState();
}

class _ManagedHistoryPageState extends State<_ManagedHistoryPage>
    with WidgetsBindingObserver {
  final List<ManagedWorkout> _workouts = [];
  String? _next;
  bool _loading = false;
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _load();
  }

  Future<void> _load({bool more = false}) async {
    if (!mounted || _loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await managementRepository(
        context,
      )!.listManagedWorkouts(widget.link.id, before: more ? _next : null);
      if (!mounted) return;
      setState(() {
        if (!more) _workouts.clear();
        _workouts.addAll(page.workouts);
        _next = page.nextCursor;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _workouts.clear();
          _next = null;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _correct(
    ManagedWorkout workout,
    WorkoutExercise exercise,
    WorkoutSetEntry set,
    WorkoutMetric metric,
  ) async {
    if (_busy || _loading) return;
    setState(() => _busy = true);
    try {
      final value = await showNumberDial(
        context,
        title: '${exercise.template.name} · ${metric.label}',
        suffix: metric.unit,
        initialValue: metric.read(set).clamp(metric.min, metric.max),
        min: metric.min,
        max: metric.max,
        step: metric.step,
      );
      if (value == null || !mounted || value == metric.read(set)) return;
      final reason = await showDialog<String>(
        context: context,
        builder: (_) => _CorrectionReasonDialog(
          workout: workout,
          exercise: exercise.template.name,
          setNumber: set.number,
          metric: metric,
          before: metric.read(set),
          after: value,
        ),
      );
      if (reason == null || !mounted) return;
      final random = Random.secure();
      final bytes = List.generate(16, (_) => random.nextInt(256));
      bytes[6] = (bytes[6] & 15) | 64;
      bytes[8] = (bytes[8] & 63) | 128;
      final hex = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
      final requestId =
          '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
      await managementRepository(context)!.proposeWorkoutCorrection(
        linkId: widget.link.id,
        workout: workout,
        exerciseId: exercise.id,
        setNumber: set.number,
        metric: metric,
        value: value,
        reason: reason,
        requestId: requestId,
      );
      if (mounted) {
        AppSnackbar.success(
          context,
          '수정 요청을 처리했어요. 연결 화면의 수정 이력에서 결과를 확인할 수 있어요.',
        );
        await _load();
      }
    } catch (_) {
      if (mounted) {
        AppSnackbar.error(context, '저장 결과를 확인하지 못했어요. 수정 이력을 확인한 뒤 다시 시도해주세요.');
        await _load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.link.memberName} 운동 기록'),
      actions: [
        IconButton(
          tooltip: '운동 기록 새로고침',
          onPressed: _busy || _loading ? null : _load,
          icon: const Icon(SetflowIcons.undo),
        ),
      ],
    ),
    body: ListView(
      padding: SetflowInsets.pageList,
      children: [
        if (_failed) ...[
          const Text('기록을 불러오지 못했어요. 연결과 공유 권한을 확인해주세요.'),
          OutlinedButton(onPressed: _load, child: const Text('다시 시도')),
        ],
        if (!_loading && !_failed && _workouts.isEmpty)
          const Text('아직 서버에 저장된 운동 기록이 없어요.'),
        for (final workout in _workouts) ...[
          SetflowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_date(workout.session.date)} · ${workout.title}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (workout.canPropose)
                  Text(
                    workout.requiresApproval
                        ? '수정 시 회원 승인이 필요해요.'
                        : '종료 후 48시간 이내 · 수정 시 회원에게 알려요.',
                  ),
                for (final exercise in workout.session.exercises) ...[
                  const SizedBox(height: SetflowSpacing.md),
                  Text(
                    exercise.template.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final set in exercise.sets) ...[
                    Text('${set.number}세트 · ${set.completed ? '완료' : '미완료'}'),
                    Wrap(
                      spacing: SetflowSpacing.sm,
                      runSpacing: SetflowSpacing.xs,
                      children: [
                        for (final metric in [
                          if (exercise.template.isCardio) ...[
                            WorkoutMetric.durationSeconds,
                            WorkoutMetric.distanceKm,
                            WorkoutMetric.intensityRpe,
                          ] else if (exercise.template.isDurationHold)
                            WorkoutMetric.durationSeconds
                          else ...[
                            WorkoutMetric.weight,
                            WorkoutMetric.reps,
                          ],
                          WorkoutMetric.restSeconds,
                          if (!exercise.template.isCardio) WorkoutMetric.rir,
                        ])
                          workout.canPropose
                              ? OutlinedButton(
                                  key: ValueKey(
                                    '${workout.key}-${exercise.id}-${set.number}-${metric.name}',
                                  ),
                                  onPressed: _busy || _loading
                                      ? null
                                      : () => _correct(
                                          workout,
                                          exercise,
                                          set,
                                          metric,
                                        ),
                                  child: Text(
                                    '${metric.label} ${_number(metric == WorkoutMetric.rir && set.rir == null ? null : metric.read(set))} ${metric.unit}',
                                  ),
                                )
                              : Text(
                                  '${metric.label} ${_number(metric == WorkoutMetric.rir && set.rir == null ? null : metric.read(set))} ${metric.unit}',
                                ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.md),
        ],
        if (_loading) const Center(child: CircularProgressIndicator()),
        if (_next != null && !_loading)
          OutlinedButton(
            onPressed: _busy ? null : () => _load(more: true),
            child: const Text('이전 기록 더 보기'),
          ),
      ],
    ),
  );
}

class _CorrectionReasonDialog extends StatefulWidget {
  const _CorrectionReasonDialog({
    required this.workout,
    required this.exercise,
    required this.setNumber,
    required this.metric,
    required this.before,
    required this.after,
  });
  final ManagedWorkout workout;
  final String exercise;
  final int setNumber;
  final WorkoutMetric metric;
  final double before;
  final double after;
  @override
  State<_CorrectionReasonDialog> createState() =>
      _CorrectionReasonDialogState();
}

class _CorrectionReasonDialogState extends State<_CorrectionReasonDialog> {
  final _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('기록 수정'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.exercise} ${widget.setNumber}세트'),
          Text(
            '${widget.metric.label}: ${_number(widget.before)} → ${_number(widget.after)} ${widget.metric.unit}',
          ),
          Text(
            widget.workout.requiresApproval
                ? '회원이 이 변경을 승인한 뒤 반영해요.'
                : '변경 내용과 이유가 회원에게 전달돼요. 시간이 지나면 승인 요청으로 전환될 수 있어요.',
          ),
          const SizedBox(height: SetflowSpacing.md),
          TextField(
            controller: _reason,
            maxLength: 500,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: '수정 이유'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: _reason.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _reason.text.trim()),
        child: Text(widget.workout.requiresApproval ? '승인 요청' : '수정 제출'),
      ),
    ],
  );
}
