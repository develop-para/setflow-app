import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/supabase_app_repository.dart';
import 'package:setflow/models.dart';

void main() {
  test(
    'normalized account projection stores cardio as time distance and RPE',
    () async {
      final gateway = _CapturingGateway();
      final repository = SupabaseAppRepository.withGateway(gateway);
      await repository.load(const []);

      final date = DateTime(2026, 8, 17);
      final run = ExerciseTemplate(
        id: 'run',
        name: '트레드밀 러닝',
        muscle: '유산소',
        icon: Icons.directions_run,
      );
      final bench = ExerciseTemplate(
        id: 'bench',
        name: '바벨 벤치 프레스',
        muscle: '가슴',
        icon: Icons.fitness_center,
      );
      final snapshot = AppSnapshot(
        role: UserRole.member,
        isDarkMode: false,
        weightUnit: 'kg',
        restDefaultSeconds: 90,
        sessions: {
          date: WorkoutSession(
            date: date,
            exercises: [
              WorkoutExercise(
                id: 'run-entry',
                template: run,
                sets: [
                  WorkoutSetEntry(
                    number: 1,
                    weight: 40,
                    reps: 10,
                    durationSeconds: 1800,
                    distanceKm: 5,
                    intensityRpe: 6.5,
                    completed: true,
                  ),
                ],
              ),
              WorkoutExercise(
                id: 'bench-entry',
                template: bench,
                sets: [
                  WorkoutSetEntry(
                    number: 1,
                    weight: 100,
                    reps: 8,
                    completed: true,
                  ),
                ],
              ),
            ],
          ),
        },
        routines: const [],
      );

      await repository.save(snapshot);

      final exercises = gateway.savedSessions.single['exercises']! as List;
      final cardio = (exercises.first as Map)['sets'] as List;
      final cardioSet = Map<String, Object?>.from(cardio.single as Map);
      expect(cardioSet['weight'], 0);
      expect(cardioSet['reps'], 0);
      expect(cardioSet['duration_sec'], 1800);
      expect(cardioSet['distance_m'], 5000);
      expect(cardioSet['intensity_rpe'], 6.5);

      final resistance = (exercises.last as Map)['sets'] as List;
      final resistanceSet = Map<String, Object?>.from(resistance.single as Map);
      expect(resistanceSet['weight'], 100);
      expect(resistanceSet['reps'], 8);
      expect(resistanceSet['duration_sec'], isNull);
      expect(resistanceSet['distance_m'], isNull);
      expect(resistanceSet['intensity_rpe'], isNull);
    },
  );
}

class _CapturingGateway implements SupabaseAppRemoteGateway {
  @override
  String? currentUserId = 'account-a';

  List<Map<String, Object?>> savedSessions = const [];

  @override
  Future<void> clearSnapshot({
    required String expectedUserId,
    required DateTime? expectedUpdatedAt,
  }) async {}

  @override
  Future<Map<String, dynamic>> requestAccountDeletion(String? reason) async {
    final purgeAfter = DateTime.utc(2026, 9, 25);
    deletionRequests[currentUserId ?? ''] = {
      'requestedAt': DateTime.utc(2026, 8, 26).toIso8601String(),
      'purgeAfter': purgeAfter.toIso8601String(),
      'reason': reason,
    };
    return deletionRequests[currentUserId ?? '']!;
  }

  @override
  Future<bool> cancelAccountDeletion() async =>
      deletionRequests.remove(currentUserId ?? '') != null;

  @override
  Future<Map<String, dynamic>?> pendingAccountDeletion(String userId) async =>
      deletionRequests[userId];

  /// 탈퇴 요청을 사용자별로 담아 두는 자리 — 서버 테이블 대역.
  final Map<String, Map<String, dynamic>> deletionRequests = {};

  @override
  Future<void> registerPushToken(String token, String platform) async {
    pushTokens[token] = platform;
  }

  @override
  Future<void> unregisterPushToken(String token) async {
    pushTokens.remove(token);
  }

  /// 기기 토큰 대역 — 서버 device_tokens 자리.
  final Map<String, String> pushTokens = {};

  @override
  Future<DateTime?> latestWorkoutUpdatedAt(String userId) async => null;

  @override
  Future<SupabaseAppSnapshotRow?> loadSnapshot(String userId) async => null;

  @override
  Future<DateTime> saveSnapshot({
    required String expectedUserId,
    required int schemaVersion,
    required Map<String, dynamic> payload,
    required List<Map<String, Object?>> sessions,
    required DateTime? expectedUpdatedAt,
  }) async {
    savedSessions = sessions;
    return DateTime.utc(2026, 8, 17);
  }
}
