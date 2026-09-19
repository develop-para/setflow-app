import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import 'account_profile_repository.dart';

class SupabaseAccountProfileRepository implements AccountProfileRepository {
  const SupabaseAccountProfileRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<AccountProfile> loadMyProfile() => _request('get_my_account_profile');

  @override
  Future<AccountProfile> saveMyBirthDate(DateTime? birthDate) => _request(
    'save_my_account_birth_date',
    params: {
      'p_birth_date': birthDate == null
          ? null
          : AccountBirthDate.format(birthDate),
    },
  );

  Future<AccountProfile> _request(
    String operation, {
    Map<String, dynamic>? params,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthFailure('로그인 후 이용해주세요.');
    final result = await _client
        .rpc(operation, params: params)
        .timeout(const Duration(seconds: 15));
    if (result is! Map ||
        result['user_id'] != userId ||
        _client.auth.currentUser?.id != userId) {
      throw const AuthFailure('계정이 바뀌었어요. 다시 열어주세요.');
    }
    final birthDate = result['birth_date'];
    return AccountProfile(
      userId: userId,
      email: result['email'] as String?,
      providers: Set.unmodifiable(
        (result['providers'] as List? ?? const []).whereType<String>(),
      ),
      birthDate: birthDate == null
          ? null
          : AccountBirthDate.parse(birthDate as String),
    );
  }
}
