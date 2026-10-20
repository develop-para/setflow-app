import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../data/trainer_client_repository.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/auth_gate.dart';
import '../widgets/common.dart';
import '../widgets/pro_access_gate.dart';
import '../widgets/workout_history_calendar.dart';
import 'coaching_workout_screens.dart' show CoachingAccountBoundary;
import 'trainer_client_workout_screen.dart';

TrainerClientRepository? trainerClientRepository(BuildContext context) {
  final repository = AppScope.of(context).businessRepository;
  return repository is TrainerClientRepository
      ? repository as TrainerClientRepository
      : null;
}

String _requestId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// 기존 연결 회원 목록과 함께 쓰는, 수업 예약이 필요 없는 회원 등록부.
class TrainerManagedClientsPanel extends StatelessWidget {
  const TrainerManagedClientsPanel({
    this.query = '',
    this.refreshRevision = 0,
    super.key,
  });
  final String query;
  final int refreshRevision;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (state.role != UserRole.trainer) return const SizedBox.shrink();
    return _ClientsPanel(
      key: ValueKey(
        '${Auth.instance.currentUser?.id ?? state.businessAccess?.userId}:$refreshRevision',
      ),
      query: query,
    );
  }
}

class _ClientsPanel extends StatefulWidget {
  const _ClientsPanel({required this.query, super.key});
  final String query;
  @override
  State<_ClientsPanel> createState() => _ClientsPanelState();
}

class _ClientsPanelState extends State<_ClientsPanel> {
  List<TrainerManagedClient> _clients = [];
  bool _loading = true;
  bool _failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_generation;
    setState(() => _loading = true);
    try {
      final clients = await trainerClientRepository(
        context,
      )!.listTrainerClients();
      if (!mounted || generation != _generation) return;
      setState(() {
        _clients = clients;
        _failed = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _clients = [];
          _failed = true;
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open([TrainerManagedClient? client]) async {
    if (!await requireProAccess(context) || !mounted) return;
    if (client == null) {
      client = await Navigator.of(context).push<TrainerManagedClient>(
        MaterialPageRoute(builder: (_) => const TrainerClientFormScreen()),
      );
      if (!mounted || client == null) return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TrainerManagedClientScreen(client: client!),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.query.trim();
    final phoneQuery = query.replaceAll(RegExp(r'[\s-]'), '');
    final visible = _clients.where(
      (client) =>
          client.name.contains(query) ||
          (phoneQuery.isNotEmpty &&
              client.phone
                  .replaceAll(RegExp(r'[\s-]'), '')
                  .contains(phoneQuery)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: SetflowSpacing.md),
        FilledButton.icon(
          key: const ValueKey('trainer-add-managed-client'),
          onPressed: () => _open(),
          icon: const Icon(SetflowIcons.signUp),
          label: const Text('회원 등록'),
        ),
        const SizedBox(height: SetflowSpacing.sm),
        Text(
          '앱 가입·수업 예약 없이 이름과 연락처로 등록하고 운동을 기록해요.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: SetflowSpacing.md),
        Row(
          children: [
            Expanded(
              child: Text(
                '직접 관리 회원 · ${_clients.length}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            IconButton(
              tooltip: '직접 관리 회원 새로고침',
              onPressed: _loading ? null : _load,
              icon: const Icon(SetflowIcons.refresh),
            ),
          ],
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_failed) ErrorState(message: '관리 회원을 불러오지 못했어요.', onRetry: _load),
        if (!_loading && !_failed && _clients.isEmpty)
          const Text('회원 등록을 눌러 첫 회원의 공간을 만들어보세요.'),
        for (final client in visible)
          ListTile(
            key: ValueKey('managed-client-${client.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text(client.name),
            subtitle: Text(
              '${client.phone} · ${client.memberUserId == null ? '앱 미연결' : '앱 연결됨'}',
            ),
            trailing: const Icon(SetflowIcons.forward),
            onTap: () => _open(client),
          ),
        const SizedBox(height: SetflowSpacing.md),
      ],
    );
  }
}

class TrainerClientFormScreen extends StatelessWidget {
  const TrainerClientFormScreen({this.client, super.key});
  final TrainerManagedClient? client;
  @override
  Widget build(BuildContext context) => CoachingAccountBoundary(
    requiredRole: UserRole.trainer,
    child: _ClientForm(client: client),
  );
}

class _ClientForm extends StatefulWidget {
  const _ClientForm({this.client});
  final TrainerManagedClient? client;
  @override
  State<_ClientForm> createState() => _ClientFormState();
}

class _ClientFormState extends State<_ClientForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.client?.name);
  late final _phone = TextEditingController(text: widget.client?.phone);
  late final _notes = TextEditingController(text: widget.client?.notes);
  final _request = _requestId();
  bool _busy = false;
  bool _uncertain = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = trainerClientRepository(context)!;
      final client = widget.client == null
          ? await repository.createTrainerClient(
              name: _name.text.trim(),
              phone: _phone.text.trim(),
              notes: _notes.text.trim(),
              requestId: _request,
            )
          : await repository.updateTrainerClient(
              clientId: widget.client!.id,
              name: _name.text.trim(),
              phone: _phone.text.trim(),
              notes: _notes.text.trim(),
              requestId: _request,
            );
      if (mounted) Navigator.pop(context, client);
    } catch (_) {
      if (mounted) {
        setState(() {
          _uncertain = true;
          _error = '저장 결과를 확인하지 못했어요. 입력을 유지한 채 같은 내용으로 다시 시도해주세요.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.client == null ? '회원 등록' : '회원 정보 수정')),
    body: Form(
      key: _form,
      child: ListView(
        padding: SetflowInsets.pageForm,
        children: [
          AppTextField(
            key: const ValueKey('managed-client-name'),
            controller: _name,
            enabled: !_busy && !_uncertain,
            label: '회원 이름',
            validator: (value) => value == null || value.trim().isEmpty
                ? '이름을 입력해주세요.'
                : value.trim().length > 80
                ? '이름은 80자 이내로 입력해주세요.'
                : null,
          ),
          const SizedBox(height: SetflowSpacing.md),
          AppTextField(
            key: const ValueKey('managed-client-phone'),
            controller: _phone,
            enabled: !_busy && !_uncertain,
            label: '휴대폰 번호',
            keyboardType: TextInputType.phone,
            validator: (value) =>
                RegExp(
                  r'^01[016789][0-9]{7,8}$',
                ).hasMatch((value ?? '').replaceAll(RegExp(r'[\s-]'), ''))
                ? null
                : '휴대폰 번호를 확인해주세요.',
          ),
          const SizedBox(height: SetflowSpacing.md),
          AppTextField(
            key: const ValueKey('managed-client-notes'),
            controller: _notes,
            enabled: !_busy && !_uncertain,
            label: '관리 메모',
            minLines: 3,
            maxLines: 8,
            validator: (value) => (value?.trim().length ?? 0) > 10000
                ? '관리 메모는 10,000자 이내로 입력해주세요.'
                : null,
          ),
          const SizedBox(height: SetflowSpacing.md),
          const Text('관리 메모는 트레이너에게만 보여요. 이름과 번호만으로 앱 계정을 자동 연결하지 않아요.'),
          if (_error != null) ...[
            const SizedBox(height: SetflowSpacing.md),
            Text(_error!, style: TextStyle(color: context.setflowColors.error)),
          ],
          const SizedBox(height: SetflowSpacing.lg),
          FilledButton(
            key: const ValueKey('managed-client-save'),
            onPressed: _busy ? null : _save,
            child: Text(
              _busy
                  ? '저장 중…'
                  : _uncertain
                  ? '같은 내용으로 다시 저장'
                  : '저장',
            ),
          ),
        ],
      ),
    ),
  );
}

class TrainerManagedClientScreen extends StatelessWidget {
  const TrainerManagedClientScreen({required this.client, super.key});
  final TrainerManagedClient client;
  @override
  Widget build(BuildContext context) => CoachingAccountBoundary(
    requiredRole: UserRole.trainer,
    child: _ClientSpace(client: client),
  );
}

class _ClientSpace extends StatefulWidget {
  const _ClientSpace({required this.client});
  final TrainerManagedClient client;
  @override
  State<_ClientSpace> createState() => _ClientSpaceState();
}

class _ClientSpaceState extends State<_ClientSpace> {
  late TrainerManagedClient _client = widget.client;
  List<TrainerClientWorkout> _workouts = [];
  bool _loading = true;
  bool _failed = false;
  int _generation = 0;
  bool _inviting = false;
  String? _inviteRequest;
  DateTime? _inviteExpiry;
  DateTime _selected = DateUtils.dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final repository = trainerClientRepository(context)!;
      final results = await Future.wait<Object>([
        repository.listTrainerClientWorkouts(_client.id),
        repository.listTrainerClients(),
      ]);
      if (mounted && generation == _generation) {
        setState(() {
          _workouts = results[0] as List<TrainerClientWorkout>;
          _client =
              (results[1] as List<TrainerManagedClient>)
                  .where((client) => client.id == _client.id)
                  .firstOrNull ??
              _client;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _failed = true;
          _workouts = [];
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _edit() async {
    final updated = await Navigator.of(context).push<TrainerManagedClient>(
      MaterialPageRoute(
        builder: (_) => TrainerClientFormScreen(client: _client),
      ),
    );
    if (mounted && updated != null) setState(() => _client = updated);
  }

  Future<void> _record(DateTime date, [TrainerClientWorkout? workout]) async {
    await Navigator.of(context).push<TrainerClientWorkout>(
      MaterialPageRoute(
        builder: (_) => TrainerClientWorkoutScreen(
          client: _client,
          date: date,
          workout: workout,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _invite() async {
    if (_inviting) return;
    setState(() => _inviting = true);
    _inviteRequest ??= _requestId();
    _inviteExpiry ??= DateTime.now().add(const Duration(days: 7));
    try {
      final invitation = await trainerClientRepository(context)!
          .createTrainerClientInvitation(
            clientId: _client.id,
            expiresAt: _inviteExpiry!,
            requestId: _inviteRequest!,
          );
      if (!mounted) return;
      _inviteRequest = null;
      _inviteExpiry = null;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('회원 앱 연결'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_client.name}님에게 이 코드를 전달해주세요. 회원 앱의 운동 장소 및 센터 → 트레이너 관리 기록에서 수락하면 연결돼요.',
                ),
                const SizedBox(height: SetflowSpacing.md),
                SelectableText(invitation.token),
                const SizedBox(height: SetflowSpacing.sm),
                Text(
                  '${invitation.expiresAt.toLocal().month}월 ${invitation.expiresAt.toLocal().day}일까지 한 번만 사용할 수 있어요.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('닫기'),
            ),
            FilledButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: invitation.token));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('코드 복사'),
            ),
          ],
        ),
      );
    } on TrainerClientInvitationUnavailable {
      _inviteRequest = null;
      _inviteExpiry = null;
      if (mounted) {
        AppSnackbar.error(context, '이전 코드를 사용할 수 없어요. 다시 눌러 새 코드를 만들어주세요.');
      }
    } catch (_) {
      if (mounted) AppSnackbar.error(context, '연결 코드를 만들지 못했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_client.name),
      actions: [
        IconButton(
          tooltip: '회원 정보와 관리 메모 수정',
          onPressed: _edit,
          icon: const Icon(SetflowIcons.settings),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: SetflowInsets.pageList,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Text(_client.phone, style: Theme.of(context).textTheme.bodyMedium),
          if (_client.notes.isNotEmpty) ...[
            const SizedBox(height: SetflowSpacing.sm),
            Text(
              _client.notes,
              key: const ValueKey('managed-client-private-notes'),
            ),
          ],
          const SizedBox(height: SetflowSpacing.sm),
          if (!_client.canConnect)
            const Text('기존 회원 계정이 삭제되어 이 공간을 다른 계정과 연결할 수 없어요.')
          else if (_client.memberUserId == null)
            OutlinedButton.icon(
              onPressed: _inviting ? null : _invite,
              icon: const Icon(SetflowIcons.signUp),
              label: const Text('회원 앱 연결 코드'),
            )
          else
            const Text('앱 연결됨 · 회원 직접 기록과 트레이너 기록을 함께 확인해요.'),
          const SizedBox(height: SetflowSpacing.lg),
          if (_failed) ErrorState(message: '회원 기록을 불러오지 못했어요.', onRetry: _load),
          WorkoutHistoryCalendar(
            buildEmptyDates: true,
            days: _workouts
                .map(
                  (record) => WorkoutHistoryDay.workout(
                    record.session,
                    hasNotes: record.notes.isNotEmpty,
                  ),
                )
                .toList(),
            initialDate: _selected,
            loading: _loading,
            onDateSelected: (date) => _selected = date,
            onDayTapped: (date) {
              if (!_failed &&
                  !_loading &&
                  !_workouts.any(
                    (record) => DateUtils.isSameDay(record.session.date, date),
                  )) {
                _record(date);
              }
            },
            recordBuilder: (date) {
              final records = _workouts
                  .where(
                    (record) => DateUtils.isSameDay(record.session.date, date),
                  )
                  .toList();
              final editable = records
                  .where((record) => record.canEdit)
                  .firstOrNull;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final record in records) ...[
                    _WorkoutRecordCard(
                      record: record,
                      onEdit: record.canEdit
                          ? () => _record(date, record)
                          : null,
                    ),
                    const SizedBox(height: SetflowSpacing.md),
                  ],
                  if (!_loading && !_failed)
                    FilledButton.icon(
                      key: const ValueKey('managed-client-add-workout'),
                      onPressed: () => _record(date, editable),
                      icon: const Icon(SetflowIcons.record),
                      label: Text(
                        editable == null ? '이 날짜에 운동 기록' : '기록 이어서 작성',
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}

class _WorkoutRecordCard extends StatelessWidget {
  const _WorkoutRecordCard({required this.record, this.onEdit});
  final TrainerClientWorkout record;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) => SetflowCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          record.source == TrainerClientWorkoutSource.member
              ? '회원 직접 기록'
              : '트레이너 기록 · ${record.authorName}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: SetflowSpacing.sm),
        for (final exercise in record.session.exercises) ...[
          Text(
            exercise.template.name,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          for (final set in exercise.sets)
            Text(
              [
                '${set.number}세트',
                if (exercise.template.isCardio ||
                    exercise.template.isDurationHold)
                  '${set.durationSeconds}초'
                else
                  '${set.weight}kg × ${set.reps}회',
                if (exercise.template.isCardio && set.distanceKm > 0)
                  '${set.distanceKm}km',
                '휴식 ${set.restSeconds}초',
                if (set.intensityRpe > 0) 'RPE ${set.intensityRpe}',
                if (set.rir != null) 'RIR ${set.rir}',
                set.completed ? '완료' : '계획',
              ].join(' · '),
            ),
          const SizedBox(height: SetflowSpacing.sm),
        ],
        if (record.notes.isNotEmpty) Text(record.notes),
        if (onEdit != null)
          TextButton(onPressed: onEdit, child: const Text('기록 이어서 작성·수정')),
      ],
    ),
  );
}

Future<void> openMyTrainerClientRecords(BuildContext context) async {
  if (!await requireSignIn(context, reason: AuthReason.coaching) ||
      !context.mounted) {
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => const MyTrainerClientRecordsScreen()),
  );
}

List<TrainerClientWorkout> _localMemberRecords(
  Iterable<WorkoutSession> sessions,
) => [
  for (final session in sessions)
    for (final sourceId
        in session.exercises
            .map((exercise) => exercise.coachingWorkoutId)
            .toSet())
      TrainerClientWorkout(
        id: sourceId ?? 'personal:${session.date.toIso8601String()}',
        session: WorkoutSession(
          date: session.date,
          exercises: session.exercises
              .where((exercise) => exercise.coachingWorkoutId == sourceId)
              .toList(),
        ),
        notes: '',
        authorName: sourceId == null
            ? ''
            : session.exercises
                      .firstWhere(
                        (exercise) => exercise.coachingWorkoutId == sourceId,
                      )
                      .coachingAuthor ??
                  '트레이너',
        source: sourceId == null
            ? TrainerClientWorkoutSource.member
            : TrainerClientWorkoutSource.trainer,
        version: 0,
        canEdit: false,
      ),
];

class MyTrainerClientRecordsScreen extends StatelessWidget {
  const MyTrainerClientRecordsScreen({super.key});
  @override
  Widget build(BuildContext context) => const CoachingAccountBoundary(
    requiredRole: UserRole.member,
    child: _MyClientRecords(),
  );
}

class _MyClientRecords extends StatefulWidget {
  const _MyClientRecords();
  @override
  State<_MyClientRecords> createState() => _MyClientRecordsState();
}

class _MyClientRecordsState extends State<_MyClientRecords> {
  List<TrainerClientWorkout> _records = [];
  List<TrainerClientLink> _links = [];
  bool _loading = true;
  bool _failed = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final repository = trainerClientRepository(context)!;
      final results = await Future.wait<Object>([
        repository.listMyTrainerClientWorkouts(),
        repository.listMyTrainerClientLinks(),
      ]);
      if (mounted && generation == _generation) {
        setState(() {
          _records = results[0] as List<TrainerClientWorkout>;
          _links = results[1] as List<TrainerClientLink>;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _records = [];
          _links = [];
          _failed = true;
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _accept() async {
    final accepted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const CoachingAccountBoundary(
          requiredRole: UserRole.member,
          child: _ClientAcceptScreen(),
        ),
      ),
    );
    if (mounted && accepted == true) await _load();
  }

  Future<void> _end(String clientId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('연결을 해제할까요?'),
        content: const Text(
          '이 트레이너와 내 개인 운동 기록 공유를 중단합니다. 트레이너가 남긴 운동 기록은 계속 확인할 수 있어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('연결 해제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await trainerClientRepository(
        context,
      )!.endMyTrainerClientLink(clientId, requestId: _requestId());
      if (mounted) await _load();
    } catch (_) {
      if (mounted) AppSnackbar.error(context, '연결을 해제하지 못했어요. 다시 시도해주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final localRecords = _localMemberRecords(
      AppScope.of(context).sessions.values,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('트레이너 관리 기록')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: SetflowInsets.pageList,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            OutlinedButton.icon(
              key: const ValueKey('accept-managed-client-invite'),
              onPressed: _accept,
              icon: const Icon(SetflowIcons.signUp),
              label: const Text('트레이너 연결 코드 입력'),
            ),
            const SizedBox(height: SetflowSpacing.md),
            const Text('내가 직접 한 운동과 트레이너가 남긴 운동을 날짜별로 확인해요.'),
            if (_failed)
              ErrorState(message: '트레이너 기록을 불러오지 못했어요.', onRetry: _load),
            const SizedBox(height: SetflowSpacing.md),
            WorkoutHistoryCalendar(
              loading: _loading,
              days: [
                ...localRecords.map(
                  (record) => WorkoutHistoryDay.workout(record.session),
                ),
                ..._records.map(
                  (record) => WorkoutHistoryDay.workout(
                    record.session,
                    hasNotes: record.notes.isNotEmpty,
                  ),
                ),
              ],
              recordBuilder: (date) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final record in localRecords.where(
                    (item) => DateUtils.isSameDay(item.session.date, date),
                  ))
                    _WorkoutRecordCard(record: record),
                  for (final record in _records.where(
                    (item) => DateUtils.isSameDay(item.session.date, date),
                  )) ...[
                    _WorkoutRecordCard(record: record),
                    const SizedBox(height: SetflowSpacing.md),
                  ],
                ],
              ),
            ),
            const SizedBox(height: SetflowSpacing.lg),
            for (final link in _links)
              if (link.isSharing)
                TextButton(
                  key: ValueKey('end-client-link-${link.clientId}'),
                  onPressed: () => _end(link.clientId),
                  child: Text('${link.trainerName} 연결 해제'),
                )
              else
                Text('${link.trainerName} · 개인 운동 공유 중단됨'),
          ],
        ),
      ),
    );
  }
}

class _ClientAcceptScreen extends StatefulWidget {
  const _ClientAcceptScreen();
  @override
  State<_ClientAcceptScreen> createState() => _ClientAcceptScreenState();
}

class _ClientAcceptScreenState extends State<_ClientAcceptScreen> {
  final _token = TextEditingController();
  String _request = _requestId();
  bool _busy = false;
  bool _consented = false;
  bool _uncertain = false;
  String? _error;
  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    if (_busy || !_consented || _token.text.trim().isEmpty) return;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(_token.text.trim())) {
      setState(() => _error = '트레이너에게 받은 64자리 연결 코드를 확인해주세요.');
      return;
    }
    final actor = Auth.instance.currentUser?.id;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await trainerClientRepository(
        context,
      )!.acceptTrainerClientInvitation(_token.text.trim(), requestId: _request);
      if (mounted && actor == Auth.instance.currentUser?.id) {
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _uncertain = true;
          _error =
              '연결을 확인하지 못했어요. 코드가 만료되었거나 다른 회원이 사용했을 수 있어요. 같은 코드로 다시 시도해주세요.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('트레이너 연결')),
    body: ListView(
      padding: SetflowInsets.pageForm,
      children: [
        const Text('본인을 관리하는 트레이너에게 직접 받은 코드인지 확인해주세요.'),
        const SizedBox(height: SetflowSpacing.md),
        AppTextField(
          key: const ValueKey('managed-client-invite-token'),
          controller: _token,
          enabled: !_busy && !_uncertain,
          label: '연결 코드',
        ),
        const SizedBox(height: SetflowSpacing.md),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _consented,
          onChanged: _busy || _uncertain
              ? null
              : (value) => setState(() => _consented = value ?? false),
          title: const Text('기록 연결과 공유에 동의해요'),
          subtitle: const Text(
            '트레이너가 남긴 기록을 내 계정에서 보고, 내 과거·앞으로의 개인 운동 기록을 이 트레이너에게 공유합니다. 관리 메모는 공유되지 않으며 언제든 연결을 해제할 수 있어요.',
          ),
        ),
        if (_error != null)
          Text(_error!, style: TextStyle(color: context.setflowColors.error)),
        const SizedBox(height: SetflowSpacing.lg),
        FilledButton(
          key: const ValueKey('managed-client-invite-accept'),
          onPressed: _busy || !_consented ? null : _accept,
          child: Text(
            _busy
                ? '연결 중…'
                : _uncertain
                ? '같은 코드로 다시 연결'
                : '동의하고 연결',
          ),
        ),
        if (_uncertain)
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _request = _requestId();
                    _uncertain = false;
                    _consented = false;
                    _error = null;
                    _token.clear();
                  }),
            child: const Text('다른 연결 코드 입력'),
          ),
      ],
    ),
  );
}
