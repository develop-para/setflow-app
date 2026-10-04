import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/custom_exercise_recommendation_screen.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

final _day = DateTime(2026, 10, 4);
const _name = '나의 스미스 프레스';
Future<AppState> _pump(
  WidgetTester tester, {
  bool small = false,
  bool dark = false,
  bool library = false,
  bool empty = false,
  bool configured = false,
  bool cardio = false,
}) async {
  await tester.binding.setSurfaceSize(
    small ? const Size(320, 700) : const Size(432, 1100),
  );
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = AppState();
  await state.initialize();
  addTearDown(state.dispose);
  if (!empty) {
    final exercise = state.createCustomExercise(
      name: _name,
      muscle: cardio ? '유산소' : '가슴',
    )!;
    if (configured) {
      state.saveCustomExerciseRecommendation(
        exercise.id,
        CustomExerciseRecommendation(
          enabled: true,
          primaryMuscle: cardio ? null : TrainingMuscle.chest,
          movement: cardio ? null : CustomExerciseMovement.horizontalPress,
          requiredEquipment: {
            cardio
                ? TrainingEquipment.rowingMachine
                : TrainingEquipment.smithMachine,
          },
          minimumExperience: TrainingExperienceLevel.beginner,
          cardioDefinitionId: cardio ? 'rowing_machine' : null,
        ),
      );
    }
  }
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(
        theme: dark ? SetflowTheme.dark : SetflowTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(small ? 2 : 1),
            padding: const EdgeInsets.only(top: 24, bottom: 28),
          ),
          child: child!,
        ),
        home: library
            ? ExerciseLibraryScreen(date: _day)
            : const CustomExerciseRecommendationsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 300));
  return state;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, String key, String label) async {
  await _tap(tester, find.byKey(ValueKey(key)));
  await _tap(tester, find.text(label).last);
}

Future<void> _enableAndFill(WidgetTester tester) async {
  await _tap(
    tester,
    find.byKey(const ValueKey('custom-recommendation-enabled')),
  );
  await _select(tester, 'custom-recommendation-primary', '가슴');
  await _select(
    tester,
    'custom-recommendation-movement-chest',
    CustomExerciseMovement.horizontalPress.label,
  );
  await _tap(
    tester,
    find.byKey(const ValueKey('custom-recommendation-equipment-smithMachine')),
  );
  await _select(
    tester,
    'custom-recommendation-experience',
    TrainingExperienceLevel.beginner.label,
  );
}

void main() {
  testWidgets(
    'configured custom rowing keeps distance dial and rowing pace when opt out',
    (tester) async {
      final state = await _pump(tester, configured: true, cardio: true);
      state.sessions.clear();
      final template = state.customExercises.single;
      state.saveCustomExerciseRecommendation(
        template.id,
        template.customRecommendation!.withEnabled(false),
      );
      state.addExercise(_day, state.customExercises.single);
      final set = state.sessionFor(_day).exercises.single.sets.single;
      state.updateSet(set, durationSeconds: 1200, distanceKm: 2);
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: MaterialApp(
            theme: SetflowTheme.light,
            home: DailyWorkoutScreen(date: _day),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cardio-distance-1')), findsOneWidget);
      expect(find.textContaining('/500m'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('cardio-distance-1')));
      expect(find.text('운동 거리 선택'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('number-dial-direct-input')),
        '3',
      );
      await _tap(tester, find.text('적용'));
      expect(set.distanceKm, 3);
      expect(set.durationSeconds, 1200);
    },
  );
  testWidgets(
    'basic create sheet stays simple and created exercise exposes optional editor',
    (tester) async {
      final state = await _pump(tester, library: true, empty: true);
      await _tap(tester, find.byTooltip('새 운동 만들기'));
      expect(find.text('주로 쓰는 부위'), findsNothing);
      expect(find.text('자동 추천에 포함'), findsNothing);
      expect(find.text('필요한 운동 경험'), findsNothing);
      await tester.enterText(
        find.byKey(const Key('custom-exercise-name')),
        _name,
      );
      await _tap(tester, find.text('운동 만들기'));
      expect(state.customExercises.single.customRecommendation, isNull);
      expect(find.byType(CustomExerciseRecommendationScreen), findsNothing);
      final id = state.customExercises.single.id;
      await tester.enterText(find.byType(TextField).first, _name);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await _tap(
        tester,
        find.byKey(ValueKey('custom-recommendation-edit-$id')),
      );
      expect(find.text('추천 정보 설정'), findsOneWidget);
      expect(find.text('동작 유형'), findsNothing);
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('custom-recommendation-enabled')),
            )
            .value,
        isFalse,
      );
    },
  );

  testWidgets('library toolbar opens list of owned custom exercises', (
    tester,
  ) async {
    final state = await _pump(tester, library: true);
    await _tap(tester, find.byTooltip('내 운동 추천 정보'));
    expect(find.text('내 운동 추천 정보'), findsOneWidget);
    expect(find.text(_name), findsOneWidget);
    await _tap(tester, find.text(_name));
    await _enableAndFill(tester);
    await _tap(
      tester,
      find.byKey(const ValueKey('custom-recommendation-save')),
    );
    expect(find.text('자동 추천 참여 중'), findsOneWidget);
    final info = state.customExercises.single.customRecommendation!;
    expect(info.enabled, isTrue);
    expect(info.primaryMuscle, TrainingMuscle.chest);
    expect(info.movement, CustomExerciseMovement.horizontalPress);
    expect(info.requiredEquipment, {TrainingEquipment.smithMachine});
    expect(info.minimumExperience, TrainingExperienceLevel.beginner);
  });

  testWidgets(
    'saving incomplete opt in validates all fields and keeps exercise manual',
    (tester) async {
      final state = await _pump(tester);
      await _tap(tester, find.text(_name));
      await _tap(
        tester,
        find.byKey(const ValueKey('custom-recommendation-enabled')),
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('custom-recommendation-save')),
      );
      expect(state.customExercises.single.customRecommendation, isNull);
      expect(find.byType(CustomExerciseRecommendationScreen), findsOneWidget);
      expect(find.text('주로 쓰는 부위를 선택해주세요.'), findsOneWidget);
      expect(find.text('동작 유형을 선택해주세요.'), findsOneWidget);
      expect(find.text('필요한 운동 경험을 선택해주세요.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('canceling a filled editor commits no metadata', (tester) async {
    final state = await _pump(tester);
    await _tap(tester, find.text(_name));
    await _enableAndFill(tester);
    Navigator.of(
      tester.element(find.byType(CustomExerciseRecommendationScreen)),
    ).pop();
    await tester.pumpAndSettle();
    expect(state.customExercises.single.customRecommendation, isNull);
    expect(find.text('직접 추가해서 사용하는 운동'), findsOneWidget);
  });

  testWidgets('opt out preserves authored metadata and reopen can reenable', (
    tester,
  ) async {
    final state = await _pump(tester, configured: true);
    await _tap(tester, find.text(_name));
    await _tap(
      tester,
      find.byKey(const ValueKey('custom-recommendation-enabled')),
    );
    await _tap(
      tester,
      find.byKey(const ValueKey('custom-recommendation-save')),
    );
    expect(state.customExercises.single.customRecommendation!.enabled, isFalse);
    expect(
      state.customExercises.single.customRecommendation!.requiredEquipment,
      {TrainingEquipment.smithMachine},
    );
    await _tap(tester, find.text(_name));
    await _tap(
      tester,
      find.byKey(const ValueKey('custom-recommendation-enabled')),
    );
    expect(
      find.text(CustomExerciseMovement.horizontalPress.label),
      findsOneWidget,
    );
    await _tap(
      tester,
      find.byKey(const ValueKey('custom-recommendation-save')),
    );
    expect(state.customExercises.single.customRecommendation!.enabled, isTrue);
  });

  testWidgets(
    'custom cardio config selects known modality without resistance fields',
    (tester) async {
      final state = await _pump(tester, cardio: true);
      await _tap(tester, find.text(_name));
      await _tap(
        tester,
        find.byKey(const ValueKey('custom-recommendation-enabled')),
      );
      expect(find.text('주로 쓰는 부위'), findsNothing);
      expect(find.text('동작 유형'), findsNothing);
      await _select(tester, 'custom-recommendation-cardio', '로잉 머신');
      await _tap(
        tester,
        find.byKey(
          const ValueKey('custom-recommendation-equipment-rowingMachine'),
        ),
      );
      await _select(
        tester,
        'custom-recommendation-experience',
        TrainingExperienceLevel.beginner.label,
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('custom-recommendation-save')),
      );
      expect(
        state.customExercises.single.customRecommendation!.cardioDefinitionId,
        'rowing_machine',
      );
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'library keeps custom row settings accessible with a selection at double text dark=$dark',
      (tester) async {
        final state = await _pump(
          tester,
          library: true,
          small: true,
          dark: dark,
        );
        await tester.enterText(find.byType(TextField).first, _name);
        await tester.pumpAndSettle();
        await _tap(tester, find.widgetWithText(ListTile, _name));
        await tester.drag(find.byType(ListView).last, const Offset(0, -180));
        await tester.pumpAndSettle();
        final id = state.customExercises.single.id;
        await _tap(
          tester,
          find.byKey(ValueKey('custom-recommendation-edit-$id')),
        );
        expect(find.text('추천 정보 설정'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'editor works at 320px with double text and safe area dark=$dark',
      (tester) async {
        final state = await _pump(tester, small: true, dark: dark);
        await _tap(tester, find.text(_name));
        await _enableAndFill(tester);
        await tester.ensureVisible(
          find.byKey(const ValueKey('custom-recommendation-save')),
        );
        await tester.pumpAndSettle();
        final button = tester.getRect(
          find.byKey(const ValueKey('custom-recommendation-save')),
        );
        expect(button.bottom, lessThanOrEqualTo(672));
        await _tap(
          tester,
          find.byKey(const ValueKey('custom-recommendation-save')),
        );
        expect(
          state.customExercises.single.customRecommendation!.enabled,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets('empty custom list supports double text dark=$dark', (
      tester,
    ) async {
      await _pump(tester, small: true, dark: dark, empty: true);
      expect(find.text('만든 운동이 없어요'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
