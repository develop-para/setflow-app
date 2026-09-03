import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_repository.dart';

/// [NotificationRepository]의 Supabase 어댑터.
///
/// 줄은 `private.enqueue_push`가 넣는다 — 앱은 읽고 "읽었다"만 찍는다.
/// RLS가 내 것만 보여 주므로 쿼리에 user_id 조건을 따로 걸지 않는다.
class SupabaseNotificationRepository implements NotificationRepository {
  SupabaseNotificationRepository(this._client);

  static const _table = 'user_notifications';
  static const _columns = 'id,kind,title,body,data,created_at,read_at';

  final SupabaseClient _client;

  bool get _signedIn => _client.auth.currentUser != null;

  @override
  Future<List<AppNotification>> listNotifications({int limit = 100}) async {
    // 계정이 없으면 서버에 내 알림이 있을 수 없다. 요청을 보내 봐야 빈 목록이다.
    if (!_signedIn) return const [];
    final rows = await _client
        .from(_table)
        .select(_columns)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(_toNotification).toList(growable: false);
  }

  @override
  Future<int> unreadCount() async {
    if (!_signedIn) return 0;
    final rows = await _client
        .from(_table)
        .select('id')
        .isFilter('read_at', null)
        // 배지는 수를 정확히 세는 것이 목적이 아니라 "있다"를 알리는 것이다.
        // 상한을 두면 알림이 수백 개 쌓인 계정에서도 쿼리가 가볍다.
        .limit(99);
    return rows.length;
  }

  @override
  Future<void> markRead(String id) async {
    if (!_signedIn) return;
    final numericId = int.tryParse(id);
    if (numericId == null) return;
    await _client
        .from(_table)
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', numericId)
        // 두 번 눌러도 처음 읽은 시각이 남는다.
        .isFilter('read_at', null);
  }

  @override
  Future<void> markAllRead() async {
    if (!_signedIn) return;
    await _client
        .from(_table)
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .isFilter('read_at', null);
  }

  AppNotification _toNotification(Map<String, dynamic> row) {
    final rawData = row['data'];
    return AppNotification(
      id: '${row['id']}',
      kind: row['kind'] as String? ?? 'account',
      title: row['title'] as String? ?? '',
      body: row['body'] as String? ?? '',
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      // FCM data는 전부 문자열이라 서버도 문자열로 넣는다. 그래도 숫자가 섞여
      // 들어오면 화면이 던지지 않게 여기서 문자열로 맞춘다.
      data: rawData is Map
          ? {
              for (final entry in rawData.entries)
                '${entry.key}': '${entry.value}',
            }
          : const {},
      readAt: DateTime.tryParse(row['read_at'] as String? ?? '')?.toLocal(),
    );
  }
}
