import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
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
    final config = _roleConfig(widget.role);
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
      bottomNavigationBar: NavigationBar(
        height: 74,
        selectedIndex: index,
        indicatorColor: config.color.withValues(alpha: .14),
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: [
          for (final item in config.nav)
            NavigationDestination(icon: Icon(item.$1), label: item.$2),
        ],
      ),
    );
  }
}

({String title, Color color, List<(IconData, String)> nav}) _roleConfig(
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
      color: SetflowColors.ink,
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
  });
  final String eyebrow;
  final String title;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 10, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '워크스페이스 전환',
            onPressed: () => _showWorkspaceMenu(context),
            icon: const Icon(Icons.grid_view_rounded),
          ),
          IconButton(
            tooltip: '워크스페이스',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    WorkspaceScreen(role: AppScope.of(context).role),
              ),
            ),
            icon: const Icon(Icons.dashboard_customize_outlined),
          ),
          IconButton(
            tooltip: '설정',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BusinessSettingsListScreen(
                  role: AppScope.of(context).role,
                ),
              ),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: '알림',
            onPressed: () => showMessage(context, '새 알림 3개가 있습니다.'),
            icon: const Badge(
              label: Text('3'),
              child: Icon(Icons.notifications_none_rounded),
            ),
          ),
        ],
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
                leading: const Icon(Icons.logout, color: SetflowColors.red),
                title: const Text(
                  '로그아웃',
                  style: TextStyle(color: SetflowColors.red),
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

class TrainerHome extends StatelessWidget {
  const TrainerHome({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const _BusinessHeader(
            eyebrow: 'VERIFIED TRAINER',
            title: '안녕하세요, 김코치님',
            accent: SetflowColors.blue,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: SetflowColors.blue,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.verified_rounded, color: Colors.white),
                          SizedBox(width: 7),
                          Text(
                            '인증 트레이너',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Spacer(),
                          Text(
                            'PRO',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 20),
                      Text(
                        '이번 달 예상 수익',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '2,480,000원',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '지난달보다 12.4% 증가',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: const [
                    MetricCard(
                      label: '관리 회원',
                      value: '12',
                      suffix: '/ 50명',
                      icon: Icons.people_outline,
                      tint: SetflowColors.purple,
                    ),
                    SizedBox(width: 10),
                    MetricCard(
                      label: '피드백 대기',
                      value: '3',
                      suffix: '건',
                      icon: Icons.mark_chat_unread_outlined,
                      tint: SetflowColors.orange,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const SectionTitle('오늘 할 일'),
                const SizedBox(height: 10),
                _ActionTile(
                  icon: Icons.timer_outlined,
                  color: SetflowColors.red,
                  title: '72시간 피드백 마감 임박',
                  subtitle: '박민지 회원 · 4시간 남음',
                  action: '피드백',
                ),
                const SizedBox(height: 10),
                _ActionTile(
                  icon: Icons.chat_bubble_outline,
                  color: SetflowColors.blue,
                  title: '새 상담이 도착했어요',
                  subtitle: '근육 증가 상담 외 1건',
                  action: '확인',
                ),
                const SizedBox(height: 24),
                const SectionTitle('루틴 성과'),
                const SizedBox(height: 10),
                const SetflowCard(
                  child: Column(
                    children: [
                      _PerformanceRow(
                        label: '루틴 조회수',
                        value: '1,284',
                        change: '+18%',
                      ),
                      Divider(height: 26),
                      _PerformanceRow(
                        label: '상담 전환',
                        value: '8.6%',
                        change: '+2.1%',
                      ),
                      Divider(height: 26),
                      _PerformanceRow(
                        label: '가져가기',
                        value: '94회',
                        change: '+12회',
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

class GymHome extends StatelessWidget {
  const GymHome({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const _BusinessHeader(
            eyebrow: 'BUSINESS VERIFIED',
            title: '모션짐 강남점',
            accent: SetflowColors.purple,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5635A5),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Row(
                    children: [
                      CircleAvatar(
                        radius: 27,
                        backgroundColor: Colors.white24,
                        child: Icon(
                          Icons.apartment_rounded,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '사업자 인증 완료',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              '엔터프라이즈 플랜',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.verified_rounded, color: Colors.white),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: const [
                    MetricCard(
                      label: '전체 회원',
                      value: '84',
                      suffix: '명',
                      icon: Icons.groups_outlined,
                      tint: SetflowColors.teal,
                    ),
                    SizedBox(width: 10),
                    MetricCard(
                      label: '이번 달 매출',
                      value: '18.4',
                      suffix: '백만원',
                      icon: Icons.trending_up,
                      tint: SetflowColors.green,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: const [
                    MetricCard(
                      label: '소속 트레이너',
                      value: '6',
                      suffix: '명',
                      icon: Icons.badge_outlined,
                      tint: SetflowColors.purple,
                    ),
                    SizedBox(width: 10),
                    MetricCard(
                      label: '신규 상담',
                      value: '9',
                      suffix: '건',
                      icon: Icons.chat_bubble_outline,
                      tint: SetflowColors.orange,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const SectionTitle('운영 알림'),
                const SizedBox(height: 10),
                _ActionTile(
                  icon: Icons.person_add_alt_1_outlined,
                  color: SetflowColors.purple,
                  title: '신규 회원 배정이 필요해요',
                  subtitle: '상담 완료 회원 3명',
                  action: '배정',
                ),
                const SizedBox(height: 10),
                _ActionTile(
                  icon: Icons.warning_amber_rounded,
                  color: SetflowColors.orange,
                  title: '피드백 이행률 확인',
                  subtitle: '이행률 80% 미만 트레이너 1명',
                  action: '보기',
                ),
                const SizedBox(height: 24),
                const SectionTitle('트레이너 현황'),
                const SizedBox(height: 10),
                const SetflowCard(
                  child: Column(
                    children: [
                      _PersonRow(
                        name: '김코치',
                        detail: '회원 18명 · 피드백 98%',
                        color: SetflowColors.blue,
                      ),
                      Divider(height: 22),
                      _PersonRow(
                        name: '박트레이너',
                        detail: '회원 15명 · 피드백 94%',
                        color: SetflowColors.teal,
                      ),
                      Divider(height: 22),
                      _PersonRow(
                        name: '이코치',
                        detail: '회원 12명 · 피드백 78%',
                        color: SetflowColors.orange,
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

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const _BusinessHeader(
            eyebrow: 'OPERATIONS',
            title: 'Setflow 운영 현황',
            accent: SetflowColors.primary,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
              children: [
                Row(
                  children: const [
                    MetricCard(
                      label: '전체 사용자',
                      value: '8,420',
                      suffix: '명',
                      icon: Icons.groups_outlined,
                      tint: SetflowColors.blue,
                    ),
                    SizedBox(width: 10),
                    MetricCard(
                      label: '활성 코칭',
                      value: '284',
                      suffix: '건',
                      icon: Icons.handshake_outlined,
                      tint: SetflowColors.teal,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: const [
                    MetricCard(
                      label: '심사 대기',
                      value: '14',
                      suffix: '건',
                      icon: Icons.fact_check_outlined,
                      tint: SetflowColors.orange,
                    ),
                    SizedBox(width: 10),
                    MetricCard(
                      label: '신고 큐',
                      value: '6',
                      suffix: '건',
                      icon: Icons.report_outlined,
                      tint: SetflowColors.red,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const SectionTitle('SLA 처리 현황'),
                const SizedBox(height: 10),
                const SetflowCard(
                  child: Column(
                    children: [
                      _ProgressRow(
                        label: 'Red 신고 · 1시간',
                        value: .82,
                        color: SetflowColors.red,
                      ),
                      SizedBox(height: 18),
                      _ProgressRow(
                        label: 'Orange 신고 · 24시간',
                        value: .94,
                        color: SetflowColors.orange,
                      ),
                      SizedBox(height: 18),
                      _ProgressRow(
                        label: '인증 심사 · 3영업일',
                        value: .97,
                        color: SetflowColors.green,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const SectionTitle('시스템 상태'),
                const SizedBox(height: 10),
                const SetflowCard(
                  child: Column(
                    children: [
                      _StatusRow(
                        label: 'API',
                        status: '정상',
                        color: SetflowColors.green,
                      ),
                      Divider(height: 24),
                      _StatusRow(
                        label: 'OCR 서비스',
                        status: '정상',
                        color: SetflowColors.green,
                      ),
                      Divider(height: 24),
                      _StatusRow(
                        label: '정산 배치',
                        status: '대기 2건',
                        color: SetflowColors.orange,
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

class PeoplePage extends StatefulWidget {
  const PeoplePage({required this.role, super.key});
  final UserRole role;

  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  String query = '';
  final people = const [
    ('박민지', '근육 증가', '오늘', 92),
    ('이준호', '체중 감량', '어제', 78),
    ('최서연', '체력 향상', '3일 전', 64),
    ('정하늘', '건강 유지', '오늘', 88),
  ];

  @override
  Widget build(BuildContext context) {
    final gym = widget.role == UserRole.gym;
    final filtered = people.where((item) => item.$1.contains(query)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(gym ? '전체 회원' : '관리 회원')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
            child: TextField(
              onChanged: (value) => setState(() => query = value),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '회원 이름 검색',
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              itemCount: filtered.length,
              itemBuilder: (_, index) {
                final person = filtered[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: SetflowCard(
                    onTap: () => _showMember(context, person),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: [
                            SetflowColors.primary,
                            SetflowColors.teal,
                            SetflowColors.purple,
                            SetflowColors.blue,
                          ][index].withValues(alpha: .2),
                          child: Text(
                            person.$1.characters.first,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                person.$1,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${person.$2} · 마지막 기록 ${person.$3}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: SetflowColors.secondaryText,
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
                                    ? SetflowColors.green
                                    : SetflowColors.orange,
                              ),
                            ),
                            const Text(
                              '완료율',
                              style: TextStyle(
                                fontSize: 9,
                                color: SetflowColors.secondaryText,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right,
                          color: SetflowColors.disabled,
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
          ? FloatingActionButton(
              onPressed: () => showMessage(context, '회원 초대 링크를 만들었습니다.'),
              backgroundColor: SetflowColors.purple,
              foregroundColor: Colors.white,
              child: const Icon(Icons.person_add_alt_1),
            )
          : null,
    );
  }

  void _showMember(BuildContext context, (String, String, String, int) person) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: SetflowColors.primary.withValues(alpha: .2),
                  child: Text(
                    person.$1.characters.first,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.$1,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        person.$2,
                        style: const TextStyle(
                          color: SetflowColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
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
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                MetricCard(
                  label: '주간 완료율',
                  value: '${person.$4}',
                  suffix: '%',
                  icon: Icons.check_circle_outline,
                  tint: SetflowColors.teal,
                ),
                const SizedBox(width: 10),
                const MetricCard(
                  label: '최근 볼륨',
                  value: '4.8',
                  suffix: 't',
                  icon: Icons.monitor_weight_outlined,
                  tint: SetflowColors.orange,
                ),
              ],
            ),
            const SizedBox(height: 22),
            const SectionTitle('최근 운동 기록'),
            const SizedBox(height: 8),
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
            const SizedBox(height: 18),
            TextField(
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '피드백',
                hintText: '회원에게 전달할 피드백을 작성하세요.',
              ),
            ),
            const SizedBox(height: 14),
            PrimaryButton(
              label: '피드백 보내기',
              onPressed: () {
                Navigator.pop(sheetContext);
                showMessage(context, '피드백을 보냈습니다.');
              },
            ),
          ],
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
    final routines = AppScope.of(context).marketRoutines;
    return Scaffold(
      appBar: AppBar(
        title: const Text('루틴 관리'),
        actions: [
          IconButton(
            onPressed: () => showMessage(context, '새 전문가 루틴 작성 화면입니다.'),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
        children: [
          const Row(
            children: [
              MetricCard(
                label: '전체 조회',
                value: '3,482',
                icon: Icons.visibility_outlined,
                tint: SetflowColors.blue,
              ),
              SizedBox(width: 8),
              MetricCard(
                label: '상담 전환',
                value: '8.6',
                suffix: '%',
                icon: Icons.trending_up,
                tint: SetflowColors.green,
              ),
            ],
          ),
          const SizedBox(height: 20),
          for (final routine in routines)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
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
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                routine.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              const Text(
                                '승인 · 마켓 노출 중',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: SetflowColors.green,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.more_vert),
                      ],
                    ),
                    const Divider(height: 24),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _MiniMetric(label: '조회', value: '1,284'),
                        _MiniMetric(label: '상담', value: '42'),
                        _MiniMetric(label: '가져가기', value: '94'),
                        _MiniMetric(label: '랭킹', value: '#12'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => RoutineStatsPage(routine: routine),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.bar_chart_rounded,
                            size: 16,
                            color: SetflowColors.blue,
                          ),
                          SizedBox(width: 6),
                          Text(
                            '통계 보기',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: SetflowColors.blue,
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
                ),
              ),
            ),
        ],
      ),
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
  final answered = <int>{};

  @override
  Widget build(BuildContext context) {
    const items = [
      ('이수진', '근육 증가', '운동 경력 3개월 · 주 3회 가능'),
      ('김도윤', '체중 감량', '무릎 통증 있음 · 홈트 선호'),
      ('정민아', '체력 향상', '러닝과 근력 병행 희망'),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('상담 수신함'),
        actions: [
          IconButton(
            tooltip: '상담 리타겟',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ConsultationRetargetScreen(role: widget.role),
              ),
            ),
            icon: const Icon(Icons.campaign_outlined),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
        itemCount: items.length,
        itemBuilder: (_, index) {
          final item = items[index];
          final done = answered.contains(index);
          return Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: SetflowCard(
              onTap: () => _answer(context, index, item),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: done
                        ? SetflowColors.soft
                        : SetflowColors.primary.withValues(alpha: .25),
                    child: Icon(
                      done
                          ? Icons.mark_email_read_outlined
                          : Icons.mark_email_unread_outlined,
                      color: done
                          ? SetflowColors.disabled
                          : SetflowColors.orange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              item.$1,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(width: 7),
                            if (!done)
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: SetflowColors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.$2,
                          style: const TextStyle(
                            fontSize: 12,
                            color: SetflowColors.secondaryText,
                          ),
                        ),
                        Text(
                          item.$3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: SetflowColors.disabled,
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
    );
  }

  void _answer(BuildContext context, int index, (String, String, String) item) {
    final controller = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item.$1}님의 상담',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              '${item.$2} · ${item.$3}',
              style: const TextStyle(color: SetflowColors.secondaryText),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: controller,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '답변 작성'),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: '답변 보내기',
              onPressed: () {
                setState(() => answered.add(index));
                Navigator.pop(sheetContext);
                showMessage(context, '상담 답변을 보냈습니다.');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class TrainerManagementPage extends StatelessWidget {
  const TrainerManagementPage({super.key});
  @override
  Widget build(BuildContext context) {
    const trainers = [
      ('김코치', '18명', '98%', 4.9),
      ('박트레이너', '15명', '94%', 4.8),
      ('이코치', '12명', '78%', 4.6),
      ('최코치', '9명', '96%', 4.9),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('소속 트레이너'),
        actions: [
          IconButton(
            onPressed: () => showMessage(context, '트레이너 초대 링크를 만들었습니다.'),
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
        itemCount: trainers.length,
        itemBuilder: (_, index) {
          final trainer = trainers[index];
          final accentColor = [
            SetflowColors.blue,
            SetflowColors.teal,
            SetflowColors.orange,
            SetflowColors.purple,
          ][index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: SetflowCard(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TrainerPerformancePage(
                    name: trainer.$1,
                    membersLabel: trainer.$2,
                    feedbackRate: trainer.$3,
                    rating: trainer.$4,
                    accentColor: accentColor,
                  ),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: accentColor.withValues(alpha: .16),
                    child: Text(
                      trainer.$1.characters.first,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trainer.$1,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '관리 회원 ${trainer.$2} · 피드백 ${trainer.$3}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: SetflowColors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: SetflowColors.primary,
                        size: 19,
                      ),
                      Text(
                        '${trainer.$4}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          );
        },
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
  final blocked = <int>{2};

  @override
  Widget build(BuildContext context) {
    const users = [
      ('운동초보', 'beginner@setflow.app', '무료'),
      ('으라차차', 'muscle@setflow.app', '프리미엄'),
      ('다이어터', 'diet@setflow.app', '무료'),
      ('요가러버', 'yoga@setflow.app', '프리미엄'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('회원 관리')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
        children: [
          const TextField(
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '닉네임 또는 이메일 검색',
            ),
          ),
          const SizedBox(height: 16),
          for (var index = 0; index < users.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: SetflowCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          child: Text(users[index].$1.characters.first),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    users[index].$1,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: users[index].$3 == '프리미엄'
                                          ? SetflowColors.primary.withValues(
                                              alpha: .2,
                                            )
                                          : SetflowColors.soft,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      users[index].$3,
                                      style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                users[index].$2,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: SetflowColors.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'block') {
                              setState(
                                () => blocked.contains(index)
                                    ? blocked.remove(index)
                                    : blocked.add(index),
                              );
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'view',
                              child: const Text('상세 보기'),
                            ),
                            PopupMenuItem(
                              value: 'block',
                              child: Text(
                                blocked.contains(index) ? '제재 해제' : '계정 제재',
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
                          style: const TextStyle(
                            fontSize: 11,
                            color: SetflowColors.secondaryText,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: blocked.contains(index)
                                ? SetflowColors.red
                                : SetflowColors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          blocked.contains(index) ? '이용 제한' : '정상 이용',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: blocked.contains(index)
                                ? SetflowColors.red
                                : SetflowColors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AdminReviewPage extends StatefulWidget {
  const AdminReviewPage({super.key});
  @override
  State<AdminReviewPage> createState() => _AdminReviewPageState();
}

class _AdminReviewPageState extends State<AdminReviewPage> {
  final approved = <int>{};
  @override
  Widget build(BuildContext context) {
    const queue = [
      ('트레이너', '이현우', '생활스포츠지도사 · NSCA-CPT'),
      ('헬스장', '바디랩 역삼', '사업자등록증 · 홈택스 정상'),
      ('트레이너', '정수빈', 'NASM-CPT · 신분증'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('인증 심사 큐')),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
        itemCount: queue.length,
        itemBuilder: (_, index) {
          final item = queue[index];
          final done = approved.contains(index);
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
                                      ? SetflowColors.blue
                                      : SetflowColors.purple)
                                  .withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          item.$1,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: item.$1 == '트레이너'
                                ? SetflowColors.blue
                                : SetflowColors.purple,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        done ? '승인 완료' : 'D-2',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: done
                              ? SetflowColors.green
                              : SetflowColors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.$2,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.$3,
                    style: const TextStyle(
                      fontSize: 12,
                      color: SetflowColors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!done)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                showMessage(context, '거절 사유 입력 화면을 열었습니다.'),
                            child: const Text('거절'),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: FilledButton(
                            onPressed: () =>
                                setState(() => approved.add(index)),
                            style: FilledButton.styleFrom(
                              backgroundColor: SetflowColors.ink,
                            ),
                            child: const Text('승인'),
                          ),
                        ),
                      ],
                    )
                  else
                    const Row(
                      children: [
                        Icon(Icons.check_circle, color: SetflowColors.green),
                        SizedBox(width: 7),
                        Text(
                          '인증 배지를 발급했습니다.',
                          style: TextStyle(
                            color: SetflowColors.green,
                            fontWeight: FontWeight.w800,
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
    );
  }
}

class SettlementPage extends StatelessWidget {
  const SettlementPage({required this.role, super.key});
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final admin = role == UserRole.admin;
    return Scaffold(
      appBar: AppBar(title: Text(admin ? '정산 처리' : '정산 및 매출')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: admin ? SetflowColors.ink : const Color(0xFF5635A5),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  admin ? '이번 주 정산 예정' : '이번 달 정산 예정',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 5),
                Text(
                  admin ? '48,620,000원' : '14,280,000원',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '에스크로 보호 적용 중',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SectionTitle('정산 내역'),
          const SizedBox(height: 10),
          for (final item in const [
            ('단기 코칭', '김코치 · 박민지', '350,000원', 'D+7'),
            ('장기 코칭', '박트레이너 · 이준호', '680,000원', '월 분할'),
            ('환불 보류', '이코치 · 최서연', '120,000원', '검토 중'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SetflowCard(
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          (item.$1 == '환불 보류'
                                  ? SetflowColors.red
                                  : SetflowColors.green)
                              .withValues(alpha: .12),
                      child: Icon(
                        item.$1 == '환불 보류'
                            ? Icons.pause_circle_outline
                            : Icons.payments_outlined,
                        color: item.$1 == '환불 보류'
                            ? SetflowColors.red
                            : SetflowColors.green,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.$1,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            item.$2,
                            style: const TextStyle(
                              fontSize: 11,
                              color: SetflowColors.secondaryText,
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
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          item.$4,
                          style: const TextStyle(
                            fontSize: 10,
                            color: SetflowColors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 22),
          const SectionTitle('정산 상세 보기'),
          const SizedBox(height: 10),
          SetflowCard(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettlementRefundsPage(role: role),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: SetflowColors.red.withValues(alpha: .12),
                  child: const Icon(
                    Icons.receipt_long_outlined,
                    color: SetflowColors.red,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '환불 내역',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '환불 요청 및 처리 이력 확인',
                        style: TextStyle(
                          fontSize: 11,
                          color: SetflowColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
          if (role != UserRole.trainer) ...[
            const SizedBox(height: 10),
            SetflowCard(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TrainerSettlementBreakdownPage(role: role),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: SetflowColors.blue.withValues(
                      alpha: .12,
                    ),
                    child: const Icon(
                      Icons.groups_outlined,
                      color: SetflowColors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '트레이너별 정산',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          '소속 코치 매출·분배 내역',
                          style: TextStyle(
                            fontSize: 11,
                            color: SetflowColors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ),
          ],
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
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String action;
  @override
  Widget build(BuildContext context) => SetflowCard(
    onTap: () => showMessage(context, '$title 작업을 열었습니다.'),
    child: Row(
      children: [
        CircleAvatar(
          backgroundColor: color.withValues(alpha: .13),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: SetflowColors.secondaryText,
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
          style: const TextStyle(
            color: SetflowColors.secondaryText,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      Text(
        value,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
      ),
      const SizedBox(width: 10),
      Text(
        change,
        style: const TextStyle(
          color: SetflowColors.green,
          fontSize: 11,
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
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w900)),
            Text(
              detail,
              style: const TextStyle(
                fontSize: 11,
                color: SetflowColors.secondaryText,
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
      const SizedBox(height: 7),
      LinearProgressIndicator(
        value: value,
        minHeight: 8,
        borderRadius: BorderRadius.circular(8),
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
      const SizedBox(width: 10),
      Expanded(
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      Text(
        status,
        style: TextStyle(
          fontSize: 12,
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
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 3),
      Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          color: SetflowColors.secondaryText,
        ),
      ),
    ],
  );
}
