import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/theme.dart';

/// 달력 아래는 필요한 내 데이터만 둔다 — 최근 기록, 최근 운동, 나의 루틴.
///
/// 오늘 진행 블록과 이번 주 요약, 전문가 루틴 광고, 함께 운동 광고는 홈에서
/// 제거됐다. 기록 기반 섹션은 값이 없으면 섹션째 사라진다.
void main() {
  Future<AppState> pumpHome(
    WidgetTester tester, {
    void Function(AppState state)? seed,
  }) async {
    await tester.binding.setSurfaceSize(const Size(393, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    seed?.call(state);
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
    await tester.pump(const Duration(milliseconds: 400));
    return state;
  }

  DateTime today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// [date]에 첫 종목을 넣고 세트를 전부 [weight]kg × [reps]로 끝낸다.
  void finishWorkout(AppState state, DateTime date, {double weight = 60}) {
    state.addExercise(date, state.exercises.first);
    for (final set in state.sessions[date]!.exercises.single.sets) {
      state.updateSet(set, weight: weight, reps: 8);
      state.toggleSet(set);
    }
  }

  testWidgets('a fresh account hides removed summaries and empty sections', (
    tester,
  ) async {
    await pumpHome(tester);

    expect(find.byKey(const ValueKey('home-today')), findsNothing);
    expect(find.text('오늘 운동 시작'), findsNothing);
    expect(find.byKey(const ValueKey('home-week')), findsNothing);
    expect(find.text('이번 주는 아직 기록이 없어요'), findsNothing);
    // 값이 없는 섹션은 빈 카드로 자리를 차지하지 않는다.
    expect(find.text('최근 기록'), findsNothing);
    expect(find.text('최근 운동'), findsNothing);
    // 지난 광고 카드들은 없다.
    expect(find.text('전문가 루틴'), findsNothing);
    expect(find.text('함께 운동'), findsNothing);
  });

  testWidgets('today summary stays removed when an active record exists', (
    tester,
  ) async {
    await pumpHome(
      tester,
      seed: (state) => state.addExercise(today(), state.exercises.first),
    );

    expect(find.byKey(const ValueKey('home-today')), findsNothing);
    expect(find.byKey(const ValueKey('home-today-done')), findsNothing);
    expect(find.text('이어서 기록'), findsNothing);
  });

  testWidgets('weekly summary stays removed when weekly records exist', (
    tester,
  ) async {
    await pumpHome(
      tester,
      seed: (state) {
        finishWorkout(state, today());
        finishWorkout(state, today().subtract(const Duration(days: 7)));
        finishWorkout(state, today().subtract(const Duration(days: 8)));
      },
    );

    expect(find.byKey(const ValueKey('home-week')), findsNothing);
    expect(find.byKey(const ValueKey('home-week-workouts')), findsNothing);
    expect(find.textContaining('지난주'), findsNothing);
  });

  testWidgets(
    'a first-ever lift is not a record, and zero volume is not "0kg"',
    (tester) async {
      // "일부러 만든 느낌": 한 번 한 종목의 첫 세트가 "최근 기록"에 오르고, 맨몸
      // 세트가 "1세트 · 0kg"으로 찍혔다. 기록은 이전 최고를 넘었을 때만, kg은
      // 볼륨이 있을 때만.
      await pumpHome(
        tester,
        seed: (state) => finishWorkout(
          state,
          today().subtract(const Duration(days: 2)),
          weight: 0,
        ),
      );

      expect(find.text('최근 기록'), findsNothing, reason: '첫 기록은 갱신이 아니다');
      expect(find.textContaining('0kg'), findsNothing);
      expect(find.textContaining('세트'), findsWidgets);
    },
  );

  testWidgets('a calendar day names its muscles and blends their colours', (
    tester,
  ) async {
    // "종목보다 부위를 표기하는 게 나은 것 같아 … 2개 이상이면 그 색상을
    // 그라데이션으로 섞으면 좋겠어." 칸 글자는 "가슴 · 등", 막대는 두 색.
    final now = today();
    await pumpHome(
      tester,
      seed: (state) {
        state.addExercise(
          now,
          state.exercises.firstWhere((t) => t.muscle == '가슴'),
        );
        state.addExercise(
          now,
          state.exercises.firstWhere((t) => t.muscle == '등'),
        );
      },
    );

    expect(find.text('가슴 · 등'), findsOneWidget);
    // 막대가 아니라 **칸 배경**이 부위 색이다 — 가슴 틴트에서 등 틴트로.
    final tint = find.byKey(
      ValueKey('calendar-tint-${now.year}${now.month}${now.day}'),
    );
    expect(tint, findsOneWidget);
    final gradient =
        (tester.widget<Ink>(tint).decoration! as BoxDecoration).gradient!
            as LinearGradient;
    expect(gradient.colors.toSet(), hasLength(2), reason: '가슴색→등색 그라데이션');
    expect(
      gradient.colors.every((c) => c.a < 1),
      isTrue,
      reason: '배경은 옅은 틴트여야 글자가 읽힌다',
    );
  });

  testWidgets('recent bests and recent sessions come from the record', (
    tester,
  ) async {
    await pumpHome(
      tester,
      seed: (state) {
        finishWorkout(state, today().subtract(const Duration(days: 3)));
        finishWorkout(
          state,
          today().subtract(const Duration(days: 1)),
          weight: 80,
        );
      },
    );

    expect(find.text('최근 기록'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-bests')), findsOneWidget);
    final figures = tester
        .widgetList<RichText>(
          find.descendant(
            of: find.byKey(const ValueKey('home-bests')),
            matching: find.byType(RichText),
          ),
        )
        .map((r) => r.text.toPlainText());
    expect(figures, contains('80kg × 8'), reason: '넘긴 기록이 큰 숫자로');
    expect(find.text('최근 운동'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-today')), findsNothing);
    expect(find.text('오늘은 아직 기록 전이에요'), findsNothing);
  });
}
