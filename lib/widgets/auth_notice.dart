import 'package:flutter/material.dart';

import '../theme.dart';
import '../theme/icons.dart';

/// How loud the notice is. In a monochrome system this is tone, not hue —
/// [danger] is simply the darkest, so it reads as the strongest signal without
/// depending on colour vision.
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
    final (color, icon) = switch (tone) {
      AuthNoticeTone.info => (SetflowColors.ink, SetflowIcons.mailSent),
      AuthNoticeTone.success => (SetflowColors.ink, SetflowIcons.success),
      AuthNoticeTone.danger => (
        context.setflowColors.error,
        SetflowIcons.error,
      ),
    };
    final onPanel = theme.brightness == Brightness.dark
        ? theme.colorScheme.onSurface
        : color;

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
