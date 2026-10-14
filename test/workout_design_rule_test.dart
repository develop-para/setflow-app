import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/data/evidence_catalog.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/domain/cardio.dart';
import 'package:setflow/domain/workout_design_rule.dart';
import 'package:setflow/models.dart';
import 'package:setflow/services/cardio_prescription_engine.dart';
import 'package:setflow/services/exercise_recommendation_engine.dart';
import 'package:setflow/services/performance_engine.dart';
import 'package:setflow/services/personal_coaching_engine.dart';
import 'package:setflow/services/resistance_prescription_engine.dart';

void main() {
  test(
    'every workout rule explains its implementation, reason, limits and review date',
    () {
      final reviewDate = DateTime.tryParse(WorkoutDesignRule.reviewedOn);
      expect(reviewDate, isNotNull);
      expect(
        reviewDate!.toIso8601String().split('T').first,
        WorkoutDesignRule.reviewedOn,
      );
      expect(
        WorkoutDesignRule.values.map((rule) => rule.title).toSet(),
        hasLength(WorkoutDesignRule.values.length),
      );
      for (final rule in WorkoutDesignRule.values) {
        expect(rule.title.trim(), isNotEmpty, reason: rule.name);
        expect(rule.implementation.trim(), isNotEmpty, reason: rule.name);
        expect(rule.rationale.trim(), isNotEmpty, reason: rule.name);
        expect(rule.limitations.trim(), isNotEmpty, reason: rule.name);
        if (rule.basis == WorkoutRuleBasis.researchAndAppRule) {
          expect(rule.principle.trim(), isNotEmpty, reason: rule.name);
          expect(rule.evidenceIds, isNotEmpty, reason: rule.name);
          for (final id in rule.evidenceIds) {
            final reference = evidenceCatalogById[id];
            expect(reference, isNotNull, reason: '${rule.name}: $id');
            expect(reference!.officialUrl.scheme, 'https');
            expect(reference.officialUrl.host, isNotEmpty);
            expect(reference.doi, isNotEmpty);
            expect(reference.appRules, isNotEmpty);
            expect(reference.limitations, isNotEmpty);
          }
        } else {
          expect(
            rule.principle,
            isEmpty,
            reason: '${rule.name}은 연구 주장으로 표시하지 않습니다.',
          );
          expect(
            rule.evidenceIds,
            isEmpty,
            reason: '${rule.name}은 제품·기록 원칙입니다.',
          );
        }
      }
    },
  );

  test(
    'recording and input rules identify product reasons without claiming exercise efficacy',
    () {
      expect(
        WorkoutDesignRule.observedValues.basis,
        WorkoutRuleBasis.recordIntegrity,
      );
      expect(
        WorkoutDesignRule.observedValues.rationale,
        contains('실제 기록처럼 만들지 않기'),
      );
      expect(
        WorkoutDesignRule.pendingSetPropagation.basis,
        WorkoutRuleBasis.userControl,
      );
      expect(
        WorkoutDesignRule.pendingSetPropagation.rationale,
        contains('반복 입력'),
      );
      expect(
        WorkoutDesignRule.timeEstimate.basis,
        WorkoutRuleBasis.planningEstimate,
      );
      expect(
        WorkoutDesignRule.timeEstimate.limitations,
        contains('실제 소요시간을 측정한 값이 아닙니다'),
      );
      expect(
        WorkoutDesignRule.inputBounds.limitations,
        contains('상한을 뜻하지 않습니다'),
      );
    },
  );

  test(
    'hypertrophy and autoregulation papers stay within their recommendation scope',
    () {
      final date = DateTime(2026, 10, 14);
      final bench = exerciseCatalog.firstWhere((item) => item.id == 'bench');
      const hypertrophySources = {
        'singer_2024_rest_hypertrophy',
        'robinson_2024_proximity_failure',
      };
      for (final goal in TrainingGoal.values) {
        final base = PerformanceEngine.prescriptionFor(goal);
        expect(
          base.evidenceIds.intersection(hypertrophySources),
          goal == TrainingGoal.hypertrophy ? hypertrophySources : isEmpty,
          reason: '${goal.name}: 근비대 연구를 다른 목표의 직접 근거로 쓰지 않는다',
        );
        for (final coached in [false, true]) {
          final result = ResistancePrescriptionEngine.prescribe(
            template: bench,
            goal: goal,
            history: const [],
            session: WorkoutSession(date: date, exercises: []),
            coachingPlan: coached
                ? PersonalCoachingEngine.build(
                    date: date,
                    history: const [],
                    goal: goal,
                  )
                : null,
          );
          expect(
            result.evidenceIds.intersection(hypertrophySources),
            goal == TrainingGoal.hypertrophy ? hypertrophySources : isEmpty,
          );
          expect(result.evidenceIds, contains('halperin_2022_rir_accuracy'));
          expect(result.evidenceNote, contains('주관적 추정'));
          expect(result.evidenceNote, contains('정확한 실측값이 아닙니다'));
          expect(
            result.evidenceIds.contains('hickmott_2022_autoregulation'),
            coached,
          );
          expect(
            result.evidenceNote.contains('고정된 부하 계획보다 우월하다고 확정하지 않습니다'),
            coached,
          );
          expect(
            result.evidenceIds,
            isNot(contains('cox_2026_mhealth_resistance')),
            reason: '모바일 중재 연구를 개인 세트·중량의 직접 처방 근거로 붙이지 않는다',
          );
        }
      }
      expect(
        WorkoutDesignRule.digitalGuidance.evidenceIds,
        contains('cox_2026_mhealth_resistance'),
      );
      expect(
        WorkoutDesignRule.digitalGuidance.limitations,
        contains('이 앱의 효과를 검증한 연구가 아닙니다'),
      );
    },
  );

  test(
    'all goal, recovery, additional-volume and cardio source branches link to design explanations',
    () {
      final date = DateTime(2026, 10, 14);
      final bench = exerciseCatalog.firstWhere(
        (exercise) => exercise.id == 'bench',
      );
      final linkedIds = {
        for (final rule in WorkoutDesignRule.values) ...rule.evidenceIds,
      };

      void verifySources(Set<String> ids, String branch) {
        expect(ids, isNotEmpty, reason: branch);
        expect(
          ids.difference(evidenceCatalogById.keys.toSet()),
          isEmpty,
          reason: branch,
        );
        expect(
          ids.difference(linkedIds),
          isEmpty,
          reason: '$branch의 출처와 연결된 설계 이유가 필요합니다.',
        );
      }

      for (final goal in TrainingGoal.values) {
        verifySources(
          PerformanceEngine.prescriptionFor(goal).evidenceIds,
          '기본 ${goal.name}',
        );
        for (final recovery in [
          TrainingRecoveryStatus.normal,
          TrainingRecoveryStatus.fatigued,
        ]) {
          final profile = RecommendationProfile(
            experienceLevel: TrainingExperienceLevel.advanced,
            availableEquipment: TrainingEquipment.values,
            painRegions: const [],
            painLevel: 0,
            restrictedMovements: const [],
            injuryNote: '',
            recoveryStatus: recovery,
            recoveryRecordedAt: date,
            updatedAt: date,
          );
          final coachingPlan = PersonalCoachingEngine.build(
            date: date,
            history: const [],
            goal: goal,
            profile: profile,
          );
          for (final additional in [false, true]) {
            final session = WorkoutSession(date: date, exercises: []);
            final resistance = ResistancePrescriptionEngine.prescribe(
              template: bench,
              goal: goal,
              history: const [],
              session: session,
              profile: profile,
              coachingPlan: coachingPlan,
              allowAdditionalVolume: additional,
            );
            verifySources(
              resistance.evidenceIds,
              '저항 ${goal.name}/${recovery.name}/$additional',
            );
            final first = ExerciseRecommendationEngine.recommendFirst(
              catalog: [bench],
              session: session,
              goals: [goal.label],
              recommendationProfile: profile,
              coachingPlan: coachingPlan,
              allowAdditionalVolume: additional,
            );
            expect(first, isNotNull);
            verifySources(
              first!.evidenceIds,
              '종목 ${goal.name}/${recovery.name}/$additional',
            );
          }
        }
        for (final exerciseId in cardioExerciseDefinitions.keys) {
          final cardio = CardioPrescriptionEngine.recommend(
            exerciseId: exerciseId,
            goal: goal,
            history: const [],
            now: date,
          )!;
          verifySources(cardio.evidenceIds, '유산소 ${goal.name}/$exerciseId');
        }
      }
      final intervals = CardioPrescriptionEngine.recommend(
        exerciseId: 'run',
        goal: TrainingGoal.endurance,
        history: [
          for (var day = 1; day <= 6; day++)
            CardioSessionRecord(
              id: 'day-$day',
              exerciseId: 'run',
              occurredAt: date.subtract(Duration(days: day)),
              duration: const Duration(minutes: 30),
              intensity: CardioIntensity.moderate,
            ),
        ],
        now: date,
        experience: CardioExperience.advanced,
        vigorousExerciseEligible: true,
      )!;
      expect(intervals.structure, CardioSessionStructure.intervals);
      verifySources(intervals.evidenceIds, '고강도 인터벌');
    },
  );
}
