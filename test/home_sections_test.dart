import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/theme/icons.dart';

/// 홈은 내 데이터에서 시작한다 — 오늘, 이번 주, 최근 기록, 최근 운동.
///
/// 캘린더가 기록 탭으로 옮겨 가면서(2026-09-01) 홈은 소식의 자리가 됐다.
/// 기록에서 계산한 값은 값이 없으면 섹션째 사라지고, 커뮤니티·추천 루틴은
/// 헤어라인 줄로 선다. 달력 칸 테스트는 CalendarScreen을 직접 띄운다.
void main() {
  Future<AppState> pumpScreen(
    WidgetTester tester,
    Widget Function(AppState state) child, {
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
          home: Scaffold(body: child(state)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    return state;
  }

  Future<AppState> pumpHome(
    WidgetTester tester, {
    VoidCallback? onOpenRecord,
    void Function(AppState state)? seed,
  }) => pumpScreen(
    tester,
    (_) =>
        HomeScreen(onOpenRecord: onOpenRecord ?? () {}, onOpenCommunity: () {}),
    seed: seed,
  );

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

  testWidgets('a fresh account sees today, this week, and no empty sections', (
    tester,
  ) async {
    await pumpHome(tester);

    expect(find.byKey(const ValueKey('home-today')), findsOneWidget);
    expect(find.text('오늘 운동 시작'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-week')), findsOneWidget);
    expect(find.text('이번 주는 아직 기록이 없어요'), findsOneWidget);
    // 값이 없는 섹션은 빈 카드로 자리를 차지하지 않는다.
    expect(find.text('최근 기록'), findsNothing);
    expect(find.text('최근 운동'), findsNothing);
  });

  testWidgets('the home tail is news: community and market as hairline rows', (
    tester,
  ) async {
    // "홈에는 광고랑 다른 정보를" — 커뮤니티 새 글과 추천 루틴이 소식이다.
    // 8/30에 뺐던 것은 회색 광고 카드였고, 이번엔 카드가 아니라 줄이다.
    await pumpHome(tester);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('home-market')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('home-community')), findsOneWidget);
    expect(find.text('추천 루틴'), findsOneWidget);
  });

  testWidgets('today card follows the record and opens the record tab', (
    tester,
  ) async {
    var opened = 0;
    final state = await pumpHome(
      tester,
      onOpenRecord: () => opened++,
      seed: (state) => state.addExercise(today(), state.exercises.first),
    );
    final total = state.sessions[today()]!.totalSets;

    // 잉크 블록의 큰 숫자는 끝낸 세트, 그 옆 작은 글자가 전체다.
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('home-today-done'))).data,
      '0',
    );
    expect(find.text('/$total 세트'), findsOneWidget);
    expect(find.text('이어서 기록'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-open-record')));
    expect(opened, 1);
  });

  testWidgets('this week counts workouts and compares with last week', (
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

    // 상자 없는 큰 숫자 셋 — 첫 번째가 운동 횟수다.
    // Text 위젯도 안에서 RichText를 만드니 첫 번째(숫자+단위)만 본다.
    final workouts = tester.widget<RichText>(
      find
          .descendant(
            of: find.byKey(const ValueKey('home-week-workouts')),
            matching: find.byType(RichText),
          )
          .first,
    );
    expect(workouts.text.toPlainText(), startsWith('1회'));
    // 이번 주 1회, 지난주 2회(오늘-7·오늘-8이 같은 주에 있을 수도, 아닐 수도
    // 있다 — 일요일이면 -7은 지난주 마지막 날이 아니라 이번 주 첫날이다).
    // 커뮤니티 데모 글에도 "지난주"가 나올 수 있으니 주간 섹션 안에서만 찾는다.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-week')),
        matching: find.textContaining('지난주'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('this week checks a day only after every set is complete', (
    tester,
  ) async {
    final date = today();
    final state = await pumpHome(
      tester,
      seed: (state) => state.addExercise(date, state.exercises.first),
    );
    await state.toggleSet(
      state.sessions[date]!.exercises.single.sets.first,
      startRest: false,
    );
    await tester.pump();
    final day = find.byKey(
      ValueKey('home-week-day-${date.year}-${date.month}-${date.day}'),
    );

    expect(day, findsOneWidget);
    expect(
      find.descendant(of: day, matching: find.byIcon(SetflowIcons.setComplete)),
      findsNothing,
      reason: '일부 세트만 기록한 날은 완료로 표시하면 안 된다',
    );

    for (final set in state.sessions[date]!.exercises.single.sets.skip(1)) {
      await state.toggleSet(set, startRest: false);
    }
    await tester.pump();

    expect(
      find.descendant(of: day, matching: find.byIcon(SetflowIcons.setComplete)),
      findsOneWidget,
      reason: '그날의 모든 세트를 끝낸 뒤에만 완료 체크가 표시돼야 한다',
    );
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
    // 달력은 이제 기록 탭의 것이라 CalendarScreen을 직접 띄운다.
    final now = today();
    await pumpScreen(
      tester,
      (_) => const CalendarScreen(),
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
    expect(find.byKey(const ValueKey('home-today')), findsOneWidget);
    expect(find.text('오늘은 아직 기록 전이에요'), findsOneWidget);
  });
}
