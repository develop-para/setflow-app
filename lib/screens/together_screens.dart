import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../data/together_repository.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/auth_gate.dart';
import '../widgets/coach_marks.dart';
import '../widgets/common.dart';
import '../widgets/dot_matrix.dart';
import 'workout_screens.dart';

/// 함께 — training with someone who is not in the room with you.
///
/// The whole surface is built around one idea: the thing that makes a gym
/// partner feel present is not seeing them, it is that **your rest ends when
/// their set does**. So the room is not a chat with a timer bolted on; it is a
/// timer that two people share, and everything else is arranged around it.
/// 함께 탭은 앱 테마를 따른다. 검은 것은 **전광판 판 하나**뿐이다(`widgets/dot_matrix.dart`
/// — 경기장 전광판은 낮에도 하얗게 변하지 않는다). 한때 탭 전체를 다크 테마로 감싸
/// "아레나"로 만들었다가(07239fe) 되돌렸다: 설정한 테마를 탭 하나만 무시하는 것이
/// 게임판 느낌보다 더 튀었다. 로비·시트·다이얼로그는 다른 탭과 같은 면 위에 있고,
/// 판이 그 위에 검게 놓인다.
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

  /// 화면 안내(코치마크)가 비출 자리들. 방의 세 덩어리 + 앱바 메뉴.
  final _statusKey = GlobalKey(debugLabel: 'together-guide-status');
  final _boardKey = GlobalKey(debugLabel: 'together-guide-board');
  final _actionKey = GlobalKey(debugLabel: 'together-guide-action');
  final _menuKey = GlobalKey(debugLabel: 'together-guide-menu');
  final _codeKey = GlobalKey(debugLabel: 'together-guide-code');

  /// 처음 방에 들어온 그 프레임에 안내를 한 번만 예약한다. 본 적 있으면
  /// (`hasSeenTogetherGuide`) 자동으로는 다시 안 뜨고 메뉴 '사용법'으로만 본다.
  bool _guideScheduled = false;

  /// 로비의 "근처 공개방" 구역이 지금 보여줄 것.
  _NearbyStatus _nearby = const _NearbyIdle();

  /// 근처 공개방을 불러온다. [request]가 false면 이미 허용된 사람만 — 탭을
  /// 열 때마다 권한 창이 뜨면 그게 곧 귀찮음이다. 버튼을 누른 사람에게만 묻는다.
  Future<void> _loadNearby({bool request = false}) async {
    final repository = _repository;
    if (repository == null || !Location.instance.isAvailable) return;
    if (repository.currentUserId == null) {
      if (mounted) setState(() => _nearby = const _NearbySignedOut());
      return;
    }
    if (!request && !await Location.instance.isGranted()) {
      if (mounted) setState(() => _nearby = const _NearbyNeedsLocation());
      return;
    }
    if (mounted) setState(() => _nearby = const _NearbyLoading());
    final result = await Location.instance.current();
    if (!mounted) return;
    switch (result) {
      case LocationFix(:final point):
        try {
          final rooms = await repository.listNearbyParties(point);
          if (mounted) setState(() => _nearby = _NearbyRooms(rooms));
        } catch (error) {
          if (mounted) {
            setState(() => _nearby = _NearbyFailed(_messageFor(error)));
          }
        }
      case LocationDenied(:final permanently):
        setState(
          () => _nearby = _NearbyNeedsLocation(permanently: permanently),
        );
      case LocationUnavailable():
        setState(() => _nearby = const _NearbyNeedsLocation(servicesOff: true));
    }
  }

  /// 공개방을 열거나 공개로 바꿀 때 필요한 좌표. 못 읽으면 null — 호출자가
  /// "비밀방으로 열었어요"라고 말한다.
  Future<GeoPoint?> _fixForPublic() async {
    final result = await Location.instance.current();
    return switch (result) {
      LocationFix(:final point) => point,
      _ => null,
    };
  }

  /// 게임의 첫 판처럼 — 딤을 깔고 버튼마다 비추며 설명한다. 텍스트 시트는
  /// 읽고 나면 화면과 이어지지 않았다는 실기기 피드백에서 왔다.
  Future<void> _showGuide() async {
    final party = _party;
    if (party == null) return;
    final solo = party.members.length == 1;
    final mode = party.mode;
    await showCoachMarks(
      context,
      steps: [
        CoachStep(
          target: solo ? _codeKey : _boardKey,
          title: solo
              ? (party.isPublic ? '근처 사람이 들어올 수 있어요' : '먼저 친구를 초대하세요')
              : '전광판',
          body: solo
              ? (party.isPublic
                    ? '근처에서 함께 탭을 연 사람에게 이 방이 보여요. 이 여섯 글자로 친구를 불러도 돼요.'
                    : '이 여섯 글자를 알려주면 같은 방으로 들어와요. 한 방에 최대 6명.')
              : '누가 몇 세트 했는지, 지금 누구 차례인지 여기서 봐요.',
        ),
        CoachStep(
          target: _statusKey,
          title: '지금 할 일은 이 한 줄',
          body: solo
              ? '친구가 들어오면 여기에 "같이 시작"이 떠요. 휴식이 돌 땐 남은 시간이 여기 보여요.'
              : '"같이 시작"을 누르면 모든 폰이 같은 카운트다운을 세요. 휴식이 돌 땐 남은 시간이 여기 보여요.',
        ),
        CoachStep(
          target: _actionKey,
          title: '세트를 끝내면 여기서',
          body: '오늘 기록의 세트가 저장되고 방에도 알려져요. 기록에 운동이 없으면 먼저 추가해요.',
        ),
        CoachStep(
          target: _menuKey,
          title: '지금 종목은 "${mode.label}"',
          body: '${mode.detail} 종목 바꾸기·공개 여부·친구 초대·나가기는 이 메뉴에 있어요.',
        ),
      ],
    );
    if (mounted) AppScope.of(context).markTogetherGuideSeen();
  }

  /// Redraws the countdowns once a second, and **only while something is
  /// counting**. The values are absolute instants, so this repaints them — it
  /// never advances a clock, which is why a phone that slept for a minute comes
  /// back correct instead of a minute behind. A room sitting idle has nothing
  /// to repaint, so the ticker stops rather than rebuilding at 1Hz forever.
  Timer? _tick;

  /// 방을 **접어 둔** 상태 — 방은 살아 있고 구독도 그대로인데 화면은 로비다.
  /// 방의 ←와 시스템 뒤로가기가 여기로 온다. 뒤로가기는 함께 탭 **안**에서
  /// 끝나야 한다: 예전엔 기록 탭으로 보냈는데, 기록에서 운동을 추가하고
  /// 돌아와 "함께 목록"으로 가려던 사람이 다시 기록에 떨어졌다("뒤로가기가
  /// 좀 이상해"). 로비 맨 위의 배너가 방으로 되돌아가는 길이다.
  bool _minimized = false;

  /// 로비에서 고른 종목. 하단의 하나뿐인 행동("헬스 방 만들기")이 이걸 따른다.
  PartyMode _lobbyMode = PartyMode.defaultMode;

  /// 초대 링크의 코드로 참여하는 중 — 기억해 둔 방 복원이 이 위에 덮어쓰지
  /// 않게 막는다(둘 다 첫 프레임 뒤에 시작해서 순서가 없다).
  bool _joiningFromLink = false;

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
    setState(() {
      _party = party;
      _minimized = false;
    });
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
            setState(() {
              _party = null;
              _minimized = false;
            });
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
    if (remembered == null ||
        repository == null ||
        _party != null ||
        _joiningFromLink) {
      return;
    }
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
      if (!mounted) return;
      unawaited(_resumeRemembered());
      // 위치는 함께 탭에 들어온 순간 묻는다 — "버튼을 눌러야 보인다"가 아니라
      // 탭이 곧 근처 방 목록이다. 거절한 사람에게는 안내와 버튼이 남는다.
      unawaited(_loadNearby(request: true));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    final code = state.pendingTogetherJoinCode;
    if (code == null || _repository == null || _joiningFromLink) return;
    _joiningFromLink = true;
    // 지우는 것도 notify라 build 중에는 못 부른다 — 프레임 뒤로.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      state.clearPendingTogetherJoinCode();
      unawaited(_joinFromLink(code));
    });
  }

  /// 초대 링크로 들어왔다. 이미 그 방이면 펼치기만 하고, 다른 방에 있었으면
  /// 나가고 들어간다 — 링크를 누른 사람의 뜻은 "그 방"이다.
  Future<void> _joinFromLink(String code) async {
    try {
      if (_party?.code == code) {
        if (_minimized) setState(() => _minimized = false);
        return;
      }
      if (!await requireSignIn(context, reason: AuthReason.together)) return;
      if (!mounted) return;
      await _leaveCurrentRoom();
      if (!mounted) return;
      await _run(() => _repository!.joinParty(code));
    } finally {
      _joiningFromLink = false;
    }
  }

  /// 로비로 접어 둔 방이 있는 채로 다른 방에 들어가면 먼저 나간다 — 한 사람이
  /// 두 방에 있을 수 없고, 서버에 유령 멤버를 남기지 않는다.
  Future<void> _leaveCurrentRoom() async {
    if (_party != null) await _leave();
  }

  void _minimizeRoom() {
    if (_party == null || _minimized) return;
    setState(() => _minimized = true);
    // 로비로 내려왔으니 목록을 새로 본다.
    unawaited(_loadNearby());
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
    final inRoom = repository != null && party != null && !_minimized;
    final showLobby = repository != null && !inRoom;
    _reportSession(inRoom);
    // 안내는 **빈 시간에만** 끼어든다. 방을 만들고 친구를 기다리는 사이는 빈
    // 시간이지만, 이미 카운트다운이 돌거나 세트가 오간 방에 참가한 사람은
    // 지금 당장 들어야 한다 — 그 앞에 딤을 깔면 운동을 방해하는 팝업이다.
    // 그런 사람은 메뉴의 '사용법'로 원할 때 본다.
    final idle =
        party != null &&
        party.startsAt == null &&
        party.members.every((member) => member.completedSets == 0);
    if (inRoom &&
        idle &&
        !_guideScheduled &&
        !AppScope.of(context).hasSeenTogetherGuide) {
      _guideScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _party != null) unawaited(_showGuide());
      });
    }
    // 시스템 뒤로가기도 앱바의 ←와 같다: 방은 그대로 두고 로비로 접는다. 안
    // 잡으면 셸 루트라 앱이 통째로 내려간다 — "뒤로가기도 없어 보이는데".
    final canGoBack = inRoom;
    return PopScope(
      canPop: !canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && canGoBack) _minimizeRoom();
      },
      child: Scaffold(
        appBar: AppBar(
          // 방 안에서는 셸 헤더가 접히므로 이 앱바가 유일한 위쪽 크롬이다.
          // 그래서 나가는 길(로비로 접기)이 여기 있어야 한다.
          // "방에 들어오면 다시 나갈 수는 없나?" — 접힌 셸에서 나가는 길이
          // 아래 화살표 하나였다. 뒤로가기는 뒤로가기처럼 생겨야 하고, 방 나가기는
          // 메뉴 속이 아니라 보이는 자리에 있어야 한다.
          leading: canGoBack
              ? IconButton(
                  key: const ValueKey('together-minimize'),
                  tooltip: '목록으로 (방은 유지)',
                  onPressed: _minimizeRoom,
                  icon: const Icon(Icons.arrow_back_rounded),
                )
              : null,
          // "함께 운동 중"과 전광판의 LIVE가 같은 말을 두 번 했다. 제목은 방이
          // 무엇인지 — 방식과 인원 — 만 말한다.
          title: Text(switch ((
            inRoom,
            party?.isPublic ?? false,
            party?.members.length ?? 0,
          )) {
            (false, _, _) => '함께',
            (true, true, 1) => '공개방 · 대기 중',
            (true, false, 1) => '함께',
            (true, final public, final n) =>
              '${public ? '공개 · ' : ''}${party!.mode.label} · $n명',
          }, key: const ValueKey('together-title')),
          actions: [
            // 헤더는 ← / 제목 / ⋮ 셋이다. 나가기는 메뉴 맨 아래 — 더보기 옆에
            // 나가기 아이콘을 나란히 두는 헤더는 없다("버튼이 있다고 막 배치하지
            // 말고"). 뒤로가기가 제대로 되는 지금, 출구는 그걸로 충분하다.
            if (inRoom)
              KeyedSubtree(
                key: _menuKey,
                child: _RoomMenu(
                  key: const ValueKey('together-room-menu'),
                  busy: _busy,
                  onInvite: () => _showInvite(party),
                  onMode: () => _showModeSheet(party),
                  onRoutines: () => _showRoutinesSheet(party),
                  onHelp: () => unawaited(_showGuide()),
                  onLeave: _confirmLeave,
                ),
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
        // 로비의 두 행동은 엄지 자리에 고정한다 — 목록이 길어져도 "방 만들기"가
        // 스크롤 밑으로 사라지지 않는다. 셸 바텀바가 그 아래 있으니 인셋은 셸이 진다.
        bottomNavigationBar: showLobby
            ? _LobbyActions(
                mode: _lobbyMode,
                busy: _busy,
                onCreate: () => unawaited(_create(initialMode: _lobbyMode)),
              )
            : null,
        body: SafeArea(
          top: false,
          child: repository == null
              ? const EmptyState(
                  key: ValueKey('together-unavailable'),
                  icon: SetflowIcons.together,
                  title: '함께 운동은 곧 열려요',
                  message: '이 빌드에는 파트너 서버가 연결되어 있지 않아요.',
                )
              : _party == null || _minimized
              ? _Lobby(
                  busy: _busy,
                  error: _error,
                  activeParty: party,
                  onResume: () => setState(() => _minimized = false),
                  nearby: _nearby,
                  locationAvailable: Location.instance.isAvailable,
                  selectedMode: _lobbyMode,
                  onSelectMode: (mode) => setState(() => _lobbyMode = mode),
                  todaySets: _todaySets(AppScope.of(context)),
                  onJoin: _join,
                  onJoinNearby: _joinNearby,
                  onLoadNearby: () => _loadNearby(request: true),
                  onRefreshNearby: _loadNearby,
                  onOpenLocationSettings: Location.instance.openSettings,
                  onSignIn: () async {
                    if (await requireSignIn(
                      context,
                      reason: AuthReason.together,
                    )) {
                      unawaited(_loadNearby());
                    }
                  },
                )
              : _PartyRoom(
                  party: party!,
                  userId: _userId,
                  busy: _busy,
                  statusKey: _statusKey,
                  boardKey: _boardKey,
                  actionKey: _actionKey,
                  codeKey: _codeKey,
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
      ),
    );
  }

  /// 초대는 사람이 없을 때만 급한 일이다. 상시 카드로 두면 이미 모인 방에서도
  /// 화면 한 칸을 계속 먹는다 — 필요할 때 여는 시트로 옮겼다.
  Future<void> _showInvite(TrainingParty party) => _sheet(
    title: '친구 초대',
    children: (sheetContext) => [
      Text(
        '링크를 보내면 누르는 순간 이 방으로 들어와요. 링크가 안 열리는 곳에서는 여섯 글자를 쳐도 돼요. 한 방에 최대 6명.',
        style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
          color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: SetflowSpacing.lg),
      AppButton(
        key: const ValueKey('together-share-link'),
        label: '초대 링크 보내기',
        icon: SetflowIcons.shareInvite,
        onPressed: () => _shareInvite(sheetContext, party),
      ),
      const SizedBox(height: SetflowSpacing.md),
      _CodeCard(code: party.code),
    ],
  );

  /// 링크와 코드를 같이 보낸다 — 링크는 한 번에 들어오는 길이고, 코드는
  /// 링크를 못 여는 곳(PC·다른 메신저)에서의 예비다. 링크가 어디에 착지하는지는
  /// 레포지토리가 정한다(운영은 https 페이지, 메모리는 스킴).
  Future<void> _shareInvite(BuildContext context, TrainingParty party) async {
    final box = context.findRenderObject() as RenderBox?;
    await Share.share(
      'Setflow에서 ${party.mode.label} 함께 해요.\n'
      '${_repository!.inviteLink(party.code)}\n'
      '초대 코드: ${party.code}',
      subject: 'Setflow 함께 운동 초대',
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    );
  }

  /// 운동 방식은 방을 열 때 한 번 정하고 거의 안 바꾼다. 상시 세그먼트로 두면
  /// 화면 한가운데를 늘 차지한다.
  Future<void> _showModeSheet(TrainingParty party) {
    final host = party.isHost(_userId ?? '');
    return _sheet(
      title: '종목과 공개 여부',
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
                  subtitle: Text('${mode.detail}\n${mode.when}'),
                  isThreeLine: true,
                ),
            ],
          ),
        ),
        const SizedBox(height: SetflowSpacing.md),
        Text(
          '누가 들어올 수 있나요',
          style: Theme.of(sheetContext).textTheme.titleMedium,
        ),
        RadioGroup<PartyVisibility>(
          groupValue: party.visibility,
          onChanged: (value) {
            Navigator.of(sheetContext).pop();
            if (value != null && value != party.visibility) {
              unawaited(_setVisibility(party, value));
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final visibility in PartyVisibility.values)
                RadioListTile<PartyVisibility>(
                  key: ValueKey('together-visibility-${visibility.name}'),
                  value: visibility,
                  enabled: host,
                  title: Text(visibility.label),
                  subtitle: Text(visibility.detail),
                ),
            ],
          ),
        ),
        if (!host)
          Padding(
            padding: const EdgeInsets.only(top: SetflowSpacing.sm),
            child: Text(
              '종목과 공개 여부는 방을 만든 사람이 정해요.',
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
    builder: (sheetContext) => Builder(
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
    ),
  );

  /// 오늘 기록의 세트 수 — 로비 티커에 올라간다. 방은 이 세트를 전광판에 센다.
  int _todaySets(AppState state) =>
      state.sessions[state.dateOnly(DateTime.now())]?.totalSets ?? 0;

  /// [initialMode]가 있으면 로비의 종목 카드에서 왔다 — 시트가 그 종목으로 열린다.
  Future<void> _create({PartyMode? initialMode}) async {
    if (!await requireSignIn(context, reason: AuthReason.together)) return;
    if (!mounted) return;
    final choice = await showSetflowSheet<(PartyVisibility, PartyMode)>(
      context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CreateSheet(
        locationAvailable: Location.instance.isAvailable,
        initialMode: initialMode,
      ),
    );
    if (choice == null || !mounted) return;
    var (visibility, mode) = choice;
    GeoPoint? location;
    if (visibility == PartyVisibility.public) {
      location = await _fixForPublic();
      if (!mounted) return;
      if (location == null) {
        // 막다른 길을 만들지 않는다 — 방은 열리고, 왜 비밀방인지 말한다.
        visibility = PartyVisibility.private;
        AppSnackbar.info(context, '위치를 읽지 못해 비밀방으로 열었어요. 코드로 초대할 수 있어요.');
      }
    }
    await _leaveCurrentRoom();
    if (!mounted) return;
    await _run(
      () => _repository!.createParty(
        mode: mode,
        visibility: visibility,
        location: location,
      ),
    );
  }

  Future<void> _joinNearby(NearbyParty room) async {
    if (!await requireSignIn(context, reason: AuthReason.together)) return;
    if (!mounted) return;
    await _leaveCurrentRoom();
    if (!mounted) return;
    await _run(() => _repository!.joinPublicParty(room.id));
    // 못 들어갔으면(꽉 참·사라짐) 목록이 낡은 것이다.
    if (mounted && _party == null) unawaited(_loadNearby());
  }

  Future<void> _setVisibility(
    TrainingParty party,
    PartyVisibility visibility,
  ) async {
    GeoPoint? location;
    if (visibility == PartyVisibility.public) {
      location = await _fixForPublic();
      if (!mounted) return;
      if (location == null) {
        AppSnackbar.info(context, '위치를 읽지 못해 공개방으로 바꾸지 못했어요.');
        return;
      }
    }
    await _run(
      () => _repository!.setVisibility(
        partyId: party.id,
        visibility: visibility,
        location: location,
      ),
    );
  }

  Future<void> _join() async {
    if (!await requireSignIn(context, reason: AuthReason.together)) return;
    if (!mounted) return;
    final code = await _askForCode(context);
    if (code == null || !mounted) return;
    await _leaveCurrentRoom();
    if (!mounted) return;
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

  /// 나가기는 되돌리기 어렵다(코드로 다시 들어오면 세트 수가 0부터다). 세트
  /// 사이의 조작이 아니라 운동을 끝내는 조작이니 한 번은 묻는다.
  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('방을 나갈까요?'),
        content: const Text('다시 들어오려면 초대 코드가 필요하고, 전광판의 세트 수는 처음부터예요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey('together-leave-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) await _leave();
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
    if (mounted) {
      setState(() {
        _party = null;
        _minimized = false;
      });
    }
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
    builder: (_) => Builder(
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
                (
                  2,
                  SetflowIcons.partyStart,
                  '준비되면 같이 시작',
                  '모든 폰이 같은 카운트다운을 세요',
                ),
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
                        style: const TextStyle(
                          fontWeight: SetflowWeight.strong,
                        ),
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
              Text('세 가지 종목 — 전광판은 어디에나', style: theme.textTheme.titleMedium),
              const SizedBox(height: SetflowSpacing.sm),
              for (final mode in PartyMode.values) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(
                        mode.label,
                        style: const TextStyle(
                          fontWeight: SetflowWeight.strong,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${mode.detail}\n${mode.when}',
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
    ),
  );
}

/// 로비의 "근처 공개방" 구역 상태. 위치는 허용된 사람만 자동으로 읽는다.
sealed class _NearbyStatus {
  const _NearbyStatus();
}

class _NearbyIdle extends _NearbyStatus {
  const _NearbyIdle();
}

class _NearbyLoading extends _NearbyStatus {
  const _NearbyLoading();
}

class _NearbySignedOut extends _NearbyStatus {
  const _NearbySignedOut();
}

class _NearbyNeedsLocation extends _NearbyStatus {
  const _NearbyNeedsLocation({
    this.permanently = false,
    this.servicesOff = false,
  });

  final bool permanently;
  final bool servicesOff;
}

class _NearbyFailed extends _NearbyStatus {
  const _NearbyFailed(this.message);

  final String message;
}

class _NearbyRooms extends _NearbyStatus {
  const _NearbyRooms(this.rooms);

  final List<NearbyParty> rooms;
}

/// 방 밖. 위는 전광판을 닮은 히어로, 가운데는 행동 둘, 아래는 근처에서 열린
/// 공개방 — 같은 헬스장의 모르는 사람과 겨루러 들어가는 문이다.
class _Lobby extends StatelessWidget {
  const _Lobby({
    required this.busy,
    required this.error,
    required this.activeParty,
    required this.onResume,
    required this.nearby,
    required this.locationAvailable,
    required this.selectedMode,
    required this.onSelectMode,
    required this.todaySets,
    required this.onJoin,
    required this.onJoinNearby,
    required this.onLoadNearby,
    required this.onRefreshNearby,
    required this.onOpenLocationSettings,
    required this.onSignIn,
  });

  final bool busy;
  final String? error;

  /// 접어 둔 방. 있으면 맨 위 배너가 되돌아가는 길이다.
  final TrainingParty? activeParty;
  final VoidCallback onResume;
  final _NearbyStatus nearby;
  final bool locationAvailable;
  final PartyMode selectedMode;
  final ValueChanged<PartyMode> onSelectMode;
  final int todaySets;
  final VoidCallback onJoin;
  final ValueChanged<NearbyParty> onJoinNearby;
  final VoidCallback onLoadNearby;
  final Future<void> Function() onRefreshNearby;
  final Future<void> Function() onOpenLocationSettings;
  final VoidCallback onSignIn;

  /// 로비는 경기장 입구다 — 회색 상자를 쌓는 문법("카드 아니면 로우 아니면 버튼")을
  /// 버린다. 전광판의 언어를 얇게 빌린 **LED 티커** 한 줄, 종목은 상자가 아니라
  /// **큰 글자 셋**(고른 것만 잉크, 라임 밑줄), 근처 방은 **선으로 나눈 목록**,
  /// 코드는 여섯 칸 한 줄. 행동은 하나 — 하단의 "<종목> 방 만들기".
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return RefreshIndicator(
      onRefresh: onRefreshNearby,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          SetflowSpacing.gutter,
          SetflowSpacing.sm,
          SetflowSpacing.gutter,
          SetflowSpacing.xl,
        ),
        children: [
          if (activeParty != null) ...[
            _ActiveRoomBanner(party: activeParty!, onResume: onResume),
            const SizedBox(height: SetflowSpacing.md),
          ],
          _LedTicker(nearby: nearby, todaySets: todaySets),
          if (error != null) ...[
            const SizedBox(height: SetflowSpacing.md),
            _Notice(message: error!),
          ],
          const SizedBox(height: SetflowSpacing.section),
          // 종목 — 목차처럼. 번호는 순서가 아니라 리듬이다.
          for (final (index, mode) in PartyMode.values.indexed)
            _ModeLine(
              key: ValueKey('lobby-mode-${mode.name}'),
              index: index + 1,
              mode: mode,
              selected: mode == selectedMode,
              enabled: !busy,
              onTap: () => onSelectMode(mode),
            ),
          const SizedBox(height: SetflowSpacing.section),
          _CodeLine(onTap: busy ? null : onJoin),
          if (locationAvailable) ...[
            const SizedBox(height: SetflowSpacing.section),
            Row(
              children: [
                const Expanded(child: SectionTitle('근처 공개방')),
                if (nearby is _NearbyRooms || nearby is _NearbyFailed)
                  IconButton(
                    key: const ValueKey('together-nearby-refresh'),
                    tooltip: '새로 고침',
                    onPressed: onRefreshNearby,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
              ],
            ),
            const SizedBox(height: SetflowSpacing.xs),
            switch (nearby) {
              _NearbyIdle() || _NearbyLoading() => _NearbyHint(
                key: const ValueKey('together-nearby-loading'),
                message: '근처에서 열린 방을 찾는 중이에요.',
              ),
              _NearbySignedOut() => _NearbyHint(
                key: const ValueKey('together-nearby-signed-out'),
                message: '로그인하면 근처에서 열린 공개방이 보여요.',
                actionLabel: '로그인',
                onAction: onSignIn,
              ),
              _NearbyNeedsLocation(:final permanently, :final servicesOff) =>
                _NearbyHint(
                  key: const ValueKey('together-nearby-location'),
                  message: servicesOff
                      ? '기기의 위치 서비스가 꺼져 있어요. 켜면 같은 헬스장에서 열린 방이 보여요.'
                      : '위치를 허용하면 같은 헬스장에서 열린 방이 보여요. 위치는 거리 계산에만 써요.',
                  actionLabel: servicesOff
                      ? null
                      : permanently
                      ? '설정 열기'
                      : '근처 방 보기',
                  onAction: permanently ? onOpenLocationSettings : onLoadNearby,
                ),
              _NearbyFailed(:final message) => _NearbyHint(
                key: const ValueKey('together-nearby-failed'),
                message: message,
                actionLabel: '다시 시도',
                onAction: onRefreshNearby,
              ),
              _NearbyRooms(:final rooms) when rooms.isEmpty => _NearbyHint(
                key: const ValueKey('together-nearby-empty'),
                message:
                    '지금 근처에 열린 공개방이 없어요. 공개로 방을 열면 여기 떠요 — 같은 헬스장 사람이 들어올 수 있어요.',
              ),
              _NearbyRooms(:final rooms) => Column(
                children: [
                  for (final room in rooms)
                    _NearbyRow(
                      key: ValueKey('together-nearby-${room.id}'),
                      room: room,
                      busy: busy,
                      onJoin: () => onJoinNearby(room),
                    ),
                ],
              ),
            },
            const SizedBox(height: SetflowSpacing.sm),
            Text('공개방에는 이름만 보여요. 언제든 나갈 수 있어요.', style: muted),
          ],
        ],
      ),
    );
  }
}

/// 전광판의 언어를 한 줄만 빌린다 — 검은 띠 위에 도트 숫자. 큰 가짜 판이 아니라
/// 얇은 티커라서, 위치가 꺼져 있으면 그 항목만 빠진다(대시를 켜지 않는다).
class _LedTicker extends StatelessWidget {
  const _LedTicker({required this.nearby, required this.todaySets});

  final _NearbyStatus nearby;
  final int todaySets;

  @override
  Widget build(BuildContext context) {
    final rooms = switch (nearby) {
      _NearbyRooms(:final rooms) => rooms,
      _ => null,
    };
    final segments = <(String, int)>[
      if (rooms != null) ('근처 방', rooms.length),
      if (rooms != null)
        ('운동 중', rooms.fold<int>(0, (n, room) => n + room.memberCount)),
      ('오늘 세트', todaySets),
    ];
    return Container(
      key: const ValueKey('lobby-ticker'),
      padding: const EdgeInsets.symmetric(
        horizontal: SetflowSpacing.lg,
        vertical: SetflowSpacing.sm2,
      ),
      decoration: BoxDecoration(
        color: LedPalette.panel,
        borderRadius: BorderRadius.circular(SetflowRadii.sm),
      ),
      child: Row(
        children: [
          for (final (index, (label, value)) in segments.indexed) ...[
            if (index > 0) const SizedBox(width: SetflowSpacing.xl),
            _LedFigure(label: label, value: value),
          ],
          const Spacer(),
          Text(
            'LIVE',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: LedPalette.dimText,
              letterSpacing: SetflowSpacing.xxs,
            ),
          ),
        ],
      ),
    );
  }
}

class _LedFigure extends StatelessWidget {
  const _LedFigure({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    const pitch = 2.6;
    final text = '$value';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        LedBoard(
          pitch: pitch,
          cols: ledDigitsWidth(text),
          rows: ledGlyphRows,
          lit: ledDigitCells(text, origin: (x: 0, y: 0)).toSet(),
        ),
        const SizedBox(width: SetflowSpacing.sm),
        Padding(
          padding: const EdgeInsets.only(bottom: SetflowSpacing.xxs),
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: LedPalette.muted),
          ),
        ),
      ],
    );
  }
}

/// 종목 한 줄 — 상자가 아니라 글자다. 고른 줄만 잉크색에 라임 밑줄이 붙고
/// 설명이 펼쳐진다. 나머지는 회색 글자로 물러난다.
class _ModeLine extends StatelessWidget {
  const _ModeLine({
    required this.index,
    required this.mode,
    required this.selected,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final int index;
  final PartyMode mode;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    final faded = context.setflowColors.disabled;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: SetflowMotion.standard,
        curve: SetflowMotion.standardCurve,
        padding: const EdgeInsets.symmetric(vertical: SetflowSpacing.md),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 32,
              child: Padding(
                padding: const EdgeInsets.only(top: SetflowSpacing.sm),
                child: Text(
                  index.toString().padLeft(2, '0'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: selected ? ink : faded,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        mode.label,
                        style: theme.textTheme.headlineLarge?.copyWith(
                          color: selected ? ink : faded,
                        ),
                      ),
                      const Spacer(),
                      Icon(_iconForMode(mode), color: selected ? ink : faded),
                    ],
                  ),
                  // 라임은 채우는 색이다 — 밑줄 막대로 "고름"을 말한다.
                  AnimatedContainer(
                    duration: SetflowMotion.standard,
                    curve: SetflowMotion.standardCurve,
                    margin: const EdgeInsets.only(top: SetflowSpacing.xs),
                    height: SetflowSpacing.xs,
                    width: selected ? 40 : 0,
                    color: theme.colorScheme.primary,
                  ),
                  AnimatedSize(
                    duration: SetflowMotion.standard,
                    curve: SetflowMotion.standardCurve,
                    alignment: Alignment.topLeft,
                    child: selected
                        ? Padding(
                            padding: const EdgeInsets.only(
                              top: SetflowSpacing.sm,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mode.detail,
                                  style: theme.textTheme.bodyMedium,
                                ),
                                const SizedBox(height: SetflowSpacing.xxs),
                                Text(
                                  mode.when,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox(width: double.infinity),
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

/// 초대 코드 — 여섯 칸이 비어 있는 한 줄. 탭하면 코드 입력이 열린다.
class _CodeLine extends StatelessWidget {
  const _CodeLine({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      key: const ValueKey('together-join'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: SetflowSpacing.md),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            Text('코드로 참여', style: theme.textTheme.titleMedium),
            const Spacer(),
            for (var i = 0; i < 6; i++) ...[
              Container(
                width: 14,
                height: SetflowSpacing.xxs,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              if (i < 5) const SizedBox(width: SetflowSpacing.xs2),
            ],
            const SizedBox(width: SetflowSpacing.md),
            Icon(
              SetflowIcons.forward,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// 로비 하단 고정 — 행동은 하나다. 라벨이 고른 종목을 따른다.
/// 스크롤 밖에 있으니 세이프에리어 안에 둔다(`test/safe_area_sweep_test.dart`).
class _LobbyActions extends StatelessWidget {
  const _LobbyActions({
    required this.mode,
    required this.busy,
    required this.onCreate,
  });

  final PartyMode mode;
  final bool busy;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SetflowSpacing.gutter,
          SetflowSpacing.sm,
          SetflowSpacing.gutter,
          SetflowSpacing.sm,
        ),
        child: AppButton(
          key: const ValueKey('together-create'),
          label: '${mode.label} 방 만들기',
          icon: SetflowIcons.partyCreate,
          isLoading: busy,
          onPressed: busy ? null : onCreate,
        ),
      ),
    );
  }
}

IconData _iconForMode(PartyMode mode) => switch (mode) {
  PartyMode.free => SetflowIcons.activityGym,
  PartyMode.together => SetflowIcons.activityCrossfit,
  PartyMode.alternating => SetflowIcons.activityAlternate,
};

/// 접어 둔 방으로 돌아가는 배너. 방은 계속 돌고 있으니 "진행 중"이고,
/// 탭 한 번이면 전광판이다. 브랜드 채움 위 전경은 언제나 잉크(onBrand).
class _ActiveRoomBanner extends StatelessWidget {
  const _ActiveRoomBanner({required this.party, required this.onResume});

  final TrainingParty party;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = party.members.length;
    return SetflowCard(
      key: const ValueKey('together-resume'),
      color: SetflowColors.brand,
      onTap: onResume,
      child: Row(
        children: [
          const Icon(SetflowIcons.together, color: SetflowColors.onBrand),
          const SizedBox(width: SetflowSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '진행 중인 방',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: SetflowColors.onBrand,
                  ),
                ),
                const SizedBox(height: SetflowSpacing.xxs),
                Text(
                  n == 1
                      ? '${party.mode.label} · 친구를 기다리는 중'
                      : '${party.mode.label} · $n명',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: SetflowColors.onBrand,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '돌아가기',
            style: theme.textTheme.labelLarge?.copyWith(
              color: SetflowColors.onBrand,
            ),
          ),
          const SizedBox(width: SetflowSpacing.xs),
          const Icon(SetflowIcons.forward, color: SetflowColors.onBrand),
        ],
      ),
    );
  }
}

class _NearbyHint extends StatelessWidget {
  const _NearbyHint({
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SetflowSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(width: SetflowSpacing.sm),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _NearbyRow extends StatelessWidget {
  const _NearbyRow({
    required this.room,
    required this.busy,
    required this.onJoin,
    super.key,
  });

  final NearbyParty room;
  final bool busy;
  final VoidCallback onJoin;

  static String _distance(int meters) =>
      meters < 1000 ? '${meters}m' : '${(meters / 1000).toStringAsFixed(1)}km';

  static String _ago(DateTime createdAt) {
    final minutes = DateTime.now().difference(createdAt).inMinutes;
    if (minutes < 1) return '방금';
    if (minutes < 60) return '$minutes분 전';
    return '${minutes ~/ 60}시간 전';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: SetflowSpacing.sm2),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          // 라임 점 = 지금 열려 있음. 전광판의 LIVE 점과 같은 뜻이다.
          Container(
            width: SetflowSpacing.sm,
            height: SetflowSpacing.sm,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: SetflowSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${room.hostName}님의 방',
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: SetflowSpacing.xxs),
                Text(
                  '${room.mode.label} · ${room.memberCount}/$maxPartyMembers명 · '
                  '${_distance(room.distanceMeters)} · ${_ago(room.createdAt)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: SetflowSpacing.sm),
          TextButton(
            key: ValueKey('together-nearby-join-${room.id}'),
            onPressed: busy ? null : onJoin,
            child: const Text('참여'),
          ),
        ],
      ),
    );
  }
}

/// 방을 열기 전에 정하는 둘 — 누가 들어올 수 있는지, 무슨 종목인지.
/// 방을 여는 것은 빈 시간이라 여기서 한 번 묻는 것이 세트 사이에 묻는 것보다 낫다.
/// 라디오 목록이 아니라 카드다 — 게임의 방 설정 화면처럼 한눈에 고른다.
class _CreateSheet extends StatefulWidget {
  const _CreateSheet({required this.locationAvailable, this.initialMode});

  /// 위치를 못 읽는 기기에서는 공개 카드를 잠그고 이유를 적는다.
  final bool locationAvailable;

  /// 로비의 종목 카드에서 왔으면 그 종목이 골라진 채로 연다.
  final PartyMode? initialMode;

  @override
  State<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends State<_CreateSheet> {
  PartyVisibility _visibility = PartyVisibility.private;
  late PartyMode _mode = widget.initialMode ?? PartyMode.defaultMode;

  static IconData _iconFor(PartyMode mode) => _iconForMode(mode);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
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
          Text('방 만들기', style: theme.textTheme.titleLarge),
          const SizedBox(height: SetflowSpacing.lg),
          Text('누가 들어올 수 있나요', style: theme.textTheme.titleMedium),
          const SizedBox(height: SetflowSpacing.sm),
          Row(
            children: [
              for (final (index, visibility)
                  in PartyVisibility.values.indexed) ...[
                if (index > 0) const SizedBox(width: SetflowSpacing.sm),
                Expanded(
                  child: _ChoiceCard(
                    key: ValueKey('create-visibility-${visibility.name}'),
                    icon: visibility == PartyVisibility.public
                        ? SetflowIcons.publicRoom
                        : SetflowIcons.privateRoom,
                    title: visibility.label,
                    subtitle: visibility == PartyVisibility.public
                        ? '근처 사람도 들어와요'
                        : '코드로만 들어와요',
                    selected: _visibility == visibility,
                    enabled:
                        widget.locationAvailable ||
                        visibility == PartyVisibility.private,
                    onTap: () => setState(() => _visibility = visibility),
                  ),
                ),
              ],
            ],
          ),
          if (!widget.locationAvailable) ...[
            const SizedBox(height: SetflowSpacing.sm),
            Text(
              '이 기기에서는 위치를 읽을 수 없어 공개방을 열 수 없어요.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: SetflowSpacing.lg),
          Text('종목', style: theme.textTheme.titleMedium),
          const SizedBox(height: SetflowSpacing.sm),
          Row(
            children: [
              for (final (index, mode) in PartyMode.values.indexed) ...[
                if (index > 0) const SizedBox(width: SetflowSpacing.sm),
                Expanded(
                  child: _ChoiceCard(
                    key: ValueKey('create-mode-${mode.name}'),
                    icon: _iconFor(mode),
                    title: mode.label,
                    selected: _mode == mode,
                    onTap: () => setState(() => _mode = mode),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: SetflowSpacing.sm),
          // 고른 종목의 설명 한 장. 세 장에 다 적으면 카드가 글 상자가 된다.
          Container(
            key: const ValueKey('create-mode-detail'),
            padding: const EdgeInsets.all(SetflowSpacing.md),
            decoration: BoxDecoration(
              color: context.setflowColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(SetflowRadii.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_mode.detail, style: theme.textTheme.bodyMedium),
                const SizedBox(height: SetflowSpacing.xxs),
                Text(
                  '${_mode.when} · 전광판은 어느 종목에나 있어요',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.lg),
          AppButton(
            key: const ValueKey('together-create-confirm'),
            label: _visibility == PartyVisibility.public ? '공개방 열기' : '비밀방 열기',
            icon: SetflowIcons.partyCreate,
            onPressed: () => Navigator.of(context).pop((_visibility, _mode)),
          ),
        ],
      ),
    );
  }
}

/// 고르는 카드 하나. 골리면 라임 테두리와 옅은 라임 바탕, 아니면 회색 판.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.enabled = true,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = !enabled
        ? context.setflowColors.disabled
        : selected
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: subtitle == null ? title : '$title, $subtitle',
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: .18)
            : context.setflowColors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SetflowRadii.md),
          side: BorderSide(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(SetflowRadii.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SetflowSpacing.sm,
              vertical: SetflowSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 24, color: foreground),
                const SizedBox(height: SetflowSpacing.xs2),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: SetflowWeight.strong,
                    fontSize: SetflowFontSize.label,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: SetflowSpacing.xxs),
                  Text(
                    subtitle!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: foreground,
                      fontSize: SetflowFontSize.small,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
    required this.statusKey,
    required this.boardKey,
    required this.actionKey,
    required this.codeKey,
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

  /// 화면 안내가 비출 자리. 각 덩어리의 ValueKey는 테스트가 쓰므로 그대로 두고
  /// 바깥을 감싼다.
  final GlobalKey statusKey;
  final GlobalKey boardKey;
  final GlobalKey actionKey;
  final GlobalKey codeKey;

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
    final countdown = party.countdownSeconds;
    final myTurn =
        party.mode == PartyMode.alternating &&
        party.currentTurnUserId == userId;

    return Column(
      children: [
        KeyedSubtree(
          key: statusKey,
          child: _LiveStatusBar(
            key: const ValueKey('together-status-hero'),
            party: party,
            userId: userId,
            countdown: countdown,
            myTurn: myTurn,
            onStart: busy ? null : onStart,
            onInvite: onInvite,
          ),
        ),
        // 전광판이 남는 높이를 전부 가져간다. 두 사람이면 스크롤이 아예 없고,
        // 여섯이면 이 안에서만 스크롤된다 — 하단 액션은 밀려나지 않는다.
        Expanded(
          child: KeyedSubtree(
            key: boardKey,
            // 혼자여도 전광판이다 — "전광판이 게임판인데". 내 줄이 먼저 켜지고,
            // 초대 코드는 판 아래 줄에 얹힌다.
            child: _Scoreboard(party: party, userId: userId, codeKey: codeKey),
          ),
        ),
        if (party.routines.isNotEmpty)
          _RoutineBanner(
            key: const ValueKey('together-routine-banner'),
            count: party.routines.length,
            onTap: onShowRoutines,
          ),
        KeyedSubtree(
          key: actionKey,
          child: _RoomActionBar(
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
        ),
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
          key: ValueKey('together-invite'),
          value: _RoomAction.invite,
          child: ListTile(
            leading: Icon(SetflowIcons.partyJoin),
            title: Text('친구 초대'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _RoomAction.mode,
          enabled: !busy,
          child: const ListTile(
            leading: Icon(Icons.tune_rounded),
            title: Text('종목 · 공개 여부'),
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
          key: const ValueKey('together-leave'),
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
      _ when solo => (
        party.isPublic ? '근처 사람을 기다리는 중' : '친구를 기다리는 중',
        _StatusTone.idle,
      ),
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
    final live = liveSet;
    // 교대에서는 자기 차례에만 눌린다 — 차례 밖의 기록은 들지도 않은 사람을
    // 지나쳐 순번을 돌린다. 다만 라벨은 상태를 정직하게 말해야 한다.
    final gated = party.mode == PartyMode.alternating && !solo && !myTurn;
    final turnName = party.currentTurnUserId == null
        ? null
        : party.memberOf(party.currentTurnUserId!)?.displayName;
    final label = !gated
        ? '${live?.$2.number ?? ''}세트 끝냈어요'
        : party.currentTurnUserId != null
        ? '${turnName ?? '상대'}님 차례예요'
        : '같이 시작으로 순서를 정해요';

    // "세트 끝냈어요"는 신호가 아니라 기록이다. 오늘 기록에 세트가 없으면 끝낼
    // 것도 없다 — 그 자리엔 실제로 할 수 있는 일 하나만 둔다: 운동 추가.
    // (실기기 피드백: "운동이 없는데 세트 끝내는 버튼이 왜 있지")
    final children = live == null
        ? [
            Padding(
              key: const ValueKey('together-live-set-empty'),
              padding: const EdgeInsets.only(bottom: SetflowSpacing.md),
              child: Column(
                children: [
                  const Text(
                    '오늘 기록에 운동이 없어요',
                    style: TextStyle(fontWeight: SetflowWeight.strong),
                  ),
                  const SizedBox(height: SetflowSpacing.xxs),
                  Text(
                    '기록 탭에서 운동을 추가하면 여기서 세트가 넘어가요.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            AppButton(
              key: const ValueKey('together-add-workout'),
              label: '오늘 운동 추가하기',
              icon: SetflowIcons.partyCreate,
              onPressed: onOpenRecord,
            ),
          ]
        : [
            _LiveSetCard(liveSet: live, unit: unit, onEdited: onSetEdited),
            const SizedBox(height: SetflowSpacing.md),
            AppButton(
              key: const ValueKey('together-set-done'),
              label: label,
              icon: SetflowIcons.setComplete,
              isLoading: busy,
              onPressed: busy || me == null || gated ? null : onSetDone,
            ),
          ];

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
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
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
    required this.unit,
    required this.onEdited,
  });

  final (WorkoutExercise, WorkoutSetEntry) liveSet;
  final String unit;

  /// 다이얼 적용을 상태의 정식 경로(updateSet)로 넘긴다 — 카드가 세트에
  /// 직접 쓰면 저장·클램프·알림이 다 빠진다.
  final void Function({double? weight, int? reps, int? restSeconds}) onEdited;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (exercise, set) = liveSet;
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
  const _Scoreboard({
    required this.party,
    required this.userId,
    required this.codeKey,
  });

  final TrainingParty party;
  final String? userId;

  /// 화면 안내가 초대 코드를 비출 자리.
  final GlobalKey codeKey;

  /// 한 줄이 차지하는 칸 수. 위 1칸, 이름 줄 3칸, 숫자 11칸, 아래 여유 3칸.
  static const _rowCells = 18;
  static const _padCells = 1;
  static const _raceCells = 3;

  @override
  Widget build(BuildContext context) {
    final ranked = party.members.toList()
      ..sort((a, b) {
        final bySets = b.completedSets.compareTo(a.completedSets);
        return bySets != 0 ? bySets : a.turnOrder.compareTo(b.turnOrder);
      });
    final maxSets = ranked.isEmpty ? 0 : ranked.first.completedSets;
    final race = party.members.length > 1 && maxSets > 0;
    final solo = party.members.length == 1;
    // 판 아래 한 줄: 경쟁 중이면 격차, 혼자면 초대 코드.
    final footer = race || solo;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 판 전체가 하나의 격자다. 칸 크기는 남는 높이에서 온다 — 두 명이면
        // 칸이 12px까지 커져 숫자가 화면 절반을 넘고("상단부터 중간 넘어가게"),
        // 여섯이면 6px로 낮아지다 넘치는 순간부터 스크롤된다.
        final totalCells =
            ranked.length * _rowCells +
            _padCells * 2 +
            (footer ? _raceCells : 0);
        // 혼자면 줄이 하나뿐이라 칸을 더 키운다 — 판이 화면을 채우고 숫자가
        // 아케이드처럼 커진다. 둘 이상이면 12px이 상한이다.
        final pitch = ((constraints.maxHeight - SetflowSpacing.lg) / totalCells)
            .clamp(6.0, solo ? 16.0 : 12.0);
        final width = constraints.maxWidth - SetflowSpacing.gutter * 2;
        final cols = (width / pitch).floor();
        final boardWidth = cols * pitch;
        final boardHeight = totalCells * pitch;

        final lit = <LedCell>{};
        final bands = <LedBand>[];
        final edges = <({int fromY, int toY})>[];
        for (final (index, member) in ranked.indexed) {
          final top = _padCells + index * _rowCells;
          lit.addAll(
            ledDigitCells(
              '${member.completedSets}',
              origin: (x: 2, y: top + 4),
            ),
          );
          if (member.userId == userId) {
            bands.add((
              fromY: top,
              toY: top + _rowCells,
              color: LedPalette.off.withValues(alpha: .45),
            ));
          }
          if (member.state == PartyMemberState.lifting) {
            edges.add((fromY: top + 1, toY: top + _rowCells - 1));
          }
        }

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
              child: Align(
                alignment: Alignment.topCenter,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(SetflowRadii.lg),
                  child: Container(
                    key: const ValueKey('together-scoreboard'),
                    width: boardWidth,
                    height: boardHeight,
                    decoration: BoxDecoration(
                      color: LedPalette.panel,
                      borderRadius: BorderRadius.circular(SetflowRadii.lg),
                      border: Border.all(color: LedPalette.edge),
                    ),
                    // 글자는 격자 위에 얹힌다. 시스템 글자 배율은 1.3배까지만 —
                    // 줄 높이가 칸 수로 고정된 판이라 그 이상은 숫자를 덮는다
                    // (달력 칸과 같은 이유).
                    child: MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.3,
                      child: Stack(
                        children: [
                          LedBoard(
                            pitch: pitch,
                            cols: cols,
                            rows: totalCells,
                            lit: lit,
                            bands: bands,
                            edges: edges,
                          ),
                          for (final (index, member) in ranked.indexed)
                            Positioned(
                              left: 2 * pitch,
                              top: (_padCells + index * _rowCells) * pitch,
                              width: boardWidth - 4 * pitch,
                              height: _rowCells * pitch,
                              child: _ScoreboardRow(
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
                                        ranked[1].completedSets <
                                            member.completedSets),
                                sharedRest: party.mode == PartyMode.together,
                                pitch: pitch,
                              ),
                            ),
                          if (race)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: _padCells * pitch,
                              height: _raceCells * pitch,
                              // 전광판 맨 아래 흐르는 한 줄 — 격차가 곧 응원이다.
                              // 라임 글자는 흰 배경에서 금지지만 여기는 검은 판이다.
                              child: Center(
                                child: Text(
                                  _raceLine(ranked),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: LedPalette.lit,
                                    fontSize: SetflowFontSize.label,
                                    fontWeight: SetflowWeight.strong,
                                    letterSpacing: .2,
                                  ),
                                ),
                              ),
                            )
                          else if (solo)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: _padCells * pitch,
                              height: _raceCells * pitch,
                              child: KeyedSubtree(
                                key: codeKey,
                                child: _CodeFooter(
                                  code: party.code,
                                  isPublic: party.isPublic,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

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

/// 혼자인 방의 전광판 아래 줄 — 초대 코드. 탭하면 복사된다. 공개방이면
/// 근처 사람이 알아서 들어오니 코드는 "친구도 부를 수 있다"는 보조 수단이다.
class _CodeFooter extends StatelessWidget {
  const _CodeFooter({required this.code, required this.isPublic});

  final String code;
  final bool isPublic;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '초대 코드 $code, 탭하면 복사',
      child: InkWell(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: code));
          if (context.mounted) AppSnackbar.success(context, '코드를 복사했어요.');
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              isPublic ? '근처 사람 입장 가능 · 초대 코드' : '초대 코드',
              style: const TextStyle(
                color: LedPalette.dimText,
                fontSize: SetflowFontSize.caption,
                fontWeight: SetflowWeight.strong,
              ),
            ),
            const SizedBox(width: SetflowSpacing.sm),
            Text(
              code,
              key: const ValueKey('together-code'),
              style: const TextStyle(
                color: LedPalette.lit,
                fontSize: SetflowFontSize.title,
                fontWeight: SetflowWeight.display,
                letterSpacing: 4,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: SetflowSpacing.sm),
            const Icon(Icons.copy_rounded, size: 16, color: LedPalette.dimText),
          ],
        ),
      ),
    );
  }
}

/// 전광판 한 줄의 글자들. 숫자는 판(격자)이 켜고, 여기는 그 위에 얹는
/// 이름·상태·종목·볼륨뿐이다. 휴식 시간은 여기 적지 않는다 — 상단 상태
/// 줄에 이미 있고, 같은 숫자가 두 곳에 있으면 어느 쪽이 진짜인지 고민하게
/// 된다. 남의 상태는 점 하나와 짧은 말로 충분하다.
class _ScoreboardRow extends StatelessWidget {
  const _ScoreboardRow({
    required this.member,
    required this.isMe,
    required this.hasTurn,
    required this.rank,
    required this.leading,
    required this.sharedRest,
    required this.pitch,
  });

  final PartyMember member;
  final bool isMe;
  final bool hasTurn;

  /// 경쟁이 시작된 뒤(2명 이상, 1세트 이상)에만 순위가 있다.
  final int? rank;
  final bool leading;

  /// '같이' 모드에서는 모두가 같은 시계로 쉬므로 상단 상태 줄이 이미 말했다.
  final bool sharedRest;

  /// 격자 칸 크기 — 글자가 숫자 자리를 피해 앉는 기준.
  final double pitch;

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
    final lifting = member.state == PartyMemberState.lifting;
    final doing = member.currentExercise;
    final volume = member.totalVolume >= 1000
        ? '${(member.totalVolume / 1000).toStringAsFixed(1)}t'
        : '${member.totalVolume.toStringAsFixed(0)}kg';
    final digitsWidth = ledDigitsWidth('${member.completedSets}') * pitch;

    return Semantics(
      key: ValueKey('scoreboard-${member.userId}'),
      label: '${member.displayName} ${member.completedSets}세트',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 3 * pitch,
            child: Row(
              children: [
                if (leading) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SetflowSpacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: LedPalette.lit,
                      borderRadius: BorderRadius.circular(SetflowRadii.xs),
                    ),
                    child: const Text(
                      '1위',
                      style: TextStyle(
                        color: LedPalette.litInk,
                        fontSize: SetflowFontSize.small,
                        fontWeight: SetflowWeight.display,
                      ),
                    ),
                  ),
                  const SizedBox(width: SetflowSpacing.sm),
                ] else if (rank != null) ...[
                  Text(
                    '$rank위',
                    style: const TextStyle(
                      color: LedPalette.dimText,
                      fontSize: SetflowFontSize.caption,
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
                      color: LedPalette.text,
                      fontWeight: SetflowWeight.strong,
                      fontSize: SetflowFontSize.label,
                    ),
                  ),
                ),
                if (_statusLabel case final status?)
                  Text(
                    status,
                    style: TextStyle(
                      color: lifting ? LedPalette.lit : LedPalette.muted,
                      fontSize: SetflowFontSize.caption,
                      fontWeight: SetflowWeight.strong,
                      letterSpacing: .5,
                    ),
                  ),
              ],
            ),
          ),
          // 숫자(격자가 켠다)의 높이만큼 비워 두고, 그 오른쪽 아래에 글자.
          SizedBox(
            height: (ledGlyphRows + 1) * pitch,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(width: digitsWidth + pitch),
                const Text(
                  '세트',
                  style: TextStyle(
                    color: LedPalette.muted,
                    fontSize: SetflowFontSize.caption,
                    fontWeight: SetflowWeight.strong,
                  ),
                ),
                const SizedBox(width: SetflowSpacing.md),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                        style: const TextStyle(
                          color: LedPalette.muted,
                          fontSize: SetflowFontSize.caption,
                        ),
                      ),
                      if (member.totalVolume > 0)
                        Text(
                          volume,
                          style: const TextStyle(
                            color: LedPalette.text,
                            fontSize: SetflowFontSize.label,
                            fontWeight: SetflowWeight.strong,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
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
