import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
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
/// **[watchParty] polls, and that is an implementation detail.** The port
/// promises a stream of rooms, not a subscription, so this can move to Realtime
/// later without a single screen changing. Polling is survivable here only
/// because the payload carries *instants*: a poll that arrives 1.5s late still
/// shows a rest ending at the same wall-clock moment as everyone else's, so the
/// lag costs you awareness, never synchrony. See `docs/backend-portability.md`.
class SupabaseTogetherRepository implements TogetherRepository {
  SupabaseTogetherRepository(
    this._client, {
    required this.exerciseCatalog,
    this.pollInterval = const Duration(seconds: 2),
  });

  final SupabaseClient _client;
  final Duration pollInterval;

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
    if (message.contains('not a member')) return '이 방에서 나간 상태예요.';
    if (message.contains('auth required')) return '함께 운동하려면 로그인이 필요해요.';
    return '지금은 연결이 어려워요. 잠시 후 다시 시도해주세요.';
  }

  @override
  Future<TrainingParty> createParty({required PartyMode mode}) => _rpc(
    'create_training_party',
    {'p_mode': mode.name, 'p_display_name': _displayName},
  );

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
  }) => _rpc('report_training_party_set', {
    'p_party_id': partyId,
    'p_rest_seconds': restSeconds,
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
  Stream<TrainingParty> watchParty(String partyId) async* {
    while (true) {
      try {
        final result = await _client.rpc<Object?>(
          'get_training_party',
          params: {'p_party_id': partyId},
        );
        final party = _partyFrom(result);
        // A null room means it closed or we were removed. Ending the stream
        // lets the screen fall back to the lobby instead of polling a room
        // that no longer exists.
        if (party == null) return;
        yield party;
      } catch (_) {
        // A dropped poll is not a dropped room. Keep the last state on screen
        // and try again — a transient 500 must not eject someone mid-workout.
      }
      await Future<void>.delayed(pollInterval);
    }
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
