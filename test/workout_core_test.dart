import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/main.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/screens/routine_editor_screen.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

void main() {
  Future<AppState> pumpWorkoutScreen(WidgetTester tester, Widget screen) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(theme: SetflowTheme.light, home: screen),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets('exercise library shows a recoverable empty search state', (
    tester,
  ) async {
    final state = await pumpWorkoutScreen(
      tester,
      ExerciseLibraryScreen(date: DateTime(2026, 7, 23)),
    );

    await tester.enterText(find.byType(TextFormField), '존재하지않는운동');
    await tester.pumpAndSettle();
    expect(find.text('검색 결과가 없어요'), findsOneWidget);

    await tester.tap(find.text('검색 초기화'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exercise-muscle-grid')), findsOneWidget);
    await tester.tap(find.text('가슴'));
    await tester.pumpAndSettle();
    expect(find.text('바벨 벤치 프레스'), findsOneWidget);

    state.dispose();
  });

  testWidgets(
    'set editor validates direct input and deletes with confirmation',
    (tester) async {
      final date = DateTime(2026, 7, 23);
      final state = AppState();
      await state.initialize();
      state.addExercise(date, state.exercises.first);
      final exercise = state.sessionFor(date).exercises.single;

      await tester.binding.setSurfaceSize(const Size(432, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: MaterialApp(
            theme: SetflowTheme.light,
            home: ExerciseSetScreen(date: date, exercise: exercise),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('0').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('number-dial-direct-input')),
        '1200',
      );
      await tester.tap(find.text('적용'));
      await tester.pump();
      expect(find.text('0~999 범위로 입력해주세요.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('number-dial-direct-input')),
        '42.5',
      );
      await tester.tap(find.text('적용'));
      await tester.pumpAndSettle();
      expect(exercise.sets.first.weight, 42.5);

      await tester.drag(find.byType(Dismissible).first, const Offset(-360, 0));
      await tester.pumpAndSettle();
      expect(find.text('1세트를 삭제할까요?'), findsOneWidget);
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(exercise.sets, hasLength(2));
      expect(exercise.sets.first.number, 1);

      state.dispose();
    },
  );

  testWidgets('daily workout edits weight reps type and rest inline', (
    tester,
  ) async {
    final date = DateTime(2026, 11, 1);
    final state = AppState();
    await state.initialize();
    state.addExercise(date, state.exercises.first);
    final exercise = state.sessions[date]!.exercises.single;
    state.updateSet(exercise.sets.first, weight: 40);

    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: DailyWorkoutScreen(date: date),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseSetScreen), findsNothing);
    expect(find.byType(TextField), findsNWidgets(9));
    await tester.enterText(find.byType(TextField).at(0), '55.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), '12');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(2), '120');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    await tester.tap(find.text('일반').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('웜업 세트'));
    await tester.pumpAndSettle();
    final completionButton = find.byKey(
      const ValueKey('inline-set-complete-1'),
    );
    expect(tester.getSize(completionButton).width, greaterThanOrEqualTo(72));
    expect(tester.getSize(completionButton).height, greaterThanOrEqualTo(44));
    expect(
      tester
          .getRect(completionButton)
          .overlaps(tester.getRect(find.byType(TextField).at(2))),
      isFalse,
    );
    await tester.tap(completionButton);
    await tester.pump();

    expect(exercise.sets.first.weight, 55.5);
    expect(exercise.sets.first.reps, 12);
    expect(exercise.sets.first.restSeconds, 120);
    expect(exercise.sets.first.type, '웜업');
    expect(state.restRemaining, 120);
    expect(find.byType(ExerciseSetScreen), findsNothing);
    state.cancelRestTimer();
    state.dispose();
  });

  testWidgets(
    'completion commits focused weight and waits for device persistence',
    (tester) async {
      final date = DateTime(2026, 11, 1);
      final repository = MemoryAppRepository();
      final state = AppState(repository: repository);
      addTearDown(state.dispose);
      await state.initialize();
      state.addExercise(date, state.exercises.first);

      await tester.binding.setSurfaceSize(const Size(432, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: MaterialApp(
            theme: SetflowTheme.light,
            home: DailyWorkoutScreen(date: date),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '82.5');
      await tester.tap(find.byKey(const ValueKey('inline-set-complete-1')));
      await tester.pump();
      await state.flushPersistence();

      final set = state.sessions[date]!.exercises.single.sets.first;
      final persistedSet =
          repository.snapshot!.sessions[date]!.exercises.single.sets.first;
      expect(set.weight, 82.5);
      expect(set.completed, isTrue);
      expect(persistedSet.weight, 82.5);
      expect(persistedSet.completed, isTrue);
      state.cancelRestTimer();
    },
  );

  testWidgets('labeled completion button stays clear of rest on 320px', (
    tester,
  ) async {
    final date = DateTime(2026, 11, 1);
    final state = AppState();
    await state.initialize();
    state.addExercise(date, state.exercises.first);

    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: DailyWorkoutScreen(date: date),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final completionButton = find.byKey(
      const ValueKey('inline-set-complete-1'),
    );
    final restField = find.byType(TextField).at(2);
    expect(find.text('완료'), findsNWidgets(3));
    expect(tester.getSize(completionButton), const Size(72, 44));
    expect(
      tester.getRect(completionButton).overlaps(tester.getRect(restField)),
      isFalse,
    );
    expect(tester.takeException(), isNull);
    state.dispose();
  });

  testWidgets('long pressing an exercise header reorders its card', (
    tester,
  ) async {
    final date = DateTime(2026, 11, 2);
    final state = AppState();
    await state.initialize();
    state.addExercise(date, state.exercises[0]);
    state.addExercise(date, state.exercises[2]);

    await tester.binding.setSurfaceSize(const Size(432, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: DailyWorkoutScreen(date: date),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final headers = find.byType(ReorderableDelayedDragStartListener);
    expect(headers, findsNWidgets(2));
    final gesture = await tester.startGesture(tester.getCenter(headers.first));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 150));
    await gesture.moveBy(const Offset(0, 12));
    await tester.pump(const Duration(milliseconds: 120));
    for (var step = 0; step < 10; step++) {
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(state.sessions[date]!.exercises.first.template.id, 'squat');
    expect(tester.takeException(), isNull);
    state.dispose();
  });

  testWidgets(
    'recommendation controls stay compact before workout completion',
    (tester) async {
      final state = AppState();
      await state.initialize();
      final historyDate = DateTime(2026, 10, 1);
      final targetDate = DateTime(2026, 10, 5);
      state.addExercise(historyDate, state.exercises.first);
      for (final set in state.sessions[historyDate]!.exercises.single.sets) {
        state.updateSet(set, weight: 100, reps: 10);
        state.toggleSet(set);
      }
      state.cancelRestTimer();

      await tester.binding.setSurfaceSize(const Size(432, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: MaterialApp(
            theme: SetflowTheme.light,
            home: DailyWorkoutScreen(date: targetDate),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(state.recommendationForDate(targetDate), isNull);
      expect(find.byKey(const Key('auto-recommend-toggle')), findsOneWidget);
      expect(find.text('추천 ON'), findsOneWidget);
      expect(find.text('추천 세트 적용'), findsNothing);
      expect(find.text('NEXT SESSION'), findsNothing);
      expect(find.textContaining('8–10회'), findsNothing);
      expect(find.textContaining('90초'), findsNothing);

      await tester.tap(find.byKey(const Key('auto-recommend-toggle')));
      await tester.pump();
      expect(state.autoRecommendNextExercise, isFalse);
      expect(find.text('추천 OFF'), findsOneWidget);
      state.dispose();
    },
  );

  testWidgets(
    'completed workout never renders a persistent next-session card',
    (tester) async {
      final state = AppState();
      await state.initialize();
      final historyDate = DateTime(2026, 10, 1);
      final targetDate = DateTime(2026, 10, 5);
      state.setMemberProfile(goals: const ['근력 향상']);
      state.addExercise(historyDate, state.exercises.first);
      for (final set in state.sessions[historyDate]!.exercises.single.sets) {
        state.updateSet(set, weight: 100, reps: 5);
        state.toggleSet(set);
      }
      state.cancelRestTimer();

      final recommendation = state.recommendationForDate(targetDate);
      expect(recommendation, isNotNull);
      expect(recommendation!.goal.label, '근력 향상');
      expect(recommendation.minReps, 4);
      expect(recommendation.maxReps, 6);
      expect(recommendation.sets, 3);
      expect(recommendation.restSeconds, 180);

      state.addExercise(targetDate, state.exercises.first);
      for (final set in state.sessions[targetDate]!.exercises.single.sets) {
        state.updateSet(set, weight: 102.5, reps: 5);
        state.toggleSet(set);
      }
      state.cancelRestTimer();

      await tester.binding.setSurfaceSize(const Size(432, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: MaterialApp(
            theme: SetflowTheme.light,
            home: DailyWorkoutScreen(date: targetDate),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('NEXT SESSION'), findsNothing);
      expect(find.text('다음 운동 추천'), findsNothing);
      expect(find.text('추천 운동 추가'), findsNothing);
      expect(find.text('추천 세트 적용'), findsNothing);
      state.dispose();
    },
  );

  testWidgets('long pressing an inline set reveals its delete action', (
    tester,
  ) async {
    final date = DateTime(2026, 11, 4);
    final state = await pumpWorkoutScreen(
      tester,
      DailyWorkoutScreen(date: DateTime(2026, 11, 4)),
    );
    state.addExercise(date, state.exercises.first);
    await tester.pumpAndSettle();

    final set = state.sessions[date]!.exercises.single.sets.first;
    await tester.longPress(find.byKey(ObjectKey(set)));
    await tester.pumpAndSettle();

    expect(find.text('길게 눌러 삭제 메뉴를 열었어요.'), findsOneWidget);
    expect(find.text('세트 삭제'), findsWidgets);
    state.dispose();
  });

  testWidgets('finishing an exercise offers and adds the next goal exercise', (
    tester,
  ) async {
    final date = DateTime(2026, 11, 3);
    final state = AppState();
    await state.initialize();
    state.setMemberProfile(goals: const ['근육 증가']);
    state.markPrecisionRecommendationPrompted();
    state.addExercise(date, state.exercises.first);

    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: DailyWorkoutScreen(date: date),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var number = 1; number <= 3; number++) {
      await tester.tap(find.byKey(ValueKey('inline-set-complete-$number')));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('다음 운동 추천'), findsOneWidget);
    expect(find.text('인클라인 덤벨 프레스'), findsOneWidget);
    expect(find.textContaining('중량 직접 선택'), findsOneWidget);
    await tester.tap(find.text('추천 운동 추가'));
    await tester.pumpAndSettle();

    final exercises = state.sessions[date]!.exercises;
    expect(exercises.map((exercise) => exercise.template.id), [
      'bench',
      'incline',
    ]);
    expect(exercises.last.sets, hasLength(3));
    expect(
      exercises.last.sets.map((set) => set.restSeconds),
      everyElement(120),
    );
    expect(exercises.last.sets.map((set) => set.weight), everyElement(0));
    state.cancelRestTimer();
    state.dispose();
  });

  testWidgets('calendar stays compact on a 320px-wide phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    state.setMemberProfile(goals: const ['근육 증가']);

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: const Scaffold(body: CalendarScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('이전 달'), findsOneWidget);
    expect(find.byTooltip('다음 달'), findsOneWidget);
    expect(find.text('합계'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('이전 달'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    state.dispose();
  });

  testWidgets('calendar keeps recommendations hidden until workout add', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    state.setMemberProfile(goals: const ['근육 증가']);
    final historyDate = state.dateOnly(
      DateTime.now().subtract(const Duration(days: 2)),
    );
    state.addExercise(historyDate, state.exercises.first);
    final historicalExercise = state.sessions[historyDate]!.exercises.single;
    for (final set in historicalExercise.sets) {
      state.updateSet(set, weight: 100, reps: 10);
      state.toggleSet(set);
    }
    state.cancelRestTimer();

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: const Scaffold(body: CalendarScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('운동 KPI'), findsOneWidget);
    expect(find.byKey(const Key('calendar-kpi-grid')), findsOneWidget);
    expect(find.byKey(const Key('calendar-kpi-e1rm')), findsOneWidget);
    expect(find.byKey(const Key('calendar-kpi-change')), findsOneWidget);
    expect(find.byKey(const Key('calendar-kpi-pr')), findsOneWidget);
    expect(find.byKey(const Key('calendar-kpi-sessions')), findsOneWidget);
    expect(find.byKey(const Key('calendar-kpi-next')), findsNothing);
    expect(find.text('NEXT SESSION'), findsNothing);
    expect(find.text('오늘 운동에 적용'), findsNothing);
    await tester.ensureVisible(find.text('오늘 운동 기록하기'));
    await tester.tap(find.text('오늘 운동 기록하기'));
    await tester.pumpAndSettle();

    final today = state.dateOnly(DateTime.now());
    expect(find.byType(DailyWorkoutScreen), findsOneWidget);
    expect(state.sessions[today]!.exercises, isEmpty);

    state.dispose();
  });

  testWidgets(
    'first automatic recommendation offers the precision survey once',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(432, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final state = AppState();
      await state.initialize();
      state.sessions.clear();
      state.setMemberProfile(goals: const ['건강 유지']);
      final targetDate = state.dateOnly(DateTime.now());

      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: MaterialApp(
            theme: SetflowTheme.light,
            home: DailyWorkoutScreen(date: targetDate),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('운동 추가'));
      await tester.pumpAndSettle();
      expect(find.text('더 정교한 추천을 받고 싶다면?'), findsOneWidget);
      expect(state.precisionRecommendationPrompted, isFalse);

      await tester.tap(find.byKey(const ValueKey('precision-survey-skip')));
      await tester.pumpAndSettle();
      expect(state.precisionRecommendationPrompted, isTrue);
      expect(state.recommendationProfile, isNull);
      expect(find.text('오늘의 첫 운동 추천'), findsOneWidget);

      state.dispose();
    },
  );

  testWidgets('precision survey saves an account profile then continues', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(432, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    state.sessions.clear();
    state.setMemberProfile(goals: const ['건강 유지']);
    final targetDate = state.dateOnly(DateTime.now());

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: DailyWorkoutScreen(date: targetDate),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('운동 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('precision-survey-start')));
    await tester.pumpAndSettle();

    expect(find.text('정밀 운동 추천 설문'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('recommendation-profile-save')),
    );
    await tester.tap(find.byKey(const ValueKey('recommendation-profile-save')));
    await tester.pumpAndSettle();

    expect(state.precisionRecommendationPrompted, isTrue);
    expect(state.recommendationProfile, isNotNull);
    expect(state.recommendationProfile!.availableEquipment, {
      TrainingEquipment.bodyweight,
    });
    expect(find.text('오늘의 첫 운동 추천'), findsOneWidget);

    state.dispose();
  });

  testWidgets('empty day workout add offers and applies the first exercise', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(432, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    state.sessions.clear();
    state.setMemberProfile(goals: const ['근육 증가']);
    state.markPrecisionRecommendationPrompted();
    final historyDate = DateTime(2026, 11, 2);
    final targetDate = DateTime(2026, 11, 3);
    state.addExercise(historyDate, state.exercises.first);
    final bench = state.sessions[historyDate]!.exercises.single;
    for (final set in bench.sets) {
      state.updateSet(set, weight: 100, reps: 10);
      state.toggleSet(set);
    }
    state.cancelRestTimer();
    final recommendation = state.firstExerciseRecommendationForDate(
      targetDate,
    )!;

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: DailyWorkoutScreen(date: targetDate),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('NEXT SESSION'), findsNothing);
    await tester.tap(find.text('운동 추가'));
    await tester.pumpAndSettle();

    expect(find.text('오늘의 첫 운동 추천'), findsOneWidget);
    expect(find.text(recommendation.template.name), findsOneWidget);
    expect(find.textContaining('중량 직접 선택'), findsOneWidget);
    expect(find.textContaining('근거 논문'), findsOneWidget);
    await tester.tap(find.text('추천 운동 추가'));
    await tester.pumpAndSettle();

    final exercise = state.sessions[targetDate]!.exercises.single;
    expect(exercise.template.id, recommendation.template.id);
    expect(exercise.sets, hasLength(recommendation.sets));
    expect(exercise.sets.map((set) => set.weight), everyElement(0));
    state.dispose();
  });

  testWidgets('no equipment replaces the recommendation before adding', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(432, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    state.sessions.clear();
    state.setMemberProfile(goals: const ['근력 향상']);
    state.markPrecisionRecommendationPrompted();
    final targetDate = DateTime(2026, 11, 4);
    final first = state.firstExerciseRecommendationForDate(targetDate)!;
    final second = state.firstExerciseRecommendationForDate(
      targetDate,
      excludedTemplateIds: {first.template.id},
    )!;

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: DailyWorkoutScreen(date: targetDate),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('운동 추가'));
    await tester.pumpAndSettle();

    expect(find.text(first.template.name), findsOneWidget);
    await tester.tap(find.byKey(const Key('recommendation-no-equipment')));
    await tester.pumpAndSettle();

    expect(second.template.id, isNot(first.template.id));
    expect(find.text(second.template.name), findsOneWidget);
    await tester.tap(find.text('추천 운동 추가'));
    await tester.pumpAndSettle();
    expect(
      state.sessions[targetDate]!.exercises.single.template.id,
      second.template.id,
    );
    state.dispose();
  });

  testWidgets('dismissing an empty-day recommendation opens manual picker', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(432, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    state.sessions.clear();
    state.setMemberProfile(goals: const ['근력 향상']);
    state.markPrecisionRecommendationPrompted();
    final targetDate = DateTime(2026, 11, 3);

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: DailyWorkoutScreen(date: targetDate),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('운동 추가'));
    await tester.pumpAndSettle();
    expect(find.text('오늘의 첫 운동 추천'), findsOneWidget);
    expect(find.text('직접 선택'), findsOneWidget);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseLibraryScreen), findsOneWidget);
    expect(find.byKey(const Key('exercise-muscle-grid')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('운동 추가'));
    await tester.pumpAndSettle();
    expect(find.text('오늘의 첫 운동 추천'), findsNothing);
    expect(find.byType(ExerciseLibraryScreen), findsOneWidget);
    state.dispose();
  });

  testWidgets('recommendation off opens the manual picker immediately', (
    tester,
  ) async {
    final targetDate = DateTime(2026, 11, 3);
    final state = AppState();
    await state.initialize();
    state.sessions.clear();
    state.setMemberProfile(goals: const ['근력 향상']);
    state.setAutoRecommendNextExercise(false);

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: DailyWorkoutScreen(date: targetDate),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('운동 추가'));
    await tester.pumpAndSettle();

    expect(find.text('오늘의 첫 운동 추천'), findsNothing);
    expect(find.byType(ExerciseLibraryScreen), findsOneWidget);
    state.dispose();
  });

  testWidgets('set completion reports the newly earned PR types', (
    tester,
  ) async {
    final date = DateTime(2026, 10, 1);
    final state = AppState();
    await state.initialize();
    state.addExercise(date, state.exercises.first);
    final exercise = state.sessions[date]!.exercises.single;
    state.updateSet(exercise.sets.first, weight: 40);

    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: ExerciseSetScreen(date: date, exercise: exercise),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();

    expect(find.textContaining('중량 PR'), findsOneWidget);
    expect(find.textContaining('반복 PR'), findsOneWidget);
    expect(find.textContaining('e1RM PR'), findsOneWidget);
    state.cancelRestTimer();
    state.dispose();
  });

  testWidgets('calendar long-press drag copies a workout onto another date', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    final now = DateTime.now();
    final source = DateTime(now.year, now.month, 7);
    final target = DateTime(now.year, now.month, 22);
    state.addExercise(source, state.exercises.first);
    state.sessions.remove(target);

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: const Scaffold(body: CalendarScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sourceFinder = find.text('7');
    final targetFinder = find.text('22');
    final gesture = await tester.startGesture(tester.getCenter(sourceFinder));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveTo(tester.getCenter(targetFinder));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(state.sessions[target], isNotNull);
    expect(state.sessions[target]!.exercises, isNotEmpty);
    expect(state.sessions[source]!.exercises, isNotEmpty);
    expect(find.textContaining('운동 1개를 복사했어요.'), findsOneWidget);

    state.dispose();
  });

  testWidgets('routine editor changes exercise selection and persists it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    final routine = state.routines.first;

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RoutineEditorScreen(routine: routine),
                    ),
                  ),
                  child: const Text('편집 열기'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('편집 열기'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '수정한 상체 루틴');
    await tester.tap(find.byTooltip('바벨 벤치 프레스 제거'));
    await tester.ensureVisible(find.text('운동 추가·삭제'));
    await tester.tap(find.text('운동 추가·삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('스쿼트'));
    await tester.pump();
    await tester.tap(find.textContaining('선택 완료'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('변경사항 저장'));
    await tester.tap(find.text('변경사항 저장'));
    await tester.pumpAndSettle();

    final updated = state.routines.firstWhere((item) => item.id == routine.id);
    expect(updated.name, '수정한 상체 루틴');
    expect(updated.exercises.map((exercise) => exercise.id), contains('squat'));
    expect(
      updated.exercises.map((exercise) => exercise.id),
      isNot(contains('bench')),
    );

    state.dispose();
  });

  testWidgets('daily workout loads a saved routine immediately', (
    tester,
  ) async {
    final date = DateTime(2026, 12, 31);
    final state = await pumpWorkoutScreen(
      tester,
      DailyWorkoutScreen(date: date),
    );
    state.sessions.remove(date);
    state.sessionFor(date);
    await tester.pump();

    expect(find.text('운동 추가'), findsOneWidget);
    expect(find.text('루틴 불러오기'), findsOneWidget);
    await tester.tap(find.text('루틴 불러오기'));
    await tester.pumpAndSettle();
    final routine = state.routines.first;
    await tester.tap(find.text(routine.name).last);
    await tester.pumpAndSettle();

    expect(state.sessions[date]!.exercises.length, routine.exercises.length);
    expect(
      find.textContaining('운동 ${routine.exercises.length}개를 적용했어요.'),
      findsOneWidget,
    );

    state.dispose();
  });

  test(
    'copy and routine application merge without duplicate exercises',
    () async {
      final state = AppState();
      await state.initialize();
      state.sessions.clear();
      final source = DateTime(2026, 9, 1);
      final target = DateTime(2026, 9, 2);
      state.addExercise(source, state.exercises[0]);
      state.addExercise(source, state.exercises[2]);
      state.addExercise(target, state.exercises[0]);

      expect(state.copySession(source, target), 1);
      expect(state.copySession(source, target), 0);
      expect(
        state.sessions[target]!.exercises.map((item) => item.template.id),
        ['bench', 'squat'],
      );

      final routine = RoutineData(
        id: 'merge_test',
        name: '병합 테스트',
        description: '중복 없이 병합하는 테스트 루틴',
        color: Colors.blue,
        exercises: [state.exercises[2], state.exercises[4]],
      );
      expect(state.applyRoutine(routine, target), 1);
      expect(state.applyRoutine(routine, target), 0);
      expect(
        state.sessions[target]!.exercises.map((item) => item.template.id),
        ['bench', 'squat', 'latpull'],
      );

      state.dispose();
    },
  );

  test('routine application preserves every planned set field', () async {
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    state.sessions.clear();
    final target = DateTime(2026, 10, 9);
    final exercise = state.exercises.first;
    final routine = RoutineData(
      id: 'planned-sets',
      name: '원본 세트 보존',
      description: '공유 루틴 적용 테스트',
      color: Colors.teal,
      exercises: [exercise],
      setPlans: {
        exercise.id: const [
          RoutineSetPlan(
            number: 1,
            weight: 20,
            reps: 12,
            type: '웜업',
            restSeconds: 45,
          ),
          RoutineSetPlan(
            number: 2,
            weight: 80,
            reps: 8,
            type: '일반',
            restSeconds: 120,
          ),
          RoutineSetPlan(
            number: 3,
            weight: 60,
            reps: 10,
            type: '드랍',
            restSeconds: 30,
          ),
        ],
      },
    );

    expect(state.applyRoutine(routine, target), 1);
    final sets = state.sessions[target]!.exercises.single.sets;
    expect(sets.map((set) => set.number), [1, 2, 3]);
    expect(sets.map((set) => set.weight), [20, 80, 60]);
    expect(sets.map((set) => set.reps), [12, 8, 10]);
    expect(sets.map((set) => set.type), ['웜업', '일반', '드랍']);
    expect(sets.map((set) => set.restSeconds), [45, 120, 30]);
    expect(sets.every((set) => !set.completed), isTrue);
  });

  testWidgets('rest timer stays above a pushed workout route', (tester) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = MemoryAppRepository(
      initialSnapshot: const AppSnapshot(
        role: UserRole.member,
        isDarkMode: false,
        weightUnit: 'kg',
        restDefaultSeconds: 90,
        sessions: {},
        routines: [],
      ),
    );
    await tester.pumpWidget(SetflowApp(repository: repository));
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();

    final calendarContext = tester.element(find.byType(CalendarScreen));
    final state = AppScope.of(calendarContext);
    state.startRestTimer(90);
    await tester.pump();
    expect(find.text('휴식 중'), findsOneWidget);

    Navigator.of(calendarContext).push(
      MaterialPageRoute(
        builder: (_) => DailyWorkoutScreen(date: DateTime(2026, 7, 23)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DailyWorkoutScreen), findsOneWidget);
    expect(find.text('휴식 중'), findsOneWidget);

    state.cancelRestTimer();
  });
}
