import 'package:flutter/material.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
        children: [
          const ListTile(
            title: Text(
              '계정',
              style: TextStyle(
                fontSize: 13,
                color: SetflowColors.secondaryText,
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
          const Divider(height: 30),
          ListTile(
            leading: const Icon(Icons.person_off_outlined, color: SetflowColors.red),
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
  get _plans => _isGym
      ? const [
          (
            id: 'basic',
            name: 'Basic',
            price: '55,000원 / 월',
            tint: SetflowColors.secondaryText,
            perks: ['등록 회원 최대 50명', '기본 통계 대시보드'],
          ),
          (
            id: 'standard',
            name: 'Standard',
            price: '99,000원 / 월',
            tint: SetflowColors.blue,
            perks: ['등록 회원 최대 100명', '트레이너 관리 도구', '정산 리포트'],
          ),
          (
            id: 'pro',
            name: 'Pro',
            price: '290,000원 / 월',
            tint: SetflowColors.purple,
            perks: ['등록 회원 최대 500명', '마켓 상단 우선 노출', '고급 통계'],
          ),
          (
            id: 'enterprise',
            name: 'Enterprise',
            price: '별도 문의',
            tint: SetflowColors.ink,
            perks: ['등록 회원 무제한', '전담 매니저 지원'],
          ),
        ]
      : const [
          (
            id: 'starter',
            name: '스타터',
            price: '무료',
            tint: SetflowColors.secondaryText,
            perks: ['관리 회원 최대 10명', '기본 통계 대시보드'],
          ),
          (
            id: 'pro',
            name: '프로',
            price: '9,900원 / 월',
            tint: SetflowColors.primary,
            perks: ['관리 회원 최대 30명', '고급 통계', '리타겟팅 발송 (월 30건)'],
          ),
          (
            id: 'enterprise',
            name: '엔터프라이즈',
            price: '29,900원 / 월',
            tint: SetflowColors.purple,
            perks: ['관리 회원 무제한', '리타겟팅 발송 (월 100건)', '마켓 홈 상단 우선 노출'],
          ),
        ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('요금제')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
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
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: plan.tint.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.workspace_premium, color: plan.tint),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plan.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              plan.price,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: SetflowColors.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (plan.id == _currentPlanId)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: plan.tint,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            '현재 플랜',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  for (final perk in plan.perks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, size: 16, color: plan.tint),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              perk,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (plan.id != _currentPlanId) ...[
                    const SizedBox(height: 6),
                    PrimaryButton(
                      label: '${plan.name} 플랜으로 변경',
                      onPressed: () {
                        setState(() => _currentPlanId = plan.id);
                        showMessage(context, '${plan.name} 플랜으로 변경되었습니다. (데모)');
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
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
    return Scaffold(
      appBar: AppBar(title: const Text('알림 설정')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
        children: [
          const ListTile(
            title: Text(
              '활동 알림',
              style: TextStyle(
                fontSize: 13,
                color: SetflowColors.secondaryText,
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
          const Divider(height: 30),
          const ListTile(
            title: Text(
              '이벤트 및 혜택',
              style: TextStyle(
                fontSize: 13,
                color: SetflowColors.secondaryText,
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
    final canWithdraw = _reason != null && _agreed;
    return Scaffold(
      appBar: AppBar(title: Text(_isGym ? '헬스장 탈퇴' : '탈퇴')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: SetflowColors.red.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: SetflowColors.red.withValues(alpha: .2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '잠깐, 탈퇴 전에 확인해 주세요',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
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
          const SizedBox(height: 20),
          const Text(
            '탈퇴 사유를 선택해 주세요',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _reason,
            hint: const Text('탈퇴 사유 선택'),
            items: [
              for (final reason in _reasons)
                DropdownMenuItem(value: reason, child: Text(reason)),
            ],
            onChanged: (value) => setState(() => _reason = value),
          ),
          const SizedBox(height: 14),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _agreed,
            onChanged: (value) => setState(() => _agreed = value ?? false),
            title: const Text(
              '안내사항을 모두 확인하였으며 탈퇴 및 수익금 정산 처리에 동의합니다.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: '탈퇴 신청하기',
            onPressed: canWithdraw ? () => _confirmWithdraw(context) : null,
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
            child: const Text(
              '탈퇴',
              style: TextStyle(color: SetflowColors.red),
            ),
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
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: SetflowColors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 12,
                    color: SetflowColors.secondaryText,
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
    return Scaffold(
      appBar: AppBar(title: const Text('인증 뱃지 갱신')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: SetflowColors.purple,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: Colors.white),
                    const SizedBox(width: 8),
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
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: SetflowColors.red,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'D-$_dDay',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  '안전한 플랫폼을 위해 코치 자격을 재확인합니다.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '만료일($_expiryDate) 전까지 증빙 서류를 제출하지 않으면 신규 회원 상담 및 결제 수신이 제한될 수 있습니다.',
                  style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '서류 업로드',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          if (!_fileAttached)
            SetflowCard(
              onTap: () => setState(() => _fileAttached = true),
              color: SetflowColors.blue.withValues(alpha: .06),
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  Icon(Icons.upload_file, size: 36, color: SetflowColors.blue),
                  const SizedBox(height: 12),
                  const Text(
                    '이곳을 눌러 파일을 선택하세요',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'JPG, PNG, PDF (최대 10MB) · 데모',
                    style: TextStyle(fontSize: 12, color: SetflowColors.secondaryText),
                  ),
                ],
              ),
            )
          else
            SetflowCard(
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: SetflowColors.green.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.description_outlined, color: SetflowColors.green),
                  ),
                  const SizedBox(width: 12),
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
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SetflowColors.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '필수 확인 사항',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                ),
                SizedBox(height: 8),
                Text(
                  '• 본명과 일치하는 공인 기관 발급 자격증만 인정됩니다.\n'
                  '• 자격번호, 발급일, 발급기관 직인이 선명해야 합니다.\n'
                  '• 허위 서류 제출 시 활동이 정지될 수 있습니다.',
                  style: TextStyle(fontSize: 12, height: 1.6),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: _submitting ? '제출 중...' : '자격 갱신 서류 제출하기',
            icon: Icons.shield_outlined,
            onPressed: !_fileAttached || _submitting
                ? null
                : () async {
                    setState(() => _submitting = true);
                    await Future<void>.delayed(const Duration(milliseconds: 600));
                    if (!context.mounted) return;
                    setState(() => _submitting = false);
                    showMessage(context, '자격 재확인 서류가 제출되었습니다. (데모)');
                    Navigator.of(context).pop();
                  },
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

class _BusinessProfileEditScreenState
    extends State<BusinessProfileEditScreen> {
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
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        children: [
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor:
                      (_isGym ? SetflowColors.purple : SetflowColors.blue)
                          .withValues(alpha: .15),
                  child: Icon(
                    _isGym ? Icons.apartment : Icons.person,
                    size: 46,
                    color: _isGym ? SetflowColors.purple : SetflowColors.blue,
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: SetflowColors.primary,
                    child: const Icon(
                      Icons.camera_alt_outlined,
                      size: 16,
                      color: SetflowColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _isGym ? '센터 이름' : '이름',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          TextField(controller: _nameController),
          const SizedBox(height: 18),
          Text(
            _isGym ? '위치' : '한 줄 키워드',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          TextField(controller: _keywordController),
          const SizedBox(height: 18),
          Text(
            _isGym ? '센터 소개' : '자기소개',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _introController,
            maxLines: 4,
            maxLength: 150,
          ),
        ],
      ),
    );
  }
}
