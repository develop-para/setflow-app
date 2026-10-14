import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

final _day = DateTime(2026, 10, 4);
const _recommendationButton = ValueKey('exercise-library-recommendation');
const _equipmentButton = ValueKey('exercise-library-recommendation-equipment');

RecommendationProfile _bodyweightProfile() => RecommendationProfile(
  experienceLevel: TrainingExperienceLevel.beginner,
  availableEquipment: {TrainingEquipment.bodyweight},
  painRegions: {},
  painLevel: 0,
  restrictedMovements: {},
  injuryNote: '',
  recoveryStatus: TrainingRecoveryStatus.normal,
  recoveryRecordedAt: _day,
  updatedAt: _day,
);

Future<AppState> _pump(
  WidgetTester tester, {
  bool daily = false,
  bool small = false,
  bool dark = false,
  double keyboardInset = 0,
  ValueListenable<double>? keyboardInsets,
  VoidCallback? onAdded,
  void Function(AppState)? configure,
}) async {
  await tester.binding.setSurfaceSize(
    small ? const Size(320, 700) : const Size(432, 1100),
  );
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = AppState();
  await state.initialize();
  addTearDown(state.dispose);
  state.sessions.clear();
  state.setMemberProfile(goals: ['근육 증가']);
  state.setAutoRecommendNextExercise(true);
  state.markPrecisionRecommendationPrompted();
  state.setTrainingFocus(_day, {TrainingMuscle.chest});
  configure?.call(state);
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(
        theme: dark ? SetflowTheme.dark : SetflowTheme.light,
        builder: (context, child) {
          Widget withInsets(double inset) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(small ? 2 : 1),
              padding: const EdgeInsets.only(top: 24, bottom: 28),
              viewInsets: EdgeInsets.only(bottom: inset),
            ),
            child: child!,
          );
          if (keyboardInsets == null) return withInsets(keyboardInset);
          return ValueListenableBuilder<double>(
            valueListenable: keyboardInsets,
            builder: (_, inset, _) => withInsets(inset),
          );
        },
        home: daily
            ? DailyWorkoutScreen(date: _day)
            : ExerciseLibraryScreen(date: _day, onAdded: onAdded),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _dismissRecommendation(
  WidgetTester tester, {
  String title = '오늘의 첫 운동 추천',
}) async {
  Navigator.of(tester.element(find.text(title))).pop();
  await tester.pumpAndSettle();
}

void _expectSingleLibrary(WidgetTester tester, State original) {
  final library = find.byType(ExerciseLibraryScreen, skipOffstage: false);
  expect(library, findsOneWidget);
  expect(tester.state(library), same(original));
}

void main() {
  testWidgets('library recommendation button follows recommendation setting', (
    tester,
  ) async {
    final state = await _pump(tester);
    expect(find.byKey(_recommendationButton), findsOneWidget);
    expect(find.byKey(_equipmentButton), findsOneWidget);
    expect(find.text('운동 추천'), findsOneWidget);
    state.setAutoRecommendNextExercise(false);
    await tester.pumpAndSettle();
    expect(find.byKey(_recommendationButton), findsNothing);
    expect(find.byKey(_equipmentButton), findsNothing);
    state.setAutoRecommendNextExercise(true);
    await tester.pumpAndSettle();
    expect(find.byKey(_recommendationButton), findsOneWidget);
    await state.flushPersistence();
  });

  testWidgets(
    'library exposes bodyweight-only equipment and preserves manual selections when editing',
    (tester) async {
      final state = await _pump(
        tester,
        configure: (state) =>
            state.setRecommendationProfile(_bodyweightProfile()),
      );
      expect(find.text('추천 장비: 맨몸만'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '푸시업');
      await tester.pumpAndSettle();
      await _tap(tester, find.byTooltip('선택').first);
      expect(find.text('1개 추가'), findsOneWidget);
      final original = tester.state(find.byType(ExerciseLibraryScreen));
      await _tap(tester, find.byKey(_equipmentButton));
      final machines = find.byKey(const ValueKey('equipment-machines'));
      expect(machines.hitTestable(), findsOneWidget);
      await _tap(tester, machines);
      await _tap(
        tester,
        find.byKey(const ValueKey('recommendation-profile-save')),
      );
      _expectSingleLibrary(tester, original);
      expect(
        state.recommendationProfile!.availableEquipment,
        contains(TrainingEquipment.machines),
      );
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '푸시업',
      );
      expect(find.text('1개 추가'), findsOneWidget);
      expect(state.sessionFor(_day).exercises, isEmpty);
      await tester.pump(const Duration(seconds: 4));
    },
  );

  for (final permanent in [false, true]) {
    testWidgets(
      'bodyweight-only pushup exclusion can recover by choosing real equipment ($permanent)',
      (tester) async {
        var additions = 0;
        final state = await _pump(
          tester,
          onAdded: () => additions++,
          configure: (state) =>
              state.setRecommendationProfile(_bodyweightProfile()),
        );
        await _tap(tester, find.byKey(_recommendationButton));
        expect(find.text('푸시업'), findsOneWidget);
        await _tap(
          tester,
          find.byKey(const ValueKey('recommendation-exclusions')),
        );
        await _tap(
          tester,
          find.byKey(
            ValueKey(
              permanent
                  ? 'recommendation-exclude-always'
                  : 'recommendation-skip-today',
            ),
          ),
        );
        expect(find.textContaining('현재 장비·운동 부위 조건'), findsOneWidget);
        await _tap(
          tester,
          find.byKey(const ValueKey('recommendation-recovery-profile')),
        );
        await _tap(tester, find.byKey(const ValueKey('equipment-machines')));
        await _tap(
          tester,
          find.byKey(const ValueKey('recommendation-profile-save')),
        );
        expect(find.text('오늘의 첫 운동 추천'), findsOneWidget);
        await _tap(tester, find.text('추천 운동 추가'));
        expect(additions, 1);
        final session = state.sessionFor(_day);
        expect(session.exercises, hasLength(1));
        expect(session.exercises.single.template.id, isNot('pushup'));
        expect(session.exercises.single.template.muscle, '가슴');
        expect(
          permanent
              ? state.recommendationPreferences.excludedExerciseIds
              : session.skippedRecommendationIds,
          contains('pushup'),
        );
        await tester.pump(const Duration(seconds: 4));
      },
    );
  }

  testWidgets(
    'search with a keyboard keeps selected exercise addition reachable at 2x text',
    (tester) async {
      var additions = 0;
      final state = await _pump(
        tester,
        small: true,
        keyboardInset: 280,
        onAdded: () => additions++,
      );
      await tester.enterText(find.byType(TextFormField), '바벨 벤치 프레스');
      await tester.pumpAndSettle();
      await _tap(
        tester,
        find.descendant(
          of: find.widgetWithText(ListTile, '바벨 벤치 프레스'),
          matching: find.text('바벨 벤치 프레스'),
        ),
      );
      expect(find.byKey(_recommendationButton), findsNothing);
      expect(find.byKey(_equipmentButton), findsNothing);
      expect(find.text('1개 추가').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _tap(tester, find.text('1개 추가'));
      expect(additions, 1);
      expect(state.sessionFor(_day).exercises, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets('keyboard inset transitions preserve search focus and text', (
    tester,
  ) async {
    final insets = ValueNotifier<double>(0);
    addTearDown(insets.dispose);
    await _pump(tester, small: true, keyboardInsets: insets);
    await tester.enterText(find.byType(TextFormField), '바벨 벤치 프레스');
    await tester.pumpAndSettle();
    final focus = tester
        .widget<EditableText>(find.byType(EditableText))
        .focusNode;
    expect(focus.hasFocus, isTrue);
    for (final inset in [280.0, 0.0, 280.0]) {
      insets.value = inset;
      await tester.pumpAndSettle();
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.focusNode, same(focus));
      expect(focus.hasFocus, isTrue);
      expect(editable.controller.text, '바벨 벤치 프레스');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'after completing pushups equipment recovery offers a different next exercise',
    (tester) async {
      final state = await _pump(
        tester,
        onAdded: () {},
        configure: (state) {
          state.setRecommendationProfile(_bodyweightProfile());
          final first = state.firstExerciseRecommendationForDate(_day)!;
          expect(first.template.id, 'pushup');
          state.addRecommendedExercise(_day, first);
          for (final set in state.sessionFor(_day).exercises.single.sets) {
            set.completed = true;
          }
        },
      );
      final previous = state.sessionFor(_day).exercises.single;
      await _tap(tester, find.byKey(_recommendationButton));
      expect(find.textContaining('사용 장비가 맨몸으로만'), findsOneWidget);
      await _tap(
        tester,
        find.byKey(const ValueKey('recommendation-recovery-primary')),
      );
      await _tap(tester, find.byKey(const ValueKey('equipment-machines')));
      await _tap(
        tester,
        find.byKey(const ValueKey('recommendation-profile-save')),
      );
      expect(find.text('다음 운동 추천'), findsOneWidget);
      await _tap(tester, find.text('추천 운동 추가'));
      final session = state.sessionFor(_day);
      expect(session.exercises, hasLength(2));
      expect(session.exercises.first, same(previous));
      expect(previous.sets.every((set) => set.completed), isTrue);
      expect(session.exercises.last.template.id, isNot('pushup'));
      expect(session.exercises.last.template.muscle, '가슴');
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets(
    'library retries after dismissing automatic first recommendation and returns to record',
    (tester) async {
      final state = await _pump(tester, daily: true);
      await _tap(tester, find.text('운동 선택'));
      expect(find.text('오늘의 첫 운동 추천'), findsOneWidget);
      await _dismissRecommendation(tester);
      expect(find.byType(ExerciseLibraryScreen), findsOneWidget);
      await _tap(tester, find.byKey(_recommendationButton));
      expect(find.text('오늘의 첫 운동 추천'), findsOneWidget);
      await _tap(tester, find.text('추천 운동 추가'));
      expect(state.sessionFor(_day).exercises, hasLength(1));
      expect(state.autoRecommendNextExercise, isTrue);
      expect(find.byType(ExerciseLibraryScreen), findsNothing);
      expect(find.byType(DailyWorkoutScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets(
    'first library recommendation lets a new session choose its training focus',
    (tester) async {
      final state = await _pump(
        tester,
        onAdded: () {},
        configure: (state) => state.sessionFor(_day).trainingFocus = null,
      );
      await _tap(tester, find.byKey(_recommendationButton));
      expect(find.text('오늘 운동 부위'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('training-focus-chest')));
      await _tap(tester, find.byKey(const ValueKey('training-focus-apply')));
      expect(find.text('오늘의 첫 운동 추천'), findsOneWidget);
      await _tap(tester, find.text('추천 운동 추가'));
      expect(state.sessionFor(_day).trainingFocus, {TrainingMuscle.chest});
      expect(state.sessionFor(_day).exercises.single.template.muscle, '가슴');
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets(
    'library resumes a dismissed automatic next recommendation before adding a new exercise',
    (tester) async {
      final state = await _pump(
        tester,
        daily: true,
        configure: (state) {
          state.autoStartRestTimer = false;
          state.addExercise(
            _day,
            state.exercises.firstWhere((exercise) => exercise.id == 'bench'),
          );
          final sets = state.sessionFor(_day).exercises.single.sets;
          for (final set in sets) {
            set.completed = true;
          }
          sets.last.completed = false;
        },
      );
      final exercise = state.sessionFor(_day).exercises.single;
      final row = find.byKey(
        ValueKey('inline-set-weight-${exercise.sets.last.number}'),
      );
      await tester.ensureVisible(row);
      await tester.drag(row, const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(find.text('다음 운동 추천'), findsOneWidget);
      await _dismissRecommendation(tester, title: '다음 운동 추천');
      expect(state.sessionFor(_day).exercises, hasLength(1));
      await _tap(tester, find.byKey(const Key('daily-add-exercise')));
      await _tap(tester, find.byKey(_recommendationButton));
      expect(find.text('다음 운동 추천'), findsOneWidget);
      await _tap(tester, find.text('추천 운동 추가'));
      expect(state.sessionFor(_day).exercises, hasLength(2));
      expect(exercise.sets.every((set) => set.completed), isTrue);
      expect(find.byType(ExerciseLibraryScreen), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets(
    'library recommends after a pending exercise without opening the precision survey',
    (tester) async {
      final state = await _pump(
        tester,
        onAdded: () {},
        configure: (state) {
          state.addExercise(
            _day,
            state.exercises.firstWhere((exercise) => exercise.id == 'bench'),
          );
          state.precisionRecommendationPrompted = false;
        },
      );
      final existing = state.sessionFor(_day).exercises.single;
      expect(existing.sets.every((set) => !set.completed), isTrue);
      await _tap(tester, find.byKey(_recommendationButton));
      expect(find.text('다음 운동 추천'), findsOneWidget);
      expect(find.text('추천을 더 정확하게'), findsNothing);
      await _tap(tester, find.text('추천 운동 추가'));
      final exercises = state.sessionFor(_day).exercises;
      expect(exercises, hasLength(2));
      expect(exercises.first, same(existing));
      expect(exercises.last.template.id, isNot(existing.template.id));
      expect(existing.sets.every((set) => !set.completed), isTrue);
      expect(state.precisionRecommendationPrompted, isFalse);
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets(
    'embedded library calls onAdded for repeated recommendations and clears manual selection',
    (tester) async {
      var additions = 0;
      final state = await _pump(
        tester,
        onAdded: () => additions++,
        configure: (state) => state.setTrainingFocus(_day, {}),
      );
      await tester.enterText(find.byType(TextFormField), '바벨 벤치 프레스');
      await tester.pumpAndSettle();
      await _tap(tester, find.byTooltip('선택').first);
      expect(find.byTooltip('선택 해제'), findsOneWidget);
      await _tap(tester, find.byKey(_recommendationButton));
      await _tap(tester, find.text('추천 운동 추가'));
      expect(additions, 1);
      expect(find.byType(ExerciseLibraryScreen), findsOneWidget);
      expect(find.byTooltip('선택 해제'), findsNothing);
      expect(find.text('1개 추가'), findsNothing);
      await _tap(tester, find.byKey(_recommendationButton));
      expect(find.text('다음 운동 추천'), findsOneWidget);
      await _tap(tester, find.text('추천 운동 추가'));
      expect(additions, 2);
      final exercises = state.sessionFor(_day).exercises;
      expect(exercises, hasLength(2));
      expect(
        exercises.map((exercise) => exercise.template.id).toSet(),
        hasLength(2),
      );
      expect(find.byType(ExerciseLibraryScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets(
    'cancel and manual choice retain one library with its search and selected exercise',
    (tester) async {
      final state = await _pump(tester);
      final original = tester.state(find.byType(ExerciseLibraryScreen));
      await tester.enterText(find.byType(TextFormField), '바벨 벤치 프레스');
      await tester.pumpAndSettle();
      await _tap(tester, find.byTooltip('선택').first);
      await _tap(tester, find.byKey(_recommendationButton));
      await _dismissRecommendation(tester);
      _expectSingleLibrary(tester, original);
      expect(find.byTooltip('선택 해제'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '바벨 벤치 프레스',
      );
      await _tap(tester, find.byKey(_recommendationButton));
      await _tap(tester, find.text('직접 선택'));
      _expectSingleLibrary(tester, original);
      expect(find.byTooltip('선택 해제'), findsOneWidget);
      expect(find.text('1개 추가'), findsOneWidget);
      expect(state.sessionFor(_day).exercises, isEmpty);
      await _tap(tester, find.byKey(_recommendationButton));
      expect(find.text('오늘의 첫 운동 추천'), findsOneWidget);
      await _dismissRecommendation(tester);
    },
  );

  testWidgets(
    'failed recommendation manual recovery stays in the same library and can retry',
    (tester) async {
      final state = await _pump(
        tester,
        configure: (state) {
          state.setTrainingFocus(_day, {TrainingMuscle.back});
          state.setRecommendationProfile(
            RecommendationProfile(
              experienceLevel: TrainingExperienceLevel.beginner,
              availableEquipment: {TrainingEquipment.bodyweight},
              painRegions: {},
              painLevel: 0,
              restrictedMovements: {},
              injuryNote: '',
              recoveryStatus: TrainingRecoveryStatus.normal,
              recoveryRecordedAt: _day,
              updatedAt: _day,
            ),
          );
        },
      );
      final original = tester.state(find.byType(ExerciseLibraryScreen));
      await _tap(tester, find.byKey(_recommendationButton));
      expect(find.text('추천 조건 확인'), findsOneWidget);
      await _tap(
        tester,
        find.byKey(const ValueKey('recommendation-recovery-manual')),
      );
      _expectSingleLibrary(tester, original);
      expect(state.sessionFor(_day).exercises, isEmpty);
      await _tap(tester, find.byKey(_recommendationButton));
      expect(find.text('추천 조건 확인'), findsOneWidget);
      Navigator.of(
        tester.element(
          find.byKey(const ValueKey('recommendation-stop-reason')),
        ),
      ).pop();
      await tester.pumpAndSettle();
      _expectSingleLibrary(tester, original);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'library recommendation fits a small screen with 2x text ($dark)',
      (tester) async {
        var additions = 0;
        final state = await _pump(
          tester,
          small: true,
          dark: dark,
          onAdded: () => additions++,
        );
        expect(tester.takeException(), isNull);
        await _tap(tester, find.byKey(_recommendationButton));
        expect(find.text('오늘의 첫 운동 추천'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _tap(tester, find.text('추천 운동 추가'));
        expect(additions, 1);
        expect(state.sessionFor(_day).exercises, hasLength(1));
        expect(find.byKey(_recommendationButton), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 4));
      },
    );
  }
}
