import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../domain/coaching_invite.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../theme/icons.dart';
import 'auth_gate.dart';
import 'common.dart';

Future<bool?> showCoachingInviteAcceptance(
  BuildContext context, {
  String? initialInput,
}) => showSetflowSheet<bool>(
  context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _CoachingInviteAcceptSheet(initialInput: initialInput),
);

class _CoachingInviteAcceptSheet extends StatefulWidget {
  const _CoachingInviteAcceptSheet({this.initialInput});
  final String? initialInput;

  @override
  State<_CoachingInviteAcceptSheet> createState() =>
      _CoachingInviteAcceptSheetState();
}

class _CoachingInviteAcceptSheetState
    extends State<_CoachingInviteAcceptSheet> {
  late final TextEditingController _controller;
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  bool _expired = false;
  String? _error;
  String? _submittedActor;
  UserRole? _submittedRole;
  VoidCallback? _releaseAcceptance;

  String? _actor(AppState state) =>
      Auth.instance.currentUser?.id ?? state.businessAccess?.userId;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialInput ?? '');
  }

  @override
  void dispose() {
    final release = _releaseAcceptance;
    if (release != null) scheduleMicrotask(release);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    if (_submittedActor != null &&
        (_actor(state) != _submittedActor || state.role != _submittedRole)) {
      _expired = true;
      _error = '계정이 바뀌었어요. 현재 계정의 코칭에서 다시 연결해 주세요.';
    }
  }

  Future<void> _paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted || _busy || _expired) return;
      if (data?.text?.trim().isNotEmpty ?? false) {
        setState(() {
          _controller.text = data!.text!.trim();
          _error = null;
        });
      } else {
        setState(() => _error = '복사한 링크가 없어요. 트레이너에게 받은 링크를 복사해 주세요.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = '붙여넣지 못했어요. 입력란에 직접 붙여넣어 주세요.');
    }
  }

  Future<void> _accept() async {
    if (_busy || _expired || !_form.currentState!.validate()) return;
    final invite = CoachingInvite.parse(_controller.text)!;
    setState(() {
      _busy = true;
      _error = null;
    });
    final state = AppScope.of(context);
    final release = state.beginCoachingInviteAcceptance();
    _releaseAcceptance = release;
    try {
      if (!await requireSignIn(context, reason: AuthReason.trainerConnection)) {
        return;
      }
      if (!mounted) return;
      if (!await state.waitForAuthenticationReady()) {
        if (mounted) {
          setState(() => _error = '로그인 상태가 바뀌었어요. 현재 계정에서 다시 시도해 주세요.');
        }
        return;
      }
      if (!mounted) return;
      final actor = _actor(state);
      final role = state.role;
      if (actor == null) {
        setState(() => _error = '로그인 상태를 확인하지 못했어요. 다시 시도해 주세요.');
        return;
      }
      _submittedActor = actor;
      _submittedRole = role;
      final result = await state.acceptCoachingConnectionInviteToken(
        invite.token,
      );
      if (!mounted) return;
      if (_expired || actor != _actor(state) || role != state.role) {
        setState(() {
          _expired = true;
          _error = '계정이 바뀌었어요. 현재 계정의 코칭에서 다시 연결해 주세요.';
        });
        return;
      }
      if (result.accepted) {
        AppSnackbar.success(context, '트레이너와 연결됐어요. 코칭에서 수업을 확인하세요.');
        Navigator.of(context).pop(true);
      } else {
        setState(() => _error = '만료되었거나 사용할 수 없는 초대예요. 트레이너에게 새 링크를 받아 주세요.');
      }
    } catch (_) {
      if (mounted && !_expired) {
        setState(
          () => _error =
              '연결하지 못했어요. 링크와 로그인 상태를 확인하고 다시 시도해 주세요. 계속 실패하면 트레이너에게 새 링크를 받아 주세요.',
        );
      }
    } finally {
      release();
      if (identical(_releaseAcceptance, release)) _releaseAcceptance = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: SetflowInsets.pageForm.add(
        EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      ),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('트레이너와 연결', style: theme.textTheme.titleLarge),
            const SizedBox(height: SetflowSpacing.sm),
            const Text('담당 트레이너에게 받은 초대 링크를 붙여넣어 주세요. 새 상담을 신청할 필요는 없어요.'),
            const SizedBox(height: SetflowSpacing.lg),
            TextFormField(
              key: const ValueKey('coaching-invite-input'),
              controller: _controller,
              enabled: !_busy && !_expired,
              minLines: 2,
              maxLines: 3,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: '트레이너 초대 링크',
                hintText: '받은 링크 또는 초대 코드를 입력하세요',
              ),
              validator: (value) => CoachingInvite.parse(value ?? '') == null
                  ? '올바른 트레이너 초대 링크를 입력해 주세요.'
                  : null,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('coaching-invite-paste'),
                onPressed: _busy || _expired ? null : _paste,
                icon: const Icon(SetflowIcons.copyCode),
                label: const Text('복사한 링크 붙여넣기'),
              ),
            ),
            const SizedBox(height: SetflowSpacing.md),
            const Text(
              '연결하면 트레이너가 수업 일정을 만들 수 있어요. 수업한 헬스장에는 해당 수업 기록만 공유됩니다.',
            ),
            const SizedBox(height: SetflowSpacing.sm),
            Text(
              '전체 개인 운동 기록의 조회·수정 권한은 별도의 운동 기록 공유 동의가 있어야 열려요.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: SetflowSpacing.md),
              Text(
                _error!,
                key: const ValueKey('coaching-invite-error'),
                style: TextStyle(color: context.setflowColors.error),
              ),
            ],
            const SizedBox(height: SetflowSpacing.lg),
            FilledButton(
              key: const ValueKey('coaching-invite-confirm'),
              onPressed: _busy || _expired ? null : _accept,
              child: Text(_busy ? '연결 중…' : '동의하고 연결'),
            ),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: const Text('나중에 하기'),
            ),
          ],
        ),
      ),
    );
  }
}
