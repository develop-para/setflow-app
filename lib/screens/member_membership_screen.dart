import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/business_repository.dart';
import '../domain/gym_directory.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/common.dart';
import '../widgets/auth_gate.dart';
import 'coaching_management_screen.dart';
import 'gym_directory_screen.dart';

class MemberMembershipScreen extends StatelessWidget {
  const MemberMembershipScreen({super.key});

  Future<void> _addLocation(BuildContext context) async {
    if (!await requireSignIn(context, reason: AuthReason.membership)) return;
    if (!context.mounted) return;
    final state = AppScope.of(context);
    List<GymDirectoryEntry> gyms;
    try {
      gyms = await state.loadVerifiedGyms();
    } catch (_) {
      if (context.mounted) {
        AppSnackbar.error(context, '헬스장 목록을 불러오지 못했어요.');
      }
      return;
    }
    if (!context.mounted) return;
    final savedGymIds = state.workoutLocations
        .map((location) => location.gymId)
        .toSet();
    final available = gyms
        .where((gym) => !savedGymIds.contains(gym.id))
        .toList(growable: false);
    final selected = await showSetflowSheet<GymDirectoryEntry>(
      context,
      isScrollControlled: true,
      builder: (_) => _GymPickerSheet(gyms: available),
    );
    if (selected == null || !context.mounted) return;
    try {
      await state.saveWorkoutLocation(selected.id);
      if (context.mounted) {
        AppSnackbar.success(context, '${selected.name}을 현재 운동 장소로 추가했어요.');
      }
    } catch (_) {
      if (context.mounted) {
        AppSnackbar.error(context, '운동 장소를 추가하지 못했어요.');
      }
    }
  }

  Future<void> _selectLocation(
    BuildContext context,
    MemberWorkoutLocation location,
  ) async {
    if (location.isActive && AppScope.of(context).currentPublicGym == null) {
      return;
    }
    if (!await requireSignIn(context, reason: AuthReason.membership)) return;
    if (!context.mounted) return;
    try {
      await AppScope.of(context).selectWorkoutLocation(location.id);
    } catch (_) {
      if (context.mounted) {
        AppSnackbar.error(context, '현재 운동 장소를 변경하지 못했어요.');
      }
    }
  }

  Future<void> _removeLocation(
    BuildContext context,
    MemberWorkoutLocation location,
  ) async {
    if (!await requireSignIn(context, reason: AuthReason.membership)) return;
    if (!context.mounted) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('운동 장소에서 삭제할까요?'),
            content: Text(
              '${location.gymName}을 개인 운동 장소 목록에서 삭제합니다. '
              '센터와 연결된 회원 관계에는 영향을 주지 않습니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('삭제'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    try {
      await AppScope.of(context).removeWorkoutLocation(location.id);
    } catch (_) {
      if (context.mounted) {
        AppSnackbar.error(context, '운동 장소를 삭제하지 못했어요.');
      }
    }
  }

  Future<void> _refresh(BuildContext context) async {
    final state = AppScope.of(context);
    try {
      await state.loadGymPlaces();
      if (Auth.instance.hasAuthenticatedUser) {
        await state.refreshWorkoutLocations();
      }
    } catch (_) {
      if (context.mounted) AppSnackbar.error(context, '장소 정보를 다시 불러오지 못했어요.');
    }
  }

  Future<void> _changePublicPlace(BuildContext context, GymPlace gym) async {
    try {
      await AppScope.of(context).selectPublicGymPlace(gym.id);
    } catch (_) {
      if (context.mounted) AppSnackbar.error(context, '운동 장소를 변경하지 못했어요.');
    }
  }

  Future<void> _removePublicPlace(BuildContext context, GymPlace gym) async {
    try {
      await AppScope.of(context).removePublicGymPlace(gym.id);
    } catch (_) {
      if (context.mounted) AppSnackbar.error(context, '저장한 장소를 삭제하지 못했어요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final memberships = state.memberMemberships;
    final locations = state.workoutLocations;
    return Scaffold(
      appBar: AppBar(title: const Text('운동 장소 및 센터')),
      body: RefreshIndicator(
        onRefresh: () => _refresh(context),
        child: ListView(
          padding: SetflowInsets.pageList,
          children: [
            SectionTitle(
              '나의 운동 장소',
              action: '헬스장 찾기',
              onAction: () => Navigator.of(context).push<GymPlace>(
                MaterialPageRoute(builder: (_) => const GymDirectoryScreen()),
              ),
            ),
            const SizedBox(height: SetflowSpacing.xs),
            Text(
              '헬스장을 검색해 이 기기에 저장하면 홈의 운동 장소가 유지돼요.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SetflowSpacing.md),
            if (state.gymPlacesError != null)
              ErrorState(
                message: '저장한 헬스장을 불러오지 못했어요.',
                onRetry: state.loadGymPlaces,
              )
            else if (state.gymPlaceLibrary.gyms.isEmpty)
              SetflowCard(
                key: const ValueKey('public-workout-places-empty'),
                onTap: () => Navigator.of(context).push<GymPlace>(
                  MaterialPageRoute(builder: (_) => const GymDirectoryScreen()),
                ),
                child: const Row(
                  children: [
                    Icon(SetflowIcons.location),
                    SizedBox(width: SetflowSpacing.md),
                    Expanded(child: Text('다니는 헬스장을 찾아 저장해보세요.')),
                    Icon(SetflowIcons.forward),
                  ],
                ),
              )
            else
              for (final gym in state.gymPlaceLibrary.gyms) ...[
                SetflowCard(
                  key: ValueKey('public-workout-place-${gym.id}'),
                  onTap: () => _changePublicPlace(context, gym),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            state.currentPublicGym?.id == gym.id
                                ? SetflowIcons.locationActive
                                : SetflowIcons.location,
                          ),
                          const SizedBox(width: SetflowSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  gym.name,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: SetflowSpacing.xxs),
                                Text(
                                  gym.address,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (state.currentPublicGym?.id == gym.id) ...[
                                  const SizedBox(height: SetflowSpacing.xs),
                                  Text(
                                    '현재 운동 장소',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.secondary,
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: '저장한 헬스장 삭제',
                            onPressed: () => _removePublicPlace(context, gym),
                            icon: const Icon(SetflowIcons.delete),
                          ),
                        ],
                      ),
                      const SizedBox(height: SetflowSpacing.xs),
                      TextButton(
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => GymPlaceDetailScreen(gym: gym),
                          ),
                        ),
                        child: const Text('헬스장 정보 · 정정 제안'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: SetflowSpacing.md),
              ],
            ListTile(
              key: const ValueKey('saved-gym-directory-requests'),
              contentPadding: EdgeInsets.zero,
              title: const Text('내 헬스장 제안'),
              subtitle: const Text('목록 추가 · 정보 정정 · 사업주 확인'),
              trailing: const Icon(SetflowIcons.forward),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => const GymDirectoryRequestsScreen(),
                ),
              ),
            ),
            const SizedBox(height: SetflowSpacing.xl),
            if (managementRepository(context) != null) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('트레이너 연결과 기록 승인'),
                subtitle: const Text('담당 트레이너 · 기록 수정 요청 · 업장 공유'),
                trailing: const Icon(SetflowIcons.forward),
                onTap: () => openCoachingManagement(context),
              ),
              const SizedBox(height: SetflowSpacing.md),
            ],
            SectionTitle(
              '인증 센터 운동 장소',
              action: '추가',
              onAction: () => _addLocation(context),
            ),
            const SizedBox(height: SetflowSpacing.xs),
            Text(
              '여러 헬스장을 저장하고 홈에서 오늘 운동할 장소를 바꿀 수 있어요.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SetflowSpacing.md),
            if (state.workoutLocationsError != null && locations.isEmpty)
              ErrorState(
                message: '운동 장소를 불러오지 못했어요.',
                onRetry: state.refreshWorkoutLocations,
              )
            else if (locations.isEmpty)
              SetflowCard(
                key: const ValueKey('workout-locations-empty'),
                onTap: () => _addLocation(context),
                child: const Row(
                  children: [
                    Icon(SetflowIcons.location),
                    SizedBox(width: SetflowSpacing.md),
                    Expanded(child: Text('다니는 헬스장을 추가해보세요.')),
                    Icon(SetflowIcons.forward),
                  ],
                ),
              )
            else
              for (final location in locations) ...[
                SetflowCard(
                  key: ValueKey('workout-location-${location.id}'),
                  onTap: () => _selectLocation(context, location),
                  child: Row(
                    children: [
                      Icon(
                        location.isActive
                            ? SetflowIcons.locationActive
                            : SetflowIcons.location,
                      ),
                      const SizedBox(width: SetflowSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              location.gymName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (location.gymAddress != null) ...[
                              const SizedBox(height: SetflowSpacing.xxs),
                              Text(
                                location.gymAddress!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                            if (location.isActive &&
                                state.currentPublicGym == null) ...[
                              const SizedBox(height: SetflowSpacing.xs),
                              Text(
                                '현재 운동 장소',
                                // 라임 글자는 흰 배경에서 사라진다 — 읽는
                                // 브랜드(secondary)로.
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.secondary,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '운동 장소 삭제',
                        onPressed: () => _removeLocation(context, location),
                        icon: const Icon(SetflowIcons.delete),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: SetflowSpacing.md),
              ],
            const SizedBox(height: SetflowSpacing.xl),
            const SectionTitle('연결 센터'),
            const SizedBox(height: SetflowSpacing.xs),
            Text(
              '센터가 승인한 연결입니다. 개인 운동 장소와 달리 담당 트레이너와 기록을 공유할 수 있어요.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SetflowSpacing.md),
            if (state.memberMembershipsError != null)
              ErrorState(
                message: '센터 연결 정보를 불러오지 못했어요.',
                onRetry: () => state.refreshBusinessDashboard(UserRole.member),
              )
            else if (memberships.isEmpty)
              const SetflowCard(
                child: Row(
                  children: [
                    Icon(SetflowIcons.gym),
                    SizedBox(width: SetflowSpacing.md),
                    Expanded(child: Text('연결된 센터가 없어요')),
                  ],
                ),
              )
            else
              for (final membership in memberships) ...[
                _MembershipCard(membership: membership),
                const SizedBox(height: SetflowSpacing.md),
              ],
          ],
        ),
      ),
    );
  }
}

class _MembershipCard extends StatelessWidget {
  const _MembershipCard({required this.membership});

  final BusinessMember membership;

  Future<void> _endMembership(BuildContext context) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('센터 연결을 종료할까요?'),
            content: const Text('담당 트레이너 배정과 센터의 운동·체성분 기록 접근 권한이 즉시 종료됩니다.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('연결 종료'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    try {
      await AppScope.of(context).endBusinessMembership(membership.id);
      if (context.mounted) {
        AppSnackbar.success(context, '센터 연결을 종료했어요.');
      }
    } catch (_) {
      if (context.mounted) {
        AppSnackbar.error(context, '센터 연결을 종료하지 못했어요.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ending = AppScope.of(
      context,
    ).isEndingBusinessMembership(membership.id);
    return SetflowCard(
      key: ValueKey('member-membership-${membership.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(SetflowIcons.gym),
              const SizedBox(width: SetflowSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      membership.gymName ?? '연결 센터',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: SetflowSpacing.xxs),
                    Text(
                      '운동 기록 공유 및 담당 트레이너 연결 중',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: ValueKey('member-end-membership-${membership.id}'),
              onPressed: ending ? null : () => _endMembership(context),
              icon: ending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(SetflowIcons.membership),
              label: Text(ending ? '종료 중...' : '센터 연결 종료'),
            ),
          ),
        ],
      ),
    );
  }
}

class _GymPickerSheet extends StatefulWidget {
  const _GymPickerSheet({required this.gyms});

  final List<GymDirectoryEntry> gyms;

  @override
  State<_GymPickerSheet> createState() => _GymPickerSheetState();
}

class _GymPickerSheetState extends State<_GymPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalized = _query.trim().toLowerCase();
    final gyms = widget.gyms
        .where(
          (gym) =>
              normalized.isEmpty ||
              gym.name.toLowerCase().contains(normalized) ||
              (gym.address?.toLowerCase().contains(normalized) ?? false),
        )
        .toList(growable: false);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .72,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SetflowSpacing.gutter,
          0,
          SetflowSpacing.gutter,
          SetflowSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('헬스장 추가', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: SetflowSpacing.md),
            TextField(
              key: const ValueKey('gym-directory-search'),
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: '이름 또는 주소 검색',
                prefixIcon: Icon(SetflowIcons.exerciseSearch),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: SetflowSpacing.md),
            Expanded(
              child: gyms.isEmpty
                  ? const EmptyState(
                      icon: SetflowIcons.gym,
                      title: '추가할 헬스장이 없어요',
                      message: '이미 모두 추가했거나 검색 결과가 없습니다.',
                    )
                  : ListView.separated(
                      itemCount: gyms.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (_, index) {
                        final gym = gyms[index];
                        return ListTile(
                          key: ValueKey('gym-directory-${gym.id}'),
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(SetflowIcons.gym),
                          title: Text(gym.name),
                          subtitle: gym.address == null
                              ? null
                              : Text(
                                  gym.address!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          trailing: const Icon(SetflowIcons.forward),
                          onTap: () => Navigator.pop(context, gym),
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
