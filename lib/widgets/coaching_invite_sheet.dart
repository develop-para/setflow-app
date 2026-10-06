import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../data/business_repository.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../theme/icons.dart';
import 'common.dart';
import 'pro_access_gate.dart';

/// 한 회원이 수락할 수 있는 초대. 링크 발급·전달과 연결 완료는 구분한다.
Future<void> showCoachingInviteSheet(BuildContext context) async {
  if (!await requireProAccess(context) || !context.mounted) return;
  final state = AppScope.of(context);
  final access = state.businessAccess;
  final profile = state.businessWorkspace?.profile;
  if (state.role != UserRole.trainer ||
      access?.canUse(UserRole.trainer) != true ||
      profile is! TrainerBusinessProfile) {
    return;
  }
  await showSetflowSheet<void>(
    context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        _CoachingInviteSheet(accountId: access!.userId, trainerId: profile.id),
  );
}

class _CoachingInviteSheet extends StatefulWidget {
  const _CoachingInviteSheet({
    required this.accountId,
    required this.trainerId,
  });
  final String accountId;
  final String trainerId;

  @override
  State<_CoachingInviteSheet> createState() => _CoachingInviteSheetState();
}

class _CoachingInviteSheetState extends State<_CoachingInviteSheet> {
  final _name = TextEditingController();
  AppState? _state;
  StreamSubscription<AuthChange>? _authSubscription;
  CoachingConnectionInviteCreation? _creation;
  bool _creating = false;
  bool _sending = false;
  bool _refreshing = false;
  bool _expired = false;

  bool get _busy => _creating || _sending || _refreshing;

  bool get _sameAccount {
    final state = _state;
    final profile = state?.businessWorkspace?.profile;
    return Auth.instance.hasAuthenticatedUser &&
        Auth.instance.currentUser?.id == widget.accountId &&
        state?.businessAccess?.userId == widget.accountId &&
        state?.businessAccess?.canUse(UserRole.trainer) == true &&
        state?.role == UserRole.trainer &&
        profile is TrainerBusinessProfile &&
        profile.id == widget.trainerId;
  }

  bool get _current => mounted && !_expired && _sameAccount;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _state = AppScope.of(context);
    _authSubscription ??= Auth.instance.authChanges.listen((change) {
      if (change.event == AuthEvent.signedOut ||
          change.user?.id != widget.accountId ||
          !_sameAccount) {
        if (!mounted || _expired) return;
        setState(() {
          _expired = true;
          _creation = null;
        });
      }
    });
    if (!_sameAccount) {
      // 계정·역할이 바뀐 뒤 돌아와도 예전 링크를 다시 드러내지 않는다.
      _expired = true;
      _creation = null;
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy || !_current) return;
    setState(() => _creating = true);
    try {
      final result = await _state!.createCoachingConnectionInvite(
        recipientName: _name.text,
      );
      if (_current) setState(() => _creation = result);
    } catch (_) {
      if (mounted && _current) {
        AppSnackbar.error(context, '연결 링크를 만들지 못했어요. 같은 회원으로 다시 시도해주세요.');
      }
    } finally {
      if (_current) setState(() => _creating = false);
    }
  }

  Future<void> _copy() async {
    final uri = _creation?.uri;
    if (_busy || !_current || uri == null) return;
    setState(() => _sending = true);
    try {
      await Clipboard.setData(ClipboardData(text: uri.toString()));
      if (mounted && _current) {
        AppSnackbar.success(context, '초대 링크를 복사했어요. 회원에게 보내주세요.');
      }
    } catch (_) {
      if (mounted && _current) {
        AppSnackbar.error(context, '링크를 복사하지 못했어요. 다시 시도해주세요.');
      }
    } finally {
      if (_current) setState(() => _sending = false);
    }
  }

  Future<void> _share(BuildContext buttonContext) async {
    final uri = _creation?.uri;
    if (_busy || !_current || uri == null) return;
    final box = buttonContext.findRenderObject() as RenderBox?;
    setState(() => _sending = true);
    try {
      await Share.share(
        '셋플로우에서 담당 트레이너와 연결해 주세요.\n'
        '셋플로우 앱에서 마이 → 코칭 → 트레이너 초대 링크 입력을 누르고 아래 링크를 붙여넣어 주세요.\n'
        '$uri\n'
        '링크는 7일 동안 한 회원만 수락할 수 있어요.',
        subject: '셋플로우 · 트레이너 연결 초대',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      );
      // 운영체제 공유창의 결과는 회원이 연결을 수락했다는 증거가 아니다.
    } catch (_) {
      if (mounted && _current) {
        AppSnackbar.error(context, '공유창을 열지 못했어요. 링크를 복사해 보내주세요.');
      }
    } finally {
      if (_current) setState(() => _sending = false);
    }
  }

  Future<void> _refresh() async {
    if (_busy || !_current) return;
    setState(() => _refreshing = true);
    try {
      await _state!.refreshBusinessDashboard(UserRole.trainer);
      if (mounted && _current) Navigator.of(context).pop();
    } catch (_) {
      if (mounted && _current) {
        AppSnackbar.error(context, '회원 목록을 확인하지 못했어요. 다시 확인해주세요.');
      }
    } finally {
      if (_current) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: SetflowInsets.pageForm.add(
        EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('회원 연결', style: theme.textTheme.headlineMedium),
          const SizedBox(height: SetflowSpacing.sm),
          if (_expired) ...[
            const Text('계정이나 역할이 바뀌어 초대 링크를 닫았어요. 현재 계정의 회원 화면에서 다시 열어주세요.'),
            const SizedBox(height: SetflowSpacing.md),
            OutlinedButton(
              key: const Key('coaching-invite-account-expired'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('닫기'),
            ),
          ] else ...[
            const Text('이미 PT 중인 회원에게 링크를 보내세요. 회원이 수락하면 내 회원 목록에 연결돼요.'),
            const SizedBox(height: SetflowSpacing.md),
            Text(
              '링크 만들기 → 회원에게 보내기 → 회원 수락',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SetflowSpacing.md),
            const Text('초대 링크는 7일 동안 한 회원만 수락할 수 있어요. 회원마다 새 링크를 보내주세요.'),
            const SizedBox(height: SetflowSpacing.lg),
            if (_creation == null) ...[
              AppTextField(
                key: const Key('coaching-invite-name'),
                controller: _name,
                enabled: !_busy,
                label: '회원 이름 (선택)',
                hint: '어떤 회원에게 보낼 링크인지 구분해요',
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: SetflowSpacing.md),
              PrimaryButton(
                key: const Key('coaching-invite-create'),
                label: _creating ? '링크 만드는 중...' : '7일 초대 링크 만들기',
                onPressed: _busy ? null : _create,
              ),
            ] else ...[
              Text('링크를 만들었어요', style: theme.textTheme.titleMedium),
              const SizedBox(height: SetflowSpacing.sm),
              const Text('공유만으로 연결되지는 않아요. 회원이 수락하면 목록에서 확인할 수 있어요.'),
              const SizedBox(height: SetflowSpacing.md),
              if (_creation!.uri case final uri?) ...[
                SelectableText(uri.toString()),
                const SizedBox(height: SetflowSpacing.lg),
                Builder(
                  builder: (buttonContext) => PrimaryButton(
                    key: const Key('coaching-invite-share'),
                    label: '회원에게 공유',
                    icon: SetflowIcons.shareInvite,
                    onPressed: _busy ? null : () => _share(buttonContext),
                  ),
                ),
                const SizedBox(height: SetflowSpacing.sm),
                OutlinedButton.icon(
                  key: const Key('coaching-invite-copy'),
                  onPressed: _busy ? null : _copy,
                  icon: const Icon(SetflowIcons.copyCode),
                  label: const Text('초대 링크 복사'),
                ),
                const SizedBox(height: SetflowSpacing.sm),
                TextButton(
                  key: const Key('coaching-invite-refresh-members'),
                  onPressed: _busy ? null : _refresh,
                  child: Text(_refreshing ? '목록 확인 중...' : '회원이 수락했나요? 목록 확인'),
                ),
              ] else
                const Text(
                  '이 요청의 링크는 이미 발급됐어요. 이전에 복사한 링크를 사용하거나 새 링크를 만들어주세요.',
                ),
              OutlinedButton(
                key: const Key('coaching-invite-next-member'),
                onPressed: _busy
                    ? null
                    : () {
                        _name.clear();
                        setState(() => _creation = null);
                      },
                child: const Text('다른 회원 초대'),
              ),
            ],
            const SizedBox(height: SetflowSpacing.lg),
            Text(
              '센터 소속과 무관하게 연결해요. 전체 운동 기록 조회·수정은 별도의 동의가 필요해요.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
