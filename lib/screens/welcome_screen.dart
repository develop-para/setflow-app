import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..forward();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
          child: FadeTransition(
            opacity: CurvedAnimation(parent: controller, curve: Curves.easeOut),
            child: SlideTransition(
              position: Tween(begin: const Offset(0, .05), end: Offset.zero)
                  .animate(
                    CurvedAnimation(
                      parent: controller,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: Column(
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: SetflowColors.primary,
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x24000000),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.rocket_launch_rounded,
                      size: 48,
                      color: Color(0xFFFF4F75),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Setflow',
                    style: TextStyle(fontSize: 31, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '환영합니다!\n어떤 사용자로 시작하시겠어요?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: SetflowColors.secondaryText,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 48),
                  _RoleTile(
                    icon: Icons.person_outline_rounded,
                    title: '일반 회원',
                    subtitle: '나만의 운동 기록 관리',
                    accent: SetflowColors.primary,
                    onTap: () => _openMemberSetup(context),
                  ),
                  const SizedBox(height: 14),
                  _RoleTile(
                    icon: Icons.fitness_center_rounded,
                    title: '트레이너',
                    subtitle: '회원 관리 및 수익 창출',
                    accent: SetflowColors.blue,
                    onTap: () => _openBusinessSetup(context, UserRole.trainer),
                  ),
                  const SizedBox(height: 14),
                  _RoleTile(
                    icon: Icons.apartment_rounded,
                    title: '헬스장 / 센터장',
                    subtitle: '소속 트레이너 및 매출 관리',
                    accent: SetflowColors.purple,
                    onTap: () => _openBusinessSetup(context, UserRole.gym),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openMemberSetup(BuildContext context) async {
    final result = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const MemberSetupScreen()));
    if (result == true && context.mounted) {
      AppScope.of(context).chooseRole(UserRole.member);
    }
  }

  Future<void> _openBusinessSetup(BuildContext context, UserRole role) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => BusinessSetupScreen(role: role)),
    );
    if (result == true && context.mounted) {
      AppScope.of(context).chooseRole(role);
    }
  }
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SetflowCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .09),
              shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Icon(icon, color: accent, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: SetflowColors.secondaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: SetflowColors.disabled,
          ),
        ],
      ),
    );
  }
}

class MemberSetupScreen extends StatefulWidget {
  const MemberSetupScreen({super.key});

  @override
  State<MemberSetupScreen> createState() => _MemberSetupScreenState();
}

class _MemberSetupScreenState extends State<MemberSetupScreen> {
  String unit = 'kg';
  int step = 0;
  final goals = <String>{};
  final heightController = TextEditingController();
  final weightController = TextEditingController();
  final ageController = TextEditingController();
  String? gender;

  @override
  void dispose() {
    heightController.dispose();
    weightController.dispose();
    ageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        actions: [
          if (step == 1)
            TextButton(onPressed: _finish, child: const Text('건너뛰기')),
          if (step == 2)
            TextButton(
              onPressed: () => setState(() => step = 3),
              child: const Text('건너뛰기'),
            ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: switch (step) {
          0 => _preferences(context),
          1 => _goals(context),
          2 => _bodyProfile(context),
          _ => _signup(context),
        },
      ),
    );
  }

  Widget _preferences(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('preferences'),
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 32),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: SetflowColors.primary,
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(
              Icons.rocket_launch_rounded,
              size: 43,
              color: Color(0xFFFF4F75),
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Setflow',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          const Text(
            '운동 흐름은 그대로,\n성장은 데이터로.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 38),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('단위 선택', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'kg', label: Text('kg')),
              ButtonSegment(value: 'lb', label: Text('lb')),
            ],
            selected: {unit},
            onSelectionChanged: (value) => setState(() => unit = value.first),
            style: ButtonStyle(
              minimumSize: WidgetStateProperty.all(const Size(150, 50)),
            ),
          ),
          const SizedBox(height: 30),
          PrimaryButton(
            label: '저장',
            icon: Icons.arrow_forward_rounded,
            onPressed: () {
              AppScope.of(context).setWeightUnit(unit);
              setState(() => step = 1);
            },
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _finish,
            child: const Text('이미 계정이 있으신가요? 로그인'),
          ),
        ],
      ),
    );
  }

  Widget _goals(BuildContext context) {
    const options = [
      ('🔥', '체중 감량', '체지방을 줄이고 다이어트'),
      ('💪', '근육 증가', '근골격량을 늘려 탄탄하게'),
      ('🏃', '체력 향상', '기초 체력과 지구력 증진'),
      ('🌱', '건강 유지', '현재 상태를 안정적으로 유지'),
    ];
    return SingleChildScrollView(
      key: const ValueKey('goals'),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '어떤 목표로\n운동하시나요?',
            style: TextStyle(
              fontSize: 29,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '가장 중요한 목표를 최대 2개까지 선택해주세요.',
            style: TextStyle(color: SetflowColors.secondaryText),
          ),
          const SizedBox(height: 28),
          ...options.map((option) {
            final selected = goals.contains(option.$2);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SetflowCard(
                onTap: () => setState(() {
                  if (selected) {
                    goals.remove(option.$2);
                  } else if (goals.length < 2) {
                    goals.add(option.$2);
                  }
                }),
                color: selected
                    ? SetflowColors.primary.withValues(alpha: .14)
                    : null,
                child: Row(
                  children: [
                    Text(option.$1, style: const TextStyle(fontSize: 28)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            option.$2,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            option.$3,
                            style: const TextStyle(
                              color: SetflowColors.secondaryText,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      selected ? Icons.check_circle : Icons.circle_outlined,
                      color: selected
                          ? SetflowColors.primary
                          : SetflowColors.disabled,
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 18),
          PrimaryButton(
            label: '다음',
            icon: Icons.arrow_forward_rounded,
            onPressed: goals.isEmpty ? null : () => setState(() => step = 2),
          ),
        ],
      ),
    );
  }

  Widget _bodyProfile(BuildContext context) {
    final filled =
        heightController.text.isNotEmpty ||
        weightController.text.isNotEmpty ||
        ageController.text.isNotEmpty ||
        gender != null;
    return SingleChildScrollView(
      key: const ValueKey('bodyProfile'),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '현재 신체 정보를\n입력해주세요',
            style: TextStyle(
              fontSize: 29,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '정확한 데이터 분석을 위해 필요해요.\n지금 모르는 정보는 나중에 입력할 수 있어요.',
            style: TextStyle(color: SetflowColors.secondaryText, height: 1.5),
          ),
          const SizedBox(height: 28),
          const Text('나이', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          TextField(
            controller: ageController,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: '예: 29',
              suffixText: '세',
            ),
          ),
          const SizedBox(height: 20),
          const Text('성별', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'M', label: Text('남성')),
              ButtonSegment(value: 'F', label: Text('여성')),
              ButtonSegment(value: 'O', label: Text('기타')),
            ],
            selected: gender == null ? const {} : {gender!},
            emptySelectionAllowed: true,
            onSelectionChanged: (value) => setState(
              () => gender = value.isEmpty ? null : value.first,
            ),
          ),
          const SizedBox(height: 20),
          const Text('키', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          TextField(
            controller: heightController,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: '예: 175',
              suffixText: 'cm',
            ),
          ),
          const SizedBox(height: 20),
          Text('체중 ($unit)', style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          TextField(
            controller: weightController,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: '예: 70', suffixText: unit),
          ),
          const SizedBox(height: 30),
          PrimaryButton(
            label: '저장',
            icon: Icons.arrow_forward_rounded,
            onPressed: filled ? () => setState(() => step = 3) : null,
          ),
        ],
      ),
    );
  }

  Widget _signup(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('signup'),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '가입하고 내 기록\n안전하게 보관하기',
            style: TextStyle(
              fontSize: 29,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '클라우드 백업과 코칭 등 전체 기능을 사용하려면\n무료 회원가입이 필요해요.',
            style: TextStyle(color: SetflowColors.secondaryText, height: 1.5),
          ),
          const SizedBox(height: 28),
          PrimaryButton(label: '카카오로 시작하기', onPressed: _finish),
          const SizedBox(height: 12),
          PrimaryButton(label: '구글로 시작하기', onPressed: _finish),
          const SizedBox(height: 12),
          PrimaryButton(label: 'Apple로 시작하기', onPressed: _finish),
          const SizedBox(height: 18),
          Center(
            child: TextButton(
              onPressed: _finish,
              child: const Text('이메일로 가입하기'),
            ),
          ),
          const SizedBox(height: 22),
          Divider(color: Theme.of(context).dividerColor),
          const SizedBox(height: 16),
          const Text(
            '우선 기기에만 저장할까요?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: SetflowColors.secondaryText),
          ),
          const SizedBox(height: 12),
          PrimaryButton(label: '가입 없이 바로 시작', onPressed: _finish),
        ],
      ),
    );
  }

  void _finish() => Navigator.of(context).pop(true);
}

class BusinessSetupScreen extends StatefulWidget {
  const BusinessSetupScreen({required this.role, super.key});
  final UserRole role;

  @override
  State<BusinessSetupScreen> createState() => _BusinessSetupScreenState();
}

enum _TrainerStep { register, docs, pending, rejected, complete }

enum _GymStep { register, docs, hometax, complete }

class _BusinessSetupScreenState extends State<BusinessSetupScreen> {
  final nameController = TextEditingController();
  final numberController = TextEditingController();
  _TrainerStep trainerStep = _TrainerStep.register;
  final uploadedDocs = <int>{};
  _GymStep gymStep = _GymStep.register;
  bool gymDocUploaded = false;
  bool gymHometaxVerified = false;

  @override
  void dispose() {
    nameController.dispose();
    numberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.role != UserRole.trainer) {
      return _buildGymWizard(context);
    }
    return _buildTrainerWizard(context);
  }

  Widget _buildGymWizard(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: switch (gymStep) {
          _GymStep.register => _gymRegister(context),
          _GymStep.docs => _gymDocs(context),
          _GymStep.hometax => _gymHometax(context),
          _GymStep.complete => _gymComplete(context),
        },
      ),
    );
  }

  Widget _gymRegister(BuildContext context) {
    final filled =
        nameController.text.trim().isNotEmpty &&
        numberController.text.trim().isNotEmpty;
    return SingleChildScrollView(
      key: const ValueKey('gymRegister'),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: SetflowColors.purple.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.apartment, color: SetflowColors.purple),
          ),
          const SizedBox(height: 22),
          const Text(
            '헬스장 등록하기',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            '센터 운영과 회원 관리를 한곳에서 시작하세요.',
            style: TextStyle(color: SetflowColors.secondaryText, height: 1.5),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: nameController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: '헬스장명'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: numberController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: '사업자등록번호'),
          ),
          const SizedBox(height: 30),
          PrimaryButton(
            label: '다음',
            icon: Icons.arrow_forward_rounded,
            onPressed: filled
                ? () => setState(() => gymStep = _GymStep.docs)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _gymDocs(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('gymDocs'),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '사업자등록증을\n제출해주세요',
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '원활한 정산과 안전한 센터 운영을 위해 필요해요.',
            style: TextStyle(color: SetflowColors.secondaryText, height: 1.5),
          ),
          const SizedBox(height: 28),
          SetflowCard(
            onTap: () => setState(() => gymDocUploaded = !gymDocUploaded),
            child: Row(
              children: [
                Icon(
                  gymDocUploaded
                      ? Icons.check_circle
                      : Icons.upload_file_rounded,
                  color: gymDocUploaded
                      ? SetflowColors.green
                      : SetflowColors.purple,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '사업자등록증',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  gymDocUploaded ? '업로드됨' : '업로드',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: gymDocUploaded
                        ? SetflowColors.green
                        : SetflowColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: SetflowColors.soft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 20,
                  color: SetflowColors.green,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '실제 파일 업로드 없이 데모로 진행됩니다. 카드를 눌러 제출 상태를 전환해보세요.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: SetflowColors.secondaryText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          PrimaryButton(
            label: '서류 제출하기',
            icon: Icons.arrow_forward_rounded,
            onPressed: gymDocUploaded
                ? () => setState(() => gymStep = _GymStep.hometax)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _gymHometax(BuildContext context) {
    final bizNumber = numberController.text.trim();
    return SingleChildScrollView(
      key: const ValueKey('gymHometax'),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: SetflowColors.purple.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.account_balance_rounded,
              color: SetflowColors.purple,
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            '홈택스 사업자 인증',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            '국세청 홈택스와 연동하여 사업자 상태를 실시간으로 확인해요.',
            style: TextStyle(color: SetflowColors.secondaryText, height: 1.5),
          ),
          const SizedBox(height: 28),
          SetflowCard(
            child: Row(
              children: [
                const Icon(
                  Icons.business_rounded,
                  color: SetflowColors.purple,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '사업자등록번호',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: SetflowColors.secondaryText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        bizNumber.isEmpty ? '미입력' : bizNumber,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          if (!gymHometaxVerified)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: SetflowColors.soft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 20,
                    color: SetflowColors.purple,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '안전한 코칭 환경을 위해 실제 영업 중인 사업자만 인증됩니다. 데모에서는 버튼을 누르면 바로 인증됩니다.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: SetflowColors.secondaryText,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: SetflowColors.green.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: SetflowColors.green.withValues(alpha: .25),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 20,
                    color: SetflowColors.green,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '인증 완료! 국세청 홈택스 기준 정상 영업 중인 사업자입니다.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        fontWeight: FontWeight.w700,
                        color: SetflowColors.secondaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 30),
          if (!gymHometaxVerified)
            PrimaryButton(
              label: '홈택스 인증하기',
              icon: Icons.fact_check_rounded,
              onPressed: bizNumber.isEmpty
                  ? null
                  : () => setState(() => gymHometaxVerified = true),
            )
          else
            PrimaryButton(
              label: '다음',
              icon: Icons.arrow_forward_rounded,
              onPressed: () => setState(() => gymStep = _GymStep.complete),
            ),
        ],
      ),
    );
  }

  Widget _gymComplete(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('gymComplete'),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: SetflowColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_rounded,
              size: 48,
              color: SetflowColors.ink,
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            '가입 심사 완료!',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          const Text(
            '센터 인증이 성공적으로 완료되었습니다.\n지금 바로 회원과 트레이너 관리를 시작해보세요!',
            textAlign: TextAlign.center,
            style: TextStyle(color: SetflowColors.secondaryText, height: 1.5),
          ),
          const SizedBox(height: 32),
          PrimaryButton(
            label: '센터 운영 시작하기',
            icon: Icons.rocket_launch_rounded,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }

  Widget _buildTrainerWizard(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: switch (trainerStep) {
          _TrainerStep.register => _trainerRegister(context),
          _TrainerStep.docs => _trainerDocs(context),
          _TrainerStep.pending => _trainerPending(context),
          _TrainerStep.rejected => _trainerRejected(context),
          _TrainerStep.complete => _trainerComplete(context),
        },
      ),
    );
  }

  Widget _trainerRegister(BuildContext context) {
    final filled =
        nameController.text.trim().isNotEmpty &&
        numberController.text.trim().isNotEmpty;
    return SingleChildScrollView(
      key: const ValueKey('trainerRegister'),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: SetflowColors.blue.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.fitness_center, color: SetflowColors.blue),
          ),
          const SizedBox(height: 22),
          const Text(
            '트레이너로 시작하기',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            '인증 배지로 신뢰받는 코칭을 시작하세요.',
            style: TextStyle(color: SetflowColors.secondaryText, height: 1.5),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: nameController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: '이름'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: numberController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: '자격증 번호'),
          ),
          const SizedBox(height: 30),
          PrimaryButton(
            label: '다음',
            icon: Icons.arrow_forward_rounded,
            onPressed: filled
                ? () => setState(() => trainerStep = _TrainerStep.docs)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _trainerDocs(BuildContext context) {
    const docLabels = ['자격증 서류 (국가/민간)', '신분증 사본 (필수)'];
    return SingleChildScrollView(
      key: const ValueKey('trainerDocs'),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '인증 서류를\n제출해주세요',
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '신뢰할 수 있는 코칭 환경을 위해 최소 2종의 서류가 필요해요.',
            style: TextStyle(color: SetflowColors.secondaryText, height: 1.5),
          ),
          const SizedBox(height: 28),
          ...List.generate(docLabels.length, (index) {
            final uploaded = uploadedDocs.contains(index);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SetflowCard(
                onTap: () => setState(() {
                  if (uploaded) {
                    uploadedDocs.remove(index);
                  } else {
                    uploadedDocs.add(index);
                  }
                }),
                child: Row(
                  children: [
                    Icon(
                      uploaded ? Icons.check_circle : Icons.upload_file_rounded,
                      color: uploaded
                          ? SetflowColors.green
                          : SetflowColors.blue,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        docLabels[index],
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      uploaded ? '업로드됨' : '업로드',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: uploaded
                            ? SetflowColors.green
                            : SetflowColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: SetflowColors.soft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 20,
                  color: SetflowColors.green,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '실제 파일 업로드 없이 데모로 진행됩니다. 카드를 눌러 서류 제출 상태를 전환해보세요.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: SetflowColors.secondaryText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          PrimaryButton(
            label: '서류 제출하기',
            icon: Icons.arrow_forward_rounded,
            onPressed: uploadedDocs.length >= 2
                ? () => setState(() => trainerStep = _TrainerStep.pending)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _trainerPending(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('trainerPending'),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: SetflowColors.blue.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search_rounded,
              size: 40,
              color: SetflowColors.blue,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '서류 심사가\n진행 중입니다',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '제출해주신 서류를 확인하고 있어요.\n영업일 기준 3일 이내 완료될 예정입니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: SetflowColors.secondaryText, height: 1.5),
          ),
          const SizedBox(height: 32),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SetflowColors.soft,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                const Text(
                  '데모 시뮬레이션',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                const Text(
                  '심사 결과를 직접 선택해보세요.',
                  style: TextStyle(
                    fontSize: 12,
                    color: SetflowColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: PrimaryButton(
                        label: '심사 승인',
                        icon: Icons.check_circle_outline,
                        onPressed: () => setState(
                          () => trainerStep = _TrainerStep.complete,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(
                          () => trainerStep = _TrainerStep.rejected,
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 54),
                          foregroundColor: SetflowColors.red,
                          side: const BorderSide(color: SetflowColors.red),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text('심사 반려'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _trainerRejected(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('trainerRejected'),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: SetflowColors.red.withValues(alpha: .1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              size: 38,
              color: SetflowColors.red,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '서류 심사 반려',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          const Text(
            '제출해주신 서류에 보완이 필요한 부분이 있어\n부득이하게 심사가 반려되었습니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: SetflowColors.secondaryText, height: 1.5),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: SetflowColors.red.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: SetflowColors.red.withValues(alpha: .2),
              ),
            ),
            child: const Text(
              '반려 사유: 제출된 서류의 이미지가 흐려 식별이 어렵습니다. 선명하게 재촬영하여 업로드해주세요.',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: SetflowColors.secondaryText,
              ),
            ),
          ),
          const SizedBox(height: 30),
          PrimaryButton(
            label: '다시 제출하기',
            icon: Icons.refresh_rounded,
            onPressed: () => setState(() {
              uploadedDocs.clear();
              trainerStep = _TrainerStep.docs;
            }),
          ),
        ],
      ),
    );
  }

  Widget _trainerComplete(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('trainerComplete'),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: SetflowColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_rounded,
              size: 48,
              color: SetflowColors.ink,
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            '심사 완료!',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          const Text(
            '서류 심사가 성공적으로 완료되었습니다.\n공식 인증 배지와 함께 코칭을 시작해보세요!',
            textAlign: TextAlign.center,
            style: TextStyle(color: SetflowColors.secondaryText, height: 1.5),
          ),
          const SizedBox(height: 32),
          PrimaryButton(
            label: '코칭 시작하기',
            icon: Icons.rocket_launch_rounded,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }
}
