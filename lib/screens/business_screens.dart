import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/kinetic.dart';
import '../widgets/motion.dart';
import 'admin_content_screens.dart';
import 'admin_system_screens.dart';
import 'business_detail_screens.dart';
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

class _BusinessShellState extends State<BusinessShell> {
  int index = 0;

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
        TrainerManagementPage(),
        SettlementPage(role: UserRole.gym),
      ],
      UserRole.admin => const [
        AdminHome(),
        AdminUsersPage(),
        AdminReviewPage(),
        SettlementPage(role: UserRole.admin),
      ],
      _ => const [SizedBox(), SizedBox(), SizedBox(), SizedBox()],
    };

    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: SetflowNavBar(
        selectedIndex: index,
        onSelected: (value) => setState(() => index = value),
        items: [
          for (final item in config.nav)
            SetflowNavItem(
              icon: item.$1,
              selectedIcon: _selectedBusinessIcon(item.$1),
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
      color: SetflowColors.blue,
      nav: const [
        (Icons.dashboard_outlined, '홈'),
        (Icons.people_outline, '회원'),
        (Icons.fitness_center, '루틴'),
        (Icons.chat_bubble_outline, '상담'),
      ],
    ),
    UserRole.gym => (
      title: '헬스장',
      color: SetflowColors.purple,
      nav: const [
        (Icons.dashboard_outlined, '홈'),
        (Icons.people_outline, '회원'),
        (Icons.badge_outlined, '트레이너'),
        (Icons.payments_outlined, '정산'),
      ],
    ),
    UserRole.admin => (
      title: '운영 관리자',
      // Neutral/monochrome role identity: adapts so the nav indicator tint
      // stays visible on both a light and a near-black dark surface.
      color: Theme.of(context).colorScheme.onSurface,
      nav: const [
        (Icons.dashboard_outlined, '현황'),
        (Icons.manage_accounts_outlined, '유저'),
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
    final eyebrowColor = theme.brightness == Brightness.dark
        ? accent
        : Color.lerp(accent, theme.colorScheme.onSurface, .35)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SetflowSpacing.xxl,
        SetflowSpacing.lg,
        SetflowSpacing.md,
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
                    fontWeight: FontWeight.w900,
                    color: eyebrowColor,
                  ),
                ),
                const SizedBox(height: SetflowSpacing.xs),
                Text(
                  title,
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          AppIconButton(
            tooltip: '새로고침',
            icon: Icons.refresh_rounded,
            onTap: onRefresh,
          ),
          const SizedBox(width: SetflowSpacing.sm),
          Badge(
            isLabelVisible: unreadCount > 0,
            label: Text('$unreadCount'),
            child: AppIconButton(
              tooltip: '알림',
              icon: Icons.notifications_none_rounded,
              onTap: () => _showNotifications(context, accent),
            ),
          ),
          const SizedBox(width: SetflowSpacing.sm),
          AppIconButton(
            tooltip: '더보기',
            icon: Icons.more_vert_rounded,
            onTap: () => _showMoreMenu(context),
          ),
        ],
      ),
    );
  }

  Future<void> _showMoreMenu(BuildContext context) async {
    final role = AppScope.of(context).role;
    final value = await showAppActionSheet<String>(
      context,
      title: '더보기',
      actions: const [
        SheetAction(
          icon: Icons.grid_view_rounded,
          label: '운영 메뉴',
          value: 'tools',
        ),
        SheetAction(
          icon: Icons.dashboard_customize_outlined,
          label: 'PC 워크스페이스',
          value: 'workspace',
        ),
        SheetAction(
          icon: Icons.settings_outlined,
          label: '설정',
          value: 'settings',
        ),
      ],
    );
    if (value == null || !context.mounted) return;
    if (value == 'tools') {
      _showWorkspaceMenu(context);
    } else if (value == 'workspace') {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => WorkspaceScreen(role: role)));
    } else if (value == 'settings') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BusinessSettingsListScreen(role: role),
        ),
      );
    }
  }

  void _showNotifications(BuildContext context, Color accent) {
    showModalBottomSheet<void>(
      context: context,
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
    final tools = switch (state.role) {
      UserRole.trainer => const [
        (Icons.person_outline, '프로필 편집', BusinessTool.profile),
        (Icons.calendar_month_outlined, '코칭 캘린더', BusinessTool.calendar),
        (Icons.replay_outlined, '환불 및 미정산', BusinessTool.refunds),
        (Icons.workspace_premium_outlined, '플랜 관리', BusinessTool.plan),
        (Icons.notifications_none, '알림 설정', BusinessTool.notifications),
        (Icons.person_off_outlined, '계정 탈퇴', BusinessTool.withdraw),
      ],
      UserRole.gym => const [
        (Icons.apartment_outlined, '헬스장 프로필', BusinessTool.profile),
        (Icons.replay_outlined, '환불 및 미정산', BusinessTool.refunds),
        (Icons.workspace_premium_outlined, '플랜 관리', BusinessTool.plan),
        (Icons.notifications_none, '알림 설정', BusinessTool.notifications),
        (Icons.person_off_outlined, '계정 탈퇴', BusinessTool.withdraw),
      ],
      UserRole.admin => const [
        (Icons.verified_outlined, '배지 발급 관리', BusinessTool.badges),
        (Icons.report_outlined, '커뮤니티 신고 큐', BusinessTool.contentReports),
        (Icons.gavel_outlined, '제재 이력', BusinessTool.sanctions),
        (Icons.child_care_outlined, '미성년자 위험 신호', BusinessTool.minorAlerts),
        (Icons.leaderboard_outlined, '랭킹 알고리즘', BusinessTool.ranking),
        (Icons.document_scanner_outlined, 'OCR 설정', BusinessTool.ocr),
        (Icons.price_change_outlined, '구독 플랜 정책', BusinessTool.plans),
        (Icons.block_outlined, '금지 키워드', BusinessTool.keywords),
        (Icons.monitor_heart_outlined, '시스템 로그', BusinessTool.logs),
      ],
      _ => const <(IconData, String, BusinessTool)>[],
    };
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .78,
        maxChildSize: .9,
        builder: (_, controller) => SafeArea(
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(
              SetflowSpacing.lg,
              0,
              SetflowSpacing.lg,
              SetflowSpacing.xl,
            ),
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
              const Divider(height: SetflowSpacing.xxl),
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
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('운영 관리자'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  state.chooseRole(UserRole.admin);
                },
              ),
              const Divider(),
              ListTile(
                leading: Icon(
                  Icons.logout,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  '로그아웃',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  state.logout();
                },
              ),
            ],
          ),
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
    await AppScope.of(context).refreshBusinessDashboard(widget.role);
    if (!mounted) return;
    setState(() => refreshing = false);
    AppSnackbar.success(context, '운영 현황을 최신 상태로 갱신했어요.');
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
                    color: Theme.of(context).colorScheme.error,
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
                        // Staggered entrance for every business dashboard.
                        children: Reveal.list(widget.children),
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
    final text = Theme.of(context).textTheme;
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
                Expanded(
                  child: Text(
                    '알림',
                    style: text.headlineMedium?.copyWith(
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
                      onDismissed: (_) => state.dismissBusinessNotification(
                        role,
                        notification.id,
                      ),
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(
                          right: SetflowSpacing.xl,
                        ),
                        color: Theme.of(
                          context,
                        ).colorScheme.error.withValues(alpha: .1),
                        child: Icon(
                          Icons.done_rounded,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: TintedIconBadge(
                          icon: _businessKindIcon(notification.kind),
                          color: accent,
                        ),
                        title: Text(
                          notification.title,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(notification.subtitle),
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

class TrainerHome extends StatelessWidget {
  const TrainerHome({super.key});

  @override
  Widget build(BuildContext context) {
    final dashboard = AppScope.of(context).dashboardFor(UserRole.trainer);
    final facts = dashboard.facts;
    final accent = context.setflowColors.blue;
    return _BusinessHomeFrame(
      eyebrow: 'VERIFIED TRAINER',
      title: '안녕하세요, ${facts['displayName'] ?? '트레이너'}님',
      accent: accent,
      role: UserRole.trainer,
      children: [
        // Hero: this month's business summary as a data-viz card — revenue
        // numeral, trend sparkline, monthly bars, and a settlement goal ring.
        TrainingHeroCard(
          kicker: '이번 달 예상 수익',
          value: (facts['revenue'] ?? '0원').replaceAll('원', ''),
          unit: '원',
          animateValue: false,
          delta: '12.4%',
          deltaUp: true,
          deltaCaption: '지난달 대비',
          spark: const [1.6, 1.8, 1.5, 2.0, 2.2, 2.1, 2.35, 2.28, 2.4, 2.48],
          weekValues: const [1.9, 2.3, 2.1, 2.48],
          weekLabels: const ['1주', '2주', '3주', '4주'],
          weekHighlight: 3,
          ringValue: 0.78,
          ringTop: '78%',
          ringBottom: '월 목표',
        ),
        const SizedBox(height: SetflowSpacing.md),
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
        const SectionTitle('루틴 성과'),
        const SizedBox(height: SetflowSpacing.md),
        SetflowCard(
          child: Column(
            children: [
              _PerformanceRow(
                label: '루틴 조회수',
                value: facts['routineViews'] ?? '0',
                change: facts['routineViewsChange'] ?? '-',
              ),
              const Divider(height: SetflowSpacing.xxl),
              _PerformanceRow(
                label: '상담 전환',
                value: facts['consultationConversion'] ?? '0%',
                change: facts['consultationConversionChange'] ?? '-',
              ),
              const Divider(height: SetflowSpacing.xxl),
              _PerformanceRow(
                label: '가져가기',
                value: facts['routineImports'] ?? '0회',
                change: facts['routineImportsChange'] ?? '-',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class GymHome extends StatelessWidget {
  const GymHome({super.key});

  @override
  Widget build(BuildContext context) {
    final dashboard = AppScope.of(context).dashboardFor(UserRole.gym);
    final facts = dashboard.facts;
    final accent = context.setflowColors.purple;
    return _BusinessHomeFrame(
      eyebrow: 'BUSINESS VERIFIED',
      title: facts['displayName'] ?? '센터',
      accent: accent,
      role: UserRole.gym,
      children: [
        // Hero: this month's center revenue as a data-viz card.
        TrainingHeroCard(
          kicker: '이번 달 매출',
          value: facts['revenue'] ?? '0',
          unit: '백만원',
          delta: '9.2%',
          deltaUp: true,
          deltaCaption: '지난달 대비',
          streak: facts['plan'] ?? '기본 플랜',
          streakIcon: Icons.verified_rounded,
          spark: const [12.1, 13.4, 12.8, 14.2, 15.6, 15.1, 16.8, 17.2, 17.9, 18.4],
          weekValues: const [14.2, 16.1, 17.0, 18.4],
          weekLabels: const ['1주', '2주', '3주', '4주'],
          weekHighlight: 3,
          ringValue: 0.82,
          ringTop: '82%',
          ringBottom: '가동률',
        ),
        const SizedBox(height: SetflowSpacing.md),
        Row(
          children: [
            MetricCard(
              label: '전체 회원',
              value: facts['members'] ?? '0',
              suffix: '명',
              icon: Icons.groups_outlined,
              tint: context.setflowColors.teal,
            ),
            const SizedBox(width: SetflowSpacing.md),
            MetricCard(
              label: '소속 트레이너',
              value: facts['trainers'] ?? '0',
              suffix: '명',
              icon: Icons.badge_outlined,
              tint: context.setflowColors.purple,
            ),
          ],
        ),
        const SizedBox(height: SetflowSpacing.lg),
        Row(
          children: [
            MetricCard(
              label: '신규 상담',
              value: facts['consultations'] ?? '0',
              suffix: '건',
              icon: Icons.chat_bubble_outline,
              tint: context.setflowColors.orange,
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
        SetflowCard(
          child: Column(
            children: [
              _PersonRow(
                name: facts['trainer1Name'] ?? '-',
                detail: facts['trainer1Detail'] ?? '데이터 없음',
                color: context.setflowColors.blue,
              ),
              const Divider(height: SetflowSpacing.xxl),
              _PersonRow(
                name: facts['trainer2Name'] ?? '-',
                detail: facts['trainer2Detail'] ?? '데이터 없음',
                color: context.setflowColors.teal,
              ),
              const Divider(height: SetflowSpacing.xxl),
              _PersonRow(
                name: facts['trainer3Name'] ?? '-',
                detail: facts['trainer3Detail'] ?? '데이터 없음',
                color: context.setflowColors.orange,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context) {
    final dashboard = AppScope.of(context).dashboardFor(UserRole.admin);
    final facts = dashboard.facts;
    return _BusinessHomeFrame(
      eyebrow: 'OPERATIONS',
      title: 'Setflow 운영 현황',
      accent: Theme.of(context).colorScheme.onPrimaryContainer,
      role: UserRole.admin,
      children: [
        // Hero: platform ops summary as a data-viz card — total users, growth
        // trend, weekly signups, and an SLA-compliance ring.
        TrainingHeroCard(
          kicker: '전체 사용자',
          value: facts['users'] ?? '0',
          unit: '명',
          animateValue: false,
          delta: '5.6%',
          deltaUp: true,
          deltaCaption: '지난주 대비',
          streak: '심사 대기 ${facts['reviews'] ?? '0'}',
          streakIcon: Icons.fact_check_outlined,
          spark: const [6.8, 7.1, 7.4, 7.6, 7.9, 8.0, 8.15, 8.28, 8.36, 8.42],
          weekValues: const [120, 86, 140, 98, 165, 72, 110],
          weekLabels: const ['월', '화', '수', '목', '금', '토', '일'],
          weekHighlight: 4,
          ringValue: 0.91,
          ringTop: '91%',
          ringBottom: 'SLA 준수',
        ),
        const SizedBox(height: SetflowSpacing.md),
        Row(
          children: [
            MetricCard(
              label: '활성 코칭',
              value: facts['coaching'] ?? '0',
              suffix: '건',
              icon: Icons.handshake_outlined,
              tint: context.setflowColors.teal,
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
        SetflowCard(
          child: Column(
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
        ),
        const SizedBox(height: SetflowSpacing.xxl),
        const SectionTitle('시스템 상태'),
        const SizedBox(height: SetflowSpacing.md),
        SetflowCard(
          child: Column(
            children: [
              _StatusRow(
                label: 'API',
                status: facts['apiStatus'] ?? '확인 필요',
                color: context.setflowColors.success,
              ),
              const Divider(height: SetflowSpacing.xxl),
              _StatusRow(
                label: 'OCR 서비스',
                status: facts['ocrStatus'] ?? '확인 필요',
                color: context.setflowColors.success,
              ),
              const Divider(height: SetflowSpacing.xxl),
              _StatusRow(
                label: '정산 배치',
                status: facts['settlementStatus'] ?? '확인 필요',
                color: context.setflowColors.orange,
              ),
            ],
          ),
        ),
        const SizedBox(height: SetflowSpacing.xxl),
        const SectionTitle('시스템 관리'),
        const SizedBox(height: SetflowSpacing.md),
        SetflowCard(
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AdminSystemScreen())),
          child: Row(
            children: [
              Icon(
                Icons.tune_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: SetflowSpacing.md),
              const Expanded(
                child: Text(
                  '랭킹 · OCR · 요금제 · 금칙어 · 로그 관리',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Icon(Icons.chevron_right, color: context.setflowColors.disabled),
            ],
          ),
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
    'trainer_feedback_due' => const PeoplePage(role: UserRole.trainer),
    'trainer_new_consultation' => const ConsultationQueuePage(
      role: UserRole.trainer,
    ),
    'gym_member_assignment' => const PeoplePage(role: UserRole.gym),
    'gym_feedback_rate' => const TrainerManagementPage(),
    'admin_urgent_reports' => const AdminReviewPage(),
    'admin_business_reviews' => const AdminUsersPage(),
    _ => WorkspaceScreen(role: role),
  };
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
}

/// Athletic tab-root header: big w900 title, optional badge, right-aligned
/// [AppIconButton] actions. Replaces the default AppBar look for screens
/// that live directly in [BusinessShell]'s bottom navigation.
class _TabHeader extends StatelessWidget {
  const _TabHeader({required this.title, this.badge, this.actions = const []});

  final String title;
  final String? badge;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SetflowSpacing.xxl,
        SetflowSpacing.lg,
        SetflowSpacing.xxl,
        SetflowSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: text.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: SetflowSpacing.sm),
                  Badge(label: Text(badge!)),
                ],
              ],
            ),
          ),
          for (final action in actions) ...[
            const SizedBox(width: SetflowSpacing.sm),
            action,
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
  final searchController = TextEditingController();
  final people = const [
    ('박민지', '근육 증가', '오늘', 92),
    ('이준호', '체중 감량', '어제', 78),
    ('최서연', '체력 향상', '3일 전', 64),
    ('정하늘', '건강 유지', '오늘', 88),
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
    final filtered = people.where((item) => item.$1.contains(query)).toList();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TabHeader(title: gym ? '전체 회원' : '관리 회원'),
            Padding(
              padding: SetflowInsets.pageHeader,
              child: AppTextField(
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
                        setState(() => query = '');
                      },
                    )
                  : ListView.builder(
                      padding: SetflowInsets.pageListTight,
                      itemCount: filtered.length,
                      itemBuilder: (_, index) {
                        final person = filtered[index];
                        return Padding(
                          padding: const EdgeInsets.only(
                            bottom: SetflowSpacing.md,
                          ),
                          child: SetflowCard(
                            onTap: () => _showMember(context, person),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: [
                                    Theme.of(context).colorScheme.primary,
                                    context.setflowColors.teal,
                                    context.setflowColors.purple,
                                    context.setflowColors.blue,
                                  ][index % 4].withValues(alpha: .2),
                                  child: Text(
                                    person.$1.characters.first,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
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
                                        person.$1,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                      const SizedBox(height: SetflowSpacing.xs),
                                      Text(
                                        gym
                                            ? '${person.$2} · 담당 ${state.dashboardFor(UserRole.gym).facts['memberAssignment.${person.$1}'] ?? '미배정'}'
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
                                      '${person.$4}%',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: person.$4 >= 80
                                            ? context.setflowColors.success
                                            : context.setflowColors.orange,
                                      ),
                                    ),
                                    Text(
                                      '완료율',
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
      ),
      floatingActionButton: gym
          ? FloatingActionButton(
              tooltip: '회원 초대',
              onPressed: () => _showInviteSheet(context),
              child: const Icon(Icons.person_add_alt_1),
            )
          : null,
    );
  }

  Future<void> _showMember(
    BuildContext context,
    (String, String, String, int) person,
  ) async {
    final feedbackController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
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
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: .2),
                  child: Text(
                    person.$1.characters.first,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: SetflowSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.$1,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        person.$2,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: SetflowSpacing.lg),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        MemberDetailScreen(person: person, role: widget.role),
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
              OutlinedButton.icon(
                onPressed: () => _showAssignmentSheet(sheetContext, person.$1),
                icon: const Icon(Icons.badge_outlined),
                label: const Text('담당 트레이너 배정'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(SetflowRadii.md),
                  ),
                ),
              ),
            ],
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
                const SizedBox(width: SetflowSpacing.md),
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
                  if (feedback.length < 10) return '피드백을 10자 이상 입력해주세요.';
                  return null;
                },
              ),
            ),
            const SizedBox(height: SetflowSpacing.lg),
            PrimaryButton(
              label: '피드백 보내기',
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                AppScope.of(context).recordBusinessMemberFeedback(
                  role: widget.role,
                  memberName: person.$1,
                  feedback: feedbackController.text.trim(),
                );
                Navigator.pop(sheetContext);
                AppSnackbar.success(context, '${person.$1}님에게 피드백을 보냈어요.');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAssignmentSheet(
    BuildContext context,
    String memberName,
  ) async {
    const trainers = ['김코치', '박트레이너', '이코치', '최코치'];
    final state = AppScope.of(context);
    var selected =
        state
            .dashboardFor(UserRole.gym)
            .facts['memberAssignment.$memberName'] ??
        trainers.first;
    await showModalBottomSheet<void>(
      context: context,
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
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  decoration: const InputDecoration(
                    labelText: '담당 트레이너',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  items: [
                    for (final trainer in trainers)
                      DropdownMenuItem(value: trainer, child: Text(trainer)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setSheetState(() => selected = value);
                    }
                  },
                ),
                const SizedBox(height: SetflowSpacing.xl),
                AppButton(
                  label: '배정 저장',
                  icon: Icons.save_outlined,
                  onPressed: () {
                    state.assignBusinessMember(
                      memberName: memberName,
                      trainerName: selected,
                    );
                    Navigator.pop(sheetContext);
                    AppSnackbar.success(
                      this.context,
                      '$memberName 회원을 $selected 트레이너에게 배정했어요.',
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showInviteSheet(BuildContext context) {
    const inviteLink = 'https://setflow.app/invite/gym-7K2M9';
    showModalBottomSheet<void>(
      context: context,
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

class RoutineManagerPage extends StatelessWidget {
  const RoutineManagerPage({required this.role, super.key});
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final routines = [...state.marketRoutines, ...state.routines];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TabHeader(
              title: '루틴 관리',
              actions: [
                AppIconButton(
                  tooltip: '새 루틴 작성',
                  icon: Icons.add,
                  onTap: () => _showRoutineCreate(context, role),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: SetflowInsets.pageList,
                children: [
                  Row(
                    children: [
                      MetricCard(
                        label: '전체 조회',
                        value: '3,482',
                        icon: Icons.visibility_outlined,
                        tint: context.setflowColors.blue,
                      ),
                      const SizedBox(width: SetflowSpacing.sm),
                      MetricCard(
                        label: '상담 전환',
                        value: '8.6',
                        suffix: '%',
                        icon: Icons.trending_up,
                        tint: context.setflowColors.success,
                      ),
                    ],
                  ),
                  const SizedBox(height: SetflowSpacing.xl),
                  for (final routine in routines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: SetflowSpacing.md),
                      child: SetflowCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: routine.color,
                                    borderRadius: BorderRadius.circular(
                                      SetflowRadii.xs,
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
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                      Text(
                                        '승인 · 마켓 노출 중',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color:
                                                  context.setflowColors.success,
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.more_vert),
                              ],
                            ),
                            const Divider(height: SetflowSpacing.xxl),
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _MiniMetric(label: '조회', value: '1,284'),
                                _MiniMetric(label: '상담', value: '42'),
                                _MiniMetric(label: '가져가기', value: '94'),
                                _MiniMetric(label: '랭킹', value: '#12'),
                              ],
                            ),
                            const SizedBox(height: SetflowSpacing.md),
                            InkWell(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      RoutineStatsPage(routine: routine),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.bar_chart_rounded,
                                    size: 16,
                                    color: context.setflowColors.blue,
                                  ),
                                  const SizedBox(width: SetflowSpacing.sm),
                                  Text(
                                    '통계 보기',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          color: context.setflowColors.blue,
                                        ),
                                  ),
                                  const Spacer(),
                                  Icon(
                                    Icons.chevron_right,
                                    size: 16,
                                    color: context.setflowColors.disabled,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
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

Future<void> _showRoutineCreate(BuildContext context, UserRole role) async {
  final nameController = TextEditingController();
  final descriptionController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
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
                '저장 후 루틴 관리 목록에서 구성과 통계를 계속 편집할 수 있어요.',
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
              const SizedBox(height: SetflowSpacing.xl),
              AppButton(
                label: '루틴 저장',
                icon: Icons.save_outlined,
                onPressed: () {
                  if (!(formKey.currentState?.validate() ?? false)) return;
                  final created = AppScope.of(context).createRoutine(
                    nameController.text.trim(),
                    descriptionController.text.trim(),
                  );
                  if (!created) {
                    AppSnackbar.error(context, '현재 플랜의 루틴 저장 한도에 도달했어요.');
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
}

class ConsultationQueuePage extends StatefulWidget {
  const ConsultationQueuePage({required this.role, super.key});
  final UserRole role;

  @override
  State<ConsultationQueuePage> createState() => _ConsultationQueuePageState();
}

class _ConsultationQueuePageState extends State<ConsultationQueuePage> {
  bool unreadOnly = false;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
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
      body: SafeArea(
        child: Column(
          children: [
            _TabHeader(
              title: '상담 수신함',
              badge: unreadCount > 0 ? '$unreadCount' : null,
              actions: [
                AppIconButton(
                  tooltip: '상담 리타겟',
                  icon: Icons.campaign_outlined,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ConsultationRetargetScreen(role: widget.role),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: SetflowInsets.pageHeader,
              child: SegPills(
                items: ['전체', '미답변 $unreadCount'],
                selectedIndex: unreadOnly ? 1 : 0,
                onChanged: (index) => setState(() => unreadOnly = index == 1),
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
                        return Padding(
                          padding: const EdgeInsets.only(
                            bottom: SetflowSpacing.md,
                          ),
                          child: SetflowCard(
                            onTap: () => _answer(context, index, item),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: done
                                      ? context.setflowColors.surfaceContainer
                                      : Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer,
                                  child: Icon(
                                    done
                                        ? Icons.mark_email_read_outlined
                                        : Icons.mark_email_unread_outlined,
                                    color: done
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant
                                        : context.setflowColors.orange,
                                  ),
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
                                            item.$1,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                            ),
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
      ),
    );
  }

  Future<void> _answer(
    BuildContext context,
    int index,
    (String, String, String) item,
  ) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
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
                  '${item.$1}님의 상담',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: SetflowSpacing.sm),
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
                    AppSnackbar.success(context, '${item.$1}님에게 상담 답변을 보냈어요.');
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String doneLabel(bool answered) => answered ? '답변 다시 보내기' : '답변 보내기';

class TrainerManagementPage extends StatefulWidget {
  const TrainerManagementPage({super.key});

  @override
  State<TrainerManagementPage> createState() => _TrainerManagementPageState();
}

class _TrainerManagementPageState extends State<TrainerManagementPage> {
  final searchController = TextEditingController();
  String query = '';
  String filter = 'all';

  static const trainers = [
    ('김코치', '18명', 98, 4.9),
    ('박트레이너', '15명', 94, 4.8),
    ('이코치', '12명', 78, 4.6),
    ('최코치', '9명', 96, 4.9),
  ];

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

    const filterValues = ['all', 'excellent', 'attention'];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TabHeader(
              title: '소속 트레이너',
              actions: [
                AppIconButton(
                  tooltip: '트레이너 초대',
                  icon: Icons.person_add_alt_1,
                  onTap: _showInviteSheet,
                ),
              ],
            ),
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
                  SegPills(
                    items: ['전체 ${trainers.length}', '우수 성과', '피드백 필요'],
                    selectedIndex: filterValues.indexOf(filter),
                    onChanged: (index) =>
                        setState(() => filter = filterValues[index]),
                  ),
                ],
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
                          padding: const EdgeInsets.only(
                            bottom: SetflowSpacing.md,
                          ),
                          child: SetflowCard(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => TrainerPerformancePage(
                                  name: trainer.$1,
                                  membersLabel: trainer.$2,
                                  feedbackRate: '${trainer.$3}%',
                                  rating: trainer.$4,
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        trainer.$1,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                      Text(
                                        '관리 회원 ${trainer.$2} · 피드백 ${trainer.$3}%',
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
                                    Icon(
                                      Icons.star_rounded,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      size: 19,
                                    ),
                                    Text(
                                      '${trainer.$4}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
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
      ),
    );
  }

  void _resetSearch() {
    searchController.clear();
    setState(() => query = '');
  }

  void _showInviteSheet() {
    const inviteLink = 'https://setflow.app/invite/trainer-GYM7K2';
    showModalBottomSheet<void>(
      context: context,
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
                label: '초대 링크 복사',
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

    const filterValues = ['all', 'active', 'blocked', 'premium'];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _TabHeader(title: '회원 관리'),
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
                  SegPills(
                    items: ['전체 ${users.length}', '정상 이용', '이용 제한', '프리미엄'],
                    selectedIndex: filterValues.indexOf(filter),
                    onChanged: (index) =>
                        setState(() => filter = filterValues[index]),
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
                          padding: const EdgeInsets.only(
                            bottom: SetflowSpacing.md,
                          ),
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
                                            spacing: SetflowSpacing.sm,
                                            runSpacing: SetflowSpacing.xs,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Text(
                                                user.$1,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                              StatusChip(
                                                label: user.$3,
                                                color: user.$3 == '프리미엄'
                                                    ? context
                                                          .setflowColors
                                                          .orange
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
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    AppIconButton(
                                      tooltip: '회원 관리 메뉴',
                                      icon: Icons.more_vert_rounded,
                                      onTap: () async {
                                        final value =
                                            await showAppActionSheet<String>(
                                              context,
                                              title: user.$1,
                                              actions: [
                                                const SheetAction(
                                                  icon: Icons.person_outline,
                                                  label: '상세 보기',
                                                  value: 'view',
                                                ),
                                                SheetAction(
                                                  icon: blocked
                                                      ? Icons.lock_open_outlined
                                                      : Icons.block_outlined,
                                                  label: blocked
                                                      ? '제재 해제'
                                                      : '계정 제재',
                                                  value: 'block',
                                                  destructive: !blocked,
                                                ),
                                              ],
                                            );
                                        if (value == null || !context.mounted) {
                                          return;
                                        }
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
                                    ),
                                  ],
                                ),
                                const Divider(height: SetflowSpacing.xxl),
                                Row(
                                  children: [
                                    Text(
                                      '가입일 2026.0${index + 3}.12',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
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
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.error
                                            : context.setflowColors.success,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: SetflowSpacing.xs),
                                    Text(
                                      blocked ? '이용 제한' : '정상 이용',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            color: blocked
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.error
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
      ),
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
    showModalBottomSheet<void>(
      context: context,
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
                    const Divider(height: SetflowSpacing.xxl),
                    _infoRow(
                      label: '계정 상태',
                      value: blocked ? '이용 제한' : '정상 이용',
                    ),
                    const Divider(height: SetflowSpacing.xxl),
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

  Widget _infoRow({required String label, required String value}) {
    return Row(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
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
  static const _contentReviewEntries = [
    (Icons.fitness_center_outlined, SetflowColors.teal, '루틴 심사', '키워드 탐지 검토'),
    (
      Icons.report_gmailerrorred_outlined,
      SetflowColors.red,
      '신고 처리',
      '유저 신고 대기열',
    ),
    (Icons.history_outlined, SetflowColors.purple, '제재 이력', '유저 제재 누적 이력'),
    (Icons.warning_amber_outlined, SetflowColors.orange, '미성년 알림', '위험 행동 감지'),
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
    final latestAudit = state
        .dashboardFor(UserRole.admin)
        .facts['audit.latest'];
    const queue = [
      ('트레이너', '이현우', '생활스포츠지도사 · NSCA-CPT'),
      ('헬스장', '바디랩 역삼', '사업자등록증 · 홈택스 정상'),
      ('트레이너', '정수빈', 'NASM-CPT · 신분증'),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _TabHeader(title: '인증 심사 큐'),
            SizedBox(
              height: 116,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  SetflowSpacing.xxl,
                  SetflowSpacing.md,
                  SetflowSpacing.xxl,
                  SetflowSpacing.xs,
                ),
                scrollDirection: Axis.horizontal,
                itemCount: _contentReviewEntries.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: SetflowSpacing.md),
                itemBuilder: (context, index) {
                  final entry = _contentReviewEntries[index];
                  return SizedBox(
                    width: 132,
                    child: SetflowCard(
                      padding: const EdgeInsets.all(SetflowSpacing.md),
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
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: SetflowSpacing.xxs),
                          Text(
                            entry.$4,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                  );
                },
              ),
            ),
            if (latestAudit != null)
              Padding(
                padding: SetflowInsets.pageHeader,
                child: InfoBanner(
                  message: '최근 처리 · $latestAudit',
                  icon: Icons.history_rounded,
                  color: Theme.of(context).colorScheme.primary,
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
                    padding: const EdgeInsets.only(bottom: SetflowSpacing.md),
                    child: SetflowCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              StatusChip(
                                label: item.$1,
                                color: item.$1 == '트레이너'
                                    ? context.setflowColors.blue
                                    : context.setflowColors.purple,
                              ),
                              const Spacer(),
                              Text(
                                approved
                                    ? '승인 완료'
                                    : status == 'rejected'
                                    ? '반려 완료'
                                    : 'D-2',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w900,
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
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: SetflowSpacing.xs),
                          Text(
                            item.$3,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
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
                                const SizedBox(width: SetflowSpacing.sm),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: () => _approveReview(
                                      reviewId,
                                      item.$2,
                                      item.$3,
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Theme.of(
                                        context,
                                      ).colorScheme.inverseSurface,
                                      foregroundColor: Theme.of(
                                        context,
                                      ).colorScheme.onInverseSurface,
                                    ),
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
      ),
    );
  }

  Future<void> _approveReview(
    String reviewId,
    String applicantName,
    String documents,
  ) async {
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
    AppScope.of(context).completeAdminReview(
      reviewId: reviewId,
      applicantName: applicantName,
      status: 'approved',
    );
    AppSnackbar.success(context, '$applicantName 인증을 승인했어요.');
  }

  Future<void> _rejectReview(String reviewId, String applicantName) async {
    final formKey = GlobalKey<FormState>();
    var reason = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
    AppScope.of(context).completeAdminReview(
      reviewId: reviewId,
      applicantName: applicantName,
      status: 'rejected',
      reason: reason,
    );
    AppSnackbar.success(context, '$applicantName 인증을 반려했어요.');
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
      body: SafeArea(
        child: Column(
          children: [
            _TabHeader(title: admin ? '정산 처리' : '정산 및 매출'),
            Expanded(
              child: ListView(
                padding: SetflowInsets.pageList,
                children: [
                  HeroStatBanner(
                    caption: admin ? '이번 주 정산 예정' : '이번 달 정산 예정',
                    value: admin ? '48,620,000원' : '14,280,000원',
                    note: '에스크로 보호 적용 중',
                    // Admin gets a neutral dark-athletic surface instead of a fixed
                    // ink fill, so it stays legible against both a light and the
                    // new near-black default background. The non-admin branch keeps
                    // its saturated purple fill, which reads fine in either theme.
                    color: admin
                        ? context.setflowColors.surfaceContainerHigh
                        : context.setflowColors.purple,
                    foreground: admin
                        ? Theme.of(context).colorScheme.onSurface
                        : Colors.white,
                  ),
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
                  SegPills(
                    items: const ['전체', '정산 예정', '검토 필요'],
                    selectedIndex: const [
                      'all',
                      'scheduled',
                      'hold',
                    ].indexOf(filter),
                    onChanged: (index) => setState(
                      () => filter = const ['all', 'scheduled', 'hold'][index],
                    ),
                  ),
                  const SizedBox(height: SetflowSpacing.xxl),
                  const SectionTitle('정산 내역'),
                  const SizedBox(height: SetflowSpacing.md),
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
                    for (final item in settlements)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: SetflowSpacing.md,
                        ),
                        child: SetflowCard(
                          child: Row(
                            children: [
                              TintedIconBadge(
                                icon: item.$1 == '환불 보류'
                                    ? Icons.pause_circle_outline
                                    : Icons.payments_outlined,
                                color: item.$1 == '환불 보류'
                                    ? Theme.of(context).colorScheme.error
                                    : context.setflowColors.success,
                              ),
                              const SizedBox(width: SetflowSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.$1,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      item.$2,
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
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    item.$3,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    item.$4,
                                    style: Theme.of(context).textTheme.bodySmall
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
                  const SectionTitle('정산 상세 보기'),
                  const SizedBox(height: SetflowSpacing.md),
                  _SettlementLinkCard(
                    icon: Icons.receipt_long_outlined,
                    color: Theme.of(context).colorScheme.error,
                    title: '환불 내역',
                    subtitle: '환불 요청 및 처리 이력 확인',
                    actionLabel: '환불 내역 보기',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SettlementRefundsPage(role: role),
                      ),
                    ),
                  ),
                  if (role != UserRole.trainer) ...[
                    const SizedBox(height: SetflowSpacing.md),
                    _SettlementLinkCard(
                      icon: Icons.groups_outlined,
                      color: context.setflowColors.blue,
                      title: '트레이너별 정산',
                      subtitle: '소속 코치 매출·분배 내역',
                      actionLabel: '트레이너별 정산 보기',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              TrainerSettlementBreakdownPage(role: role),
                        ),
                      ),
                    ),
                  ],
                  if (admin) ...[
                    const SizedBox(height: SetflowSpacing.md),
                    _SettlementLinkCard(
                      icon: Icons.percent_outlined,
                      color: context.setflowColors.purple,
                      title: '수수료 정산',
                      subtitle: '사업자·트레이너별 수수료 산정 내역',
                      actionLabel: '수수료 정산 보기',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SettlementCommissionPage(role: role),
                        ),
                      ),
                    ),
                    const SizedBox(height: SetflowSpacing.md),
                    _SettlementLinkCard(
                      icon: Icons.task_alt_outlined,
                      color: context.setflowColors.success,
                      title: '최종 정산 확정',
                      subtitle: '지급 대상 확정 및 처리 상태 관리',
                      actionLabel: '최종 정산 확정하기',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              SettlementFinalConfirmPage(role: role),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
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
  @override
  Widget build(BuildContext context) => SetflowCard(
    onTap: onTap,
    child: Row(
      children: [
        TintedIconBadge(icon: icon, color: color),
        const SizedBox(width: SetflowSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Text(
          action,
          style: TextStyle(fontWeight: FontWeight.w900, color: color),
        ),
        const Icon(Icons.chevron_right, size: 18),
      ],
    ),
  );
}

/// Rich action-card treatment for settlement shortcuts: [TintedIconBadge]
/// header row plus a full-width volt-faint action row, matching the
/// athletic mockup's "바로 시작" tinted CTA footer.
class _SettlementLinkCard extends StatelessWidget {
  const _SettlementLinkCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final volt = Theme.of(context).colorScheme.primary;
    return SetflowCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TintedIconBadge(icon: icon, color: color),
              const SizedBox(width: SetflowSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      subtitle,
                      style: text.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: SetflowSpacing.sm),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: volt.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(SetflowRadii.sm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  actionLabel,
                  style: text.labelMedium?.copyWith(
                    color: volt,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: SetflowSpacing.xs),
                Icon(Icons.arrow_forward_rounded, size: 14, color: volt),
              ],
            ),
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
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
      ),
      const SizedBox(width: SetflowSpacing.md),
      Text(
        change,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: context.setflowColors.success,
          fontWeight: FontWeight.w900,
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
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleAvatar(
        backgroundColor: color.withValues(alpha: .15),
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
      const SizedBox(width: SetflowSpacing.md),
      Expanded(
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      Text(
        status,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
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
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: SetflowSpacing.xs),
      Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}
