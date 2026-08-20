import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/routine_catalog_repository.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/common.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    AppState state,
    Widget screen, {
    Size size = const Size(432, 1000),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(theme: SetflowTheme.light, home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty-day cardio suggestion uses time distance and RPE', (
    tester,
  ) async {
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    state.setMemberProfile(goals: const ['체중 감량']);
    final cardio = state.exercises.firstWhere(
      (exercise) => exercise.id == 'brisk_walk',
    );
    final historyDate = state.dateOnly(
      DateTime.now().subtract(const Duration(days: 2)),
    );
    final today = state.dateOnly(DateTime.now());
    state.sessions.remove(today);
    state.addExercise(historyDate, cardio);
    final historicalSet =
        state.sessions[historyDate]!.exercises.single.sets.single;
    state.updateSet(
      historicalSet,
      durationSeconds: 30 * 60,
      distanceKm: 3,
      intensityRpe: 4,
    );
    state.toggleSet(historicalSet, startRest: false);

    await pumpScreen(tester, state, DailyWorkoutScreen(date: today));
    await tester.tap(find.text('운동 추가'));
    await tester.pumpAndSettle();

    final recommendationCard = find.byType(SetflowCard).last;
    final recommendationText = tester
        .widgetList<Text>(
          find.descendant(of: recommendationCard, matching: find.byType(Text)),
        )
        .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
        .join(' ');
    expect(find.text('오늘의 첫 운동 추천'), findsOneWidget);
    expect(recommendationText, contains('빠르게 걷기'));
    expect(recommendationText, contains('40분'));
    expect(recommendationText, contains('4.0km'));
    expect(recommendationText, contains('RPE 3–4'));
    expect(recommendationText, isNot(contains('kg')));
    expect(recommendationText, isNot(contains('회')));
    expect(recommendationText, isNot(contains('세트')));
    await state.flushPersistence();
  });

  testWidgets('calendar and dashboard keep mixed workout metrics separate', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    final today = state.dateOnly(DateTime.now());

    state.addExercise(today, state.exercises.first);
    final resistanceSet = state.sessions[today]!.exercises.first.sets.first;
    state.updateSet(resistanceSet, weight: 50, reps: 10);
    state.toggleSet(resistanceSet, startRest: false);

    final cardio = state.exercises.firstWhere(
      (exercise) => exercise.id == 'rowing_machine',
    );
    state.addExercise(today, cardio);
    final cardioSet = state.sessions[today]!.exercises.last.sets.single;
    state.updateSet(
      cardioSet,
      durationSeconds: 30 * 60 + 30,
      distanceKm: 5,
      intensityRpe: 4,
    );
    state.toggleSet(cardioSet, startRest: false);

    await pumpScreen(tester, state, const Scaffold(body: CalendarScreen()));

    try {
      expect(find.text('500kg · 30.5분'), findsOneWidget);
      expect(find.text('30.5분 유산소'), findsOneWidget);
      expect(find.text('500kg'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'근력 볼륨 500kg.*유산소 1구간 30\.5분 완료')),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }

    await pumpScreen(tester, state, const DashboardScreen());
    expect(find.text('근력 볼륨'), findsOneWidget);
    expect(find.text('이번 주 유산소 30.5분'), findsOneWidget);
    expect(find.text('시간·거리·RPE 기록'), findsOneWidget);
    expect(find.text('주간 근력 볼륨'), findsOneWidget);
    await state.flushPersistence();
  });

  testWidgets('cardio-only dashboard uses minutes instead of weight volume', (
    tester,
  ) async {
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    final today = state.dateOnly(DateTime.now());
    final cardio = state.exercises.firstWhere(
      (exercise) => exercise.id == 'stationary_bike',
    );
    state.addExercise(today, cardio);
    final cardioSet = state.sessions[today]!.exercises.single.sets.single;
    state.updateSet(cardioSet, durationSeconds: 45 * 60, intensityRpe: 4);
    state.toggleSet(cardioSet, startRest: false);

    await pumpScreen(tester, state, const DashboardScreen());

    expect(find.text('유산소 시간'), findsOneWidget);
    expect(find.text('45 분', findRichText: true), findsOneWidget);
    expect(find.text('주간 유산소 시간'), findsOneWidget);
    expect(find.text('근력 볼륨'), findsNothing);
    await state.flushPersistence();
  });

  testWidgets('market searches exercise names and filters every cardio type', (
    tester,
  ) async {
    final state = AppState(routineCatalogRepository: _RoutineCatalogStub());
    await state.initialize();
    addTearDown(state.dispose);
    await pumpScreen(tester, state, const MarketScreen());

    await tester.enterText(find.byType(TextFormField), '로잉 머신');
    await tester.pumpAndSettle();
    expect(find.text('아침 컨디셔닝'), findsOneWidget);
    expect(find.text('기초 근력'), findsNothing);

    await tester.enterText(find.byType(TextFormField), '');
    await tester.tap(find.widgetWithText(ChoiceChip, '체중 감량'));
    await tester.pumpAndSettle();
    expect(find.text('아침 컨디셔닝'), findsOneWidget);
    expect(find.text('기초 근력'), findsNothing);
  });
}

class _RoutineCatalogStub implements RoutineCatalogRepository {
  @override
  Future<bool> hasActivePaidPlan() async => false;

  @override
  Future<List<RoutineCatalogItem>> listPublished() async => [
    RoutineCatalogItem(
      id: 'cardio-routine',
      coachingRoutineId: 'cardio-source',
      title: '아침 컨디셔닝',
      description: '편안한 강도의 전신 유산소',
      authorName: '유산소 코치',
      difficulty: '초급',
      accessTier: RoutineCatalogAccessTier.free,
      authorType: RoutineAuthorType.trainer,
      exercises: const [
        RoutineCatalogExercise(
          id: 'cardio-exercise',
          baseExerciseId: 'rowing_machine',
          name: '로잉 머신',
          targetMuscle: '유산소',
          orderIndex: 0,
          sets: [],
        ),
      ],
    ),
    RoutineCatalogItem(
      id: 'strength-routine',
      coachingRoutineId: 'strength-source',
      title: '기초 근력',
      description: '저항운동 입문 루틴',
      authorName: '근력 코치',
      difficulty: '초급',
      accessTier: RoutineCatalogAccessTier.free,
      authorType: RoutineAuthorType.trainer,
      exercises: const [
        RoutineCatalogExercise(
          id: 'strength-exercise',
          baseExerciseId: 'squat',
          name: '스쿼트',
          targetMuscle: '하체',
          orderIndex: 0,
          sets: [],
        ),
      ],
    ),
  ];

  @override
  Future<void> updateAccessTier(
    String routineId,
    RoutineCatalogAccessTier accessTier,
  ) async {}
}
