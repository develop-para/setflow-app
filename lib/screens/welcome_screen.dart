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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        actions: [
          if (step == 1)
            TextButton(onPressed: _finish, child: const Text('건너뛰기')),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: step == 0 ? _preferences(context) : _goals(context),
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
            label: '시작하기',
            onPressed: goals.isEmpty ? null : _finish,
          ),
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

class _BusinessSetupScreenState extends State<BusinessSetupScreen> {
  final nameController = TextEditingController();
  final numberController = TextEditingController();

  @override
  void dispose() {
    nameController.dispose();
    numberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trainer = widget.role == UserRole.trainer;
    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: (trainer ? SetflowColors.blue : SetflowColors.purple)
                    .withValues(alpha: .12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                trainer ? Icons.fitness_center : Icons.apartment,
                color: trainer ? SetflowColors.blue : SetflowColors.purple,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              trainer ? '트레이너로 시작하기' : '헬스장 등록하기',
              style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              trainer ? '인증 배지로 신뢰받는 코칭을 시작하세요.' : '센터 운영과 회원 관리를 한곳에서 시작하세요.',
              style: const TextStyle(
                color: SetflowColors.secondaryText,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: nameController,
              decoration: InputDecoration(labelText: trainer ? '이름' : '헬스장명'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: numberController,
              decoration: InputDecoration(
                labelText: trainer ? '자격증 번호' : '사업자등록번호',
              ),
            ),
            const SizedBox(height: 14),
            SetflowCard(
              child: Row(
                children: [
                  Icon(
                    Icons.upload_file_rounded,
                    color: trainer ? SetflowColors.blue : SetflowColors.purple,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      trainer ? '자격증 서류 2종 업로드' : '사업자등록증 업로드',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const Icon(
                    Icons.add_circle_outline,
                    color: SetflowColors.disabled,
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
                      '데모에서는 인증 완료 상태로 바로 시작합니다. 실제 심사는 영업일 3일 이내 처리됩니다.',
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
              label: '인증 데모 시작',
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
  }
}
