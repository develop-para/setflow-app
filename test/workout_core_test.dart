import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/main.dart';
import 'package:setflow/screens/member_screens.dart';
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
    expect(find.text('바벨 벤치 프레스'), findsOneWidget);

    state.dispose();
  });

  testWidgets(
    'set editor sheet opens from a set row, validates direct input, and '
    'deletes with confirmation',
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

      // Tapping the row (not the check control) opens the athletic bottom
      // sheet editor — the PopupMenu-era inline steppers are gone.
      await tester.tap(find.text('40kg').first);
      await tester.pumpAndSettle();
      expect(find.text('바벨 벤치 프레스 · 1번째 세트'), findsOneWidget);

      await tester.tap(find.text('40').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '1200');
      await tester.tap(find.text('저장'));
      await tester.pump();
      expect(find.text('0~999 범위로 입력해주세요.'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '42.5');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(exercise.sets.first.weight, 42.5);

      // Destructive delete now lives in the sheet, confirmed with the same
      // themed AlertDialog as before.
      await tester.tap(find.text('세트 삭제'));
      await tester.pumpAndSettle();
      expect(find.text('1세트를 삭제할까요?'), findsOneWidget);
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(exercise.sets, hasLength(2));
      expect(exercise.sets.first.number, 1);

      state.dispose();
    },
  );

  testWidgets('rest timer stays above a pushed workout route', (tester) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = MemoryAppRepository(
      initialSnapshot: const AppSnapshot(
        role: UserRole.member,
        themeMode: ThemeMode.light,
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
