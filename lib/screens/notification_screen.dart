import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/notification_repository.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/common.dart';
import 'welcome_screen.dart';

/// 홈 헤더 오른쪽 위의 알림함 버튼.
///
/// 런처 아이콘의 배지는 시스템 알림창이 세는 것이라, 알림을 밀어 지우면
/// 배지만 남고 앱에는 흔적이 없었다. 이 문 뒤에 그 흔적이 있다.
/// 안 읽은 것이 있으면 글리프가 채워지고 라임 점이 붙는다 — 숫자는 쓰지 않는다.
/// 몇 개인지는 들어가면 보이고, 헤더에서 답할 질문은 "볼 게 있나"뿐이다.
class NotificationHeaderButton extends StatelessWidget {
  const NotificationHeaderButton({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final unread = state.unreadNotificationCount > 0;
    return IconButton(
      key: const ValueKey('home-notifications'),
      tooltip: unread ? '알림 (읽지 않음 있음)' : '알림',
      visualDensity: VisualDensity.compact,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            unread
                ? SetflowIcons.notificationsActive
                : SetflowIcons.notifications,
            size: 22,
          ),
          if (unread)
            // 글리프는 상자보다 작아서 -1로 두면 점이 종에서 떠 보인다.
            Positioned(
              right: 2,
              top: 1,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: SetflowColors.brand,
                  shape: BoxShape.circle,
                  // 라임 점이 아이콘 획에 붙어 뭉쳐 보이지 않게 바탕색으로 띄운다.
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const NotificationScreen())),
    );
  }
}

/// 알림함 — "무슨 알림이었지"에 답하는 화면.
///
/// 런처 아이콘의 배지는 시스템 알림창에 남은 우리 알림 수라서, 알림을 밀어
/// 지우면 배지만 남고 앱에는 흔적이 없었다(실기기 보고: "알림 표기가 있는 것
/// 같은데 들어가면 무슨 알림인지 모르겠네"). 여기가 그 흔적이다.
///
/// 누르면 시스템 알림을 누른 것과 **같은 곳**으로 간다 — 목적지를 두 벌로
/// 관리하지 않으려고 [AppNotification.toPushOpen]으로 같은 경로를 태운다.
class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  @override
  void initState() {
    super.initState();
    // 화면을 여는 것이 곧 새로고침이다. 헤더의 점은 수만 알고 목록은 모른다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.of(context).refreshNotifications();
    });
  }

  Future<void> _open(AppState state, AppNotification notification) async {
    await state.markNotificationRead(notification.id);
    if (!mounted) return;
    // 알림함을 닫고 나서 이동한다 — 시스템 알림을 누른 것과 같은 결과가 되고,
    // 뒤로가기가 목적지 위의 알림함으로 되돌아오는 이상한 길이 생기지 않는다.
    Navigator.of(context).pop();
    state.openPush(notification.toPushOpen());
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final signedIn = Auth.instance.hasAuthenticatedUser;
    final hasUnread = state.notifications.any((item) => item.isUnread);

    return Scaffold(
      appBar: AppBar(
        title: const Text('알림'),
        actions: [
          if (signedIn && hasUnread)
            TextButton(
              key: const ValueKey('notifications-mark-all'),
              onPressed: state.markAllNotificationsRead,
              child: const Text('모두 읽음'),
            ),
        ],
      ),
      body: _body(context, state, signedIn),
    );
  }

  Widget _body(BuildContext context, AppState state, bool signedIn) {
    // 알림은 계정에 붙는다. 게스트에게 빈 목록을 보여 주면 "알림이 없다"로
    // 읽히는데, 사실은 받을 수가 없는 것이다.
    if (!signedIn) {
      return EmptyState(
        icon: SetflowIcons.notifications,
        title: '로그인하면 알림이 쌓여요',
        message: '코칭 답변, 함께 운동 방 소식, 커뮤니티 반응을 여기서 다시 볼 수 있어요.',
        actionLabel: '로그인',
        onAction: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const WelcomeScreen())),
      );
    }
    if (state.notificationsLoading && state.notifications.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.notificationsError != null && state.notifications.isEmpty) {
      return ErrorState(
        message: '알림을 불러오지 못했어요. 잠시 후 다시 시도해주세요.',
        onRetry: state.refreshNotifications,
      );
    }
    if (state.notifications.isEmpty) {
      return const EmptyState(
        icon: SetflowIcons.notifications,
        title: '받은 알림이 없어요',
        message: '코칭 답변이나 함께 운동 방 소식이 도착하면 여기에 남아요.',
      );
    }
    return RefreshIndicator(
      onRefresh: state.refreshNotifications,
      child: ListView.separated(
        padding: SetflowInsets.pageList,
        itemCount: state.notifications.length,
        separatorBuilder: (_, _) => const SizedBox(height: SetflowSpacing.sm),
        itemBuilder: (context, index) {
          final notification = state.notifications[index];
          return _NotificationTile(
            notification: notification,
            onTap: () => _open(state, notification),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.setflowColors;
    final unread = notification.isUnread;

    return Material(
      // 안 읽은 것은 브랜드 틴트로 깔린다. 라임은 채우는 색이라 글자 아래
      // 배경으로만 쓰고, 글자는 그대로 잉크다.
      color: unread ? colors.brandSoft : theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(SetflowRadii.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(SetflowSpacing.md2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  _iconFor(notification.kind),
                  size: 20,
                  color: unread
                      ? colors.brandDeep
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: SetflowSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: unread
                            ? SetflowWeight.strong
                            : SetflowWeight.medium,
                      ),
                    ),
                    const SizedBox(height: SetflowSpacing.xxs),
                    Text(notification.body, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: SetflowSpacing.xs),
                    Text(
                      relativeNotificationTime(notification.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (unread) ...[
                const SizedBox(width: SetflowSpacing.sm),
                // 안 읽음 표시. 글자를 쓰지 않는 자리라 라임을 그대로 채운다.
                Semantics(
                  label: '읽지 않음',
                  child: Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 6),
                    decoration: const BoxDecoration(
                      color: SetflowColors.brand,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String kind) => switch (kind) {
    'coaching_feedback' => SetflowIcons.coaching,
    'community_reaction' => SetflowIcons.community,
    'together' => SetflowIcons.together,
    'workout_reminder' => SetflowIcons.record,
    'business' || 'business_activity' => SetflowIcons.pro,
    _ => SetflowIcons.notifications,
  };
}

/// "언제 왔는지"를 사람 말로. 알림함은 훑는 화면이라 정확한 시각보다
/// 얼마나 오래됐는지가 먼저다.
String relativeNotificationTime(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final elapsed = reference.difference(time);
  if (elapsed.inMinutes < 1) return '방금';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}분 전';
  if (elapsed.inDays < 1) return '${elapsed.inHours}시간 전';
  if (elapsed.inDays < 7) return '${elapsed.inDays}일 전';
  return '${time.month}월 ${time.day}일';
}
