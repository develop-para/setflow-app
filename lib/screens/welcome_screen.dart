import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/business_repository.dart';
import '../services/auth_service.dart';
import '../services/trainer_document_picker.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import 'email_auth_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final authService = Auth.instance;
  StreamSubscription<AuthChange>? authSubscription;
  bool isSubmitting = false;
  bool awaitingOAuth = false;
  String? submitError;

  @override
  void initState() {
    super.initState();
    authSubscription = authService.authChanges.listen((change) {
      if (awaitingOAuth && change.event == AuthEvent.signedIn) {
        unawaited(_completeAuthentication());
      }
    });
  }

  @override
  void dispose() {
    unawaited(authSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reached from settings, so it is a pushed route that needs a way back.
    final canClose = Navigator.of(context).canPop();
    return Scaffold(
      appBar: canClose
          ? AppBar(
              leading: IconButton(
                tooltip: '닫기',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
              ),
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            SetflowSpacing.gutter,
            8,
            SetflowSpacing.gutter,
            24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: SetflowWordmark(fontSize: SetflowFontSize.display),
              ),
              const SizedBox(height: SetflowSpacing.md),
              Text(
                '로그인하고 오늘의 운동을 시작하세요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: SetflowSpacing.huge),
              if (submitError != null) ...[
                _OnboardingAlert(
                  message: submitError!,
                  color: context.setflowColors.error,
                  icon: Icons.error_outline_rounded,
                ),
                const SizedBox(height: SetflowSpacing.lg),
              ],
              AppButton(
                key: const Key('welcome-email-sign-up'),
                label: '이메일로 회원가입',
                icon: Icons.mail_outline_rounded,
                onPressed: isSubmitting
                    ? null
                    : () => _openEmailAuth(EmailAuthMode.signUp),
                isLoading: isSubmitting && !awaitingOAuth,
              ),
              const SizedBox(height: SetflowSpacing.sm),
              TextButton(
                key: const Key('welcome-email-sign-in'),
                onPressed: isSubmitting
                    ? null
                    : () => _openEmailAuth(EmailAuthMode.signIn),
                child: const Text('이미 계정이 있나요? 로그인'),
              ),
              // Only providers that can actually complete a sign-in appear.
              // A disabled button teaches nothing and invites a tap that fails;
              // when a provider is enabled these show up on their own.
              ..._socialSection(context),
              const SizedBox(height: SetflowSpacing.lg),
              Text(
                '가입하면 기록이 계정에 안전하게 백업되고, 본인만 접근할 수 있어요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: SetflowFontSize.caption,
                  height: 1.45,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The divider plus one button per configured provider — or nothing at all.
  ///
  /// `isConfigured` is false unless the provider is switched on for this build
  /// *and* registered in the backend, so an empty list here means social
  /// sign-in genuinely cannot work yet.
  List<Widget> _socialSection(BuildContext context) {
    const providers = <(SocialLoginProvider, String, AppButtonVariant)>[
      (SocialLoginProvider.kakao, '카카오로 계속', AppButtonVariant.tonal),
      (SocialLoginProvider.google, 'Google로 계속', AppButtonVariant.outlined),
      (SocialLoginProvider.naver, '네이버로 계속', AppButtonVariant.outlined),
    ];
    final available = providers
        .where((provider) => authService.isConfigured(provider.$1))
        .toList();
    if (available.isEmpty) return const [];

    return [
      const SizedBox(height: SetflowSpacing.xl),
      Row(
        children: [
          Expanded(child: Divider(color: Theme.of(context).dividerColor)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: SetflowSpacing.md),
            child: Text(
              'SNS 계정으로 계속',
              style: TextStyle(
                fontSize: SetflowFontSize.caption,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Divider(color: Theme.of(context).dividerColor)),
        ],
      ),
      const SizedBox(height: SetflowSpacing.lg),
      for (final (provider, label, variant) in available) ...[
        AppButton(
          key: ValueKey('social-${provider.name}'),
          label: label,
          onPressed: isSubmitting ? null : () => _startSocialLogin(provider),
          variant: variant,
          isLoading: isSubmitting && awaitingOAuth,
        ),
        const SizedBox(height: SetflowSpacing.md),
      ],
    ];
  }

  Future<void> _openEmailAuth(EmailAuthMode mode) async {
    final state = AppScope.of(context);
    final authenticated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EmailAuthScreen(initialMode: mode)),
    );
    if (authenticated == true && mounted) {
      await _completeAuthentication();
    } else {
      // This screen no longer collects a profile to stage — the onboarding
      // wizard is gone — but a cancelled sign-in must still drop anything
      // another surface staged.
      state.clearStagedMemberProfileForAuthentication();
    }
  }

  Future<void> _startSocialLogin(SocialLoginProvider provider) async {
    if (isSubmitting) return;
    final state = AppScope.of(context);
    setState(() {
      isSubmitting = true;
      awaitingOAuth = true;
      submitError = null;
    });
    try {
      final launched = await authService.signInWithSocial(provider);
      if (!launched) {
        throw const AuthFailure('로그인 화면을 열지 못했어요. 다시 시도해주세요.');
      }
    } catch (error) {
      state.clearStagedMemberProfileForAuthentication();
      if (mounted) {
        setState(() {
          isSubmitting = false;
          awaitingOAuth = false;
          submitError = authService.messageFor(error);
        });
      }
    }
  }

  Future<void> _completeAuthentication() async {
    if (!mounted || authService.currentUser == null) return;
    setState(() {
      isSubmitting = true;
      awaitingOAuth = false;
      submitError = null;
    });
    final state = AppScope.of(context);
    try {
      await state.syncAfterAuthentication();
      if (!mounted) return;
      AppSnackbar.success(context, '로그인됐어요. 기록을 안전하게 동기화합니다.');
      // The server-resolved role drives the shell. Without a live business
      // repository nothing resolves it, so fall back to the member shell.
      if (state.role == UserRole.guest) state.chooseRole(UserRole.member);
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop(true);
        return;
      }
      if (mounted) setState(() => isSubmitting = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          isSubmitting = false;
          submitError = '로그인은 완료됐지만 기록 동기화에 실패했어요. 다시 시도해주세요.';
        });
      }
    }
  }
}

class BusinessSetupScreen extends StatefulWidget {
  const BusinessSetupScreen({
    required this.role,
    this.trainerDocumentPicker,
    super.key,
  });
  final UserRole role;
  final TrainerDocumentPicker? trainerDocumentPicker;

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
  final uploadedDocs = <int, PickedTrainerDocument>{};
  TrainerApplicationDocumentType certificationDocumentType =
      TrainerApplicationDocumentType.nationalCertificate;
  _GymStep gymStep = _GymStep.register;
  bool gymDocUploaded = false;
  bool gymHometaxVerified = false;
  bool isSubmitting = false;
  bool editingRejectedApplication = false;
  String? submitError;

  TrainerDocumentPicker get _trainerDocumentPicker =>
      widget.trainerDocumentPicker ?? ImagePickerTrainerDocumentPicker();

  @override
  void dispose() {
    nameController.dispose();
    numberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (state.usesLiveBusinessData && !editingRejectedApplication) {
      final application = widget.role == UserRole.trainer
          ? state.businessAccess?.trainerApplication
          : state.businessAccess?.gymApplication;
      if (application?.status == BusinessApplicationStatus.pending ||
          application?.status == BusinessApplicationStatus.rejected) {
        return _buildExistingApplication(application!);
      }
    }
    if (widget.role != UserRole.trainer) {
      return _buildGymWizard(context);
    }
    return _buildTrainerWizard(context);
  }

  Widget _buildExistingApplication(BusinessApplication application) {
    final pending = application.status == BusinessApplicationStatus.pending;
    final accent = pending
        ? context.setflowColors.orange
        : context.setflowColors.error;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '닫기',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(widget.role == UserRole.trainer ? '트레이너 등록' : '센터 등록'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: SetflowInsets.pageForm,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                pending
                    ? Icons.hourglass_top_rounded
                    : Icons.error_outline_rounded,
                size: 42,
                color: accent,
              ),
              const SizedBox(height: SetflowSpacing.xxl),
              Text(
                pending ? '관리자 심사 중이에요' : '신청이 반려됐어요',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: SetflowSpacing.sm),
              Text(
                pending
                    ? '접수된 신청서를 확인하고 있습니다. 같은 신청을 다시 제출하지 않아도 돼요.'
                    : application.rejectReason ?? '등록 정보를 보완한 뒤 다시 신청해주세요.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: SetflowSpacing.xxl),
              if (pending)
                AppButton(
                  label: '확인',
                  onPressed: () => Navigator.maybePop(context),
                )
              else
                AppButton(
                  label: '정보 보완 후 다시 신청',
                  icon: Icons.edit_outlined,
                  onPressed: () {
                    setState(() => editingRejectedApplication = true);
                  },
                ),
            ],
          ),
        ),
      ),
    );
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
    final live = AppScope.of(context).usesLiveBusinessData;
    final filled =
        nameController.text.trim().isNotEmpty &&
        numberController.text.trim().isNotEmpty;
    return Form(
      key: businessFormKey,
      child: SingleChildScrollView(
        key: const ValueKey('gymRegister'),
        padding: const EdgeInsets.fromLTRB(
          SetflowSpacing.gutter,
          12,
          SetflowSpacing.gutter,
          32,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: context.setflowColors.purple.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(SetflowRadii.lg),
              ),
              child: Icon(Icons.apartment, color: context.setflowColors.purple),
            ),
            const SizedBox(height: SetflowSpacing.xxl),
            const Text(
              '헬스장 등록하기',
              style: TextStyle(
                fontSize: SetflowFontSize.display,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: SetflowSpacing.sm),
            Text(
              '센터 운영과 회원 관리를 한곳에서 시작하세요.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: SetflowSpacing.section),
            AppTextField(
              controller: nameController,
              onChanged: (_) => setState(() {}),
              label: '헬스장명',
              hint: '예: 세트플로우 피트니스 강남점',
              textInputAction: TextInputAction.next,
              validator: (value) => _requiredValidator(value, '헬스장명'),
            ),
            const SizedBox(height: SetflowSpacing.md2),
            AppTextField(
              controller: numberController,
              onChanged: (_) => setState(() {}),
              label: '사업자등록번호',
              hint: '숫자 10자리',
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              validator: _gymNumberValidator,
            ),
            const SizedBox(height: SetflowSpacing.section),
            PrimaryButton(
              label: live ? '신청 내용 확인' : '다음',
              icon: live
                  ? Icons.fact_check_outlined
                  : Icons.arrow_forward_rounded,
              onPressed: filled
                  ? () {
                      if (businessFormKey.currentState?.validate() ?? false) {
                        setState(
                          () => gymStep = live
                              ? _GymStep.complete
                              : _GymStep.docs,
                        );
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
    final live = AppScope.of(context).usesLiveBusinessData;
    return SingleChildScrollView(
      key: const ValueKey('gymDocs'),
      padding: const EdgeInsets.fromLTRB(
        SetflowSpacing.gutter,
        12,
        SetflowSpacing.gutter,
        32,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (live) ...[
            _OnboardingAlert(
              message: '사업자 서류 업로드는 서버 연동 준비 중이에요.',
              color: context.setflowColors.orange,
              icon: Icons.cloud_off_outlined,
            ),
            const SizedBox(height: SetflowSpacing.lg),
          ],
          const Text(
            '사업자등록증을\n제출해주세요',
            style: TextStyle(
              fontSize: SetflowFontSize.display,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: SetflowSpacing.sm2),
          Text(
            '원활한 정산과 안전한 센터 운영을 위해 필요해요.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: SetflowSpacing.xxl2),
          SetflowCard(
            onTap: live
                ? null
                : () => setState(() => gymDocUploaded = !gymDocUploaded),
            child: Row(
              children: [
                Icon(
                  gymDocUploaded
                      ? Icons.check_circle
                      : Icons.upload_file_rounded,
                  color: gymDocUploaded
                      ? context.setflowColors.success
                      : context.setflowColors.purple,
                ),
                const SizedBox(width: SetflowSpacing.md),
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
                        ? context.setflowColors.success
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.xxl),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: SetflowColors.soft,
              borderRadius: BorderRadius.circular(SetflowRadii.md),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 20,
                  color: context.setflowColors.success,
                ),
                const SizedBox(width: SetflowSpacing.sm2),
                Expanded(
                  child: Text(
                    live
                        ? '실제 파일 업로드가 연결되기 전에는 제출 완료 상태를 만들지 않아요.'
                        : '실제 파일 업로드 없이 데모로 진행됩니다. 카드를 눌러 제출 상태를 전환해보세요.',
                    style: TextStyle(
                      fontSize: SetflowFontSize.caption,
                      height: 1.45,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.section),
          if (submitError != null) ...[
            _OnboardingAlert(
              message: submitError!,
              color: context.setflowColors.error,
              icon: Icons.error_outline_rounded,
            ),
            const SizedBox(height: SetflowSpacing.lg),
          ],
          AppButton(
            label: live ? '서버 연동 준비 중' : '서류 제출하기',
            icon: Icons.arrow_forward_rounded,
            isLoading: isSubmitting,
            onPressed: !live && gymDocUploaded ? _submitGymDocuments : null,
          ),
        ],
      ),
    );
  }

  Widget _gymHometax(BuildContext context) {
    final live = AppScope.of(context).usesLiveBusinessData;
    final bizNumber = numberController.text.trim();
    return SingleChildScrollView(
      key: const ValueKey('gymHometax'),
      padding: const EdgeInsets.fromLTRB(
        SetflowSpacing.gutter,
        12,
        SetflowSpacing.gutter,
        32,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: context.setflowColors.purple.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(SetflowRadii.lg),
            ),
            child: Icon(
              Icons.account_balance_rounded,
              color: context.setflowColors.purple,
            ),
          ),
          const SizedBox(height: SetflowSpacing.xxl),
          const Text(
            '홈택스 사업자 인증',
            style: TextStyle(
              fontSize: SetflowFontSize.display,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: SetflowSpacing.sm),
          Text(
            live ? '국세청 사업자 상태 조회 서버 연동을 준비 중이에요.' : '국세청 홈택스 인증 흐름을 데모로 확인해요.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: SetflowSpacing.xxl2),
          SetflowCard(
            child: Row(
              children: [
                Icon(
                  Icons.business_rounded,
                  color: context.setflowColors.purple,
                ),
                const SizedBox(width: SetflowSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '사업자등록번호',
                        style: TextStyle(
                          fontSize: SetflowFontSize.small,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: SetflowSpacing.xxs),
                      Text(
                        bizNumber.isEmpty
                            ? '미입력'
                            : _formatBusinessNumber(bizNumber),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.xxl),
          if (!gymHometaxVerified)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: SetflowColors.soft,
                borderRadius: BorderRadius.circular(SetflowRadii.md),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 20,
                    color: context.setflowColors.purple,
                  ),
                  const SizedBox(width: SetflowSpacing.sm2),
                  Expanded(
                    child: Text(
                      live
                          ? '실제 사업자 조회가 연결되기 전에는 인증 완료 상태를 만들지 않아요.'
                          : '안전한 코칭 환경을 위해 실제 영업 중인 사업자만 인증됩니다. 데모에서는 버튼을 누르면 바로 인증됩니다.',
                      style: TextStyle(
                        fontSize: SetflowFontSize.caption,
                        height: 1.45,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                color: context.setflowColors.success.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(SetflowRadii.md),
                border: Border.all(
                  color: context.setflowColors.success.withValues(alpha: .25),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 20,
                    color: context.setflowColors.success,
                  ),
                  SizedBox(width: SetflowSpacing.sm2),
                  Expanded(
                    child: Text(
                      '인증 완료! 국세청 홈택스 기준 정상 영업 중인 사업자입니다.',
                      style: TextStyle(
                        fontSize: SetflowFontSize.caption,
                        height: 1.45,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: SetflowSpacing.section),
          if (!gymHometaxVerified)
            AppButton(
              label: live ? '서버 연동 준비 중' : '홈택스 인증하기',
              icon: Icons.fact_check_rounded,
              isLoading: isSubmitting,
              onPressed: live || bizNumber.isEmpty ? null : _verifyHometax,
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
    final live = AppScope.of(context).usesLiveBusinessData;
    return SingleChildScrollView(
      key: const ValueKey('gymComplete'),
      padding: const EdgeInsets.fromLTRB(
        SetflowSpacing.gutter,
        32,
        SetflowSpacing.gutter,
        32,
      ),
      child: Column(
        children: [
          Icon(Icons.verified_rounded, size: 48, color: SetflowColors.ink),
          const SizedBox(height: SetflowSpacing.xxl2),
          Text(
            live ? '센터 신청 준비 완료' : '가입 심사 완료!',
            style: TextStyle(
              fontSize: SetflowFontSize.display,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: SetflowSpacing.md),
          Text(
            live
                ? '신청서를 제출하면 관리자가 사업자 정보를 확인합니다.\n승인 후 센터 운영 화면이 자동으로 열려요.'
                : '센터 인증이 성공적으로 완료되었습니다.\n지금 바로 회원과 트레이너 관리를 시작해보세요!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: SetflowSpacing.section),
          AppButton(
            label: live ? '센터 신청 제출' : '운영 시작',
            icon: live ? Icons.send_rounded : Icons.rocket_launch_rounded,
            onPressed: () =>
                _completeBusiness(live ? '센터 인증 신청이 접수됐어요.' : '센터 등록이 완료됐어요.'),
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
    final live = AppScope.of(context).usesLiveBusinessData;
    final filled =
        nameController.text.trim().isNotEmpty &&
        numberController.text.trim().isNotEmpty;
    return Form(
      key: businessFormKey,
      child: SingleChildScrollView(
        key: const ValueKey('trainerRegister'),
        padding: const EdgeInsets.fromLTRB(
          SetflowSpacing.gutter,
          12,
          SetflowSpacing.gutter,
          32,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: context.setflowColors.blue.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(SetflowRadii.lg),
              ),
              child: Icon(
                Icons.fitness_center,
                color: context.setflowColors.blue,
              ),
            ),
            const SizedBox(height: SetflowSpacing.xxl),
            const Text(
              '트레이너로 시작하기',
              style: TextStyle(
                fontSize: SetflowFontSize.display,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: SetflowSpacing.sm),
            Text(
              '인증 배지로 신뢰받는 코칭을 시작하세요.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: SetflowSpacing.section),
            AppTextField(
              controller: nameController,
              onChanged: (_) => setState(() {}),
              label: '이름',
              hint: '실명을 입력해주세요',
              textInputAction: TextInputAction.next,
              validator: (value) => _requiredValidator(value, '이름'),
            ),
            const SizedBox(height: SetflowSpacing.md2),
            AppTextField(
              controller: numberController,
              onChanged: (_) => setState(() {}),
              label: '자격증 번호',
              hint: '예: 생활스포츠지도사 123456',
              validator: _trainerNumberValidator,
            ),
            const SizedBox(height: SetflowSpacing.section),
            AppButton(
              label: live ? '다음 · 서류 제출' : '다음',
              icon: Icons.arrow_forward_rounded,
              isLoading: isSubmitting,
              onPressed: filled
                  ? () async {
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
    final live = AppScope.of(context).usesLiveBusinessData;
    const docLabels = ['자격증 서류 (국가/민간)', '신분증 사본 (필수)'];
    return SingleChildScrollView(
      key: const ValueKey('trainerDocs'),
      padding: const EdgeInsets.fromLTRB(
        SetflowSpacing.gutter,
        12,
        SetflowSpacing.gutter,
        32,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '인증 서류를\n제출해주세요',
            style: TextStyle(
              fontSize: SetflowFontSize.display,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: SetflowSpacing.sm2),
          Text(
            '신뢰할 수 있는 코칭 환경을 위해 최소 2종의 서류가 필요해요.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: SetflowSpacing.xxl2),
          if (live) ...[
            DropdownButtonFormField<TrainerApplicationDocumentType>(
              key: const Key('trainer-certificate-type'),
              initialValue: certificationDocumentType,
              decoration: const InputDecoration(labelText: '자격증 구분'),
              items: const [
                DropdownMenuItem(
                  value: TrainerApplicationDocumentType.nationalCertificate,
                  child: Text('국가 자격증'),
                ),
                DropdownMenuItem(
                  value: TrainerApplicationDocumentType.privateCertificate,
                  child: Text('민간 자격증'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => certificationDocumentType = value);
                }
              },
            ),
            const SizedBox(height: SetflowSpacing.md2),
          ],
          ...List.generate(docLabels.length, (index) {
            final uploaded = uploadedDocs.containsKey(index);
            final document = uploadedDocs[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SetflowCard(
                key: Key('trainer-document-$index'),
                onTap: live
                    ? () => _pickTrainerDocument(index)
                    : () => setState(() {
                        if (uploaded) {
                          uploadedDocs.remove(index);
                        } else {
                          uploadedDocs[index] = PickedTrainerDocument(
                            bytes: Uint8List.fromList(const [1]),
                            fileName: 'demo-document.jpg',
                            contentType: 'image/jpeg',
                          );
                        }
                      }),
                child: Row(
                  children: [
                    Icon(
                      uploaded ? Icons.check_circle : Icons.upload_file_rounded,
                      color: uploaded
                          ? context.setflowColors.success
                          : context.setflowColors.blue,
                    ),
                    const SizedBox(width: SetflowSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            docLabels[index],
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          if (document != null)
                            Text(
                              document.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: SetflowFontSize.small,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      uploaded ? '업로드됨' : '업로드',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: uploaded
                            ? context.setflowColors.success
                            : Theme.of(context).colorScheme.onSurfaceVariant,
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
              borderRadius: BorderRadius.circular(SetflowRadii.md),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 20,
                  color: context.setflowColors.success,
                ),
                const SizedBox(width: SetflowSpacing.sm2),
                Expanded(
                  child: Text(
                    live
                        ? '카드를 눌러 카메라로 촬영하거나 갤러리 이미지를 선택하세요. 파일은 비공개 저장소에 업로드됩니다.'
                        : '데모에서는 카드를 눌러 서류 제출 상태를 전환할 수 있어요.',
                    style: TextStyle(
                      fontSize: SetflowFontSize.caption,
                      height: 1.45,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.section),
          if (submitError != null) ...[
            _OnboardingAlert(
              message: submitError!,
              color: context.setflowColors.error,
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
    final live = AppScope.of(context).usesLiveBusinessData;
    return SingleChildScrollView(
      key: const ValueKey('trainerPending'),
      padding: const EdgeInsets.fromLTRB(
        SetflowSpacing.gutter,
        24,
        SetflowSpacing.gutter,
        32,
      ),
      child: Column(
        children: [
          Icon(
            Icons.search_rounded,
            size: 40,
            color: context.setflowColors.blue,
          ),
          const SizedBox(height: SetflowSpacing.xxl),
          const Text(
            '서류 심사가\n진행 중입니다',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: SetflowFontSize.headlineLarge,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: SetflowSpacing.md),
          Text(
            '제출해주신 서류를 확인하고 있어요.\n영업일 기준 3일 이내 완료될 예정입니다.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: SetflowSpacing.section),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SetflowColors.soft,
              borderRadius: BorderRadius.circular(SetflowRadii.lg),
            ),
            child: live
                ? Column(
                    children: [
                      Icon(Icons.admin_panel_settings_outlined),
                      SizedBox(height: SetflowSpacing.sm),
                      Text(
                        '승인 권한은 관리자에게만 있어요',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: SetflowSpacing.xs),
                      Text(
                        '심사 결과는 계정에 자동 반영됩니다.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: SetflowFontSize.caption,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      const Text(
                        '데모 시뮬레이션',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: SetflowSpacing.xs),
                      Text(
                        '심사 결과를 직접 선택해보세요.',
                        style: TextStyle(
                          fontSize: SetflowFontSize.caption,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: SetflowSpacing.lg),
                      Row(
                        children: [
                          Expanded(
                            child: AppButton(
                              label: '심사 승인',
                              icon: Icons.check_circle_outline,
                              onPressed: () {
                                AppSnackbar.success(context, '트레이너 심사가 승인됐어요.');
                                setState(
                                  () => trainerStep = _TrainerStep.complete,
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: SetflowSpacing.md),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => setState(
                                () => trainerStep = _TrainerStep.rejected,
                              ),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 54),
                                foregroundColor: context.setflowColors.error,
                                side: BorderSide(
                                  color: context.setflowColors.error,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    SetflowRadii.lg,
                                  ),
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
          if (live) ...[
            const SizedBox(height: SetflowSpacing.xl),
            AppButton(
              label: '확인',
              icon: Icons.check_rounded,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ],
      ),
    );
  }

  Widget _trainerRejected(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('trainerRejected'),
      padding: const EdgeInsets.fromLTRB(
        SetflowSpacing.gutter,
        24,
        SetflowSpacing.gutter,
        32,
      ),
      child: Column(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 38,
            color: context.setflowColors.error,
          ),
          const SizedBox(height: SetflowSpacing.xxl),
          const Text(
            '서류 심사 반려',
            style: TextStyle(
              fontSize: SetflowFontSize.headlineLarge,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: SetflowSpacing.md),
          Text(
            '제출해주신 서류에 보완이 필요한 부분이 있어\n부득이하게 심사가 반려되었습니다.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: SetflowSpacing.xxl),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.setflowColors.error.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(SetflowRadii.md),
              border: Border.all(
                color: context.setflowColors.error.withValues(alpha: .2),
              ),
            ),
            child: Text(
              '반려 사유: 제출된 서류의 이미지가 흐려 식별이 어렵습니다. 선명하게 재촬영하여 업로드해주세요.',
              style: TextStyle(
                fontSize: SetflowFontSize.caption,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: SetflowSpacing.section),
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
      padding: const EdgeInsets.fromLTRB(
        SetflowSpacing.gutter,
        32,
        SetflowSpacing.gutter,
        32,
      ),
      child: Column(
        children: [
          Icon(Icons.verified_rounded, size: 48, color: SetflowColors.ink),
          const SizedBox(height: SetflowSpacing.xxl2),
          const Text(
            '심사 완료!',
            style: TextStyle(
              fontSize: SetflowFontSize.display,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: SetflowSpacing.md),
          Text(
            '서류 심사가 성공적으로 완료되었습니다.\n공식 인증 배지와 함께 코칭을 시작해보세요!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: SetflowSpacing.section),
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
    final live = AppScope.of(context).usesLiveBusinessData;
    if (widget.role == UserRole.trainer) {
      if (live && trainerStep == _TrainerStep.pending) {
        Navigator.of(context).pop(true);
        return;
      }
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
        _GymStep.complete => live ? _GymStep.register : _GymStep.hometax,
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
    if (AppScope.of(context).usesLiveBusinessData) {
      setState(() {
        submitError = '사업자 서류 업로드는 서버 연동 준비 중이에요.';
      });
      return;
    }
    await _runSubmission(
      successMessage: '사업자등록증이 안전하게 제출됐어요.',
      onSuccess: () => gymStep = _GymStep.hometax,
    );
  }

  Future<void> _verifyHometax() async {
    if (AppScope.of(context).usesLiveBusinessData) {
      setState(() {
        submitError = '홈택스 사업자 조회는 서버 연동 준비 중이에요.';
      });
      return;
    }
    await _runSubmission(
      successMessage: '홈택스 사업자 인증이 완료됐어요.',
      delay: const Duration(milliseconds: 850),
      onSuccess: () => gymHometaxVerified = true,
    );
  }

  Future<void> _pickTrainerDocument(int index) async {
    final source = await showSetflowSheet<TrainerDocumentSource>(
      context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              key: const Key('trainer-document-camera'),
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('카메라로 촬영'),
              onTap: () =>
                  Navigator.pop(sheetContext, TrainerDocumentSource.camera),
            ),
            ListTile(
              key: const Key('trainer-document-gallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('갤러리에서 선택'),
              onTap: () =>
                  Navigator.pop(sheetContext, TrainerDocumentSource.gallery),
            ),
            if (uploadedDocs.containsKey(index))
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: context.setflowColors.error,
                ),
                title: const Text('선택한 파일 제거'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  setState(() => uploadedDocs.remove(index));
                },
              ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      final document = await _trainerDocumentPicker.pick(source);
      if (document == null || !mounted) return;
      setState(() {
        uploadedDocs[index] = document;
        submitError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        submitError = error is FormatException
            ? error.message.toString()
            : '이미지를 불러오지 못했어요. 다시 시도해주세요.';
      });
    }
  }

  List<TrainerApplicationDocumentInput> _trainerDocumentInputs() {
    final certification = uploadedDocs[0];
    final identity = uploadedDocs[1];
    if (certification == null || identity == null) {
      throw StateError('자격증과 신분증 이미지를 모두 선택해주세요.');
    }
    return [
      TrainerApplicationDocumentInput(
        type: certificationDocumentType,
        bytes: certification.bytes,
        fileName: certification.fileName,
        contentType: certification.contentType,
      ),
      TrainerApplicationDocumentInput(
        type: TrainerApplicationDocumentType.identity,
        bytes: identity.bytes,
        fileName: identity.fileName,
        contentType: identity.contentType,
      ),
    ];
  }

  Future<void> _submitTrainerDocuments() async {
    final state = AppScope.of(context);
    if (state.usesLiveBusinessData) {
      if (isSubmitting) return;
      setState(() {
        isSubmitting = true;
        submitError = null;
      });
      try {
        if (!await _ensureBusinessAuthentication()) return;
        await state.submitTrainerBusinessApplication(
          displayName: nameController.text.trim(),
          credentialNumber: numberController.text.trim(),
          documents: _trainerDocumentInputs(),
        );
        if (!mounted) return;
        setState(() => trainerStep = _TrainerStep.pending);
        AppSnackbar.success(context, '트레이너 인증 신청이 접수됐어요.');
      } catch (_) {
        if (mounted) {
          setState(() => submitError = '신청을 제출하지 못했어요. 잠시 후 다시 시도해주세요.');
        }
      } finally {
        if (mounted) setState(() => isSubmitting = false);
      }
      return;
    }
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

  Future<void> _completeBusiness(String message) async {
    if (!await _ensureBusinessAuthentication()) return;
    if (!mounted) return;
    final state = AppScope.of(context);
    if (state.usesLiveBusinessData) {
      try {
        if (widget.role == UserRole.gym) {
          await state.submitGymBusinessApplication(
            gymName: nameController.text.trim(),
            businessNumber: numberController.text.trim(),
          );
        } else {
          await state.submitTrainerBusinessApplication(
            displayName: nameController.text.trim(),
            credentialNumber: numberController.text.trim(),
            documents: _trainerDocumentInputs(),
          );
        }
      } catch (_) {
        if (mounted) {
          AppSnackbar.error(context, '인증 신청을 제출하지 못했어요. 입력 내용을 확인해주세요.');
        }
        return;
      }
      if (!mounted) return;
      AppSnackbar.success(context, message);
      Navigator.of(context).pop(true);
      return;
    }
    if (widget.role == UserRole.gym) {
      state.completeGymOnboarding(
        displayName: nameController.text.trim(),
        businessNumber: numberController.text.trim(),
      );
    }
    AppSnackbar.success(context, message);
    Navigator.of(context).pop(true);
  }

  Future<bool> _ensureBusinessAuthentication() async {
    if (Auth.instance.currentUser == null) {
      final authenticated = await Navigator.of(
        context,
      ).push<bool>(MaterialPageRoute(builder: (_) => const EmailAuthScreen()));
      if (authenticated != true || !mounted) return false;
      try {
        await AppScope.of(context).syncAfterAuthentication();
      } catch (_) {
        if (mounted) {
          AppSnackbar.error(context, '로그인은 완료됐지만 기록 동기화에 실패했어요.');
        }
        return false;
      }
    }
    return mounted;
  }

  String _formatBusinessNumber(String value) {
    if (value.length != 10) return value;
    return '${value.substring(0, 3)}-${value.substring(3, 5)}-${value.substring(5)}';
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
              margin: EdgeInsets.only(right: index == total - 2 ? 0 : 6),
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
