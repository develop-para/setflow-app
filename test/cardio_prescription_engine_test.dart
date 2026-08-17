import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/data/evidence_catalog.dart';
import 'package:setflow/domain/cardio.dart';
import 'package:setflow/models.dart';
import 'package:setflow/services/cardio_prescription_engine.dart';
import 'package:setflow/services/performance_engine.dart';

void main() {
  CardioSessionRecord record({
    required String id,
    required String exerciseId,
    required DateTime occurredAt,
    int minutes = 30,
    CardioIntensity intensity = CardioIntensity.moderate,
    double? distanceKm,
    double? perceivedExertion,
  }) => CardioSessionRecord(
    id: id,
    exerciseId: exerciseId,
    occurredAt: occurredAt,
    duration: Duration(minutes: minutes),
    intensity: intensity,
    distanceKm: distanceKm,
    perceivedExertion: perceivedExertion,
  );

  group('cardio recording contract', () {
    test(
      'catalog cardio ids expose modality-specific metrics without weight',
      () {
        expect(
          cardioExerciseDefinitions.keys,
          containsAll(<String>[
            'run',
            'stationary_bike',
            'stair_climber',
            'rowing_machine',
            'elliptical',
            'brisk_walk',
            'jump_rope',
          ]),
        );

        final run = cardioDefinitionForExercise('run')!;
        expect(
          run.primaryMetrics,
          containsAll(<CardioMetric>[
            CardioMetric.duration,
            CardioMetric.distance,
            CardioMetric.pace,
          ]),
        );
        final bike = cardioDefinitionForExercise('stationary_bike')!;
        expect(
          bike.metrics,
          containsAll(<CardioMetric>[
            CardioMetric.duration,
            CardioMetric.resistance,
            CardioMetric.power,
            CardioMetric.cadence,
          ]),
        );
        final row = cardioDefinitionForExercise('rowing_machine')!;
        expect(
          row.metrics,
          containsAll(<CardioMetric>[
            CardioMetric.distance,
            CardioMetric.strokeRate,
            CardioMetric.power,
          ]),
        );
      },
    );

    test('derives running and rowing pace from time and distance', () {
      final run = record(
        id: 'run-1',
        exerciseId: 'run',
        occurredAt: DateTime(2026, 8, 17),
        minutes: 30,
        distanceKm: 5,
      );

      expect(run.derivedAverageSpeedKph, 10);
      expect(run.paceSecondsPerKm, 360);
      expect(run.rowingPaceSecondsPer500m, 180);
      expect(run.validate(), isEmpty);
    });

    test('validates duration, heart rate, RPE and impossible values', () {
      final invalid = CardioSessionRecord(
        id: '',
        exerciseId: 'bench',
        occurredAt: DateTime(2026, 8, 17),
        duration: Duration.zero,
        intensity: CardioIntensity.moderate,
        distanceKm: -1,
        averageHeartRateBpm: 220,
        maxHeartRateBpm: 200,
        perceivedExertion: 11,
      );

      expect(
        invalid.validate(),
        containsAll(<String>[
          'id',
          'exerciseId',
          'duration',
          'distanceKm',
          'heartRateOrder',
          'perceivedExertion',
        ]),
      );
    });
  });

  group('evidence-based cardio prescription', () {
    test('every source id resolves to the settings evidence catalog', () {
      final catalogIds = evidenceCatalog
          .map((reference) => reference.id)
          .toSet();
      expect(
        <String>{
          CardioEvidenceIds.whoPhysicalActivity2020,
          CardioEvidenceIds.acsmExercisePrescription2011,
          CardioEvidenceIds.acsmAdiposity2024,
          CardioEvidenceIds.aerobicIntervals2007,
          CardioEvidenceIds.concurrentTraining2022,
        }.difference(catalogIds),
        isEmpty,
      );
    });

    test('uses a 30-minute moderate default and weekly WHO target', () {
      final prescription = CardioPrescriptionEngine.recommend(
        exerciseId: 'brisk_walk',
        goal: TrainingGoal.health,
        history: const [],
        now: DateTime(2026, 8, 17),
      )!;

      expect(prescription.structure, CardioSessionStructure.continuous);
      expect(prescription.sessionDuration, const Duration(minutes: 30));
      expect(prescription.intensity, CardioIntensity.moderate);
      expect((prescription.minimumRpe, prescription.maximumRpe), (3, 4));
      expect(prescription.weeklyTargetModerateEquivalentMinutes, 150);
      expect(prescription.durationSeconds, 1800);
      expect(prescription.targetRpeMin, 3);
      expect(prescription.intensityLabel, '중강도');
      expect(prescription.supportsDistance, isTrue);
      expect(prescription.sourceIds, prescription.evidenceIds);
      expect(
        prescription.evidenceIds,
        containsAll(<String>{
          CardioEvidenceIds.whoPhysicalActivity2020,
          CardioEvidenceIds.acsmExercisePrescription2011,
        }),
      );
    });

    test('counts vigorous time as double and ignores prior weeks', () {
      final history = <CardioSessionRecord>[
        record(
          id: 'monday',
          exerciseId: 'run',
          occurredAt: DateTime(2026, 8, 17),
          minutes: 30,
        ),
        record(
          id: 'tuesday',
          exerciseId: 'run',
          occurredAt: DateTime(2026, 8, 18),
          minutes: 20,
          intensity: CardioIntensity.vigorous,
        ),
        record(
          id: 'prior-week',
          exerciseId: 'run',
          occurredAt: DateTime(2026, 8, 16),
          minutes: 60,
        ),
        record(
          id: 'future',
          exerciseId: 'run',
          occurredAt: DateTime(2026, 8, 21),
          minutes: 60,
        ),
        record(
          id: 'light-rpe',
          exerciseId: 'brisk_walk',
          occurredAt: DateTime(2026, 8, 18),
          minutes: 60,
          perceivedExertion: 2,
        ),
      ];

      expect(
        CardioPrescriptionEngine.weeklyModerateEquivalentMinutes(
          history,
          now: DateTime(2026, 8, 19),
        ),
        70,
      );
    });

    test('computes HRR only from supplied max and resting heart rates', () {
      final withHeartRate = CardioPrescriptionEngine.recommend(
        exerciseId: 'stationary_bike',
        goal: TrainingGoal.health,
        history: const [],
        measuredMaxHeartRateBpm: 190,
        restingHeartRateBpm: 60,
      )!;
      final withoutResting = CardioPrescriptionEngine.recommend(
        exerciseId: 'stationary_bike',
        goal: TrainingGoal.health,
        history: const [],
        measuredMaxHeartRateBpm: 190,
      )!;

      expect(withHeartRate.targetHeartRate!.method, 'HRR');
      expect(withHeartRate.targetHeartRate!.minimumBpm, 112);
      expect(withHeartRate.targetHeartRate!.maximumBpm, 137);
      expect(withoutResting.targetHeartRate, isNull);
    });

    test(
      'translates recent median speed into distance without increasing pace',
      () {
        final history = <CardioSessionRecord>[
          record(
            id: 'old-outlier',
            exerciseId: 'run',
            occurredAt: DateTime(2026, 7, 1),
            minutes: 30,
            distanceKm: 20,
          ),
          record(
            id: 'recent-slow',
            exerciseId: 'run',
            occurredAt: DateTime(2026, 8, 8),
            minutes: 30,
            distanceKm: 4,
          ),
          record(
            id: 'one',
            exerciseId: 'run',
            occurredAt: DateTime(2026, 8, 10),
            minutes: 30,
            distanceKm: 5,
          ),
          record(
            id: 'two',
            exerciseId: 'run',
            occurredAt: DateTime(2026, 8, 12),
            minutes: 30,
            distanceKm: 6,
          ),
          record(
            id: 'recent-three',
            exerciseId: 'run',
            occurredAt: DateTime(2026, 8, 13),
            minutes: 30,
            distanceKm: 5,
          ),
          record(
            id: 'recent-four',
            exerciseId: 'run',
            occurredAt: DateTime(2026, 8, 14),
            minutes: 30,
            distanceKm: 5,
          ),
        ];

        final prescription = CardioPrescriptionEngine.recommend(
          exerciseId: 'run',
          goal: TrainingGoal.health,
          history: history,
          now: DateTime(2026, 8, 17),
        )!;

        expect(prescription.targetDistanceKm, 5);
      },
    );

    test('adds fat-loss and concurrent-training evidence by goal', () {
      final fatLoss = CardioPrescriptionEngine.recommend(
        exerciseId: 'elliptical',
        goal: TrainingGoal.fatLoss,
        history: const [],
      )!;
      final hypertrophy = CardioPrescriptionEngine.recommend(
        exerciseId: 'stationary_bike',
        goal: TrainingGoal.hypertrophy,
        history: const [],
      )!;

      expect(fatLoss.sessionDuration, const Duration(minutes: 40));
      expect(
        fatLoss.evidenceIds,
        contains(CardioEvidenceIds.acsmAdiposity2024),
      );
      expect(
        hypertrophy.evidenceIds,
        contains(CardioEvidenceIds.concurrentTraining2022),
      );
    });

    test(
      'gates 4 x 4 intervals behind experience, eligibility and history',
      () {
        final now = DateTime(2026, 8, 17, 18);
        final history = <CardioSessionRecord>[
          for (var day = 1; day <= 6; day++)
            record(
              id: 'base-$day',
              exerciseId: 'run',
              occurredAt: now.subtract(Duration(days: day * 3)),
              minutes: 30,
            ),
        ];
        final defaultPlan = CardioPrescriptionEngine.recommend(
          exerciseId: 'run',
          goal: TrainingGoal.endurance,
          history: history,
          now: now,
          experience: CardioExperience.advanced,
        )!;
        final intervalPlan = CardioPrescriptionEngine.recommend(
          exerciseId: 'run',
          goal: TrainingGoal.endurance,
          history: history,
          now: now,
          experience: CardioExperience.advanced,
          vigorousExerciseEligible: true,
          measuredMaxHeartRateBpm: 190,
        )!;

        expect(defaultPlan.structure, CardioSessionStructure.continuous);
        expect(intervalPlan.structure, CardioSessionStructure.intervals);
        expect(intervalPlan.workBouts, 4);
        expect(intervalPlan.workBoutDuration, const Duration(minutes: 4));
        expect(intervalPlan.recoveryBoutDuration, const Duration(minutes: 3));
        expect(intervalPlan.targetHeartRate!.minimumBpm, 171);
        expect(intervalPlan.targetHeartRate!.maximumBpm, 181);
        expect(
          intervalPlan.evidenceIds,
          contains(CardioEvidenceIds.aerobicIntervals2007),
        );
      },
    );

    test('returns null for resistance exercise ids', () {
      expect(
        CardioPrescriptionEngine.recommend(
          exerciseId: 'bench',
          goal: TrainingGoal.health,
          history: const [],
        ),
        isNull,
      );
    });

    test(
      'resistance e1RM engine refuses cardio even with legacy set values',
      () {
        const treadmill = ExerciseTemplate(
          id: 'run',
          name: '트레드밀 러닝',
          muscle: '유산소',
          icon: Icons.directions_run,
        );
        final legacySession = WorkoutSession(
          date: DateTime(2026, 8, 17),
          exercises: [
            WorkoutExercise(
              id: 'legacy-run',
              template: treadmill,
              sets: [
                WorkoutSetEntry(
                  number: 1,
                  weight: 10,
                  reps: 30,
                  completed: true,
                ),
              ],
            ),
          ],
        );

        expect(
          PerformanceEngine.summarize(
            sessions: [legacySession],
            template: treadmill,
          ),
          isNull,
        );
        expect(
          PerformanceEngine.recommend(
            sessions: [legacySession],
            template: treadmill,
            goal: TrainingGoal.health,
          ),
          isNull,
        );
      },
    );
  });
}
