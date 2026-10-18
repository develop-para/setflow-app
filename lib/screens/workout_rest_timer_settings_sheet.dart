import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/rest_timer_notification_setting.dart';
import '../widgets/rest_timer_overlay_setting.dart';

/// 설정을 직접 열 때만 표시한다. 세트 완료 흐름에는 권한 안내를 끼우지 않는다.
Future<void> showWorkoutRestTimerSettings(BuildContext context) =>
    showSetflowSheet<void>(
      context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SingleChildScrollView(
        padding: SetflowInsets.pageForm,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('휴식 타이머', style: Theme.of(sheetContext).textTheme.titleLarge),
            const SizedBox(height: SetflowSpacing.sm),
            const RestTimerOverlaySetting(),
            const RestTimerNotificationSetting(),
            const SizedBox(height: SetflowSpacing.md),
            FilledButton(
              key: const ValueKey('rest-timer-settings-close'),
              onPressed: () => Navigator.pop(sheetContext),
              child: const Text('닫기'),
            ),
          ],
        ),
      ),
    );
