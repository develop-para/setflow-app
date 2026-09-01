import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../services/setflow_web.dart';
import 'app_snapshot_codec.dart';
import 'together_repository.dart';

/// The Supabase adapter for [TogetherRepository].
///
/// Two things are worth knowing before changing anything here.
///
/// **Every write is an RPC, on purpose.** The tables carry no write policies at
/// all, so a client cannot set `current_turn_user_id` even if it wanted to.
/// That is what makes "the turn is decided once, on the server" a property of
/// the system rather than a convention the app agrees to follow.
///
/// **[watchParty] rides Realtime, with a keepalive poll underneath.** The port
/// promises a stream of rooms, not a subscription — which is exactly why this
/// could move from 2s polling to a websocket without a single screen changing.
/// Every mutating RPC broadcasts the whole room to the private `party:<id>`
/// channel (`realtime.send`, authorised by an RLS policy on
/// realtime.messages), so a partner's set shows up the moment it lands.
///
/// The poll did not disappear; it slowed down into a safety net. A dropped
/// websocket, a missed message, or a cold Realtime service (its first-ever
/// connection is what creates the messages partitions) all self-heal within
/// one keepalive tick — and because the payload carries *instants*, a late
/// arrival still counts down to the same wall-clock moment as everyone else.
/// See `docs/backend-portability.md`.
class SupabaseTogetherRepository implements TogetherRepository {
  SupabaseTogetherRepository(
    this._client, {
    required this.exerciseCatalog,
    this.pollInterval = const Duration(seconds: 10),
    this.nearbyPollInterval = const Duration(seconds: 15),
  });

  final SupabaseClient _client;

  /// Keepalive cadence, not the update path — broadcasts carry the updates.
  final Duration pollInterval;

  /// 근처 목록 스트림의 폴 주기. 방과 달리 "근처"는 서버가 좌표로 계산하는
  /// 조회라 방마다 있는 브로드캐스트 채널이 없다 — 그래서 이 스트림은 순수
  /// 폴링이고, 로비가 화면에 있는 동안만 구독되므로 방 안에서는 돌지 않는다.
  final Duration nearbyPollInterval;

  /// Needed to turn an offered routine back into templates this device knows.
  final List<ExerciseTemplate> exerciseCatalog;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  String get _displayName {
    final metadata = _client.auth.currentUser?.userMetadata;
    for (final value in [metadata?['nickname'], metadata?['name']]) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return _client.auth.currentUser?.email?.split('@').first ?? '회원';
  }

  Future<TrainingParty> _rpc(String name, Map<String, dynamic> params) async {
    try {
      final result = await _client.rpc<Object?>(name, params: params);
      final party = _partyFrom(result);
      if (party == null) throw const TogetherFailure('방 정보를 불러오지 못했어요.');
      return party;
    } on PostgrestException catch (error) {
      throw TogetherFailure(_messageFor(error));
    }
  }

  String _messageFor(PostgrestException error) {
    final message = error.message.toLowerCase();
    if (message.contains('party not found')) {
      return '그런 코드의 방이 없어요. 다시 확인해주세요.';
    }
    if (message.contains('party full')) {
      return '방이 가득 찼어요. 한 방에는 최대 6명까지예요.';
    }
    if (message.contains('not a member')) return '이 방에서 나간 상태예요.';
    if (message.contains('not the host')) return '공개 여부는 방을 만든 사람이 정해요.';
    if (message.contains('location required')) return '공개방으로 바꾸려면 위치가 필요해요.';
    if (message.contains('auth required')) return '함께 운동하려면 로그인이 필요해요.';
    return '지금은 연결이 어려워요. 잠시 후 다시 시도해주세요.';
  }

  @override
  Future<TrainingParty> createParty({
    required PartyMode mode,
    PartyVisibility visibility = PartyVisibility.private,
    GeoPoint? location,
  }) => _rpc('create_training_party', {
    'p_mode': mode.name,
    'p_display_name': _displayName,
    'p_visibility': visibility.name,
    'p_lat': location?.lat,
    'p_lng': location?.lng,
  });

  @override
  Future<List<NearbyParty>> listNearbyParties(GeoPoint at) async {
    try {
      final result = await _client.rpc<Object?>(
        'list_nearby_training_parties',
        params: {'p_lat': at.lat, 'p_lng': at.lng},
      );
      return [
        for (final raw in (result as List? ?? const []))
          if (raw is Map) ?_nearbyFrom(Map<String, dynamic>.from(raw)),
      ];
    } on PostgrestException catch (error) {
      throw TogetherFailure(_messageFor(error));
    }
  }

  @override
  Stream<List<NearbyParty>> watchNearbyParties(GeoPoint at) {
    final controller = StreamController<List<NearbyParty>>();
    Timer? poll;
    var fetching = false;

    Future<void> fetch() async {
      if (fetching || controller.isClosed) return;
      fetching = true;
      try {
        final rooms = await listNearbyParties(at);
        if (!controller.isClosed) controller.add(rooms);
      } catch (error, stackTrace) {
        // 한 번의 실패로 스트림을 닫지 않는다 — 다음 폴이 스스로 회복한다.
        if (!controller.isClosed) controller.addError(error, stackTrace);
      } finally {
        fetching = false;
      }
    }

    controller.onListen = () {
      // The port promises the current list immediately on listen.
      unawaited(fetch());
      poll = Timer.periodic(nearbyPollInterval, (_) => fetch());
    };
    controller.onCancel = () {
      poll?.cancel();
      unawaited(controller.close());
    };
    return controller.stream;
  }

  @override
  Future<TrainingParty> joinPublicParty(String partyId) => _rpc(
    'join_public_training_party',
    {'p_party_id': partyId, 'p_display_name': _displayName},
  );

  @override
  Future<TrainingParty> setVisibility({
    required String partyId,
    required PartyVisibility visibility,
    GeoPoint? location,
  }) => _rpc('set_training_party_visibility', {
    'p_party_id': partyId,
    'p_visibility': visibility.name,
    'p_lat': location?.lat,
    'p_lng': location?.lng,
  });

  NearbyParty? _nearbyFrom(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null) return null;
    return NearbyParty(
      id: id,
      hostName: json['host_name'] as String? ?? '회원',
      mode: PartyMode.values.firstWhere(
        (value) => value.name == json['mode'],
        orElse: () => PartyMode.together,
      ),
      memberCount: (json['member_count'] as num?)?.toInt() ?? 1,
      distanceMeters: (json['distance_m'] as num?)?.toInt() ?? 0,
      createdAt: _time(json['created_at']) ?? DateTime.now(),
    );
  }

  /// https 착지 페이지(`web/join.html`) — 열리면 커스텀 스킴으로 넘겨주고,
  /// 앱이 없으면 코드를 보여 준다. 메신저에서 눌리는 링크는 https뿐이라서다.
  /// 안드로이드는 assetlinks 검증이 되면 브라우저 없이 앱이 바로 받는다.
  @override
  Uri inviteLink(String code) => SetflowWeb.togetherJoin(code);

  @override
  Future<TrainingParty> joinParty(String code) => _rpc('join_training_party', {
    'p_code': code.trim().toUpperCase(),
    'p_display_name': _displayName,
  });

  @override
  Future<void> leaveParty(String partyId) async {
    await _client.rpc<Object?>(
      'leave_training_party',
      params: {'p_party_id': partyId},
    );
  }

  @override
  Future<TrainingParty> setMode({
    required String partyId,
    required PartyMode mode,
  }) => _rpc('set_training_party_mode', {
    'p_party_id': partyId,
    'p_mode': mode.name,
  });

  @override
  Future<TrainingParty> startTogether(
    String partyId, {
    Duration lead = const Duration(seconds: 5),
  }) => _rpc('start_training_party', {
    'p_party_id': partyId,
    'p_lead_seconds': lead.inSeconds,
  });

  @override
  Future<TrainingParty> reportSetDone({
    required String partyId,
    required int restSeconds,
    String? exerciseName,
    int? setNumber,
    int? setTotal,
    double? totalVolume,
  }) => _rpc('report_training_party_set', {
    'p_party_id': partyId,
    'p_rest_seconds': restSeconds,
    'p_exercise': ?exerciseName,
    'p_set_number': ?setNumber,
    'p_set_total': ?setTotal,
    'p_volume': ?totalVolume,
  });

  @override
  Future<TrainingParty> offerRoutine({
    required String partyId,
    required RoutineData routine,
  }) => _rpc('offer_training_party_routine', {
    'p_party_id': partyId,
    'p_name': routine.name,
    'p_payload': AppSnapshotCodec.routineToJson(routine),
    'p_sender_name': _displayName,
  });

  @override
  Future<TrainingParty?> fetchParty(String partyId) async {
    try {
      final result = await _client.rpc<Object?>(
        'get_training_party',
        params: {'p_party_id': partyId},
      );
      return _partyFrom(result);
    } on PostgrestException {
      return null;
    }
  }

  @override
  Stream<TrainingParty> watchParty(String partyId) {
    final controller = StreamController<TrainingParty>();
    RealtimeChannel? channel;
    Timer? keepalive;
    var closed = false;

    void close() {
      if (closed) return;
      closed = true;
      keepalive?.cancel();
      final open = channel;
      channel = null;
      if (open != null) unawaited(_client.removeChannel(open));
      unawaited(controller.close());
    }

    Future<void> fetch() async {
      if (closed) return;
      try {
        final result = await _client.rpc<Object?>(
          'get_training_party',
          params: {'p_party_id': partyId},
        );
        if (closed) return;
        final party = _partyFrom(result);
        // A null room means it closed or we were removed. Ending the stream
        // lets the screen fall back to the lobby instead of watching a room
        // that no longer exists.
        if (party == null) {
          close();
        } else {
          controller.add(party);
        }
      } catch (_) {
        // A dropped fetch is not a dropped room. Keep the last state on screen
        // — a transient 500 must not eject someone mid-workout.
      }
    }

    controller.onListen = () {
      channel =
          _client.channel(
              'party:$partyId',
              opts: const RealtimeChannelConfig(private: true),
            )
            ..onBroadcast(
              event: 'party',
              callback: (payload) {
                if (closed) return;
                // realtime.send 페이로드는 그대로 오지만, 클라이언트 발신 형태로
                // 한 겹 싸여 올 가능성도 방어한다.
                final body = payload.containsKey('party')
                    ? payload
                    : (payload['payload'] is Map
                          ? Map<String, dynamic>.from(payload['payload'] as Map)
                          : const <String, dynamic>{});
                if (!body.containsKey('party')) return;
                final raw = body['party'];
                if (raw == null) {
                  // 방이 닫혔다는 서버의 마지막 인사.
                  close();
                  return;
                }
                final party = _partyFrom(raw);
                if (party != null) controller.add(party);
              },
            )
            ..subscribe();
      // The port promises the current state immediately on listen, and the
      // keepalive heals anything the socket missed.
      unawaited(fetch());
      keepalive = Timer.periodic(pollInterval, (_) => fetch());
    };
    controller.onCancel = close;
    return controller.stream;
  }

  TrainingParty? _partyFrom(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final id = json['id'] as String?;
    final code = json['code'] as String?;
    if (id == null || code == null) return null;

    return TrainingParty(
      id: id,
      code: code,
      hostUserId: json['host_user_id'] as String? ?? '',
      mode: PartyMode.values.firstWhere(
        (value) => value.name == json['mode'],
        orElse: () => PartyMode.together,
      ),
      visibility: json['visibility'] == 'public'
          ? PartyVisibility.public
          : PartyVisibility.private,
      startsAt: _time(json['starts_at']),
      currentTurnUserId: json['current_turn_user_id'] as String?,
      members: [
        for (final raw in (json['members'] as List? ?? const []))
          if (raw is Map) _memberFrom(Map<String, dynamic>.from(raw)),
      ],
      routines: [
        for (final raw in (json['routines'] as List? ?? const []))
          if (raw is Map) ?_offerFrom(Map<String, dynamic>.from(raw)),
      ],
    );
  }

  PartyMember _memberFrom(Map<String, dynamic> json) => PartyMember(
    userId: json['user_id'] as String? ?? '',
    displayName: json['display_name'] as String? ?? '회원',
    state: PartyMemberState.values.firstWhere(
      (value) => value.name == json['state'],
      orElse: () => PartyMemberState.waiting,
    ),
    restEndsAt: _time(json['rest_ends_at']),
    completedSets: (json['completed_sets'] as num?)?.toInt() ?? 0,
    turnOrder: (json['turn_order'] as num?)?.toInt() ?? 0,
    currentExercise: json['current_exercise'] as String?,
    currentSetNumber: (json['current_set_number'] as num?)?.toInt(),
    currentSetTotal: (json['current_set_total'] as num?)?.toInt(),
    totalVolume: (json['total_volume'] as num?)?.toDouble() ?? 0,
  );

  OfferedRoutine? _offerFrom(Map<String, dynamic> json) {
    final payload = json['payload'];
    if (payload is! Map) return null;
    final routine = AppSnapshotCodec.routineFromJson(
      Map<String, dynamic>.from(payload),
      exerciseCatalog,
    );
    if (routine == null) return null;
    return OfferedRoutine(
      id: json['id'] as String? ?? routine.id,
      senderUserId: json['sender_user_id'] as String? ?? '',
      senderName: json['sender_name'] as String? ?? '회원',
      routine: routine,
      offeredAt: _time(json['created_at']) ?? DateTime.now(),
    );
  }

  /// Server times arrive as UTC strings and are compared against the device
  /// clock, so they have to come back as local — a rest ending "at 09:00Z"
  /// counted against local noon would read as nine hours of rest.
  DateTime? _time(Object? value) {
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }
}
