import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/app_repository.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 회원 탈퇴 — 회원과 사업자가 같은 화면, 같은 서버 경로를 쓴다.
///
/// 예전에는 회원 설정의 '회원 탈퇴'가 토스트만 띄우고, 사업자 설정과 빠른
/// 이동에 각각 다른 탈퇴 화면이 또 있었다. 셋 다 아무것도 하지 않았으므로
/// 사용자는 신청된 줄 알고 넘어갔다. 지우는 경로는 하나여야 한다.
///
/// 즉시 삭제가 아니라 30일 유예다(`request_account_deletion`). 그래서 이
/// 화면은 "신청" 말고 **"신청 취소"** 도 할 수 있어야 한다 — 유예가 되돌릴 수
/// 없으면 유예가 아니다.
class AccountDeletionScreen extends StatefulWidget {
  const AccountDeletionScreen({this.role = UserRole.member, super.key});

  /// 사업자는 회원에게 없는 결과(관리 회원 안내·미정산 정산)가 따라온다.
  final UserRole role;

  @override
  State<AccountDeletionScreen> createState() => _AccountDeletionScreenState();
}

class _AccountDeletionScreenState extends State<AccountDeletionScreen> {
  String? _reason;
  bool _agreed = false;
  bool _busy = false;
  bool _loading = true;
  AccountDeletionRequest? _pending;

  bool get _isBusiness =>
      widget.role == UserRole.trainer || widget.role == UserRole.gym;

  bool get _isGym => widget.role == UserRole.gym;

  static const _memberReasons = [
    '앱을 잘 쓰지 않게 됐어요',
    '기록이 원하는 대로 남지 않아요',
    '다른 앱을 쓰기로 했어요',
    '개인정보가 걱정돼요',
    '기타 사유',
  ];

  static const _businessReasons = [
    '운영할 시간이 부족해요',
    '수수료가 너무 높아요',
    '사용 방법이 어려워요',
    '서비스 이용이 불만족스러워요',
    '기타 사유',
  ];

  String get _title => _isGym ? '헬스장 탈퇴' : '회원 탈퇴';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPending());
  }

  Future<void> _loadPending() async {
    final state = AppScope.of(context);
    try {
      final pending = await state.refreshPendingAccountDeletion();
      if (!mounted) return;
      setState(() {
        _pending = pending;
        _loading = false;
      });
    } catch (_) {
      // 조회가 실패해도 신청 자체는 막지 않는다 — 서버가 중복을 걸러낸다.
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: SetflowInsets.pageList,
              children: _pending == null
                  ? _requestForm(context, state)
                  : _pendingBody(context, _pending!),
            ),
    );
  }

  // 유예 중 — 지금 필요한 것은 "며칠 남았나"와 "되돌리기" 둘뿐이다.
  List<Widget> _pendingBody(
    BuildContext context,
    AccountDeletionRequest request,
  ) {
    final daysLeft = request.daysLeft(DateTime.now());
    return [
      _WarningPanel(
        title: '탈퇴 신청이 접수됐어요',
        children: [
          _WarningItem(
            icon: Icons.schedule_rounded,
            title: daysLeft == 0 ? '오늘 처리될 예정이에요' : '$daysLeft일 뒤에 삭제돼요',
            message:
                '${_formatDate(request.purgeAfter)}까지는 아래 버튼으로 되돌릴 수 있어요. '
                '그 뒤에는 복구할 수 없습니다.',
          ),
          if (request.reason != null)
            _WarningItem(
              icon: Icons.edit_note_rounded,
              title: '남겨주신 사유',
              message: request.reason!,
            ),
        ],
      ),
      const SizedBox(height: SetflowSpacing.xl),
      PrimaryButton(
        key: const ValueKey('account-deletion-cancel'),
        label: _busy ? '되돌리는 중…' : '탈퇴 신청 취소',
        onPressed: _busy ? null : _cancel,
      ),
    ];
  }

  List<Widget> _requestForm(BuildContext context, AppState state) {
    final reasons = _isBusiness ? _businessReasons : _memberReasons;
    final canWithdraw = !_busy && _reason != null && _agreed;
    return [
      _WarningPanel(
        title: '잠깐, 탈퇴 전에 확인해 주세요',
        children: [
          const _WarningItem(
            icon: Icons.schedule_rounded,
            title: '30일 유예 기간',
            message: '탈퇴 신청 후 30일 동안은 다시 로그인해서 되돌릴 수 있습니다.',
          ),
          const _WarningItem(
            icon: Icons.fitness_center_rounded,
            title: '운동 기록이 사라져요',
            message: '유예 기간이 끝나면 기록·루틴·통계를 되살릴 수 없습니다.',
          ),
          if (_isBusiness) ...[
            _WarningItem(
              icon: Icons.groups_outlined,
              title: _isGym ? '소속 트레이너 / 회원 안내' : '관리 회원 안내',
              message: '이용 중인 상대방에게 서비스 종료 안내가 발송됩니다.',
            ),
            const _WarningItem(
              icon: Icons.wallet_outlined,
              title: '미정산 수익금 처리',
              message: '탈퇴 신청 후 익월 1일에 등록된 계좌로 일괄 지급됩니다.',
            ),
          ],
        ],
      ),
      const SizedBox(height: SetflowSpacing.xl),
      const Text(
        '탈퇴 사유를 선택해 주세요',
        style: TextStyle(
          fontSize: SetflowFontSize.body,
          fontWeight: SetflowWeight.strong,
        ),
      ),
      const SizedBox(height: SetflowSpacing.sm),
      DropdownButtonFormField<String>(
        key: const ValueKey('account-deletion-reason'),
        initialValue: _reason,
        hint: const Text('탈퇴 사유 선택'),
        items: [
          for (final reason in reasons)
            DropdownMenuItem(value: reason, child: Text(reason)),
        ],
        onChanged: _busy ? null : (value) => setState(() => _reason = value),
      ),
      const SizedBox(height: SetflowSpacing.md2),
      CheckboxListTile(
        key: const ValueKey('account-deletion-agree'),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _agreed,
        onChanged: _busy
            ? null
            : (value) => setState(() => _agreed = value ?? false),
        title: const Text(
          '안내사항을 모두 확인했으며 탈퇴 처리에 동의합니다.',
          style: TextStyle(
            fontSize: SetflowFontSize.label,
            fontWeight: SetflowWeight.medium,
          ),
        ),
      ),
      const SizedBox(height: SetflowSpacing.xl),
      PrimaryButton(
        key: const ValueKey('account-deletion-submit'),
        label: _busy ? '신청하는 중…' : '탈퇴 신청하기',
        onPressed: canWithdraw ? () => _confirm(state) : null,
      ),
    ];
  }

  Future<void> _confirm(AppState state) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('정말 탈퇴하시겠어요?'),
        content: const Text('30일 안에는 다시 로그인해서 되돌릴 수 있어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              '탈퇴 신청',
              style: TextStyle(color: context.setflowColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await state.requestAccountDeletion(reason: _reason);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppSnackbar.error(context, '탈퇴 신청을 보내지 못했어요. 잠시 후 다시 시도해주세요.');
      return;
    }
    if (!mounted) return;
    // 신청이 끝나면 로그아웃한다. 유예 중에도 다시 로그인할 수 있으므로
    // 되돌릴 길은 남아 있고, 계정을 지우기로 한 사람을 계속 로그인 상태로
    // 두지도 않는다.
    final navigator = Navigator.of(context);
    AppSnackbar.success(context, '탈퇴를 신청했어요. 30일 안에 로그인하면 되돌릴 수 있어요.');
    navigator.popUntil((route) => route.isFirst);
    await state.logout();
  }

  Future<void> _cancel() async {
    final state = AppScope.of(context);
    setState(() => _busy = true);
    try {
      final cancelled = await state.cancelAccountDeletion();
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (cancelled) _pending = null;
      });
      AppSnackbar.success(
        context,
        cancelled ? '탈퇴 신청을 취소했어요.' : '되돌릴 탈퇴 신청이 없어요.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppSnackbar.error(context, '지금은 취소하지 못했어요. 잠시 후 다시 시도해주세요.');
    }
  }

  static String _formatDate(DateTime value) =>
      '${value.year}년 ${value.month}월 ${value.day}일';
}

class _WarningPanel extends StatelessWidget {
  const _WarningPanel({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(SetflowSpacing.lg),
      decoration: BoxDecoration(
        color: context.setflowColors.error.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(SetflowRadii.xl),
        border: Border.all(
          color: context.setflowColors.error.withValues(alpha: .2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: SetflowFontSize.title,
              fontWeight: SetflowWeight.strong,
            ),
          ),
          const SizedBox(height: SetflowSpacing.sm2),
          ...children,
        ],
      ),
    );
  }
}

class _WarningItem extends StatelessWidget {
  const _WarningItem({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SetflowSpacing.sm2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: context.setflowColors.error),
          const SizedBox(width: SetflowSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: SetflowFontSize.label,
                    fontWeight: SetflowWeight.strong,
                  ),
                ),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: SetflowFontSize.small,
                    height: 1.45,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
