import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

enum EmailAuthMode { signUp, signIn }

class EmailAuthScreen extends StatefulWidget {
  const EmailAuthScreen({this.initialMode = EmailAuthMode.signUp, super.key});

  final EmailAuthMode initialMode;

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
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

  bool get _isSignUp => _mode == EmailAuthMode.signUp;

  @override
  void dispose() {
    _nicknameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                        Icons.lock_person_rounded,
                        size: 52,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: SetflowSpacing.lg),
                      Text(
                        _isSignUp ? '내 기록을 안전하게 보관해요' : '다시 만나서 반가워요',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      if (_isSignUp) ...[
                        const SizedBox(height: SetflowSpacing.sm),
                        Text(
                          '가입하면 기록이 계정에 백업돼요.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                      const SizedBox(height: SetflowSpacing.xl),
                      if (_awaitingEmailConfirmation) ...[
                        _AuthMessage(
                          key: const ValueKey('auth-confirm-email'),
                          message:
                              '${_emailController.text.trim()} 으로 인증 메일을 보냈어요. '
                              '메일의 링크를 열면 로그인할 수 있어요.',
                          color: SetflowColors.ink,
                          icon: Icons.mark_email_unread_rounded,
                        ),
                        const SizedBox(height: SetflowSpacing.md),
                      ],
                      if (_error != null) ...[
                        _AuthMessage(
                          message: _error!,
                          color: SetflowColors.red,
                          icon: Icons.error_outline_rounded,
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
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          if (!RegExp(
                            r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                          ).hasMatch(email)) {
                            return '올바른 이메일 주소를 입력해주세요.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: SetflowSpacing.md),
                      AppTextField(
                        controller: _passwordController,
                        label: '비밀번호',
                        helperText: _isSignUp ? '8자 이상 입력해주세요.' : null,
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
                                ? Icons.visibility_rounded
                                : Icons.visibility_off_rounded,
                          ),
                        ),
                        validator: (value) {
                          if ((value ?? '').length < 8) {
                            return '비밀번호를 8자 이상 입력해주세요.';
                          }
                          return null;
                        },
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
                      const SizedBox(height: SetflowSpacing.xl),
                      AppButton(
                        label: _isSignUp ? '회원가입' : '로그인',
                        icon: _isSignUp
                            ? Icons.person_add_alt_1_rounded
                            : Icons.login_rounded,
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
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
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

class _AuthMessage extends StatelessWidget {
  const _AuthMessage({
    required this.message,
    required this.color,
    required this.icon,
    super.key,
  });

  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(SetflowSpacing.md),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          border: Border.all(color: color.withValues(alpha: .24)),
          borderRadius: BorderRadius.circular(SetflowRadii.md),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: SetflowSpacing.sm),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
