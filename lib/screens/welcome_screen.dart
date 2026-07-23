import 'package:flutter/services.dart';
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
  final bodyFormKey = GlobalKey<FormState>();
  String unit = 'kg';
  int step = 0;
  final goals = <String>{};
  final heightController = TextEditingController();
  final weightController = TextEditingController();
  final ageController = TextEditingController();
  String? gender;
  bool isSubmitting = false;
  String? submitError;

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
        leading: IconButton(
          tooltip: '이전',
          onPressed: _goBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text('${step + 1} / 4'),
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SetflowSpacing.xxl),
            child: _OnboardingProgress(current: step + 1, total: 4),
          ),
          const SizedBox(height: SetflowSpacing.sm),
          Expanded(
            child: AnimatedSwitcher(
              duration: SetflowMotion.standard,
              switchInCurve: SetflowMotion.standardCurve,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(.04, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: switch (step) {
                0 => _preferences(context),
                1 => _goals(context),
                2 => _bodyProfile(context),
                _ => _signup(context),
              },
            ),
          ),
        ],
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
    return Form(
      key: bodyFormKey,
      child: SingleChildScrollView(
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
            AppTextField(
              controller: ageController,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              hint: '예: 29세',
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (value) => _optionalNumberValidator(
                value,
                minimum: 14,
                maximum: 100,
                label: '나이',
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
              onSelectionChanged: (value) =>
                  setState(() => gender = value.isEmpty ? null : value.first),
            ),
            const SizedBox(height: 20),
            const Text('키', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            AppTextField(
              controller: heightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              hint: '예: 175cm',
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^\d{0,3}\.?\d{0,1}'),
                ),
              ],
              validator: (value) => _optionalNumberValidator(
                value,
                minimum: 100,
                maximum: 250,
                label: '키',
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '체중 ($unit)',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            AppTextField(
              controller: weightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              hint: '예: 70$unit',
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^\d{0,3}\.?\d{0,1}'),
                ),
              ],
              validator: (value) => _optionalNumberValidator(
                value,
                minimum: unit == 'kg' ? 30 : 66,
                maximum: unit == 'kg' ? 300 : 660,
                label: '체중',
              ),
            ),
            const SizedBox(height: 30),
            PrimaryButton(
              label: '저장',
              icon: Icons.arrow_forward_rounded,
              onPressed: filled
                  ? () {
                      if (bodyFormKey.currentState?.validate() ?? false) {
                        setState(() => step = 3);
                      }
                    }
                  : null,
            ),
          ],
        ),
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
          if (submitError != null) ...[
            _OnboardingAlert(
              message: submitError!,
              color: SetflowColors.red,
              icon: Icons.error_outline_rounded,
            ),
            const SizedBox(height: SetflowSpacing.lg),
          ],
          AppButton(
            label: '카카오로 시작하기',
            onPressed: () => _submitMember('카카오'),
            isLoading: isSubmitting,
          ),
          const SizedBox(height: 12),
          AppButton(
            label: '구글로 시작하기',
            onPressed: () => _submitMember('구글'),
            variant: AppButtonVariant.outlined,
            isLoading: isSubmitting,
          ),
          const SizedBox(height: 12),
          AppButton(
            label: 'Apple로 시작하기',
            onPressed: () => _submitMember('Apple'),
            variant: AppButtonVariant.outlined,
            isLoading: isSubmitting,
          ),
          const SizedBox(height: 18),
          Center(
            child: TextButton(
              onPressed: isSubmitting ? null : () => _submitMember('이메일'),
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
          AppButton(
            label: '가입 없이 바로 시작',
            onPressed: isSubmitting ? null : _finish,
            variant: AppButtonVariant.tonal,
          ),
        ],
      ),
    );
  }

  void _goBack() {
    if (step == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      submitError = null;
      step--;
    });
  }

  String? _optionalNumberValidator(
    String? value, {
    required double minimum,
    required double maximum,
    required String label,
  }) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final number = double.tryParse(text);
    if (number == null) return '$label 값을 숫자로 입력해주세요.';
    if (number < minimum || number > maximum) {
      return '$label 값은 ${minimum.toStringAsFixed(0)}~${maximum.toStringAsFixed(0)} 범위로 입력해주세요.';
    }
    return null;
  }

  Future<void> _submitMember(String provider) async {
    if (isSubmitting) return;
    setState(() {
      isSubmitting = true;
      submitError = null;
    });
    try {
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;
      AppSnackbar.success(context, '$provider 연결이 완료됐어요.');
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => submitError = '가입 정보를 저장하지 못했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
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
  final businessFormKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final numberController = TextEditingController();
  _TrainerStep trainerStep = _TrainerStep.register;
  final uploadedDocs = <int>{};
  _GymStep gymStep = _GymStep.register;
  bool gymDocUploaded = false;
  bool gymHometaxVerified = false;
  bool isSubmitting = false;
  String? submitError;

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
    final current = switch (gymStep) {
      _GymStep.register => 1,
      _GymStep.docs => 2,
      _GymStep.hometax => 3,
      _GymStep.complete => 4,
    };
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '이전',
          onPressed: _goBusinessBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('센터 등록'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SetflowSpacing.xxl),
            child: _OnboardingProgress(current: current, total: 4),
          ),
          const SizedBox(height: SetflowSpacing.sm),
          Expanded(
            child: AnimatedSwitcher(
              duration: SetflowMotion.standard,
              switchInCurve: SetflowMotion.standardCurve,
              child: switch (gymStep) {
                _GymStep.register => _gymRegister(context),
                _GymStep.docs => _gymDocs(context),
                _GymStep.hometax => _gymHometax(context),
                _GymStep.complete => _gymComplete(context),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _gymRegister(BuildContext context) {
    final filled =
        nameController.text.trim().isNotEmpty &&
        numberController.text.trim().isNotEmpty;
    return Form(
      key: businessFormKey,
      child: SingleChildScrollView(
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
            AppTextField(
              controller: nameController,
              onChanged: (_) => setState(() {}),
              label: '헬스장명',
              hint: '예: 세트플로우 피트니스 강남점',
              textInputAction: TextInputAction.next,
              validator: (value) => _requiredValidator(value, '헬스장명'),
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: numberController,
              onChanged: (_) => setState(() {}),
              label: '사업자등록번호',
              hint: '숫자 10자리',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: _gymNumberValidator,
            ),
            const SizedBox(height: 30),
            PrimaryButton(
              label: '다음',
              icon: Icons.arrow_forward_rounded,
              onPressed: filled
                  ? () {
                      if (businessFormKey.currentState?.validate() ?? false) {
                        setState(() => gymStep = _GymStep.docs);
                      }
                    }
                  : null,
            ),
          ],
        ),
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
          if (submitError != null) ...[
            _OnboardingAlert(
              message: submitError!,
              color: SetflowColors.red,
              icon: Icons.error_outline_rounded,
            ),
            const SizedBox(height: SetflowSpacing.lg),
          ],
          AppButton(
            label: '서류 제출하기',
            icon: Icons.arrow_forward_rounded,
            isLoading: isSubmitting,
            onPressed: gymDocUploaded ? _submitGymDocuments : null,
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
                const Icon(Icons.business_rounded, color: SetflowColors.purple),
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
            AppButton(
              label: '홈택스 인증하기',
              icon: Icons.fact_check_rounded,
              isLoading: isSubmitting,
              onPressed: bizNumber.isEmpty ? null : _verifyHometax,
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
          AppButton(
            label: '센터 운영 시작하기',
            icon: Icons.rocket_launch_rounded,
            onPressed: () => _completeBusiness('센터 등록이 완료됐어요.'),
          ),
        ],
      ),
    );
  }

  Widget _buildTrainerWizard(BuildContext context) {
    final current = switch (trainerStep) {
      _TrainerStep.register => 1,
      _TrainerStep.docs => 2,
      _TrainerStep.pending => 3,
      _TrainerStep.rejected || _TrainerStep.complete => 4,
    };
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '이전',
          onPressed: _goBusinessBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('트레이너 등록'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SetflowSpacing.xxl),
            child: _OnboardingProgress(current: current, total: 4),
          ),
          const SizedBox(height: SetflowSpacing.sm),
          Expanded(
            child: AnimatedSwitcher(
              duration: SetflowMotion.standard,
              switchInCurve: SetflowMotion.standardCurve,
              child: switch (trainerStep) {
                _TrainerStep.register => _trainerRegister(context),
                _TrainerStep.docs => _trainerDocs(context),
                _TrainerStep.pending => _trainerPending(context),
                _TrainerStep.rejected => _trainerRejected(context),
                _TrainerStep.complete => _trainerComplete(context),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _trainerRegister(BuildContext context) {
    final filled =
        nameController.text.trim().isNotEmpty &&
        numberController.text.trim().isNotEmpty;
    return Form(
      key: businessFormKey,
      child: SingleChildScrollView(
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
              child: const Icon(
                Icons.fitness_center,
                color: SetflowColors.blue,
              ),
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
            AppTextField(
              controller: nameController,
              onChanged: (_) => setState(() {}),
              label: '이름',
              hint: '실명을 입력해주세요',
              textInputAction: TextInputAction.next,
              validator: (value) => _requiredValidator(value, '이름'),
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: numberController,
              onChanged: (_) => setState(() {}),
              label: '자격증 번호',
              hint: '예: 생활스포츠지도사 123456',
              validator: _trainerNumberValidator,
            ),
            const SizedBox(height: 30),
            PrimaryButton(
              label: '다음',
              icon: Icons.arrow_forward_rounded,
              onPressed: filled
                  ? () {
                      if (businessFormKey.currentState?.validate() ?? false) {
                        setState(() => trainerStep = _TrainerStep.docs);
                      }
                    }
                  : null,
            ),
          ],
        ),
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
          if (submitError != null) ...[
            _OnboardingAlert(
              message: submitError!,
              color: SetflowColors.red,
              icon: Icons.error_outline_rounded,
            ),
            const SizedBox(height: SetflowSpacing.lg),
          ],
          AppButton(
            label: '서류 제출하기',
            icon: Icons.arrow_forward_rounded,
            isLoading: isSubmitting,
            onPressed: uploadedDocs.length >= 2
                ? _submitTrainerDocuments
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
                      child: AppButton(
                        label: '심사 승인',
                        icon: Icons.check_circle_outline,
                        onPressed: () {
                          AppSnackbar.success(context, '트레이너 심사가 승인됐어요.');
                          setState(() => trainerStep = _TrainerStep.complete);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            setState(() => trainerStep = _TrainerStep.rejected),
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
          AppButton(
            label: '코칭 시작하기',
            icon: Icons.rocket_launch_rounded,
            onPressed: () => _completeBusiness('트레이너 등록이 완료됐어요.'),
          ),
        ],
      ),
    );
  }

  void _goBusinessBack() {
    submitError = null;
    if (widget.role == UserRole.trainer) {
      if (trainerStep == _TrainerStep.register) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        trainerStep = switch (trainerStep) {
          _TrainerStep.docs => _TrainerStep.register,
          _TrainerStep.pending ||
          _TrainerStep.rejected ||
          _TrainerStep.complete => _TrainerStep.docs,
          _TrainerStep.register => _TrainerStep.register,
        };
      });
      return;
    }
    if (gymStep == _GymStep.register) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      gymStep = switch (gymStep) {
        _GymStep.docs => _GymStep.register,
        _GymStep.hometax => _GymStep.docs,
        _GymStep.complete => _GymStep.hometax,
        _GymStep.register => _GymStep.register,
      };
    });
  }

  String? _requiredValidator(String? value, String label) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '$label을 입력해주세요.';
    if (text.length < 2) return '$label을 2자 이상 입력해주세요.';
    return null;
  }

  String? _trainerNumberValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '자격증 번호를 입력해주세요.';
    if (text.length < 4) return '자격증 번호를 4자 이상 입력해주세요.';
    return null;
  }

  String? _gymNumberValidator(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '사업자등록번호를 입력해주세요.';
    if (digits.length != 10) return '사업자등록번호 숫자 10자리를 입력해주세요.';
    return null;
  }

  Future<void> _submitGymDocuments() async {
    await _runSubmission(
      successMessage: '사업자등록증이 안전하게 제출됐어요.',
      onSuccess: () => gymStep = _GymStep.hometax,
    );
  }

  Future<void> _verifyHometax() async {
    await _runSubmission(
      successMessage: '홈택스 사업자 인증이 완료됐어요.',
      delay: const Duration(milliseconds: 850),
      onSuccess: () => gymHometaxVerified = true,
    );
  }

  Future<void> _submitTrainerDocuments() async {
    await _runSubmission(
      successMessage: '인증 서류가 제출됐어요.',
      onSuccess: () => trainerStep = _TrainerStep.pending,
    );
  }

  Future<void> _runSubmission({
    required String successMessage,
    required VoidCallback onSuccess,
    Duration delay = const Duration(milliseconds: 700),
  }) async {
    if (isSubmitting) return;
    setState(() {
      isSubmitting = true;
      submitError = null;
    });
    try {
      await Future<void>.delayed(delay);
      if (!mounted) return;
      setState(onSuccess);
      AppSnackbar.success(context, successMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() => submitError = '요청을 처리하지 못했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  void _completeBusiness(String message) {
    AppSnackbar.success(context, message);
    Navigator.of(context).pop(true);
  }
}

class _OnboardingProgress extends StatelessWidget {
  const _OnboardingProgress({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '가입 진행 단계 $current/$total',
      value: '${(current / total * 100).round()}%',
      child: Row(
        children: List.generate(total, (index) {
          final active = index < current;
          return Expanded(
            child: AnimatedContainer(
              duration: SetflowMotion.micro,
              curve: Curves.easeOut,
              height: 4,
              margin: EdgeInsets.only(right: index == total - 1 ? 0 : 6),
              decoration: BoxDecoration(
                color: active
                    ? theme.colorScheme.primary
                    : context.setflowColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(SetflowRadii.full),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _OnboardingAlert extends StatelessWidget {
  const _OnboardingAlert({
    required this.message,
    required this.color,
    required this.icon,
  });

  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(SetflowSpacing.md),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(SetflowRadii.md),
          border: Border.all(color: color.withValues(alpha: .24)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: SetflowSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
