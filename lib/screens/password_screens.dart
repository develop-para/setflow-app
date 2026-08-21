import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/auth_notice.dart';
import '../widgets/common.dart';

/// Asks for the account's address and mails a reset link.
///
/// Without this screen a forgotten password is permanent: the account exists,
/// so signing up again fails, and the password is unknown, so signing in fails
/// too. There is no third door.
class PasswordResetRequestScreen extends StatefulWidget {
  const PasswordResetRequestScreen({this.initialEmail, super.key});

  /// Prefilled from the sign-in form the user just failed on — retyping the
  /// address they already typed is pure friction.
  final String? initialEmail;

  @override
  State<PasswordResetRequestScreen> createState() =>
      _PasswordResetRequestScreenState();
}

class _PasswordResetRequestScreenState
    extends State<PasswordResetRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _emailController = TextEditingController(
    text: widget.initialEmail ?? '',
  );
  final _auth = Auth.instance;

  bool _submitting = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('비밀번호 재설정')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SetflowSpacing.xxl),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  SetflowIcons.password,
                  size: 44,
                  color: theme.colorScheme.onSurface,
                ),
                const SizedBox(height: SetflowSpacing.lg),
                Text(
                  '가입한 이메일로 재설정 링크를 보내드려요',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: SetflowSpacing.sm),
                Text(
                  '링크를 열면 새 비밀번호를 정할 수 있어요.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: SetflowSpacing.xl),
                if (_sent) ...[
                  AuthNotice(
                    key: const ValueKey('reset-sent'),
                    // Says "if an account exists" on purpose. Confirming the
                    // address is registered would turn this form into a way to
                    // check who has an account.
                    message:
                        '${_emailController.text.trim()} 으로 가입된 계정이 있다면 '
                        '재설정 링크를 보냈어요. 메일함을 확인해주세요.',
                  ),
                  const SizedBox(height: SetflowSpacing.md),
                ],
                if (_error != null) ...[
                  AuthNotice(
                    key: const ValueKey('reset-error'),
                    message: _error!,
                    tone: AuthNoticeTone.danger,
                  ),
                  const SizedBox(height: SetflowSpacing.md),
                ],
                AppTextField(
                  controller: _emailController,
                  label: '이메일',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.email],
                  validator: validateEmailField,
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: SetflowSpacing.xl),
                AppButton(
                  key: const ValueKey('reset-send'),
                  label: _sent ? '다시 보내기' : '재설정 링크 보내기',
                  icon: SetflowIcons.mailSent,
                  isLoading: _submitting,
                  onPressed: _submitting ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _auth.sendPasswordReset(email: _emailController.text);
      if (!mounted) return;
      setState(() => _sent = true);
    } catch (error) {
      if (mounted) setState(() => _error = _auth.messageFor(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

/// Sets a new password.
///
/// Serves two arrivals that look different to the user but are the same
/// operation to the backend:
/// * a reset link opened from mail ([requiresCurrentPassword] false — proving
///   control of the mailbox already happened),
/// * a signed-in user changing it deliberately ([requiresCurrentPassword]
///   true — a live session is not proof of identity, an unlocked phone would
///   otherwise be enough to lock the owner out).
class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({this.requiresCurrentPassword = false, super.key});

  final bool requiresCurrentPassword;

  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _auth = Auth.instance;

  bool _submitting = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changing = widget.requiresCurrentPassword;
    return Scaffold(
      appBar: AppBar(title: Text(changing ? '비밀번호 변경' : '새 비밀번호 설정')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SetflowSpacing.xxl),
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    SetflowIcons.password,
                    size: 44,
                    color: theme.colorScheme.onSurface,
                  ),
                  const SizedBox(height: SetflowSpacing.lg),
                  Text(
                    changing ? '새 비밀번호를 정해주세요' : '새 비밀번호로 바꿔주세요',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: SetflowSpacing.xl),
                  if (_error != null) ...[
                    AuthNotice(
                      key: const ValueKey('new-password-error'),
                      message: _error!,
                      tone: AuthNoticeTone.danger,
                    ),
                    const SizedBox(height: SetflowSpacing.md),
                  ],
                  if (changing) ...[
                    AppTextField(
                      key: const ValueKey('current-password'),
                      controller: _currentController,
                      label: '현재 비밀번호',
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.password],
                      validator: (value) =>
                          (value ?? '').isEmpty ? '현재 비밀번호를 입력해주세요.' : null,
                    ),
                    const SizedBox(height: SetflowSpacing.md),
                  ],
                  AppTextField(
                    key: const ValueKey('new-password'),
                    controller: _passwordController,
                    label: '새 비밀번호',
                    helperText: '${AuthPasswordPolicy.minLength}자 이상 입력해주세요.',
                    obscureText: _obscure,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newPassword],
                    suffixIcon: IconButton(
                      tooltip: _obscure ? '비밀번호 보기' : '비밀번호 숨기기',
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? SetflowIcons.passwordVisible
                            : SetflowIcons.passwordHidden,
                      ),
                    ),
                    validator: AuthPasswordPolicy.validate,
                  ),
                  const SizedBox(height: SetflowSpacing.md),
                  AppTextField(
                    key: const ValueKey('confirm-password'),
                    controller: _confirmController,
                    label: '새 비밀번호 확인',
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.newPassword],
                    validator: (value) => value != _passwordController.text
                        ? '비밀번호가 일치하지 않아요.'
                        : null,
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: SetflowSpacing.xl),
                  AppButton(
                    key: const ValueKey('new-password-save'),
                    label: '비밀번호 저장',
                    icon: SetflowIcons.password,
                    isLoading: _submitting,
                    onPressed: _submitting ? null : _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (widget.requiresCurrentPassword) {
        final ok = await _auth.verifyPassword(_currentController.text);
        if (!mounted) return;
        if (!ok) {
          setState(() {
            _submitting = false;
            _error = '현재 비밀번호가 맞지 않아요.';
          });
          return;
        }
      }
      await _auth.updatePassword(newPassword: _passwordController.text);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = _auth.messageFor(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

/// Shared so the sign-in, sign-up and reset forms cannot disagree about what a
/// valid address looks like.
String? validateEmailField(String? value) {
  final email = value?.trim() ?? '';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
    return '올바른 이메일 주소를 입력해주세요.';
  }
  return null;
}
