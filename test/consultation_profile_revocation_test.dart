import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/member_social_detail_screens.dart';
import 'package:setflow/theme.dart';

void main() {
  testWidgets('member can revoke a consultation survey share', (tester) async {
    await tester.binding.setSurfaceSize(const Size(432, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    addTearDown(state.dispose);
    await state.initialize();
    final recordedAt = DateTime(2026, 8, 21);
    final consultation = ConsultationData(
      id: 'consultation-share',
      trainerName: '김코치',
      specialty: '근력',
      goal: '근력 향상',
      level: '초급',
      question: '운동을 조정해주세요.',
      createdAt: recordedAt,
      status: ConsultationStatus.answered,
      response: '상담 답변입니다.',
      sharedRecommendationProfile: RecommendationProfile(
        experienceLevel: TrainingExperienceLevel.beginner,
        availableEquipment: const {TrainingEquipment.bodyweight},
        painRegions: const {TrainingPainRegion.knee},
        painLevel: 2,
        restrictedMovements: const {TrainingMovementRestriction.squatLunge},
        injuryNote: '',
        recoveryStatus: TrainingRecoveryStatus.normal,
        recoveryRecordedAt: recordedAt,
        updatedAt: recordedAt,
      ),
    );
    state.consultations
      ..clear()
      ..add(consultation);

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: ConsultationDetailScreen(consultation: consultation),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final revoke = find.byKey(const ValueKey('consultation-profile-revoke'));
    await tester.scrollUntilVisible(
      revoke,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(revoke);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('consultation-profile-revoke-confirm')),
    );
    await tester.pumpAndSettle();

    expect(consultation.recommendationProfileShareRevokedAt, isNotNull);
    expect(find.textContaining('공유 철회됨'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('consultation-profile-revoke')),
      findsNothing,
    );
  });
}
