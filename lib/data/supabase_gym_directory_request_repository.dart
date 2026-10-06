import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/gym_directory.dart';
import 'gym_directory_repository.dart';

class SupabaseGymDirectoryRequestRepository
    implements GymDirectoryRequestRepository {
  SupabaseGymDirectoryRequestRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _client.rpc('gym_directory_request_service_available') ==
          true;
    } catch (_) {
      // An undeployed endpoint, expired session or unavailable network leaves
      // the device draft usable. It must never be described as a sent request.
      return false;
    }
  }

  @override
  Future<DateTime> submitRequest(GymDirectoryRequest request) async {
    request.validate();
    final user = _client.auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('제안을 보내려면 로그인해주세요.');
    }
    final ownerId = user.id;
    if (request.ownerUserId != null && request.ownerUserId != ownerId) {
      throw StateError('다른 계정에 보관된 제안은 보낼 수 없어요.');
    }
    final result = await _client.rpc(
      'submit_gym_directory_request',
      params: {
        'request_id': request.id,
        'request_kind': request.kind.name,
        'facility_id': request.facilityId?.trim(),
        'gym_name': request.gymName.trim(),
        'address': request.address.trim(),
        'note': request.note.trim(),
      },
    );
    // Verify against the owner captured before sending. AppState durably binds
    // that owner first, so a late receipt can be retained for them after an
    // account switch without exposing it to the new account.
    if (result is! Map ||
        result['id'] != request.id ||
        result['owner_user_id'] != ownerId ||
        result['submitted_at'] is! String) {
      throw const FormatException('서버의 제안 접수 정보를 확인할 수 없어요.');
    }
    final submittedAt = DateTime.tryParse(result['submitted_at'] as String);
    if (submittedAt == null) {
      throw const FormatException('서버의 제안 접수 시각을 확인할 수 없어요.');
    }
    return submittedAt;
  }
}
