import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart' as google_web;

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
    if (!ready || isLoading) {
      return AppButton(
        label: 'Google',
        onPressed: onPressed,
        variant: AppButtonVariant.outlined,
        isLoading: isLoading,
        semanticLabel: ready ? 'Google 로그인' : 'Google 로그인 설정 안내',
      );
    }

    final width = (MediaQuery.sizeOf(context).width - 48)
        .clamp(120.0, 400.0)
        .toDouble();
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Center(
        child: google_web.renderButton(
          configuration: google_web.GSIButtonConfiguration(
            type: google_web.GSIButtonType.standard,
            theme: google_web.GSIButtonTheme.outline,
            size: google_web.GSIButtonSize.large,
            text: google_web.GSIButtonText.continueWith,
            shape: google_web.GSIButtonShape.pill,
            logoAlignment: google_web.GSIButtonLogoAlignment.left,
            minimumWidth: width,
            locale: 'ko',
          ),
        ),
      ),
    );
  }
}
