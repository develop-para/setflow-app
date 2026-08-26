import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../data/together_repository.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/auth_gate.dart';
import '../widgets/common.dart';
import 'workout_screens.dart';

/// 함께 — training with someone who is not in the room with you.
///
/// The whole surface is built around one idea: the thing that makes a gym
/// partner feel present is not seeing them, it is that **your rest ends when
/// their set does**. So the room is not a chat with a timer bolted on; it is a
/// timer that two people share, and everything else is arranged around it.
class TogetherScreen extends StatefulWidget {
  const TogetherScreen({this.onOpenRecord, this.onSessionChanged, super.key});

  /// 방의 "지금 세트" 카드가 오늘 기록이 비었을 때 기록 탭으로 보내는 통로.
  /// 기록은 셸의 탭이라 push하면 바텀바 없는 사본이 열린다.
  final VoidCallback? onOpenRecord;

  /// 방에 들어가고 나옴을 셸에 알린다. 방은 운동 중 전용 화면이라 셸이
  /// 헤더와 바텀바를 접는다 — 전광판과 하단 액션이 화면을 다 써야 한다.
  final ValueChanged<bool>? onSessionChanged;

  @override
  State<TogetherScreen> createState() => _TogetherScreenState();
}

class _TogetherScreenState extends State<TogetherScreen> {
  TrainingParty? _party;
  StreamSubscription<TrainingParty>? _subscription;
  String? _error;
  bool _busy = false;

  /// Redraws the countdowns once a second, and **only while something is
  /// counting**. The values are absolute instants, so this repaints them — it
  /// never advances a clock, which is why a phone that slept for a minute comes
  /// back correct instead of a minute behind. A room sitting idle has nothing
  /// to repaint, so the ticker stops rather than rebuilding at 1Hz forever.
  Timer? _tick;

  /// 셸에 마지막으로 알린 상태. 다섯 군데의 `_party = ...` 대입마다 알림을
  /// 흩뿌리는 대신 build에서 한 번 비교한다 — 어느 경로로 들어오고 나가든
  /// 셸이 보는 값은 하나다.
  bool? _reportedSession;

  void _reportSession(bool active) {
    if (_reportedSession == active) return;
    _reportedSession = active;
    // build 도중 부모의 setState를 부르면 안 된다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSessionChanged?.call(active);
    });
  }

  TogetherRepository? get _repository =>
      AppScope.of(context).togetherRepository;

  String? get _userId => _repository?.currentUserId;

  @override
  void dispose() {
    _tick?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _watch(TrainingParty party) {
    unawaited(_subscription?.cancel());
    setState(() => _party = party);
    AppScope.of(context).setActiveTrainingParty(party.id);
    _subscription = _repository
        ?.watchParty(party.id)
        .listen(
          (next) {
            if (!mounted) return;
            _handleIncoming(next);
          },
          // 스트림이 끝났다 = 방이 사라졌거나 내가 빠졌다. 이 처리가 없으면
          // 유령 방이 화면에 남는다 — 로비로 내려가고 기억도 지운다.
          onDone: () {
            if (!mounted) return;
            AppScope.of(context).setActiveTrainingParty(null);
            setState(() => _party = null);
            _tick?.cancel();
            _tick = null;
          },
        );
    _syncTicker(party);
  }

  /// 앱을 껐다 켜도 방은 이어진다 — 저장해 둔 방이 아직 살아 있고 내가
  /// 멤버면 그대로 돌아가고, 아니면 기억을 지우고 로비를 보여준다.
  Future<void> _resumeRemembered() async {
    final state = AppScope.of(context);
    final remembered = state.activeTrainingPartyId;
    final repository = _repository;
    if (remembered == null || repository == null || _party != null) return;
    setState(() => _busy = true);
    try {
      final party = await repository.fetchParty(remembered);
      if (!mounted) return;
      if (party == null) {
        state.setActiveTrainingParty(null);
      } else {
        _watch(party);
      }
    } catch (_) {
      // 복원 실패는 로비로 두면 된다 — 코드로 다시 들어올 길이 있다.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_resumeRemembered());
    });
  }

  bool _isCounting(TrainingParty party) =>
      party.countdownSeconds > 0 ||
      party.members.any((member) => member.restRemainingSeconds > 0);

  void _syncTicker(TrainingParty party) {
    if (!_isCounting(party)) {
      _tick?.cancel();
      _tick = null;
      return;
    }
    _tick ??= Timer.periodic(const Duration(seconds: 1), (timer) {
      final current = _party;
      if (!mounted || current == null || !_isCounting(current)) {
        timer.cancel();
        _tick = null;
        return;
      }
      setState(() {});
    });
  }

  /// Mirrors the room's rest into the app's own timer.
  ///
  /// Without this the partner's set would end and nothing on this phone would
  /// happen — the shared rest has to drive the same overlay a solo rest does,
  /// or "같이 쉰다" is just a label on a card.
  void _handleIncoming(TrainingParty next) {
    final previous = _party;
    setState(() => _party = next);
    _syncTicker(next);

    final me = _userId == null ? null : next.memberOf(_userId!);
    if (me == null) return;
    final wasResting = previous?.memberOf(me.userId)?.restEndsAt;
    if (me.state == PartyMemberState.resting &&
        me.restEndsAt != null &&
        me.restEndsAt != wasResting) {
      final state = AppScope.of(context);
      final seconds = me.restRemainingSeconds;
      if (seconds > 0) state.startRestTimer(seconds);
      return;
    }
    // The turn landing on you is the one moment worth interrupting for: the
    // rest you were in is over because someone else finished lifting.
    if (me.state == PartyMemberState.lifting &&
        previous?.memberOf(me.userId)?.state == PartyMemberState.resting) {
      AppScope.of(context).cancelRestTimer();
      AppSnackbar.info(context, '내 차례예요.');
    }
  }

  Future<void> _run(Future<TrainingParty> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final party = await action();
      if (!mounted) return;
      if (_subscription == null || _party?.id != party.id) {
        _watch(party);
      } else {
        setState(() => _party = party);
        _syncTicker(party);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _messageFor(Object error) => error is TogetherFailure
      ? error.message
      : '지금은 연결이 어려워요. 잠시 후 다시 시도해주세요.';

  @override
  Widget build(BuildContext context) {
    final repository = _repository;
    final party = _party;
    final inRoom = repository != null && party != null;
    _reportSession(inRoom);
    return Scaffold(
      appBar: AppBar(
        // 방 안에서는 셸 헤더가 접히므로 이 앱바가 유일한 위쪽 크롬이다.
        // 그래서 나가는 길(기록 탭으로 접기)이 여기 있어야 한다.
        leading: inRoom && widget.onOpenRecord != null
            ? IconButton(
                key: const ValueKey('together-minimize'),
                tooltip: '기록으로 이동 (방은 그대로)',
                onPressed: widget.onOpenRecord,
                icon: const Icon(Icons.expand_more_rounded),
              )
            : null,
        title: inRoom
            ? const _LiveTitle(key: ValueKey('together-live-title'))
            : const Text('함께'),
        actions: [
          if (inRoom)
            _RoomMenu(
              key: const ValueKey('together-room-menu'),
              busy: _busy,
              onInvite: () => _showInvite(party),
              onMode: () => _showModeSheet(party),
              onRoutines: () => _showRoutinesSheet(party),
              onHelp: () => _showTogetherHelp(context),
              onLeave: _leave,
            )
          else
            IconButton(
              key: const ValueKey('together-help'),
              tooltip: '함께 운동 사용법',
              onPressed: () => _showTogetherHelp(context),
              icon: const Icon(Icons.help_outline_rounded),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: repository == null
            ? const EmptyState(
                key: ValueKey('together-unavailable'),
                icon: SetflowIcons.together,
                title: '함께 운동은 곧 열려요',
                message: '이 빌드에는 파트너 서버가 연결되어 있지 않아요.',
              )
            : _party == null
            ? _Lobby(
                busy: _busy,
                error: _error,
                onCreate: _create,
                onJoin: _join,
              )
            : _PartyRoom(
                party: party!,
                userId: _userId,
                busy: _busy,
                liveSet: _liveSetOfToday(AppScope.of(context)),
                onOpenRecord: widget.onOpenRecord,
                onInvite: () => _showInvite(party),
                onShowRoutines: () => _showRoutinesSheet(party),
                unit: AppScope.of(context).weightUnit,
                onSetEdited: ({weight, reps, restSeconds}) {
                  final live = _liveSetOfToday(AppScope.of(context));
                  if (live == null) return;
                  // updateSet이 클램프·저장·알림까지 맡는 정식 경로다.
                  AppScope.of(context).updateSet(
                    live.$2,
                    weight: weight,
                    reps: reps,
                    restSeconds: restSeconds,
                  );
                  setState(() {});
                },
                onStart: () =>
                    _run(() => _repository!.startTogether(_party!.id)),
                onSetDone: _reportSetDone,
              ),
      ),
    );
  }

  /// 초대는 사람이 없을 때만 급한 일이다. 상시 카드로 두면 이미 모인 방에서도
  /// 화면 한 칸을 계속 먹는다 — 필요할 때 여는 시트로 옮겼다.
  Future<void> _showInvite(TrainingParty party) => _sheet(
    title: '친구 초대',
    children: (sheetContext) => [
      Text(
        '이 여섯 글자를 알려주면 같은 방으로 들어와요. 한 방에 최대 6명.',
        style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
          color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: SetflowSpacing.lg),
      _CodeCard(code: party.code),
    ],
  );

  /// 운동 방식은 방을 열 때 한 번 정하고 거의 안 바꾼다. 상시 세그먼트로 두면
  /// 화면 한가운데를 늘 차지한다.
  Future<void> _showModeSheet(TrainingParty party) {
    final host = party.isHost(_userId ?? '');
    return _sheet(
      title: '운동 방식',
      children: (sheetContext) => [
        RadioGroup<PartyMode>(
          groupValue: party.mode,
          onChanged: (value) {
            Navigator.of(sheetContext).pop();
            if (value != null && value != party.mode) {
              unawaited(
                _run(
                  () => _repository!.setMode(partyId: party.id, mode: value),
                ),
              );
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final mode in PartyMode.values)
                RadioListTile<PartyMode>(
                  key: ValueKey('together-mode-${mode.name}'),
                  value: mode,
                  // 방을 만든 사람만 바꾼다 — 나머지에게는 지금 방식을
                  // 읽을 수 있게 두되 손대지 못하게 한다.
                  enabled: host,
                  title: Text(mode.label),
                  subtitle: Text(mode.detail),
                ),
            ],
          ),
        ),
        if (!host)
          Padding(
            padding: const EdgeInsets.only(top: SetflowSpacing.sm),
            child: Text(
              '운동 방식은 방을 만든 사람이 정해요.',
              style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  /// 주고받은 루틴은 화면을 차지할 만큼 자주 쓰이지 않는다. 도착하면 하단에
  /// 한 줄 배너로 알리고, 내용은 여기서 본다.
  Future<void> _showRoutinesSheet(TrainingParty party) => _sheet(
    title: '주고받은 루틴',
    children: (sheetContext) => [
      if (party.routines.isEmpty)
        Text(
          '내 루틴을 건네면 상대가 그대로 담을 수 있어요.\n'
          '상대가 나를 위해 짜준 루틴도 여기로 와요.',
          style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
            color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
          ),
        )
      else
        for (final offer in party.routines) ...[
          _OfferCard(
            offer: offer,
            mine: offer.senderUserId == _userId,
            onSave: () {
              Navigator.of(sheetContext).pop();
              unawaited(_saveOfferedRoutine(offer));
            },
          ),
          const SizedBox(height: SetflowSpacing.sm),
        ],
      const SizedBox(height: SetflowSpacing.sm),
      AppButton(
        key: const ValueKey('together-offer-routine'),
        label: '내 루틴 건네기',
        icon: SetflowIcons.handOver,
        variant: AppButtonVariant.outlined,
        onPressed: () {
          Navigator.of(sheetContext).pop();
          unawaited(_offerRoutine());
        },
      ),
    ],
  );

  /// 방의 시트 셋이 같은 껍데기를 쓴다 — 제목 하나에 내용이 붙는 형태다.
  Future<void> _sheet({
    required String title,
    required List<Widget> Function(BuildContext) children,
  }) => showSetflowSheet<void>(
    context,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(
        SetflowSpacing.gutter,
        0,
        SetflowSpacing.gutter,
        SetflowSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(sheetContext).textTheme.titleLarge),
          const SizedBox(height: SetflowSpacing.lg),
          ...children(sheetContext),
        ],
      ),
    ),
  );

  Future<void> _create() async {
    if (!await requireSignIn(context, reason: AuthReason.together)) return;
    if (!mounted) return;
    await _run(() => _repository!.createParty(mode: PartyMode.together));
  }

  Future<void> _join() async {
    if (!await requireSignIn(context, reason: AuthReason.together)) return;
    if (!mounted) return;
    final code = await _askForCode(context);
    if (code == null || !mounted) return;
    await _run(() => _repository!.joinParty(code));
  }

  /// 오늘 기록의 차례인 세트. 기록 화면과 같은 규칙이다: 각 종목에서 완료
  /// 안 된 첫 세트가 차례고, 종목은 목록 순서를 따른다.
  (WorkoutExercise, WorkoutSetEntry)? _liveSetOfToday(AppState state) {
    final session = state.sessions[state.dateOnly(DateTime.now())];
    if (session == null) return null;
    for (final exercise in session.exercises) {
      for (final set in exercise.sets) {
        if (!set.completed) return (exercise, set);
      }
    }
    return null;
  }

  /// "세트 끝냈어요"는 신호가 아니라 기록이다. 방에만 알리고 장부에 안 남으면
  /// 같은 세트를 기록 탭에서 한 번 더 밀어야 한다 — 같은 행위가 두 번이 된다.
  Future<void> _reportSetDone() async {
    final state = AppScope.of(context);
    final live = _liveSetOfToday(state);
    var rest = state.restDefaultSeconds;
    String? exerciseName;
    int? setNumber;
    int? setTotal;
    if (live != null) {
      final (exercise, set) = live;
      rest = set.restSeconds > 0 ? set.restSeconds : rest;
      exerciseName = exercise.template.name;
      setNumber = set.number;
      setTotal = exercise.sets.length;
      // 휴식은 방이 정한 공유 시각으로 시작해야 한다 — 여기서 로컬 타이머를
      // 켜면 서버 echo와 두 개가 돈다.
      await state.toggleSet(set, startRest: false);
      state.adoptActualIntoPendingSets(exercise, set);
      if (!mounted) return;
    }
    // 전광판 볼륨은 완료 반영 후의 오늘 합계다.
    final volume = state.sessions[state.dateOnly(DateTime.now())]?.volume ?? 0;
    await _run(
      () => _repository!.reportSetDone(
        partyId: _party!.id,
        restSeconds: rest,
        exerciseName: exerciseName,
        setNumber: setNumber,
        setTotal: setTotal,
        totalVolume: volume,
      ),
    );
  }

  Future<void> _offerRoutine() async {
    final state = AppScope.of(context);
    if (state.routines.isEmpty) {
      AppSnackbar.info(context, '먼저 루틴을 하나 만들어주세요.');
      return;
    }
    final routine = await showSetflowSheet<RoutineData>(
      context,
      isScrollControlled: true,
      builder: (_) => _RoutinePickerSheet(routines: state.routines),
    );
    if (routine == null || !mounted) return;
    await _run(
      () => _repository!.offerRoutine(partyId: _party!.id, routine: routine),
    );
    if (mounted) AppSnackbar.success(context, '루틴을 건넸어요.');
  }

  Future<void> _saveOfferedRoutine(OfferedRoutine offer) async {
    final state = AppScope.of(context);
    final result = state.importRoutine(offer.routine);
    if (!mounted) return;
    AppSnackbar.info(context, switch (result) {
      RoutineImportResult.imported => '${offer.routine.name}을(를) 내 루틴에 담았어요.',
      RoutineImportResult.alreadySaved => '이미 담아둔 루틴이에요.',
      RoutineImportResult.limitReached => '무료 루틴은 4개까지 담을 수 있어요.',
      RoutineImportResult.paidPlanRequired => '이용권이 필요한 루틴이에요.',
    });
  }

  Future<void> _leave() async {
    final party = _party;
    if (party == null) return;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _tick?.cancel();
    _tick = null;
    AppScope.of(context).setActiveTrainingParty(null);
    try {
      await _repository!.leaveParty(party.id);
    } catch (_) {
      // Leaving is the one action that must always appear to work: staying
      // stuck in a room you closed is worse than a stale row on the server.
    }
    if (mounted) setState(() => _party = null);
  }
}

Future<String?> _askForCode(BuildContext context) => showSetflowSheet<String>(
  context,
  isScrollControlled: true,
  builder: (_) => const _CodeSheet(),
);

/// Owns its own controller.
///
/// Disposing it from the caller's `whenComplete` looked tidier and was wrong:
/// the sheet keeps rebuilding through its exit animation, so the field would
/// reach for a controller that had already been torn down.
class _CodeSheet extends StatefulWidget {
  const _CodeSheet();

  @override
  State<_CodeSheet> createState() => _CodeSheetState();
}

class _CodeSheetState extends State<_CodeSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        SetflowSpacing.xxl,
        0,
        SetflowSpacing.xxl,
        SetflowSpacing.xxl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '초대 코드 입력',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: SetflowSpacing.lg),
          // 코드는 코드처럼 보여야 한다: 크고, 가운데, 글자 사이가 벌어진
          // 모노스페이스 느낌. 여섯 글자가 차면 그대로 참여한다 — 버튼은
          // 붙여넣기한 사람 몫이다.
          TextField(
            key: const ValueKey('together-code-input'),
            controller: _controller,
            autofocus: true,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(
              fontSize: SetflowFontSize.headline,
              fontWeight: FontWeight.w900,
              letterSpacing: 8,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            decoration: const InputDecoration(
              hintText: 'ABC123',
              counterText: '',
            ),
            maxLength: 6,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
              LengthLimitingTextInputFormatter(6),
              // Codes are handed out in caps, so typing in lower case has to
              // work rather than quietly fail to match.
              TextInputFormatter.withFunction(
                (_, next) => next.copyWith(text: next.text.toUpperCase()),
              ),
            ],
            onChanged: (value) {
              if (value.length == 6) _submit();
            },
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: SetflowSpacing.lg),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  key: const ValueKey('together-code-paste'),
                  label: '붙여넣기',
                  icon: Icons.content_paste_rounded,
                  variant: AppButtonVariant.outlined,
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    final text = data?.text?.trim().toUpperCase() ?? '';
                    final code = RegExp(
                      '[A-Z0-9]{6}',
                    ).firstMatch(text)?.group(0);
                    if (code == null || !mounted) return;
                    _controller.text = code;
                    _submit();
                  },
                ),
              ),
              const SizedBox(width: SetflowSpacing.sm),
              Expanded(
                child: AppButton(
                  key: const ValueKey('together-code-submit'),
                  label: '참여하기',
                  icon: SetflowIcons.partyJoin,
                  onPressed: _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 사용법 시트 — 설명은 페이지에 늘어놓지 않고 물음표 뒤에 둔다.
/// 처음 온 사람은 히어로의 그림으로 감을 잡고, 더 궁금하면 여기로 온다.
void _showTogetherHelp(BuildContext context) {
  showSetflowSheet<void>(
    context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          SetflowSpacing.gutter,
          0,
          SetflowSpacing.gutter,
          SetflowSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('함께 운동 사용법', style: theme.textTheme.titleLarge),
            const SizedBox(height: SetflowSpacing.lg),
            for (final (step, icon, title, detail) in const [
              (
                1,
                SetflowIcons.partyCreate,
                '방을 만들고 코드를 공유해요',
                '전화로 불러줄 수 있는 여섯 글자예요. 한 방에 최대 6명.',
              ),
              (2, SetflowIcons.partyStart, '준비되면 같이 시작', '모든 폰이 같은 카운트다운을 세요'),
              (
                3,
                SetflowIcons.setComplete,
                '세트 끝!을 누르면',
                '내 기록에 저장되고, 상대 휴식이 그 순간 끝나요',
              ),
            ]) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: sheetContext.setflowColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(SetflowRadii.sm),
                    ),
                    child: Text(
                      '$step',
                      style: const TextStyle(fontWeight: SetflowWeight.strong),
                    ),
                  ),
                  const SizedBox(width: SetflowSpacing.md),
                  Icon(
                    icon,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: SetflowSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: SetflowWeight.strong,
                            fontSize: SetflowFontSize.label,
                          ),
                        ),
                        Text(
                          detail,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SetflowSpacing.md2),
            ],
            const SizedBox(height: SetflowSpacing.xs),
            Text('두 가지 방식', style: theme.textTheme.titleMedium),
            const SizedBox(height: SetflowSpacing.sm),
            for (final mode in PartyMode.values) ...[
              Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      mode.label,
                      style: const TextStyle(fontWeight: SetflowWeight.strong),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      mode.detail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SetflowSpacing.sm),
            ],
          ],
        ),
      );
    },
  );
}

class _Lobby extends StatelessWidget {
  const _Lobby({
    required this.busy,
    required this.error,
    required this.onCreate,
    required this.onJoin,
  });

  final bool busy;
  final String? error;
  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    // 방과 같은 규칙: 들어가면 가운데, 넘치면 스크롤. 위에 붙여 두면
    // 화면 아래 절반이 빈 채로 남아 페이지가 미완성처럼 보인다.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              SetflowSpacing.gutter,
              SetflowSpacing.sm,
              SetflowSpacing.gutter,
              SetflowSpacing.xxl2,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 설명은 물음표 뒤로 갔다. 페이지가 하는 일은 둘뿐이다: 그림 한 장으로
                // "두 사람, 타이머 하나"를 보여주고, 방을 만들거나 참여하게 한다.
                Container(
                  padding: const EdgeInsets.all(SetflowSpacing.xl),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        SetflowColors.inkBlockTop,
                        SetflowColors.inkBlockBottom,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(SetflowRadii.lg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '떨어져 있어도\n같이 운동해요',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: SetflowFontSize.headline,
                          fontWeight: FontWeight.w900,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: SetflowSpacing.lg),
                      // 문장이 아니라 그림: 두 사람이 타이머 하나를 같이 쓰는 모습이
                      // 이 기능의 전부다. 단, **예시임이 한눈에 보여야 한다** —
                      // 실기기에서 "처음 들어왔는데 왜 이 상태지?"로 읽혔다.
                      // 있는 척하는 UI 금지 규칙(AGENTS 8) 그대로: 데모에는 데모 표기.
                      Container(
                        padding: const EdgeInsets.all(SetflowSpacing.md2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(SetflowRadii.md),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '예시',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: .45),
                                    fontSize: SetflowFontSize.small,
                                    fontWeight: SetflowWeight.strong,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(width: SetflowSpacing.sm),
                                for (final name in const ['나', '친구']) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: SetflowSpacing.sm2,
                                      vertical: SetflowSpacing.xxs,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: .14,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        SetflowRadii.full,
                                      ),
                                    ),
                                    child: Text(
                                      name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: SetflowFontSize.small,
                                        fontWeight: SetflowWeight.strong,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: SetflowSpacing.xs2),
                                ],
                                const Spacer(),
                                const Text(
                                  '같이 휴식 00:42',
                                  style: TextStyle(
                                    color: SetflowColors.brand,
                                    fontSize: SetflowFontSize.label,
                                    fontWeight: FontWeight.w900,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: SetflowSpacing.sm2),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(
                                SetflowRadii.full,
                              ),
                              child: const LinearProgressIndicator(
                                value: .65,
                                minHeight: 5,
                                backgroundColor: Colors.white12,
                                valueColor: AlwaysStoppedAnimation(
                                  SetflowColors.brand,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: SetflowSpacing.sm),
                      Text(
                        '두 사람, 타이머 하나 — 세트가 끝나면 같이 쉬어요.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .68),
                          fontSize: SetflowFontSize.label,
                          fontWeight: SetflowWeight.medium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: SetflowSpacing.xl),
                if (error != null) ...[
                  _Notice(message: error!),
                  const SizedBox(height: SetflowSpacing.lg),
                ],
                AppButton(
                  key: const ValueKey('together-create'),
                  label: '방 만들기',
                  icon: SetflowIcons.partyCreate,
                  isLoading: busy,
                  onPressed: busy ? null : onCreate,
                ),
                const SizedBox(height: SetflowSpacing.sm2),
                AppButton(
                  key: const ValueKey('together-join'),
                  label: '코드로 참여',
                  icon: SetflowIcons.partyJoin,
                  variant: AppButtonVariant.outlined,
                  onPressed: busy ? null : onJoin,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 방 — 전광판이 주인공인 운동 중 화면.
///
/// 예전에는 히어로·코드·모드·순위판·세트카드·버튼 둘이 **한 스크롤에 세로로**
/// 줄 서 있었다. 전부 같은 무게의 둥근 카드라 위계가 없었고, 정작 방의 전부인
/// "세트 끝냈어요"가 맨 아래에서 접혔다. 휴식 시간은 한 화면에 세 번 나왔다.
///
/// 지금은 셋으로 나뉜다 — 위에 **상태 한 줄**, 가운데 **전광판**(화면의 대부분),
/// 아래 **고정된 액션**. 스크롤은 사람이 많을 때만 생기고, 엄지가 닿는 자리의
/// 버튼은 어떤 경우에도 화면을 벗어나지 않는다. 코드·운동 방식·루틴은 늘
/// 필요한 것이 아니라서 앱바 메뉴 뒤로 갔다.
class _PartyRoom extends StatelessWidget {
  const _PartyRoom({
    required this.party,
    required this.userId,
    required this.busy,
    required this.liveSet,
    required this.onOpenRecord,
    required this.onInvite,
    required this.onShowRoutines,
    required this.unit,
    required this.onSetEdited,
    required this.onStart,
    required this.onSetDone,
  });

  final TrainingParty party;
  final String? userId;
  final bool busy;

  /// 오늘 기록에서 차례인 세트. 방은 "무슨 세트를 하는 중인가"를 기록에서
  /// 읽는다 — 여기 없는 별도 장부를 만들지 않는다.
  final (WorkoutExercise, WorkoutSetEntry)? liveSet;
  final VoidCallback? onOpenRecord;
  final VoidCallback onInvite;
  final VoidCallback onShowRoutines;
  final String unit;
  final void Function({double? weight, int? reps, int? restSeconds})
  onSetEdited;
  final VoidCallback onStart;
  final VoidCallback onSetDone;

  @override
  Widget build(BuildContext context) {
    final solo = party.members.length == 1;
    final countdown = party.countdownSeconds;
    final myTurn =
        party.mode == PartyMode.alternating &&
        party.currentTurnUserId == userId;

    return Column(
      children: [
        _LiveStatusBar(
          key: const ValueKey('together-status-hero'),
          party: party,
          userId: userId,
          countdown: countdown,
          myTurn: myTurn,
          onStart: busy ? null : onStart,
          onInvite: onInvite,
        ),
        // 전광판이 남는 높이를 전부 가져간다. 두 사람이면 스크롤이 아예 없고,
        // 여섯이면 이 안에서만 스크롤된다 — 하단 액션은 밀려나지 않는다.
        Expanded(
          child: solo
              ? _WaitingPanel(
                  key: const ValueKey('together-waiting'),
                  code: party.code,
                  onInvite: onInvite,
                )
              : _Scoreboard(party: party, userId: userId),
        ),
        if (party.routines.isNotEmpty)
          _RoutineBanner(
            key: const ValueKey('together-routine-banner'),
            count: party.routines.length,
            onTap: onShowRoutines,
          ),
        _RoomActionBar(
          party: party,
          userId: userId,
          busy: busy,
          myTurn: myTurn,
          liveSet: liveSet,
          unit: unit,
          onOpenRecord: onOpenRecord,
          onSetEdited: onSetEdited,
          onSetDone: onSetDone,
        ),
      ],
    );
  }
}

/// 앱바 제목 자리의 라이브 표시. 방 안이라는 사실이 제목 한 줄로 보인다.
class _LiveTitle extends StatelessWidget {
  const _LiveTitle({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: SetflowSpacing.sm),
        const Text('함께 운동 중'),
      ],
    );
  }
}

/// 방의 부수적인 조작들. 늘 보일 필요가 없는 것만 여기 들어온다 —
/// 초대 코드, 운동 방식, 루틴, 나가기.
class _RoomMenu extends StatelessWidget {
  const _RoomMenu({
    required this.busy,
    required this.onInvite,
    required this.onMode,
    required this.onRoutines,
    required this.onHelp,
    required this.onLeave,
    super.key,
  });

  final bool busy;
  final VoidCallback onInvite;
  final VoidCallback onMode;
  final VoidCallback onRoutines;
  final VoidCallback onHelp;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_RoomAction>(
      tooltip: '방 메뉴',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (action) {
        switch (action) {
          case _RoomAction.invite:
            onInvite();
          case _RoomAction.mode:
            onMode();
          case _RoomAction.routines:
            onRoutines();
          case _RoomAction.help:
            onHelp();
          case _RoomAction.leave:
            onLeave();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: _RoomAction.invite,
          child: ListTile(
            leading: Icon(SetflowIcons.partyJoin),
            title: Text('초대 코드'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _RoomAction.mode,
          enabled: !busy,
          child: const ListTile(
            leading: Icon(Icons.tune_rounded),
            title: Text('운동 방식'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: _RoomAction.routines,
          child: ListTile(
            leading: Icon(SetflowIcons.handOver),
            title: Text('주고받은 루틴'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: _RoomAction.help,
          child: ListTile(
            leading: Icon(Icons.help_outline_rounded),
            title: Text('사용법'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _RoomAction.leave,
          child: ListTile(
            leading: Icon(
              SetflowIcons.leaveParty,
              color: context.setflowColors.error,
            ),
            title: Text(
              '방 나가기',
              style: TextStyle(color: context.setflowColors.error),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

enum _RoomAction { invite, mode, routines, help, leave }

/// 상태는 한 줄이다.
///
/// 휴식 시간이 히어로·내 줄·상대 줄에 세 번 나오던 것을 여기 하나로 모았다.
/// 같은 숫자가 세 곳에 있으면 어느 것이 진짜인지 보는 사람이 고민하게 된다.
class _LiveStatusBar extends StatelessWidget {
  const _LiveStatusBar({
    required this.party,
    required this.userId,
    required this.countdown,
    required this.myTurn,
    required this.onStart,
    required this.onInvite,
    super.key,
  });

  final TrainingParty party;
  final String? userId;
  final int countdown;
  final bool myTurn;
  final VoidCallback? onStart;
  final VoidCallback onInvite;

  static String _clock(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
      '${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (countdown > 0) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          SetflowSpacing.gutter,
          SetflowSpacing.sm,
          SetflowSpacing.gutter,
          0,
        ),
        child: _Countdown(seconds: countdown),
      );
    }

    final me = userId == null ? null : party.memberOf(userId!);
    final rest = me?.state == PartyMemberState.resting
        ? me!.restRemainingSeconds
        : 0;
    final solo = party.members.length == 1;
    // 락스텝 모드에서 아직 아무도 세트를 올리지 않았으면 다음 행동은
    // "같이 시작"이다. 각자 모드에는 같이 출발할 신호 자체가 없다.
    final canStart =
        party.mode != PartyMode.free &&
        !solo &&
        party.members.every((member) => member.completedSets == 0);

    final (label, tone) = switch (null) {
      _ when solo => ('친구를 기다리는 중', _StatusTone.idle),
      _ when rest > 0 => (
        switch (party.mode) {
          PartyMode.together => '같이 휴식 ${_clock(rest)}',
          PartyMode.alternating => '휴식 ${_clock(rest)} · 상대 차례',
          PartyMode.free => '내 휴식 ${_clock(rest)}',
        },
        _StatusTone.resting,
      ),
      _ when myTurn => ('내 차례예요', _StatusTone.active),
      _ when me?.state == PartyMemberState.lifting => (
        '세트 중',
        _StatusTone.active,
      ),
      _
          when party.mode == PartyMode.alternating &&
              party.currentTurnUserId != null =>
        (
          '${party.memberOf(party.currentTurnUserId!)?.displayName ?? '상대'}님 차례',
          _StatusTone.idle,
        ),
      _ when party.mode == PartyMode.free => ('각자 페이스로', _StatusTone.idle),
      _ => ('준비되면 같이 시작', _StatusTone.idle),
    };

    final theme = Theme.of(context);
    final foreground = switch (tone) {
      _StatusTone.resting => theme.colorScheme.onSurface,
      _StatusTone.active => theme.colorScheme.onSurface,
      _StatusTone.idle => theme.colorScheme.onSurfaceVariant,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(
        SetflowSpacing.gutter,
        SetflowSpacing.sm,
        SetflowSpacing.md,
        SetflowSpacing.sm,
      ),
      color: tone == _StatusTone.resting
          ? context.setflowColors.surfaceContainerLow
          : Colors.transparent,
      child: Row(
        children: [
          if (tone == _StatusTone.active)
            Padding(
              padding: const EdgeInsets.only(right: SetflowSpacing.sm),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: SetflowFontSize.title,
                fontWeight: SetflowWeight.display,
                color: foreground,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          // 혼자 있는 방은 본문이 통째로 초대 화면이다 — 여기 버튼을 또 두면
          // 같은 일을 두 곳에서 시킨다.
          if (canStart)
            TextButton.icon(
              key: const ValueKey('together-start'),
              onPressed: onStart,
              icon: const Icon(SetflowIcons.partyStart, size: 18),
              label: const Text('같이 시작'),
            ),
        ],
      ),
    );
  }
}

enum _StatusTone { idle, active, resting }

/// 혼자 있는 방 — 전광판에 올릴 것이 없으니 자리를 초대가 가져간다.
class _WaitingPanel extends StatelessWidget {
  const _WaitingPanel({required this.code, required this.onInvite, super.key});

  final String code;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SetflowSpacing.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              SetflowIcons.together,
              size: 44,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: SetflowSpacing.lg),
            Text(
              '친구를 초대하세요',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SetflowSpacing.xs),
            Text(
              '이 코드를 알려주면 같은 방으로 들어와요.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SetflowSpacing.xl),
            _CodeCard(code: code),
          ],
        ),
      ),
    );
  }
}

/// 루틴이 도착했다는 사실만 한 줄로. 내용은 시트에서 본다.
class _RoutineBanner extends StatelessWidget {
  const _RoutineBanner({required this.count, required this.onTap, super.key});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SetflowSpacing.gutter,
          vertical: SetflowSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(
              SetflowIcons.handOver,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: SetflowSpacing.sm),
            Expanded(
              child: Text(
                '주고받은 루틴 $count개',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: SetflowWeight.medium,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// 엄지가 닿는 자리. 지금 세트와 그것을 끝내는 버튼만 있고, 스크롤 밖에
/// 고정돼 어떤 방 상태에서도 화면을 벗어나지 않는다.
class _RoomActionBar extends StatelessWidget {
  const _RoomActionBar({
    required this.party,
    required this.userId,
    required this.busy,
    required this.myTurn,
    required this.liveSet,
    required this.unit,
    required this.onOpenRecord,
    required this.onSetEdited,
    required this.onSetDone,
  });

  final TrainingParty party;
  final String? userId;
  final bool busy;
  final bool myTurn;
  final (WorkoutExercise, WorkoutSetEntry)? liveSet;
  final String unit;
  final VoidCallback? onOpenRecord;
  final void Function({double? weight, int? reps, int? restSeconds})
  onSetEdited;
  final VoidCallback onSetDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = userId == null ? null : party.memberOf(userId!);
    final solo = party.members.length == 1;
    // 교대에서는 자기 차례에만 눌린다 — 차례 밖의 기록은 들지도 않은 사람을
    // 지나쳐 순번을 돌린다. 다만 라벨은 상태를 정직하게 말해야 한다.
    final gated = party.mode == PartyMode.alternating && !solo && !myTurn;
    final turnName = party.currentTurnUserId == null
        ? null
        : party.memberOf(party.currentTurnUserId!)?.displayName;
    final label = !gated
        ? (liveSet == null ? '세트 끝냈어요' : '${liveSet!.$2.number}세트 끝냈어요')
        : party.currentTurnUserId != null
        ? '${turnName ?? '상대'}님 차례예요'
        : '같이 시작으로 순서를 정해요';

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            SetflowSpacing.gutter,
            SetflowSpacing.md,
            SetflowSpacing.gutter,
            SetflowSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LiveSetCard(
                liveSet: liveSet,
                onOpenRecord: onOpenRecord,
                unit: unit,
                onEdited: onSetEdited,
              ),
              const SizedBox(height: SetflowSpacing.md),
              AppButton(
                key: const ValueKey('together-set-done'),
                label: label,
                icon: SetflowIcons.setComplete,
                isLoading: busy,
                onPressed: busy || me == null || gated ? null : onSetDone,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 지금 하는 세트 — 방과 기록을 잇는 다리.
///
/// 방에서 "세트 끝냈어요"를 누르면 오늘 기록의 이 세트가 완료된다. 이 카드가
/// 없으면 버튼이 무엇을 끝내는지 화면 어디에도 없다 — 실기기 피드백 그대로
/// "뭘 해야 할지 모르겠는" 방이 된다.
class _LiveSetCard extends StatelessWidget {
  const _LiveSetCard({
    required this.liveSet,
    required this.onOpenRecord,
    required this.unit,
    required this.onEdited,
  });

  final (WorkoutExercise, WorkoutSetEntry)? liveSet;
  final VoidCallback? onOpenRecord;
  final String unit;

  /// 다이얼 적용을 상태의 정식 경로(updateSet)로 넘긴다 — 카드가 세트에
  /// 직접 쓰면 저장·클램프·알림이 다 빠진다.
  final void Function({double? weight, int? reps, int? restSeconds}) onEdited;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final live = liveSet;
    if (live == null) {
      return SetflowCard(
        key: const ValueKey('together-live-set-empty'),
        onTap: onOpenRecord,
        child: Row(
          children: [
            Icon(
              SetflowIcons.record,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: SetflowSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '오늘 기록에 운동이 없어요',
                    style: TextStyle(fontWeight: SetflowWeight.strong),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '기록 탭에서 운동을 추가하면 여기서 세트가 넘어가요.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (onOpenRecord != null)
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      );
    }

    final (exercise, set) = live;
    final total = exercise.sets.length;
    return SetflowCard(
      key: const ValueKey('together-live-set'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                exercise.template.icon,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: SetflowSpacing.md),
              Expanded(
                child: Text(
                  exercise.template.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: SetflowWeight.strong),
                ),
              ),
              Text(
                '${set.number}세트 / $total세트',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: SetflowWeight.medium,
                ),
              ),
            ],
          ),
          if (!exercise.template.isCardio) ...[
            const SizedBox(height: SetflowSpacing.md),
            // 방에서 세트 루프가 다 돌아야 한다 — 무게를 고치러 기록 탭에
            // 갔다 오는 순간 "함께"가 끊긴다. 같은 다이얼, 같은 문법이다.
            Row(
              children: [
                Expanded(
                  child: _RoomDialChip(
                    key: const ValueKey('together-dial-weight'),
                    label: '무게',
                    value: _decimal(set.weight),
                    suffix: unit,
                    onTap: () async {
                      final result = await showNumberDial(
                        context,
                        title: '무게',
                        suffix: unit,
                        initialValue: set.weight,
                        min: 0,
                        max: 999,
                        step: .5,
                      );
                      if (result == null) return;
                      onEdited(weight: result);
                    },
                  ),
                ),
                const SizedBox(width: SetflowSpacing.xs2),
                Expanded(
                  child: _RoomDialChip(
                    key: const ValueKey('together-dial-reps'),
                    label: '횟수',
                    value: '${set.reps}',
                    suffix: '회',
                    onTap: () async {
                      final result = await showNumberDial(
                        context,
                        title: '횟수',
                        suffix: '회',
                        initialValue: set.reps.toDouble(),
                        min: 0,
                        max: 100,
                        step: 1,
                      );
                      if (result == null) return;
                      onEdited(reps: result.round());
                    },
                  ),
                ),
                const SizedBox(width: SetflowSpacing.xs2),
                Expanded(
                  child: _RoomDialChip(
                    key: const ValueKey('together-dial-rest'),
                    label: '휴식',
                    value: '${set.restSeconds}',
                    suffix: '초',
                    onTap: () async {
                      final result = await showNumberDial(
                        context,
                        title: '휴식 시간',
                        suffix: '초',
                        initialValue: set.restSeconds.toDouble(),
                        min: 15,
                        max: 600,
                        step: 5,
                      );
                      if (result == null) return;
                      onEdited(restSeconds: result.round());
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _decimal(double value) =>
      value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
}

/// 기록 화면의 숫자 상자와 같은 성격: 상자가 곧 버튼이고, 다이얼의 적용이
/// 유일한 저장 지점이다.
class _RoomDialChip extends StatelessWidget {
  const _RoomDialChip({
    required this.label,
    required this.value,
    required this.suffix,
    required this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final String suffix;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '$label $value$suffix',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SetflowRadii.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SetflowSpacing.sm,
            vertical: SetflowSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: context.setflowColors.surfaceContainer,
            borderRadius: BorderRadius.circular(SetflowRadii.sm),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: value,
                      style: const TextStyle(
                        fontSize: SetflowFontSize.body,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    TextSpan(
                      text: suffix,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 방의 상태를 한 문장으로 — "지금 뭘 해야 하나"의 단 하나의 답.
///
/// 카운트다운이 있으면 그 숫자가 히어로다. 나머지 상태는 전부 문장으로
/// 갈린다: 혼자면 초대, 모두 대기면 시작, 교대면 누구 차례인지.
class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SetflowCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '초대 코드',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: SetflowSpacing.xxs),
                Text(
                  code,
                  key: const ValueKey('together-code'),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    // The code is read aloud digit by digit, so the glyphs need
                    // to line up rather than kern into each other.
                    letterSpacing: SetflowSpacing.xs,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('together-copy-code'),
            tooltip: '코드 복사',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (context.mounted) AppSnackbar.success(context, '코드를 복사했어요.');
            },
            icon: const Icon(SetflowIcons.copyCode),
          ),
        ],
      ),
    );
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SetflowCard(
      color: SetflowColors.brand,
      child: Column(
        children: [
          Text(
            '같이 시작',
            style: theme.textTheme.labelLarge?.copyWith(
              // Lime is a fill, never a text colour — the foreground on it is
              // always ink.
              color: SetflowColors.onBrand,
            ),
          ),
          const SizedBox(height: SetflowSpacing.xxs),
          Text(
            '$seconds',
            key: const ValueKey('together-countdown'),
            style: theme.textTheme.displayMedium?.copyWith(
              color: SetflowColors.onBrand,
            ),
          ),
        ],
      ),
    );
  }
}

/// 전광판. "친구가 어디까지 했나"가 한눈에 — 세트 수로 순위를 매기고,
/// 각자 지금 무슨 종목의 몇 세트째인지와 오늘 볼륨을 같이 적는다.
///
/// 경쟁은 세트 수 하나로만 잰다. 볼륨은 체급 따라 다르니 참고 숫자로 두고,
/// 순위 배지는 실제로 앞선 사람(동률 제외)에게만 붙는다.
/// 전광판 — 이 화면의 주인공.
///
/// 예전에는 다른 카드들 사이에 낀 목록이었다. 이제 남는 높이를 전부 쓰므로
/// 숫자가 커도 되고, 그래야 방을 흘깃 봤을 때 "누가 얼마나 앞서 있나"가
/// 한 번에 읽힌다. 순위는 세트 수로만 매긴다 — 볼륨은 체급이 다르면
/// 비교가 성립하지 않아 참고 숫자로만 둔다.
class _Scoreboard extends StatelessWidget {
  const _Scoreboard({required this.party, required this.userId});

  final TrainingParty party;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ranked = party.members.toList()
      ..sort((a, b) {
        final bySets = b.completedSets.compareTo(a.completedSets);
        return bySets != 0 ? bySets : a.turnOrder.compareTo(b.turnOrder);
      });
    final maxSets = ranked.isEmpty ? 0 : ranked.first.completedSets;
    final race = party.members.length > 1 && maxSets > 0;

    // 전광판은 남는 높이를 나눠 갖는다. 두 명이면 줄이 커지고, 여섯이면
    // 줄이 낮아지다 넘치는 순간부터 스크롤된다 — 위에 붙여 두면 두 명짜리
    // 방에서 화면 절반이 빈 채로 남는다.
    return LayoutBuilder(
      builder: (context, constraints) {
        final gaps = SetflowSpacing.sm2 * ranked.length + (race ? 28.0 : 0);
        final rowHeight =
            ((constraints.maxHeight - gaps - SetflowSpacing.lg) /
                    (ranked.isEmpty ? 1 : ranked.length))
                // 상한이 없으면 두 명짜리 방에서 카드 한 장이 208까지 늘어나 안쪽이
                // 헐렁해진다. 남는 높이는 카드를 늘리는 대신 전광판째로 가운데 둔다.
                .clamp(116.0, 150.0);
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                SetflowSpacing.gutter,
                SetflowSpacing.sm,
                SetflowSpacing.gutter,
                SetflowSpacing.md,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final (index, member) in ranked.indexed) ...[
                    _ScoreboardRow(
                      member: member,
                      isMe: member.userId == userId,
                      hasTurn:
                          party.mode == PartyMode.alternating &&
                          party.currentTurnUserId == member.userId,
                      rank: race ? index + 1 : null,
                      leading:
                          race &&
                          index == 0 &&
                          (ranked.length < 2 ||
                              ranked[1].completedSets < member.completedSets),
                      maxSets: maxSets,
                      sharedRest: party.mode == PartyMode.together,
                      minHeight: rowHeight,
                    ),
                    const SizedBox(height: SetflowSpacing.sm2),
                  ],
                  if (race)
                    Padding(
                      padding: const EdgeInsets.only(top: SetflowSpacing.xxs),
                      child: Text(
                        _raceLine(ranked),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: SetflowWeight.medium,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 전광판 아래 한 줄 — 격차가 곧 응원이다.
  String _raceLine(List<PartyMember> ranked) {
    if (ranked.length < 2) return '';
    final gap = ranked[0].completedSets - ranked[1].completedSets;
    if (gap == 0) return '동률이에요 — 다음 세트가 승부처';
    final chasing = ranked[1].userId == userId;
    return chasing
        ? '${ranked[0].displayName}님이 $gap세트 앞서요 — 따라잡아요!'
        : '${ranked[0].displayName}님이 $gap세트 앞서는 중';
  }
}

/// 전광판 한 줄.
///
/// 세트 수가 이 줄에서 가장 큰 글자다(`SetflowWeight.display`가 허용되는
/// "화면에서 가장 큰 숫자"의 자리). 휴식 시간은 여기 적지 않는다 — 상단 상태
/// 줄에 이미 있고, 같은 숫자가 두 곳에 있으면 어느 쪽이 진짜인지 고민하게
/// 된다. 남의 상태는 점 하나와 짧은 말로 충분하다.
class _ScoreboardRow extends StatelessWidget {
  const _ScoreboardRow({
    required this.member,
    required this.isMe,
    required this.hasTurn,
    required this.rank,
    required this.leading,
    required this.maxSets,
    required this.sharedRest,
    required this.minHeight,
  });

  final PartyMember member;
  final bool isMe;
  final bool hasTurn;

  /// 경쟁이 시작된 뒤(2명 이상, 1세트 이상)에만 순위가 있다.
  final int? rank;
  final bool leading;
  final int maxSets;

  /// '같이' 모드에서는 모두가 같은 시계로 쉬므로 상단 상태 줄이 이미 말했다.
  final bool sharedRest;

  /// 전광판이 나눠 준 높이. 줄이 이만큼은 차지해야 두 명짜리 방이 비어
  /// 보이지 않는다.
  final double minHeight;

  String? get _statusLabel {
    if (member.state == PartyMemberState.resting) {
      return sharedRest ? null : '휴식';
    }
    if (member.state == PartyMemberState.lifting) return '세트 중';
    if (hasTurn) return '차례';
    return '대기';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lifting = member.state == PartyMemberState.lifting;
    final doing = member.currentExercise;
    final progress = maxSets <= 0
        ? 0.0
        : (member.completedSets / maxSets).clamp(0.0, 1.0);
    final volume = member.totalVolume >= 1000
        ? '${(member.totalVolume / 1000).toStringAsFixed(1)}t'
        : '${member.totalVolume.toStringAsFixed(0)}kg';

    return Container(
      key: ValueKey('scoreboard-${member.userId}'),
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.fromLTRB(
        SetflowSpacing.lg,
        SetflowSpacing.md2,
        SetflowSpacing.lg,
        SetflowSpacing.md2,
      ),
      decoration: BoxDecoration(
        // 나는 늘 옅게 도드라지고, 지금 들고 있는 사람이 전광판에서 빛난다.
        color: isMe
            ? context.setflowColors.surfaceContainerLow
            : Colors.transparent,
        borderRadius: BorderRadius.circular(SetflowRadii.lg),
        border: Border.all(
          color: lifting
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: lifting ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (leading) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SetflowSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(SetflowRadii.full),
                  ),
                  child: Text(
                    '1위',
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontSize: SetflowFontSize.small,
                      fontWeight: SetflowWeight.display,
                    ),
                  ),
                ),
                const SizedBox(width: SetflowSpacing.sm),
              ] else if (rank != null) ...[
                Text(
                  '$rank위',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: SetflowWeight.strong,
                  ),
                ),
                const SizedBox(width: SetflowSpacing.sm),
              ],
              Expanded(
                child: Text(
                  isMe && member.displayName != '나'
                      ? '${member.displayName} (나)'
                      : member.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: SetflowWeight.strong,
                    fontSize: SetflowFontSize.label,
                  ),
                ),
              ),
              if (lifting)
                Padding(
                  padding: const EdgeInsets.only(right: SetflowSpacing.xs),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              if (_statusLabel case final status?)
                Text(
                  status,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: lifting
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: SetflowWeight.strong,
                  ),
                ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 흘깃 봤을 때 읽히는 숫자는 이것 하나다.
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${member.completedSets}',
                      style: const TextStyle(
                        fontSize: SetflowFontSize.display,
                        fontWeight: SetflowWeight.display,
                        height: 1,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    TextSpan(
                      text: ' 세트',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: SetflowWeight.strong,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SetflowSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      doing == null
                          ? '아직 세트 전이에요'
                          : '$doing · ${member.currentSetNumber ?? '-'}'
                                '/${member.currentSetTotal ?? '-'}세트',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (member.totalVolume > 0)
                      Text(
                        volume,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (maxSets > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(SetflowRadii.xs),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: theme.colorScheme.outlineVariant,
                valueColor: AlwaysStoppedAnimation(
                  isMe
                      ? theme.colorScheme.primary
                      : context.setflowColors.disabled,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.offer,
    required this.mine,
    required this.onSave,
  });

  final OfferedRoutine offer;
  final bool mine;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SetflowCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(offer.routine.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: SetflowSpacing.xxs),
                Text(
                  mine ? '내가 건넨 루틴' : '${offer.senderName}이(가) 건넨 루틴',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Your own routine is already in your list; offering it back to
          // yourself would only make a duplicate.
          if (!mine)
            TextButton(
              key: ValueKey('together-save-${offer.id}'),
              onPressed: onSave,
              child: const Text('담기'),
            ),
        ],
      ),
    );
  }
}

class _RoutinePickerSheet extends StatelessWidget {
  const _RoutinePickerSheet({required this.routines});

  final List<RoutineData> routines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SetflowSpacing.xxl),
            child: Text('건넬 루틴 고르기', style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: SetflowSpacing.md),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: routines.length,
              itemBuilder: (_, index) {
                final routine = routines[index];
                return ListTile(
                  key: ValueKey('together-pick-${routine.id}'),
                  title: Text(routine.name),
                  subtitle: Text('${routine.exercises.length}개 종목'),
                  trailing: const Icon(SetflowIcons.forward),
                  onTap: () => Navigator.of(context).pop(routine),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.setflowColors;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(SetflowSpacing.md),
        decoration: BoxDecoration(
          color: colors.error.withValues(alpha: .08),
          border: Border.all(color: colors.error.withValues(alpha: .24)),
          borderRadius: BorderRadius.circular(SetflowRadii.md),
        ),
        child: Row(
          children: [
            Icon(
              SetflowIcons.error,
              color: colors.error,
              size: SetflowSpacing.xl,
            ),
            const SizedBox(width: SetflowSpacing.sm),
            Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}
