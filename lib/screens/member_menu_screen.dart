import 'package:flutter/material.dart';

import '../app_state.dart';
import '../member_navigation.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/auth_gate.dart';
import '../widgets/common.dart';
import '../widgets/member_navigation_editor.dart';
import '../widgets/member_navigation_items.dart';
import '../widgets/portal.dart';
import '../widgets/pro_access_gate.dart';
import 'detail_screens.dart';
import 'member_membership_screen.dart';
import 'member_screens.dart';
import 'welcome_screen.dart';
import 'workout_screens.dart';

/// 전체 메뉴 — 홈 왼쪽 위 그리드 버튼이 여는 서랍. OKX의 서랍과 같은 문법:
/// 큰 화면 제목 없이(이름이 곧 제목) 프로필이 먼저 서고, 기능은 섹션
/// 컨테이너 안의 **아이콘 그리드**다 — 설정처럼 줄로 세우면 목록이지 서랍이
/// 아니다(실기기 보고: "사진처럼 하라고 했는데 설정 페이지처럼 만들어놨네").
class MemberMenuScreen extends StatefulWidget {
  const MemberMenuScreen({super.key});

  @override
  State<MemberMenuScreen> createState() => _MemberMenuScreenState();
}

class _MemberMenuScreenState extends State<MemberMenuScreen> {
  bool _editing = false;
  bool _saving = false;
  String? _editingUserId;
  List<MemberDestination> _draft = MemberNavigation.defaults;

  void _startEditing() => setState(() {
    _draft = AppScope.of(context).memberNavigation;
    _editingUserId = Auth.instance.currentUser?.id;
    _editing = true;
  });

  void _place(MemberDestination destination, int slot) {
    if (_saving) return;
    setState(() => _draft = MemberNavigation.place(_draft, destination, slot));
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_editingUserId != Auth.instance.currentUser?.id) {
      setState(() => _editing = false);
      AppSnackbar.error(context, '계정이 바뀌었어요. 다시 편집해주세요.');
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await AppScope.of(context).saveMemberNavigation(_draft);
      if (!mounted) return;
      if (!saved) {
        AppSnackbar.error(context, '계정이 바뀌었어요. 다시 편집해주세요.');
      } else {
        AppSnackbar.success(context, '하단 메뉴를 저장했어요.');
      }
      setState(() => _editing = false);
    } catch (_) {
      if (mounted) AppSnackbar.error(context, '저장하지 못했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDestination(int slot) async {
    final destination = await showSetflowSheet<MemberDestination>(
      context,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: SetflowInsets.pageForm,
        children: [
          Text(
            '${slot + 1}번째 메뉴 선택',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final item in MemberDestination.values)
            ListTile(
              key: ValueKey('navigation-pick-${item.name}'),
              leading: Icon(item.icon),
              title: Text(item.label),
              selected: _draft[slot] == item,
              onTap: () => Navigator.of(sheetContext).pop(item),
            ),
        ],
      ),
    );
    if (mounted && _editing && destination != null) _place(destination, slot);
  }

  Future<void> _assignToSlot(MemberDestination destination) async {
    final slot = await showSetflowSheet<int>(
      context,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: SetflowInsets.pageForm,
        children: [
          Text(
            '${destination.label} 위치',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (var index = 0; index < _draft.length; index++)
            ListTile(
              key: ValueKey('navigation-assign-$index'),
              leading: Icon(_draft[index].icon),
              title: Text('${index + 1}번째 · ${_draft[index].label}'),
              onTap: () => Navigator.of(sheetContext).pop(index),
            ),
        ],
      ),
    );
    if (mounted && _editing && slot != null) _place(destination, slot);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = AppScope.of(context);
    final signedIn = Auth.instance.hasAuthenticatedUser;
    final name = state.memberDisplayName.isEmpty
        ? '게스트'
        : state.memberDisplayName;
    final today = state.dateOnly(DateTime.now());

    return PopScope(
      canPop: !_editing && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) setState(() => _editing = false);
      },
      child: Scaffold(
        // 제목 없는 앱바 — 뒤로가기 하나면 된다. 서랍의 제목은 아래 이름이다.
        appBar: AppBar(
          actions: [
            if (_editing) ...[
              TextButton(
                key: const ValueKey('navigation-reset'),
                onPressed: _saving
                    ? null
                    : () => setState(() => _draft = MemberNavigation.defaults),
                child: const Text('초기화'),
              ),
              TextButton(
                key: const ValueKey('navigation-save'),
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '저장 중' : '저장'),
              ),
            ] else
              TextButton(
                key: const ValueKey('navigation-edit'),
                onPressed: _startEditing,
                child: const Text('하단 메뉴 편집'),
              ),
          ],
        ),
        bottomNavigationBar: _editing
            ? AbsorbPointer(
                absorbing: _saving,
                child: MemberNavigationEditor(
                  destinations: _draft,
                  onPlace: _place,
                  onPick: _pickDestination,
                ),
              )
            : null,
        body: AbsorbPointer(
          absorbing: _saving,
          child: ListView(
            padding: SetflowInsets.pageList,
            children: [
              if (_editing) ...[
                const Text(
                  '메뉴를 길게 눌러 아래 원하는 자리에 놓으세요. 아래 메뉴끼리 옮기면 자리가 바뀌어요. 눌러서 바꿀 수도 있어요.',
                ),
                const SizedBox(height: SetflowSpacing.lg),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: theme.textTheme.headlineLarge),
                        const SizedBox(height: SetflowSpacing.xxs),
                        Text(
                          signedIn ? '기록이 계정에 백업돼요' : '로그인하면 기록이 백업돼요',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!signedIn)
                    TextButton(
                      key: const ValueKey('menu-sign-in'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const WelcomeScreen(),
                        ),
                      ),
                      child: const Text('로그인'),
                    ),
                ],
              ),
              const SizedBox(height: SetflowSpacing.section),
              _MenuSection(
                title: '기본 메뉴',
                onCustomize: _editing ? _assignToSlot : null,
                items: [
                  for (final destination in MemberNavigation.defaults)
                    _MenuItem(
                      keyValue: 'menu-${destination.name}',
                      icon: destination.icon,
                      label: destination.label,
                      destination: destination,
                    ),
                ],
              ),
              const SizedBox(height: SetflowSpacing.lg),
              _MenuSection(
                title: '운동',
                onCustomize: _editing ? _assignToSlot : null,
                items: [
                  _MenuItem(
                    keyValue: 'menu-routines',
                    destination: MemberDestination.routines,
                    icon: SetflowIcons.routine,
                    label: '내 루틴',
                    builder: (_) => const RoutinesScreen(),
                  ),
                  _MenuItem(
                    keyValue: 'menu-market',
                    destination: MemberDestination.market,
                    icon: SetflowIcons.market,
                    label: '전문가 루틴',
                    builder: (_) => const MarketScreen(),
                  ),
                  _MenuItem(
                    keyValue: 'menu-library',
                    destination: MemberDestination.library,
                    icon: SetflowIcons.exerciseSearch,
                    label: '운동 찾기',
                    builder: (_) => ExerciseLibraryScreen(date: today),
                  ),
                ],
              ),
              const SizedBox(height: SetflowSpacing.lg),
              _MenuSection(
                title: '데이터',
                onCustomize: _editing ? _assignToSlot : null,
                items: [
                  _MenuItem(
                    keyValue: 'menu-stats',
                    destination: MemberDestination.dashboard,
                    icon: SetflowIcons.stats,
                    label: '대시보드',
                    builder: (_) => const DashboardScreen(),
                  ),
                  _MenuItem(
                    keyValue: 'menu-body',
                    destination: MemberDestination.body,
                    icon: SetflowIcons.goal,
                    label: '체성분',
                    builder: (_) => const BodyCompositionScreen(),
                  ),
                ],
              ),
              const SizedBox(height: SetflowSpacing.lg),
              _MenuSection(
                title: '코칭·센터',
                onCustomize: _editing ? _assignToSlot : null,
                items: [
                  _MenuItem(
                    keyValue: 'menu-coaching',
                    destination: MemberDestination.coaching,
                    icon: SetflowIcons.coaching,
                    label: '코칭',
                    builder: (_) => const CoachingScreen(),
                  ),
                  _MenuItem(
                    keyValue: 'menu-membership',
                    destination: MemberDestination.membership,
                    icon: SetflowIcons.membership,
                    label: '운동 장소',
                    reason: AuthReason.membership,
                    builder: (_) => const MemberMembershipScreen(),
                  ),
                ],
              ),
              const SizedBox(height: SetflowSpacing.lg),
              _MenuSection(
                title: '계정',
                onCustomize: _editing ? _assignToSlot : null,
                items: [
                  _MenuItem(
                    keyValue: 'menu-settings',
                    destination: MemberDestination.settings,
                    icon: SetflowIcons.settings,
                    label: '설정',
                    builder: (_) => const SettingsScreen(),
                  ),
                  // 트레이너 전환은 헤더 세그먼트가 아니라 이 서랍의 타일이다 —
                  // 승인된 계정에게만 보인다(없는 문은 그리지 않는다).
                  if (!_editing && proPortalAvailable(state))
                    _MenuItem(
                      keyValue: 'menu-portal-trainer',
                      icon: SetflowIcons.pro,
                      label: '${proPortalLabel(state)} 화면',
                      onTap: _switchToPro,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _switchToPro(BuildContext context) async {
    final state = AppScope.of(context);
    // 승인 게이트: 로그인만으로는 부족하다 — 관리자 승인이 문의 열쇠다.
    if (!await requireProAccess(context)) return;
    if (!context.mounted) return;
    // 전환은 셸을 통째로 갈아끼운다 — 이 메뉴 라우트가 위에 남으면 새 셸을 덮는다.
    Navigator.of(context).pop();
    await state.switchPortal(AppPortal.trainer);
  }
}

class _MenuItem {
  const _MenuItem({
    required this.keyValue,
    required this.icon,
    required this.label,
    this.reason,
    this.builder,
    this.onTap,
    this.destination,
  });

  final String keyValue;
  final IconData icon;
  final String label;
  final MemberDestination? destination;

  /// Set when the destination cannot work for a guest.
  final AuthReason? reason;
  final WidgetBuilder? builder;
  final Future<void> Function(BuildContext context)? onTap;
}

/// OKX 서랍의 섹션 — 컨테이너 안에 제목과 아이콘 그리드(아이콘 위, 라벨 아래).
///
/// 판은 **테두리·그림자 없는 옅은 톤 하나**다(OKX처럼 면의 밝기 차이로만
/// 층을 낸다). SetflowCard(테두리+그림자)로 쌓았더니 흰 바탕 위에서 설정
/// 카드처럼 무거웠다 — 회색은 램프에서 골라 겹으로 쓴다: 판 n50, 보조 글자
/// muted, 제목·아이콘은 잉크.
class _MenuSection extends StatelessWidget {
  const _MenuSection({
    required this.title,
    required this.items,
    this.onCustomize,
  });

  final String title;
  final List<_MenuItem> items;
  final ValueChanged<MemberDestination>? onCustomize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(SetflowSpacing.xl),
      decoration: BoxDecoration(
        color: context.setflowColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(SetflowRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: SetflowSpacing.xl),
          // 폭만 4열로 고정하고 높이는 내용이 정한다 — 고정 높이 그리드는
          // 시스템 글자 배율에서 어김없이 모자란다(AGENTS.md 8절).
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth =
                  (constraints.maxWidth - SetflowSpacing.sm * 3) / 4;
              return Wrap(
                spacing: SetflowSpacing.sm,
                runSpacing: SetflowSpacing.xl,
                children: [
                  for (final item in items)
                    SizedBox(
                      width: itemWidth,
                      child: _MenuGridItem(
                        item: item,
                        onCustomize: onCustomize,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MenuGridItem extends StatelessWidget {
  const _MenuGridItem({required this.item, this.onCustomize});

  final _MenuItem item;
  final ValueChanged<MemberDestination>? onCustomize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tile = InkWell(
      key: ValueKey(item.keyValue),
      borderRadius: BorderRadius.circular(SetflowRadii.sm),
      onTap: () => onCustomize != null && item.destination != null
          ? onCustomize!(item.destination!)
          : _open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SetflowSpacing.xs),
        child: Column(
          children: [
            Icon(item.icon, size: 26),
            const SizedBox(height: SetflowSpacing.sm),
            Text(
              item.label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
    return item.destination == null
        ? tile
        : MemberNavigationDraggable(
            destination: item.destination!,
            enabled: onCustomize != null,
            child: tile,
          );
  }

  Future<void> _open(BuildContext context) async {
    final custom = item.onTap;
    if (custom != null) {
      await custom(context);
      return;
    }
    final gate = item.reason;
    if (gate != null && !await requireSignIn(context, reason: gate)) return;
    if (!context.mounted) return;
    if (item.builder == null && item.destination != null) {
      Navigator.of(context).pop(item.destination);
      return;
    }
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: item.builder!));
  }
}
