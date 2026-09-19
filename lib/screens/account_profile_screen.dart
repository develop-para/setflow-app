import 'dart:async';

import 'package:flutter/material.dart';

import '../data/account_profile_repository.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/auth_notice.dart';

class AccountProfileScreen extends StatefulWidget {
  const AccountProfileScreen({required this.repository, super.key});

  final AccountProfileRepository repository;

  @override
  State<AccountProfileScreen> createState() => _AccountProfileScreenState();
}

class _AccountProfileScreenState extends State<AccountProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _birthDate = TextEditingController();
  late final StreamSubscription<AuthChange> _authChanges;
  final _userId = Auth.instance.currentUser?.id;
  AccountProfile? _profile;
  String? _error;
  bool _loading = true;
  bool _saving = false;

  bool get _sameAccount =>
      _userId != null && Auth.instance.currentUser?.id == _userId;

  @override
  void initState() {
    super.initState();
    _authChanges = Auth.instance.authChanges.listen((_) {
      if (mounted && !_sameAccount) {
        setState(() {
          _profile = null;
          _birthDate.clear();
          _loading = false;
          _error = '계정이 바뀌었어요. 화면을 닫고 다시 열어주세요.';
        });
      }
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_authChanges.cancel());
    _birthDate.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_sameAccount) {
      setState(() {
        _loading = false;
        _error = '로그인 후 이용해주세요.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await widget.repository.loadMyProfile();
      if (!mounted || !_sameAccount) return;
      if (profile.userId != _userId) {
        throw const AuthFailure('계정이 바뀌었어요. 다시 열어주세요.');
      }
      setState(() {
        _profile = profile;
        _birthDate.text = profile.birthDate == null
            ? ''
            : AccountBirthDate.format(profile.birthDate!);
      });
    } catch (_) {
      if (mounted && _sameAccount) {
        setState(() => _error = '계정 정보를 불러오지 못했어요. 다시 시도해주세요.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving ||
        !_sameAccount ||
        !(_form.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.repository.saveMyBirthDate(
        AccountBirthDate.parse(_birthDate.text),
      );
      if (!mounted || !_sameAccount) return;
      if (result.userId != _userId) {
        throw const AuthFailure('계정이 바뀌었어요. 다시 열어주세요.');
      }
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted && _sameAccount) {
        setState(() => _error = '저장하지 못했어요. 연결을 확인하고 다시 시도해주세요.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _sameAccount ? _profile : null;
    return Scaffold(
      appBar: AppBar(title: const Text('계정 정보')),
      body: SafeArea(
        top: false,
        child: Form(
          key: _form,
          child: ListView(
            padding: SetflowInsets.pageForm,
            children: [
              if (_loading) const LinearProgressIndicator(),
              if (_error != null) ...[
                AuthNotice(message: _error!, tone: AuthNoticeTone.danger),
                const SizedBox(height: SetflowSpacing.md),
                if (profile == null && _sameAccount)
                  OutlinedButton(onPressed: _load, child: const Text('다시 확인')),
              ],
              if (profile != null) ...[
                Text('이메일', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: SetflowSpacing.sm),
                SelectableText(profile.email ?? '등록된 이메일이 없어요.'),
                const SizedBox(height: SetflowSpacing.xl),
                TextFormField(
                  key: const ValueKey('account-birth-date'),
                  controller: _birthDate,
                  enabled: !_saving,
                  keyboardType: TextInputType.datetime,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: '생년월일',
                    hintText: '예: 1995-04-16',
                    helperText: '공개 프로필과 코칭 공유에는 표시되지 않아요.',
                    helperMaxLines: 3,
                  ),
                  validator: AccountBirthDate.validate,
                  onFieldSubmitted: (_) => _save(),
                ),
                const SizedBox(height: SetflowSpacing.md),
                const Text('선택 정보예요. 입력한 날짜를 비우고 저장하면 삭제돼요.'),
                const SizedBox(height: SetflowSpacing.xl),
                FilledButton(
                  key: const ValueKey('account-profile-save'),
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? '저장 중...' : '저장'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
