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
  const TogetherScreen({this.onOpenRecord, super.key});

  /// 방의 "지금 세트" 카드가 오늘 기록이 비었을 때 기록 탭으로 보내는 통로.
  /// 기록은 셸의 탭이라 push하면 바텀바 없는 사본이 열린다.
  final VoidCallback? onOpenRecord;

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('함께'),
        actions: [
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
                party: _party!,
                userId: _userId,
                busy: _busy,
                liveSet: _liveSetOfToday(AppScope.of(context)),
                onOpenRecord: widget.onOpenRecord,
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
                onModeChanged: (mode) => _run(
                  () => _repository!.setMode(partyId: _party!.id, mode: mode),
                ),
                onOfferRoutine: _offerRoutine,
                onSaveRoutine: _saveOfferedRoutine,
                onLeave: _leave,
              ),
      ),
    );
  }

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
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        SetflowSpacing.gutter,
        SetflowSpacing.sm,
        SetflowSpacing.gutter,
        SetflowSpacing.xxl2,
      ),
      children: [
        // 설명은 물음표 뒤로 갔다. 페이지가 하는 일은 둘뿐이다: 그림 한 장으로
        // "두 사람, 타이머 하나"를 보여주고, 방을 만들거나 참여하게 한다.
        Container(
          padding: const EdgeInsets.all(SetflowSpacing.xl),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [SetflowColors.inkBlockTop, SetflowColors.inkBlockBottom],
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
                              color: Colors.white.withValues(alpha: .14),
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
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: SetflowSpacing.sm2),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(SetflowRadii.full),
                      child: const LinearProgressIndicator(
                        value: .65,
                        minHeight: 5,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation(SetflowColors.brand),
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
    );
  }
}

class _PartyRoom extends StatelessWidget {
  const _PartyRoom({
    required this.party,
    required this.userId,
    required this.busy,
    required this.liveSet,
    required this.onOpenRecord,
    required this.unit,
    required this.onSetEdited,
    required this.onStart,
    required this.onSetDone,
    required this.onModeChanged,
    required this.onOfferRoutine,
    required this.onSaveRoutine,
    required this.onLeave,
  });

  final TrainingParty party;
  final String? userId;
  final bool busy;

  /// 오늘 기록에서 차례인 세트. 방은 "무슨 세트를 하는 중인가"를 기록에서
  /// 읽는다 — 여기 없는 별도 장부를 만들지 않는다.
  final (WorkoutExercise, WorkoutSetEntry)? liveSet;
  final VoidCallback? onOpenRecord;
  final String unit;
  final void Function({double? weight, int? reps, int? restSeconds})
  onSetEdited;
  final VoidCallback onStart;
  final VoidCallback onSetDone;
  final ValueChanged<PartyMode> onModeChanged;
  final VoidCallback onOfferRoutine;
  final ValueChanged<OfferedRoutine> onSaveRoutine;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = userId == null ? null : party.memberOf(userId!);
    final countdown = party.countdownSeconds;
    final myTurn =
        party.mode == PartyMode.alternating &&
        party.currentTurnUserId == userId;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        SetflowSpacing.gutter,
        SetflowSpacing.sm,
        SetflowSpacing.gutter,
        SetflowSpacing.xxl2,
      ),
      children: [
        // 맨 위는 언제나 "지금 할 일" 하나다 — 방의 상태가 곧 다음 행동이고,
        // 그게 안 보이면 기능이 있어도 뭘 해야 할지 모르는 방이 된다.
        _RoomStatusHero(
          party: party,
          userId: userId,
          countdown: countdown,
          myTurn: myTurn,
        ),
        const SizedBox(height: SetflowSpacing.lg),
        _CodeCard(code: party.code),
        const SizedBox(height: SetflowSpacing.lg),
        _ModePicker(
          mode: party.mode,
          enabled: !busy && party.isHost(userId ?? ''),
          onChanged: onModeChanged,
        ),
        const SizedBox(height: SetflowSpacing.lg),
        _Scoreboard(party: party, userId: userId),
        _LiveSetCard(
          liveSet: liveSet,
          onOpenRecord: onOpenRecord,
          unit: unit,
          onEdited: onSetEdited,
        ),
        const SizedBox(height: SetflowSpacing.lg),
        // In 교대 the button is only live on your turn: a set logged out of
        // turn would move the rotation past someone who never lifted.
        // 단, 라벨은 상태를 **정직하게** 말해야 한다 — 시작 전(차례 미정)에
        // "상대 차례예요"는 거짓말이고, 혼자 있는 방에는 상대가 없다.
        Builder(
          builder: (context) {
            final solo = party.members.length == 1;
            final turnDecided = party.currentTurnUserId != null;
            final gated =
                party.mode == PartyMode.alternating && !solo && !myTurn;
            final turnName = party.currentTurnUserId == null
                ? null
                : party.memberOf(party.currentTurnUserId!)?.displayName;
            final label = !gated
                ? (liveSet == null ? '세트 끝냈어요' : '${liveSet!.$2.number}세트 끝냈어요')
                : turnDecided
                ? '${turnName ?? '상대'}님 차례예요'
                : '같이 시작으로 순서를 정해요';
            return AppButton(
              key: const ValueKey('together-set-done'),
              label: label,
              icon: SetflowIcons.setComplete,
              isLoading: busy,
              onPressed: busy || me == null || gated ? null : onSetDone,
            );
          },
        ),
        // 각자 모드에는 같이 출발할 신호가 없다 — 락스텝 모드에서만 보인다.
        if (party.mode != PartyMode.free) ...[
          const SizedBox(height: SetflowSpacing.sm2),
          AppButton(
            key: const ValueKey('together-start'),
            label: '같이 시작',
            icon: SetflowIcons.partyStart,
            variant: AppButtonVariant.outlined,
            onPressed: busy ? null : onStart,
          ),
        ],
        const SizedBox(height: SetflowSpacing.section),
        Row(
          children: [
            Expanded(
              child: Text('주고받은 루틴', style: theme.textTheme.titleMedium),
            ),
            TextButton.icon(
              key: const ValueKey('together-offer-routine'),
              onPressed: busy ? null : onOfferRoutine,
              icon: const Icon(SetflowIcons.handOver),
              label: const Text('건네기'),
            ),
          ],
        ),
        const SizedBox(height: SetflowSpacing.sm),
        if (party.routines.isEmpty)
          Text(
            '내 루틴을 건네면 상대가 그대로 담을 수 있어요.\n상대가 나를 위해 짜준 루틴도 여기로 와요.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final offer in party.routines) ...[
            _OfferCard(
              offer: offer,
              mine: offer.senderUserId == userId,
              onSave: () => onSaveRoutine(offer),
            ),
            const SizedBox(height: SetflowSpacing.sm),
          ],
        const SizedBox(height: SetflowSpacing.section),
        AppButton(
          key: const ValueKey('together-leave'),
          label: '방 나가기',
          icon: SetflowIcons.leaveParty,
          variant: AppButtonVariant.text,
          onPressed: onLeave,
        ),
      ],
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
class _RoomStatusHero extends StatelessWidget {
  const _RoomStatusHero({
    required this.party,
    required this.userId,
    required this.countdown,
    required this.myTurn,
  });

  final TrainingParty party;
  final String? userId;
  final int countdown;
  final bool myTurn;

  (String, String) _copyOf() {
    if (party.members.length == 1) {
      return ('친구를 초대하세요', '아래 코드를 알려주면 같은 방에 들어와요');
    }
    final me = userId == null ? null : party.memberOf(userId!);
    final resting = me?.state == PartyMemberState.resting;
    if (resting && (me?.restRemainingSeconds ?? 0) > 0) {
      final left = me!.restRemainingSeconds;
      final clock =
          '${(left ~/ 60).toString().padLeft(2, '0')}:'
          '${(left % 60).toString().padLeft(2, '0')}';
      return (
        '휴식 $clock',
        switch (party.mode) {
          PartyMode.alternating => '상대가 세트를 끝내면 바로 내 차례예요',
          PartyMode.free => '내 휴식이에요 — 끝나면 다음 세트로',
          PartyMode.together => '휴식이 끝나면 같이 다음 세트로',
        },
      );
    }
    if (party.mode == PartyMode.free) {
      return ('각자 페이스로 가요', '세트를 끝내면 전광판에 올라가요 — 준비되면 바로 시작');
    }
    if (party.mode == PartyMode.alternating) {
      if (myTurn) {
        return ('내 차례예요', '세트를 마치면 아래 버튼으로 넘겨주세요');
      }
      final turnName = party.currentTurnUserId == null
          ? null
          : party.memberOf(party.currentTurnUserId!)?.displayName;
      if (turnName != null) {
        return ('$turnName님 차례', '기다리는 동안 다음 세트 무게를 맞춰두세요');
      }
    }
    if (me?.state == PartyMemberState.lifting) {
      return ('세트 중', '끝나면 아래 버튼을 눌러 같이 쉬어요');
    }
    return ('준비되면 같이 시작', '모두 모였어요 — 같이 시작을 누르세요');
  }

  @override
  Widget build(BuildContext context) {
    if (countdown > 0) {
      return _Countdown(seconds: countdown);
    }
    final (headline, detail) = _copyOf();
    return Container(
      key: const ValueKey('together-status-hero'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: SetflowSpacing.xl,
        vertical: SetflowSpacing.lg,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [SetflowColors.inkBlockTop, SetflowColors.inkBlockBottom],
        ),
        borderRadius: BorderRadius.circular(SetflowRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline,
            style: const TextStyle(
              color: Colors.white,
              fontSize: SetflowFontSize.titleLarge,
              fontWeight: FontWeight.w900,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: SetflowSpacing.xxs),
          Text(
            detail,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .68),
              fontSize: SetflowFontSize.label,
              fontWeight: SetflowWeight.medium,
            ),
          ),
        ],
      ),
    );
  }
}

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

class _ModePicker extends StatelessWidget {
  const _ModePicker({
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  final PartyMode mode;
  final bool enabled;
  final ValueChanged<PartyMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<PartyMode>(
          segments: [
            for (final value in PartyMode.values)
              ButtonSegment(value: value, label: Text(value.label)),
          ],
          selected: {mode},
          onSelectionChanged: enabled
              ? (selection) => onChanged(selection.first)
              : null,
        ),
        const SizedBox(height: SetflowSpacing.sm),
        Text(
          mode.detail,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
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

    return Column(
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
          ),
          const SizedBox(height: SetflowSpacing.sm),
        ],
        if (race)
          Padding(
            padding: const EdgeInsets.only(top: SetflowSpacing.xxs),
            child: Text(
              _raceLine(ranked),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
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

class _ScoreboardRow extends StatelessWidget {
  const _ScoreboardRow({
    required this.member,
    required this.isMe,
    required this.hasTurn,
    required this.rank,
    required this.leading,
    required this.maxSets,
  });

  final PartyMember member;
  final bool isMe;
  final bool hasTurn;

  /// 경쟁이 시작된 뒤(2명 이상, 1세트 이상)에만 순위가 있다.
  final int? rank;
  final bool leading;
  final int maxSets;

  String get _statusLabel {
    if (member.state == PartyMemberState.resting) {
      final left = member.restRemainingSeconds;
      if (left > 0) {
        return '휴식 ${(left ~/ 60).toString().padLeft(2, '0')}:'
            '${(left % 60).toString().padLeft(2, '0')}';
      }
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

    return Container(
      key: ValueKey('scoreboard-${member.userId}'),
      padding: const EdgeInsets.fromLTRB(
        SetflowSpacing.lg,
        SetflowSpacing.md2,
        SetflowSpacing.lg,
        SetflowSpacing.md,
      ),
      decoration: BoxDecoration(
        color: context.setflowColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(SetflowRadii.md),
        // 지금 들고 있는 사람이 전광판에서 빛난다.
        border: Border.all(
          color: lifting
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: lifting ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                      fontWeight: FontWeight.w900,
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
                  isMe ? '${member.displayName} (나)' : member.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                _statusLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: lifting
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: SetflowWeight.strong,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  doing == null
                      ? '아직 세트 전이에요'
                      : '$doing · ${member.currentSetNumber ?? '-'}'
                            '/${member.currentSetTotal ?? '-'}세트',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: SetflowSpacing.md),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${member.completedSets}',
                      style: const TextStyle(
                        fontSize: SetflowFontSize.title,
                        fontWeight: SetflowWeight.display,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    TextSpan(
                      text: '세트',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: SetflowWeight.strong,
                      ),
                    ),
                    if (member.totalVolume > 0)
                      TextSpan(
                        text:
                            '  ${member.totalVolume >= 1000 ? '${(member.totalVolume / 1000).toStringAsFixed(1)}t' : '${member.totalVolume.toStringAsFixed(0)}kg'}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (maxSets > 0) ...[
            const SizedBox(height: SetflowSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(SetflowRadii.xs),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: theme.colorScheme.outlineVariant,
                valueColor: AlwaysStoppedAnimation(
                  isMe
                      ? theme.colorScheme.primary
                      : context.setflowColors.disabled,
                ),
              ),
            ),
          ],
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
