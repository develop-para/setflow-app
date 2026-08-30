import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../services/push_service.dart';
import '../korean_holidays.dart';
import '../data/business_repository.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/common.dart';
import '../widgets/auth_gate.dart';
import '../widgets/bottom_bar.dart';
import '../widgets/portal.dart';
import 'detail_screens.dart';
import 'evidence_library_screen.dart';
import 'member_mypage_screen.dart';
import 'member_membership_screen.dart';
import 'member_social_detail_screens.dart';
import 'routine_editor_screen.dart';
import 'together_screens.dart';
import 'workout_screens.dart';
import 'welcome_screen.dart';

String _formatMinuteValue(double minutes) {
  final wholeMinutes = minutes.round();
  if ((minutes - wholeMinutes).abs() < .05) return '$wholeMinutes';
  return minutes.toStringAsFixed(1);
}

class MemberShell extends StatefulWidget {
  const MemberShell({super.key});

  @override
  State<MemberShell> createState() => _MemberShellState();
}

class _WorkoutLocationHeaderButton extends StatelessWidget {
  const _WorkoutLocationHeaderButton();

  Future<void> _open(BuildContext context) async {
    if (!await requireSignIn(context, reason: AuthReason.membership)) return;
    if (!context.mounted) return;
    final state = AppScope.of(context);
    final result = await showSetflowSheet<String>(
      context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(
          SetflowSpacing.gutter,
          0,
          SetflowSpacing.gutter,
          SetflowSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '현재 운동 장소',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: SetflowSpacing.xs),
            Text(
              '선택한 장소는 홈과 오프라인 상담의 기본 헬스장으로 사용됩니다.',
              style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SetflowSpacing.md),
            if (state.workoutLocations.isEmpty)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(SetflowIcons.location),
                title: Text('등록한 운동 장소가 없어요'),
              )
            else
              for (final location in state.workoutLocations)
                ListTile(
                  key: ValueKey('header-workout-location-${location.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    location.isActive
                        ? SetflowIcons.locationActive
                        : SetflowIcons.location,
                  ),
                  title: Text(location.gymName),
                  subtitle: location.gymAddress == null
                      ? null
                      : Text(
                          location.gymAddress!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing: location.isActive
                      ? const Icon(SetflowIcons.success)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, location.id),
                ),
            const SizedBox(height: SetflowSpacing.sm),
            AppButton(
              key: const ValueKey('manage-workout-locations'),
              label: '운동 장소 관리',
              icon: SetflowIcons.settings,
              variant: AppButtonVariant.outlined,
              onPressed: () => Navigator.pop(sheetContext, 'manage'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || result == null) return;
    if (result == 'manage') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const MemberMembershipScreen()),
      );
      return;
    }
    try {
      await state.selectWorkoutLocation(result);
    } catch (_) {
      if (context.mounted) {
        AppSnackbar.error(context, '운동 장소를 변경하지 못했어요.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = AppScope.of(context).currentWorkoutLocation;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 108),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('home-workout-location'),
          borderRadius: BorderRadius.circular(SetflowRadii.full),
          onTap: () => _open(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SetflowSpacing.xs,
              vertical: SetflowSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(SetflowIcons.location, size: 18),
                const SizedBox(width: SetflowSpacing.xxs),
                Flexible(
                  child: Text(
                    location?.gymName ?? '운동 장소',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                const Icon(SetflowIcons.expand, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 탭한 푸시가 여는 회원 셸의 페이지. 상세 화면(상담·게시글)은 main.dart가
/// 이 위에 push하므로, 여기서는 "어느 탭이 그 알림의 집인가"만 답한다.
/// 모르는 알림은 null — 탭을 옮기지 않는다.
int? memberPageForPush(PushOpen open) {
  return switch (open.kind) {
    'together' => 1,
    'workout_reminder' => 2,
    'community_reaction' => 3,
    'account' => 4,
    'coaching_feedback' => switch (open.event) {
      'routine_share' => 2,
      'member_assigned' => 4,
      _ => 0,
    },
    _ => null,
  };
}

class _MemberShellState extends State<MemberShell> {
  /// Index into the page list, where 2 is the center destination.
  int index = 0;
  bool _recordSheetOpen = false;

  /// 함께 방에 들어가 있는가. 방은 운동 중 전용 화면이라 셸의 헤더와 바텀바를
  /// 접는다 — 전광판과 하단 액션이 화면을 다 쓰게 하려는 것이다.
  bool _togetherSession = false;

  /// 함께 탭을 보고 있으면서 방 안일 때만 접는다. 다른 탭으로 옮기면 방은
  /// 그대로 두고 바를 되돌려야 한다 — 안 그러면 나갈 길이 사라진다.
  bool get _inTogetherSession => _togetherSession && index == 1;

  void _show(int page) => setState(() => index = page);

  String? _handledRoutineShareToken;
  int _handledPushSerial = 0;

  /// Page index the center disc owns.
  static const _recordPage = 2;
  static const _togetherPage = 1;

  /// 홈. The only page that carries the 일반인/트레이너 switch.
  static const _homePage = 0;

  /// Bar slots left of the center action, then right of it.
  static const destinations = [
    SetflowNavItem(
      icon: SetflowIcons.home,
      selectedIcon: SetflowIcons.homeActive,
      label: '홈',
    ),
    SetflowNavItem(
      icon: SetflowIcons.together,
      selectedIcon: SetflowIcons.togetherActive,
      label: '함께',
    ),
    SetflowNavItem(
      icon: SetflowIcons.community,
      selectedIcon: SetflowIcons.communityActive,
      label: '커뮤니티',
    ),
    SetflowNavItem(
      icon: SetflowIcons.my,
      selectedIcon: SetflowIcons.myActive,
      label: '마이',
    ),
  ];

  /// Bar slot -> page. Slots 0/1 sit before the center page, 2/3 after it.
  static const _slotToPage = [0, 1, 3, 4];

  int? get _selectedSlot {
    final slot = _slotToPage.indexOf(index);
    return slot == -1 ? null : slot;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    final open = state.pendingPushOpen;
    if (open != null && open.serial != _handledPushSerial) {
      _handledPushSerial = open.serial;
      final page = memberPageForPush(open);
      if (page != null && page != index) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _show(page);
        });
      }
    }
    // 초대 링크는 함께 탭으로 — 참여 자체는 그 화면이 코드를 집어 처리한다.
    if (state.pendingTogetherJoinCode != null && index != _togetherPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && index != _togetherPage) _show(_togetherPage);
      });
    }
    final token = state.pendingRoutineShareToken;
    if (token == null) {
      _handledRoutineShareToken = null;
      return;
    }
    if (token == _handledRoutineShareToken) return;
    _handledRoutineShareToken = token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 루틴 no longer owns a tab, so surface the record page instead.
      if (mounted && index != _recordPage) _show(_recordPage);
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final pages = [
      const CalendarScreen(),
      // 통계(DashboardScreen)가 있던 자리. 화면은 지우지 않고 메뉴에서만 내렸다 —
      // 지표는 나중에 다시 올릴 것이고, 그때 되살릴 코드가 남아 있어야 한다.
      TogetherScreen(
        onOpenRecord: () => _show(_recordPage),
        // 방 안에서는 셸의 헤더와 바텀바가 사라진다. 운동 중 전용 화면이라
        // 전광판과 하단 액션이 화면을 다 쓰고, 방을 나가면 되돌아온다.
        onSessionChanged: (active) {
          if (_togetherSession == active) return;
          setState(() => _togetherSession = active);
        },
      ),
      DailyWorkoutScreen(date: today),
      const CommunityScreen(),
      const MyPageScreen(),
    ];

    return PopScope(
      // Back closes the sheet before it ever reaches "leave the app".
      canPop: !_recordSheetOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeRecordSheet();
      },
      child: Scaffold(
        body: Stack(
          children: [
            Column(
              children: [
                if (!_inTogetherSession)
                  PortalHeaderBar(
                    switcher: index == _homePage,
                    leading: index == _homePage
                        ? const _WorkoutLocationHeaderButton()
                        : null,
                  ),
                // The header already ate the status-bar inset, so the per-page
                // SafeArea below must not add it a second time. 아래도 같다:
                // 바텀바가 떠 있으면 하단 인셋은 바가 먹는다 — 안 빼면 홈의
                // SafeArea가 제스처 바 높이(34px)만큼 바 위에 빈 띠를 남긴다
                // ("바텀 내비게이션에 왜 저 여백이"). 바가 접힌 방 안에서는 남긴다.
                // 한 번에 계산한다. `removePadding`과 `removeViewInsets`를 겹치면
                // 둘 다 같은 바깥 context의 MediaQuery를 읽어서 안쪽 것이 바깥 것을
                // 되돌린다 — 그래서 하단 인셋 제거가 먹지 않았다.
                Expanded(
                  child: MediaQuery(
                    data: MediaQuery.of(context)
                        .removePadding(
                          removeTop: true,
                          removeBottom: !_inTogetherSession,
                        )
                        .removeViewInsets(removeBottom: true),
                    child: IndexedStack(index: index, children: pages),
                  ),
                ),
              ],
            ),
            // The sheet lives inside the shell body rather than in a modal
            // route, so the bar below it — and its close button — stay live.
            // A showModalBottomSheet barrier would swallow every disc tap.
            if (_recordSheetOpen) ...[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeRecordSheet,
                  child: const ColoredBox(color: SetflowColors.scrim),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: _RecordActionSheet(
                  onSelected: (action) {
                    _closeRecordSheet();
                    _runRecordAction(action, today);
                  },
                ),
              ),
            ],
          ],
        ),
        bottomNavigationBar: _inTogetherSession
            ? null
            : SetflowActionNavBar(
                items: destinations,
                selectedIndex: _selectedSlot,
                onSelected: (slot) {
                  _closeRecordSheet();
                  _show(_slotToPage[slot]);
                },
                centerLabel: '기록',
                centerIcon: _recordSheetOpen
                    ? SetflowIcons.close
                    : SetflowIcons.record,
                centerSelected: index == _recordPage,
                onCenterTap: _handleCenterTap,
              ),
      ),
    );
  }

  /// The OKX Trade contract: the first tap opens the core surface, a second tap
  /// while already there opens its action sheet, and a third closes it.
  void _handleCenterTap() {
    if (_recordSheetOpen) {
      _closeRecordSheet();
      return;
    }
    setState(() {
      if (index != _recordPage) {
        index = _recordPage;
      } else {
        _recordSheetOpen = true;
      }
    });
  }

  void _closeRecordSheet() {
    if (!_recordSheetOpen) return;
    setState(() => _recordSheetOpen = false);
  }

  void _runRecordAction(_RecordAction action, DateTime today) {
    switch (action) {
      case _RecordAction.routines:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const RoutinesScreen()));
      case _RecordAction.market:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const MarketScreen()));
      case _RecordAction.library:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ExerciseLibraryScreen(date: today)),
        );
      case _RecordAction.pastDays:
        _show(_homePage);
    }
  }
}

enum _RecordAction { routines, market, library, pastDays }

/// The center disc's action sheet — the ways to fill today's log, the way OKX
/// puts its trade modes behind the Trade button.
class _RecordActionSheet extends StatelessWidget {
  const _RecordActionSheet({required this.onSelected});

  final ValueChanged<_RecordAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: SetflowMotion.standard,
      curve: SetflowMotion.standardCurve,
      builder: (context, value, child) =>
          FractionalTranslation(translation: Offset(0, value), child: child),
      child: Material(
        color: theme.scaffoldBackgroundColor,
        // Flat on purpose: a monochrome sheet separates with a hairline, and a
        // drop shadow here would smear onto the bar's transparent riser.
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: SetflowSpacing.md),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(SetflowRadii.xs),
              ),
            ),
            const SizedBox(height: SetflowSpacing.lg),
            const Padding(
              padding: EdgeInsets.fromLTRB(
                SetflowSpacing.xxl,
                0,
                SetflowSpacing.xxl,
                SetflowSpacing.sm,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '무엇으로 기록할까요?',
                  style: TextStyle(
                    fontSize: SetflowFontSize.titleLarge,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            _RecordActionTile(
              actionKey: 'record-action-routines',
              icon: SetflowIcons.routine,
              title: '내 루틴',
              subtitle: '저장한 루틴을 불러와 오늘에 적용',
              onTap: () => onSelected(_RecordAction.routines),
            ),
            _RecordActionTile(
              actionKey: 'record-action-market',
              icon: SetflowIcons.market,
              title: '전문가 루틴',
              subtitle: '트레이너가 만든 루틴 둘러보기',
              onTap: () => onSelected(_RecordAction.market),
            ),
            _RecordActionTile(
              actionKey: 'record-action-library',
              icon: SetflowIcons.exerciseSearch,
              title: '운동 찾기',
              subtitle: '운동을 직접 골라 오늘에 추가',
              onTap: () => onSelected(_RecordAction.library),
            ),
            _RecordActionTile(
              actionKey: 'record-action-past',
              icon: SetflowIcons.pastDays,
              title: '지난 날짜 기록',
              subtitle: '캘린더에서 다른 날짜 열기',
              onTap: () => onSelected(_RecordAction.pastDays),
            ),
            const SizedBox(height: SetflowSpacing.lg),
          ],
        ),
      ),
    );
  }
}

class _RecordActionTile extends StatelessWidget {
  const _RecordActionTile({
    required this.actionKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String actionKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey(actionKey),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: SetflowSpacing.xxl,
      ),
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? dragSource;
  RoutineData? draggedRoutine;

  /// 이번 주가 기본이다. 접혀 있어야 그 아래 이번 달 요약·나의 루틴이 첫
  /// 화면에 들어온다. 펼치면 [anchor]가 든 달 전체가 나온다.
  bool expanded = false;

  /// 접었을 때 남는 주를 정하는 날짜. 달을 바꿀 때마다 같이 옮겨서
  /// **항상 현재 격자 안에 있다** — 그래야 접는 순간 보여줄 주가 확실하다.
  DateTime anchor = DateUtils.dateOnly(DateTime.now());

  /// 펼쳤을 땐 한 달, 접었을 땐 한 주씩 넘어간다. 보이는 만큼 움직여야
  /// 화살표와 스와이프가 같은 뜻으로 읽힌다.
  void _step(int offset) {
    setState(() {
      if (expanded) {
        _goToMonth(DateTime(month.year, month.month + offset));
      } else {
        anchor = DateTime(anchor.year, anchor.month, anchor.day + 7 * offset);
        month = DateTime(anchor.year, anchor.month);
      }
    });
  }

  void _goToMonth(DateTime target) {
    month = DateTime(target.year, target.month);
    final today = DateUtils.dateOnly(DateTime.now());
    anchor = today.year == month.year && today.month == month.month
        ? today
        : DateTime(month.year, month.month, 1);
  }

  void _toggleExpanded() {
    setState(() => expanded = !expanded);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final days = _calendarDays(month);
    final weeks = List.generate(
      6,
      (index) => days.sublist(index * 7, index * 7 + 7),
    );
    // 접었을 때 남는 한 주. anchor는 항상 이 격자 안에 있지만,
    // 못 찾으면 첫 주로 떨어뜨려서 화면이 통째로 비는 일은 없게 한다.
    final foldedWeek = weeks.firstWhere(
      (week) => week.any((day) => DateUtils.isSameDay(day, anchor)),
      orElse: () => weeks.first,
    );
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            // 홈도 페이지 여백은 gutter다 — 헤더만 16/8이면 아래 카드들과
            // 양끝이 어긋나 보인다.
            padding: const EdgeInsets.fromLTRB(
              SetflowSpacing.gutter,
              10,
              SetflowSpacing.gutter,
              10,
            ),
            child: LayoutBuilder(
              builder: (context, headerConstraints) {
                final compactHeader = headerConstraints.maxWidth < 360;
                return Row(
                  children: [
                    // 제목이 남는 폭을 다 먹고 필요하면 스스로 줄어든다 —
                    // 고정 폭 + Spacer 조합은 버튼이 하나만 늘어도 넘친다.
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: compactHeader ? 104 : null,
                          child: PopupMenuButton<int>(
                            tooltip: '월 선택',
                            onSelected: (value) => setState(
                              () => _goToMonth(DateTime(month.year, value)),
                            ),
                            itemBuilder: (_) => List.generate(
                              12,
                              (i) => PopupMenuItem(
                                value: i + 1,
                                child: Text('${i + 1}월'),
                              ),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                  vertical: 8,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // 제목은 titleLarge — 화면에서 가장 큰
                                    // 숫자는 이 달의 볼륨이지 연월이 아니다.
                                    Text(
                                      DateFormat('yyyy.MM').format(month),
                                      style: theme.textTheme.titleLarge,
                                    ),
                                    const SizedBox(width: SetflowSpacing.xxs),
                                    Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 20,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 이동 버튼은 맨 아이콘 둘이다. 알약 테두리 안에 구분선까지
                    // 넣었더니 제목보다 무거운 덩어리가 됐다("버튼이 너무 커").
                    _MonthArrowButton(
                      tooltip: expanded ? '이전 달' : '이전 주',
                      icon: Icons.chevron_left_rounded,
                      onPressed: () => _step(-1),
                    ),
                    _MonthArrowButton(
                      tooltip: expanded ? '다음 달' : '다음 주',
                      icon: Icons.chevron_right_rounded,
                      onPressed: () => _step(1),
                    ),
                    // 통계와 설정은 여기 없다. 통계는 바텀바의 "통계" 탭이고
                    // 설정은 "마이"에 있다 — 여기서 push하면 셸 위에 바텀바 없는
                    // 사본이 하나 더 열려서 돌아갈 길이 사라진다.
                  ],
                );
              },
            ),
          ),
          // 이 달의 스코어보드는 달력 위에 있다 — 격자를 보기 전에 "이 달이
          // 어땠나"부터 읽힌다. 스크롤 본문이 아니라 여기 붙어야 달을 넘길 때
          // 같이 따라온다.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SetflowSpacing.gutter,
              0,
              SetflowSpacing.gutter,
              SetflowSpacing.sm2,
            ),
            child: _MonthSummary(month: month),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 격자·요일 헤더·아래 섹션 전부 이 값 — 페이지 여백(gutter)과
                // 같아야 요약 카드와 양끝이 맞는다.
                const horizontalPadding = SetflowSpacing.gutter;
                const summaryWidth = 54.0;
                // 폴드·태블릿에서도 화면 폭을 그대로 쓴다 — 640 클램프는 폰 프레임
                // 시절의 유물이다.
                final contentWidth = constraints.maxWidth;
                final dayWidth =
                    (contentWidth - horizontalPadding * 2 - summaryWidth) / 7;
                // 칸이 커진 것은 장식이 아니라 내용 때문이다: 한 날에 어떤
                // 종목을 했는지까지 칸 안에 적는다. 접힌 주간이 기본이라
                // 세로 여유는 충분하다.
                final rowHeight = (dayWidth * 1.9).clamp(92.0, 116.0);
                return GestureDetector(
                  onHorizontalDragEnd: (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    if (velocity.abs() < 120) return;
                    _step(velocity < 0 ? 1 : -1);
                  },
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AnimatedSwitcher(
                      duration: SetflowMotion.standard,
                      switchInCurve: SetflowMotion.standardCurve,
                      switchOutCurve: SetflowMotion.standardCurve,
                      child: Padding(
                        key: ValueKey('${month.year}-${month.month}'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                        ),
                        child: Column(
                          children: [
                            _CalendarWeekdayHeader(summaryWidth: summaryWidth),
                            const SizedBox(height: SetflowSpacing.xs2),
                            for (final week in weeks)
                              _CollapsibleWeek(
                                visible:
                                    expanded || identical(week, foldedWeek),
                                height: rowHeight,
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (final day in week)
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.all(2),
                                          child: _CalendarCell(
                                            date: day,
                                            session: state
                                                .sessions[state.dateOnly(day)],
                                            unit: state.weightUnit,
                                            feedbackCount: state
                                                .memberSessionFeedbackForDate(
                                                  day,
                                                )
                                                .length,
                                            inMonth: day.month == month.month,
                                            isToday: DateUtils.isSameDay(
                                              day,
                                              DateTime.now(),
                                            ),
                                            onTap: () =>
                                                _handleDayTap(context, day),
                                            onItemDropped: (item) =>
                                                _handleCalendarDrop(
                                                  context,
                                                  item,
                                                  day,
                                                ),
                                            onDragStarted: () {
                                              HapticFeedback.mediumImpact();
                                              setState(() => dragSource = day);
                                            },
                                            onDragEnded: () {
                                              if (mounted) {
                                                setState(
                                                  () => dragSource = null,
                                                );
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                    SizedBox(
                                      width: summaryWidth,
                                      child: _WeeklySummary(week: week),
                                    ),
                                  ],
                                ),
                              ),
                            _CalendarFoldHandle(
                              key: const Key('calendar-fold-handle'),
                              expanded: expanded,
                              onPressed: _toggleExpanded,
                            ),
                            const SizedBox(height: SetflowSpacing.xl),
                            _MemberCoachingScheduleSection(
                              schedules: state.coachingSchedules,
                              memberUserId: state.businessAccess?.userId,
                              loading: state.coachingSchedulesLoading,
                              error: state.coachingSchedulesError,
                              onRetry: () async {
                                try {
                                  await state.refreshCoachingSchedules();
                                } catch (_) {
                                  // The compact section keeps the retry state visible.
                                }
                              },
                            ),
                            const SizedBox(height: SetflowSpacing.xl),
                            const _RecentBestsSection(),
                            const _RecentSessionsSection(),
                            const SizedBox(height: SetflowSpacing.xl),
                            _MyRoutinePreviewSection(
                              onDragStarted: (routine) {
                                HapticFeedback.mediumImpact();
                                setState(() => draggedRoutine = routine);
                              },
                              onDragEnded: () {
                                if (mounted) {
                                  setState(() => draggedRoutine = null);
                                }
                              },
                            ),
                            if (dragSource != null || draggedRoutine != null)
                              Container(
                                margin: const EdgeInsets.only(top: 10),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: dark
                                      ? Colors.white12
                                      : SetflowColors.ink,
                                  borderRadius: BorderRadius.circular(
                                    SetflowRadii.md,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.drag_indicator_rounded,
                                      color: SetflowColors.primary,
                                      size: 18,
                                    ),
                                    const SizedBox(width: SetflowSpacing.sm),
                                    Expanded(
                                      child: Text(
                                        draggedRoutine != null
                                            ? '${draggedRoutine!.name}을 원하는 날짜 위에 놓아주세요'
                                            : '${dragSource!.month}월 ${dragSource!.day}일 운동을 다른 날짜 위에 놓아주세요',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: SetflowFontSize.caption,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
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

  void _handleDayTap(BuildContext context, DateTime day) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => DailyWorkoutScreen(date: day)));
  }

  void _handleWorkoutDrop(
    BuildContext context,
    DateTime source,
    DateTime target,
  ) {
    final state = AppScope.of(context);
    final copied = state.copySession(source, target);
    if (copied == 0) {
      AppSnackbar.info(context, '대상 날짜에 같은 운동이 이미 있어요.');
      return;
    }
    HapticFeedback.selectionClick();
    AppSnackbar.success(
      context,
      '${target.month}월 ${target.day}일에 운동 $copied개를 복사했어요.',
    );
  }

  void _handleCalendarDrop(BuildContext context, Object item, DateTime target) {
    if (item is DateTime) {
      _handleWorkoutDrop(context, item, target);
      return;
    }
    if (item is! RoutineData) return;
    final added = AppScope.of(context).applyRoutine(item, target);
    if (added == 0) {
      AppSnackbar.info(context, '이 날짜에 루틴 운동이 이미 모두 있어요.');
      return;
    }
    HapticFeedback.selectionClick();
    AppSnackbar.success(
      context,
      '${target.month}월 ${target.day}일에 ${item.name} 운동 $added개를 적용했어요.',
    );
  }

  List<DateTime> _calendarDays(DateTime target) {
    final first = DateTime(target.year, target.month, 1);
    // 한국 달력은 일요일에서 시작한다 — 벽에 걸린 달력이 전부 그렇다.
    // weekday는 월=1..일=7이라, 일요일부터 세려면 7로 나눈 나머지가 밀어낼 칸 수다.
    final start = first.subtract(Duration(days: first.weekday % 7));
    return List.generate(42, (index) => start.add(Duration(days: index)));
  }
}

class _MemberCoachingScheduleSection extends StatelessWidget {
  const _MemberCoachingScheduleSection({
    required this.schedules,
    required this.memberUserId,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final List<BusinessCoachingSchedule> schedules;
  final String? memberUserId;
  final bool loading;
  final Object? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final userId = memberUserId;
    if (userId == null) return const SizedBox.shrink();
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final upcoming = schedules
        .where(
          (schedule) =>
              schedule.memberUserId == userId && !schedule.date.isBefore(start),
        )
        .take(3)
        .toList(growable: false);
    if (upcoming.isEmpty && !loading && error == null) {
      return const SizedBox.shrink();
    }
    if (upcoming.isEmpty && loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (upcoming.isEmpty && error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: OutlinedButton.icon(
          key: const Key('member-coaching-schedule-retry'),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('코칭 일정을 다시 불러오기'),
        ),
      );
    }

    return Padding(
      key: const Key('member-coaching-schedules'),
      padding: const EdgeInsets.only(top: 12),
      child: SetflowCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.event_note_rounded,
                  size: 19,
                  color: context.setflowColors.blue,
                ),
                const SizedBox(width: SetflowSpacing.sm),
                Text(
                  '예정된 코칭',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                Text(
                  '읽기 전용',
                  style: TextStyle(
                    fontSize: SetflowFontSize.tiny,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SetflowSpacing.sm),
            for (var index = 0; index < upcoming.length; index++) ...[
              if (index > 0) const Divider(height: 16),
              _MemberScheduleRow(schedule: upcoming[index]),
            ],
          ],
        ),
      ),
    );
  }
}

class _MemberScheduleRow extends StatelessWidget {
  const _MemberScheduleRow({required this.schedule});

  final BusinessCoachingSchedule schedule;

  @override
  Widget build(BuildContext context) {
    final startHour = (schedule.startMinutes ~/ 60).toString().padLeft(2, '0');
    final startMinute = (schedule.startMinutes % 60).toString().padLeft(2, '0');
    return Row(
      children: [
        Container(
          width: 44,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: context.setflowColors.blue.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(SetflowRadii.sm),
          ),
          child: Column(
            children: [
              Text(
                '${schedule.date.month}/${schedule.date.day}',
                style: const TextStyle(
                  fontSize: SetflowFontSize.tiny,
                  fontWeight: SetflowWeight.medium,
                ),
              ),
              Text(
                '$startHour:$startMinute',
                style: const TextStyle(fontSize: SetflowFontSize.tiny),
              ),
            ],
          ),
        ),
        const SizedBox(width: SetflowSpacing.sm2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                schedule.title,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              Text(
                schedule.trainerName ?? schedule.gymName ?? '담당 트레이너',
                style: TextStyle(
                  fontSize: SetflowFontSize.small,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Icon(
          schedule.isCompleted
              ? Icons.check_circle_rounded
              : Icons.chevron_right_rounded,
          size: 18,
          color: schedule.isCompleted
              ? context.setflowColors.success
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

class _MonthArrowButton extends StatelessWidget {
  const _MonthArrowButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      padding: EdgeInsets.zero,
      iconSize: 22,
      icon: Icon(icon),
    );
  }
}

/// 한 주 행. 접히면 높이가 0으로 줄면서 사라진다.
///
/// 높이를 직접 0으로 주면 안의 셀들이 찌그러지며 오버플로가 난다 —
/// 그래서 자식은 늘 제 높이를 갖고, 잘라내는 건 [Align.heightFactor] 쪽이다.
class _CollapsibleWeek extends StatelessWidget {
  const _CollapsibleWeek({
    required this.visible,
    required this.height,
    required this.child,
  });

  final bool visible;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: visible ? 1 : 0, end: visible ? 1 : 0),
      duration: SetflowMotion.standard,
      curve: SetflowMotion.standardCurve,
      builder: (context, factor, child) {
        if (factor <= 0) return const SizedBox.shrink();
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: factor,
            // 접히는 중인 주는 눈에만 남는다 — 탭이나 드롭을 받으면 안 된다.
            child: IgnorePointer(
              ignoring: !visible,
              child: Opacity(opacity: factor, child: child),
            ),
          ),
        );
      },
      child: SizedBox(height: height, child: child),
    );
  }
}

/// 월간 ↔ 주간을 바꾸는 손잡이. 화살표가 가리키는 쪽이 결과다.
class _CalendarFoldHandle extends StatelessWidget {
  const _CalendarFoldHandle({
    super.key,
    required this.expanded,
    required this.onPressed,
  });

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = expanded ? '이번 주만 보기' : '한 달 전체 보기';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Center(
        child: Tooltip(
          message: label,
          child: Semantics(
            button: true,
            label: label,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(SetflowRadii.full),
              child: Container(
                width: 76,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.setflowColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(SetflowRadii.full),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Icon(
                  expanded ? SetflowIcons.collapse : SetflowIcons.expand,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarWeekdayHeader extends StatelessWidget {
  const _CalendarWeekdayHeader({required this.summaryWidth});

  final double summaryWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: context.setflowColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(SetflowRadii.sm),
      ),
      child: Row(
        children: [
          for (var index = 0; index < 7; index++)
            Expanded(
              child: Center(
                child: Text(
                  ['일', '월', '화', '수', '목', '금', '토'][index],
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: SetflowWeight.medium,
                    // 달력은 한국 사람이 평생 봐 온 규칙이 있다 — 일요일과 공휴일은
                    // 빨강, 토요일은 파랑. 농도로 대신하면 그냥 흐린 글자일 뿐이다.
                    color: switch (index) {
                      0 => context.setflowColors.error,
                      6 => context.setflowColors.blue,
                      _ => theme.colorScheme.onSurface,
                    },
                  ),
                ),
              ),
            ),
          SizedBox(
            width: summaryWidth,
            child: Center(
              child: Text(
                '합계',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: SetflowWeight.medium,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarCell extends StatelessWidget {
  const _CalendarCell({
    required this.date,
    required this.session,
    required this.unit,
    required this.feedbackCount,
    required this.inMonth,
    required this.isToday,
    required this.onTap,
    required this.onItemDropped,
    required this.onDragStarted,
    required this.onDragEnded,
  });
  final DateTime date;
  final WorkoutSession? session;
  final String unit;
  final int feedbackCount;
  final bool inMonth;
  final bool isToday;
  final VoidCallback onTap;
  final ValueChanged<Object> onItemDropped;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completion = session?.completion ?? 0;
    final hasSession = (session?.totalSets ?? 0) > 0;
    // 종목 이름은 칸에 안 들어간다("레그 프…"로 잘려서 아무것도 못 읽었다).
    // 그날의 **부위**를 적는다 — 가슴 · 등. 부위는 짧고, 달력을 훑을 때 묻는 것도
    // "이번 주 어디를 했나"다. 종목은 칸을 열면 있다.
    final muscles = <String>{
      for (final item in session?.exercises ?? const <WorkoutExercise>[])
        item.template.muscle,
    }.toList();
    final muscleFills = [for (final muscle in muscles) _muscleFill(muscle)];
    final resistanceVolumeLabel = session == null || session!.volume <= 0
        ? ''
        : session!.volume > 1000
        ? '${(session!.volume / 1000).toStringAsFixed(1)}t'
        : '${session!.volume.toStringAsFixed(0)}$unit';
    final cardioSeconds = session?.cardioDurationSeconds ?? 0;
    final cardioMinutes = _formatMinuteValue(cardioSeconds / 60);
    final activityLabel = [
      if (resistanceVolumeLabel.isNotEmpty) resistanceVolumeLabel,
      if (cardioSeconds > 0) '$cardioMinutes분',
    ].join(' · ');
    final semanticLabel = StringBuffer(
      '${date.year}년 ${date.month}월 ${date.day}일',
    );
    if (hasSession) {
      final resistanceSets = session!.exercises
          .where((exercise) => !exercise.template.isCardio)
          .fold<int>(
            0,
            (sum, exercise) =>
                sum + exercise.sets.where((set) => set.completed).length,
          );
      final cardioSegments = session!.exercises
          .where((exercise) => exercise.template.isCardio)
          .fold<int>(
            0,
            (sum, exercise) =>
                sum + exercise.sets.where((set) => set.completed).length,
          );
      if (resistanceSets > 0) semanticLabel.write(', $resistanceSets세트 완료');
      if (resistanceVolumeLabel.isNotEmpty) {
        semanticLabel.write(', 근력 볼륨 $resistanceVolumeLabel');
      }
      if (cardioSegments > 0) {
        semanticLabel.write(', 유산소 $cardioSegments구간 $cardioMinutes분 완료');
      }
    } else {
      semanticLabel.write(', 운동 기록 없음');
    }
    if (feedbackCount > 0) {
      semanticLabel.write(', 코치 피드백 $feedbackCount개');
    }

    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) => switch (details.data) {
        final DateTime source => !DateUtils.isSameDay(source, date),
        RoutineData() => true,
        _ => false,
      },
      onAcceptWithDetails: (details) => onItemDropped(details.data),
      builder: (context, candidates, rejected) {
        final isDropTarget = candidates.isNotEmpty;
        final cell = Opacity(
          opacity: inMonth ? 1 : .32,
          child: Semantics(
            button: true,
            label: semanticLabel.toString(),
            hint: hasSession ? '길게 눌러 다른 날짜로 운동 복사' : null,
            excludeSemantics: true,
            child: AnimatedContainer(
              duration: SetflowMotion.micro,
              decoration: BoxDecoration(
                color: isDropTarget
                    ? theme.colorScheme.primary.withValues(alpha: .15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(SetflowRadii.sm),
                boxShadow: isDropTarget
                    ? [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(
                            alpha: .24,
                          ),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
              ),
              child: Material(
                // 이 달의 칸은 빈 날에도 옅은 상자를 깐다 — 상자가 있어야
                // 격자가 격자로 보인다. 운동한 날이 묻히지 않는 것은 색이 아니라
                // 위계가 지킨다: 기록 있는 날만 더 진한 채움 + 테두리 + 내용을
                // 갖고, 앞뒤 달에서 넘어온 칸은 칠하지 않아 달의 모양이 남는다.
                // 운동한 날의 채움은 회색이 아니라 **부위 색 틴트**다 — 두 부위면
                // 틴트가 그라데이션으로 이어진다. 채움은 Material이 아니라 아래
                // Ink가 그린다(Material 색엔 그라데이션이 없다).
                color: isDropTarget
                    ? theme.colorScheme.primaryContainer
                    : hasSession
                    ? Colors.transparent
                    : inMonth
                    ? context.setflowColors.surfaceContainerLow
                    : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(SetflowRadii.sm),
                  side: BorderSide(
                    color: isDropTarget
                        ? theme.colorScheme.primary
                        : hasSession
                        ? theme.colorScheme.outlineVariant
                        : Colors.transparent,
                    width: isDropTarget ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Ink(
                  key: ValueKey(
                    'calendar-tint-${date.year}${date.month}${date.day}',
                  ),
                  decoration: hasSession && !isDropTarget
                      ? BoxDecoration(
                          gradient: LinearGradient(
                            colors: _muscleFills(
                              muscleFills,
                              completion: completion.clamp(0, 1).toDouble(),
                            ),
                          ),
                        )
                      : null,
                  child: InkWell(
                    onTap: onTap,
                    child: MediaQuery.withClampedTextScaling(
                      // 달력 칸의 높이는 격자가 정한다 — 한 달이 한 화면에 들어와야
                      // 달력이다. 그래서 이 안의 글자만 배율을 1.2배로 묶는다.
                      // 나머지 화면은 시스템 설정을 그대로 따른다.
                      maxScaleFactor: 1.2,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
                        child: Column(
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                  alignment: Alignment.center,
                                  decoration: isToday
                                      ? BoxDecoration(
                                          color: theme.colorScheme.primary,
                                          shape: BoxShape.circle,
                                        )
                                      : null,
                                  child: Text(
                                    '${date.day}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: SetflowWeight.medium,
                                      color: isToday
                                          ? theme.colorScheme.onPrimary
                                          : isRestDay(date)
                                          ? context.setflowColors.error
                                          : date.weekday == DateTime.saturday
                                          ? context.setflowColors.blue
                                          : theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                if (feedbackCount > 0)
                                  Positioned(
                                    right: 0,
                                    child: Icon(
                                      Icons.mark_chat_unread_rounded,
                                      key: ValueKey(
                                        'calendar-feedback-${date.year}-'
                                        '${date.month}-${date.day}',
                                      ),
                                      size: 13,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                              ],
                            ),
                            const Spacer(),
                            if (hasSession) ...[
                              // 부위와 볼륨은 글자로만. 예전엔 완료율에 따라 teal/orange
                              // 틴트를 깔았는데, 바로 위 오늘 표시가 라임이라 한 칸에
                              // 색이 셋이었고 어느 것도 의미로 읽히지 않았다.
                              Text(
                                muscles.join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontSize: SetflowFontSize.micro,
                                  height: 1.25,
                                  fontWeight: SetflowWeight.medium,
                                ),
                              ),
                              Text(
                                activityLabel,
                                maxLines: 1,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: SetflowFontSize.micro,
                                  height: 1.2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: SetflowSpacing.xs),
                              // 막대는 없다 — 완료율은 채움의 진하기가 말한다.
                            ] else
                              const SizedBox(height: SetflowSpacing.xl),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        if (!hasSession) return cell;
        return LongPressDraggable<Object>(
          data: date,
          onDragStarted: onDragStarted,
          onDragEnd: (_) => onDragEnded(),
          feedback: Material(
            elevation: 10,
            borderRadius: BorderRadius.circular(SetflowRadii.md),
            color: theme.colorScheme.inverseSurface,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.fitness_center_rounded,
                    size: 18,
                    color: theme.colorScheme.onInverseSurface,
                  ),
                  const SizedBox(width: SetflowSpacing.sm),
                  Text(
                    '${date.month}월 ${date.day}일 · 운동 ${session!.exercises.length}개',
                    style: TextStyle(
                      color: theme.colorScheme.onInverseSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: .25, child: cell),
          child: cell,
        );
      },
    );
  }
}

/// What the month came to, under the grid that drew it.
///
/// The calendar ends about two thirds of the way down the phone and nothing
/// followed it, so home was a grid floating over an empty half-screen. The
/// honest thing to put there is the total the grid already implies — it reads
/// as the answer to "how did this month go", which is the question someone
/// opens a training calendar with.
///
/// The empty month says so in one line rather than showing three zeros. A zero
/// is a result; no records at all is not.
// ---------------------------------------------------------------------------
// 홈 하단 — 달력 아래는 **내 데이터**다: 오늘, 이번 주, 최근 기록(PR), 최근 운동.
// 전에는 전문가 루틴 미리보기와 함께 운동 광고 카드였다("캘린더 아래 컨텐츠들이
// 별로야, 전면 개편"). 마켓은 기록 시트에 있고 함께는 제 탭이 있다 — 홈이 그걸
// 또 팔 이유가 없다. 여기 있는 것은 전부 기기의 기록에서 계산한 값이고, 값이
// 없으면 섹션째 사라진다(빈 카드로 자리를 채우지 않는다).
// ---------------------------------------------------------------------------

const _weekdayShort = ['일', '월', '화', '수', '목', '금', '토'];

Color _muscleColor(BuildContext context, String muscle) =>
    muscleColorOf(context, muscle);

/// 달력 칸 채움 색 — 면 전용 팔레트(`SetflowMuscleFill`). 점·글자에 쓰는
/// [_muscleColor]와 짝이 같다(가슴=빨강 계열 …), 밝기만 다르다.
Color _muscleFill(String muscle) => switch (muscle) {
  '가슴' => SetflowMuscleFill.chest,
  '등' => SetflowMuscleFill.back,
  '어깨' => SetflowMuscleFill.shoulders,
  '하체' => SetflowMuscleFill.legs,
  '팔' => SetflowMuscleFill.arms,
  '복근' => SetflowMuscleFill.core,
  _ => SetflowMuscleFill.cardio,
};

/// 칸 채움 — 깃허브 잔디처럼. 색은 그날의 부위, **진하기는 완료율**이다: 계획만
/// 있는 날은 연하게, 다 한 날은 원색. 두 부위면 그 색들이 그라데이션으로 이어진다.
/// 하나면 같은 색 둘(그라데이션 API가 둘을 요구한다).
List<Color> _muscleFills(List<Color> colors, {required double completion}) {
  const floor = .45;
  final alpha = floor + (1 - floor) * completion.clamp(0, 1);
  final filled = [for (final c in colors) c.withValues(alpha: alpha)];
  if (filled.isEmpty) return [Colors.transparent, Colors.transparent];
  if (filled.length == 1) return [filled.first, filled.first];
  return filled;
}

/// 세트가 하나라도 있는 날만 "운동한 날"이다. 최근순.
List<WorkoutSession> _sessionsNewestFirst(AppState state) =>
    state.sessions.values.where((s) => s.totalSets > 0).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

String _volumeText(double volume, String unit) => volume >= 1000
    ? '${(volume / 1000).toStringAsFixed(1)}t'
    : '${volume.round()}$unit';

String _exercisesText(WorkoutSession session) {
  final lead = session.exercises.first.template.name;
  final others = session.exercises.length - 1;
  return others > 0 ? '$lead 외 $others종' : lead;
}

/// "3세트 · 400kg" — 볼륨이 0이면(맨몸·유산소) kg을 찍지 않는다. "1세트 · 0kg"은
/// 틀린 숫자처럼 보인다. 유산소만 한 날은 시간으로 말한다.
String _sessionSummaryText(WorkoutSession session, String unit) {
  final sets = '${session.completedSets}세트';
  if (session.volume > 0) return '$sets · ${_volumeText(session.volume, unit)}';
  final minutes = session.cardioDurationSeconds ~/ 60;
  if (minutes > 0) return '$sets · $minutes분';
  return sets;
}

String _shortDate(DateTime date) =>
    '${date.month}/${date.day} (${_weekdayShort[date.weekday % 7]})';

/// 큰 숫자 하나 — 운동 앱의 주인공은 숫자다. 단위는 작게, 숫자는 tabular.
class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.unit});

  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    final dim = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          maxLines: 1,
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              TextSpan(
                text: unit,
                style: theme.textTheme.labelMedium?.copyWith(color: dim),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 헤어라인 한 줄 — 목록은 상자가 아니라 선으로 나눈다.
class _HairlineRow extends StatelessWidget {
  const _HairlineRow({required this.child, this.onTap, super.key});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: SetflowSpacing.md),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: child,
      ),
    );
  }
}

/// 최근 기록 — 최근 30일 안에 **이전 최고를 넘긴** 종목별 중량. 헤어라인 목록,
/// 숫자 앞의 라임 네모가 "기록"이다. 없으면 섹션이 없다.
class _RecentBestsSection extends StatelessWidget {
  const _RecentBestsSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = AppScope.of(context);
    final sessions = _sessionsNewestFirst(state);
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final templates = <String, ExerciseTemplate>{
      for (final session in sessions)
        if (!session.date.isBefore(cutoff))
          for (final exercise in session.exercises)
            if (!exercise.template.isCardio)
              exercise.template.id: exercise.template,
    };
    final rows = <(ExerciseTemplate, PerformanceSetRecord)>[];
    for (final template in templates.values) {
      final summary = PerformanceEngine.summarize(
        sessions: sessions,
        template: template,
        formula: state.oneRepMaxFormula,
      );
      if (summary == null) continue;
      final best = summary.weightPr;
      if (best.date.isBefore(cutoff)) continue;
      // 기록은 넘었을 때 생긴다 — 그 날보다 앞선 세션이 있어야 한다.
      final hasEarlier = sessions.any(
        (session) =>
            session.date.isBefore(best.date) &&
            session.exercises.any((e) => e.template.id == template.id),
      );
      if (!hasEarlier) continue;
      rows.add((template, best));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    rows.sort((a, b) => b.$2.date.compareTo(a.$2.date));

    return Column(
      key: const ValueKey('home-bests'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('최근 기록'),
        const SizedBox(height: SetflowSpacing.xs),
        for (final (template, best) in rows.take(3))
          _HairlineRow(
            child: Row(
              children: [
                Container(
                  width: SetflowSpacing.sm,
                  height: SetflowSpacing.sm,
                  margin: const EdgeInsets.only(right: SetflowSpacing.sm),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _muscleColor(context, template.muscle),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template.name,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: SetflowSpacing.xxs),
                      Text(
                        _shortDate(best.date),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: SetflowSpacing.sm,
                  height: SetflowSpacing.sm,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: SetflowSpacing.sm),
                _Figure(
                  value: PerformanceEngine.formatWeight(best.set.weight),
                  unit: '${state.weightUnit} × ${best.set.reps}',
                ),
              ],
            ),
          ),
        const SizedBox(height: SetflowSpacing.section),
      ],
    );
  }
}

/// 최근 운동 — 세트를 끝낸 최근 세 번(오늘 제외). 헤어라인 목록, 탭하면 그날로.
class _RecentSessionsSection extends StatelessWidget {
  const _RecentSessionsSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = AppScope.of(context);
    final today = state.dateOnly(DateTime.now());
    final recent = _sessionsNewestFirst(
      state,
    ).where((s) => s.completedSets > 0 && s.date != today).take(3).toList();
    if (recent.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('최근 운동'),
        const SizedBox(height: SetflowSpacing.xs),
        for (final session in recent)
          _HairlineRow(
            key: ValueKey(
              'home-recent-${session.date.year}${session.date.month}${session.date.day}',
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DailyWorkoutScreen(date: session.date),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    _shortDate(session.date),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                // 부위 색 점 — 그날의 첫 종목 부위. 색은 여기서만 의미를 갖는다.
                Container(
                  width: SetflowSpacing.sm,
                  height: SetflowSpacing.sm,
                  margin: const EdgeInsets.only(right: SetflowSpacing.sm),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _muscleColor(
                      context,
                      session.exercises.first.template.muscle,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    _exercisesText(session),
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: SetflowSpacing.sm),
                Text(
                  _sessionSummaryText(session, state.weightUnit),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: SetflowSpacing.xs),
                Icon(
                  SetflowIcons.forward,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 홈에서 바로 날짜에 적용하는 실제 내 루틴.
///
/// 카드를 길게 눌러 캘린더 날짜에 놓으면 [AppState.applyRoutine]이 기존
/// 운동과 안전하게 병합한다.
class _MyRoutinePreviewSection extends StatelessWidget {
  const _MyRoutinePreviewSection({
    required this.onDragStarted,
    required this.onDragEnded,
  });

  final ValueChanged<RoutineData> onDragStarted;
  final VoidCallback onDragEnded;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final routines = state.routines.take(4).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          '나의 루틴',
          action: '전체 보기',
          onAction: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const RoutinesScreen())),
        ),
        const SizedBox(height: SetflowSpacing.xs),
        Text(
          '루틴을 길게 눌러 위 캘린더의 원하는 날짜에 놓아주세요.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: SetflowSpacing.sm),
        if (routines.isEmpty)
          SetflowCard(
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const RoutinesScreen())),
            child: Row(
              children: [
                const Icon(SetflowIcons.routine),
                const SizedBox(width: SetflowSpacing.md),
                Expanded(
                  child: Text(
                    '저장된 루틴이 없어요. 나의 루틴에서 먼저 만들어보세요.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const Icon(SetflowIcons.forward),
              ],
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (index, routine) in routines.indexed) ...[
                  if (index > 0) const SizedBox(width: SetflowSpacing.sm2),
                  _MyRoutineHomeCard(
                    routine: routine,
                    onDragStarted: () => onDragStarted(routine),
                    onDragEnded: onDragEnded,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _MyRoutineHomeCard extends StatelessWidget {
  const _MyRoutineHomeCard({
    required this.routine,
    required this.onDragStarted,
    required this.onDragEnded,
  });

  final RoutineData routine;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 250,
      child: LongPressDraggable<Object>(
        data: routine,
        onDragStarted: onDragStarted,
        onDragEnd: (_) => onDragEnded(),
        feedback: Material(
          elevation: 10,
          color: theme.colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(SetflowRadii.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SetflowSpacing.lg,
              vertical: SetflowSpacing.md,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  SetflowIcons.routine,
                  size: 18,
                  color: theme.colorScheme.onInverseSurface,
                ),
                const SizedBox(width: SetflowSpacing.sm),
                Text(
                  '${routine.name} · ${routine.exercises.length}개 운동',
                  style: TextStyle(
                    color: theme.colorScheme.onInverseSurface,
                    fontWeight: SetflowWeight.strong,
                  ),
                ),
              ],
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: .28,
          child: _MyRoutineCardBody(routine: routine),
        ),
        child: _MyRoutineCardBody(routine: routine),
      ),
    );
  }
}

class _MyRoutineCardBody extends StatelessWidget {
  const _MyRoutineCardBody({required this.routine});

  final RoutineData routine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SetflowCard(
      key: ValueKey('home-routine-${routine.id}'),
      padding: const EdgeInsets.all(SetflowSpacing.lg),
      onTap: () async {
        final updated = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => RoutineEditorScreen(routine: routine),
          ),
        );
        if (updated == true && context.mounted) {
          AppSnackbar.success(context, '루틴 변경사항을 저장했어요.');
        }
      },
      child: Semantics(
        hint: '길게 눌러 캘린더 날짜에 적용',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 32,
                  decoration: BoxDecoration(
                    color: routine.color,
                    borderRadius: BorderRadius.circular(SetflowRadii.full),
                  ),
                ),
                const SizedBox(width: SetflowSpacing.sm),
                Expanded(
                  child: Text(
                    '${routine.exercises.length}개 운동 · ${routine.level}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: SetflowWeight.medium,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SetflowSpacing.md),
            Text(
              routine.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: SetflowFontSize.title,
                fontWeight: FontWeight.w900,
                height: 1.25,
              ),
            ),
            const SizedBox(height: SetflowSpacing.xs),
            Text(
              routine.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SetflowSpacing.md),
            Row(
              children: [
                Icon(
                  SetflowIcons.home,
                  size: 15,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: SetflowSpacing.xs),
                Expanded(
                  child: Text(
                    '길게 눌러 날짜에 적용',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: SetflowWeight.strong,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthSummary extends StatelessWidget {
  const _MonthSummary({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = AppScope.of(context);
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final sessions = [
      for (var day = 1; day <= daysInMonth; day++)
        state.sessions[state.dateOnly(DateTime(month.year, month.month, day))],
    ].whereType<WorkoutSession>().where((s) => s.totalSets > 0).toList();

    final volume = sessions.fold<double>(0, (sum, s) => sum + s.volume);
    // 셋째 지표는 유산소 분에서 완료 세트로 바꿨다. 유산소를 안 하는 달은
    // 0분이 자리만 차지했고, 세트 수는 근력·유산소 어느 쪽이든 "실제로 몸을
    // 움직인 횟수"라 일수·볼륨과 같은 축에서 읽힌다.
    final completedSets = sessions.fold<int>(
      0,
      (sum, s) =>
          sum +
          s.exercises.fold<int>(
            0,
            (a, e) => a + e.sets.where((set) => set.completed).length,
          ),
    );

    if (sessions.isEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            SetflowIcons.home,
            size: 16,
            color: context.setflowColors.disabled,
          ),
          const SizedBox(width: SetflowSpacing.sm),
          Flexible(
            child: Text(
              '${month.month}월 기록이 아직 없어요',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }

    // 회색 카드에 구분선으로 나눈 세 칸은 달력 격자와 다른 부품처럼 보였다
    // ("디자인이 안 맞다"). 요약은 페이지 위에 그냥 놓인 숫자 셋이다 —
    // 격자·헤더와 같은 면, 같은 여백.
    return Row(
      children: [
        _MonthSummaryStat(
          value: '${sessions.length}',
          unit: '일',
          label: '${month.month}월 운동',
        ),
        const SizedBox(width: SetflowSpacing.xxl),
        _MonthSummaryStat(
          value: volume > 1000
              ? (volume / 1000).toStringAsFixed(1)
              : volume.toStringAsFixed(0),
          unit: volume > 1000 ? 't' : state.weightUnit,
          label: '총 볼륨',
        ),
        const SizedBox(width: SetflowSpacing.xxl),
        _MonthSummaryStat(value: '$completedSets', unit: '세트', label: '완료 세트'),
      ],
    );
  }
}

class _MonthSummaryStat extends StatelessWidget {
  const _MonthSummaryStat({
    required this.value,
    required this.unit,
    required this.label,
  });

  final String value;
  final String unit;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Flexible(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: SetflowWeight.display,
                    // 숫자가 세로로 안 흔들리게 — 달을 넘길 때 자릿수가 바뀐다.
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                TextSpan(
                  text: unit,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: SetflowWeight.strong,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklySummary extends StatelessWidget {
  const _WeeklySummary({required this.week});
  final List<DateTime> week;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final sessions = week
        .map((date) => state.sessions[state.dateOnly(date)])
        .whereType<WorkoutSession>();
    final sets = sessions.fold<int>(
      0,
      (sum, session) =>
          sum +
          session.exercises
              .where((exercise) => !exercise.template.isCardio)
              .fold<int>(
                0,
                (setSum, exercise) =>
                    setSum + exercise.sets.where((set) => set.completed).length,
              ),
    );
    final volume = sessions.fold<double>(0, (sum, item) => sum + item.volume);
    final cardioSeconds = sessions.fold<int>(
      0,
      (sum, session) => sum + session.cardioDurationSeconds,
    );
    final theme = Theme.of(context);
    // 날짜 칸이 전부 상자를 갖게 되면서 합계 칸도 같은 격자의 일부다 —
    // 빈 주는 옅은 채움만, 내용 있는 주만 테두리로 선다. 날짜 칸과 같은 위계다.
    final hasAnything = sets > 0 || cardioSeconds > 0 || volume > 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 2, 2, 2),
      decoration: BoxDecoration(
        color: hasAnything
            ? context.setflowColors.surfaceContainer
            : context.setflowColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(SetflowRadii.sm),
        border: Border.all(
          color: hasAnything
              ? theme.colorScheme.outlineVariant
              : Colors.transparent,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (sets > 0)
            RichText(
              text: TextSpan(
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                children: [
                  TextSpan(
                    text: '$sets',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: SetflowFontSize.caption,
                      fontWeight: SetflowWeight.medium,
                    ),
                  ),
                  const TextSpan(
                    text: ' 세트',
                    style: TextStyle(
                      fontSize: SetflowFontSize.micro,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          if (cardioSeconds > 0)
            Text(
              '${_formatMinuteValue(cardioSeconds / 60)}분 유산소',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: SetflowFontSize.micro,
                fontWeight: FontWeight.w800,
              ),
            ),
          if (volume > 0)
            Text(
              volume > 1000
                  ? '${(volume / 1000).toStringAsFixed(1)}t'
                  : '${volume.toStringAsFixed(0)}${state.weightUnit}',
              style: TextStyle(
                fontSize: SetflowFontSize.micro,
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

class RoutinesScreen extends StatelessWidget {
  const RoutinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 루틴'),
        actions: [
          // 전문가 루틴 lost its own tab to the center action; same domain, so
          // it lives here rather than in a menu nobody opens.
          IconButton(
            key: const ValueKey('routines-open-market'),
            tooltip: '전문가 루틴',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const MarketScreen())),
            icon: const Icon(SetflowIcons.market),
          ),
          IconButton(
            tooltip: '루틴 만들기',
            onPressed: () => _createRoutine(context),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          _IncomingRoutineSharesSection(state: state),
          if (state.pendingRoutineShareToken != null ||
              state.incomingRoutineShares.any(
                (share) => share.status == RoutineShareStatus.pending,
              ))
            const SizedBox(height: SetflowSpacing.xl),
          Row(
            children: [
              Expanded(
                child: Text(
                  '저장된 루틴 ${state.routines.length}/4',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '무료 플랜',
                style: TextStyle(
                  fontSize: SetflowFontSize.small,
                  fontWeight: SetflowWeight.medium,
                  // 플랜 이름은 정보지 경고가 아니다. 주황을 쓰면 한도에
                  // 걸린 것처럼 읽힌다.
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.lg),
          // 루틴은 카드가 아니라 줄이다 — 헤어라인으로 나누고, 식별색 선 하나,
          // 종목은 칩 무더기 대신 한 문장, 편집은 큰 테두리 버튼 대신 글자 버튼.
          for (final routine in state.routines)
            Container(
              padding: const EdgeInsets.symmetric(vertical: SetflowSpacing.lg),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // 루틴 식별색은 남긴다 — 모델에 실려 공유 카드에도
                      // 나오는 정체성이다. 다만 카드에서 제일 큰 색 덩어리일
                      // 이유는 없어서, 굵은 알약에서 가는 선으로 줄였다.
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              routine.name,
                              style: const TextStyle(
                                fontSize: SetflowFontSize.titleLarge,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              '${routine.exercises.length}개 운동 · ${routine.level}',
                              style: TextStyle(
                                fontSize: SetflowFontSize.caption,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'apply', child: Text('오늘 적용')),
                          PopupMenuItem(value: 'edit', child: Text('수정')),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(
                              '삭제',
                              style: TextStyle(
                                color: context.setflowColors.error,
                              ),
                            ),
                          ),
                        ],
                        onSelected: (value) async {
                          if (value == 'apply') {
                            final added = state.applyRoutine(
                              routine,
                              DateTime.now(),
                            );
                            if (added == 0) {
                              AppSnackbar.info(
                                context,
                                '오늘 기록에 루틴 운동이 이미 모두 있어요.',
                              );
                            } else {
                              AppSnackbar.success(
                                context,
                                '오늘 캘린더에 운동 $added개를 적용했어요.',
                              );
                            }
                          } else if (value == 'edit') {
                            await _editRoutine(context, routine);
                          } else if (value == 'delete') {
                            final confirmed =
                                await showDialog<bool>(
                                  context: context,
                                  builder: (dialogContext) => AlertDialog(
                                    title: const Text('루틴을 삭제할까요?'),
                                    content: Text(
                                      '${routine.name} 루틴은 삭제 후 복구할 수 없습니다.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext, false),
                                        child: const Text('취소'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext, true),
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              context.setflowColors.error,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('삭제'),
                                      ),
                                    ],
                                  ),
                                ) ??
                                false;
                            if (confirmed && context.mounted) {
                              try {
                                final removed = await state.removeRoutine(
                                  routine,
                                );
                                if (!context.mounted) return;
                                if (removed) {
                                  AppSnackbar.success(context, '루틴을 삭제했어요.');
                                } else {
                                  AppSnackbar.error(
                                    context,
                                    '삭제할 루틴을 찾지 못했어요.',
                                  );
                                }
                              } catch (_) {
                                if (context.mounted) {
                                  AppSnackbar.error(
                                    context,
                                    '루틴을 서버에서 삭제하지 못했어요. 다시 시도해주세요.',
                                  );
                                }
                              }
                            }
                          }
                        },
                      ),
                    ],
                  ),
                  if (routine.description.isNotEmpty) ...[
                    const SizedBox(height: SetflowSpacing.sm),
                    Text(
                      routine.description,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  const SizedBox(height: SetflowSpacing.xs),
                  Text(
                    routine.exercises.map((item) => item.name).join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: SetflowSpacing.xs),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _editRoutine(context, routine),
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: const Text('루틴 편집'),
                    ),
                  ),
                ],
              ),
            ),
          if (state.routines.isEmpty)
            EmptyState(
              icon: Icons.playlist_add_rounded,
              title: '저장된 루틴이 없어요',
              message: '새 루틴을 만들거나 전문가 루틴을 저장해보세요.',
              actionLabel: '새 루틴 만들기',
              onAction: () => _createRoutine(context),
            ),
          OutlinedButton.icon(
            onPressed: state.routines.length >= 4
                ? () => AppSnackbar.info(context, '무료 플랜은 루틴을 4개까지 저장할 수 있어요.')
                : () => _createRoutine(context),
            icon: const Icon(Icons.add),
            label: const Text('새 루틴 만들기'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SetflowRadii.lg),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createRoutine(BuildContext context) async {
    final state = AppScope.of(context);
    if (state.routines.length >= 4) {
      AppSnackbar.error(context, '무료 플랜은 루틴을 4개까지 저장할 수 있어요.');
      return;
    }
    final draft = await showSetflowSheet<RoutineDraft>(
      context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const RoutineCreateSheet(),
    );
    if (draft == null || !context.mounted) return;
    bool created;
    try {
      created = await state.createPersonalRoutine(
        draft.name,
        draft.description,
      );
    } catch (_) {
      if (context.mounted) {
        AppSnackbar.error(context, '루틴을 서버에 저장하지 못했어요. 다시 시도해주세요.');
      }
      return;
    }
    if (!context.mounted) return;
    if (created) {
      AppSnackbar.success(context, '새 루틴을 저장했어요.');
    } else {
      AppSnackbar.error(context, '무료 플랜 저장 한도에 도달했어요.');
    }
  }

  Future<void> _editRoutine(BuildContext context, RoutineData routine) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RoutineEditorScreen(routine: routine)),
    );
    if (updated == true && context.mounted) {
      AppSnackbar.success(context, '루틴 변경사항을 저장했어요.');
    }
  }
}

class _IncomingRoutineSharesSection extends StatelessWidget {
  const _IncomingRoutineSharesSection({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final pendingShares = state.incomingRoutineShares
        .where((share) => share.status == RoutineShareStatus.pending)
        .toList(growable: false);
    final pendingToken = state.pendingRoutineShareToken;
    if (pendingShares.isEmpty && pendingToken == null) {
      return Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () => _showRoutineShareCodeSheet(context),
          icon: const Icon(Icons.link_rounded, size: 18),
          label: const Text('공유 코드 받기'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '트레이너가 보낸 루틴',
                style: TextStyle(
                  fontSize: SetflowFontSize.titleLarge,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _showRoutineShareCodeSheet(context),
              child: const Text('코드 입력'),
            ),
          ],
        ),
        const SizedBox(height: SetflowSpacing.sm),
        if (pendingToken != null)
          Padding(
            padding: const EdgeInsets.only(bottom: SetflowSpacing.md),
            child: SetflowCard(
              color: SetflowColors.primary.withValues(alpha: .07),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.mark_email_unread_rounded,
                        color: SetflowColors.primary,
                      ),
                      SizedBox(width: SetflowSpacing.sm),
                      Expanded(
                        child: Text(
                          '공유받은 루틴이 있어요',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: SetflowSpacing.xs),
                  Text(
                    '링크의 루틴을 확인하고 내 루틴으로 안전하게 가져옵니다.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: SetflowFontSize.caption,
                    ),
                  ),
                  const SizedBox(height: SetflowSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: '나중에',
                          variant: AppButtonVariant.outlined,
                          onPressed: state.clearPendingRoutineShareToken,
                        ),
                      ),
                      const SizedBox(width: SetflowSpacing.sm),
                      Expanded(
                        child: AppButton(
                          label: '루틴 받기',
                          icon: Icons.download_done_rounded,
                          onPressed: () =>
                              _acceptRoutineShareToken(context, pendingToken),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        for (final share in pendingShares)
          Padding(
            padding: const EdgeInsets.only(bottom: SetflowSpacing.md),
            child: _IncomingRoutineShareCard(state: state, share: share),
          ),
      ],
    );
  }
}

class _IncomingRoutineShareCard extends StatelessWidget {
  const _IncomingRoutineShareCard({required this.state, required this.share});

  final AppState state;
  final RoutineShareRecord share;

  @override
  Widget build(BuildContext context) {
    final isSaving = state.isRespondingRoutineShare(share.id);
    final expiresAt = share.expiresAt;
    return SetflowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: context.setflowColors.orange.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(SetflowRadii.md),
                ),
                child: Icon(
                  Icons.fitness_center_rounded,
                  color: context.setflowColors.orange,
                ),
              ),
              const SizedBox(width: SetflowSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      share.routineTitle,
                      style: const TextStyle(
                        fontSize: SetflowFontSize.title,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${share.senderName} · ${share.routine?.exercises.length ?? 0}개 운동',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: SetflowFontSize.caption,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: context.setflowColors.success.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(SetflowRadii.full),
                ),
                child: Text(
                  '새 루틴',
                  style: TextStyle(
                    color: context.setflowColors.success,
                    fontSize: SetflowFontSize.tiny,
                    fontWeight: SetflowWeight.medium,
                  ),
                ),
              ),
            ],
          ),
          if (share.message case final String message
              when message.isNotEmpty) ...[
            const SizedBox(height: SetflowSpacing.md),
            Text(message, style: const TextStyle(height: 1.45)),
          ],
          if (expiresAt != null) ...[
            const SizedBox(height: SetflowSpacing.sm),
            Text(
              '${DateFormat('yyyy.MM.dd HH:mm').format(expiresAt.toLocal())}까지 수락 가능',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: SetflowFontSize.small,
              ),
            ),
          ],
          const SizedBox(height: SetflowSpacing.md),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: '거절',
                  variant: AppButtonVariant.outlined,
                  onPressed: isSaving
                      ? null
                      : () => _declineRoutineShare(context, share),
                ),
              ),
              const SizedBox(width: SetflowSpacing.sm),
              Expanded(
                child: AppButton(
                  label: '수락',
                  icon: Icons.check_rounded,
                  isLoading: isSaving,
                  onPressed: isSaving
                      ? null
                      : () => _acceptRoutineShare(context, share),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoutineAcceptDecision {
  const _RoutineAcceptDecision({this.applyDate});

  final DateTime? applyDate;
}

Future<_RoutineAcceptDecision?> _askRoutineAcceptDecision(
  BuildContext context,
) async {
  final choice = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('루틴을 받을까요?'),
      content: const Text(
        '원본 운동 순서와 저항운동의 중량·횟수·휴식, '
        '유산소의 시간·거리·RPE를 그대로 저장합니다.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'save'),
          child: const Text('저장만'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, 'apply'),
          child: const Text('날짜에 적용'),
        ),
      ],
    ),
  );
  if (!context.mounted || choice == null) return null;
  if (choice == 'save') return const _RoutineAcceptDecision();
  final date = await showDatePicker(
    context: context,
    initialDate: DateTime.now(),
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: DateTime.now().add(const Duration(days: 730)),
    helpText: '루틴을 적용할 날짜',
    cancelText: '취소',
    confirmText: '적용',
  );
  return date == null ? null : _RoutineAcceptDecision(applyDate: date);
}

Future<void> _acceptRoutineShare(
  BuildContext context,
  RoutineShareRecord share,
) async {
  final decision = await _askRoutineAcceptDecision(context);
  if (decision == null || !context.mounted) return;
  final state = AppScope.of(context);
  try {
    await state.respondToRoutineShare(
      share.id,
      accept: true,
      applyDate: decision.applyDate,
    );
    if (!context.mounted) return;
    AppSnackbar.success(
      context,
      decision.applyDate == null
          ? '루틴을 내 루틴에 저장했어요.'
          : '${DateFormat('M월 d일').format(decision.applyDate!)} 캘린더에 루틴을 적용했어요.',
    );
  } catch (_) {
    if (context.mounted) {
      AppSnackbar.error(context, '루틴을 받지 못했어요. 만료 여부를 확인해주세요.');
    }
  }
}

Future<void> _declineRoutineShare(
  BuildContext context,
  RoutineShareRecord share,
) async {
  final confirmed =
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('공유를 거절할까요?'),
          content: Text('${share.routineTitle} 루틴은 받은 목록에서 사라집니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('거절'),
            ),
          ],
        ),
      ) ??
      false;
  if (!confirmed || !context.mounted) return;
  try {
    await AppScope.of(context).respondToRoutineShare(share.id, accept: false);
    if (context.mounted) AppSnackbar.info(context, '루틴 공유를 거절했어요.');
  } catch (_) {
    if (context.mounted) AppSnackbar.error(context, '요청을 처리하지 못했어요.');
  }
}

Future<void> _acceptRoutineShareToken(
  BuildContext context,
  String token,
) async {
  final decision = await _askRoutineAcceptDecision(context);
  if (decision == null || !context.mounted) return;
  try {
    await AppScope.of(
      context,
    ).acceptRoutineShareToken(token, applyDate: decision.applyDate);
    if (!context.mounted) return;
    AppSnackbar.success(
      context,
      decision.applyDate == null
          ? '공유 루틴을 내 루틴에 저장했어요.'
          : '${DateFormat('M월 d일').format(decision.applyDate!)} 캘린더에 루틴을 적용했어요.',
    );
  } catch (_) {
    if (context.mounted) {
      AppSnackbar.error(context, '공유 링크가 만료됐거나 이미 사용할 수 없어요.');
    }
  }
}

Future<void> _showRoutineShareCodeSheet(BuildContext context) async {
  final controller = TextEditingController();
  Future<void>? sheetCompleted;
  final token = await showSetflowSheet<String>(
    context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      sheetCompleted ??= ModalRoute.of(sheetContext)?.completed;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          SetflowSpacing.lg,
          SetflowSpacing.sm,
          SetflowSpacing.lg,
          MediaQuery.viewInsetsOf(sheetContext).bottom + SetflowSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '공유 루틴 받기',
              style: Theme.of(sheetContext).textTheme.headlineSmall,
            ),
            const SizedBox(height: SetflowSpacing.sm),
            Text(
              '트레이너에게 받은 링크 또는 공유 코드를 붙여넣어 주세요.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SetflowSpacing.lg),
            TextField(
              controller: controller,
              autofocus: true,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '공유 링크 또는 코드',
                prefixIcon: Icon(Icons.link_rounded),
              ),
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) Navigator.pop(sheetContext, value);
              },
            ),
            const SizedBox(height: SetflowSpacing.lg),
            AppButton(
              label: '확인',
              icon: Icons.arrow_forward_rounded,
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) Navigator.pop(sheetContext, value);
              },
            ),
          ],
        ),
      );
    },
  );
  await sheetCompleted;
  controller.dispose();
  if (token == null || token.trim().isEmpty || !context.mounted) return;
  await _acceptRoutineShareToken(context, token);
}

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  final searchController = TextEditingController();
  String filter = '전체';
  String sort = '인기순';

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final query = searchController.text.trim().toLowerCase();
    final routines = state.marketRoutines.where((routine) {
      final matchesQuery =
          query.isEmpty ||
          routine.name.toLowerCase().contains(query) ||
          routine.author.toLowerCase().contains(query) ||
          routine.description.toLowerCase().contains(query) ||
          routine.exercises.any(
            (exercise) => exercise.name.toLowerCase().contains(query),
          );
      final matchesFilter =
          filter == '전체' ||
          routine.level == filter ||
          (filter == '근육 증가' &&
              routine.exercises.any((exercise) => !exercise.isCardio)) ||
          (filter == '체중 감량' &&
              routine.exercises.any((exercise) => exercise.isCardio));
      return matchesQuery && matchesFilter;
    }).toList();
    if (sort == '이름순') {
      routines.sort((a, b) => a.name.compareTo(b.name));
    } else if (sort == '최신순') {
      routines.sort((a, b) => b.id.compareTo(a.id));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('전문가 루틴'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '정렬',
            initialValue: sort,
            onSelected: (value) => setState(() => sort = value),
            itemBuilder: (_) => ['인기순', '최신순', '이름순']
                .map((item) => PopupMenuItem(value: item, child: Text(item)))
                .toList(),
            icon: const Icon(Icons.swap_vert_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        children: [
          AppTextField(
            controller: searchController,
            onChanged: (_) => setState(() {}),
            prefixIcon: const Icon(Icons.search),
            hint: '목표, 운동, 트레이너 검색',
          ),
          const SizedBox(height: SetflowSpacing.md2),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['전체', '체중 감량', '근육 증가', '초급', '중급']
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(item),
                        selected: filter == item,
                        onSelected: (_) => setState(() => filter = item),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: SetflowSpacing.xxl),
          SectionTitle(
            query.isEmpty && filter == '전체'
                ? '지금 인기 있는 루틴'
                : '검색 결과 ${routines.length}개',
          ),
          const SizedBox(height: SetflowSpacing.sm2),
          if (routines.isEmpty)
            EmptyState(
              icon: Icons.search_off_rounded,
              title: '조건에 맞는 루틴이 없어요',
              message: '검색어나 필터를 바꿔 다시 찾아보세요.',
              actionLabel: '검색 초기화',
              onAction: () => setState(() {
                searchController.clear();
                filter = '전체';
              }),
            ),
          for (final (index, routine) in routines.indexed)
            // 카드가 아니라 줄이다 — 이름, 설명, 메타(난이도 · 무료/유료 · 작성자).
            // 무료/유료는 알약이 아니라 색 글자(성공색/보라)로만 구분한다.
            InkWell(
              key: ValueKey('market-card-$index'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ExpertRoutineDetailScreen(routine: routine),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: SetflowSpacing.lg,
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            routine.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: SetflowSpacing.xs),
                          Text(
                            routine.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: SetflowSpacing.sm),
                          Row(
                            children: [
                              Text(
                                routine.level,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              Text(
                                ' · ',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              _RoutineAccessBadge(
                                accessTier: routine.accessTier,
                              ),
                              Text(
                                ' · ',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              Icon(
                                Icons.verified_rounded,
                                color: context.setflowColors.blue,
                                size: 14,
                              ),
                              const SizedBox(width: SetflowSpacing.xxs),
                              Flexible(
                                child: Text(
                                  routine.author,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: SetflowSpacing.sm),
                    Icon(
                      SetflowIcons.forward,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _RoutineAccessBadge extends StatelessWidget {
  const _RoutineAccessBadge({required this.accessTier});

  final RoutineAccessTier accessTier;

  @override
  Widget build(BuildContext context) {
    final isPaid = accessTier == RoutineAccessTier.paid;
    // 알약이 아니라 색 글자다 — 무료는 성공색, 유료는 보라. 뜻이 있는 색만 쓴다.
    return Semantics(
      label: '${accessTier.label} 루틴',
      child: Text(
        accessTier.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: isPaid
              ? context.setflowColors.purple
              : context.setflowColors.success,
        ),
      ),
    );
  }
}

/// 피드 한 줄 — 작성자·시간, 지표(제목 자리), 본문 두 줄, 오른쪽에 사진 또는 아이콘.
class _CommunityRow extends StatelessWidget {
  const _CommunityRow({required this.post, required this.onTap});

  final CommunityPost post;
  final VoidCallback onTap;

  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return '방금';
    if (d.inHours < 1) return '${d.inMinutes}분 전';
    if (d.inDays < 1) return '${d.inHours}시간 전';
    if (d.inDays < 7) return '${d.inDays}일 전';
    return '${at.month}/${at.day}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      label: '${post.author}의 게시물, ${post.content}',
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: SetflowSpacing.md),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            post.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: post.isMine
                                  ? theme.colorScheme.onSurface
                                  : muted,
                            ),
                          ),
                        ),
                        Text(
                          ' · ${_ago(post.createdAt)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: SetflowSpacing.xs),
                    Text(
                      post.metric,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (post.content.isNotEmpty) ...[
                      const SizedBox(height: SetflowSpacing.xxs),
                      Text(
                        post.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: SetflowSpacing.md),
              ClipRRect(
                borderRadius: BorderRadius.circular(SetflowRadii.sm),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: post.imageUrl == null
                      ? Center(child: Icon(post.icon, size: 26, color: muted))
                      : Image.network(
                          post.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              size: 22,
                              color: muted,
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});
  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  String sort = '최신순';

  Future<void> _compose() async {
    // Posts leave this device and carry an author, so this is where the account
    // is asked for — not at launch.
    if (!await requireSignIn(context, reason: AuthReason.community)) return;
    if (!mounted) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SocialPostComposerScreen()),
    );
    if (created == true && mounted) {
      AppSnackbar.success(context, '게시물을 등록했어요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final posts = [...state.communityPosts];
    switch (sort) {
      case '좋아요순':
        posts.sort((a, b) => b.likes.compareTo(a.likes));
      case '댓글순':
        posts.sort((a, b) => b.comments.length.compareTo(a.comments.length));
      default:
        posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('커뮤니티'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '게시물 정렬',
            initialValue: sort,
            onSelected: (value) => setState(() => sort = value),
            itemBuilder: (_) => ['최신순', '좋아요순', '댓글순']
                .map((item) => PopupMenuItem(value: item, child: Text(item)))
                .toList(),
            icon: const Icon(Icons.swap_vert_rounded),
          ),
        ],
      ),
      body: posts.isEmpty
          ? EmptyState(
              icon: Icons.photo_library_outlined,
              title: '아직 게시물이 없어요',
              message: '첫 운동 기록을 공유하고 서로 응원해보세요.',
              actionLabel: '첫 게시물 작성',
              onAction: _compose,
            )
          // 회색 타일 격자는 사진이 없는 게시물을 전부 "빈 칸"으로 보이게 했다.
          // 피드는 **줄**이다: 헤어라인으로 나누고, 사진이 있으면 오른쪽에 작게,
          // 없으면 종목 아이콘. 지표("하체 · 12세트 · 4.2t")가 제목 자리다 —
          // 운동 피드에서 먼저 읽을 것은 문장이 아니라 숫자다.
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                SetflowSpacing.gutter,
                SetflowSpacing.xs,
                SetflowSpacing.gutter,
                100,
              ),
              itemCount: posts.length,
              itemBuilder: (_, index) => _CommunityRow(
                post: posts[index],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        CommunityPostDetailScreen(post: posts[index]),
                  ),
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('community-compose'),
        onPressed: _compose,
        // 라임은 바텀바 가운데 원 하나가 갖는다. 그 옆에 라임 원을 하나 더
        // 놓으면 어느 쪽이 이 화면의 동작인지 알 수 없다. 그래서 여기는
        // 테두리만 있는 2차 동작이다 — 검정 블록도 아니고, 라임도 아니다.
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        highlightElevation: 0,
        shape: CircleBorder(
          side: BorderSide(color: Theme.of(context).colorScheme.onSurface),
        ),
        child: const Icon(SetflowIcons.addExercise),
      ),
    );
  }
}

class CoachingScreen extends StatelessWidget {
  const CoachingScreen({super.key});

  Future<void> _newConsult(BuildContext context) async {
    if (!await requireSignIn(context, reason: AuthReason.coaching)) return;
    if (!context.mounted) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ConsultationCreateScreen()),
    );
    if (created == true && context.mounted) {
      AppSnackbar.success(context, '상담이 접수되었습니다.');
    }
  }

  Future<void> _refresh(BuildContext context) async {
    final state = AppScope.of(context);
    try {
      if (state.usesLiveBusinessData) {
        await state.refreshMemberConsultations();
      } else {
        await state.refreshBusinessDashboard(state.role);
      }
    } catch (_) {
      if (context.mounted) {
        AppSnackbar.error(context, '상담 내역을 불러오지 못했어요.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final activeConsultations = _activeMemberConsultations(state);
    final unknownStatusCount = state.usesLiveBusinessData
        ? state.memberConsultations
              .where(
                (item) => item.status == BusinessConsultationStatus.unknown,
              )
              .length
        : 0;
    return Scaffold(
      appBar: AppBar(title: const Text('코칭')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: SetflowColors.primary.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(SetflowRadii.xl),
            ),
            child: Row(
              children: [
                Icon(Icons.support_agent_rounded, color: SetflowColors.ink),
                SizedBox(width: SetflowSpacing.md2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '내 기록을 전문가와 연결하세요',
                        style: TextStyle(
                          fontSize: SetflowFontSize.titleLarge,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: SetflowSpacing.xs2),
                      Text(
                        '상담 답변을 확인하고 1:1 코칭까지 이어갈 수 있어요.',
                        style: TextStyle(
                          fontSize: SetflowFontSize.caption,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.lg),
          AppButton(
            key: const ValueKey('coaching-new-consultation-primary'),
            label: '새 상담 신청',
            icon: Icons.edit_note_rounded,
            onPressed: () => _newConsult(context),
          ),
          const SizedBox(height: SetflowSpacing.xxl),
          SectionTitle('진행 중 상담 ${activeConsultations.length}건'),
          const SizedBox(height: SetflowSpacing.sm2),
          if (state.usesLiveBusinessData &&
              state.memberConsultationsLoading &&
              state.memberConsultations.isEmpty)
            const LoadingState(
              key: ValueKey('coaching-active-loading'),
              message: '진행 중인 상담을 불러오고 있어요',
              itemCount: 2,
              compact: true,
            )
          else if (state.usesLiveBusinessData &&
              state.memberConsultationsError != null &&
              state.memberConsultations.isEmpty)
            ErrorState(
              key: const ValueKey('coaching-active-error'),
              message: '진행 중인 상담을 확인하지 못했어요.',
              onRetry: () => _refresh(context),
            )
          else if (activeConsultations.isEmpty)
            const EmptyState(
              key: ValueKey('coaching-active-empty'),
              icon: Icons.support_agent_rounded,
              title: '진행 중인 상담이 없어요',
              message: '운동 목표와 고민을 전문가에게 질문해보세요.',
            )
          else
            for (final entry in activeConsultations)
              Padding(
                key: ValueKey(
                  'coaching-active-consultation-${entry.consultation.id}',
                ),
                padding: const EdgeInsets.only(bottom: SetflowSpacing.md),
                child: SetflowCard(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ConsultationDetailScreen(
                        consultation: entry.consultation,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.person_rounded,
                            color: context.setflowColors.blue,
                          ),
                          const SizedBox(width: SetflowSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.consultation.trainerName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  entry.consultation.specialty,
                                  style: TextStyle(
                                    fontSize: SetflowFontSize.caption,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _MemberConsultationBadge(entry: entry),
                        ],
                      ),
                      const Divider(height: 28),
                      Text(
                        entry.consultation.question,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(height: 1.45),
                      ),
                    ],
                  ),
                ),
              ),
          if (state.usesLiveBusinessData &&
              state.memberConsultationsError != null &&
              state.memberConsultations.isNotEmpty) ...[
            const SizedBox(height: SetflowSpacing.sm),
            SetflowCard(
              key: const ValueKey('coaching-active-stale-warning'),
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(SetflowSpacing.md),
              child: Row(
                children: [
                  Icon(
                    Icons.sync_problem_rounded,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: SetflowSpacing.sm),
                  Expanded(
                    child: Text(
                      '최신 상담 상태를 확인하지 못했어요. 표시된 내용은 이전 동기화 결과입니다.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: state.memberConsultationsLoading
                        ? null
                        : () => _refresh(context),
                    child: const Text('재시도'),
                  ),
                ],
              ),
            ),
          ],
          if (unknownStatusCount > 0) ...[
            const SizedBox(height: SetflowSpacing.sm),
            SetflowCard(
              key: const ValueKey('coaching-unknown-status-notice'),
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(SetflowSpacing.md),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: SetflowSpacing.sm),
                  Expanded(
                    child: Text(
                      '상태 확인이 필요한 상담이 $unknownStatusCount건 있어요. '
                      '새로고침 후에도 계속되면 고객센터에 문의해주세요.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: SetflowSpacing.xs),
          OutlinedButton.icon(
            key: const ValueKey('coaching-consultation-history'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ConsultationHistoryScreen(),
              ),
            ),
            icon: const Icon(Icons.history_rounded),
            label: const Text('과거 상담 이력'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SetflowRadii.lg),
              ),
            ),
          ),
          const SizedBox(height: SetflowSpacing.xxl2),
          const SectionTitle('코칭 보호 정책'),
          const SizedBox(height: SetflowSpacing.sm),
          SetflowCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.shield_outlined,
                  color: context.setflowColors.success,
                ),
                SizedBox(width: SetflowSpacing.md),
                Expanded(
                  child: Text(
                    '운동 일지 작성 후 72시간 안에 피드백을 받지 못하면 중도 해지 요청이 활성화됩니다.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
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

class ConsultationHistoryScreen extends StatefulWidget {
  const ConsultationHistoryScreen({super.key});

  @override
  State<ConsultationHistoryScreen> createState() =>
      _ConsultationHistoryScreenState();
}

class _ConsultationHistoryScreenState extends State<ConsultationHistoryScreen> {
  Future<void> _refresh() async {
    final state = AppScope.of(context);
    try {
      if (state.usesLiveBusinessData) {
        await state.refreshMemberConsultations();
      } else {
        await state.refreshBusinessDashboard(state.role);
      }
    } catch (_) {
      if (mounted) {
        AppSnackbar.error(context, '과거 상담 이력을 새로고침하지 못했어요.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final history = _historicalMemberConsultations(state);
    final initialLoadFailed =
        state.usesLiveBusinessData &&
        state.memberConsultationsError != null &&
        history.isEmpty;
    final isLoading =
        state.usesLiveBusinessData &&
        state.memberConsultationsLoading &&
        state.memberConsultations.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('과거 상담 이력'),
        actions: [
          IconButton(
            key: const ValueKey('consultation-history-refresh'),
            tooltip: '새로고침',
            onPressed: state.memberConsultationsLoading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        key: const ValueKey('consultation-history-refresh-indicator'),
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: LoadingState(
                  key: ValueKey('consultation-history-loading'),
                  message: '과거 상담 이력을 불러오고 있어요',
                ),
              )
            else if (initialLoadFailed && history.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorState(
                  key: const ValueKey('consultation-history-error'),
                  message: '과거 상담 이력을 불러오지 못했어요.',
                  onRetry: _refresh,
                ),
              )
            else if (history.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  key: ValueKey('consultation-history-empty'),
                  icon: Icons.history_rounded,
                  title: '아직 과거 상담 이력이 없어요',
                  message: '답변이 완료된 상담이 여기에 모여요.',
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  18,
                  SetflowSpacing.md,
                  18,
                  SetflowSpacing.sm,
                ),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    '답변이 완료된 상담 ${history.length}건',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(),
                  ),
                ),
              ),
              if (state.usesLiveBusinessData &&
                  state.memberConsultationsError != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    18,
                    0,
                    18,
                    SetflowSpacing.md,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: SetflowCard(
                      key: const ValueKey('consultation-history-stale-warning'),
                      color: Theme.of(context).colorScheme.errorContainer,
                      padding: const EdgeInsets.all(SetflowSpacing.md),
                      child: Text(
                        '최신 이력을 확인하지 못해 이전 동기화 결과를 표시하고 있어요.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
                sliver: SliverList.separated(
                  key: const ValueKey('consultation-history-list'),
                  itemCount: history.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: SetflowSpacing.md),
                  itemBuilder: (context, index) =>
                      _ConsultationHistoryCard(entry: history[index]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConsultationHistoryCard extends StatelessWidget {
  const _ConsultationHistoryCard({required this.entry});

  final _MemberConsultationEntry entry;

  @override
  Widget build(BuildContext context) {
    final consultation = entry.consultation;
    final answer = consultation.response?.trim();
    return SetflowCard(
      key: ValueKey('consultation-history-item-${consultation.id}'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ConsultationDetailScreen(consultation: consultation),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.support_agent_rounded,
                color: context.setflowColors.success,
              ),
              const SizedBox(width: SetflowSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      consultation.trainerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: SetflowSpacing.xxs),
                    Text(
                      DateFormat(
                        'yyyy.MM.dd HH:mm',
                      ).format(consultation.createdAt.toLocal()),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _MemberConsultationBadge(entry: entry),
            ],
          ),
          const Divider(height: SetflowSpacing.xl),
          Text(
            consultation.question.trim().isEmpty
                ? '질문 내용이 저장되지 않았어요.'
                : consultation.question,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, height: 1.45),
          ),
          const SizedBox(height: SetflowSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(SetflowSpacing.md),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(SetflowRadii.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '전문가 답변',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(),
                ),
                const SizedBox(height: SetflowSpacing.xs),
                Text(
                  answer == null || answer.isEmpty
                      ? '답변 내용을 상세 화면에서 확인해주세요.'
                      : answer,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.45,
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

class _MemberConsultationBadge extends StatelessWidget {
  const _MemberConsultationBadge({required this.entry});

  final _MemberConsultationEntry entry;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (entry.cloud?.status) {
      BusinessConsultationStatus.pending => (
        '답변 대기',
        context.setflowColors.orange,
      ),
      BusinessConsultationStatus.assigned => (
        '담당 배정',
        context.setflowColors.blue,
      ),
      BusinessConsultationStatus.answered => (
        '답변 완료',
        context.setflowColors.success,
      ),
      BusinessConsultationStatus.replied => (
        '상담 완료',
        context.setflowColors.success,
      ),
      BusinessConsultationStatus.unknown => (
        '상태 확인 필요',
        context.setflowColors.error,
      ),
      null => switch (entry.consultation.status) {
        ConsultationStatus.waiting => ('답변 대기', context.setflowColors.orange),
        ConsultationStatus.answered => ('상담 완료', context.setflowColors.success),
        ConsultationStatus.coaching => ('코칭 중', context.setflowColors.blue),
      },
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
}

class _MemberConsultationEntry {
  const _MemberConsultationEntry({required this.consultation, this.cloud});

  final ConsultationData consultation;
  final BusinessConsultation? cloud;
}

List<_MemberConsultationEntry> _activeMemberConsultations(AppState state) {
  if (!state.usesLiveBusinessData) {
    return state.consultations
        .where(
          (item) =>
              item.status == ConsultationStatus.waiting ||
              item.status == ConsultationStatus.coaching,
        )
        .map((item) => _MemberConsultationEntry(consultation: item))
        .toList(growable: false);
  }
  return state.memberConsultations
      .where(
        (item) =>
            item.status == BusinessConsultationStatus.pending ||
            item.status == BusinessConsultationStatus.assigned,
      )
      .map(_memberConsultationEntry)
      .toList(growable: false);
}

List<_MemberConsultationEntry> _historicalMemberConsultations(AppState state) {
  if (!state.usesLiveBusinessData) {
    return state.consultations
        .where((item) => item.status == ConsultationStatus.answered)
        .map((item) => _MemberConsultationEntry(consultation: item))
        .toList(growable: false);
  }
  return state.memberConsultations
      .where(
        (item) =>
            item.status == BusinessConsultationStatus.answered ||
            item.status == BusinessConsultationStatus.replied,
      )
      .map(_memberConsultationEntry)
      .toList(growable: false);
}

_MemberConsultationEntry _memberConsultationEntry(BusinessConsultation cloud) {
  return _MemberConsultationEntry(
    consultation: _consultationDataFromCloud(cloud),
    cloud: cloud,
  );
}

ConsultationData _consultationDataFromCloud(BusinessConsultation record) {
  final responseMessages =
      record.messages
          .where(
            (message) =>
                message.sender == BusinessMessageSender.trainer ||
                message.sender == BusinessMessageSender.gym,
          )
          .toList()
        ..sort(
          (left, right) =>
              (left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                  .compareTo(
                    right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                  ),
        );
  return ConsultationData(
    id: record.id,
    trainerName: record.trainerName ?? record.gymName ?? '담당 전문가',
    specialty: record.specialty ?? record.goal ?? '맞춤 운동 상담',
    goal: record.goal ?? '',
    level: record.level ?? '',
    question: record.question ?? '',
    createdAt: record.createdAt ?? DateTime.now(),
    status:
        record.status == BusinessConsultationStatus.answered ||
            record.status == BusinessConsultationStatus.replied
        ? ConsultationStatus.answered
        : ConsultationStatus.waiting,
    response: responseMessages.lastOrNull?.text,
    sharedRecommendationProfile: record.sharedRecommendationProfile,
    recommendationProfileShareRevokedAt:
        record.recommendationProfileShareRevokedAt,
  );
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final today = state.dateOnly(DateTime.now());
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final week = List.generate(
      7,
      (index) => weekStart.add(Duration(days: index)),
    );
    final weeklySessions = week
        .map((day) => state.sessions[state.dateOnly(day)])
        .toList();
    final weeklyVolumes = weeklySessions
        .map((session) => session?.volume ?? 0)
        .toList();
    final weeklyCardioMinutes = weeklySessions
        .map((session) => (session?.cardioDurationSeconds ?? 0) / 60)
        .toList(growable: false);
    final totalVolume = weeklyVolumes.fold<double>(
      0,
      (sum, value) => sum + value,
    );
    final totalCardioMinutes = weeklyCardioMinutes.fold<double>(
      0,
      (sum, value) => sum + value,
    );
    final chartShowsResistance = totalVolume > 0;
    final chartValues = chartShowsResistance
        ? weeklyVolumes
        : weeklyCardioMinutes;
    final maxChartValue = chartValues.fold<double>(
      0,
      (best, value) => value > best ? value : best,
    );
    final totalSets = weeklySessions.fold<int>(
      0,
      (sum, session) => sum + (session?.totalSets ?? 0),
    );
    final completedSets = weeklySessions.fold<int>(
      0,
      (sum, session) => sum + (session?.completedSets ?? 0),
    );
    final workoutDays = weeklySessions
        .where((session) => (session?.completedSets ?? 0) > 0)
        .length;
    final summary = state.featuredPerformance;

    return Scaffold(
      appBar: AppBar(title: const Text('운동 대시보드')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        children: [
          Row(
            children: [
              MetricCard(
                label: '이번 주',
                value: '$workoutDays',
                suffix: '회',
                icon: Icons.calendar_today,
                tint: context.setflowColors.teal,
              ),
              const SizedBox(width: SetflowSpacing.sm2),
              MetricCard(
                label: chartShowsResistance ? '근력 볼륨' : '유산소 시간',
                value: chartShowsResistance
                    ? totalVolume >= 1000
                          ? (totalVolume / 1000).toStringAsFixed(1)
                          : totalVolume.toStringAsFixed(0)
                    : _formatMinuteValue(totalCardioMinutes),
                suffix: chartShowsResistance
                    ? totalVolume >= 1000
                          ? 't'
                          : state.weightUnit
                    : '분',
                icon: chartShowsResistance
                    ? Icons.monitor_weight_outlined
                    : Icons.directions_run_rounded,
                tint: context.setflowColors.orange,
              ),
            ],
          ),
          if (chartShowsResistance && totalCardioMinutes > 0) ...[
            const SizedBox(height: SetflowSpacing.md),
            SetflowCard(
              child: Row(
                children: [
                  Icon(
                    Icons.directions_run_rounded,
                    color: context.setflowColors.teal,
                  ),
                  const SizedBox(width: SetflowSpacing.md),
                  Expanded(
                    child: Text(
                      '이번 주 유산소 '
                      '${_formatMinuteValue(totalCardioMinutes)}분',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Text(
                    '시간·거리·RPE 기록',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: SetflowFontSize.small,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: SetflowSpacing.md),
          Row(
            children: [
              MetricCard(
                label: '연속 기록',
                value: '${_currentStreak(state, today)}',
                suffix: '일',
                icon: Icons.local_fire_department,
                tint: context.setflowColors.error,
              ),
              const SizedBox(width: SetflowSpacing.sm2),
              MetricCard(
                label: '완료율',
                value: totalSets == 0
                    ? '0'
                    : '${(completedSets / totalSets * 100).round()}',
                suffix: '%',
                icon: Icons.check_circle_outline,
                tint: context.setflowColors.blue,
              ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.xxl2),
          SectionTitle(chartShowsResistance ? '주간 근력 볼륨' : '주간 유산소 시간'),
          const SizedBox(height: SetflowSpacing.sm2),
          SetflowCard(
            child: SizedBox(
              height: 170,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: maxChartValue == 0
                                      ? .04
                                      : (chartValues[i] / maxChartValue).clamp(
                                          .04,
                                          1.0,
                                        ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: i == today.weekday - 1
                                          ? SetflowColors.primary
                                          : context.setflowColors.teal
                                                .withValues(alpha: .7),
                                      borderRadius: BorderRadius.circular(
                                        SetflowRadii.xs,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: SetflowSpacing.xs2),
                            Text(
                              ['월', '화', '수', '목', '금', '토', '일'][i],
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
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: SetflowSpacing.xxl),
          const SectionTitle('MY PERFORMANCE'),
          const SizedBox(height: SetflowSpacing.sm2),
          if (summary == null)
            SetflowCard(
              child: Text(
                '완료한 근력 운동 세트가 쌓이면 e1RM과 PR 변화가 표시됩니다.',
                style: TextStyle(
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else ...[
            SetflowCard(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.trending_up,
                      color: context.setflowColors.orange,
                    ),
                    title: Text(
                      summary.template.name,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      summary.changeFromPrevious == null
                          ? '${summary.sessionCount}회 기록 · 추정 품질 ${summary.quality.label}'
                          : '직전 대비 '
                                '${summary.changeFromPrevious! >= 0 ? '+' : ''}'
                                '${summary.changeFromPrevious!.toStringAsFixed(1)}${state.weightUnit}',
                    ),
                    trailing: Text(
                      '${summary.currentE1rm.toStringAsFixed(1)}${state.weightUnit}',
                      style: const TextStyle(
                        fontSize: SetflowFontSize.titleLarge,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Divider(),
                  _PerformancePrRow(
                    label: '중량 PR',
                    value:
                        '${PerformanceEngine.formatWeight(summary.weightPr.set.weight)}${state.weightUnit}',
                  ),
                  _PerformancePrRow(
                    label: '반복 PR',
                    value:
                        '${PerformanceEngine.formatWeight(summary.repPr.set.weight)}${state.weightUnit} × '
                        '${summary.repPr.set.reps}회',
                  ),
                  _PerformancePrRow(
                    label: 'e1RM PR',
                    value:
                        '${summary.e1rmPr.estimate.value.toStringAsFixed(1)}${state.weightUnit}',
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static int _currentStreak(AppState state, DateTime today) {
    var streak = 0;
    var day = today;
    while ((state.sessions[state.dateOnly(day)]?.completedSets ?? 0) > 0) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }
}

class _PerformancePrRow extends StatelessWidget {
  const _PerformancePrRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _logout(BuildContext context, AppState state) async {
    final route = ModalRoute.of(context);
    Navigator.of(context).pop();
    await route?.completed;
    await state.logout();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          SetflowSpacing.gutter,
          4,
          SetflowSpacing.gutter,
          28,
        ),
        children: [
          ListTile(
            title: Text(
              '계정 & 개인화',
              style: TextStyle(
                fontSize: SetflowFontSize.label,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('계정 & 프로필'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const SettingDetailScreen(section: SettingSection.account),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_none),
            title: const Text('알림 설정'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SettingDetailScreen(
                  section: SettingSection.notifications,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('데이터 & 개인정보'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const SettingDetailScreen(section: SettingSection.privacy),
              ),
            ),
          ),
          const Divider(height: 30),
          ListTile(
            title: Text(
              '운동 기록',
              style: TextStyle(
                fontSize: SetflowFontSize.label,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          ListTile(
            key: const ValueKey('settings-workout'),
            leading: const Icon(Icons.fitness_center_outlined),
            title: const Text('운동 기록 환경설정'),
            subtitle: Text(
              '${state.weightUnit} · 휴식 ${state.restDefaultSeconds}초',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const SettingDetailScreen(section: SettingSection.workout),
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('다크 모드'),
            value: state.isDarkMode,
            onChanged: (_) => state.toggleTheme(),
          ),
          const Divider(height: 30),
          ListTile(
            title: Text(
              state.usesLiveBusinessData ? '전문가 계정' : '데모 워크스페이스',
              style: TextStyle(
                fontSize: SetflowFontSize.label,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (state.usesLiveBusinessData) ...[
            _BusinessRoleEntry(
              role: UserRole.trainer,
              icon: Icons.fitness_center,
              title: '트레이너',
              hasAccess:
                  state.businessAccess?.canUse(UserRole.trainer) ?? false,
              application: state.businessAccess?.trainerApplication,
            ),
            _BusinessRoleEntry(
              role: UserRole.gym,
              icon: Icons.apartment,
              title: '헬스장 / 센터장',
              hasAccess: state.businessAccess?.canUse(UserRole.gym) ?? false,
              application: state.businessAccess?.gymApplication,
            ),
          ] else ...[
            ListTile(
              leading: const Icon(Icons.fitness_center),
              title: const Text('트레이너 화면 보기 (데모)'),
              subtitle: const Text('샘플 데이터로 채운 미리보기예요.'),
              onTap: () {
                Navigator.pop(context);
                state.chooseRole(UserRole.trainer);
              },
            ),
            ListTile(
              leading: const Icon(Icons.apartment),
              title: const Text('헬스장 화면 보기 (데모)'),
              subtitle: const Text('샘플 데이터로 채운 미리보기예요.'),
              onTap: () {
                Navigator.pop(context);
                state.chooseRole(UserRole.gym);
              },
            ),
          ],
          if (state.isAdmin)
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('운영 관리자 화면 보기 (데모)'),
              onTap: () {
                Navigator.pop(context);
                state.chooseRole(UserRole.admin);
              },
            ),
          const Divider(height: 30),
          ListTile(
            title: Text(
              '참고자료',
              style: TextStyle(
                fontSize: SetflowFontSize.label,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          ListTile(
            key: const ValueKey('settings-evidence-library'),
            leading: const Icon(Icons.science_outlined),
            title: const Text('관련 논문'),
            subtitle: const Text('추천 계산과 운동 구성에 참고한 근거'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EvidenceLibraryScreen()),
            ),
          ),
          const Divider(height: 30),
          // Sign-in is only offered to a session that has nothing to sign out
          // of: no Supabase user *and* still a guest. A local member session
          // restored from a snapshot gets logout, not a login prompt.
          if (!Auth.instance.hasAuthenticatedUser &&
              state.role == UserRole.guest)
            ListTile(
              key: const ValueKey('settings-sign-in'),
              leading: const Icon(
                SetflowIcons.signIn,
                color: SetflowColors.primary,
              ),
              title: const Text('로그인 / 회원가입'),
              subtitle: const Text('기록을 클라우드에 백업하고 코칭을 사용하세요'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const WelcomeScreen())),
            )
          else
            ListTile(
              leading: Icon(
                SetflowIcons.signOut,
                color: context.setflowColors.error,
              ),
              title: Text(
                '로그아웃',
                style: TextStyle(color: context.setflowColors.error),
              ),
              // Waits for the sheet to finish closing before signing out, so the
              // teardown never races the route animation.
              onTap: () => _logout(context, state),
            ),
        ],
      ),
    );
  }
}

class _BusinessRoleEntry extends StatelessWidget {
  const _BusinessRoleEntry({
    required this.role,
    required this.icon,
    required this.title,
    required this.hasAccess,
    this.application,
  });

  final UserRole role;
  final IconData icon;
  final String title;
  final bool hasAccess;
  final BusinessApplication? application;

  @override
  Widget build(BuildContext context) {
    final status = application?.status;
    final pending = status == BusinessApplicationStatus.pending;
    final rejected = status == BusinessApplicationStatus.rejected;
    final subtitle = hasAccess
        ? '승인 완료 · 운영 화면 열기'
        : pending
        ? '관리자 심사 중'
        : rejected
        ? '반려됨 · ${application?.rejectReason ?? '정보를 보완해 다시 신청해주세요.'}'
        : '등록 정보를 제출하고 관리자 승인을 요청하세요.';
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: pending
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: pending
          ? null
          : () async {
              final state = AppScope.of(context);
              if (hasAccess) {
                Navigator.pop(context);
                state.chooseRole(role);
                return;
              }
              await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => BusinessSetupScreen(role: role),
                ),
              );
            },
    );
  }
}
