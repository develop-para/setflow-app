import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/screens/detail_screens.dart';
import 'package:setflow/theme.dart';

/// 휴식 카운트다운 소리 설정. 소리는 네이티브 타이머 서비스가 내지만,
/// 무엇을 낼지는 여기 설정이 정한다 — 켜고 끄기와 예고 시점이 저장까지
/// 왕복하는지 본다.
void main() {
  Future<AppState> pumpNotifications(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(432, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: const SettingDetailScreen(
            section: SettingSection.notifications,
          ),
        ),
      ),
    );
    // initialize가 건 250ms 저장 디바운스까지 여기서 비운다 —
    // 티어다운은 타이머 검사보다 늦게 돈다.
    await tester.pump(const Duration(milliseconds: 400));
    return state;
  }

  testWidgets('sound defaults on with a 30s countdown', (tester) async {
    final state = await pumpNotifications(tester);
    expect(state.timerSound, isTrue);
    expect(state.timerCountdownSeconds, 30);
    expect(find.text('타이머 소리'), findsOneWidget);
    expect(find.byKey(const ValueKey('countdown-30')), findsOneWidget);
  });

  testWidgets('picking a countdown updates state', (tester) async {
    final state = await pumpNotifications(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('countdown-60')),
      120,
    );
    await tester.tap(find.byKey(const ValueKey('countdown-60')));
    await tester.pumpAndSettle();
    expect(state.timerCountdownSeconds, 60);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('turning sound off hides the countdown row', (tester) async {
    final state = await pumpNotifications(tester);
    await tester.tap(find.byKey(const ValueKey('setting-timer-sound')));
    await tester.pumpAndSettle();
    expect(state.timerSound, isFalse);
    expect(find.text('카운트다운 예고'), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
  });

  test('the choice survives the snapshot round trip', () {
    AppSnapshot base({bool sound = false, int countdown = 60}) => AppSnapshot(
      role: UserRole.guest,
      isDarkMode: false,
      weightUnit: 'kg',
      restDefaultSeconds: 90,
      sessions: const {},
      routines: const [],
      timerSound: sound,
      timerCountdownSeconds: countdown,
    );

    final decoded = AppSnapshotCodec.fromJson(
      AppSnapshotCodec.toJson(base()),
      exerciseCatalog,
    )!;
    expect(decoded.timerSound, isFalse);
    expect(decoded.timerCountdownSeconds, 60);

    // 옛 스냅샷(필드 없음)은 기본값으로 돌아온다.
    final legacy = AppSnapshotCodec.toJson(base());
    (legacy['preferences'] as Map<String, dynamic>)
      ..remove('timerSound')
      ..remove('timerCountdownSeconds');
    final restored = AppSnapshotCodec.fromJson(legacy, exerciseCatalog)!;
    expect(restored.timerSound, isTrue);
    expect(restored.timerCountdownSeconds, 30);
  });
}
