import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.teampara.setflow/lock_screen_workout');
  Map<Object?, Object?>? published;
  var settingsOpened = false;
  var supported = true;
  var notificationsAllowed = true;

  setUp(() {
    published = null;
    settingsOpened = false;
    supported = true;
    notificationsAllowed = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'status':
              return {
                'supported': supported,
                'enabled': published != null,
                'notificationsAllowed': notificationsAllowed,
                if (published != null) ...{
                  'ownerKey': published!['ownerKey'],
                  'workoutDate': published!['workoutDate'],
                  'sessionId': published!['sessionId'],
                },
              };
            case 'getGuestOwnerKey':
              return 'lock-screen-flow-guest';
            case 'readEvents':
              return [];
            case 'publish':
              published = Map<Object?, Object?>.from(call.arguments as Map);
              return true;
            case 'clear':
              published = null;
              return null;
            case 'openSettings':
              settingsOpened = true;
              return true;
            case 'ack':
              return null;
          }
          throw PlatformException(code: 'unexpected_method');
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<AppState> pumpRecording(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    final date = state.dateOnly(DateTime.now());
    state.addExercise(date, state.exercises.first);
    final set = state.sessionFor(date).exercises.single.sets.first;
    state.updateSet(set, weight: 40, reps: 10);
    await state.flushPersistence();
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.dark,
          builder: (_, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: 2,
            maxScaleFactor: 2,
            child: child!,
          ),
          home: DailyWorkoutScreen(date: date),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets('guest enables and stops real lock-screen recording', (
    tester,
  ) async {
    final state = await pumpRecording(tester);
    await tester.tap(find.byTooltip('기록 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('daily-lock-screen-workout')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('lock-screen-workout-start')),
    );
    await tester.tap(find.byKey(const ValueKey('lock-screen-workout-start')));
    await tester.pumpAndSettle();
    expect(published, isNotNull);
    final sets = published!['sets'] as List;
    expect((sets.first as Map)['weight'], 40);
    expect((sets.first as Map)['reps'], 10);
    expect(state.lockScreenWorkoutActive, isTrue);
    expect(
      find.byKey(const ValueKey('lock-screen-workout-active')),
      findsOneWidget,
    );
    expect(state.sessionFor(DateTime.now()).completedSets, 0);
    await tester.tap(find.byTooltip('기록 메뉴'));
    await tester.pumpAndSettle();
    expect(find.text('잠금화면 기록 끄기'), findsOneWidget);
    await tester.tap(find.text('잠금화면 기록 끄기'));
    await tester.pumpAndSettle();
    expect(state.lockScreenWorkoutActive, isFalse);
    expect(published, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'disabled notifications lead to device settings without publishing',
    (tester) async {
      notificationsAllowed = false;
      await pumpRecording(tester);
      await tester.tap(find.byTooltip('기록 메뉴'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('daily-lock-screen-workout')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('기기 설정 열기'));
      await tester.tap(find.text('기기 설정 열기'));
      await tester.pumpAndSettle();
      expect(settingsOpened, isTrue);
      expect(published, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('unsupported hosts omit the lock-screen action', (tester) async {
    supported = false;
    await pumpRecording(tester);
    await tester.tap(find.byTooltip('기록 메뉴'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('daily-lock-screen-workout')),
      findsNothing,
    );
    expect(published, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
