import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/screens/detail_screens.dart';
import 'package:setflow/theme.dart';

final _day = DateTime(2026, 10, 14);
const _restSlider = ValueKey('setting-rest-default');

Future<(AppState, MemoryAppRepository)> _pump(
  WidgetTester tester, {
  required int seconds,
  bool dark = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(320, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final snapshot = AppSnapshot(
    role: UserRole.guest,
    isDarkMode: dark,
    weightUnit: 'kg',
    restDefaultSeconds: seconds,
    sessions: {
      _day: WorkoutSession(
        date: _day,
        exercises: [
          WorkoutExercise(
            id: 'recorded-bench',
            template: exerciseCatalog.firstWhere(
              (exercise) => exercise.id == 'bench',
            ),
            sets: [
              WorkoutSetEntry(
                number: 1,
                weight: 60,
                reps: 8,
                completed: true,
                restSeconds: 105,
                rir: 2,
              ),
            ],
          ),
        ],
      ),
    },
    routines: const [],
  );
  final restored = AppSnapshotCodec.fromJson(
    AppSnapshotCodec.toJson(snapshot),
    exerciseCatalog,
  )!;
  final repository = MemoryAppRepository(initialSnapshot: restored);
  final state = AppState(repository: repository);
  await state.initialize();
  addTearDown(state.dispose);
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(
        theme: dark ? SetflowTheme.dark : SetflowTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(2),
            padding: const EdgeInsets.only(top: 24, bottom: 28),
          ),
          child: child!,
        ),
        home: const SettingDetailScreen(section: SettingSection.workout),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (state, repository);
}

Future<void> _chooseMaximum(WidgetTester tester) async {
  final slider = find.byKey(_restSlider);
  await tester.ensureVisible(slider);
  await tester.pumpAndSettle();
  expect(slider.hitTestable(), findsOneWidget);
  final rect = tester.getRect(slider);
  final start = rect.center;
  final end = Offset(rect.right - 1, rect.center.dy);
  final gesture = await tester.startGesture(start);
  await tester.pump(const Duration(milliseconds: 24));
  for (var step = 1; step <= 8; step++) {
    await gesture.moveTo(Offset.lerp(start, end, step / 8)!);
    await tester.pump(const Duration(milliseconds: 24));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  for (final dark in [false, true]) {
    for (final seconds in [540, 600]) {
      testWidgets(
        'workout settings retain $seconds seconds and allow the shared maximum at 2x ($dark)',
        (tester) async {
          final (state, repository) = await _pump(
            tester,
            seconds: seconds,
            dark: dark,
          );
          final before = AppSnapshotCodec.sessionToJson(state.sessionFor(_day));
          final slider = tester.widget<Slider>(find.byKey(_restSlider));
          expect(slider.value, seconds.toDouble());
          expect(slider.min, 30);
          expect(slider.max, 600);
          expect(find.text('$seconds초'), findsOneWidget);
          expect(state.restDefaultSeconds, seconds);
          expect(tester.takeException(), isNull);
          await state.flushPersistence();
          expect(repository.snapshot!.restDefaultSeconds, seconds);

          await _chooseMaximum(tester);
          expect(state.restDefaultSeconds, 600);
          expect(tester.widget<Slider>(find.byKey(_restSlider)).value, 600);
          await state.flushPersistence();
          expect(repository.snapshot!.restDefaultSeconds, 600);
          expect(
            AppSnapshotCodec.sessionToJson(state.sessionFor(_day)),
            before,
          );
          expect(
            AppSnapshotCodec.sessionToJson(
              repository.snapshot!.sessions[_day]!,
            ),
            before,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final seconds in [15, 900]) {
    testWidgets(
      'legacy rest $seconds is displayed safely without changing stored values on entry',
      (tester) async {
        final (state, repository) = await _pump(tester, seconds: seconds);
        final before = AppSnapshotCodec.sessionToJson(state.sessionFor(_day));
        expect(
          tester.widget<Slider>(find.byKey(_restSlider)).value,
          seconds.clamp(30, 600).toDouble(),
        );
        expect(state.restDefaultSeconds, seconds);
        expect(repository.snapshot!.restDefaultSeconds, seconds);
        expect(tester.takeException(), isNull);
        await state.flushPersistence();
        expect(repository.snapshot!.restDefaultSeconds, seconds);
        expect(AppSnapshotCodec.sessionToJson(state.sessionFor(_day)), before);

        await _chooseMaximum(tester);
        expect(state.restDefaultSeconds, 600);
        await state.flushPersistence();
        expect(repository.snapshot!.restDefaultSeconds, 600);
        expect(AppSnapshotCodec.sessionToJson(state.sessionFor(_day)), before);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
