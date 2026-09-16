import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/workout_dashboard_screen.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

const press = ExerciseTemplate(
  id: 'my-press',
  name: '내 프레스',
  muscle: '가슴',
  icon: Icons.fitness_center,
);
const oldRow = ExerciseTemplate(
  id: 'old-row',
  name: '오래된 로우',
  muscle: '등',
  icon: Icons.fitness_center,
);
const pushup = ExerciseTemplate(
  id: 'my-pushup',
  name: '맨몸 푸시업',
  muscle: '가슴',
  icon: Icons.fitness_center,
  measurement: ExerciseMeasurement.repsOnly,
);
const plank = ExerciseTemplate(
  id: 'my-plank',
  name: '플랭크',
  muscle: '복근',
  icon: Icons.fitness_center,
  measurement: ExerciseMeasurement.duration,
);
const run = ExerciseTemplate(
  id: 'my-run',
  name: '달리기',
  muscle: '유산소',
  icon: Icons.directions_run,
);

DateTime get today {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

void record(
  AppState state,
  ExerciseTemplate template, {
  int ago = 0,
  double weight = 60,
  int reps = 8,
  int seconds = 0,
  double km = 0,
  double rpe = 0,
  bool completed = true,
  String? id,
}) {
  final date = today.subtract(Duration(days: ago));
  state.sessions
      .putIfAbsent(date, () => WorkoutSession(date: date, exercises: []))
      .exercises
      .add(
        WorkoutExercise(
          id: id ?? '${template.id}-$ago',
          template: template,
          sets: [
            WorkoutSetEntry(
              number: 1,
              weight: weight,
              reps: reps,
              completed: completed,
              durationSeconds: seconds,
              distanceKm: km,
              intensityRpe: rpe,
            ),
          ],
        ),
      );
}

void main() {
  Future<AppState> pump(
    WidgetTester tester, {
    void Function(AppState)? seed,
    Widget screen = const DashboardScreen(),
    Size size = const Size(393, 1000),
    double scale = 1,
    bool dark = false,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    seed?.call(state);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: dark ? SetflowTheme.dark : SetflowTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              padding: const EdgeInsets.only(bottom: 28),
            ),
            child: child!,
          ),
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('guests can start logging from an honest empty dashboard', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('아직 완료한 운동이 없어요'), findsOneWidget);
    expect(find.text('0개'), findsOneWidget);
    await reveal(tester, find.text('운동 기록하기'));
    await tester.tap(find.text('운동 기록하기'));
    await tester.pumpAndSettle();
    expect(find.byType(DailyWorkoutScreen), findsOneWidget);
  });

  testWidgets(
    'all history includes custom old high-rep bodyweight hold and cardio exercises',
    (tester) async {
      await pump(
        tester,
        seed: (state) {
          record(state, press, reps: 20);
          record(state, oldRow, ago: 400);
          record(state, pushup, weight: 0, reps: 25);
          record(state, plank, weight: 0, reps: 0, seconds: 45);
          record(state, run, seconds: 1800, km: 5);
          record(
            state,
            const ExerciseTemplate(
              id: 'planned',
              name: '계획 운동',
              muscle: '하체',
              icon: Icons.fitness_center,
            ),
            completed: false,
          );
          record(
            state,
            const ExerciseTemplate(
              id: 'seed',
              name: '예시 운동',
              muscle: '하체',
              icon: Icons.fitness_center,
            ),
            id: 'seed_example',
          );
        },
      );
      expect(find.text('5개 종목'), findsOneWidget);
      for (final template in [press, oldRow, pushup, plank, run]) {
        await tester.enterText(
          find.byKey(const ValueKey('dashboard-search')),
          template.name,
        );
        await tester.pumpAndSettle();
        await reveal(
          tester,
          find.byKey(ValueKey('exercise-kpi-${template.id}')),
        );
        expect(
          find.descendant(
            of: find.byKey(ValueKey('exercise-kpi-${template.id}')),
            matching: find.text(template.name),
          ),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search muscle period sorting and reset apply to the whole exercise list',
    (tester) async {
      await pump(
        tester,
        seed: (state) {
          record(state, press);
          record(state, oldRow, ago: 60);
          record(state, oldRow, ago: 61);
          record(state, pushup, ago: 2, weight: 0);
        },
      );
      await tester.tap(find.byTooltip('운동 정렬'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('많이 한 순').last);
      await tester.pumpAndSettle();
      final rows = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('exercise-kpi-'),
      );
      expect(
        tester.widget(rows.first).key,
        const ValueKey('exercise-kpi-old-row'),
      );
      await tester.tap(find.widgetWithText(ChoiceChip, '가슴'));
      await tester.pumpAndSettle();
      expect(find.text('2개 종목'), findsOneWidget);
      expect(find.byKey(const ValueKey('exercise-kpi-old-row')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('dashboard-search')),
        '프레스',
      );
      await tester.pumpAndSettle();
      expect(find.text('1개 종목'), findsOneWidget);
      await tester.tap(find.byTooltip('검색어 지우기'));
      await tester.tap(find.widgetWithText(ChoiceChip, '전체 부위'));
      await tester.enterText(
        find.byKey(const ValueKey('dashboard-search')),
        '로우',
      );
      await tester.tap(find.byKey(const ValueKey('stats-period-month')));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('전체 기록 보기'));
      expect(find.text('이 조건에 맞는 기록이 없어요'), findsOneWidget);
      await tester.tap(find.text('전체 기록 보기'));
      await tester.pumpAndSettle();
      expect(find.text('3개 종목'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('dashboard-search')))
            .controller!
            .text,
        isEmpty,
      );
    },
  );

  testWidgets(
    'weighted details show actual KPIs selectable trend and expandable sets',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await pump(
          tester,
          seed: (state) {
            record(state, press, ago: 5, weight: 60);
            record(state, press, weight: 80);
          },
        );
        await tester.enterText(
          find.byKey(const ValueKey('dashboard-search')),
          '프레스',
        );
        await tester.pumpAndSettle();
        await reveal(
          tester,
          find.byKey(const ValueKey('exercise-kpi-my-press')),
        );
        await tester.tap(find.byKey(const ValueKey('exercise-kpi-my-press')));
        await tester.pumpAndSettle();
        expect(find.byType(ExerciseKpiScreen), findsOneWidget);
        expect(find.text('1,120 kg·회'), findsOneWidget);
        await reveal(tester, find.byKey(const ValueKey('exercise-kpi-chart')));
        expect(find.text('직전 기록 대비 +20 kg'), findsOneWidget);
        expect(find.bySemanticsLabel('최고 중량 변화'), findsOneWidget);
        await tester.tap(find.byTooltip('이전 기록'));
        await tester.pumpAndSettle();
        expect(find.text('60 kg'), findsOneWidget);
        await tester.tap(find.byTooltip('다음 기록'));
        await tester.pumpAndSettle();
        expect(find.text('직전 기록 대비 +20 kg'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('kpi-metric-volume')));
        await tester.pumpAndSettle();
        expect(find.text('640 kg·회'), findsOneWidget);
        await reveal(tester, find.byType(ExpansionTile).first);
        await tester.tap(find.byType(ExpansionTile).first);
        await tester.pumpAndSettle();
        expect(find.text('1세트 · 80 kg × 8회'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('dashboard-search')))
              .controller!
              .text,
          '프레스',
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'bodyweight and timed details have relevant metrics without fake 1RM',
    (tester) async {
      for (final template in [pushup, plank, run]) {
        await pump(
          tester,
          screen: ExerciseKpiScreen(template: template),
          seed: (state) {
            record(
              state,
              template,
              weight: 0,
              reps: 25,
              seconds: 1200,
              km: 3,
              rpe: 5,
            );
          },
        );
        expect(find.text('최고 추정 1RM'), findsNothing);
        expect(find.textContaining('kg'), findsNothing);
        if (template == pushup) expect(find.text('25회'), findsWidgets);
        if (template == plank) expect(find.text('최장 버티기'), findsWidgets);
        if (template == run) {
          expect(find.text('6:40 /km'), findsOneWidget);
          expect(find.text('RPE 5'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'the list is not truncated and recorded edits refresh its numbers',
    (tester) async {
      final state = await pump(
        tester,
        seed: (state) {
          for (var i = 0; i < 28; i++) {
            record(
              state,
              ExerciseTemplate(
                id: 'exercise-$i',
                name: '운동 ${i.toString().padLeft(2, '0')}',
                muscle: '등',
                icon: Icons.fitness_center,
              ),
            );
          }
        },
      );
      await reveal(
        tester,
        find.byKey(const ValueKey('exercise-kpi-exercise-27')),
      );
      expect(find.text('운동 27'), findsOneWidget);
      final set = state.sessions[today]!.exercises.last.sets.single;
      state.updateSet(set, weight: 90);
      await tester.pumpAndSettle();
      expect(find.text('90 kg'), findsOneWidget);
      await state.flushPersistence();
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'dashboard and detail fit 320px 2x text with a bottom inset (${dark ? 'dark' : 'light'})',
      (tester) async {
        await pump(
          tester,
          dark: dark,
          size: const Size(320, 640),
          scale: 2,
          seed: (state) {
            record(state, press, weight: 120, reps: 12);
            record(state, press, ago: 2, weight: 100, reps: 12);
            record(state, run, seconds: 2100, km: 5);
          },
        );
        await reveal(
          tester,
          find.byKey(const ValueKey('exercise-kpi-my-press')),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('exercise-kpi-my-press')));
        await tester.pumpAndSettle();
        await reveal(tester, find.byTooltip('이전 기록'));
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('이전 기록'));
        await tester.pumpAndSettle();
        await reveal(tester, find.byType(ExpansionTile).last);
        await tester.tap(find.byType(ExpansionTile).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
