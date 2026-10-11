import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/services/rest_timer_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.teampara.setflow/rest_timer');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'personal set completion sends its recorded day to the native timer',
    () async {
      final state = AppState();
      await state.initialize();
      addTearDown(state.dispose);
      final day = DateTime(2026, 9, 29);
      state.addExercise(day, state.exercises.first);
      final session = state.sessions[day]!;
      await state.toggleSet(session.exercises.single.sets.first);
      final start = calls.where((call) => call.method == 'start').single;
      expect(start.arguments['workoutDate'], '2026-09-29');
      expect(start.arguments.containsKey('sessionId'), isFalse);
      expect(state.restFocus!.workoutDate, day);

      state.extendRestTimer();
      await Future<void>.value();
      expect(calls.last.arguments['workoutDate'], '2026-09-29');
    },
  );

  test(
    'coaching rest retains its assignment and shared rest clears the target',
    () async {
      final state = AppState();
      await state.initialize();
      addTearDown(state.dispose);
      state.startRestTimer(
        90,
        focus: RestFocus(
          exerciseName: '스쿼트',
          setsLeft: 2,
          workoutDate: DateTime(2026, 10, 12),
          coachingWorkoutId: 'coaching-workout-7',
        ),
      );
      await Future<void>.value();
      expect(calls.last.arguments['sessionId'], 'coaching-workout-7');
      state.startRestTimer(60);
      await Future<void>.value();
      expect(calls.last.arguments.containsKey('workoutDate'), isFalse);
      expect(calls.last.arguments.containsKey('sessionId'), isFalse);
    },
  );

  test(
    'closing the native timer stays cancelled when the app resumes',
    () async {
      final state = AppState();
      await state.initialize();
      addTearDown(state.dispose);
      state.startRestTimer(90);
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'status') {
          return {'remainingSeconds': 0, 'endsAtMillis': 0};
        }
        return null;
      });
      await state.syncRestTimerFromPlatform();
      expect(state.restRemaining, 0);
      expect(
        calls.where((call) => call.method == 'start'),
        hasLength(1),
        reason:
            'Resuming must not restart a timer closed from the floating window',
      );
    },
  );

  test(
    'overlay preference changes never open permission settings implicitly',
    () async {
      expect(await RestTimerPlatform.setOverlayEnabled(true), isTrue);
      expect(calls.single.method, 'setOverlayEnabled');
      expect(calls.single.arguments, {'enabled': true});
      calls.clear();
      expect(await RestTimerPlatform.setOverlayEnabled(false), isTrue);
      expect(calls.single.method, 'setOverlayEnabled');
      expect(calls.single.arguments, {'enabled': false});
    },
  );

  test(
    'permission and enabled preference are distinct native status values',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'enabled': true, 'permissionGranted': false},
      );
      final status = await RestTimerPlatform.overlayStatus();
      expect(status!.enabled, isTrue);
      expect(status.permissionGranted, isFalse);
    },
  );

  test(
    'pending return preserves recorded day and coaching identifier',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'workoutDate': '2026-09-29',
          'sessionId': '  coaching-7  ',
        },
      );
      final open = await RestTimerPlatform.consumePendingWorkoutOpen();
      expect(open!.workoutDate, DateTime(2026, 9, 29));
      expect(open.coachingWorkoutId, 'coaching-7');
    },
  );

  test(
    'invalid or absent dates never invent a personal record destination',
    () async {
      for (final date in ['2026-02-31', '2026-10-12T05:00:00Z', '', null]) {
        messenger.setMockMethodCallHandler(
          channel,
          (_) async => {'workoutDate': date},
        );
        final open = await RestTimerPlatform.consumePendingWorkoutOpen();
        expect(open!.workoutDate, isNull);
        expect(open.coachingWorkoutId, isNull);
      }
    },
  );

  test(
    'unsupported or failing hosts keep optional overlay features unavailable',
    () async {
      for (final unavailable in [false, true]) {
        messenger.setMockMethodCallHandler(
          channel,
          unavailable
              ? (_) async {
                  throw PlatformException(code: 'unavailable');
                }
              : null,
        );
        expect(await RestTimerPlatform.overlayStatus(), isNull);
        expect(await RestTimerPlatform.setOverlayEnabled(true), isFalse);
        expect(await RestTimerPlatform.openOverlaySettings(), isFalse);
        expect(await RestTimerPlatform.consumePendingWorkoutOpen(), isNull);
      }
    },
  );
}
