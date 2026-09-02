import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../services/push_service.dart';
import '../data/business_repository.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/common.dart';
import '../widgets/portal.dart';
import '../widgets/recommendation_profile_summary.dart';
import 'admin_content_screens.dart';
import 'admin_system_screens.dart';
import 'business_detail_screens.dart';
import 'business_routine_flow_screens.dart';
import 'business_settings_screens.dart';
import 'consultation_retarget_screen.dart';
import 'member_detail_screens.dart';
import 'settlement_detail_screens.dart';
import 'stats_detail_screens.dart';
import 'workspace_screen.dart';

class BusinessShell extends StatefulWidget {
  const BusinessShell({required this.role, super.key});
  final UserRole role;

  @override
  State<BusinessShell> createState() => _BusinessShellState();
}

/// pro 셸 헤더의 "회원 화면" — 회원 셸로 돌아가는 유일한 문.
///
/// 돌아가는 방향은 게이트가 없다: 회원 쪽은 게스트도 쓰는 표면이고, access가
/// 아직 로드 중인 데모 빌드에서도 이 문이 있어야 pro 셸에 갇히지 않는다.
class _ClientPortalReturnButton extends StatelessWidget {
  const _ClientPortalReturnButton();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return TextButton.icon(
      key: const ValueKey('portal-return-client'),
      onPressed: () => state.switchPortal(AppPortal.client),
      icon: const Icon(SetflowIcons.my, size: 18),
      label: const Text('회원 화면'),
    );
  }
}

/// 탭한 푸시가 여는 업무 셸의 페이지. 트레이너는 상담 큐가 넷째 탭, 센터는
/// 운영이 셋째 탭이다. 관리자 셸은 알림의 집이 아니라 계정 알림만 홈으로.
int? businessPageForPush(UserRole role, PushOpen open) {
  if (open.kind == 'account') return 0;
  if (open.kind != 'business' && open.kind != 'business_activity') return null;
  if (role == UserRole.admin) return null;
  final event = open.event ?? '';
  if (event.startsWith('consultation') ||
      event == 'coaching_schedule_reminder') {
    return role == UserRole.gym ? 2 : 3;
  }
  if (event.startsWith('routine')) return 2;
  // 회원 배정·초대 수락·회원 관계 종료는 사람 탭의 일이다.
  return 1;
}

class _BusinessShellState extends State<BusinessShell> {
  int index = 0;
  int _handledPushSerial = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final open = AppScope.of(context).pendingPushOpen;
    if (open == null || open.serial == _handledPushSerial) return;
    _handledPushSerial = open.serial;
    final page = businessPageForPush(widget.role, open);
    if (page == null || page == index) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => index = page);
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = _roleConfig(context, widget.role);
    final pages = switch (widget.role) {
      UserRole.trainer => const [
        TrainerHome(),
        PeoplePage(role: UserRole.trainer),
        RoutineManagerPage(role: UserRole.trainer),
        ConsultationQueuePage(role: UserRole.trainer),
      ],
      UserRole.gym => const [
        GymHome(),
        PeoplePage(role: UserRole.gym),
        GymOperationsPage(),
        SettlementPage(role: UserRole.gym),
      ],
      UserRole.admin => [
        AdminHome(),
        AdminUsersPage(),
        RoutineManagerPage(role: UserRole.admin),
        AdminReviewPage(),
        SettlementPage(role: UserRole.admin),
      ],
      _ => const [SizedBox(), SizedBox(), SizedBox(), SizedBox()],
    };

    return Scaffold(
      body: Column(
        children: [
          // 헤더 세그먼트는 걷어냈지만(전환은 회원 쪽 전체 메뉴의 한 줄),
          // pro 셸에 서 있는 사람의 **돌아가는 문**은 사라지면 안 된다 —
          // 트레이너도 자기 운동은 회원 화면에서 기록한다. 이 방향은 게이트가 없다.
          const PortalHeaderBar(trailing: _ClientPortalReturnButton()),
          // The header already ate the status-bar inset, so the per-page
          // SafeArea below must not add it a second time.
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: MediaQuery.removeViewInsets(
                context: context,
                removeBottom: true,
                child: IndexedStack(index: index, children: pages),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 64,
        selectedIndex: index,
        // 인디케이터는 테마가 정한다(잉크 바 + 라임). 역할색 14%는 검은 바
        // 위에서 사실상 보이지 않았다 — 어느 탭인지 라벨 굵기로만 읽혔다.
        onDestinationSelected: (value) {
          HapticFeedback.selectionClick();
          setState(() => index = value);
        },
        destinations: [
          for (final item in config.nav)
            NavigationDestination(
              icon: Icon(item.$1),
              selectedIcon: Icon(_selectedBusinessIcon(item.$1)),
              label: item.$2,
            ),
        ],
      ),
    );
  }
}

IconData _selectedBusinessIcon(IconData icon) {
  return switch (icon) {
    Icons.dashboard_outlined => Icons.dashboard_rounded,
    Icons.people_outline => Icons.people_rounded,
    Icons.fitness_center => Icons.fitness_center_rounded,
    Icons.chat_bubble_outline => Icons.chat_bubble_rounded,
    Icons.badge_outlined => Icons.badge_rounded,
    Icons.payments_outlined => Icons.payments_rounded,
    Icons.manage_accounts_outlined => Icons.manage_accounts_rounded,
    Icons.fact_check_outlined => Icons.fact_check_rounded,
    Icons.grid_view_outlined => Icons.grid_view_rounded,
    _ => icon,
  };
}

IconData _businessKindIcon(String kind) {
  return switch (kind) {
    'consultation' => Icons.chat_bubble_outline_rounded,
    'timer' => Icons.timer_outlined,
    'settlement' => Icons.payments_outlined,
    'member' => Icons.person_add_alt_1_outlined,
    'warning' => Icons.warning_amber_rounded,
    'urgent' => Icons.report_gmailerrorred_rounded,
    'review' => Icons.fact_check_outlined,
    _ => Icons.notifications_none_rounded,
  };
}

Color _businessKindColor(BuildContext context, String kind) {
  final colors = context.setflowColors;
  return switch (kind) {
    'consultation' => colors.blue,
    'timer' || 'urgent' => Theme.of(context).colorScheme.error,
    'settlement' => colors.teal,
    'member' || 'review' => colors.purple,
    'warning' => colors.orange,
    _ => colors.info,
  };
}

({String title, Color color, List<(IconData, String)> nav}) _roleConfig(
  BuildContext context,
  UserRole role,
) {
  return switch (role) {
    UserRole.trainer => (
      title: '트레이너',
      color: context.setflowColors.blue,
      nav: [
        (Icons.dashboard_outlined, '홈'),
        (Icons.people_outline, '회원'),
        (Icons.fitness_center, '루틴'),
        (Icons.chat_bubble_outline, '상담'),
      ],
    ),
    UserRole.gym => (
      title: '헬스장',
      color: context.setflowColors.purple,
      nav: const [
        (Icons.dashboard_outlined, '홈'),
        (Icons.people_outline, '회원'),
        (Icons.grid_view_outlined, '운영'),
        (Icons.payments_outlined, '정산'),
      ],
    ),
    UserRole.admin => (
      title: '운영 관리자',
      color: SetflowColors.ink,
      nav: const [
        (Icons.dashboard_outlined, '현황'),
        (Icons.manage_accounts_outlined, '유저'),
        (Icons.fitness_center, '루틴'),
        (Icons.fact_check_outlined, '심사'),
        (Icons.payments_outlined, '정산'),
      ],
    ),
    _ => (title: '', color: SetflowColors.primary, nav: const []),
  };
}

class _BusinessHeader extends StatelessWidget {
  const _BusinessHeader({
    required this.eyebrow,
    required this.title,
    required this.accent,
    required this.onRefresh,
  });
  final String eyebrow;
  final String title;
  final Color accent;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final unreadCount = state.unreadBusinessNotifications(state.role);
    final theme = Theme.of(context);
    // 역할색 eyebrow는 장식이었다 — 색은 의미에만 쓰고, 라벨은 회색이면 된다
    // (회원 쪽과 같은 문법). accent는 알림 시트의 강조에만 남는다.
    final eyebrowColor = theme.colorScheme.onSurfaceVariant;
    return Padding(
      // 좌측은 페이지 여백(18). 우측 6은 아이콘 버튼의 내부 패딩(12)을 빼서
      // 아이콘 글리프가 카드 오른끝(18)과 같은 선에 앉게 하는 값이다 —
      // AppBar가 액션을 다루는 방식과 같다.
      padding: const EdgeInsets.fromLTRB(
        SetflowSpacing.gutter,
        SetflowSpacing.lg,
        SetflowSpacing.xs2,
        SetflowSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: SetflowWeight.medium,
                    color: eyebrowColor,
                  ),
                ),
                const SizedBox(height: SetflowSpacing.xs),
                Text(title, style: theme.textTheme.headlineLarge?.copyWith()),
              ],
            ),
          ),
          IconButton(
            tooltip: '새로고침',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '알림',
            onPressed: () => _showNotifications(context, accent),
            icon: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text('$unreadCount'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '더보기',
            onSelected: (value) {
              final role = AppScope.of(context).role;
              if (value == 'tools') {
                _showWorkspaceMenu(context);
              } else if (value == 'workspace') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WorkspaceScreen(role: role),
                  ),
                );
              } else if (value == 'settings') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BusinessSettingsListScreen(role: role),
                  ),
                );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'tools',
                child: ListTile(
                  leading: Icon(Icons.grid_view_rounded),
                  title: Text('빠른 이동'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (!state.usesLiveBusinessData)
                const PopupMenuItem(
                  value: 'workspace',
                  child: ListTile(
                    leading: Icon(Icons.dashboard_customize_outlined),
                    title: Text('PC 요약'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('설정'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            icon: const Icon(Icons.more_vert_rounded),
          ),
        ],
      ),
    );
  }

  void _showNotifications(BuildContext context, Color accent) {
    showSetflowSheet<void>(
      context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _BusinessNotificationSheet(
        accent: accent,
        role: AppScope.of(context).role,
      ),
    );
  }

  void _showWorkspaceMenu(BuildContext context) {
    final state = AppScope.of(context);
    if (state.role == UserRole.gym && !state.usesLiveBusinessData) {
      _showGymQuickMenu(context, state);
      return;
    }
    final availableWorkspaceRoles = [
      UserRole.member,
      UserRole.trainer,
      UserRole.gym,
      UserRole.admin,
    ].where((role) => state.businessAccess?.canUse(role) ?? false).toList();
    final tools = state.usesLiveBusinessData && state.role == UserRole.trainer
        ? const [
            (Icons.calendar_month_outlined, '코칭 캘린더', BusinessTool.calendar),
          ]
        : state.usesLiveBusinessData && state.role == UserRole.gym
        ? const [
            (Icons.calendar_month_outlined, '코칭 캘린더', BusinessTool.calendar),
          ]
        : state.usesLiveBusinessData && state.role == UserRole.admin
        ? const <(IconData, String, BusinessTool)>[]
        : switch (state.role) {
            UserRole.trainer => const [
              (Icons.calendar_month_outlined, '코칭 캘린더', BusinessTool.calendar),
              (Icons.replay_outlined, '환불 및 미정산', BusinessTool.refunds),
            ],
            UserRole.gym => const <(IconData, String, BusinessTool)>[],
            UserRole.admin => const [
              (Icons.verified_outlined, '배지 발급 관리', BusinessTool.badges),
              (Icons.report_outlined, '커뮤니티 신고 큐', BusinessTool.contentReports),
              (Icons.gavel_outlined, '제재 이력', BusinessTool.sanctions),
              (
                Icons.child_care_outlined,
                '미성년자 위험 신호',
                BusinessTool.minorAlerts,
              ),
              (Icons.leaderboard_outlined, '랭킹 알고리즘', BusinessTool.ranking),
              (Icons.document_scanner_outlined, 'OCR 설정', BusinessTool.ocr),
              (Icons.price_change_outlined, '구독 플랜 정책', BusinessTool.plans),
              (Icons.block_outlined, '금지 키워드', BusinessTool.keywords),
              (Icons.monitor_heart_outlined, '시스템 로그', BusinessTool.logs),
            ],
            _ => const <(IconData, String, BusinessTool)>[],
          };
    showSetflowSheet<void>(
      context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .78,
        maxChildSize: .9,
        builder: (_, controller) => SafeArea(
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            children: [
              const ListTile(
                title: Text(
                  '운영 메뉴',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              for (final item in tools)
                ListTile(
                  leading: Icon(item.$1),
                  title: Text(item.$2),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            BusinessToolScreen(tool: item.$3, role: state.role),
                      ),
                    );
                  },
                ),
              if (state.usesLiveBusinessData &&
                  availableWorkspaceRoles.length > 1) ...[
                const Divider(height: 28),
                const ListTile(
                  title: Text(
                    '워크스페이스 전환',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                for (final role in availableWorkspaceRoles)
                  ListTile(
                    leading: Icon(switch (role) {
                      UserRole.member => Icons.person_outline,
                      UserRole.trainer => Icons.fitness_center,
                      UserRole.gym => Icons.apartment,
                      UserRole.admin => Icons.admin_panel_settings_outlined,
                      _ => Icons.apps_outlined,
                    }),
                    title: Text(switch (role) {
                      UserRole.member => '일반 회원',
                      UserRole.trainer => '트레이너',
                      UserRole.gym => '헬스장',
                      UserRole.admin => '운영 관리자',
                      _ => role.name,
                    }),
                    trailing: role == state.role
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      state.chooseRole(role);
                    },
                  ),
              ] else if (!state.usesLiveBusinessData) ...[
                const Divider(height: 28),
                const ListTile(
                  title: Text(
                    '데모 워크스페이스 전환',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('일반 회원'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    state.chooseRole(UserRole.member);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.fitness_center),
                  title: const Text('트레이너'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    state.chooseRole(UserRole.trainer);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.apartment),
                  title: const Text('헬스장'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    state.chooseRole(UserRole.gym);
                  },
                ),
                if (state.isAdmin)
                  ListTile(
                    leading: const Icon(Icons.admin_panel_settings_outlined),
                    title: const Text('운영 관리자'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      state.chooseRole(UserRole.admin);
                    },
                  ),
              ],
              const Divider(),
              ListTile(
                leading: Icon(Icons.logout, color: context.setflowColors.error),
                title: Text(
                  '로그아웃',
                  style: TextStyle(color: context.setflowColors.error),
                ),
                onTap: () async {
                  final route = ModalRoute.of(sheetContext);
                  Navigator.pop(sheetContext);
                  await route?.completed;
                  await state.logout();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGymQuickMenu(BuildContext context, AppState state) {
    final destinations = <(IconData, String, Widget)>[
      const (Icons.people_outline, '회원', PeoplePage(role: UserRole.gym)),
      const (
        Icons.chat_bubble_outline,
        '상담',
        ConsultationQueuePage(role: UserRole.gym),
      ),
      const (Icons.badge_outlined, '트레이너', TrainerManagementPage()),
      const (
        Icons.fitness_center_outlined,
        '루틴',
        RoutineManagerPage(role: UserRole.gym),
      ),
      const (Icons.payments_outlined, '정산', SettlementPage(role: UserRole.gym)),
    ];
    showSetflowSheet<void>(
      context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          children: [
            const ListTile(
              title: Text(
                '빠른 이동',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            for (final item in destinations)
              ListTile(
                leading: Icon(item.$1),
                title: Text(item.$2),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => item.$3));
                },
              ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.logout, color: context.setflowColors.error),
              title: Text(
                '로그아웃',
                style: TextStyle(color: context.setflowColors.error),
              ),
              onTap: () async {
                final route = ModalRoute.of(sheetContext);
                Navigator.pop(sheetContext);
                await route?.completed;
                await state.logout();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BusinessHomeFrame extends StatefulWidget {
  const _BusinessHomeFrame({
    required this.eyebrow,
    required this.title,
    required this.accent,
    required this.role,
    required this.children,
  });

  final String eyebrow;
  final String title;
  final Color accent;
  final UserRole role;
  final List<Widget> children;

  @override
  State<_BusinessHomeFrame> createState() => _BusinessHomeFrameState();
}

class _BusinessHomeFrameState extends State<_BusinessHomeFrame> {
  bool refreshing = false;

  Future<void> _refresh() async {
    if (refreshing) return;
    setState(() => refreshing = true);
    try {
      await AppScope.of(context).refreshBusinessDashboard(widget.role);
      if (mounted) {
        AppSnackbar.success(context, '운영 현황을 최신 상태로 갱신했어요.');
      }
    } catch (_) {
      if (mounted) {
        AppSnackbar.error(context, '운영 현황을 불러오지 못했어요.');
      }
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return SafeArea(
      child: Column(
        children: [
          _BusinessHeader(
            eyebrow: widget.eyebrow,
            title: widget.title,
            accent: widget.accent,
            onRefresh: _refresh,
          ),
          if (state.usesLiveBusinessData && state.businessError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SetflowSpacing.xxl,
                SetflowSpacing.xs,
                SetflowSpacing.xxl,
                SetflowSpacing.sm,
              ),
              child: Material(
                color: Theme.of(
                  context,
                ).colorScheme.errorContainer.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(SetflowRadii.md),
                child: ListTile(
                  leading: const Icon(Icons.cloud_off_rounded),
                  title: const Text(
                    '운영 데이터를 불러오지 못했어요.',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  trailing: TextButton(
                    onPressed: _refresh,
                    child: const Text('재시도'),
                  ),
                ),
              ),
            ),
          if (state.persistenceError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SetflowSpacing.xxl,
                SetflowSpacing.xs,
                SetflowSpacing.xxl,
                SetflowSpacing.sm,
              ),
              child: Material(
                color: Theme.of(
                  context,
                ).colorScheme.errorContainer.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(SetflowRadii.md),
                child: ListTile(
                  leading: Icon(
                    Icons.cloud_off_rounded,
                    color: context.setflowColors.error,
                  ),
                  title: const Text(
                    '운영 데이터 저장에 실패했어요.',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  trailing: TextButton(
                    onPressed: () {
                      state.retryPersistence();
                      AppSnackbar.info(context, '저장을 다시 시도했어요.');
                    },
                    child: const Text('재시도'),
                  ),
                ),
              ),
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: SetflowMotion.standard,
              switchInCurve: SetflowMotion.standardCurve,
              switchOutCurve: SetflowMotion.standardCurve,
              child: refreshing
                  ? const Padding(
                      key: ValueKey('business-loading'),
                      padding: EdgeInsets.symmetric(
                        horizontal: SetflowSpacing.xxl,
                      ),
                      child: LoadingState(itemCount: 5),
                    )
                  : state.dashboardFor(widget.role).facts.isEmpty &&
                        state.dashboardFor(widget.role).tasks.isEmpty
                  ? EmptyState(
                      key: const ValueKey('business-empty'),
                      icon: Icons.dashboard_customize_outlined,
                      title: '표시할 운영 데이터가 없어요',
                      message: '데이터를 다시 불러오거나 운영 설정을 확인해주세요.',
                      actionLabel: '다시 불러오기',
                      onAction: _refresh,
                    )
                  : RefreshIndicator(
                      key: const ValueKey('business-content'),
                      onRefresh: _refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                          SetflowSpacing.xxl,
                          SetflowSpacing.xs,
                          SetflowSpacing.xxl,
                          SetflowSpacing.xxl,
                        ),
                        children: widget.children,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessNotificationSheet extends StatelessWidget {
  const _BusinessNotificationSheet({required this.accent, required this.role});

  final Color accent;
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final notifications = state
        .dashboardFor(role)
        .notifications
        .where((notification) => !notification.isRead)
        .toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SetflowSpacing.xxl,
          0,
          SetflowSpacing.xxl,
          SetflowSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '알림',
                    style: TextStyle(
                      fontSize: SetflowFontSize.headlineLarge,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (notifications.isNotEmpty)
                  TextButton(
                    onPressed: () =>
                        state.markAllBusinessNotificationsRead(role),
                    child: const Text('모두 읽음'),
                  ),
              ],
            ),
            const SizedBox(height: SetflowSpacing.sm),
            if (notifications.isEmpty)
              const EmptyState(
                icon: Icons.notifications_none_rounded,
                title: '새 알림이 없어요',
                message: '새로운 운영 알림이 도착하면 여기에 표시됩니다.',
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: notifications.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final notification = notifications[index];
                    return Dismissible(
                      key: ValueKey(notification.title),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) => state.markBusinessNotificationRead(
                        role,
                        notification.id,
                      ),
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 18),
                        color: context.setflowColors.teal.withValues(alpha: .1),
                        child: Icon(
                          Icons.done_rounded,
                          color: context.setflowColors.teal,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          _businessKindIcon(notification.kind),
                          color: accent,
                        ),
                        title: Text(
                          notification.title,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(notification.subtitle),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          final navigator = Navigator.of(context);
                          state.markBusinessNotificationRead(
                            role,
                            notification.id,
                          );
                          navigator.pop();
                          navigator.push(
                            MaterialPageRoute<void>(
                              builder: (_) => _businessNotificationPage(
                                role,
                                notification.kind,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Widget _businessNotificationPage(UserRole role, String kind) {
  if (role == UserRole.gym) {
    return switch (kind) {
      'member' => const PeoplePage(role: UserRole.gym),
      'warning' => const TrainerManagementPage(),
      'settlement' => const SettlementPage(role: UserRole.gym),
      _ => const ConsultationQueuePage(role: UserRole.gym),
    };
  }
  if (role == UserRole.trainer) {
    return switch (kind) {
      'timer' => const PeoplePage(role: UserRole.trainer),
      'settlement' => const SettlementPage(role: UserRole.trainer),
      _ => const ConsultationQueuePage(role: UserRole.trainer),
    };
  }
  return switch (kind) {
    'review' => const AdminUsersPage(),
    'settlement' => const SettlementPage(role: UserRole.admin),
    _ => AdminReviewPage(),
  };
}

class TrainerHome extends StatelessWidget {
  const TrainerHome({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final dashboard = state.dashboardFor(UserRole.trainer);
    final facts = dashboard.facts;
    final accent = context.setflowColors.blue;
    return _BusinessHomeFrame(
      eyebrow: 'VERIFIED TRAINER',
      title: '안녕하세요, ${facts['displayName'] ?? '트레이너'}님',
      accent: accent,
      role: UserRole.trainer,
      children: [
        Container(
          padding: const EdgeInsets.all(SetflowSpacing.xl),
          decoration: BoxDecoration(
            // 돈이 걸린 히어로는 어디서나 잉크 블록이다(정산 카드와 같은 판).
            // 파란 슬랩은 카테고리 색을 포털에서 제일 큰 면에 쓰는 일이었다.
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
              const Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.verified_rounded,
                          color: SetflowColors.brand,
                        ),
                        SizedBox(width: SetflowSpacing.sm),
                        Flexible(
                          child: Text(
                            '인증 트레이너',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: SetflowSpacing.md),
                  Text(
                    'PRO',
                    style: TextStyle(
                      color: SetflowColors.brand,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              SizedBox(height: SetflowSpacing.xl),
              Text(
                '이번 달 예상 수익',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: SetflowFontSize.caption,
                ),
              ),
              SizedBox(height: SetflowSpacing.xs),
              Text(
                facts['revenue'] ?? '0원',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: SetflowFontSize.display,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: SetflowSpacing.sm),
              Text(
                facts['revenueChange'] ?? '비교 데이터 없음',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: SetflowFontSize.caption,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: SetflowSpacing.md2),
        Row(
          children: [
            MetricCard(
              label: '관리 회원',
              value: facts['members'] ?? '0',
              suffix: facts['memberCapacity'] ?? '/ 0명',
              icon: Icons.people_outline,
              tint: context.setflowColors.purple,
            ),
            const SizedBox(width: SetflowSpacing.md),
            MetricCard(
              label: '피드백 대기',
              value: facts['feedbackPending'] ?? '0',
              suffix: '건',
              icon: Icons.mark_chat_unread_outlined,
              tint: context.setflowColors.orange,
            ),
          ],
        ),
        const SizedBox(height: SetflowSpacing.xxl),
        const SectionTitle('오늘 할 일'),
        const SizedBox(height: SetflowSpacing.md),
        for (var index = 0; index < dashboard.tasks.length; index++) ...[
          _ActionTile(
            icon: _businessKindIcon(dashboard.tasks[index].kind),
            color: _businessKindColor(context, dashboard.tasks[index].kind),
            title: dashboard.tasks[index].title,
            subtitle: dashboard.tasks[index].subtitle,
            action: dashboard.tasks[index].action,
            onTap: () => _openBusinessTask(
              context,
              UserRole.trainer,
              dashboard.tasks[index],
            ),
          ),
          if (index < dashboard.tasks.length - 1)
            const SizedBox(height: SetflowSpacing.md),
        ],
        const SizedBox(height: SetflowSpacing.xxl),
        SectionTitle(state.usesLiveBusinessData ? '운영 데이터' : '루틴 성과'),
        const SizedBox(height: SetflowSpacing.md),
        // 카드가 아니라 헤어라인 목록 — 회원 홈과 같은 문법.
        if (state.usesLiveBusinessData)
          Column(
            children: [
              _StatusRow(
                label: '등록 루틴',
                status: '${state.ownedBusinessRoutines.length}개',
                color: context.setflowColors.blue,
              ),
              const Divider(height: 26),
              _StatusRow(
                label: '전체 상담',
                status: '${state.businessConsultations.length}건',
                color: context.setflowColors.orange,
              ),
              const Divider(height: 26),
              _StatusRow(
                label: '답변 완료',
                status:
                    '${state.businessConsultations.where(_hasBusinessReply).length}건',
                color: context.setflowColors.success,
              ),
            ],
          )
        else
          Column(
            children: [
              _PerformanceRow(
                label: '루틴 조회수',
                value: facts['routineViews'] ?? '0',
                change: facts['routineViewsChange'] ?? '-',
              ),
              const Divider(height: 26),
              _PerformanceRow(
                label: '상담 전환',
                value: facts['consultationConversion'] ?? '0%',
                change: facts['consultationConversionChange'] ?? '-',
              ),
              const Divider(height: 26),
              _PerformanceRow(
                label: '가져가기',
                value: facts['routineImports'] ?? '0회',
                change: facts['routineImportsChange'] ?? '-',
              ),
            ],
          ),
      ],
    );
  }
}

class GymHome extends StatelessWidget {
  const GymHome({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final dashboard = state.dashboardFor(UserRole.gym);
    final facts = dashboard.facts;
    final accent = context.setflowColors.purple;
    final trainerRows = state.usesLiveBusinessData
        ? state.businessTrainers
              .take(3)
              .map(
                (trainer) => (
                  trainer.displayName ?? '이름 미등록',
                  '회원 ${trainer.memberCount}명 · 피드백 ${trainer.feedbackFulfillmentRate.toStringAsFixed(0)}%',
                ),
              )
              .toList(growable: false)
        : [
            (facts['trainer1Name'] ?? '-', facts['trainer1Detail'] ?? '데이터 없음'),
            (facts['trainer2Name'] ?? '-', facts['trainer2Detail'] ?? '데이터 없음'),
            (facts['trainer3Name'] ?? '-', facts['trainer3Detail'] ?? '데이터 없음'),
          ];
    return _BusinessHomeFrame(
      eyebrow: '센터 홈',
      title: facts['displayName'] ?? '센터',
      accent: accent,
      role: UserRole.gym,
      children: [
        Container(
          padding: const EdgeInsets.all(SetflowSpacing.xl),
          decoration: BoxDecoration(
            // 트레이너 수익 카드와 같은 잉크 블록 — 보라 슬랩은 카테고리
            // 색을 포털의 제일 큰 면에 쓰는 일이었다. 인증 표시는 브랜드가
            // 맡는다.
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [SetflowColors.inkBlockTop, SetflowColors.inkBlockBottom],
            ),
            borderRadius: BorderRadius.circular(SetflowRadii.lg),
          ),
          child: Row(
            children: [
              const Icon(Icons.apartment_rounded, color: Colors.white),
              const SizedBox(width: SetflowSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '사업자 인증 완료',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: SetflowFontSize.caption,
                      ),
                    ),
                    SizedBox(height: SetflowSpacing.xs),
                    Text(
                      facts['plan'] ?? '기본 플랜',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: SetflowFontSize.headline,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.verified_rounded, color: SetflowColors.brand),
            ],
          ),
        ),
        const SizedBox(height: SetflowSpacing.md2),
        Row(
          children: [
            MetricCard(
              label: '전체 회원',
              value: facts['members'] ?? '0',
              suffix: '명',
              icon: Icons.groups_outlined,
              tint: context.setflowColors.teal,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PeoplePage(role: UserRole.gym),
                ),
              ),
            ),
            const SizedBox(width: SetflowSpacing.md),
            MetricCard(
              label: '이번 달 매출',
              value: facts['revenue'] ?? '0',
              suffix: '백만원',
              icon: Icons.trending_up,
              tint: context.setflowColors.success,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SettlementPage(role: UserRole.gym),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: SetflowSpacing.md2),
        Row(
          children: [
            MetricCard(
              label: '소속 트레이너',
              value: facts['trainers'] ?? '0',
              suffix: '명',
              icon: Icons.badge_outlined,
              tint: context.setflowColors.purple,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TrainerManagementPage(),
                ),
              ),
            ),
            const SizedBox(width: SetflowSpacing.md),
            MetricCard(
              label: '신규 상담',
              value: facts['consultations'] ?? '0',
              suffix: '건',
              icon: Icons.chat_bubble_outline,
              tint: context.setflowColors.orange,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const ConsultationQueuePage(role: UserRole.gym),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: SetflowSpacing.xxl),
        const SectionTitle('운영 알림'),
        const SizedBox(height: SetflowSpacing.md),
        for (var index = 0; index < dashboard.tasks.length; index++) ...[
          _ActionTile(
            icon: _businessKindIcon(dashboard.tasks[index].kind),
            color: _businessKindColor(context, dashboard.tasks[index].kind),
            title: dashboard.tasks[index].title,
            subtitle: dashboard.tasks[index].subtitle,
            action: dashboard.tasks[index].action,
            onTap: () => _openBusinessTask(
              context,
              UserRole.gym,
              dashboard.tasks[index],
            ),
          ),
          if (index < dashboard.tasks.length - 1)
            const SizedBox(height: SetflowSpacing.md),
        ],
        const SizedBox(height: SetflowSpacing.xxl),
        const SectionTitle('트레이너 현황'),
        const SizedBox(height: SetflowSpacing.md),
        if (trainerRows.isEmpty)
          const EmptyState(
            icon: Icons.badge_outlined,
            title: '소속 트레이너가 없어요',
            message: '트레이너가 센터에 합류하면 운영 현황이 여기에 표시됩니다.',
          )
        else
          // 카드가 아니라 헤어라인 목록 — 탭하면 트레이너 관리로.
          InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TrainerManagementPage(),
              ),
            ),
            child: Column(
              children: [
                for (var index = 0; index < trainerRows.length; index++) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: SetflowSpacing.xs,
                    ),
                    child: _PersonRow(
                      name: trainerRows[index].$1,
                      detail: trainerRows[index].$2,
                      color: context.setflowColors.blue,
                    ),
                  ),
                  if (index < trainerRows.length - 1) const Divider(height: 22),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class GymOperationsPage extends StatelessWidget {
  const GymOperationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final facts = state.dashboardFor(UserRole.gym).facts;
    final assignedMemberIds = state.businessWorkspace?.assignments
        .where((assignment) => assignment.active)
        .map((assignment) => assignment.memberId)
        .toSet();
    final unassigned = state.usesLiveBusinessData
        ? state.businessMembers
              .where(
                (member) => !(assignedMemberIds?.contains(member.id) ?? false),
              )
              .length
        : const [
            '박민지',
            '이준호',
            '최서연',
            '정하늘',
          ].where((name) => facts['memberAssignment.$name'] == null).length;
    final routineCount = state.usesLiveBusinessData
        ? state.ownedBusinessRoutines.length
        : state.routines.length + state.marketRoutines.length;
    final unansweredConsultations = state.usesLiveBusinessData
        ? state.businessConsultations
              .where((item) => !_hasBusinessReply(item))
              .length
        : int.tryParse(facts['consultations'] ?? '') ?? 0;
    final visitingTrainerCount = state.coachingSessionRecords
        .map((item) => item.trainerId)
        .toSet()
        .length;
    return Scaffold(
      appBar: AppBar(title: const Text('운영')),
      body: ListView(
        padding: SetflowInsets.pageList,
        children: [
          const SectionTitle('오늘'),
          const SizedBox(height: SetflowSpacing.md),
          Row(
            children: [
              MetricCard(
                label: '미배정',
                value: '$unassigned',
                suffix: '명',
                icon: Icons.person_add_alt_1_outlined,
                tint: context.setflowColors.purple,
                onTap: () =>
                    _open(context, const PeoplePage(role: UserRole.gym)),
              ),
              const SizedBox(width: SetflowSpacing.md),
              MetricCard(
                label: '새 상담',
                value: '$unansweredConsultations',
                suffix: '건',
                icon: Icons.chat_bubble_outline_rounded,
                tint: context.setflowColors.orange,
                onTap: () => _open(
                  context,
                  const ConsultationQueuePage(role: UserRole.gym),
                ),
              ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.xxl),
          const SectionTitle('업무'),
          _OperationShortcut(
            icon: Icons.chat_bubble_outline_rounded,
            color: context.setflowColors.orange,
            title: '상담',
            subtitle: '문의 확인과 답변',
            value: '${facts['consultations'] ?? '0'}건',
            onTap: () =>
                _open(context, const ConsultationQueuePage(role: UserRole.gym)),
          ),
          _OperationShortcut(
            icon: Icons.badge_outlined,
            color: context.setflowColors.purple,
            title: '트레이너',
            subtitle: '소속 및 우리 지점 수업 기록',
            value: state.usesLiveBusinessData
                ? '${state.businessTrainers.length} + $visitingTrainerCount명'
                : '${facts['trainers'] ?? '0'}명',
            onTap: () => _open(context, const TrainerManagementPage()),
          ),
          _OperationShortcut(
            icon: Icons.fitness_center_outlined,
            color: context.setflowColors.teal,
            title: '루틴',
            subtitle: '센터 루틴 관리',
            value: '$routineCount개',
            onTap: () =>
                _open(context, const RoutineManagerPage(role: UserRole.gym)),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

class _OperationShortcut extends StatelessWidget {
  const _OperationShortcut({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String value;
  final VoidCallback onTap;

  // 카드 스택이 아니라 헤어라인 줄. 아이콘은 개념 표시라 색 없이 그대로 둔다
  // — 색은 의미(상태)에만 쓴다는 규칙(AGENTS.md 6절).
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: SetflowSpacing.lg),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: SetflowSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: SetflowSpacing.xxs),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: SetflowSpacing.xs),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final dashboard = state.dashboardFor(UserRole.admin);
    final facts = dashboard.facts;
    if (state.usesLiveBusinessData) {
      return _BusinessHomeFrame(
        eyebrow: 'OPERATIONS',
        title: 'Setflow 운영 현황',
        accent: Theme.of(context).colorScheme.onPrimaryContainer,
        role: UserRole.admin,
        children: [
          Row(
            children: [
              MetricCard(
                label: '사업자 심사 대기',
                value: facts['reviews'] ?? '0',
                suffix: '건',
                icon: Icons.fact_check_outlined,
                tint: context.setflowColors.orange,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => AdminReviewPage()),
                ),
              ),
              const SizedBox(width: SetflowSpacing.md),
              MetricCard(
                label: '데이터 연결',
                value: '정상',
                icon: Icons.cloud_done_outlined,
                tint: context.setflowColors.success,
              ),
            ],
          ),
          if (dashboard.tasks.isNotEmpty) ...[
            const SizedBox(height: SetflowSpacing.xxl),
            const SectionTitle('우선 처리'),
            const SizedBox(height: SetflowSpacing.md),
            for (var index = 0; index < dashboard.tasks.length; index++) ...[
              _ActionTile(
                icon: _businessKindIcon(dashboard.tasks[index].kind),
                color: _businessKindColor(context, dashboard.tasks[index].kind),
                title: dashboard.tasks[index].title,
                subtitle: dashboard.tasks[index].subtitle,
                action: dashboard.tasks[index].action,
                onTap: () => _openBusinessTask(
                  context,
                  UserRole.admin,
                  dashboard.tasks[index],
                ),
              ),
              if (index < dashboard.tasks.length - 1)
                const SizedBox(height: SetflowSpacing.md),
            ],
          ],
          const SizedBox(height: SetflowSpacing.xxl),
          const EmptyState(
            icon: Icons.monitor_heart_outlined,
            title: '추가 운영 집계는 아직 연결 전이에요',
            message: '사용자·신고·SLA 지표는 실제 집계 API가 준비되면 이 화면에 표시됩니다.',
          ),
        ],
      );
    }
    return _BusinessHomeFrame(
      eyebrow: 'OPERATIONS',
      title: 'Setflow 운영 현황',
      accent: Theme.of(context).colorScheme.onPrimaryContainer,
      role: UserRole.admin,
      children: [
        Row(
          children: [
            MetricCard(
              label: '전체 사용자',
              value: facts['users'] ?? '0',
              suffix: '명',
              icon: Icons.groups_outlined,
              tint: context.setflowColors.blue,
            ),
            const SizedBox(width: SetflowSpacing.md),
            MetricCard(
              label: '활성 코칭',
              value: facts['coaching'] ?? '0',
              suffix: '건',
              icon: Icons.handshake_outlined,
              tint: context.setflowColors.teal,
            ),
          ],
        ),
        const SizedBox(height: SetflowSpacing.md),
        Row(
          children: [
            MetricCard(
              label: '심사 대기',
              value: facts['reviews'] ?? '0',
              suffix: '건',
              icon: Icons.fact_check_outlined,
              tint: context.setflowColors.orange,
            ),
            const SizedBox(width: SetflowSpacing.md),
            MetricCard(
              label: '신고 큐',
              value: facts['reports'] ?? '0',
              suffix: '건',
              icon: Icons.report_outlined,
              tint: Theme.of(context).colorScheme.error,
            ),
          ],
        ),
        const SizedBox(height: SetflowSpacing.xxl),
        const SectionTitle('우선 처리'),
        const SizedBox(height: SetflowSpacing.md),
        for (var index = 0; index < dashboard.tasks.length; index++) ...[
          _ActionTile(
            icon: _businessKindIcon(dashboard.tasks[index].kind),
            color: _businessKindColor(context, dashboard.tasks[index].kind),
            title: dashboard.tasks[index].title,
            subtitle: dashboard.tasks[index].subtitle,
            action: dashboard.tasks[index].action,
            onTap: () => _openBusinessTask(
              context,
              UserRole.admin,
              dashboard.tasks[index],
            ),
          ),
          if (index < dashboard.tasks.length - 1)
            const SizedBox(height: SetflowSpacing.md),
        ],
        const SizedBox(height: SetflowSpacing.xxl),
        const SectionTitle('SLA 처리 현황'),
        const SizedBox(height: SetflowSpacing.md),
        Column(
          children: [
            _ProgressRow(
              label: 'Red 신고 · 1시간',
              value: _percentageFact(facts, 'redSla'),
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: SetflowSpacing.xl),
            _ProgressRow(
              label: 'Orange 신고 · 24시간',
              value: _percentageFact(facts, 'orangeSla'),
              color: context.setflowColors.orange,
            ),
            const SizedBox(height: SetflowSpacing.xl),
            _ProgressRow(
              label: '인증 심사 · 3영업일',
              value: _percentageFact(facts, 'reviewSla'),
              color: context.setflowColors.success,
            ),
          ],
        ),
        const SizedBox(height: SetflowSpacing.xxl),
        const SectionTitle('시스템 상태'),
        const SizedBox(height: SetflowSpacing.md),
        Column(
          children: [
            _StatusRow(
              label: 'API',
              status: facts['apiStatus'] ?? '확인 필요',
              color: context.setflowColors.success,
            ),
            const Divider(height: 24),
            _StatusRow(
              label: 'OCR 서비스',
              status: facts['ocrStatus'] ?? '확인 필요',
              color: context.setflowColors.success,
            ),
            const Divider(height: 24),
            _StatusRow(
              label: '정산 배치',
              status: facts['settlementStatus'] ?? '확인 필요',
              color: context.setflowColors.orange,
            ),
          ],
        ),
        const SizedBox(height: SetflowSpacing.xxl),
        const SectionTitle('시스템 관리'),
        const SizedBox(height: SetflowSpacing.md),
        _OperationShortcut(
          icon: Icons.tune_outlined,
          color: context.setflowColors.blue,
          title: '시스템 관리',
          subtitle: '랭킹 · OCR · 요금제 · 금칙어 · 로그',
          value: '',
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => AdminSystemScreen())),
        ),
      ],
    );
  }
}

double _percentageFact(Map<String, String> facts, String key) {
  return ((double.tryParse(facts[key] ?? '') ?? 0) / 100).clamp(0, 1);
}

void _openBusinessTask(
  BuildContext context,
  UserRole role,
  BusinessTaskData task,
) {
  final page = switch (task.id) {
    'feedback_due' ||
    'trainer_feedback_due' => const PeoplePage(role: UserRole.trainer),
    'new_consultation' || 'trainer_new_consultation' => ConsultationQueuePage(
      role: role == UserRole.gym ? UserRole.gym : UserRole.trainer,
    ),
    'gym_member_assignment' => const PeoplePage(role: UserRole.gym),
    'gym_feedback_rate' => const TrainerManagementPage(),
    'admin_urgent_reports' => AdminReviewPage(),
    'admin_business_reviews' => AdminReviewPage(),
    _ => WorkspaceScreen(role: role),
  };
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
}

String _relativeBusinessDate(DateTime? date) {
  if (date == null) return '기록 없음';
  final now = DateTime.now();
  final day = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  final difference = today.difference(day).inDays;
  if (difference <= 0) return '오늘';
  if (difference == 1) return '어제';
  return '$difference일 전';
}

String _formatBusinessWon(double value) {
  final digits = value.round().toString();
  return digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

class _CoachingSessionRecordCard extends StatelessWidget {
  const _CoachingSessionRecordCard({required this.record});

  final CoachingSessionRecord record;

  @override
  Widget build(BuildContext context) {
    final date = record.sessionDate;
    return SetflowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  record.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                '${date.month}/${date.day}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.xs),
          Text('${record.trainerName} · ${record.gymName}'),
          const SizedBox(height: SetflowSpacing.sm),
          Text(record.sessionSummary),
          if (record.routineTitle != null || record.routineSummary != null) ...[
            const Divider(height: SetflowSpacing.xl),
            Text(
              '루틴 · ${record.routineTitle ?? '직접 구성'}',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (record.routineSummary != null) Text(record.routineSummary!),
          ],
          if (record.consultationSummary != null) ...[
            const Divider(height: SetflowSpacing.xl),
            Text(
              '상담 요약',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(record.consultationSummary!),
          ],
        ],
      ),
    );
  }
}

class PeoplePage extends StatefulWidget {
  const PeoplePage({required this.role, super.key});
  final UserRole role;

  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  String query = '';
  String filter = 'all';
  final searchController = TextEditingController();
  final List<(String, String, String, int, String?)> demoPeople = const [
    ('박민지', '근육 증가', '오늘', 92, null),
    ('이준호', '체중 감량', '어제', 78, null),
    ('최서연', '체력 향상', '3일 전', 64, null),
    ('정하늘', '건강 유지', '오늘', 88, null),
  ];

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gym = widget.role == UserRole.gym;
    final state = AppScope.of(context);
    final List<(String, String, String, int, String?)> people;
    if (!state.usesLiveBusinessData) {
      people = demoPeople;
    } else if (gym) {
      final sharedMemberIds = state.businessMembers
          .map((item) => item.userId)
          .whereType<String>()
          .toSet();
      final sharedPeople = <(String, String, String, int, String?)>[];
      for (final record in state.coachingSessionRecords) {
        if (!sharedMemberIds.add(record.memberUserId)) continue;
        final sessionCount = state.coachingSessionRecords
            .where((item) => item.memberUserId == record.memberUserId)
            .length;
        sharedPeople.add((
          record.memberName,
          record.memberGoal ?? '목표 미등록',
          _relativeBusinessDate(record.sharedAt),
          sessionCount,
          'shared:${record.memberUserId}',
        ));
      }
      people = [
        ...state.businessMembers.map(
          (member) => (
            member.name,
            member.goal ?? '목표 미등록',
            _relativeBusinessDate(member.lastActivityAt),
            member.completionRate.round().clamp(0, 100).toInt(),
            member.id,
          ),
        ),
        ...sharedPeople,
      ];
    } else {
      final connectedUserIds = state.coachingConnections
          .where((item) => item.isActive)
          .map((item) => item.memberUserId)
          .toSet();
      people = [
        ...state.coachingConnections
            .where((item) => item.isActive)
            .map(
              (connection) => (
                connection.memberName,
                connection.memberGoal ?? '목표 미등록',
                _relativeBusinessDate(connection.lastSessionAt),
                connection.sessionCount,
                'coaching:${connection.id}',
              ),
            ),
        ...state.businessMembers
            .where(
              (member) =>
                  member.userId == null ||
                  !connectedUserIds.contains(member.userId),
            )
            .map(
              (member) => (
                member.name,
                member.goal ?? '목표 미등록',
                _relativeBusinessDate(member.lastActivityAt),
                member.completionRate.round().clamp(0, 100).toInt(),
                member.id,
              ),
            ),
      ];
    }
    final assignments = state.dashboardFor(UserRole.gym).facts;
    final assignedMemberIds = state.businessWorkspace?.assignments
        .where((assignment) => assignment.active)
        .map((assignment) => assignment.memberId)
        .toSet();
    final filtered = people.where((item) {
      final matchesQuery = item.$1.contains(query.trim());
      final matchesFilter = switch (filter) {
        'unassigned' =>
          state.usesLiveBusinessData
              ? !(assignedMemberIds?.contains(item.$5) ?? false)
              : assignments['memberAssignment.${item.$1}'] == null,
        'attention' => item.$4 < 80,
        _ => true,
      };
      return matchesQuery && matchesFilter;
    }).toList();
    return Scaffold(
      appBar: AppBar(title: Text(gym ? '전체 회원' : '관리 회원')),
      body: Column(
        children: [
          Padding(
            padding: SetflowInsets.pageHeader,
            child: Column(
              children: [
                AppTextField(
                  controller: searchController,
                  onChanged: (value) => setState(() => query = value),
                  prefixIcon: const Icon(Icons.search),
                  hint: '회원 이름 검색',
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '검색어 지우기',
                          onPressed: () {
                            searchController.clear();
                            setState(() => query = '');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
                if (gym) ...[
                  const SizedBox(height: SetflowSpacing.md),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _memberFilterChip('all', '전체'),
                        const SizedBox(width: SetflowSpacing.sm),
                        _memberFilterChip('unassigned', '미배정'),
                        const SizedBox(width: SetflowSpacing.sm),
                        _memberFilterChip('attention', '확인 필요'),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? EmptyState(
                    icon: Icons.person_search_outlined,
                    title: '검색 결과가 없어요',
                    message: '다른 이름으로 검색하거나 검색어를 초기화해주세요.',
                    actionLabel: '검색 초기화',
                    onAction: () {
                      searchController.clear();
                      setState(() {
                        query = '';
                        filter = 'all';
                      });
                    },
                  )
                : ListView.builder(
                    padding: SetflowInsets.pageListTight,
                    itemCount: filtered.length,
                    itemBuilder: (_, index) {
                      final person = filtered[index];
                      final isCoachingConnection =
                          person.$5?.startsWith('coaching:') ?? false;
                      final isSharedGymMember =
                          person.$5?.startsWith('shared:') ?? false;
                      final liveAssignment = state
                          .businessWorkspace
                          ?.assignments
                          .where(
                            (assignment) =>
                                assignment.active &&
                                assignment.memberId == person.$5,
                          )
                          .firstOrNull;
                      final assignedTrainerName = state.usesLiveBusinessData
                          ? liveAssignment?.trainerName ?? '미배정'
                          : state
                                    .dashboardFor(UserRole.gym)
                                    .facts['memberAssignment.${person.$1}'] ??
                                '미배정';
                      // 사람 목록은 읽고 들어가는 목록이다 — 회색 카드 스택이
                      // 아니라 헤어라인 줄(회원 쪽과 같은 언어). 인덱스 순환
                      // 아바타색은 의미가 없어 중립으로, 색은 완료율 숫자
                      // (신호등)에만 남는다.
                      return InkWell(
                        onTap: () => _showMember(context, person),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: SetflowSpacing.md,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor:
                                    context.setflowColors.surfaceContainer,
                                child: Text(
                                  person.$1.characters.first,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: SetflowSpacing.md2),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      person.$1,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: SetflowSpacing.xs),
                                    Text(
                                      isSharedGymMember
                                          ? '${person.$2} · 이 헬스장 공유 수업'
                                          : isCoachingConnection
                                          ? '${person.$2} · 개인 코칭 연결'
                                          : gym
                                          ? '${person.$2} · 담당 $assignedTrainerName'
                                          : '${person.$2} · 마지막 기록 ${person.$3}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    isCoachingConnection || isSharedGymMember
                                        ? '${person.$4}회'
                                        : '${person.$4}%',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color:
                                          isCoachingConnection ||
                                              isSharedGymMember ||
                                              person.$4 >= 80
                                          ? context.setflowColors.success
                                          : context.setflowColors.orange,
                                    ),
                                  ),
                                  Text(
                                    isCoachingConnection || isSharedGymMember
                                        ? '공유 수업'
                                        : '완료율',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: SetflowSpacing.xs),
                              Icon(
                                Icons.chevron_right,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: gym
          ? FloatingActionButton.extended(
              heroTag: 'gym-member-invite',
              tooltip: '회원 초대',
              onPressed: () => _showInviteSheet(context),
              // 보라 FAB는 역할색 장식이었다 — 채움은 테마(라임 + 잉크)가 정한다.
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('초대'),
            )
          : FloatingActionButton.extended(
              heroTag: 'trainer-member-invite',
              tooltip: '개인 코칭 회원 초대',
              onPressed: () => _showCoachingInviteSheet(context),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('회원 초대'),
            ),
    );
  }

  Widget _memberFilterChip(String value, String label) {
    return FilterChip(
      label: Text(label),
      selected: filter == value,
      onSelected: (_) => setState(() => filter = value),
    );
  }

  Future<void> _showMember(
    BuildContext context,
    (String, String, String, int, String?) person,
  ) async {
    final personId = person.$5;
    if (personId?.startsWith('coaching:') ?? false) {
      await _showCoachingConnection(
        context,
        personId!.substring('coaching:'.length),
      );
      return;
    }
    if (personId?.startsWith('shared:') ?? false) {
      await _showSharedGymMember(
        context,
        personId!.substring('shared:'.length),
      );
      return;
    }
    final feedbackController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    Future<void>? sheetCompleted;
    final state = AppScope.of(context);
    final live = state.usesLiveBusinessData;
    final liveMember = person.$5 == null
        ? null
        : state.businessMembers
              .where((member) => member.id == person.$5)
              .firstOrNull;
    await showSetflowSheet<void>(
      context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        sheetCompleted ??= ModalRoute.of(sheetContext)?.completed;
        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SafeArea(
            top: false,
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: .7,
              builder: (_, controller) => ListView(
                controller: controller,
                padding: SetflowInsets.pageListTight,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: SetflowColors.primary.withValues(
                          alpha: .2,
                        ),
                        child: Text(
                          person.$1.characters.first,
                          style: const TextStyle(
                            fontSize: SetflowFontSize.headlineLarge,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: SetflowSpacing.md2),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              person.$1,
                              style: const TextStyle(
                                fontSize: SetflowFontSize.headlineLarge,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              person.$2,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: SetflowSpacing.md2),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => MemberDetailScreen(
                            member:
                                liveMember ??
                                BusinessMember(
                                  id: 'demo-${person.$1}',
                                  gymId: 'demo',
                                  name: person.$1,
                                  goal: person.$2,
                                  remainingPtSessions: 0,
                                  completionRate: person.$4.toDouble(),
                                ),
                            role: widget.role,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.person_search_outlined),
                    label: const Text('회원 상세 보기'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(SetflowRadii.md),
                      ),
                    ),
                  ),
                  if (widget.role == UserRole.gym) ...[
                    const SizedBox(height: SetflowSpacing.sm),
                    if (liveMember?.userId == null)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              _showInviteSheet(context, member: liveMember);
                            }
                          });
                        },
                        icon: const Icon(Icons.link_rounded),
                        label: const Text('회원 계정 연결 초대'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              SetflowRadii.md,
                            ),
                          ),
                        ),
                      ),
                    if (liveMember?.userId == null)
                      const SizedBox(height: SetflowSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            _showAssignmentSheet(
                              context,
                              person.$1,
                              memberId: person.$5,
                            );
                          }
                        });
                      },
                      icon: const Icon(Icons.badge_outlined),
                      label: const Text('담당 트레이너 배정'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(SetflowRadii.md),
                        ),
                      ),
                    ),
                    if (live && liveMember != null) ...[
                      const SizedBox(height: SetflowSpacing.sm),
                      OutlinedButton.icon(
                        key: ValueKey('end-membership-${liveMember.id}'),
                        onPressed:
                            state.isEndingBusinessMembership(liveMember.id)
                            ? null
                            : () async {
                                final confirmed = await _confirmEndMembership(
                                  sheetContext,
                                  memberName: liveMember.name,
                                  centerInitiated: true,
                                );
                                if (!confirmed) return;
                                try {
                                  await state.endBusinessMembership(
                                    liveMember.id,
                                  );
                                  if (!sheetContext.mounted ||
                                      !context.mounted) {
                                    return;
                                  }
                                  Navigator.pop(sheetContext);
                                  AppSnackbar.success(
                                    context,
                                    '${liveMember.name} 회원의 센터 연결을 종료했어요.',
                                  );
                                } catch (_) {
                                  if (context.mounted) {
                                    AppSnackbar.error(
                                      context,
                                      '회원 연결을 종료하지 못했어요.',
                                    );
                                  }
                                }
                              },
                        icon: const Icon(Icons.person_remove_outlined),
                        label: const Text('센터 회원 연결 종료'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              SetflowRadii.md,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                  if (!live) ...[
                    const SizedBox(height: SetflowSpacing.xxl),
                    Row(
                      children: [
                        MetricCard(
                          label: '주간 완료율',
                          value: '${person.$4}',
                          suffix: '%',
                          icon: Icons.check_circle_outline,
                          tint: context.setflowColors.teal,
                        ),
                        const SizedBox(width: SetflowSpacing.sm2),
                        MetricCard(
                          label: '최근 볼륨',
                          value: '4.8',
                          suffix: 't',
                          icon: Icons.monitor_weight_outlined,
                          tint: context.setflowColors.orange,
                        ),
                      ],
                    ),
                    const SizedBox(height: SetflowSpacing.xxl),
                    const SectionTitle('최근 운동 기록'),
                    const SizedBox(height: SetflowSpacing.sm),
                    const SetflowCard(
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '상체 루틴',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            subtitle: Text('오늘 · 12세트 · 4.8t'),
                            trailing: Icon(Icons.chevron_right),
                          ),
                          Divider(),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '하체 루틴',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            subtitle: Text('3일 전 · 10세트 · 5.2t'),
                            trailing: Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: SetflowSpacing.xl),
                    Form(
                      key: formKey,
                      child: AppTextField(
                        controller: feedbackController,
                        maxLines: 3,
                        label: '피드백',
                        hint: '회원에게 전달할 피드백을 작성하세요.',
                        validator: (value) {
                          final feedback = value?.trim() ?? '';
                          if (feedback.isEmpty) return '피드백 내용을 입력해주세요.';
                          if (feedback.length < 10) {
                            return '피드백을 10자 이상 입력해주세요.';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: SetflowSpacing.md2),
                    PrimaryButton(
                      label: '피드백 보내기',
                      onPressed: () {
                        if (!(formKey.currentState?.validate() ?? false)) {
                          return;
                        }
                        AppScope.of(context).recordBusinessMemberFeedback(
                          role: widget.role,
                          memberName: person.$1,
                          feedback: feedbackController.text.trim(),
                        );
                        Navigator.pop(sheetContext);
                        AppSnackbar.success(
                          context,
                          '${person.$1}님에게 피드백을 보냈어요.',
                        );
                      },
                    ),
                  ] else ...[
                    const SizedBox(height: SetflowSpacing.xl),
                    const EmptyState(
                      icon: Icons.lock_person_outlined,
                      title: '공유된 상세 운동 기록이 없어요',
                      message: '회원이 공유에 동의한 기록이 연결되면 상세 운동과 피드백 기능이 열립니다.',
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
    await sheetCompleted;
    feedbackController.dispose();
  }

  Future<void> _showCoachingConnection(
    BuildContext context,
    String connectionId,
  ) async {
    final state = AppScope.of(context);
    final connection = state.coachingConnections
        .where((item) => item.id == connectionId)
        .firstOrNull;
    if (connection == null) return;
    final records = state.coachingSessionRecords
        .where((item) => item.coachingId == connection.id)
        .toList(growable: false);
    await showSetflowSheet<void>(
      context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .72,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: SetflowInsets.pageListTight,
          children: [
            Text(
              connection.memberName,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: SetflowSpacing.xs),
            Text(
              '${connection.memberGoal ?? '목표 미등록'} · 개인 코칭 ${connection.sessionCount}회',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SetflowSpacing.md2),
            const SetflowCard(
              child: Text(
                '코칭 캘린더에서 회원과 실제 수업 헬스장을 선택해 일정을 만들 수 있습니다. 수업 후 기록을 공유하면 해당 헬스장에는 그 수업 내용만 전달됩니다.',
              ),
            ),
            const SizedBox(height: SetflowSpacing.xl),
            const SectionTitle('공유한 수업 기록'),
            const SizedBox(height: SetflowSpacing.sm),
            if (records.isEmpty)
              const EmptyState(
                icon: Icons.event_note_outlined,
                title: '아직 공유한 수업이 없어요',
                message: '헬스장이 지정된 일정을 완료하면서 수업 기록을 공유해보세요.',
              )
            else
              for (final record in records)
                Padding(
                  padding: const EdgeInsets.only(bottom: SetflowSpacing.sm),
                  child: _CoachingSessionRecordCard(record: record),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSharedGymMember(
    BuildContext context,
    String memberUserId,
  ) async {
    final records = AppScope.of(context).coachingSessionRecords
        .where((item) => item.memberUserId == memberUserId)
        .toList(growable: false);
    if (records.isEmpty) return;
    final latest = records.first;
    await showSetflowSheet<void>(
      context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .76,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: SetflowInsets.pageListTight,
          children: [
            Text(
              latest.memberName,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: SetflowSpacing.xs),
            Text(
              '이 헬스장에서 공유된 수업 ${records.length}건 · ${latest.memberGoal ?? '목표 미등록'}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SetflowSpacing.md2),
            const SetflowCard(
              child: Text(
                '이 화면은 고용·소속 명단이 아닙니다. 우리 헬스장에서 진행되고 회원이 동의한 수업 기록만 표시합니다.',
              ),
            ),
            const SizedBox(height: SetflowSpacing.xl),
            const SectionTitle('수업별 공유 내역'),
            const SizedBox(height: SetflowSpacing.sm),
            for (final record in records)
              Padding(
                padding: const EdgeInsets.only(bottom: SetflowSpacing.sm),
                child: _CoachingSessionRecordCard(record: record),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCoachingInviteSheet(BuildContext context) async {
    final nameController = TextEditingController();
    Future<void>? sheetCompleted;
    var creating = false;
    CoachingConnectionInviteCreation? creation;
    await showSetflowSheet<void>(
      context,
      showDragHandle: true,
      builder: (sheetContext) {
        sheetCompleted ??= ModalRoute.of(sheetContext)?.completed;
        return StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            top: false,
            child: Padding(
              padding: SetflowInsets.pageForm,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '개인 코칭 회원 초대',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: SetflowSpacing.sm),
                  Text(
                    '센터 소속과 무관하게 회원 동의로 연결합니다. 수업 기록은 실제 수업한 헬스장에 해당 수업 단위로만 공유됩니다.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: SetflowSpacing.xl),
                  if (creation == null) ...[
                    AppTextField(
                      key: const Key('coaching-invite-name'),
                      controller: nameController,
                      label: '회원 이름 (선택)',
                      hint: '초대 링크를 구분할 이름',
                    ),
                    const SizedBox(height: SetflowSpacing.md2),
                    PrimaryButton(
                      key: const Key('coaching-invite-create'),
                      label: creating ? '보안 링크 생성 중...' : '7일 초대 링크 만들기',
                      onPressed: creating
                          ? null
                          : () async {
                              setSheetState(() => creating = true);
                              try {
                                final result = await AppScope.of(context)
                                    .createCoachingConnectionInvite(
                                      recipientName: nameController.text,
                                    );
                                if (sheetContext.mounted) {
                                  setSheetState(() => creation = result);
                                }
                              } catch (_) {
                                if (sheetContext.mounted) {
                                  AppSnackbar.error(
                                    sheetContext,
                                    '회원 초대 링크를 만들지 못했어요.',
                                  );
                                }
                              } finally {
                                if (sheetContext.mounted) {
                                  setSheetState(() => creating = false);
                                }
                              }
                            },
                    ),
                  ] else ...[
                    SelectableText(
                      creation!.uri?.toString() ?? '이 요청에서는 보안 토큰이 이미 발급되었습니다.',
                    ),
                    const SizedBox(height: SetflowSpacing.md2),
                    PrimaryButton(
                      label: '초대 링크 복사',
                      onPressed: creation!.uri == null
                          ? null
                          : () async {
                              await Clipboard.setData(
                                ClipboardData(text: creation!.uri.toString()),
                              );
                              if (sheetContext.mounted) {
                                AppSnackbar.success(
                                  sheetContext,
                                  '개인 코칭 초대 링크를 복사했어요.',
                                );
                              }
                            },
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
    await sheetCompleted;
    nameController.dispose();
  }

  Future<bool> _confirmEndMembership(
    BuildContext context, {
    required String memberName,
    required bool centerInitiated,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('센터 연결을 종료할까요?'),
            content: Text(
              centerInitiated
                  ? '$memberName 회원의 담당 트레이너 배정과 운동 기록 공유 권한이 즉시 종료됩니다.'
                  : '담당 트레이너 배정과 운동 기록 공유 권한이 즉시 종료됩니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialogContext).colorScheme.error,
                ),
                child: const Text('연결 종료'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _showAssignmentSheet(
    BuildContext context,
    String memberName, {
    String? memberId,
  }) async {
    final state = AppScope.of(context);
    final trainers = state.usesLiveBusinessData
        ? state.businessTrainers
              .where((item) => item.trainerId != null)
              .map(
                (item) => (
                  item.trainerId!,
                  item.displayName ?? '이름 미등록',
                  item.memberCount,
                  item.roleTitle ?? '트레이너',
                ),
              )
              .toList(growable: false)
        : const [
            ('김코치', '김코치', 18, '근력'),
            ('박트레이너', '박트레이너', 15, '감량'),
            ('이코치', '이코치', 12, '체형'),
            ('최코치', '최코치', 9, '재활'),
          ];
    final currentAssignment = state.businessWorkspace?.assignments
        .where(
          (assignment) => assignment.active && assignment.memberId == memberId,
        )
        .firstOrNull;
    final demoAssignedName = state
        .dashboardFor(UserRole.gym)
        .facts['memberAssignment.$memberName'];
    var selected = state.usesLiveBusinessData
        ? currentAssignment?.trainerId ?? ''
        : demoAssignedName ?? trainers.firstOrNull?.$1 ?? '';
    if (selected.isNotEmpty &&
        !trainers.any((trainer) => trainer.$1 == selected)) {
      selected = '';
    }
    final liveMember = memberId == null
        ? null
        : state.businessMembers
              .where((member) => member.id == memberId)
              .firstOrNull;
    var saving = false;
    await showSetflowSheet<void>(
      context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: SetflowInsets.pageForm,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$memberName 담당자 배정',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: SetflowSpacing.sm),
                Text(
                  '선택한 트레이너의 담당 회원 목록과 업무 현황에 바로 반영됩니다.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: SetflowSpacing.xl),
                if (trainers.isEmpty) ...[
                  const EmptyState(
                    icon: Icons.badge_outlined,
                    title: '배정할 트레이너가 없어요',
                    message: '센터 소속 트레이너가 등록되면 회원을 배정할 수 있어요.',
                  ),
                  const SizedBox(height: SetflowSpacing.sm),
                ],
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  decoration: const InputDecoration(
                    labelText: '담당 트레이너',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('미배정')),
                    for (final trainer in trainers)
                      DropdownMenuItem(
                        value: trainer.$1,
                        child: Row(
                          children: [
                            Text(trainer.$2),
                            const SizedBox(width: SetflowSpacing.sm),
                            Text(
                              '${trainer.$3}/25명 · ${trainer.$4}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                  ],
                  onChanged: saving
                      ? null
                      : (value) {
                          if (value != null) {
                            setSheetState(() => selected = value);
                          }
                        },
                ),
                const SizedBox(height: SetflowSpacing.xl),
                AppButton(
                  label: saving ? '저장 중...' : '배정 저장',
                  icon: Icons.save_outlined,
                  onPressed:
                      saving ||
                          (state.usesLiveBusinessData && liveMember == null)
                      ? null
                      : () async {
                          setSheetState(() => saving = true);
                          final selectedName = trainers
                              .where((trainer) => trainer.$1 == selected)
                              .firstOrNull
                              ?.$2;
                          try {
                            if (state.usesLiveBusinessData) {
                              await state.assignBusinessMemberById(
                                gymId: liveMember!.gymId,
                                memberId: liveMember.id,
                                trainerId: selected.isEmpty ? null : selected,
                              );
                            } else {
                              await state.assignBusinessMember(
                                memberName: memberName,
                                trainerName: selected.isEmpty
                                    ? null
                                    : selectedName,
                              );
                            }
                            if (!sheetContext.mounted || !mounted) return;
                            Navigator.pop(sheetContext);
                            AppSnackbar.success(
                              this.context,
                              selected.isEmpty
                                  ? '$memberName 회원을 미배정으로 변경했어요.'
                                  : '$memberName 회원을 $selectedName 트레이너에게 배정했어요.',
                            );
                          } catch (_) {
                            if (mounted) {
                              AppSnackbar.error(
                                this.context,
                                '회원 배정을 저장하지 못했어요.',
                              );
                            }
                            if (sheetContext.mounted) {
                              setSheetState(() => saving = false);
                            }
                          }
                        },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showInviteSheet(
    BuildContext context, {
    BusinessMember? member,
  }) async {
    final state = AppScope.of(context);
    if (state.usesLiveBusinessData) {
      await showSetflowSheet<void>(
        context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _GymBusinessInviteSheet(
          state: state,
          kind: BusinessInviteKind.member,
          member: member,
        ),
      );
      return;
    }
    const inviteLink = 'https://setflow.app/invite/gym-7K2M9';
    await showSetflowSheet<void>(
      context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: SetflowInsets.pageListTight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('회원 초대', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: SetflowSpacing.sm),
              Text(
                '아래 링크를 회원에게 전달하면 센터 가입과 담당자 배정을 시작할 수 있어요.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: SetflowSpacing.xl),
              SetflowCard(
                child: const SelectableText(
                  inviteLink,
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: SetflowSpacing.lg),
              AppButton(
                label: '초대 링크 복사',
                icon: Icons.copy_rounded,
                onPressed: () async {
                  await Clipboard.setData(
                    const ClipboardData(text: inviteLink),
                  );
                  if (!sheetContext.mounted) return;
                  Navigator.pop(sheetContext);
                  AppSnackbar.success(context, '회원 초대 링크를 복사했어요.');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GymBusinessInviteSheet extends StatefulWidget {
  const _GymBusinessInviteSheet({
    required this.state,
    required this.kind,
    this.member,
  });

  final AppState state;
  final BusinessInviteKind kind;
  final BusinessMember? member;

  @override
  State<_GymBusinessInviteSheet> createState() =>
      _GymBusinessInviteSheetState();
}

class _GymBusinessInviteSheetState extends State<_GymBusinessInviteSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _roleController;
  BusinessInviteCreation? _creation;
  bool _saving = false;

  bool get _isMember => widget.kind == BusinessInviteKind.member;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.member?.name ?? '');
    _phoneController = TextEditingController(text: widget.member?.phone ?? '');
    _roleController = TextEditingController(text: '트레이너');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _roleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final creation = _creation;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          SetflowSpacing.lg,
          SetflowSpacing.sm,
          SetflowSpacing.lg,
          SetflowSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: creation == null
            ? _buildForm(context)
            : _buildCreated(context, creation),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isMember ? '회원 초대' : '트레이너 초대',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: SetflowSpacing.sm),
          Text(
            _isMember
                ? '초대 링크를 수락한 계정만 이 센터 회원으로 연결됩니다.'
                : '승인된 트레이너 계정만 이 센터 소속으로 연결됩니다.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: SetflowSpacing.xl),
          AppTextField(
            key: const Key('business-invite-name'),
            controller: _nameController,
            label: _isMember ? '회원 이름' : '트레이너 이름 (선택)',
            enabled: widget.member == null && !_saving,
            validator: _isMember
                ? (value) =>
                      (value?.trim().isEmpty ?? true) ? '회원 이름을 입력해주세요.' : null
                : null,
          ),
          if (_isMember) ...[
            const SizedBox(height: SetflowSpacing.md),
            AppTextField(
              controller: _phoneController,
              label: '연락처 (선택)',
              keyboardType: TextInputType.phone,
              enabled: widget.member == null && !_saving,
            ),
          ] else ...[
            const SizedBox(height: SetflowSpacing.md),
            AppTextField(
              controller: _roleController,
              label: '센터 내 역할',
              enabled: !_saving,
            ),
          ],
          const SizedBox(height: SetflowSpacing.md),
          Text(
            '링크 유효기간 7일 · 링크는 한 계정만 사용할 수 있어요.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: SetflowFontSize.caption,
            ),
          ),
          const SizedBox(height: SetflowSpacing.xl),
          AppButton(
            key: const Key('business-invite-create'),
            label: _saving ? '보안 링크 생성 중...' : '초대 링크 만들기',
            icon: Icons.link_rounded,
            onPressed: _saving ? null : _create,
          ),
        ],
      ),
    );
  }

  Widget _buildCreated(BuildContext context, BusinessInviteCreation creation) {
    final uri = creation.uri;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.check_circle_rounded,
          size: 42,
          color: context.setflowColors.teal,
        ),
        const SizedBox(height: SetflowSpacing.md),
        Text('초대 링크를 만들었어요', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: SetflowSpacing.sm),
        const Text('보안을 위해 원문 링크는 지금 한 번만 표시됩니다.'),
        const SizedBox(height: SetflowSpacing.lg),
        SetflowCard(
          child: SelectableText(
            uri?.toString() ?? '링크를 다시 생성해주세요.',
            key: const Key('business-invite-uri'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: SetflowSpacing.lg),
        AppButton(
          label: '링크 복사',
          icon: Icons.copy_rounded,
          onPressed: uri == null
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: uri.toString()));
                  if (context.mounted) {
                    AppSnackbar.success(context, '초대 링크를 복사했어요.');
                  }
                },
        ),
      ],
    );
  }

  Future<void> _create() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final creation = await widget.state.createGymBusinessInvite(
        kind: widget.kind,
        memberId: widget.member?.id,
        recipientName: _nameController.text.trim(),
        recipientPhone: _isMember ? _phoneController.text.trim() : null,
        roleTitle: _isMember ? null : _roleController.text.trim(),
      );
      if (mounted) setState(() => _creation = creation);
    } catch (_) {
      if (mounted) {
        AppSnackbar.error(context, '초대 링크를 만들지 못했어요. 다시 시도해주세요.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class RoutineManagerPage extends StatefulWidget {
  const RoutineManagerPage({required this.role, super.key});
  final UserRole role;

  @override
  State<RoutineManagerPage> createState() => _RoutineManagerPageState();
}

RoutineData _routineDataFromOwned(AppState state, OwnedCoachingRoutine record) {
  final templates = <ExerciseTemplate>[];
  final setPlans = <String, List<RoutineSetPlan>>{};
  for (final item in record.exercises) {
    final template =
        state.exercises
            .where(
              (template) =>
                  template.referencesId(item.baseExerciseId) ||
                  template.name == item.name,
            )
            .firstOrNull ??
        ExerciseTemplate(
          id: item.baseExerciseId ?? item.id,
          name: item.name,
          muscle: item.targetMuscle,
          icon: Icons.fitness_center_rounded,
        );
    templates.add(template);
    setPlans[template.id] = item.sets
        .map(
          (set) => RoutineSetPlan(
            number: set.setNumber,
            weight: set.targetWeight ?? 0,
            reps: set.targetReps ?? 0,
            type: workoutSetTypeLabel(set.type),
            restSeconds: set.restSeconds,
            durationSeconds: set.durationSeconds ?? 0,
            distanceKm: (set.distanceMeters ?? 0) / 1000,
            intensityRpe: set.intensityRpe ?? 0,
          ),
        )
        .toList(growable: false);
  }
  final author = switch (state.businessWorkspace?.profile) {
    TrainerBusinessProfile(:final displayName) => displayName,
    GymBusinessProfile(:final name) => name,
    _ => '전문가',
  };
  return RoutineData(
    id: record.id,
    name: record.title,
    description: record.intro ?? '설명이 등록되지 않았습니다.',
    // 여기만 라이트 상수로 남는다: 이 색은 모델(RoutineData)에 실려 나가고,
    // 모델은 BuildContext 를 모른다. 제대로 고치려면 색을 모델에서 빼고 화면이
    // status -> 색을 그릴 때 정해야 한다 — 별개의 작업이다.
    // 배경: docs/dark-mode-debt.md
    color: switch (record.status) {
      BusinessRoutineStatus.approved => SetflowColors.green,
      BusinessRoutineStatus.rejected => SetflowColors.red,
      BusinessRoutineStatus.review => SetflowColors.orange,
      _ => SetflowColors.blue,
    },
    exercises: templates,
    author: author,
    level: switch (record.difficulty) {
      BusinessRoutineDifficulty.beginner => '초급',
      BusinessRoutineDifficulty.advanced => '고급',
      _ => '중급',
    },
    setPlans: setPlans,
    sourceCoachingRoutineId: record.id,
  );
}

String _businessRoutineStatusLabel(BusinessRoutineStatus status) =>
    switch (status) {
      BusinessRoutineStatus.draft => '작성 중',
      BusinessRoutineStatus.review => '심사 중',
      BusinessRoutineStatus.approved => '승인 · 마켓 노출',
      BusinessRoutineStatus.rejected => '반려',
      BusinessRoutineStatus.unknown => '상태 확인 필요',
    };

String _routineShareStatusLabel(RoutineShareStatus status) => switch (status) {
  RoutineShareStatus.pending => '수락 대기',
  RoutineShareStatus.accepted => '수락 완료',
  RoutineShareStatus.declined => '거절',
  RoutineShareStatus.revoked => '공유 취소',
  RoutineShareStatus.expired => '만료',
  RoutineShareStatus.unknown => '상태 확인 필요',
};

Color _routineShareStatusColor(
  BuildContext context,
  RoutineShareStatus status,
) => switch (status) {
  RoutineShareStatus.accepted => context.setflowColors.success,
  RoutineShareStatus.pending => context.setflowColors.orange,
  RoutineShareStatus.declined ||
  RoutineShareStatus.revoked ||
  RoutineShareStatus.expired => Theme.of(context).colorScheme.onSurfaceVariant,
  RoutineShareStatus.unknown => context.setflowColors.error,
};

class _RoutineShareStatusSummary extends StatelessWidget {
  const _RoutineShareStatusSummary({
    required this.routine,
    required this.shares,
  });

  final OwnedCoachingRoutine routine;
  final List<RoutineShareRecord> shares;

  @override
  Widget build(BuildContext context) {
    final pending = shares
        .where((share) => share.status == RoutineShareStatus.pending)
        .length;
    final accepted = shares
        .where((share) => share.status == RoutineShareStatus.accepted)
        .length;
    return Semantics(
      button: true,
      label: '회원 전송 현황, 수락 $accepted명, 대기 $pending명',
      child: InkWell(
        key: ValueKey('routine-share-status-${routine.id}'),
        borderRadius: BorderRadius.circular(SetflowRadii.md),
        onTap: () => _showRoutineShareStatusSheet(context, routine),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: SetflowSpacing.xs),
          child: Row(
            children: [
              Icon(
                Icons.send_outlined,
                size: 18,
                color: context.setflowColors.blue,
              ),
              const SizedBox(width: SetflowSpacing.sm),
              const Expanded(
                child: Text(
                  '회원 전송 현황',
                  style: TextStyle(
                    fontSize: SetflowFontSize.caption,
                    fontWeight: SetflowWeight.medium,
                  ),
                ),
              ),
              if (accepted > 0)
                _RoutineShareCountBadge(
                  label: '수락 $accepted',
                  color: context.setflowColors.success,
                ),
              if (accepted > 0 && pending > 0)
                const SizedBox(width: SetflowSpacing.xs),
              if (pending > 0)
                _RoutineShareCountBadge(
                  label: '대기 $pending',
                  color: context.setflowColors.orange,
                ),
              const SizedBox(width: SetflowSpacing.xs),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoutineShareCountBadge extends StatelessWidget {
  const _RoutineShareCountBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(SetflowRadii.full),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: SetflowFontSize.tiny,
          fontWeight: SetflowWeight.medium,
        ),
      ),
    );
  }
}

Future<void> _showRoutineShareStatusSheet(
  BuildContext context,
  OwnedCoachingRoutine routine,
) {
  return showSetflowSheet<void>(
    context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _RoutineShareStatusSheet(routine: routine),
  );
}

class _RoutineShareStatusSheet extends StatelessWidget {
  const _RoutineShareStatusSheet({required this.routine});

  final OwnedCoachingRoutine routine;

  Future<void> _revokeShare(
    BuildContext context,
    RoutineShareRecord share,
  ) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('회원 공유를 취소할까요?'),
            content: const Text('취소하면 해당 회원은 이 루틴을 더 이상 수락할 수 없습니다.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('닫기'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialogContext).colorScheme.error,
                ),
                child: const Text('공유 취소'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;

    try {
      await AppScope.of(context).revokeBusinessRoutineShare(share.id);
      if (context.mounted) {
        AppSnackbar.success(context, '회원 공유를 취소했어요.');
      }
    } catch (_) {
      if (context.mounted) {
        AppSnackbar.error(context, '공유를 취소하지 못했어요. 새로고침 후 상태를 확인해주세요.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final shares = state.outgoingRoutineShares
        .where((share) => share.routineId == routine.id)
        .toList(growable: false);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SetflowSpacing.lg,
                0,
                SetflowSpacing.lg,
                SetflowSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '회원 전송 현황',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: SetflowSpacing.xs),
                  Text(
                    routine.title,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  SetflowSpacing.lg,
                  0,
                  SetflowSpacing.lg,
                  SetflowSpacing.lg,
                ),
                itemCount: shares.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: SetflowSpacing.sm),
                itemBuilder: (context, index) {
                  final share = shares[index];
                  final memberName = share.kind == RoutineShareKind.link
                      ? '외부 공유 링크'
                      : state.businessMembers
                                .where(
                                  (member) =>
                                      member.userId == share.recipientUserId,
                                )
                                .firstOrNull
                                ?.name ??
                            '연결 종료 회원';
                  final statusColor = _routineShareStatusColor(
                    context,
                    share.status,
                  );
                  final canRevoke =
                      state.supportsRoutineShareRevocation &&
                      share.kind == RoutineShareKind.direct &&
                      share.status == RoutineShareStatus.pending;
                  final isRevoking = state.isRevokingRoutineShare(share.id);
                  return SetflowCard(
                    key: ValueKey('routine-share-record-${share.id}'),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          share.kind == RoutineShareKind.link
                              ? Icons.link_rounded
                              : Icons.person_outline_rounded,
                          color: statusColor,
                        ),
                        const SizedBox(width: SetflowSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                memberName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: SetflowSpacing.xs),
                              Text(
                                _routineShareStatusLabel(share.status),
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: SetflowFontSize.caption,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (share.createdAt != null)
                                Text(
                                  '${_relativeBusinessDate(share.createdAt)} 전송',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontSize: SetflowFontSize.small,
                                  ),
                                ),
                              if (canRevoke) ...[
                                const SizedBox(height: SetflowSpacing.xs),
                                TextButton.icon(
                                  key: ValueKey(
                                    'routine-share-revoke-${share.id}',
                                  ),
                                  onPressed: isRevoking
                                      ? null
                                      : () => _revokeShare(context, share),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Theme.of(
                                      context,
                                    ).colorScheme.error,
                                    minimumSize: const Size(0, 36),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: SetflowSpacing.sm,
                                    ),
                                  ),
                                  icon: isRevoking
                                      ? const SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.person_remove_outlined,
                                          size: 18,
                                        ),
                                  label: Text(isRevoking ? '취소 중' : '공유 취소'),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (share.status == RoutineShareStatus.accepted)
                          Icon(
                            Icons.check_circle_rounded,
                            color: context.setflowColors.success,
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutineManagerPageState extends State<RoutineManagerPage> {
  final Set<String> _savingRoutineIds = {};

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final isAdminPage = widget.role == UserRole.admin;
    final liveOwnedRoutines = state.usesLiveBusinessData
        ? state.ownedBusinessRoutines
        : const <OwnedCoachingRoutine>[];
    final pendingReviews = isAdminPage
        ? liveOwnedRoutines
              .where(
                (routine) => routine.status == BusinessRoutineStatus.review,
              )
              .toList(growable: false)
        : const <OwnedCoachingRoutine>[];
    final routines = isAdminPage
        ? state.marketRoutines
        : state.usesLiveBusinessData
        ? liveOwnedRoutines
              .map((record) => _routineDataFromOwned(state, record))
              .toList(growable: false)
        : [...state.marketRoutines, ...state.routines];
    return Scaffold(
      appBar: AppBar(
        title: Text(isAdminPage ? '루틴 플랜 관리' : '루틴 관리'),
        actions: [
          if (!isAdminPage)
            IconButton(
              tooltip: '새 루틴 작성',
              onPressed: () => _openRoutineEditor(),
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      body: isAdminPage && !state.isAdmin
          ? const EmptyState(
              icon: Icons.lock_outline_rounded,
              title: '관리자 권한이 필요해요',
              message: '루틴의 무료·유료 플랜은 승인된 관리자만 변경할 수 있어요.',
            )
          : RefreshIndicator(
              onRefresh: () => state.refreshBusinessDashboard(widget.role),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: SetflowInsets.pageList,
                children: [
                  if (isAdminPage)
                    SetflowCard(
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: SetflowColors.primary.withValues(
                                alpha: .14,
                              ),
                              borderRadius: BorderRadius.circular(
                                SetflowRadii.md,
                              ),
                            ),
                            // 라임 위 라임 틴트 — 글리프는 읽는 브랜드로.
                            child: Icon(
                              Icons.workspace_premium_outlined,
                              color: context.setflowColors.brandDeep,
                            ),
                          ),
                          const SizedBox(width: SetflowSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '마켓 이용 플랜',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                                SizedBox(height: SetflowSpacing.xs),
                                Text(
                                  '변경한 무료·유료 설정은 회원 마켓에 바로 반영돼요.',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontSize: SetflowFontSize.caption,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Row(
                      children: [
                        MetricCard(
                          label: '전체 조회',
                          value: state.usesLiveBusinessData
                              ? '${liveOwnedRoutines.fold<int>(0, (sum, item) => sum + item.cumulativeUsers)}'
                              : '3,482',
                          icon: Icons.visibility_outlined,
                          tint: context.setflowColors.blue,
                        ),
                        const SizedBox(width: SetflowSpacing.sm),
                        MetricCard(
                          label: state.usesLiveBusinessData ? '등록 루틴' : '상담 전환',
                          value: state.usesLiveBusinessData
                              ? '${liveOwnedRoutines.length}'
                              : '8.6',
                          suffix: state.usesLiveBusinessData ? '개' : '%',
                          icon: state.usesLiveBusinessData
                              ? Icons.library_books_outlined
                              : Icons.trending_up,
                          tint: context.setflowColors.success,
                        ),
                      ],
                    ),
                  const SizedBox(height: SetflowSpacing.xl),
                  if (isAdminPage && state.usesLiveBusinessData) ...[
                    SectionTitle('심사 대기 ${pendingReviews.length}개'),
                    const SizedBox(height: SetflowSpacing.sm),
                    if (pendingReviews.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: SetflowSpacing.xl),
                        child: EmptyState(
                          icon: Icons.task_alt_rounded,
                          title: '대기 중인 심사가 없어요',
                          message: '전문가가 제출한 루틴이 이곳에 표시됩니다.',
                        ),
                      )
                    else
                      for (final review in pendingReviews)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: SetflowSpacing.md,
                          ),
                          child: AdminRoutineReviewCard(routine: review),
                        ),
                    const SizedBox(height: SetflowSpacing.sm),
                  ],
                  if (isAdminPage) ...[
                    SectionTitle('마켓 루틴 ${routines.length}개'),
                    const SizedBox(height: SetflowSpacing.sm),
                  ],
                  if (routines.isEmpty)
                    EmptyState(
                      icon: Icons.fitness_center_rounded,
                      title: state.usesLiveBusinessData && !isAdminPage
                          ? '등록된 루틴이 없어요'
                          : '등록된 마켓 루틴이 없어요',
                      message: state.usesLiveBusinessData && !isAdminPage
                          ? '새 루틴을 작성하면 실제 전문가 루틴 테이블에 저장됩니다.'
                          : '승인된 루틴이 등록되면 이곳에서 이용 플랜을 설정할 수 있어요.',
                    ),
                  for (final routine in routines)
                    Builder(
                      builder: (context) {
                        final owned = liveOwnedRoutines
                            .where((item) => item.id == routine.id)
                            .firstOrNull;
                        final routineShares = owned == null
                            ? const <RoutineShareRecord>[]
                            : state.outgoingRoutineShares
                                  .where((share) => share.routineId == owned.id)
                                  .toList(growable: false);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SetflowCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    // 루틴 식별색은 어디서나 가는 선이다 —
                                    // 내 루틴·불러오기 시트와 같은 문법.
                                    Container(
                                      width: 4,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: routine.color,
                                        borderRadius: BorderRadius.circular(
                                          SetflowRadii.full,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: SetflowSpacing.md),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            routine.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: SetflowFontSize.title,
                                            ),
                                          ),
                                          Text(
                                            owned == null
                                                ? '승인 · 마켓 노출 중'
                                                : _businessRoutineStatusLabel(
                                                    owned.status,
                                                  ),
                                            style: TextStyle(
                                              fontSize: SetflowFontSize.small,
                                              color:
                                                  owned?.status ==
                                                      BusinessRoutineStatus
                                                          .rejected
                                                  ? Theme.of(
                                                      context,
                                                    ).colorScheme.error
                                                  : context
                                                        .setflowColors
                                                        .success,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!isAdminPage && owned != null)
                                      PopupMenuButton<String>(
                                        tooltip: '루틴 작업',
                                        enabled:
                                            !state.isSavingBusinessRoutine(
                                              owned.id,
                                            ) &&
                                            !state.isSubmittingBusinessRoutine(
                                              owned.id,
                                            ) &&
                                            !state.isSharingBusinessRoutine(
                                              owned.id,
                                            ),
                                        itemBuilder: (_) => [
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: Text(
                                              owned.status ==
                                                      BusinessRoutineStatus
                                                          .approved
                                                  ? '새 개정본 만들기'
                                                  : owned.status ==
                                                        BusinessRoutineStatus
                                                            .review
                                                  ? '내용 보기'
                                                  : '수정',
                                            ),
                                          ),
                                          if (owned.status ==
                                                  BusinessRoutineStatus.draft ||
                                              owned.status ==
                                                  BusinessRoutineStatus
                                                      .rejected)
                                            const PopupMenuItem(
                                              value: 'submit',
                                              child: Text('심사 요청'),
                                            ),
                                          if (owned.status ==
                                                  BusinessRoutineStatus.draft ||
                                              owned.status ==
                                                  BusinessRoutineStatus
                                                      .approved)
                                            const PopupMenuItem(
                                              value: 'member-share',
                                              child: Text('담당 회원에게 공유'),
                                            ),
                                          if (owned.status ==
                                              BusinessRoutineStatus.approved)
                                            const PopupMenuItem(
                                              value: 'link-share',
                                              child: Text('외부 공유 링크 만들기'),
                                            ),
                                        ],
                                        onSelected: (action) =>
                                            _handleRoutineAction(owned, action),
                                      ),
                                  ],
                                ),
                                const Divider(height: 24),
                                if (isAdminPage)
                                  _AdminRoutineAccessEditor(
                                    routine: routine,
                                    isSaving: _savingRoutineIds.contains(
                                      routine.id,
                                    ),
                                    onChanged: (tier) =>
                                        _updateAccessTier(routine, tier),
                                  )
                                else ...[
                                  if (owned?.rejectReason?.isNotEmpty ==
                                      true) ...[
                                    Text(
                                      '반려 사유: ${owned!.rejectReason}',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                        fontSize: SetflowFontSize.caption,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: SetflowSpacing.sm),
                                  ],
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      _MiniMetric(
                                        label: '사용',
                                        value: owned == null
                                            ? '1,284'
                                            : '${owned.cumulativeUsers}',
                                      ),
                                      _MiniMetric(
                                        label: '운동',
                                        value: owned == null
                                            ? '42'
                                            : '${owned.exercises.length}',
                                      ),
                                      _MiniMetric(
                                        label: '상태',
                                        value: owned == null
                                            ? '승인'
                                            : _businessRoutineStatusLabel(
                                                owned.status,
                                              ),
                                      ),
                                    ],
                                  ),
                                  if (owned != null &&
                                      routineShares.isNotEmpty) ...[
                                    const Divider(height: 24),
                                    _RoutineShareStatusSummary(
                                      routine: owned,
                                      shares: routineShares,
                                    ),
                                  ],
                                  const SizedBox(height: SetflowSpacing.md),
                                  if (!state.usesLiveBusinessData)
                                    InkWell(
                                      onTap: () => Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => RoutineStatsPage(
                                            routine: routine,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.bar_chart_rounded,
                                            size: 16,
                                            // 글자로 된 행동은 읽는 브랜드다
                                            // — 파랑은 차트 시리즈의 색이라
                                            // 여기 쓰면 링크가 데이터처럼
                                            // 읽힌다.
                                            color:
                                                context.setflowColors.brandDeep,
                                          ),
                                          SizedBox(width: SetflowSpacing.xs2),
                                          Text(
                                            '통계 보기',
                                            style: TextStyle(
                                              fontSize: SetflowFontSize.caption,
                                              fontWeight: SetflowWeight.medium,
                                              color: context
                                                  .setflowColors
                                                  .brandDeep,
                                            ),
                                          ),
                                          Spacer(),
                                          Icon(
                                            Icons.chevron_right,
                                            size: 16,
                                            color: SetflowColors.disabled,
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Future<void> _updateAccessTier(
    RoutineData routine,
    RoutineAccessTier tier,
  ) async {
    if (_savingRoutineIds.contains(routine.id) || tier == routine.accessTier) {
      return;
    }
    setState(() => _savingRoutineIds.add(routine.id));
    final state = AppScope.of(context);
    try {
      final updated = await state.updateMarketRoutineAccess(routine, tier);
      if (!updated) throw StateError('Administrator access required.');
      if (!mounted) return;
      AppSnackbar.success(
        context,
        '${routine.name}을(를) ${tier.label} 루틴으로 변경했어요.',
      );
    } catch (_) {
      if (!mounted) return;
      AppSnackbar.error(context, '플랜을 변경하지 못했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _savingRoutineIds.remove(routine.id));
    }
  }

  Future<void> _openRoutineEditor([OwnedCoachingRoutine? routine]) async {
    final state = AppScope.of(context);
    if (!state.usesLiveBusinessData) {
      await _showRoutineCreate(context, widget.role);
      return;
    }
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BusinessRoutineEditorScreen(
          ownerRole: widget.role,
          routine: routine,
          readOnly: routine?.status == BusinessRoutineStatus.review,
        ),
      ),
    );
    if (updated == true && mounted) {
      AppSnackbar.success(context, '루틴 초안을 저장했어요.');
    }
  }

  Future<void> _handleRoutineAction(
    OwnedCoachingRoutine routine,
    String action,
  ) async {
    switch (action) {
      case 'edit':
        await _openRoutineEditor(routine);
      case 'submit':
        await _submitRoutine(routine);
      case 'member-share':
        final shared = await showRoutineMemberShareSheet(
          context,
          routine: routine,
        );
        if (shared == true && mounted) {
          AppSnackbar.success(context, '선택한 회원에게 루틴을 보냈어요.');
        }
      case 'link-share':
        await createAndShowRoutineShareLink(context, routine);
    }
  }

  Future<void> _submitRoutine(OwnedCoachingRoutine routine) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('루틴 심사를 요청할까요?'),
            content: const Text(
              '심사 중에는 내용을 수정할 수 없습니다. 반려되면 보완 후 다시 제출할 수 있어요.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('심사 요청'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    try {
      await AppScope.of(context).submitBusinessRoutineForReview(routine.id);
      if (mounted) AppSnackbar.success(context, '관리자에게 심사를 요청했어요.');
    } catch (_) {
      if (mounted) AppSnackbar.error(context, '심사 요청을 보내지 못했어요.');
    }
  }
}

class _AdminRoutineAccessEditor extends StatelessWidget {
  const _AdminRoutineAccessEditor({
    required this.routine,
    required this.isSaving,
    required this.onChanged,
  });

  final RoutineData routine;
  final bool isSaving;
  final ValueChanged<RoutineAccessTier> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '회원 이용 플랜',
                style: TextStyle(
                  fontSize: SetflowFontSize.caption,
                  fontWeight: SetflowWeight.medium,
                ),
              ),
            ),
            if (isSaving)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Text(
                routine.accessTier.label,
                style: TextStyle(
                  color: routine.accessTier == RoutineAccessTier.paid
                      ? context.setflowColors.purple
                      : context.setflowColors.success,
                  fontSize: SetflowFontSize.caption,
                  fontWeight: SetflowWeight.medium,
                ),
              ),
          ],
        ),
        const SizedBox(height: SetflowSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<RoutineAccessTier>(
            segments: [
              for (final tier in RoutineAccessTier.values)
                ButtonSegment(
                  value: tier,
                  icon: Icon(
                    tier == RoutineAccessTier.free
                        ? Icons.lock_open_rounded
                        : Icons.workspace_premium_rounded,
                  ),
                  label: Text(tier.label),
                ),
            ],
            selected: {routine.accessTier},
            onSelectionChanged: isSaving
                ? null
                : (selection) => onChanged(selection.first),
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _showRoutineCreate(BuildContext context, UserRole role) async {
  final state = AppScope.of(context);
  final nameController = TextEditingController();
  final descriptionController = TextEditingController();
  final setCountController = TextEditingController(text: '3');
  final repsController = TextEditingController(text: '10');
  final formKey = GlobalKey<FormState>();
  final selectedExerciseIds = <String>{};
  var saving = false;
  Future<void>? sheetCompleted;
  await showSetflowSheet<void>(
    context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      sheetCompleted ??= ModalRoute.of(sheetContext)?.completed;
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            SetflowSpacing.xxl,
            SetflowSpacing.xs,
            SetflowSpacing.xxl,
            MediaQuery.viewInsetsOf(sheetContext).bottom + SetflowSpacing.xxl,
          ),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    role == UserRole.gym ? '센터 루틴 만들기' : '전문가 루틴 만들기',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: SetflowSpacing.sm),
                  Text(
                    state.usesLiveBusinessData
                        ? '운동과 목표 세트를 선택하면 초안으로 저장됩니다.'
                        : '저장 후 루틴 관리 목록에서 구성과 통계를 계속 편집할 수 있어요.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: SetflowSpacing.xl),
                  AppTextField(
                    controller: nameController,
                    label: '루틴 이름',
                    hint: '예: 직장인 4주 근력 루틴',
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      final name = value?.trim() ?? '';
                      if (name.isEmpty) return '루틴 이름을 입력해주세요.';
                      if (name.length < 3) return '루틴 이름을 3자 이상 입력해주세요.';
                      return null;
                    },
                  ),
                  const SizedBox(height: SetflowSpacing.md),
                  AppTextField(
                    controller: descriptionController,
                    label: '루틴 설명',
                    hint: '대상과 운동 목표를 설명해주세요.',
                    maxLines: 3,
                    validator: (value) {
                      if ((value?.trim().length ?? 0) < 10) {
                        return '루틴 설명을 10자 이상 입력해주세요.';
                      }
                      return null;
                    },
                  ),
                  if (state.usesLiveBusinessData) ...[
                    const SizedBox(height: SetflowSpacing.xl),
                    const SectionTitle('운동 선택'),
                    const SizedBox(height: SetflowSpacing.sm),
                    _BusinessExerciseMultiPicker(
                      catalog: state.exercises,
                      selectedIds: selectedExerciseIds,
                      enabled: !saving,
                    ),
                    const SizedBox(height: SetflowSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            controller: setCountController,
                            label: '운동별 세트',
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: (value) {
                              final count = int.tryParse(value ?? '');
                              if (count == null || count < 1 || count > 10) {
                                return '1~10세트';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: SetflowSpacing.sm),
                        Expanded(
                          child: AppTextField(
                            controller: repsController,
                            label: '목표 횟수',
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: (value) {
                              final reps = int.tryParse(value ?? '');
                              if (reps == null || reps < 1 || reps > 100) {
                                return '1~100회';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: SetflowSpacing.xl),
                  AppButton(
                    label: saving ? '저장 중...' : '루틴 저장',
                    icon: Icons.save_outlined,
                    onPressed: saving
                        ? null
                        : () async {
                            if (!(formKey.currentState?.validate() ?? false)) {
                              return;
                            }
                            final selectedExercises = state.exercises
                                .where(
                                  (exercise) =>
                                      selectedExerciseIds.contains(exercise.id),
                                )
                                .toList(growable: false);
                            if (state.usesLiveBusinessData &&
                                selectedExercises.isEmpty) {
                              AppSnackbar.info(context, '운동을 한 개 이상 선택해주세요.');
                              return;
                            }
                            setSheetState(() => saving = true);
                            try {
                              if (state.usesLiveBusinessData) {
                                await state.createBusinessRoutine(
                                  ownerRole: role,
                                  title: nameController.text.trim(),
                                  description: descriptionController.text
                                      .trim(),
                                  routineExercises: selectedExercises,
                                  setCount: int.parse(setCountController.text),
                                  targetReps: int.parse(repsController.text),
                                );
                              } else {
                                final created = state.createRoutine(
                                  nameController.text.trim(),
                                  descriptionController.text.trim(),
                                );
                                if (!created) {
                                  AppSnackbar.error(
                                    context,
                                    '현재 플랜의 루틴 저장 한도에 도달했어요.',
                                  );
                                  setSheetState(() => saving = false);
                                  return;
                                }
                              }
                            } catch (_) {
                              if (context.mounted) {
                                AppSnackbar.error(context, '루틴을 저장하지 못했어요.');
                              }
                              if (sheetContext.mounted) {
                                setSheetState(() => saving = false);
                              }
                              return;
                            }
                            if (!sheetContext.mounted || !context.mounted) {
                              return;
                            }
                            Navigator.pop(sheetContext);
                            AppSnackbar.success(context, '새 루틴을 저장했어요.');
                          },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  await sheetCompleted;
  nameController.dispose();
  descriptionController.dispose();
  setCountController.dispose();
  repsController.dispose();
}

/// A large shared catalog must stay lazy. Rendering every exercise as a chip
/// made the live routine sheet build nearly a thousand widgets before it could
/// accept input.
class _BusinessExerciseMultiPicker extends StatefulWidget {
  const _BusinessExerciseMultiPicker({
    required this.catalog,
    required this.selectedIds,
    required this.enabled,
  });

  final List<ExerciseTemplate> catalog;
  final Set<String> selectedIds;
  final bool enabled;

  @override
  State<_BusinessExerciseMultiPicker> createState() =>
      _BusinessExerciseMultiPickerState();
}

class _BusinessExerciseMultiPickerState
    extends State<_BusinessExerciseMultiPicker> {
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.catalog
        .where((exercise) => exercise.matchesCatalogQuery(_search))
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('선택 ${widget.selectedIds.length}개'),
            const Spacer(),
            Text(
              '전체 ${widget.catalog.length}개',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: SetflowSpacing.sm),
        AppTextField(
          key: const Key('business-routine-exercise-search'),
          controller: _searchController,
          prefixIcon: const Icon(Icons.search_rounded),
          hint: '운동명 · 부위 · 기구 검색 (한국어/영문)',
          onChanged: (value) => setState(() => _search = value),
        ),
        const SizedBox(height: SetflowSpacing.sm),
        SizedBox(
          height: 360,
          child: filtered.isEmpty
              ? const Center(child: Text('검색 결과가 없어요.'))
              : ListView.builder(
                  key: const Key('business-routine-exercise-results'),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final exercise = filtered[index];
                    final selected = widget.selectedIds.contains(exercise.id);
                    return CheckboxListTile(
                      value: selected,
                      enabled: widget.enabled,
                      controlAffinity: ListTileControlAffinity.trailing,
                      secondary: Icon(exercise.icon),
                      title: Text(exercise.name),
                      subtitle: Text(
                        '${exercise.muscle} · ${exercise.resolvedEquipmentName}',
                      ),
                      onChanged: widget.enabled
                          ? (checked) => setState(() {
                              if (checked ?? false) {
                                widget.selectedIds.add(exercise.id);
                              } else {
                                widget.selectedIds.remove(exercise.id);
                              }
                            })
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class ConsultationQueuePage extends StatefulWidget {
  const ConsultationQueuePage({required this.role, super.key});
  final UserRole role;

  @override
  State<ConsultationQueuePage> createState() => _ConsultationQueuePageState();
}

class _ConsultationQueuePageState extends State<ConsultationQueuePage> {
  bool unreadOnly = false;
  final Set<String> _openConsultationIds = {};
  Future<void>? _refreshInFlight;
  Object? _refreshError;

  bool get _supportsLiveRefresh =>
      widget.role == UserRole.trainer || widget.role == UserRole.gym;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_supportsLiveRefresh) return;
      final state = AppScope.of(context);
      if (state.usesLiveBusinessData) {
        unawaited(_refreshLiveConsultations(state));
      }
    });
  }

  Future<void> _refreshLiveConsultations(
    AppState state, {
    bool showFeedback = false,
  }) {
    final refreshInFlight = _refreshInFlight;
    if (refreshInFlight != null) return refreshInFlight;
    if (!mounted || !state.usesLiveBusinessData || !_supportsLiveRefresh) {
      return Future<void>.value();
    }

    final refresh = _performLiveRefresh(state, showFeedback: showFeedback);
    _refreshInFlight = refresh;
    return refresh;
  }

  Future<void> _performLiveRefresh(
    AppState state, {
    required bool showFeedback,
  }) async {
    setState(() => _refreshError = null);
    try {
      await state.refreshBusinessDashboard(widget.role);
      if (mounted && showFeedback) {
        AppSnackbar.success(context, '상담 목록을 최신 상태로 갱신했어요.');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _refreshError = error);
      if (showFeedback) {
        AppSnackbar.error(context, '상담 목록을 불러오지 못했어요.');
      }
    } finally {
      _refreshInFlight = null;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (state.usesLiveBusinessData) {
      return _buildLiveConsultations(context, state);
    }
    const items = [
      ('이수진', '근육 증가', '운동 경력 3개월 · 주 3회 가능'),
      ('김도윤', '체중 감량', '무릎 통증 있음 · 홈트 선호'),
      ('정민아', '체력 향상', '러닝과 근력 병행 희망'),
    ];
    final answered = items.indexed
        .where(
          (entry) =>
              state.isBusinessConsultationAnswered(widget.role, entry.$1),
        )
        .map((entry) => entry.$1)
        .toSet();
    final visible = items.indexed
        .where((entry) => !unreadOnly || !answered.contains(entry.$1))
        .toList();
    final unreadCount = items.length - answered.length;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('상담 수신함'),
            if (unreadCount > 0) ...[
              const SizedBox(width: SetflowSpacing.sm),
              Badge(label: Text('$unreadCount')),
            ],
          ],
        ),
        actions: [
          if (!state.usesLiveBusinessData)
            IconButton(
              tooltip: '상담 리타겟',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ConsultationRetargetScreen(role: widget.role),
                ),
              ),
              icon: const Icon(Icons.campaign_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: SetflowInsets.pageHeader,
            child: Row(
              children: [
                FilterChip(
                  label: const Text('전체'),
                  selected: !unreadOnly,
                  onSelected: (_) => setState(() => unreadOnly = false),
                ),
                const SizedBox(width: SetflowSpacing.sm),
                FilterChip(
                  label: Text('미답변 $unreadCount'),
                  selected: unreadOnly,
                  onSelected: (_) => setState(() => unreadOnly = true),
                ),
              ],
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? EmptyState(
                    icon: Icons.mark_email_read_outlined,
                    title: '미답변 상담이 없어요',
                    message: '현재 도착한 상담에 모두 답변했습니다.',
                    actionLabel: '전체 상담 보기',
                    onAction: () => setState(() => unreadOnly = false),
                  )
                : ListView.builder(
                    padding: SetflowInsets.pageListTight,
                    itemCount: visible.length,
                    itemBuilder: (_, visibleIndex) {
                      final index = visible[visibleIndex].$1;
                      final item = visible[visibleIndex].$2;
                      final done = answered.contains(index);
                      // 수신함은 읽는 목록이다 — 카드가 아니라 헤어라인 줄.
                      // 색은 "아직 안 읽음"(빨간 점)에만 남는다.
                      return InkWell(
                        onTap: () => _answer(context, index, item),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: SetflowSpacing.md,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                done
                                    ? Icons.mark_email_read_outlined
                                    : Icons.mark_email_unread_outlined,
                                size: 20,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: SetflowSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          item.$1,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
                                        ),
                                        const SizedBox(
                                          width: SetflowSpacing.sm,
                                        ),
                                        if (!done)
                                          Container(
                                            width: 7,
                                            height: 7,
                                            decoration: BoxDecoration(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.error,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: SetflowSpacing.xs),
                                    Text(
                                      item.$2,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                    Text(
                                      item.$3,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveConsultations(BuildContext context, AppState state) {
    final pending = state.businessConsultations
        .where((item) => !_hasBusinessReply(item))
        .toList(growable: false);
    final visible = unreadOnly ? pending : state.businessConsultations;
    final refreshing = _refreshInFlight != null;
    final hasRefreshError =
        _refreshError != null || state.businessError != null;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('상담 수신함'),
            if (pending.isNotEmpty) ...[
              const SizedBox(width: SetflowSpacing.sm),
              Badge(label: Text('${pending.length}')),
            ],
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('business-consultations-refresh'),
            tooltip: refreshing ? '상담 새로고침 중' : '상담 새로고침',
            onPressed: refreshing
                ? null
                : () => _refreshLiveConsultations(state, showFeedback: true),
            icon: refreshing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (hasRefreshError)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SetflowSpacing.xxl,
                SetflowSpacing.sm,
                SetflowSpacing.xxl,
                0,
              ),
              child: Material(
                key: const ValueKey('business-consultations-refresh-error'),
                color: Theme.of(
                  context,
                ).colorScheme.errorContainer.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(SetflowRadii.md),
                child: ListTile(
                  leading: const Icon(Icons.cloud_off_rounded),
                  title: const Text(
                    '상담 목록을 최신 상태로 불러오지 못했어요.',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: state.businessConsultations.isNotEmpty
                      ? const Text('기존에 불러온 상담 목록을 계속 표시합니다.')
                      : const Text('네트워크 연결을 확인한 뒤 다시 시도해주세요.'),
                  trailing: TextButton(
                    key: const ValueKey('business-consultations-refresh-retry'),
                    onPressed: refreshing
                        ? null
                        : () => _refreshLiveConsultations(
                            state,
                            showFeedback: true,
                          ),
                    child: const Text('재시도'),
                  ),
                ),
              ),
            ),
          Padding(
            padding: SetflowInsets.pageHeader,
            child: Row(
              children: [
                FilterChip(
                  label: const Text('전체'),
                  selected: !unreadOnly,
                  onSelected: (_) => setState(() => unreadOnly = false),
                ),
                const SizedBox(width: SetflowSpacing.sm),
                FilterChip(
                  label: Text('미답변 ${pending.length}'),
                  selected: unreadOnly,
                  onSelected: (_) => setState(() => unreadOnly = true),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              key: const ValueKey('business-consultations-refresh-indicator'),
              onRefresh: () => _refreshLiveConsultations(state),
              child: visible.isEmpty
                  ? CustomScrollView(
                      key: const ValueKey('business-consultations-list'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: SetflowInsets.pageListTight,
                          sliver: SliverFillRemaining(
                            hasScrollBody: false,
                            child: refreshing && !hasRefreshError
                                ? const LoadingState(
                                    key: ValueKey(
                                      'business-consultations-loading',
                                    ),
                                    message: '상담 목록을 불러오는 중',
                                    compact: true,
                                  )
                                : EmptyState(
                                    key: const ValueKey(
                                      'business-consultations-empty',
                                    ),
                                    icon: Icons.mark_email_read_outlined,
                                    title: unreadOnly
                                        ? '미답변 상담이 없어요'
                                        : '도착한 상담이 없어요',
                                    message: unreadOnly
                                        ? '현재 도착한 상담에 모두 답변했습니다.'
                                        : '새 상담이 접수되면 이곳에서 바로 답변할 수 있어요.',
                                    actionLabel: unreadOnly ? '전체 상담 보기' : null,
                                    onAction: unreadOnly
                                        ? () =>
                                              setState(() => unreadOnly = false)
                                        : null,
                                  ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      key: const ValueKey('business-consultations-list'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: SetflowInsets.pageListTight,
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final item = visible[index];
                        final done = _hasBusinessReply(item);
                        // 수신함은 읽는 목록 — 데모 목록과 같은 헤어라인 줄.
                        return InkWell(
                          onTap: _openConsultationIds.contains(item.id)
                              ? null
                              : () => _answerLive(context, item),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: SetflowSpacing.md,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outlineVariant,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  done
                                      ? Icons.mark_email_read_outlined
                                      : Icons.mark_email_unread_outlined,
                                  size: 20,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: SetflowSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            item.memberName ?? '회원',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleMedium,
                                          ),
                                          const SizedBox(
                                            width: SetflowSpacing.sm,
                                          ),
                                          if (!done)
                                            Container(
                                              width: 7,
                                              height: 7,
                                              decoration: BoxDecoration(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.error,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: SetflowSpacing.xs),
                                      Text(
                                        _businessConsultationModeLine(
                                          state,
                                          item,
                                        ),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall,
                                      ),
                                      Text(item.goal ?? '운동 목표 미등록'),
                                      if (item.sharedRecommendationProfile !=
                                              null &&
                                          item.recommendationProfileShareRevokedAt ==
                                              null)
                                        Text(
                                          '정밀 추천 정보 공유됨',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color:
                                                    context.setflowColors.teal,
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                      Text(
                                        item.question ?? '질문 내용이 없습니다.',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                      if (item.assignedTrainerId case final id?)
                                        Text(
                                          '담당 · ${_businessTrainerName(state, id)}',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelSmall,
                                        ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _answerLive(
    BuildContext context,
    BusinessConsultation consultation,
  ) async {
    if (_openConsultationIds.contains(consultation.id)) return;
    setState(() => _openConsultationIds.add(consultation.id));
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var submitting = false;
    var assigning = false;
    final activeTrainers = AppScope.of(context).businessTrainers
        .where(
          (item) =>
              item.status == 'active' &&
              item.trainerId != null &&
              item.displayName != null,
        )
        .toList(growable: false);
    var assignedTrainerId = consultation.assignedTrainerId;
    var selectedTrainerId =
        activeTrainers.any((item) => item.trainerId == assignedTrainerId)
        ? assignedTrainerId
        : null;
    Future<void>? sheetCompleted;
    try {
      await showSetflowSheet<void>(
        context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) {
          sheetCompleted ??= ModalRoute.of(sheetContext)?.completed;
          return StatefulBuilder(
            builder: (sheetContext, setSheetState) => Padding(
              padding: EdgeInsets.fromLTRB(
                SetflowSpacing.xxl,
                4,
                SetflowSpacing.xxl,
                MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${consultation.memberName ?? '회원'}님의 상담',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: SetflowSpacing.xs2),
                      Text(
                        _businessConsultationModeLine(
                          AppScope.of(context),
                          consultation,
                        ),
                        style: Theme.of(sheetContext).textTheme.labelMedium
                            ?.copyWith(
                              color: Theme.of(
                                sheetContext,
                              ).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: SetflowSpacing.sm),
                      Text(consultation.question ?? '질문 내용이 없습니다.'),
                      if (consultation.sharedRecommendationProfile != null &&
                          consultation.recommendationProfileShareRevokedAt ==
                              null) ...[
                        const SizedBox(height: SetflowSpacing.lg),
                        SetflowCard(
                          key: const ValueKey(
                            'trainer-shared-recommendation-profile',
                          ),
                          color: context.setflowColors.teal.withValues(
                            alpha: .07,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '회원이 공유한 정밀 추천 정보',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: SetflowSpacing.xs),
                              Text(
                                '이 상담을 위해 회원이 명시적으로 제공한 설문 사본입니다. 회복 상태의 기록 날짜를 함께 확인하세요.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      height: 1.4,
                                    ),
                              ),
                              const Divider(height: 22),
                              RecommendationProfileSummary(
                                profile:
                                    consultation.sharedRecommendationProfile!,
                                compact: true,
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (widget.role == UserRole.gym) ...[
                        const SizedBox(height: SetflowSpacing.lg),
                        DropdownButtonFormField<String>(
                          key: const Key('consultation-trainer-select'),
                          initialValue: selectedTrainerId,
                          decoration: const InputDecoration(
                            labelText: '담당 트레이너',
                          ),
                          items: [
                            for (final trainer in activeTrainers)
                              DropdownMenuItem(
                                value: trainer.trainerId,
                                child: Text(trainer.displayName!),
                              ),
                          ],
                          onChanged: assigning
                              ? null
                              : (value) => setSheetState(
                                  () => selectedTrainerId = value,
                                ),
                        ),
                        const SizedBox(height: SetflowSpacing.sm2),
                        AppButton(
                          key: const Key('consultation-assign-trainer'),
                          label: assigning ? '배정 중...' : '트레이너에게 배정',
                          icon: Icons.assignment_ind_outlined,
                          variant: AppButtonVariant.tonal,
                          onPressed:
                              assigning ||
                                  selectedTrainerId == null ||
                                  selectedTrainerId == assignedTrainerId
                              ? null
                              : () async {
                                  setSheetState(() => assigning = true);
                                  try {
                                    await AppScope.of(
                                      context,
                                    ).assignBusinessConsultation(
                                      consultationId: consultation.id,
                                      trainerId: selectedTrainerId!,
                                    );
                                    if (!sheetContext.mounted || !mounted) {
                                      return;
                                    }
                                    setSheetState(() {
                                      assignedTrainerId = selectedTrainerId;
                                      assigning = false;
                                    });
                                    AppSnackbar.success(
                                      context,
                                      '담당 트레이너에게 상담을 배정했어요.',
                                    );
                                  } catch (_) {
                                    if (mounted) {
                                      AppSnackbar.error(
                                        context,
                                        '상담을 배정하지 못했어요.',
                                      );
                                    }
                                    if (sheetContext.mounted) {
                                      setSheetState(() => assigning = false);
                                    }
                                  }
                                },
                        ),
                      ],
                      const SizedBox(height: SetflowSpacing.xl),
                      AppTextField(
                        controller: controller,
                        maxLines: 4,
                        label: '답변 작성',
                        hint: '회원이 바로 실행할 수 있도록 구체적으로 작성해주세요.',
                        validator: (value) {
                          final answer = value?.trim() ?? '';
                          if (answer.length < 10) return '답변을 10자 이상 입력해주세요.';
                          return null;
                        },
                      ),
                      const SizedBox(height: SetflowSpacing.lg),
                      AppButton(
                        label: submitting
                            ? '전송 중...'
                            : doneLabel(_hasBusinessReply(consultation)),
                        icon: Icons.send_rounded,
                        onPressed: submitting
                            ? null
                            : () async {
                                if (!(formKey.currentState?.validate() ??
                                    false)) {
                                  return;
                                }
                                setSheetState(() => submitting = true);
                                try {
                                  await AppScope.of(
                                    context,
                                  ).answerBusinessConsultationById(
                                    role: widget.role,
                                    consultationId: consultation.id,
                                    answer: controller.text.trim(),
                                  );
                                  if (!sheetContext.mounted || !mounted) return;
                                  Navigator.pop(sheetContext);
                                  AppSnackbar.success(context, '상담 답변을 보냈어요.');
                                } catch (_) {
                                  if (mounted) {
                                    AppSnackbar.error(context, '답변을 보내지 못했어요.');
                                  }
                                  if (sheetContext.mounted) {
                                    setSheetState(() => submitting = false);
                                  }
                                }
                              },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    } finally {
      await sheetCompleted;
      controller.dispose();
      if (mounted) {
        setState(() => _openConsultationIds.remove(consultation.id));
      }
    }
  }

  Future<void> _answer(
    BuildContext context,
    int index,
    (String, String, String) item,
  ) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    Future<void>? sheetCompleted;
    await showSetflowSheet<void>(
      context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        sheetCompleted ??= ModalRoute.of(sheetContext)?.completed;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            SetflowSpacing.xxl,
            4,
            SetflowSpacing.xxl,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
          ),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item.$1}님의 상담',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: SetflowSpacing.xs2),
                  Text(
                    '${item.$2} · ${item.$3}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: SetflowSpacing.xl),
                  AppTextField(
                    controller: controller,
                    maxLines: 4,
                    label: '답변 작성',
                    hint: '회원이 바로 실행할 수 있도록 구체적으로 작성해주세요.',
                    validator: (value) {
                      final answer = value?.trim() ?? '';
                      if (answer.isEmpty) return '상담 답변을 입력해주세요.';
                      if (answer.length < 10) return '답변을 10자 이상 입력해주세요.';
                      return null;
                    },
                  ),
                  const SizedBox(height: SetflowSpacing.lg),
                  AppButton(
                    label: doneLabel(
                      AppScope.of(
                        context,
                      ).isBusinessConsultationAnswered(widget.role, index),
                    ),
                    icon: Icons.send_rounded,
                    onPressed: () {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      AppScope.of(context).answerBusinessConsultation(
                        role: widget.role,
                        consultationIndex: index,
                        answer: controller.text.trim(),
                      );
                      Navigator.pop(sheetContext);
                      AppSnackbar.success(
                        context,
                        '${item.$1}님에게 상담 답변을 보냈어요.',
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    await sheetCompleted;
    controller.dispose();
  }
}

String doneLabel(bool answered) => answered ? '답변 다시 보내기' : '답변 보내기';

bool _hasBusinessReply(BusinessConsultation consultation) {
  if (consultation.status == BusinessConsultationStatus.answered ||
      consultation.status == BusinessConsultationStatus.replied) {
    return true;
  }
  return consultation.messages.any(
    (message) =>
        message.sender == BusinessMessageSender.trainer ||
        message.sender == BusinessMessageSender.gym,
  );
}

String _businessConsultationModeLine(
  AppState state,
  BusinessConsultation consultation,
) {
  final location = switch (consultation.matchingSource) {
    ConsultationMatchingSource.gym => consultation.gymName,
    ConsultationMatchingSource.region =>
      state.serviceRegions
              .where(
                (region) => region.code == consultation.requestedRegionCode,
              )
              .firstOrNull
              ?.name ??
          consultation.requestedRegionCode,
    ConsultationMatchingSource.direct => consultation.gymName,
  };
  return location == null
      ? consultation.mode.label
      : '${consultation.mode.label} · $location';
}

String _businessTrainerName(AppState state, String trainerId) =>
    state.businessTrainers
        .where((item) => item.trainerId == trainerId)
        .map((item) => item.displayName)
        .whereType<String>()
        .firstOrNull ??
    '담당 트레이너';

class TrainerManagementPage extends StatefulWidget {
  const TrainerManagementPage({super.key});

  @override
  State<TrainerManagementPage> createState() => _TrainerManagementPageState();
}

class _TrainerManagementPageState extends State<TrainerManagementPage> {
  final searchController = TextEditingController();
  String query = '';
  String filter = 'all';

  static const demoTrainers = [
    ('김코치', '18명', 98, 4.9, 4800000.0),
    ('박트레이너', '15명', 94, 4.8, 3900000.0),
    ('이코치', '12명', 78, 4.6, 2700000.0),
    ('최코치', '9명', 96, 4.9, 2100000.0),
  ];

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final trainers = state.usesLiveBusinessData
        ? state.businessTrainers
              .map(
                (trainer) => (
                  trainer.displayName ?? '이름 미등록',
                  '${trainer.memberCount}명',
                  trainer.feedbackFulfillmentRate.round().clamp(0, 100),
                  trainer.averageRating,
                  trainer.monthlySales,
                ),
              )
              .toList(growable: false)
        : demoTrainers;
    final visible = trainers.indexed.where((entry) {
      final trainer = entry.$2;
      final matchesQuery = trainer.$1.contains(query.trim());
      final matchesFilter = switch (filter) {
        'excellent' => trainer.$3 >= 95,
        'attention' => trainer.$3 < 90,
        _ => true,
      };
      return matchesQuery && matchesFilter;
    }).toList();
    final visitingTrainerCount = state.coachingSessionRecords
        .map((item) => item.trainerId)
        .toSet()
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('트레이너'),
        actions: [
          IconButton(
            tooltip: '트레이너 초대',
            onPressed: _showInviteSheet,
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: SetflowInsets.pageHeader,
            child: Column(
              children: [
                AppTextField(
                  controller: searchController,
                  onChanged: (value) => setState(() => query = value),
                  prefixIcon: const Icon(Icons.search_rounded),
                  hint: '트레이너 이름 검색',
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '검색어 지우기',
                          onPressed: _resetSearch,
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
                const SizedBox(height: SetflowSpacing.md),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _trainerFilterChip('all', '전체 ${trainers.length}'),
                      const SizedBox(width: SetflowSpacing.sm),
                      _trainerFilterChip('excellent', '우수 성과'),
                      const SizedBox(width: SetflowSpacing.sm),
                      _trainerFilterChip('attention', '피드백 필요'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (state.usesLiveBusinessData && visitingTrainerCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SetflowSpacing.lg,
                0,
                SetflowSpacing.lg,
                SetflowSpacing.md,
              ),
              child: SetflowCard(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const VisitingTrainerSessionsPage(),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      color: context.setflowColors.teal,
                    ),
                    const SizedBox(width: SetflowSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '우리 지점 수업 트레이너',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            '고용 여부와 무관 · 공유된 수업 기록 기준',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '$visitingTrainerCount명',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
          Expanded(
            child: visible.isEmpty
                ? EmptyState(
                    icon: Icons.manage_search_rounded,
                    title: '조건에 맞는 트레이너가 없어요',
                    message: '검색어와 성과 필터를 초기화한 뒤 다시 확인해주세요.',
                    actionLabel: '검색·필터 초기화',
                    onAction: () {
                      _resetSearch();
                      setState(() => filter = 'all');
                    },
                  )
                : ListView.builder(
                    padding: SetflowInsets.pageListTight,
                    itemCount: visible.length,
                    itemBuilder: (_, visibleIndex) {
                      final index = visible[visibleIndex].$1;
                      final trainer = visible[visibleIndex].$2;
                      final accentColor = [
                        context.setflowColors.blue,
                        context.setflowColors.teal,
                        context.setflowColors.orange,
                        context.setflowColors.purple,
                      ][index % 4];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SetflowCard(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => TrainerPerformancePage(
                                name: trainer.$1,
                                membersLabel: trainer.$2,
                                feedbackRate: '${trainer.$3}%',
                                rating: trainer.$4,
                                monthlySales: trainer.$5,
                                liveData: state.usesLiveBusinessData,
                                accentColor: accentColor,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: accentColor.withValues(
                                  alpha: .16,
                                ),
                                child: Text(
                                  trainer.$1.characters.first,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: SetflowSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      trainer.$1,
                                      style: const TextStyle(
                                        fontSize: SetflowFontSize.title,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      '회원 ${trainer.$2}/25명 · 피드백 ${trainer.$3}%',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                children: [
                                  // 별점은 후기 별과 같은 오렌지 — 라임은
                                  // 밝은 면 위에서 사라진다.
                                  Icon(
                                    Icons.star_rounded,
                                    color: context.setflowColors.orange,
                                    size: 19,
                                  ),
                                  Text(
                                    '${trainer.$4}',
                                    style: const TextStyle(
                                      fontSize: SetflowFontSize.small,
                                      fontWeight: SetflowWeight.medium,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: SetflowSpacing.xs),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _trainerFilterChip(String value, String label) {
    return FilterChip(
      label: Text(label),
      selected: filter == value,
      onSelected: (_) => setState(() => filter = value),
    );
  }

  void _resetSearch() {
    searchController.clear();
    setState(() => query = '');
  }

  Future<void> _showInviteSheet() async {
    final state = AppScope.of(context);
    if (state.usesLiveBusinessData) {
      await showSetflowSheet<void>(
        context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _GymBusinessInviteSheet(
          state: state,
          kind: BusinessInviteKind.trainer,
        ),
      );
      return;
    }
    const inviteLink = 'https://setflow.app/invite/trainer-GYM7K2';
    await showSetflowSheet<void>(
      context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: SetflowInsets.pageForm,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '트레이너 초대',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: SetflowSpacing.sm),
              Text(
                '아래 링크로 가입한 트레이너는 센터 승인 대기 목록에 추가됩니다.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: SetflowSpacing.xl),
              SetflowCard(
                child: const SelectableText(
                  inviteLink,
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: SetflowSpacing.lg),
              AppButton(
                label: '링크 복사',
                icon: Icons.copy_rounded,
                onPressed: () async {
                  await Clipboard.setData(
                    const ClipboardData(text: inviteLink),
                  );
                  if (!mounted || !sheetContext.mounted) return;
                  Navigator.pop(sheetContext);
                  AppSnackbar.success(context, '트레이너 초대 링크를 복사했어요.');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VisitingTrainerSessionsPage extends StatelessWidget {
  const VisitingTrainerSessionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final records = AppScope.of(context).coachingSessionRecords;
    final trainerIds = <String>[];
    for (final record in records) {
      if (!trainerIds.contains(record.trainerId)) {
        trainerIds.add(record.trainerId);
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('우리 지점 수업 트레이너')),
      body: trainerIds.isEmpty
          ? const EmptyState(
              icon: Icons.location_off_outlined,
              title: '공유된 외부 수업이 없어요',
              message: '트레이너가 이 지점의 수업 기록을 공유하면 여기에 표시됩니다.',
            )
          : ListView.builder(
              padding: SetflowInsets.pageList,
              itemCount: trainerIds.length,
              itemBuilder: (context, index) {
                final trainerRecords = records
                    .where((item) => item.trainerId == trainerIds[index])
                    .toList(growable: false);
                final latest = trainerRecords.first;
                final memberCount = trainerRecords
                    .map((item) => item.memberUserId)
                    .toSet()
                    .length;
                return Padding(
                  padding: const EdgeInsets.only(bottom: SetflowSpacing.md),
                  child: SetflowCard(
                    onTap: () => _showTrainerRecords(
                      context,
                      latest.trainerName,
                      trainerRecords,
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          child: Text(latest.trainerName.characters.first),
                        ),
                        const SizedBox(width: SetflowSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                latest.trainerName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                '회원 $memberCount명 · 공유 수업 ${trainerRecords.length}건',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _showTrainerRecords(
    BuildContext context,
    String trainerName,
    List<CoachingSessionRecord> records,
  ) => showSetflowSheet<void>(
    context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .78,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: SetflowInsets.pageListTight,
        children: [
          Text(trainerName, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: SetflowSpacing.xs),
          Text(
            '우리 헬스장에서 실제 진행되어 공유된 기록만 표시됩니다. 센터 소속 또는 고용 관계를 의미하지 않습니다.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: SetflowSpacing.xl),
          for (final record in records)
            Padding(
              padding: const EdgeInsets.only(bottom: SetflowSpacing.sm),
              child: _CoachingSessionRecordCard(record: record),
            ),
        ],
      ),
    ),
  );
}

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});
  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  final searchController = TextEditingController();
  String query = '';
  String filter = 'all';

  static const users = [
    ('운동초보', 'beginner@setflow.app', '무료'),
    ('으라차차', 'muscle@setflow.app', '프리미엄'),
    ('다이어터', 'diet@setflow.app', '무료'),
    ('요가러버', 'yoga@setflow.app', '프리미엄'),
  ];

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (state.usesLiveBusinessData) {
      return Scaffold(
        appBar: AppBar(title: const Text('회원 관리')),
        body: const EmptyState(
          key: ValueKey('admin-users-live-unavailable'),
          icon: Icons.manage_accounts_outlined,
          title: '회원 관리 API가 아직 연결되지 않았어요',
          message: '실제 계정 조회와 제재 RPC가 준비되기 전에는 임의 회원 정보를 표시하지 않습니다.',
        ),
      );
    }
    final visible = users.indexed.where((entry) {
      final index = entry.$1;
      final user = entry.$2;
      final blocked = state.isAdminUserBlocked(user.$2, fallback: index == 2);
      final keyword = query.trim().toLowerCase();
      final matchesQuery =
          keyword.isEmpty ||
          user.$1.toLowerCase().contains(keyword) ||
          user.$2.toLowerCase().contains(keyword);
      final matchesFilter = switch (filter) {
        'active' => !blocked,
        'blocked' => blocked,
        'premium' => user.$3 == '프리미엄',
        _ => true,
      };
      return matchesQuery && matchesFilter;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('회원 관리')),
      body: Column(
        children: [
          Padding(
            padding: SetflowInsets.pageHeader,
            child: Column(
              children: [
                AppTextField(
                  controller: searchController,
                  onChanged: (value) => setState(() => query = value),
                  prefixIcon: const Icon(Icons.search_rounded),
                  hint: '닉네임 또는 이메일 검색',
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '검색어 지우기',
                          onPressed: _resetAdminUserFilters,
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
                const SizedBox(height: SetflowSpacing.md),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _adminUserFilterChip('all', '전체 ${users.length}'),
                      const SizedBox(width: SetflowSpacing.sm),
                      _adminUserFilterChip('active', '정상 이용'),
                      const SizedBox(width: SetflowSpacing.sm),
                      _adminUserFilterChip('blocked', '이용 제한'),
                      const SizedBox(width: SetflowSpacing.sm),
                      _adminUserFilterChip('premium', '프리미엄'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? EmptyState(
                    icon: Icons.person_search_outlined,
                    title: '조건에 맞는 회원이 없어요',
                    message: '검색어와 계정 상태 필터를 초기화해주세요.',
                    actionLabel: '검색·필터 초기화',
                    onAction: _resetAdminUserFilters,
                  )
                : ListView.builder(
                    padding: SetflowInsets.pageListTight,
                    itemCount: visible.length,
                    itemBuilder: (_, visibleIndex) {
                      final index = visible[visibleIndex].$1;
                      final user = visible[visibleIndex].$2;
                      final blocked = state.isAdminUserBlocked(
                        user.$2,
                        fallback: index == 2,
                      );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SetflowCard(
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    child: Text(user.$1.characters.first),
                                  ),
                                  const SizedBox(width: SetflowSpacing.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 7,
                                          runSpacing: 4,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            Text(
                                              user.$1,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            _statusPill(
                                              label: user.$3,
                                              color: user.$3 == '프리미엄'
                                                  ? context.setflowColors.orange
                                                  : Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                            ),
                                          ],
                                        ),
                                        Text(
                                          user.$2,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    tooltip: '회원 관리 메뉴',
                                    onSelected: (value) async {
                                      if (value == 'view') {
                                        _showAdminUserDetails(
                                          user,
                                          blocked,
                                          index,
                                        );
                                      } else {
                                        await _confirmAdminUserRestriction(
                                          user,
                                          blocked,
                                        );
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(
                                        value: 'view',
                                        child: Text('상세 보기'),
                                      ),
                                      PopupMenuItem(
                                        value: 'block',
                                        child: Text(
                                          blocked ? '제재 해제' : '계정 제재',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const Divider(height: 24),
                              Row(
                                children: [
                                  Text(
                                    '가입일 2026.0${index + 3}.12',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: blocked
                                          ? Theme.of(context).colorScheme.error
                                          : context.setflowColors.success,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: SetflowSpacing.xs2),
                                  Text(
                                    blocked ? '이용 제한' : '정상 이용',
                                    style: TextStyle(
                                      fontSize: SetflowFontSize.small,
                                      fontWeight: FontWeight.w800,
                                      color: blocked
                                          ? Theme.of(context).colorScheme.error
                                          : context.setflowColors.success,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _adminUserFilterChip(String value, String label) {
    return FilterChip(
      label: Text(label),
      selected: filter == value,
      onSelected: (_) => setState(() => filter = value),
    );
  }

  void _resetAdminUserFilters() {
    searchController.clear();
    setState(() {
      query = '';
      filter = 'all';
    });
  }

  Future<void> _confirmAdminUserRestriction(
    (String, String, String) user,
    bool blocked,
  ) async {
    final formKey = GlobalKey<FormState>();
    var reason = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text(blocked ? '계정 제재를 해제할까요?' : '계정 이용을 제한할까요?'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${user.$1} · ${user.$2}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (!blocked) ...[
                const SizedBox(height: SetflowSpacing.lg),
                TextFormField(
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '제재 사유',
                    hintText: '회원에게 안내할 구체적인 사유를 입력해주세요.',
                  ),
                  onChanged: (value) => reason = value.trim(),
                  validator: (value) {
                    if ((value?.trim().length ?? 0) < 5) {
                      return '제재 사유를 5자 이상 입력해주세요.';
                    }
                    return null;
                  },
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              if (!blocked && !(formKey.currentState?.validate() ?? false)) {
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: Text(blocked ? '제재 해제' : '이용 제한'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    AppScope.of(context).setAdminUserBlocked(
      email: user.$2,
      blocked: !blocked,
      reason: blocked ? '관리자 제재 해제' : reason,
    );
    AppSnackbar.success(
      context,
      blocked ? '${user.$1}님의 제재를 해제했어요.' : '${user.$1}님의 계정을 제한했어요.',
    );
  }

  void _showAdminUserDetails(
    (String, String, String) user,
    bool blocked,
    int index,
  ) {
    showSetflowSheet<void>(
      context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: SetflowInsets.pageForm,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.$1, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: SetflowSpacing.xs),
              Text(
                user.$2,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: SetflowSpacing.xl),
              SetflowCard(
                child: Column(
                  children: [
                    _infoRow(label: '이용 플랜', value: user.$3),
                    const Divider(height: 24),
                    _infoRow(
                      label: '계정 상태',
                      value: blocked ? '이용 제한' : '정상 이용',
                    ),
                    const Divider(height: 24),
                    _infoRow(label: '가입일', value: '2026.0${index + 3}.12'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusPill({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(SetflowRadii.sm),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: SetflowFontSize.tiny,
          fontWeight: SetflowWeight.medium,
        ),
      ),
    );
  }

  Widget _infoRow({required String label, required String value}) {
    return Row(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Spacer(),
        Text(value, style: TextStyle(fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class AdminReviewPage extends StatefulWidget {
  const AdminReviewPage({super.key});
  @override
  State<AdminReviewPage> createState() => _AdminReviewPageState();
}

class _AdminReviewPageState extends State<AdminReviewPage> {
  final Set<String> _savingApplicationIds = {};

  /// 아이콘·색·제목 묶음. 색이 테마를 따라야 해서 const 리터럴에서 함수가 됐다.
  List<(IconData, Color, String, String)> _contentReviewEntries(
    BuildContext context,
  ) => [
    (
      Icons.fitness_center_outlined,
      context.setflowColors.teal,
      '루틴 심사',
      '키워드 탐지 검토',
    ),
    (
      Icons.report_gmailerrorred_outlined,
      context.setflowColors.error,
      '신고 처리',
      '유저 신고 대기열',
    ),
    (
      Icons.history_outlined,
      context.setflowColors.purple,
      '제재 이력',
      '유저 제재 누적 이력',
    ),
    (
      Icons.warning_amber_outlined,
      context.setflowColors.orange,
      '미성년 알림',
      '위험 행동 감지',
    ),
  ];

  Widget _contentReviewScreenFor(int index) => switch (index) {
    0 => const AdminContentRoutinesScreen(),
    1 => const AdminContentReportsScreen(),
    2 => const AdminUserSanctionHistoryScreen(),
    _ => const AdminContentMinorAlertsScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (state.usesLiveBusinessData) {
      return _buildLiveApplications(context, state);
    }
    final latestAudit = state
        .dashboardFor(UserRole.admin)
        .facts['audit.latest'];
    const queue = [
      ('트레이너', '이현우', '생활스포츠지도사 · NSCA-CPT'),
      ('헬스장', '바디랩 역삼', '사업자등록증 · 홈택스 정상'),
      ('트레이너', '정수빈', 'NASM-CPT · 신분증'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('인증 심사 큐')),
      body: Column(
        children: [
          SizedBox(
            height: 116,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                SetflowSpacing.gutter,
                12,
                SetflowSpacing.gutter,
                4,
              ),
              scrollDirection: Axis.horizontal,
              itemCount: _contentReviewEntries(context).length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: SetflowSpacing.sm2),
              itemBuilder: (context, index) {
                final entry = _contentReviewEntries(context)[index];
                return SizedBox(
                  width: 132,
                  child: SetflowCard(
                    padding: const EdgeInsets.all(12),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _contentReviewScreenFor(index),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(entry.$1, color: entry.$2),
                        const SizedBox(height: SetflowSpacing.sm),
                        Text(
                          entry.$3,
                          style: const TextStyle(
                            fontSize: SetflowFontSize.label,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: SetflowSpacing.xxs),
                        Text(
                          entry.$4,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: SetflowFontSize.tiny,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (latestAudit != null)
            Padding(
              padding: SetflowInsets.pageHeader,
              child: SetflowCard(
                padding: const EdgeInsets.all(SetflowSpacing.md),
                child: Row(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 18,
                      // 라임 아이콘은 밝은 카드 위에서 사라진다 — 읽는 브랜드.
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    const SizedBox(width: SetflowSpacing.sm),
                    Expanded(
                      child: Text(
                        '최근 처리 · $latestAudit',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: SetflowInsets.pageList,
              itemCount: queue.length,
              itemBuilder: (_, index) {
                final item = queue[index];
                final reviewId = 'review_$index';
                final status = state.adminReviewStatus(reviewId);
                final done = status != 'pending';
                final approved = status == 'approved';
                final rejectReason = state
                    .dashboardFor(UserRole.admin)
                    .facts['adminReview.$reviewId.reason'];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SetflowCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    (item.$1 == '트레이너'
                                            ? context.setflowColors.blue
                                            : context.setflowColors.purple)
                                        .withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(
                                  SetflowRadii.xs,
                                ),
                              ),
                              child: Text(
                                item.$1,
                                style: TextStyle(
                                  fontSize: SetflowFontSize.tiny,
                                  fontWeight: SetflowWeight.medium,
                                  color: item.$1 == '트레이너'
                                      ? context.setflowColors.blue
                                      : context.setflowColors.purple,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              approved
                                  ? '승인 완료'
                                  : status == 'rejected'
                                  ? '반려 완료'
                                  : 'D-2',
                              style: TextStyle(
                                fontSize: SetflowFontSize.small,
                                fontWeight: SetflowWeight.medium,
                                color: approved
                                    ? context.setflowColors.success
                                    : status == 'rejected'
                                    ? Theme.of(context).colorScheme.error
                                    : context.setflowColors.orange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: SetflowSpacing.md),
                        Text(
                          item.$2,
                          style: const TextStyle(
                            fontSize: SetflowFontSize.titleLarge,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: SetflowSpacing.xs),
                        Text(
                          item.$3,
                          style: TextStyle(
                            fontSize: SetflowFontSize.caption,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: SetflowSpacing.lg),
                        if (!done)
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () =>
                                      _rejectReview(reviewId, item.$2),
                                  child: const Text('거절'),
                                ),
                              ),
                              const SizedBox(width: SetflowSpacing.sm2),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () => _approveReview(
                                    reviewId,
                                    item.$2,
                                    item.$3,
                                  ),
                                  // 잉크 배경을 덮어쓰면 기본 전경(onPrimary=잉크)과
                                  // 겹쳐 '승인'이 검정 위 검정으로 사라진다 —
                                  // 실제로 글자 없는 검은 버튼으로 보였다.
                                  child: const Text('승인'),
                                ),
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              Icon(
                                approved
                                    ? Icons.check_circle
                                    : Icons.cancel_rounded,
                                color: approved
                                    ? context.setflowColors.success
                                    : Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(width: SetflowSpacing.sm),
                              Expanded(
                                child: Text(
                                  approved
                                      ? '인증 배지를 발급했습니다.'
                                      : '반려 사유 · ${rejectReason ?? '서류 확인 필요'}',
                                  style: TextStyle(
                                    color: approved
                                        ? context.setflowColors.success
                                        : Theme.of(context).colorScheme.error,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveApplications(BuildContext context, AppState state) {
    final applications = state.businessApplications;
    return Scaffold(
      appBar: AppBar(
        title: const Text('인증 심사 큐'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: () async {
              try {
                await state.refreshBusinessDashboard(UserRole.admin);
              } catch (_) {
                if (context.mounted) {
                  AppSnackbar.error(context, '심사 목록을 불러오지 못했어요.');
                }
              }
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: applications.isEmpty
          ? const EmptyState(
              key: ValueKey('business-applications-empty'),
              icon: Icons.fact_check_outlined,
              title: '대기 중인 인증 신청이 없어요',
              message: '트레이너 또는 센터 신청이 접수되면 이곳에 표시됩니다.',
            )
          : ListView.builder(
              padding: SetflowInsets.pageList,
              itemCount: applications.length,
              itemBuilder: (context, index) {
                final application = applications[index];
                final pending =
                    application.status == BusinessApplicationStatus.pending;
                final rejected =
                    application.status == BusinessApplicationStatus.rejected;
                final saving = _savingApplicationIds.contains(application.id);
                final statusLabel = switch (application.status) {
                  BusinessApplicationStatus.pending => '심사 대기',
                  BusinessApplicationStatus.approved => '승인 완료',
                  BusinessApplicationStatus.rejected => '반려 완료',
                  BusinessApplicationStatus.unknown => '상태 확인 필요',
                };
                final statusColor = switch (application.status) {
                  BusinessApplicationStatus.pending =>
                    context.setflowColors.orange,
                  BusinessApplicationStatus.approved =>
                    context.setflowColors.success,
                  BusinessApplicationStatus.rejected => Theme.of(
                    context,
                  ).colorScheme.error,
                  BusinessApplicationStatus.unknown => Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant,
                };
                final typeLabel =
                    application.kind == BusinessApplicationKind.trainer
                    ? '트레이너'
                    : '헬스장';
                final detail =
                    application.kind == BusinessApplicationKind.trainer
                    ? '트레이너 자격 및 제출 정보 확인'
                    : '사업자번호 ${application.businessNumber ?? '미등록'}';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SetflowCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Chip(label: Text(typeLabel)),
                            const Spacer(),
                            Text(
                              statusLabel,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: SetflowSpacing.sm2),
                        Text(
                          application.applicantName,
                          style: const TextStyle(
                            fontSize: SetflowFontSize.titleLarge,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: SetflowSpacing.xs),
                        Text(detail),
                        if (rejected && application.rejectReason != null) ...[
                          const SizedBox(height: SetflowSpacing.sm),
                          Text(
                            '반려 사유 · ${application.rejectReason}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        if (pending) ...[
                          const SizedBox(height: SetflowSpacing.lg),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: saving
                                      ? null
                                      : () => _rejectReview(
                                          application.id,
                                          application.applicantName,
                                        ),
                                  child: Text(saving ? '처리 중' : '반려'),
                                ),
                              ),
                              const SizedBox(width: SetflowSpacing.sm2),
                              Expanded(
                                child: FilledButton(
                                  onPressed: saving
                                      ? null
                                      : () => _approveReview(
                                          application.id,
                                          application.applicantName,
                                          detail,
                                        ),
                                  child: Text(saving ? '처리 중' : '승인'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _approveReview(
    String reviewId,
    String applicantName,
    String documents,
  ) async {
    if (_savingApplicationIds.contains(reviewId)) return;
    setState(() => _savingApplicationIds.add(reviewId));
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('인증을 승인할까요?'),
          content: Text('$applicantName\n$documents\n\n승인 즉시 인증 배지가 발급됩니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('승인 및 배지 발급'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      try {
        await AppScope.of(context).completeAdminReview(
          reviewId: reviewId,
          applicantName: applicantName,
          status: 'approved',
        );
        if (mounted) {
          AppSnackbar.success(context, '$applicantName 인증을 승인했어요.');
        }
      } catch (_) {
        if (mounted) AppSnackbar.error(context, '인증 승인에 실패했어요.');
      }
    } finally {
      if (mounted) setState(() => _savingApplicationIds.remove(reviewId));
    }
  }

  Future<void> _rejectReview(String reviewId, String applicantName) async {
    if (_savingApplicationIds.contains(reviewId)) return;
    setState(() => _savingApplicationIds.add(reviewId));
    final formKey = GlobalKey<FormState>();
    var reason = '';
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: const Text('인증을 반려할까요?'),
          content: Form(
            key: formKey,
            child: TextFormField(
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '반려 사유',
                hintText: '재제출할 서류나 수정 사항을 입력해주세요.',
              ),
              onChanged: (value) => reason = value.trim(),
              validator: (value) {
                if ((value?.trim().length ?? 0) < 5) {
                  return '반려 사유를 5자 이상 입력해주세요.';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                Navigator.pop(dialogContext, true);
              },
              child: const Text('반려 사유 전송'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      try {
        await AppScope.of(context).completeAdminReview(
          reviewId: reviewId,
          applicantName: applicantName,
          status: 'rejected',
          reason: reason,
        );
        if (mounted) {
          AppSnackbar.success(context, '$applicantName 인증을 반려했어요.');
        }
      } catch (_) {
        if (mounted) AppSnackbar.error(context, '인증 반려 처리에 실패했어요.');
      }
    } finally {
      if (mounted) setState(() => _savingApplicationIds.remove(reviewId));
    }
  }
}

class SettlementPage extends StatefulWidget {
  const SettlementPage({required this.role, super.key});
  final UserRole role;

  @override
  State<SettlementPage> createState() => _SettlementPageState();
}

class _SettlementPageState extends State<SettlementPage> {
  final searchController = TextEditingController();
  String query = '';
  String filter = 'all';

  UserRole get role => widget.role;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (state.usesLiveBusinessData) {
      return _buildLiveSettlement(context, state);
    }
    final admin = role == UserRole.admin;
    const allSettlements = [
      ('단기 코칭', '김코치 · 박민지', '350,000원', 'D+7', 'scheduled'),
      ('장기 코칭', '박트레이너 · 이준호', '680,000원', '월 분할', 'scheduled'),
      ('환불 보류', '이코치 · 최서연', '120,000원', '검토 중', 'hold'),
    ];
    final settlements = allSettlements.where((item) {
      final keyword = query.trim();
      final matchesQuery =
          keyword.isEmpty ||
          item.$1.contains(keyword) ||
          item.$2.contains(keyword);
      final matchesFilter = filter == 'all' || item.$5 == filter;
      return matchesQuery && matchesFilter;
    }).toList();
    return Scaffold(
      appBar: AppBar(title: Text(admin ? '정산 처리' : '정산')),
      body: ListView(
        padding: SetflowInsets.pageList,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              // 돈이 걸린 히어로는 어디서나 같은 잉크 블록이다 — 트레이너
              // 수익 카드와 같은 판(회색 슬랩은 혼자 다른 재질로 보였다).
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
                Text(
                  admin ? '이번 주 정산 예정' : '이번 달 정산 예정',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: SetflowFontSize.caption,
                  ),
                ),
                const SizedBox(height: SetflowSpacing.xs2),
                Text(
                  admin ? '48,620,000원' : '14,280,000원',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: SetflowFontSize.display,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: SetflowSpacing.md),
                const Text(
                  '에스크로 보호 적용 중',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: SetflowFontSize.small,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (!admin) ...[
            const SizedBox(height: SetflowSpacing.xl),
            // 요약 숫자는 상자 없이 — 회원 홈의 월 요약과 같은 문법.
            const Row(
              children: [
                Expanded(child: _SettlementFigure('매출', '18.4M')),
                Expanded(child: _SettlementFigure('코치', '3.8M')),
                Expanded(child: _SettlementFigure('보류', '0.32M')),
                Expanded(child: _SettlementFigure('입금', '14.28M')),
              ],
            ),
          ],
          const SizedBox(height: SetflowSpacing.xxl),
          AppTextField(
            controller: searchController,
            onChanged: (value) => setState(() => query = value),
            prefixIcon: const Icon(Icons.search_rounded),
            hint: '코칭 유형·트레이너·회원 검색',
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: '검색어 지우기',
                    onPressed: () {
                      searchController.clear();
                      setState(() => query = '');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
          const SizedBox(height: SetflowSpacing.md),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _settlementFilterChip('all', '전체'),
                const SizedBox(width: SetflowSpacing.sm),
                _settlementFilterChip('scheduled', '정산 예정'),
                const SizedBox(width: SetflowSpacing.sm),
                _settlementFilterChip('hold', '검토 필요'),
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.xxl),
          const SectionTitle('정산 내역'),
          const SizedBox(height: SetflowSpacing.sm2),
          if (settlements.isEmpty)
            EmptyState(
              icon: Icons.receipt_long_outlined,
              title: '조건에 맞는 정산 내역이 없어요',
              message: '검색어와 상태 필터를 초기화한 뒤 다시 확인해주세요.',
              actionLabel: '검색·필터 초기화',
              onAction: () {
                searchController.clear();
                setState(() {
                  query = '';
                  filter = 'all';
                });
              },
            )
          else
            // 내역은 읽는 목록 — 헤어라인 줄. 색은 상태(보류=경고)에만.
            for (final item in settlements)
              InkWell(
                onTap: () => _showSettlementDetail(context, item),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: SetflowSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        item.$1 == '환불 보류'
                            ? Icons.pause_circle_outline
                            : Icons.payments_outlined,
                        size: 20,
                        color: item.$1 == '환불 보류'
                            ? context.setflowColors.error
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: SetflowSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.$1,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: SetflowSpacing.xxs),
                            Text(
                              item.$2,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            item.$3,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                          Text(
                            item.$4,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: SetflowSpacing.xxl),
          const SectionTitle('상세'),
          // 상세로 가는 문들은 내비게이션 목록 — 마이·전체 메뉴와 같은 줄이다.
          _OperationShortcut(
            icon: Icons.receipt_long_outlined,
            color: context.setflowColors.error,
            title: '환불',
            subtitle: '환불 요청 및 처리 이력 확인',
            value: '',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettlementRefundsPage(role: role),
              ),
            ),
          ),
          if (role != UserRole.trainer)
            _OperationShortcut(
              icon: Icons.groups_outlined,
              color: context.setflowColors.blue,
              title: '코치별',
              subtitle: '소속 코치 매출·분배 내역',
              value: '',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TrainerSettlementBreakdownPage(role: role),
                ),
              ),
            ),
          if (admin) ...[
            _OperationShortcut(
              icon: Icons.percent_outlined,
              color: context.setflowColors.purple,
              title: '수수료 정산',
              subtitle: '사업자·트레이너별 수수료 산정 내역',
              value: '',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettlementCommissionPage(role: role),
                ),
              ),
            ),
            _OperationShortcut(
              icon: Icons.task_alt_outlined,
              color: context.setflowColors.success,
              title: '최종 정산 확정',
              subtitle: '지급 대상 확정 및 처리 상태 관리',
              value: '',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettlementFinalConfirmPage(role: role),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveSettlement(BuildContext context, AppState state) {
    if (role == UserRole.admin) {
      return Scaffold(
        appBar: AppBar(title: const Text('정산 처리')),
        body: const EmptyState(
          key: ValueKey('admin-settlements-live-unavailable'),
          icon: Icons.account_balance_outlined,
          title: '관리자 정산 집계 API가 아직 연결되지 않았어요',
          message: '실제 전체 원장 집계와 지급 처리 RPC가 준비되기 전에는 임의 금액을 표시하지 않습니다.',
        ),
      );
    }
    final metrics = state.businessWorkspace?.dashboardStats;
    final double primaryAmount = switch (role) {
      UserRole.trainer => metrics?.pendingSettlement ?? 0.0,
      UserRole.gym => metrics?.totalRevenue ?? 0.0,
      _ => 0.0,
    };
    return Scaffold(
      appBar: AppBar(title: Text(role == UserRole.admin ? '정산 처리' : '정산')),
      body: RefreshIndicator(
        onRefresh: () => state.refreshBusinessDashboard(role),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: SetflowInsets.pageList,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: role == UserRole.admin
                    ? SetflowColors.ink
                    : SetflowNeutral.n700,
                borderRadius: BorderRadius.circular(SetflowRadii.xl),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    role == UserRole.gym ? '누적 센터 매출' : '정산 예정 금액',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: SetflowFontSize.caption,
                    ),
                  ),
                  const SizedBox(height: SetflowSpacing.xs2),
                  Text(
                    '${_formatBusinessWon(primaryAmount)}원',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: SetflowFontSize.display,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: SetflowSpacing.sm),
                  const Text(
                    '서버 정산 원장 기준',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: SetflowFontSize.small,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: SetflowSpacing.md),
            Row(
              children: [
                MetricCard(
                  label: role == UserRole.gym ? '센터 회원' : '이번 달 지급',
                  value: role == UserRole.gym
                      ? '${metrics?.activeMembers ?? 0}'
                      : _formatBusinessWon(metrics?.monthSettled ?? 0),
                  suffix: role == UserRole.gym ? '명' : '원',
                  icon: role == UserRole.gym
                      ? Icons.people_outline_rounded
                      : Icons.account_balance_wallet_outlined,
                  tint: context.setflowColors.success,
                ),
                const SizedBox(width: SetflowSpacing.sm),
                MetricCard(
                  label: role == UserRole.gym ? '소속 트레이너' : '관리 회원',
                  value: role == UserRole.gym
                      ? '${metrics?.trainerCount ?? 0}'
                      : '${metrics?.activeMembers ?? 0}',
                  suffix: '명',
                  icon: Icons.people_outline_rounded,
                  tint: context.setflowColors.blue,
                ),
              ],
            ),
            const SizedBox(height: SetflowSpacing.xxl),
            const EmptyState(
              key: ValueKey('business-settlements-empty'),
              icon: Icons.receipt_long_outlined,
              title: '표시할 정산 내역이 없어요',
              message: '정산 거래가 생성되면 실제 원장 데이터가 이곳에 표시됩니다.',
            ),
          ],
        ),
      ),
    );
  }

  void _showSettlementDetail(
    BuildContext context,
    (String, String, String, String, String) item,
  ) {
    final hold = item.$5 == 'hold';
    showSetflowSheet<void>(
      context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: SetflowInsets.pageForm,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.$1, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: SetflowSpacing.lg),
              _SettlementDetailRow(label: '대상', value: item.$2),
              _SettlementDetailRow(label: '금액', value: item.$3),
              _SettlementDetailRow(label: '상태', value: item.$4),
              const SizedBox(height: SetflowSpacing.lg),
              AppButton(
                label: hold ? '검토' : '확인',
                icon: hold ? Icons.receipt_long_outlined : Icons.done_rounded,
                onPressed: () {
                  Navigator.pop(sheetContext);
                  if (hold) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SettlementRefundsPage(role: role),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settlementFilterChip(String value, String label) {
    return FilterChip(
      label: Text(label),
      selected: filter == value,
      onSelected: (_) => setState(() => filter = value),
    );
  }
}

class _SettlementFigure extends StatelessWidget {
  const _SettlementFigure(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: SetflowSpacing.xs),
        FittedBox(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _SettlementDetailRow extends StatelessWidget {
  const _SettlementDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SetflowSpacing.md),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onTap;

  // 오늘 할 일은 읽는 줄이 아니라 **집어 들 행동**이다 — 지표(큰 숫자)와
  // 목록(헤어라인) 사이에서 이것만 면 위로 들어 올린다(SetflowCard의 자리,
  // "들어 올릴 내용"). 전부 헤어라인으로 접었더니 "다 구분선 처리"로 읽혔다 —
  // 조화는 한 패턴의 반복이 아니라 역할별 형태다(2026-09-01 피드백).
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SetflowCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: SetflowSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: SetflowSpacing.xxs),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: SetflowSpacing.sm),
          Text(
            action,
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
          const SizedBox(width: SetflowSpacing.xs),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _PerformanceRow extends StatelessWidget {
  const _PerformanceRow({
    required this.label,
    required this.value,
    required this.change,
  });
  final String label;
  final String value;
  final String change;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      Text(
        value,
        style: const TextStyle(
          fontSize: SetflowFontSize.titleLarge,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(width: SetflowSpacing.sm2),
      Text(
        change,
        style: TextStyle(
          color: context.setflowColors.success,
          fontSize: SetflowFontSize.small,
          fontWeight: SetflowWeight.medium,
        ),
      ),
    ],
  );
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.name,
    required this.detail,
    required this.color,
  });
  final String name;
  final String detail;

  /// 옛 카드 시절의 지정색 — 인덱스 순환 색은 의미가 없어서 더는 칠하지
  /// 않는다(이니셜 아바타 자체는 정상 패턴이라 유지).
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleAvatar(
        backgroundColor: context.setflowColors.surfaceContainer,
        child: Text(
          name.characters.first,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      const SizedBox(width: SetflowSpacing.md),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w900)),
            Text(
              detail,
              style: TextStyle(
                fontSize: SetflowFontSize.small,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      const Icon(Icons.chevron_right),
    ],
  );
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final double value;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            '${(value * 100).toInt()}%',
            style: TextStyle(fontWeight: FontWeight.w900, color: color),
          ),
        ],
      ),
      const SizedBox(height: SetflowSpacing.sm),
      LinearProgressIndicator(
        value: value,
        minHeight: 8,
        borderRadius: BorderRadius.circular(SetflowRadii.xs),
        color: color,
        backgroundColor: color.withValues(alpha: .12),
      ),
    ],
  );
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.status,
    required this.color,
  });
  final String label;
  final String status;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: SetflowSpacing.sm2),
      Expanded(
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      Text(
        status,
        style: TextStyle(
          fontSize: SetflowFontSize.caption,
          color: color,
          fontWeight: SetflowWeight.medium,
        ),
      ),
    ],
  );
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: SetflowFontSize.title,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: SetflowSpacing.xs),
      Text(
        label,
        style: TextStyle(
          fontSize: SetflowFontSize.tiny,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}
