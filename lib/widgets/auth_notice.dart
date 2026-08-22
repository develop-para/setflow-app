import 'package:flutter/material.dart';

import '../theme.dart';
import '../theme/icons.dart';

/// Semantic notice tone. Icons and labels keep every state understandable
/// without relying on colour alone.
enum AuthNoticeTone { info, success, danger }

/// The one panel every auth screen uses to say something back to the user.
///
/// Auth screens fail often and for boring reasons (wrong password, expired
/// link, mail not arrived), so the reply is part of the flow rather than an
/// exception path. It is a `liveRegion` so a screen reader announces the new
/// message instead of leaving it to be discovered.
class AuthNotice extends StatelessWidget {
  const AuthNotice({
    required this.message,
    this.tone = AuthNoticeTone.info,
    this.action,
    super.key,
  });

  final String message;
  final AuthNoticeTone tone;

  /// Optional follow-up, e.g. "메일 다시 보내기". Placed inside the panel so the
  /// remedy sits with the problem.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.setflowColors;
    final (color, icon) = switch (tone) {
      AuthNoticeTone.info => (semantic.info, SetflowIcons.mailSent),
      AuthNoticeTone.success => (semantic.success, SetflowIcons.success),
      AuthNoticeTone.danger => (SetflowColors.red, SetflowIcons.error),
    };
    final onPanel = theme.colorScheme.onSurface;

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(SetflowSpacing.md),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          border: Border.all(color: color.withValues(alpha: .24)),
          borderRadius: BorderRadius.circular(SetflowRadii.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: onPanel, size: 20),
                const SizedBox(width: SetflowSpacing.sm),
                Expanded(
                  child: Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(color: onPanel),
                  ),
                ),
              ],
            ),
            if (action != null) ...[
              const SizedBox(height: SetflowSpacing.xs),
              Align(alignment: Alignment.centerLeft, child: action),
            ],
          ],
        ),
      ),
    );
  }
}
