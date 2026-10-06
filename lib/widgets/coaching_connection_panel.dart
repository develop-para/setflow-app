import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/coaching_management_repository.dart';
import '../screens/coaching_management_screen.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../theme/icons.dart';
import 'coaching_invite_accept_sheet.dart';
import 'common.dart';

/// Existing PT members start with their trainer, rather than a new consultation.
class CoachingConnectionPanel extends StatefulWidget {
  const CoachingConnectionPanel({required this.onOpenSchedule, super.key});

  final VoidCallback onOpenSchedule;

  @override
  State<CoachingConnectionPanel> createState() =>
      _CoachingConnectionPanelState();
}

class _CoachingConnectionPanelState extends State<CoachingConnectionPanel>
    with WidgetsBindingObserver {
  String? _actor;
  UserRole? _role;
  int _generation = 0;
  int _receivedRequests = 0;
  bool _requestsFailed = false;

  String? _currentActor(AppState state) =>
      Auth.instance.currentUser?.id ?? state.businessAccess?.userId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    final actor = _currentActor(state);
    if (_actor == actor && _role == state.role) return;
    _actor = actor;
    _role = state.role;
    _generation++;
    _receivedRequests = 0;
    _requestsFailed = false;
    if (actor != null && state.role == UserRole.member) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _actor == actor && _role == UserRole.member) _refresh();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _actor != null) _refresh();
  }

  Future<void> _refresh() async {
    final state = AppScope.of(context);
    if (_actor == null || state.role != UserRole.member) return;
    final actor = _actor;
    final generation = ++_generation;
    await Future.wait([
      state.refreshMemberCoachingConnections().catchError((Object _) {}),
      () async {
        final repository = state.businessRepository;
        if (repository is! CoachingManagementRepository) return;
        try {
          final links = await (repository as CoachingManagementRepository)
              .listManagementLinks()
              .timeout(const Duration(seconds: 15));
          if (!mounted ||
              generation != _generation ||
              actor != _currentActor(state) ||
              state.role != UserRole.member) {
            return;
          }
          setState(() {
            _receivedRequests = links
                .where((link) => link.status == 'pending' && link.canRespond)
                .length;
            _requestsFailed = false;
          });
        } catch (_) {
          if (mounted &&
              generation == _generation &&
              actor == _currentActor(state) &&
              state.role == UserRole.member) {
            setState(() => _requestsFailed = true);
          }
        }
      }(),
    ]);
  }

  Future<void> _connect() async {
    final accepted = await showCoachingInviteAcceptance(context);
    if (accepted == true && mounted) await _refresh();
  }

  Future<void> _manage() async {
    await openCoachingManagement(context);
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final signedIn = _actor != null && state.role == UserRole.member;
    final connections = signedIn
        ? state.coachingConnections.where((item) => item.isActive).toList()
        : const [];
    final theme = Theme.of(context);
    final loading = signedIn && state.memberCoachingConnectionsLoading;
    final failed = signedIn && state.memberCoachingConnectionsError != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          '내 트레이너',
          action: signedIn ? '새로고침' : null,
          onAction: signedIn ? _refresh : null,
        ),
        const SizedBox(height: SetflowSpacing.sm),
        if (_receivedRequests > 0) ...[
          SetflowCard(
            key: const ValueKey('coaching-received-requests'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '운동 기록 공유 요청 $_receivedRequests건',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: SetflowSpacing.xs),
                const Text('트레이너와 공유할 내용을 확인하고 수락하거나 거절하세요.'),
                const SizedBox(height: SetflowSpacing.sm),
                FilledButton(onPressed: _manage, child: const Text('받은 요청 확인')),
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.md),
        ],
        if (loading && connections.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: SetflowSpacing.md),
            child: Text('연결된 트레이너를 확인하고 있어요.'),
          )
        else if (failed) ...[
          Text(
            connections.isEmpty
                ? '연결 상태를 확인하지 못했어요.'
                : '최신 연결 상태를 확인하지 못했어요. 이전에 확인한 연결을 표시합니다.',
          ),
          TextButton(
            key: const ValueKey('coaching-connections-retry'),
            onPressed: loading ? null : _refresh,
            child: const Text('다시 확인'),
          ),
        ] else if (connections.isEmpty)
          const Text('담당 트레이너에게 초대 링크를 받아 연결하세요. 새로운 상담 없이 바로 시작할 수 있어요.'),
        for (final connection in connections) ...[
          SetflowCard(
            key: ValueKey('member-coaching-connection-${connection.id}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connection.trainerName,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: SetflowSpacing.xs),
                Text(
                  '수업 연결됨',
                  style: TextStyle(color: context.setflowColors.success),
                ),
                if (connection.programName?.isNotEmpty ?? false)
                  Text(connection.programName!),
                Text('수업 기록 ${connection.sessionCount}회'),
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.sm),
        ],
        const SizedBox(height: SetflowSpacing.md),
        if (connections.isNotEmpty) ...[
          FilledButton.icon(
            key: const ValueKey('coaching-connected-schedules'),
            onPressed: widget.onOpenSchedule,
            icon: const Icon(SetflowIcons.calendar),
            label: const Text('수업 일정 보기'),
          ),
          const SizedBox(height: SetflowSpacing.sm),
          OutlinedButton.icon(
            key: const ValueKey('coaching-connect-trainer'),
            onPressed: _connect,
            icon: const Icon(SetflowIcons.signIn),
            label: const Text('트레이너 추가 연결'),
          ),
        ] else
          FilledButton.icon(
            key: const ValueKey('coaching-connect-trainer'),
            onPressed: _connect,
            icon: const Icon(SetflowIcons.signIn),
            label: const Text('트레이너 초대 링크 입력'),
          ),
        const SizedBox(height: SetflowSpacing.md),
        ListTile(
          key: const ValueKey('coaching-record-sharing'),
          contentPadding: EdgeInsets.zero,
          title: const Text('운동 기록 공유·요청 확인'),
          subtitle: Text(
            _requestsFailed
                ? '요청을 확인하지 못했어요. 눌러서 다시 확인하세요.'
                : '전체 운동 기록은 별도로 동의한 뒤 공유해요.',
          ),
          trailing: const Icon(SetflowIcons.forward),
          onTap: _manage,
        ),
      ],
    );
  }
}
