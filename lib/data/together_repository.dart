/// Training with someone who is not in the room with you.
///
/// Three decisions run through every type here, and changing any of them is a
/// bigger change than it looks:
///
/// 1. **Instants, never durations.** `startsAt` and `restEndsAt` are absolute
///    times. A device that learns about a rest two seconds late still counts
///    down to the same moment as everyone else, so lag shifts *when you find
///    out*, not *what you see*. Sending "90초 남음" instead would drift the
///    partners apart a little more every set.
/// 2. **The turn is decided once, on the server.** `currentTurnUserId` lives on
///    the party, not on each phone. Two people cannot both believe it is their
///    turn, which is the only failure that would make an alternating set feel
///    broken rather than merely late.
/// 3. **The port hands out a domain stream, not a subscription.** Whether
///    [TogetherRepository.watchParty] polls or rides Realtime is the adapter's
///    business. This is the app's first live surface, so it is also the
///    precedent: `RealtimeChannel` must never reach a screen.
///    See `docs/backend-portability.md`.
library;

import 'dart:async';
import 'dart:math';

import '../models.dart';

/// 방 정원. 서버(join_training_party)와 메모리 백엔드가 같은 값을 강제한다 —
/// 화면이 명단이 되는 것, 교대 대기가 늘어지는 것, 유출된 코드로 무한정
/// 들어오는 것을 막는 한 숫자다.
const int maxPartyMembers = 6;

/// How the room decides who lifts when.
enum PartyMode {
  /// Everyone starts on the same countdown and rests on the same clock. The
  /// feeling is a class: you are all mid-set at the same moment.
  together(
    '같이',
    '같은 신호에 시작하고, 누가 세트를 끝내면 모두 같이 쉬어요.',
    '나란히 다른 기구에서 같은 템포로 할 때',
  ),

  /// One person lifts while the others rest, then it passes on. The feeling is
  /// a spotter: your rest ends exactly when their set does.
  alternating(
    '교대',
    '한 명씩 번갈아 해요. 내가 끝내면 상대 차례, 상대가 끝내면 내 휴식이 끝나요.',
    '한 기구를 둘이 나눠 쓸 때',
  ),

  /// 각자 페이스. 떨어져서 각자 헬스장에 있으면 기구 대기·다른 종목 때문에
  /// 같은 시계로 묶을 수 없다 — 그때의 "함께"는 타이머가 아니라 전광판이다.
  /// 휴식은 자기 것만 돌고, 세트 수로만 겨룬다.
  free('각자', '각자 페이스로 하고, 전광판으로만 겨뤄요. 휴식은 내 것만 돌아요.', '떨어진 헬스장에서 따로 할 때');

  const PartyMode(this.label, this.detail, this.when);

  final String label;

  /// 어떻게 도는가 — 한 문장.
  final String detail;

  /// 언제 고르는가. "교대가 뭔지 모르겠다"는 피드백의 답은 규칙보다 상황이었다.
  final String when;
}

/// 누가 들어올 수 있는가. 비밀(기본)은 코드를 아는 사람만, 공개는 근처
/// 목록에 떠서 모르는 사람도 — 같은 헬스장에서 처음 보는 사람과 겨루는 방이다.
enum PartyVisibility {
  public('공개', '근처에서 열린 방 목록에 떠요. 모르는 사람도 들어올 수 있어요.'),
  private('비밀', '초대 코드를 아는 사람만 들어와요.');

  const PartyVisibility(this.label, this.detail);

  final String label;
  final String detail;
}

/// 근처 공개방 한 줄. 좌표는 없다 — 서버가 거리만 준다.
class NearbyParty {
  const NearbyParty({
    required this.id,
    required this.hostName,
    required this.mode,
    required this.memberCount,
    required this.distanceMeters,
    required this.createdAt,
  });

  final String id;
  final String hostName;
  final PartyMode mode;
  final int memberCount;
  final int distanceMeters;
  final DateTime createdAt;
}

enum PartyMemberState {
  /// In the room, nothing running.
  waiting,

  /// It is this person's set right now.
  lifting,

  /// Resting until [PartyMember.restEndsAt].
  resting,
}

class PartyMember {
  const PartyMember({
    required this.userId,
    required this.displayName,
    this.state = PartyMemberState.waiting,
    this.restEndsAt,
    this.completedSets = 0,
    this.turnOrder = 0,
    this.currentExercise,
    this.currentSetNumber,
    this.currentSetTotal,
    this.totalVolume = 0,
  });

  final String userId;
  final String displayName;
  final PartyMemberState state;

  /// Absolute end of this person's rest. Null unless [state] is resting.
  final DateTime? restEndsAt;
  final int completedSets;

  /// Position in the alternating rotation. Stable for the life of the party so
  /// the order does not reshuffle when someone's row is rewritten.
  final int turnOrder;

  /// 전광판 정보 — 지금 무슨 종목의 몇 세트째인지, 오늘 볼륨이 얼마인지.
  /// 세트를 보고할 때 각자 자기 기록에서 실어 보낸다. 표시용 수치이지
  /// 장부가 아니다 — 진실은 각자의 오늘 기록에 있다.
  final String? currentExercise;
  final int? currentSetNumber;
  final int? currentSetTotal;
  final double totalVolume;

  int get restRemainingSeconds {
    final endsAt = restEndsAt;
    if (endsAt == null) return 0;
    final left = endsAt.difference(DateTime.now()).inMilliseconds;
    return left <= 0 ? 0 : (left / 1000).ceil();
  }

  PartyMember copyWith({
    PartyMemberState? state,
    Object? restEndsAt = _unset,
    int? completedSets,
    int? turnOrder,
    String? currentExercise,
    int? currentSetNumber,
    int? currentSetTotal,
    double? totalVolume,
  }) => PartyMember(
    userId: userId,
    displayName: displayName,
    state: state ?? this.state,
    restEndsAt: restEndsAt == _unset
        ? this.restEndsAt
        : restEndsAt as DateTime?,
    completedSets: completedSets ?? this.completedSets,
    turnOrder: turnOrder ?? this.turnOrder,
    currentExercise: currentExercise ?? this.currentExercise,
    currentSetNumber: currentSetNumber ?? this.currentSetNumber,
    currentSetTotal: currentSetTotal ?? this.currentSetTotal,
    totalVolume: totalVolume ?? this.totalVolume,
  );
}

const Object _unset = Object();

/// A routine handed to the room — either "here's mine" or "I wrote this for
/// you". Both are the same act from the app's side: one person's plan lands
/// where the others can take it.
class OfferedRoutine {
  const OfferedRoutine({
    required this.id,
    required this.senderUserId,
    required this.senderName,
    required this.routine,
    required this.offeredAt,
  });

  final String id;
  final String senderUserId;
  final String senderName;
  final RoutineData routine;
  final DateTime offeredAt;
}

class TrainingParty {
  const TrainingParty({
    required this.id,
    required this.code,
    required this.hostUserId,
    required this.mode,
    required this.members,
    this.visibility = PartyVisibility.private,
    this.location,
    this.startsAt,
    this.currentTurnUserId,
    this.routines = const [],
  });

  final String id;

  /// What you read out loud to a friend. Short enough to type, long enough not
  /// to collide with the handful of rooms open at once.
  final String code;
  final String hostUserId;
  final PartyMode mode;
  final List<PartyMember> members;
  final PartyVisibility visibility;

  /// 공개방을 연 자리. 메모리 백엔드가 거리를 재는 데 쓰고, 서버에서 오는
  /// 방 JSON에는 없다(남의 좌표는 앱에 닿지 않는다).
  final GeoPoint? location;

  bool get isPublic => visibility == PartyVisibility.public;

  /// When the shared countdown fires. Null once it has been consumed.
  final DateTime? startsAt;

  /// Whose set it is, in [PartyMode.alternating].
  final String? currentTurnUserId;
  final List<OfferedRoutine> routines;

  bool isHost(String userId) => hostUserId == userId;

  PartyMember? memberOf(String userId) {
    for (final member in members) {
      if (member.userId == userId) return member;
    }
    return null;
  }

  /// Seconds until the shared start, or 0 when there is nothing pending.
  int get countdownSeconds {
    final at = startsAt;
    if (at == null) return 0;
    final left = at.difference(DateTime.now()).inMilliseconds;
    return left <= 0 ? 0 : (left / 1000).ceil();
  }

  TrainingParty copyWith({
    PartyMode? mode,
    List<PartyMember>? members,
    PartyVisibility? visibility,
    Object? location = _unset,
    Object? startsAt = _unset,
    Object? currentTurnUserId = _unset,
    List<OfferedRoutine>? routines,
  }) => TrainingParty(
    id: id,
    code: code,
    hostUserId: hostUserId,
    mode: mode ?? this.mode,
    members: members ?? this.members,
    visibility: visibility ?? this.visibility,
    location: location == _unset ? this.location : location as GeoPoint?,
    startsAt: startsAt == _unset ? this.startsAt : startsAt as DateTime?,
    currentTurnUserId: currentTurnUserId == _unset
        ? this.currentTurnUserId
        : currentTurnUserId as String?,
    routines: routines ?? this.routines,
  );
}

class TogetherFailure implements Exception {
  const TogetherFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class TogetherRepository {
  /// Who this client is acting as. Null when signed out — every verb below
  /// needs an account, because a room with an anonymous member has no way to
  /// say whose turn it is.
  String? get currentUserId;

  /// 공개방은 [location]이 있어야 목록에 뜬다. 없으면 어댑터가 비밀방으로
  /// 연다 — 화면이 그렇게 안내한 뒤다.
  Future<TrainingParty> createParty({
    required PartyMode mode,
    PartyVisibility visibility = PartyVisibility.private,
    GeoPoint? location,
  });

  Future<TrainingParty> joinParty(String code);

  /// 근처에서 열린 공개방. 가까운 순, 좌표 없이 거리만.
  Future<List<NearbyParty>> listNearbyParties(GeoPoint at);

  /// 코드 없이 공개방에 들어간다. 비밀방이면 "그런 방이 없어요".
  Future<TrainingParty> joinPublicParty(String partyId);

  /// 방장이 공개/비밀을 바꾼다. 공개로 바꾸려면 [location]이 필요하다.
  Future<TrainingParty> setVisibility({
    required String partyId,
    required PartyVisibility visibility,
    GeoPoint? location,
  });

  Future<void> leaveParty(String partyId);

  /// The room as it changes. Emits the current state immediately on listen so
  /// a screen never has to render an empty frame first.
  Stream<TrainingParty> watchParty(String partyId);

  /// 방 하나를 한 번 읽는다. 없거나 내가 멤버가 아니면 null — 앱을 다시 켠
  /// 사람이 저장해 둔 방으로 돌아갈 수 있는지 묻는 용도다.
  Future<TrainingParty?> fetchParty(String partyId);

  Future<TrainingParty> setMode({
    required String partyId,
    required PartyMode mode,
  });

  /// Arms the shared countdown. [lead] is the head start everyone gets to put
  /// the phone down.
  Future<TrainingParty> startTogether(
    String partyId, {
    Duration lead = const Duration(seconds: 5),
  });

  /// The one verb the whole feature turns on: "I finished a set."
  ///
  /// What it means depends on the mode, and that decision belongs here rather
  /// than in the UI — in [PartyMode.together] everyone drops into the same
  /// rest, in [PartyMode.alternating] the finisher rests and the turn moves on.
  Future<TrainingParty> reportSetDone({
    required String partyId,
    required int restSeconds,
    String? exerciseName,
    int? setNumber,
    int? setTotal,
    double? totalVolume,
  });

  Future<TrainingParty> offerRoutine({
    required String partyId,
    required RoutineData routine,
  });
}

/// The rules, with no network under them.
///
/// This is not only a test double: it is where the party logic actually lives,
/// so the Supabase adapter and any future server implement the *same*
/// behaviour rather than each inventing their own idea of whose turn it is.
class MemoryTogetherBackend {
  MemoryTogetherBackend({Random? random}) : _random = random ?? Random();

  final Random _random;
  final _parties = <String, TrainingParty>{};
  final _controllers = <String, StreamController<TrainingParty>>{};
  var _sequence = 0;

  TrainingParty? partyById(String id) => _parties[id];

  TrainingParty? partyByCode(String code) {
    final normalized = code.trim().toUpperCase();
    for (final party in _parties.values) {
      if (party.code == normalized) return party;
    }
    return null;
  }

  String _nextId(String prefix) => '$prefix-${++_sequence}';

  /// Ambiguous glyphs are left out: someone is going to read this over the
  /// phone, and "0 아니고 O" is not a thing anyone should have to say.
  String _newCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    while (true) {
      final code = List.generate(
        6,
        (_) => alphabet[_random.nextInt(alphabet.length)],
      ).join();
      if (partyByCode(code) == null) return code;
    }
  }

  TrainingParty create({
    required String userId,
    required String displayName,
    required PartyMode mode,
    PartyVisibility visibility = PartyVisibility.private,
    GeoPoint? location,
  }) {
    // 서버와 같은 규칙: 좌표 없는 공개방은 비밀방이다.
    final effective = visibility == PartyVisibility.public && location == null
        ? PartyVisibility.private
        : visibility;
    final party = TrainingParty(
      id: _nextId('party'),
      code: _newCode(),
      hostUserId: userId,
      mode: mode,
      visibility: effective,
      location: effective == PartyVisibility.public ? location : null,
      members: [
        PartyMember(userId: userId, displayName: displayName, turnOrder: 0),
      ],
    );
    _parties[party.id] = party;
    return party;
  }

  /// 반경 안의 공개방, 가까운 순. 내가 이미 든 방과 꽉 찬 방은 뺀다.
  List<NearbyParty> nearby({
    required GeoPoint at,
    required String userId,
    double radiusMeters = 3000,
  }) {
    final rows = <(double, NearbyParty)>[];
    for (final party in _parties.values) {
      final location = party.location;
      if (!party.isPublic || location == null) continue;
      if (party.memberOf(userId) != null) continue;
      if (party.members.length >= maxPartyMembers) continue;
      final distance = at.distanceTo(location);
      if (distance > radiusMeters) continue;
      final host = party.memberOf(party.hostUserId);
      rows.add((
        distance,
        NearbyParty(
          id: party.id,
          hostName: host?.displayName ?? '회원',
          mode: party.mode,
          memberCount: party.members.length,
          distanceMeters: (distance / 10).round() * 10,
          createdAt: DateTime.now(),
        ),
      ));
    }
    rows.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final row in rows.take(20)) row.$2];
  }

  TrainingParty joinPublic({
    required String partyId,
    required String userId,
    required String displayName,
  }) {
    final party = _parties[partyId];
    if (party == null || !party.isPublic) {
      throw const TogetherFailure('그 방은 이제 없어요. 목록을 새로 고쳐 주세요.');
    }
    return join(code: party.code, userId: userId, displayName: displayName);
  }

  TrainingParty setVisibility({
    required String partyId,
    required String userId,
    required PartyVisibility visibility,
    GeoPoint? location,
  }) {
    final party = _require(partyId);
    if (!party.isHost(userId)) {
      throw const TogetherFailure('공개 여부는 방을 만든 사람이 정해요.');
    }
    if (visibility == PartyVisibility.public && location == null) {
      throw const TogetherFailure('공개방으로 바꾸려면 위치가 필요해요.');
    }
    return _publish(
      party.copyWith(
        visibility: visibility,
        location: visibility == PartyVisibility.public ? location : null,
      ),
    );
  }

  TrainingParty join({
    required String code,
    required String userId,
    required String displayName,
  }) {
    final party = partyByCode(code);
    if (party == null) {
      throw const TogetherFailure('그런 코드의 방이 없어요. 다시 확인해주세요.');
    }
    if (!party.members.any((m) => m.userId == userId) &&
        party.members.length >= maxPartyMembers) {
      throw const TogetherFailure('방이 가득 찼어요. 한 방에는 최대 6명까지예요.');
    }
    if (party.memberOf(userId) != null) return party;
    final members = [
      ...party.members,
      PartyMember(
        userId: userId,
        displayName: displayName,
        turnOrder: party.members.length,
      ),
    ];
    return _publish(party.copyWith(members: members));
  }

  TrainingParty leave({required String partyId, required String userId}) {
    final party = _require(partyId);
    final members = party.members
        .where((member) => member.userId != userId)
        .toList();
    // The turn cannot sit with someone who walked out, or the room stalls
    // waiting for a phone that is no longer listening.
    final turn = party.currentTurnUserId == userId
        ? (members.isEmpty ? null : members.first.userId)
        : party.currentTurnUserId;
    final updated = party.copyWith(members: members, currentTurnUserId: turn);
    if (members.isEmpty) {
      _parties.remove(partyId);
      _publish(updated);
      return updated;
    }
    return _publish(updated);
  }

  TrainingParty setMode({required String partyId, required PartyMode mode}) {
    final party = _require(partyId);
    return _publish(
      party.copyWith(
        mode: mode,
        // Switching the rule mid-room would otherwise leave a turn pointer from
        // the old rule pointing at someone the new rule never chose.
        currentTurnUserId: null,
        members: party.members
            .map(
              (member) => member.copyWith(
                state: PartyMemberState.waiting,
                restEndsAt: null,
              ),
            )
            .toList(),
      ),
    );
  }

  TrainingParty start({
    required String partyId,
    required Duration lead,
    DateTime? now,
  }) {
    final party = _require(partyId);
    final at = (now ?? DateTime.now()).add(lead);
    final first = party.members.isEmpty
        ? null
        : (party.members.toList()
                ..sort((a, b) => a.turnOrder.compareTo(b.turnOrder)))
              .first;
    return _publish(
      party.copyWith(
        startsAt: at,
        // In alternating the countdown belongs to whoever lifts first, so the
        // turn is decided before the clock starts rather than at zero.
        currentTurnUserId: party.mode == PartyMode.alternating
            ? first?.userId
            : null,
        members: party.members
            .map(
              (member) => member.copyWith(
                state:
                    party.mode == PartyMode.together ||
                        member.userId == first?.userId
                    ? PartyMemberState.lifting
                    : PartyMemberState.resting,
                restEndsAt: null,
              ),
            )
            .toList(),
      ),
    );
  }

  TrainingParty reportSetDone({
    required String partyId,
    required String userId,
    required int restSeconds,
    String? exerciseName,
    int? setNumber,
    int? setTotal,
    double? totalVolume,
    DateTime? now,
  }) {
    final party = _require(partyId);
    final at = (now ?? DateTime.now()).add(Duration(seconds: restSeconds));
    final ordered = party.members.toList()
      ..sort((a, b) => a.turnOrder.compareTo(b.turnOrder));

    if (party.mode == PartyMode.free) {
      // 각자: 보고자만 휴식에 들어간다. 남의 시계는 남의 것이다.
      return _publish(
        party.copyWith(
          members: party.members
              .map(
                (member) => member.userId == userId
                    ? member.copyWith(
                        state: PartyMemberState.resting,
                        restEndsAt: at,
                        completedSets: member.completedSets + 1,
                        currentExercise: exerciseName,
                        currentSetNumber: setNumber,
                        currentSetTotal: setTotal,
                        totalVolume: totalVolume,
                      )
                    : member,
              )
              .toList(),
        ),
      );
    }

    if (party.mode == PartyMode.together) {
      return _publish(
        party.copyWith(
          startsAt: null,
          members: party.members
              .map(
                (member) => member.copyWith(
                  state: PartyMemberState.resting,
                  restEndsAt: at,
                  completedSets: member.userId == userId
                      ? member.completedSets + 1
                      : member.completedSets,
                  currentExercise: member.userId == userId
                      ? exerciseName
                      : null,
                  currentSetNumber: member.userId == userId ? setNumber : null,
                  currentSetTotal: member.userId == userId ? setTotal : null,
                  totalVolume: member.userId == userId ? totalVolume : null,
                ),
              )
              .toList(),
        ),
      );
    }

    // Alternating: the finisher rests, the next in the rotation lifts. Their
    // rest ends the moment the handover happens, which is the whole point --
    // "you're up" arrives instead of a countdown they have to watch.
    final index = ordered.indexWhere((member) => member.userId == userId);
    final next = ordered.isEmpty
        ? null
        : ordered[(index < 0 ? 0 : index + 1) % ordered.length];
    return _publish(
      party.copyWith(
        startsAt: null,
        currentTurnUserId: next?.userId,
        members: party.members.map((member) {
          if (member.userId == userId) {
            return member.copyWith(
              state: PartyMemberState.resting,
              restEndsAt: at,
              completedSets: member.completedSets + 1,
              currentExercise: exerciseName,
              currentSetNumber: setNumber,
              currentSetTotal: setTotal,
              totalVolume: totalVolume,
            );
          }
          if (member.userId == next?.userId) {
            return member.copyWith(
              state: PartyMemberState.lifting,
              restEndsAt: null,
            );
          }
          return member;
        }).toList(),
      ),
    );
  }

  TrainingParty offerRoutine({
    required String partyId,
    required String userId,
    required String senderName,
    required RoutineData routine,
    DateTime? now,
  }) {
    final party = _require(partyId);
    return _publish(
      party.copyWith(
        routines: [
          OfferedRoutine(
            id: _nextId('offer'),
            senderUserId: userId,
            senderName: senderName,
            routine: routine,
            offeredAt: now ?? DateTime.now(),
          ),
          ...party.routines,
        ],
      ),
    );
  }

  Stream<TrainingParty> watch(String partyId) async* {
    final controller = _controllers.putIfAbsent(
      partyId,
      () => StreamController<TrainingParty>.broadcast(),
    );
    // The room as it stands goes out before any change does, so a screen never
    // renders an empty frame it would immediately replace.
    final current = _parties[partyId];
    if (current != null) yield current;
    yield* controller.stream;
  }

  TrainingParty _require(String partyId) {
    final party = _parties[partyId];
    if (party == null) throw const TogetherFailure('방이 이미 닫혔어요.');
    return party;
  }

  TrainingParty _publish(TrainingParty party) {
    if (_parties.containsKey(party.id) || party.members.isNotEmpty) {
      _parties[party.id] = party;
    }
    _controllers[party.id]?.add(party);
    return party;
  }

  void dispose() {
    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
  }
}

/// One person's client onto a [MemoryTogetherBackend].
///
/// Tests build two of these over one backend to play both sides of a room; the
/// demo build uses a single one so the screen is explorable without a server.
class MemoryTogetherRepository implements TogetherRepository {
  MemoryTogetherRepository({
    required this.backend,
    required String? userId,
    this.displayName = '나',
  }) : currentUserId = userId;

  final MemoryTogetherBackend backend;
  final String displayName;

  @override
  final String? currentUserId;

  String get _requireUser {
    final id = currentUserId;
    if (id == null) throw const TogetherFailure('함께 운동하려면 로그인이 필요해요.');
    return id;
  }

  @override
  Future<TrainingParty> createParty({
    required PartyMode mode,
    PartyVisibility visibility = PartyVisibility.private,
    GeoPoint? location,
  }) async => backend.create(
    userId: _requireUser,
    displayName: displayName,
    mode: mode,
    visibility: visibility,
    location: location,
  );

  @override
  Future<TrainingParty> joinParty(String code) async =>
      backend.join(code: code, userId: _requireUser, displayName: displayName);

  @override
  Future<List<NearbyParty>> listNearbyParties(GeoPoint at) async =>
      backend.nearby(at: at, userId: _requireUser);

  @override
  Future<TrainingParty> joinPublicParty(String partyId) async =>
      backend.joinPublic(
        partyId: partyId,
        userId: _requireUser,
        displayName: displayName,
      );

  @override
  Future<TrainingParty> setVisibility({
    required String partyId,
    required PartyVisibility visibility,
    GeoPoint? location,
  }) async => backend.setVisibility(
    partyId: partyId,
    userId: _requireUser,
    visibility: visibility,
    location: location,
  );

  @override
  Future<void> leaveParty(String partyId) async =>
      backend.leave(partyId: partyId, userId: _requireUser);

  @override
  Stream<TrainingParty> watchParty(String partyId) => backend.watch(partyId);

  @override
  Future<TrainingParty> setMode({
    required String partyId,
    required PartyMode mode,
  }) async => backend.setMode(partyId: partyId, mode: mode);

  @override
  Future<TrainingParty> startTogether(
    String partyId, {
    Duration lead = const Duration(seconds: 5),
  }) async => backend.start(partyId: partyId, lead: lead);

  @override
  Future<TrainingParty?> fetchParty(String partyId) async {
    final party = backend.partyById(partyId);
    if (party == null || party.memberOf(_requireUser) == null) return null;
    return party;
  }

  @override
  Future<TrainingParty> reportSetDone({
    required String partyId,
    required int restSeconds,
    String? exerciseName,
    int? setNumber,
    int? setTotal,
    double? totalVolume,
  }) async => backend.reportSetDone(
    partyId: partyId,
    userId: _requireUser,
    restSeconds: restSeconds,
    exerciseName: exerciseName,
    setNumber: setNumber,
    setTotal: setTotal,
    totalVolume: totalVolume,
  );

  @override
  Future<TrainingParty> offerRoutine({
    required String partyId,
    required RoutineData routine,
  }) async => backend.offerRoutine(
    partyId: partyId,
    userId: _requireUser,
    senderName: displayName,
    routine: routine,
  );
}
