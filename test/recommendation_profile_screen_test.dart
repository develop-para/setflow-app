import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/recommendation_profile_screen.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

void main() {
  Future<void> pumpProfileEditor(
    WidgetTester tester,
    AppState state, {
    bool focusEquipment = false,
    Size surfaceSize = const Size(432, 1000),
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => RecommendationProfileScreen(
                        focusEquipment: focusEquipment,
                      ),
                    ),
                  ),
                  child: const Text('설문 열기'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('설문 열기'));
    await tester.pumpAndSettle();
  }

  testWidgets('new survey requires an explicit equipment choice', (
    tester,
  ) async {
    final state = AppState();
    addTearDown(state.dispose);
    await state.initialize();
    await pumpProfileEditor(tester, state, surfaceSize: const Size(360, 640));

    for (final equipment in TrainingEquipment.values) {
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(ValueKey('equipment-${equipment.name}')),
            )
            .selected,
        isFalse,
      );
    }
    await tester.ensureVisible(find.byKey(const ValueKey('injury-note')));
    await tester.tap(find.byKey(const ValueKey('recommendation-profile-save')));
    await tester.pumpAndSettle();

    expect(state.recommendationProfile, isNull);
    expect(find.byType(RecommendationProfileScreen), findsOneWidget);
    expect(
      find
          .byKey(const ValueKey('recommendation-equipment-error'))
          .hitTestable(),
      findsOneWidget,
    );
    expect(find.text('2. 사용할 수 있는 장비').hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('equipment-bodyweight')).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('an explicitly selected bodyweight profile can be saved', (
    tester,
  ) async {
    final state = AppState();
    addTearDown(state.dispose);
    await state.initialize();
    await pumpProfileEditor(tester, state, focusEquipment: true);

    await tester.tap(find.byKey(const ValueKey('equipment-bodyweight')));
    await tester.tap(find.byKey(const ValueKey('recommendation-profile-save')));
    await tester.pumpAndSettle();

    expect(state.recommendationProfile!.availableEquipment, {
      TrainingEquipment.bodyweight,
    });
    expect(find.byType(RecommendationProfileScreen), findsNothing);
  });

  testWidgets(
    'equipment entry opens at the section on a small large-text screen',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.initialize();
      await pumpProfileEditor(
        tester,
        state,
        focusEquipment: true,
        surfaceSize: const Size(360, 640),
        textScale: 2,
      );

      expect(find.text('2. 사용할 수 있는 장비').hitTestable(), findsOneWidget);
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scrollable.position.pixels, greaterThan(0));
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();
      final afterScroll = scrollable.position.pixels;
      state.setMemberProfile(goals: const ['건강 유지']);
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, afterScroll);
      await state.flushPersistence();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editing preserves saved equipment and movement restrictions', (
    tester,
  ) async {
    final state = AppState();
    addTearDown(state.dispose);
    await state.initialize();
    const equipment = {TrainingEquipment.dumbbells, TrainingEquipment.bench};
    const restrictions = {
      TrainingMovementRestriction.horizontalPress,
      TrainingMovementRestriction.verticalPull,
    };
    state.setRecommendationProfile(
      _profile(
        recordedAt: DateTime.now(),
        equipment: equipment,
        restrictions: restrictions,
        experience: TrainingExperienceLevel.intermediate,
      ),
    );
    await pumpProfileEditor(tester, state, focusEquipment: true);

    for (final option in TrainingEquipment.values) {
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(ValueKey('equipment-${option.name}')),
            )
            .selected,
        equipment.contains(option),
      );
    }
    for (final movement in restrictions) {
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(ValueKey('restriction-${movement.name}')),
            )
            .selected,
        isTrue,
      );
    }
    await tester.tap(find.byKey(const ValueKey('recommendation-profile-save')));
    await tester.pumpAndSettle();

    expect(state.recommendationProfile!.availableEquipment, equipment);
    expect(state.recommendationProfile!.restrictedMovements, restrictions);
    expect(
      state.recommendationProfile!.experienceLevel,
      TrainingExperienceLevel.intermediate,
    );
  });

  testWidgets('editing equipment does not refresh stale recovery answers', (
    tester,
  ) async {
    final state = AppState();
    addTearDown(state.dispose);
    await state.initialize();
    final yesterday = DateTime.now().toUtc().subtract(const Duration(days: 1));
    state.setRecommendationProfile(
      _profile(
        recordedAt: yesterday,
        recovery: TrainingRecoveryStatus.fatigued,
      ),
    );
    await pumpProfileEditor(tester, state);

    final dumbbells = find.byKey(const ValueKey('equipment-dumbbells'));
    await tester.ensureVisible(dumbbells);
    await tester.tap(dumbbells);
    final staleRecoveryCopy = find.textContaining('오늘 상태를 다시 선택하지 않으면');
    await tester.scrollUntilVisible(
      staleRecoveryCopy,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(staleRecoveryCopy, findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('recommendation-profile-save')),
    );
    await tester.tap(find.byKey(const ValueKey('recommendation-profile-save')));
    await tester.pumpAndSettle();

    expect(
      state.recommendationProfile!.recoveryRecordedAt.isAtSameMomentAs(
        yesterday,
      ),
      isTrue,
    );
    expect(
      state.recommendationProfile!.recoveryStatus,
      TrainingRecoveryStatus.fatigued,
    );
    expect(
      state.recommendationProfile!.availableEquipment,
      contains(TrainingEquipment.dumbbells),
    );
  });

  testWidgets('member can delete the account-scoped survey', (tester) async {
    final state = AppState();
    addTearDown(state.dispose);
    await state.initialize();
    state.setRecommendationProfile(_profile(recordedAt: DateTime.now()));
    await pumpProfileEditor(tester, state);

    await tester.tap(
      find.byKey(const ValueKey('recommendation-profile-delete')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('recommendation-profile-delete-confirm')),
    );
    await tester.pumpAndSettle();

    expect(state.recommendationProfile, isNull);
    expect(state.precisionRecommendationPrompted, isTrue);
  });

  testWidgets('severe pain pauses auto recommendation but keeps manual add', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(432, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    addTearDown(state.dispose);
    await state.initialize();
    state.sessions.clear();
    state.setMemberProfile(goals: const ['건강 유지']);
    state.setRecommendationProfile(
      RecommendationProfile(
        experienceLevel: TrainingExperienceLevel.beginner,
        availableEquipment: const {TrainingEquipment.bodyweight},
        painRegions: const {TrainingPainRegion.knee},
        painLevel: 7,
        restrictedMovements: const {},
        injuryNote: '',
        recoveryStatus: TrainingRecoveryStatus.normal,
        recoveryRecordedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    final date = state.dateOnly(DateTime.now());
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

    await tester.tap(find.text('운동 선택'));
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseLibraryScreen), findsOneWidget);
    expect(find.textContaining('자동 추천을 중단했어요'), findsOneWidget);
  });
}

RecommendationProfile _profile({
  required DateTime recordedAt,
  TrainingRecoveryStatus recovery = TrainingRecoveryStatus.normal,
  Set<TrainingEquipment> equipment = const {TrainingEquipment.bodyweight},
  Set<TrainingMovementRestriction> restrictions = const {},
  TrainingExperienceLevel experience = TrainingExperienceLevel.beginner,
}) {
  return RecommendationProfile(
    experienceLevel: experience,
    availableEquipment: equipment,
    painRegions: const {},
    painLevel: 0,
    restrictedMovements: restrictions,
    injuryNote: '',
    recoveryStatus: recovery,
    recoveryRecordedAt: recordedAt,
    updatedAt: recordedAt,
  );
}
