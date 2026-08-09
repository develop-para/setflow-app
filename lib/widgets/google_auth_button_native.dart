import 'package:flutter/material.dart';

import 'common.dart';

class GoogleAuthButton extends StatelessWidget {
  const GoogleAuthButton({
    required this.ready,
    required this.isLoading,
    required this.onPressed,
    super.key,
  });

  final bool ready;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: 'Google',
      onPressed: onPressed,
      variant: AppButtonVariant.outlined,
      isLoading: isLoading,
      semanticLabel: ready ? 'Google 로그인' : 'Google 로그인 설정 안내',
    );
  }
}
