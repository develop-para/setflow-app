import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/business_repository.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../theme/icons.dart';

/// A choice of granted workspaces, never a way to create or grant a role.
class WorkspaceSelectionScreen extends StatelessWidget {
  const WorkspaceSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final error =
        state.workspaceEntryError ??
        (state.businessAccess == null
            ? state.businessError ?? state.persistenceError
            : null);
    final waiting = state.businessAccess == null && error == null;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('시작할 화면'),
        actions: [
          TextButton(
            onPressed: state.workspaceEntryLoading ? null : state.logout,
            child: const Text('로그아웃'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: SetflowInsets.pageForm,
          children: [
            Text(
              '${Auth.instance.currentDisplayName}님, 반가워요',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: SetflowSpacing.sm),
            Text(
              '오늘 사용할 화면을 선택해주세요.\n이용 중에도 메뉴에서 바꿀 수 있어요.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SetflowSpacing.xxl),
            if (waiting || state.workspaceEntryLoading) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: SetflowSpacing.md),
              const Text('이용 권한을 확인하고 있어요.'),
              const SizedBox(height: SetflowSpacing.lg),
            ],
            if (error != null) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  switch (error) {
                    AuthFailure() => error.message,
                    BusinessAccessDenied() => error.message,
                    _ => '이용 권한을 확인하지 못했어요. 연결을 확인하고 다시 시도해주세요.',
                  },
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: context.setflowColors.error,
                  ),
                ),
              ),
              const SizedBox(height: SetflowSpacing.md),
              OutlinedButton(
                key: const ValueKey('workspace-retry'),
                onPressed: state.workspaceEntryLoading
                    ? null
                    : state.refreshBusinessAccess,
                child: const Text('다시 확인'),
              ),
              const SizedBox(height: SetflowSpacing.lg),
            ],
            for (final role in state.availableWorkspaceRoles) ...[
              _WorkspaceCard(role: role, enabled: !state.workspaceEntryLoading),
              const SizedBox(height: SetflowSpacing.md),
            ],
            if (state.businessAccess == null)
              TextButton(
                key: const ValueKey('workspace-personal'),
                onPressed: state.workspaceEntryLoading
                    ? null
                    : state.continueWithPersonalWorkspace,
                child: const Text('개인 운동 기록으로 계속'),
              ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({required this.role, required this.enabled});

  final UserRole role;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, description, icon) = switch (role) {
      UserRole.trainer => ('트레이너', '회원 코칭과 수업을 관리해요', SetflowIcons.pro),
      UserRole.gym => ('사업장', '사업장과 소속 회원을 관리해요', SetflowIcons.gym),
      UserRole.admin => ('운영 관리자', '신청 심사와 운영을 관리해요', SetflowIcons.settings),
      _ => ('회원', '내 운동과 루틴을 기록해요', SetflowIcons.my),
    };
    return OutlinedButton(
      key: ValueKey('workspace-${role.name}'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(SetflowSpacing.lg),
        foregroundColor: theme.colorScheme.onSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SetflowRadii.lg),
        ),
      ),
      onPressed: enabled
          ? () => AppScope.of(context).enterWorkspace(role)
          : null,
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: SetflowSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: SetflowSpacing.xs),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: SetflowSpacing.sm),
          const Icon(SetflowIcons.forward),
        ],
      ),
    );
  }
}
