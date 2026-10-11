import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/main.dart';
import 'package:setflow/screens/coaching_workout_screens.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/widgets/common.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.teampara.setflow/rest_timer');
  Map<String, Object?>? pending;
  var consumeCalls = 0;

  String encodedDate(DateTime date) => DateTime(
    date.year,
    date.month,
    date.day,
  ).toIso8601String().split('T').first;

  setUp(() {
    pending = null;
    consumeCalls = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'consumePendingWorkoutOpen') {
        consumeCalls++;
        final request = pending;
        pending = null;
        return request;
      }
      return null;
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  Future<AppState> launch(
    WidgetTester tester, {
    AppRepository? repository,
  }) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() async {
      AppSnackbar.dismiss();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(SetflowApp(repository: repository));
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();
    return AppScope.of(
      tester.element(find.byType(MemberShell, skipOffstage: false)),
    );
  }

  NavigatorState navigator(WidgetTester tester) =>
      tester.state<NavigatorState>(find.byType(Navigator).first);

  Future<void> resume(WidgetTester tester) async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  Future<void> showElsewhere(WidgetTester tester) async {
    unawaited(
      navigator(tester).push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(
            key: ValueKey('unrelated-screen'),
            body: Text('다른 화면'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('warm return restores the retained past-day route and scroll', (
    tester,
  ) async {
    final state = await launch(tester);
    final date = state.dateOnly(
      DateTime.now().subtract(const Duration(days: 3)),
    );
    for (final exercise in state.exercises.take(8)) {
      state.addExercise(date, exercise);
    }
    final source = MaterialPageRoute<void>(
      builder: (_) => DailyWorkoutScreen(date: date),
    );
    unawaited(navigator(tester).push(source));
    await tester.pumpAndSettle();
    final sourceElement = tester.element(find.byType(DailyWorkoutScreen));
    final scroll = find
        .descendant(
          of: find.byType(DailyWorkoutScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.drag(scroll, const Offset(0, -450));
    await tester.pumpAndSettle();
    final position = tester.state<ScrollableState>(scroll).position;
    final offset = position.pixels;
    expect(offset, greaterThan(0));
    state.startRestTimer(
      90,
      focus: RestFocus(exerciseName: '스쿼트', setsLeft: 2, workoutDate: date),
    );
    await showElsewhere(tester);

    pending = {'workoutDate': encodedDate(date)};
    await resume(tester);

    expect(source.isCurrent, isTrue);
    expect(
      tester.element(find.byType(DailyWorkoutScreen)),
      same(sourceElement),
    );
    expect(position.pixels, offset);
    expect(find.byKey(const ValueKey('unrelated-screen')), findsNothing);
    expect(
      find.byType(DailyWorkoutScreen, skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('a popped source reopens its date instead of the latest screen', (
    tester,
  ) async {
    final state = await launch(tester);
    final date = state.dateOnly(
      DateTime.now().subtract(const Duration(days: 4)),
    );
    final source = MaterialPageRoute<void>(
      builder: (_) => DailyWorkoutScreen(date: date),
    );
    unawaited(navigator(tester).push(source));
    await tester.pumpAndSettle();
    final sourceElement = tester.element(find.byType(DailyWorkoutScreen));
    state.startRestTimer(
      90,
      focus: RestFocus(exerciseName: '벤치 프레스', setsLeft: 1, workoutDate: date),
    );
    navigator(tester).pop();
    await tester.pumpAndSettle();
    await showElsewhere(tester);
    pending = {'workoutDate': encodedDate(date)};

    await resume(tester);

    expect(
      tester.widget<DailyWorkoutScreen>(find.byType(DailyWorkoutScreen)).date,
      date,
    );
    expect(
      tester.element(find.byType(DailyWorkoutScreen)),
      isNot(same(sourceElement)),
    );
  });

  testWidgets('cold return waits for restore and splash then consumes once', (
    tester,
  ) async {
    final date = DateTime(2026, 9, 18);
    pending = {'workoutDate': encodedDate(date)};
    final repository = _DelayedRepository();
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(SetflowApp(repository: repository));
    await tester.pump(const Duration(milliseconds: 1900));
    expect(consumeCalls, 1);
    expect(find.byType(DailyWorkoutScreen), findsNothing);
    expect(find.byKey(const ValueKey('setflow-loading-logo')), findsOneWidget);
    repository.loaded.complete();
    await tester.pumpAndSettle();

    expect(
      tester.widget<DailyWorkoutScreen>(find.byType(DailyWorkoutScreen)).date,
      date,
    );
    expect(consumeCalls, 1);
    navigator(tester).pop();
    await tester.pumpAndSettle();
    await resume(tester);
    expect(consumeCalls, 2);
    expect(find.byType(DailyWorkoutScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets(
    'today returns to the retained record tab without a pushed copy',
    (tester) async {
      final state = await launch(tester);
      final today = state.dateOnly(DateTime.now());
      state.addExercise(today, state.exercises.first);
      await tester.tap(find.byKey(const ValueKey('bottom-bar-center-action')));
      await tester.pumpAndSettle();
      final source = tester.element(find.byType(DailyWorkoutScreen));
      state.startRestTimer(
        90,
        focus: RestFocus(exerciseName: '스쿼트', setsLeft: 2, workoutDate: today),
      );
      await tester.tap(find.text('홈'));
      await tester.pumpAndSettle();
      await showElsewhere(tester);
      pending = {'workoutDate': encodedDate(today)};

      await resume(tester);

      expect(navigator(tester).canPop(), isFalse);
      expect(tester.element(find.byType(DailyWorkoutScreen)), same(source));
      expect(
        find.byType(DailyWorkoutScreen, skipOffstage: false),
        findsOneWidget,
      );
    },
  );

  testWidgets('cold today return selects the record tab after splash', (
    tester,
  ) async {
    final today = DateUtils.dateOnly(DateTime.now());
    pending = {'workoutDate': encodedDate(today)};
    await launch(tester);

    expect(navigator(tester).canPop(), isFalse);
    expect(
      tester.widget<DailyWorkoutScreen>(find.byType(DailyWorkoutScreen)).date,
      today,
    );
    expect(find.byType(RecordScreen), findsOneWidget);
  });

  testWidgets('shared rest and ordinary resume keep the current screen', (
    tester,
  ) async {
    final state = await launch(tester);
    final date = DateUtils.dateOnly(DateTime.now());
    state.startRestTimer(
      90,
      focus: RestFocus(exerciseName: '스쿼트', setsLeft: 2, workoutDate: date),
    );
    state.startRestTimer(
      90,
    ); // A newer shared rest supersedes the record source.
    await showElsewhere(tester);
    pending = <String, Object?>{};
    await resume(tester);
    expect(find.byKey(const ValueKey('unrelated-screen')), findsOneWidget);
    expect(find.byType(DailyWorkoutScreen), findsNothing);
    await resume(tester);
    expect(find.byKey(const ValueKey('unrelated-screen')), findsOneWidget);
  });

  testWidgets('coaching return opens its workout ID before any personal date', (
    tester,
  ) async {
    pending = {'sessionId': 'lesson-source', 'workoutDate': '2026-09-18'};
    await launch(tester);

    expect(
      tester
          .widget<CoachingWorkoutScreen>(find.byType(CoachingWorkoutScreen))
          .workoutId,
      'lesson-source',
    );
    expect(find.byType(DailyWorkoutScreen), findsNothing);
  });
}

class _DelayedRepository extends MemoryAppRepository {
  final loaded = Completer<void>();

  @override
  Future<AppSnapshot?> load(List<ExerciseTemplate> exerciseCatalog) async {
    await loaded.future;
    return super.load(exerciseCatalog);
  }
}
