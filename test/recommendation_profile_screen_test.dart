import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/recommendation_profile_screen.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

void main() {
  Future<void> pumpProfileEditor(WidgetTester tester, AppState state) async {
    await tester.binding.setSurfaceSize(const Size(432, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const RecommendationProfileScreen(),
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

    await tester.tap(find.text('운동 추가'));
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseLibraryScreen), findsOneWidget);
    expect(find.textContaining('자동 추천을 중단했어요'), findsOneWidget);
  });
}

RecommendationProfile _profile({
  required DateTime recordedAt,
  TrainingRecoveryStatus recovery = TrainingRecoveryStatus.normal,
}) {
  return RecommendationProfile(
    experienceLevel: TrainingExperienceLevel.beginner,
    availableEquipment: const {TrainingEquipment.bodyweight},
    painRegions: const {},
    painLevel: 0,
    restrictedMovements: const {},
    injuryNote: '',
    recoveryStatus: recovery,
    recoveryRecordedAt: recordedAt,
    updatedAt: recordedAt,
  );
}
