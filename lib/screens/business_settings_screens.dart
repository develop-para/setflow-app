import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 사업자(트레이너/헬스장) 설정 목록 화면.
class BusinessSettingsListScreen extends StatelessWidget {
  const BusinessSettingsListScreen({required this.role, super.key});
  final UserRole role;

  bool get _isGym => role == UserRole.gym;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          SetflowSpacing.xxl,
          SetflowSpacing.xs,
          SetflowSpacing.xxl,
          SetflowSpacing.xxl,
        ),
        children: [
          ListTile(
            title: Text(
              '계정',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(_isGym ? '센터 프로필 편집' : '프로필 편집'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BusinessProfileEditScreen(role: role),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: const Text('요금제'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BusinessSettingsPlanScreen(role: role),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_none),
            title: const Text('알림 설정'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BusinessSettingsNotificationsScreen(role: role),
              ),
            ),
          ),
          if (!_isGym)
            ListTile(
              leading: const Icon(Icons.verified_outlined),
              title: const Text('인증 뱃지 갱신'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const BusinessBadgeRenewScreen(),
                ),
              ),
            ),
          const Divider(height: SetflowSpacing.section),
          ListTile(
            title: Text(
              '화면',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SwitchListTile(
            secondary: Icon(
              state.isDarkMode
                  ? Icons.dark_mode_rounded
                  : Icons.light_mode_rounded,
            ),
            title: const Text('다크 모드'),
            subtitle: Text(state.isDarkMode ? '어두운 화면 사용 중' : '밝은 화면 사용 중'),
            value: state.isDarkMode,
            onChanged: (_) => state.toggleTheme(),
          ),
          const Divider(height: SetflowSpacing.section),
          ListTile(
            leading: const Icon(
              Icons.person_off_outlined,
              color: SetflowColors.red,
            ),
            title: Text(
              _isGym ? '헬스장 탈퇴' : '탈퇴',
              style: const TextStyle(color: SetflowColors.red),
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BusinessSettingsWithdrawScreen(role: role),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 요금제 화면.
class BusinessSettingsPlanScreen extends StatefulWidget {
  const BusinessSettingsPlanScreen({required this.role, super.key});
  final UserRole role;

  @override
  State<BusinessSettingsPlanScreen> createState() =>
      _BusinessSettingsPlanScreenState();
}

class _BusinessSettingsPlanScreenState
    extends State<BusinessSettingsPlanScreen> {
  bool get _isGym => widget.role == UserRole.gym;

  late String _currentPlanId = _isGym ? 'basic' : 'starter';

  List<({String id, String name, String price, Color tint, List<String> perks})>
  get _plans {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.setflowColors;
    return _isGym
        ? [
            (
              id: 'basic',
              name: 'Basic',
              price: '55,000원 / 월',
              tint: scheme.onSurfaceVariant,
              perks: ['등록 회원 최대 50명', '기본 통계 대시보드'],
            ),
            (
              id: 'standard',
              name: 'Standard',
              price: '99,000원 / 월',
              tint: semantic.blue,
              perks: ['등록 회원 최대 100명', '트레이너 관리 도구', '정산 리포트'],
            ),
            (
              id: 'pro',
              name: 'Pro',
              price: '290,000원 / 월',
              tint: semantic.purple,
              perks: ['등록 회원 최대 500명', '마켓 상단 우선 노출', '고급 통계'],
            ),
            (
              id: 'enterprise',
              name: 'Enterprise',
              price: '별도 문의',
              tint: scheme.onSurface,
              perks: ['등록 회원 무제한', '전담 매니저 지원'],
            ),
          ]
        : [
            (
              id: 'starter',
              name: '스타터',
              price: '무료',
              tint: scheme.onSurfaceVariant,
              perks: ['관리 회원 최대 10명', '기본 통계 대시보드'],
            ),
            (
              id: 'pro',
              name: '프로',
              price: '9,900원 / 월',
              tint: scheme.primary,
              perks: ['관리 회원 최대 30명', '고급 통계', '리타겟팅 발송 (월 30건)'],
            ),
            (
              id: 'enterprise',
              name: '엔터프라이즈',
              price: '29,900원 / 월',
              tint: semantic.purple,
              perks: ['관리 회원 무제한', '리타겟팅 발송 (월 100건)', '마켓 홈 상단 우선 노출'],
            ),
          ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('요금제')),
      body: ListView(
        padding: SetflowInsets.pageList,
        children: [
          for (final plan in _plans) ...[
            SetflowCard(
              color: plan.id == _currentPlanId
                  ? plan.tint.withValues(alpha: .08)
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      TintedIconBadge(
                        icon: Icons.workspace_premium,
                        color: plan.tint,
                        square: true,
                      ),
                      const SizedBox(width: SetflowSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plan.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              plan.price,
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (plan.id == _currentPlanId)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: SetflowSpacing.md,
                            vertical: SetflowSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: plan.tint,
                            borderRadius: BorderRadius.circular(
                              SetflowRadii.lg,
                            ),
                          ),
                          child: Text(
                            '현재 플랜',
                            style: theme.textTheme.bodySmall?.copyWith(
                              // plan.tint can be a light tone (e.g. onSurface
                              // in dark mode), so pick a foreground that
                              // actually contrasts with the fill instead of
                              // assuming a dark badge.
                              color:
                                  ThemeData.estimateBrightnessForColor(
                                        plan.tint,
                                      ) ==
                                      Brightness.dark
                                  ? Colors.white
                                  : theme.colorScheme.onPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: SetflowSpacing.lg),
                  // Rich action card (pattern 4): perks as a bordered chip
                  // row instead of a vertical checklist.
                  Wrap(
                    spacing: SetflowSpacing.sm,
                    runSpacing: SetflowSpacing.sm,
                    children: [
                      for (final perk in plan.perks)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: SetflowSpacing.sm,
                            vertical: SetflowSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: context.setflowColors.surfaceContainer,
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                            ),
                            borderRadius: BorderRadius.circular(
                              SetflowRadii.sm,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle,
                                size: 14,
                                color: plan.tint,
                              ),
                              const SizedBox(width: SetflowSpacing.xs),
                              Text(
                                perk,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (plan.id != _currentPlanId) ...[
                    const SizedBox(height: SetflowSpacing.md),
                    // Tinted volt action row (pattern 4's "바로 시작" style)
                    // instead of a solid PrimaryButton.
                    Material(
                      color: theme.colorScheme.primary.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(SetflowRadii.md),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(SetflowRadii.md),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _currentPlanId = plan.id);
                          showMessage(
                            context,
                            '${plan.name} 플랜으로 변경되었습니다. (데모)',
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: SetflowSpacing.md,
                          ),
                          child: Center(
                            child: Text(
                              '${plan.name} 플랜으로 변경',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: SetflowSpacing.lg),
          ],
        ],
      ),
    );
  }
}

/// 알림 설정 화면.
class BusinessSettingsNotificationsScreen extends StatefulWidget {
  const BusinessSettingsNotificationsScreen({required this.role, super.key});
  final UserRole role;

  @override
  State<BusinessSettingsNotificationsScreen> createState() =>
      _BusinessSettingsNotificationsScreenState();
}

class _BusinessSettingsNotificationsScreenState
    extends State<BusinessSettingsNotificationsScreen> {
  bool _primaryActivity = true;
  bool _feedback = true;
  bool _settlement = false;
  bool _marketing = false;

  bool get _isGym => widget.role == UserRole.gym;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('알림 설정')),
      body: ListView(
        padding: SetflowInsets.pageList,
        children: [
          ListTile(
            title: Text(
              '활동 알림',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.chat_bubble_outline),
            title: Text(_isGym ? '신규 회원 문의' : '신규 상담 요청'),
            subtitle: Text(_isGym ? '센터 등록/이용 문의 알림' : '새로운 회원의 코칭 문의 알림'),
            value: _primaryActivity,
            onChanged: (value) => setState(() => _primaryActivity = value),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fitness_center),
            title: Text(_isGym ? '트레이너 활동 알림' : '회원 운동 기록 및 피드백'),
            subtitle: Text(_isGym ? '소속 트레이너 활동 현황 알림' : '코칭 중인 회원의 새로운 활동'),
            value: _feedback,
            onChanged: (value) => setState(() => _feedback = value),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.payments_outlined),
            title: const Text('정산 및 환불 현황'),
            subtitle: const Text('주기적인 정산 금액 및 분쟁 알림'),
            value: _settlement,
            onChanged: (value) => setState(() => _settlement = value),
          ),
          const Divider(height: SetflowSpacing.section),
          ListTile(
            title: Text(
              '이벤트 및 혜택',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.card_giftcard_outlined),
            title: const Text('마케팅 정보 수신 동의'),
            subtitle: const Text('플랫폼 이벤트 및 혜택 안내'),
            value: _marketing,
            onChanged: (value) => setState(() => _marketing = value),
          ),
        ],
      ),
    );
  }
}

/// 탈퇴 화면.
class BusinessSettingsWithdrawScreen extends StatefulWidget {
  const BusinessSettingsWithdrawScreen({required this.role, super.key});
  final UserRole role;

  @override
  State<BusinessSettingsWithdrawScreen> createState() =>
      _BusinessSettingsWithdrawScreenState();
}

class _BusinessSettingsWithdrawScreenState
    extends State<BusinessSettingsWithdrawScreen> {
  String? _reason;
  bool _agreed = false;

  bool get _isGym => widget.role == UserRole.gym;

  static const _reasons = [
    '운영할 시간이 부족해요',
    '수수료가 너무 높아요',
    '사용 방법이 어려워요',
    '서비스 이용이 불만족스러워요',
    '기타 사유',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canWithdraw = _reason != null && _agreed;
    return Scaffold(
      appBar: AppBar(title: Text(_isGym ? '헬스장 탈퇴' : '탈퇴')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: SetflowInsets.pageList,
              children: [
                Container(
                  padding: const EdgeInsets.all(SetflowSpacing.xl),
                  decoration: BoxDecoration(
                    color: SetflowColors.red.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(SetflowRadii.lg),
                    border: Border.all(
                      color: SetflowColors.red.withValues(alpha: .2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '잠깐, 탈퇴 전에 확인해 주세요',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: SetflowSpacing.md),
                      _WarningItem(
                        icon: Icons.schedule,
                        title: '30일 유예 기간',
                        message: '탈퇴 신청 후 30일 동안은 언제든 로그인하여 복구할 수 있습니다.',
                      ),
                      _WarningItem(
                        icon: Icons.groups_outlined,
                        title: _isGym ? '소속 트레이너/회원 자동 안내' : '관리 회원 자동 안내',
                        message: '이용 중인 상대방에게 서비스 종료 안내가 자동 발송됩니다.',
                      ),
                      _WarningItem(
                        icon: Icons.wallet_outlined,
                        title: '미정산 수익금 처리',
                        message: '탈퇴 신청 후 익월 1일에 등록된 계좌로 일괄 지급됩니다.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: SetflowSpacing.xl),
                Text(
                  '탈퇴 사유를 선택해 주세요',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: SetflowSpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: _reason,
                  hint: const Text('탈퇴 사유 선택'),
                  items: [
                    for (final reason in _reasons)
                      DropdownMenuItem(value: reason, child: Text(reason)),
                  ],
                  onChanged: (value) => setState(() => _reason = value),
                ),
                const SizedBox(height: SetflowSpacing.lg),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _agreed,
                  onChanged: (value) => setState(() => _agreed = value ?? false),
                  title: Text(
                    '안내사항을 모두 확인하였으며 탈퇴 및 수익금 정산 처리에 동의합니다.',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Pattern 5: destructive dominant action stays sticky and red.
          Padding(
            padding: SetflowInsets.bottomAction,
            child: FilledButton(
              onPressed: canWithdraw ? () => _confirmWithdraw(context) : null,
              style: FilledButton.styleFrom(
                backgroundColor: SetflowColors.red,
                minimumSize: const Size.fromHeight(52),
              ),
              child: const Text('탈퇴 신청하기'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmWithdraw(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('정말 탈퇴하시겠습니까?'),
        content: const Text('30일 유예 기간 내에 언제든 복구할 수 있습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('탈퇴', style: TextStyle(color: SetflowColors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      showMessage(context, '탈퇴 신청이 완료되었습니다. (데모)');
      Navigator.of(context).pop();
    }
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: SetflowSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 18, color: SetflowColors.red),
          const SizedBox(width: SetflowSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: SetflowSpacing.xxs),
                Text(
                  message,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
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

/// (트레이너) 인증 뱃지 갱신 화면.
class BusinessBadgeRenewScreen extends StatefulWidget {
  const BusinessBadgeRenewScreen({super.key});

  @override
  State<BusinessBadgeRenewScreen> createState() =>
      _BusinessBadgeRenewScreenState();
}

class _BusinessBadgeRenewScreenState extends State<BusinessBadgeRenewScreen> {
  bool _fileAttached = false;
  bool _submitting = false;

  static const _dDay = 15;
  static const _expiryDate = '2026.08.06';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('인증 뱃지 갱신')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: SetflowInsets.pageList,
              children: [
                Container(
                  padding: const EdgeInsets.all(SetflowSpacing.xl),
                  decoration: BoxDecoration(
                    color: context.setflowColors.purple,
                    borderRadius: BorderRadius.circular(SetflowRadii.xl),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.shield_outlined, color: Colors.white),
                          const SizedBox(width: SetflowSpacing.sm),
                          const Text(
                            '연 1회 정기 심사',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: SetflowSpacing.md,
                              vertical: SetflowSpacing.xs,
                            ),
                            decoration: BoxDecoration(
                              color: SetflowColors.red,
                              borderRadius: BorderRadius.circular(
                                SetflowRadii.lg,
                              ),
                            ),
                            child: Text(
                              'D-$_dDay',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: SetflowSpacing.lg),
                      Text(
                        '안전한 플랫폼을 위해 코치 자격을 재확인합니다.',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: SetflowSpacing.sm),
                      Text(
                        '만료일($_expiryDate) 전까지 증빙 서류를 제출하지 않으면 신규 회원 상담 및 결제 수신이 제한될 수 있습니다.',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: SetflowSpacing.xl),
                Text(
                  '서류 업로드',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: SetflowSpacing.md),
                if (!_fileAttached)
                  SetflowCard(
                    onTap: () => setState(() => _fileAttached = true),
                    color: context.setflowColors.blue.withValues(alpha: .06),
                    padding: const EdgeInsets.all(SetflowSpacing.section),
                    child: Column(
                      children: [
                        Icon(
                          Icons.upload_file,
                          size: 36,
                          color: context.setflowColors.blue,
                        ),
                        const SizedBox(height: SetflowSpacing.md),
                        Text(
                          '이곳을 눌러 파일을 선택하세요',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: SetflowSpacing.xs),
                        Text(
                          'JPG, PNG, PDF (최대 10MB) · 데모',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  SetflowCard(
                    child: Row(
                      children: [
                        const TintedIconBadge(
                          icon: Icons.description_outlined,
                          color: SetflowColors.green,
                          square: true,
                        ),
                        const SizedBox(width: SetflowSpacing.md),
                        const Expanded(
                          child: Text(
                            '자격증_사본.pdf',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _fileAttached = false),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: SetflowSpacing.xl),
                Container(
                  padding: const EdgeInsets.all(SetflowSpacing.lg),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(SetflowRadii.lg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '필수 확인 사항',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: SetflowSpacing.sm),
                      Text(
                        '• 본명과 일치하는 공인 기관 발급 자격증만 인정됩니다.\n'
                        '• 자격번호, 발급일, 발급기관 직인이 선명해야 합니다.\n'
                        '• 허위 서류 제출 시 활동이 정지될 수 있습니다.',
                        style: theme.textTheme.labelMedium?.copyWith(height: 1.6),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Pattern 5: sticky volt CTA for the single dominant submit action.
          Padding(
            padding: SetflowInsets.bottomAction,
            child: PrimaryButton(
              label: _submitting ? '제출 중...' : '자격 갱신 서류 제출하기',
              icon: Icons.shield_outlined,
              onPressed: !_fileAttached || _submitting
                  ? null
                  : () async {
                      setState(() => _submitting = true);
                      await Future<void>.delayed(
                        const Duration(milliseconds: 600),
                      );
                      if (!context.mounted) return;
                      setState(() => _submitting = false);
                      showMessage(context, '자격 재확인 서류가 제출되었습니다. (데모)');
                      Navigator.of(context).pop();
                    },
            ),
          ),
        ],
      ),
    );
  }
}

/// 프로필 편집 화면.
class BusinessProfileEditScreen extends StatefulWidget {
  const BusinessProfileEditScreen({required this.role, super.key});
  final UserRole role;

  @override
  State<BusinessProfileEditScreen> createState() =>
      _BusinessProfileEditScreenState();
}

class _BusinessProfileEditScreenState extends State<BusinessProfileEditScreen> {
  bool get _isGym => widget.role == UserRole.gym;

  late final _nameController = TextEditingController(
    text: _isGym ? '낼도돌파 피트니스 강남점' : '김코치',
  );
  late final _keywordController = TextEditingController(
    text: _isGym ? '서울 강남구 테헤란로 123' : '바디프로필 전문가',
  );
  late final _introController = TextEditingController(
    text: _isGym
        ? '최고의 시설과 실력 있는 강사진이 함께하는 프리미엄 피트니스 센터입니다.'
        : '3년 연속 바디프로필 전문 메이커입니다. 어렵지 않게 즐기면서 목표를 이뤄드릴게요!',
  );

  @override
  void dispose() {
    _nameController.dispose();
    _keywordController.dispose();
    _introController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _isGym ? context.setflowColors.purple : context.setflowColors.blue;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isGym ? '센터 프로필 편집' : '프로필 편집'),
        actions: [
          TextButton(
            onPressed: () {
              showMessage(context, '프로필이 저장되었습니다. (데모)');
              Navigator.of(context).pop();
            },
            child: const Text('저장'),
          ),
        ],
      ),
      body: ListView(
        padding: SetflowInsets.pageForm,
        children: [
          Center(
            child: Stack(
              children: [
                TintedIconBadge(
                  icon: _isGym ? Icons.apartment : Icons.person,
                  color: accent,
                  size: 96,
                  iconSize: 46,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: theme.colorScheme.primary,
                    child: Icon(
                      Icons.camera_alt_outlined,
                      size: 16,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.xxl),
          Text(
            _isGym ? '센터 이름' : '이름',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: SetflowSpacing.sm),
          TextField(controller: _nameController),
          const SizedBox(height: SetflowSpacing.xl),
          Text(
            _isGym ? '위치' : '한 줄 키워드',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: SetflowSpacing.sm),
          TextField(controller: _keywordController),
          const SizedBox(height: SetflowSpacing.xl),
          Text(
            _isGym ? '센터 소개' : '자기소개',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: SetflowSpacing.sm),
          TextField(controller: _introController, maxLines: 4, maxLength: 150),
        ],
      ),
    );
  }
}
