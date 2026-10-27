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
  var events = <Map<String, Object?>>[];

  setUp(() {
    published = null;
    settingsOpened = false;
    supported = true;
    notificationsAllowed = true;
    events = [];
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
              return events;
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
              final ids = (call.arguments as Map)['eventIds'] as List;
              events.removeWhere((event) => ids.contains(event['eventId']));
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

  for (final restore in [true, false]) {
    testWidgets(
      'a changed set can be explicitly reviewed (restore: $restore)',
      (tester) async {
        final state = await pumpRecording(tester);
        final date = state.dateOnly(DateTime.now());
        expect(await state.startLockScreenWorkout(date), isTrue);
        final source = Map<Object?, Object?>.of(published!);
        final target = Map<String, Object?>.from(
          (source['sets'] as List).first as Map,
        );
        events = [
          {
            'eventId': 'review-event',
            'sessionId': source['sessionId'],
            'ownerKey': source['ownerKey'],
            'workoutDate': source['workoutDate'],
            'publishedAtMillis': source['publishedAtMillis'],
            'expiresAtMillis': source['expiresAtMillis'],
            'completedAtMillis': DateTime.now().millisecondsSinceEpoch,
            'set': target,
          },
        ];
        final original = state.sessionFor(date).exercises.single;
        state.updateSet(original.sets.first, weight: 45);
        await state.reconcileLockScreenWorkout();
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('lock-screen-workout-review')),
        );
        await tester.tap(
          find.byKey(const ValueKey('lock-screen-workout-review')),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining(target['valuesLabel'] as String),
          findsOneWidget,
        );
        final choice = find.text(restore ? '별도 기록 복원' : '앱 기록 유지');
        await tester.scrollUntilVisible(
          choice,
          160,
          scrollable: find
              .descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(choice);
        await tester.pumpAndSettle();
        expect(original.sets.first.weight, 45);
        expect(original.sets.first.completed, isFalse);
        expect(state.sessionFor(date).exercises.length, restore ? 2 : 1);
        if (restore) {
          final recovered = state.sessionFor(date).exercises.last.sets.single;
          expect(recovered.completed, isTrue);
          expect(recovered.weight, 40);
          expect(recovered.reps, 10);
        }
        expect(events, isEmpty);
        expect(state.lockScreenWorkoutPendingEvents, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
