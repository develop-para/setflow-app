import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/auth_notice.dart';
import '../widgets/common.dart';
import 'password_screens.dart';

enum EmailAuthMode { signUp, signIn }

class EmailAuthScreen extends StatefulWidget {
  const EmailAuthScreen({this.initialMode = EmailAuthMode.signUp, super.key});

  final EmailAuthMode initialMode;

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  /// A resend that can be spammed just gets the address rate-limited by the
  /// mail provider, which looks to the user like the app is broken.
  static const _resendCooldown = Duration(seconds: 60);

  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _auth = Auth.instance;

  late EmailAuthMode _mode = widget.initialMode;
  bool _submitting = false;
  bool _awaitingEmailConfirmation = false;
  bool _obscurePassword = true;
  String? _error;

  Timer? _resendTimer;
  int _resendSecondsLeft = 0;
  String? _resendNotice;

  bool get _isSignUp => _mode == EmailAuthMode.signUp;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _nicknameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_isSignUp ? '이메일 회원가입' : '이메일 로그인')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(SetflowSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        SetflowIcons.account,
                        size: 44,
                        color: theme.colorScheme.onSurface,
                      ),
                      const SizedBox(height: SetflowSpacing.lg),
                      Text(
                        _isSignUp ? '내 기록을 안전하게 보관해요' : '다시 만나서 반가워요',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (_isSignUp) ...[
                        const SizedBox(height: SetflowSpacing.sm),
                        Text(
                          '가입하면 기록이 계정에 백업돼요.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                      const SizedBox(height: SetflowSpacing.xl),
                      if (_awaitingEmailConfirmation) ...[
                        AuthNotice(
                          key: const ValueKey('auth-confirm-email'),
                          message:
                              '${_emailController.text.trim()} 으로 인증 메일을 보냈어요. '
                              '메일의 링크를 열면 로그인할 수 있어요.',
                          // The remedy for "the mail never came" belongs next
                          // to the message that says a mail was sent.
                          action: TextButton(
                            key: const ValueKey('auth-resend-confirmation'),
                            onPressed: _resendSecondsLeft > 0 || _submitting
                                ? null
                                : _resendConfirmation,
                            child: Text(
                              _resendSecondsLeft > 0
                                  ? '메일 다시 보내기 ($_resendSecondsLeft초)'
                                  : '메일이 안 왔어요 · 다시 보내기',
                            ),
                          ),
                        ),
                        const SizedBox(height: SetflowSpacing.md),
                      ],
                      if (_resendNotice != null) ...[
                        AuthNotice(
                          key: const ValueKey('auth-resend-notice'),
                          message: _resendNotice!,
                          tone: AuthNoticeTone.success,
                        ),
                        const SizedBox(height: SetflowSpacing.md),
                      ],
                      if (_error != null) ...[
                        AuthNotice(
                          key: const ValueKey('auth-error'),
                          message: _error!,
                          tone: AuthNoticeTone.danger,
                        ),
                        const SizedBox(height: SetflowSpacing.md),
                      ],
                      if (_isSignUp) ...[
                        AppTextField(
                          controller: _nicknameController,
                          label: '닉네임',
                          hint: '2자 이상',
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.nickname],
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            if (text.length < 2) return '닉네임을 2자 이상 입력해주세요.';
                            if (text.length > 30) return '닉네임은 30자 이하로 입력해주세요.';
                            return null;
                          },
                        ),
                        const SizedBox(height: SetflowSpacing.md),
                      ],
                      AppTextField(
                        controller: _emailController,
                        label: '이메일',
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        validator: validateEmailField,
                      ),
                      const SizedBox(height: SetflowSpacing.md),
                      AppTextField(
                        controller: _passwordController,
                        label: '비밀번호',
                        helperText: _isSignUp
                            ? '${AuthPasswordPolicy.minLength}자 이상 입력해주세요.'
                            : null,
                        obscureText: _obscurePassword,
                        textInputAction: _isSignUp
                            ? TextInputAction.next
                            : TextInputAction.done,
                        autofillHints: [
                          _isSignUp
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword ? '비밀번호 보기' : '비밀번호 숨기기',
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? SetflowIcons.passwordVisible
                                : SetflowIcons.passwordHidden,
                          ),
                        ),
                        // Sign-in must not enforce the current policy: someone
                        // whose password predates it still has to get in.
                        validator: _isSignUp
                            ? AuthPasswordPolicy.validate
                            : (value) => (value ?? '').isEmpty
                                  ? '비밀번호를 입력해주세요.'
                                  : null,
                        onSubmitted: _isSignUp ? null : (_) => _submit(),
                      ),
                      if (_isSignUp) ...[
                        const SizedBox(height: SetflowSpacing.md),
                        AppTextField(
                          controller: _confirmController,
                          label: '비밀번호 확인',
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.newPassword],
                          validator: (value) =>
                              value != _passwordController.text
                              ? '비밀번호가 일치하지 않아요.'
                              : null,
                          onSubmitted: (_) => _submit(),
                        ),
                      ],
                      if (!_isSignUp)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            key: const ValueKey('auth-forgot-password'),
                            onPressed: _submitting ? null : _openPasswordReset,
                            child: const Text('비밀번호를 잊으셨나요?'),
                          ),
                        ),
                      const SizedBox(height: SetflowSpacing.xl),
                      AppButton(
                        label: _isSignUp ? '회원가입' : '로그인',
                        icon: _isSignUp
                            ? SetflowIcons.signUp
                            : SetflowIcons.signIn,
                        isLoading: _submitting,
                        onPressed: _submitting ? null : _submit,
                      ),
                      const SizedBox(height: SetflowSpacing.md),
                      TextButton(
                        onPressed: _submitting ? null : _toggleMode,
                        child: Text(
                          _isSignUp ? '이미 계정이 있나요? 로그인' : '처음이신가요? 이메일 회원가입',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toggleMode() {
    setState(() {
      _mode = _isSignUp ? EmailAuthMode.signIn : EmailAuthMode.signUp;
      _error = null;
      _awaitingEmailConfirmation = false;
      _resendNotice = null;
    });
  }

  Future<void> _openPasswordReset() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PasswordResetRequestScreen(initialEmail: _emailController.text),
      ),
    );
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSecondsLeft = _resendCooldown.inSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendSecondsLeft--);
      if (_resendSecondsLeft <= 0) timer.cancel();
    });
  }

  Future<void> _resendConfirmation() async {
    setState(() {
      _submitting = true;
      _error = null;
      _resendNotice = null;
    });
    try {
      await _auth.resendConfirmationEmail(email: _emailController.text);
      if (!mounted) return;
      setState(() => _resendNotice = '인증 메일을 다시 보냈어요.');
      _startResendCooldown();
    } catch (error) {
      if (mounted) setState(() => _error = _auth.messageFor(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
      _resendNotice = null;
    });
    try {
      if (_isSignUp) {
        final result = await _auth.signUp(
          email: _emailController.text,
          password: _passwordController.text,
          nickname: _nicknameController.text,
        );
        if (!mounted) return;
        if (result.needsEmailConfirmation) {
          // The project requires email confirmation, so there is nothing to
          // sign in to yet. Say so instead of reporting a failure — the account
          // really was created.
          setState(() {
            _submitting = false;
            _awaitingEmailConfirmation = true;
            _error = null;
          });
          _startResendCooldown();
          return;
        }
      } else {
        await _auth.signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
        if (!mounted) return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = _auth.messageFor(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
