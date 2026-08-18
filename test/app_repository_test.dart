import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/app_snapshot_codec.dart';

void main() {
  group('AppSnapshotCodec', () {
    test('round-trips preferences, workouts, routines, and social data', () {
      const catalog = [
        ExerciseTemplate(
          id: 'squat',
          name: '스쿼트',
          muscle: '하체',
          icon: Icons.accessibility_new,
        ),
      ];
      final date = DateTime(2026, 7, 23);
      final snapshot = AppSnapshot(
        role: UserRole.member,
        isDarkMode: true,
        weightUnit: 'lb',
        restDefaultSeconds: 120,
        autoRecommendNextExercise: false,
        customExercises: const [
          ExerciseTemplate(
            id: 'custom_press',
            name: '나만의 프레스',
            muscle: '가슴',
            icon: Icons.fitness_center,
          ),
        ],
        goals: const ['근육 증가', '체력 향상'],
        heightCm: 175.5,
        weight: 72.4,
        age: 29,
        gender: 'M',
        sessions: {
          date: WorkoutSession(
            date: date,
            exercises: [
              WorkoutExercise(
                id: 'workout_1',
                template: catalog.first,
                sets: [
                  WorkoutSetEntry(
                    number: 1,
                    weight: 80,
                    reps: 8,
                    completed: true,
                    restSeconds: 150,
                  ),
                ],
              ),
            ],
          ),
        },
        routines: [
          RoutineData(
            id: 'routine_1',
            name: '하체 루틴',
            description: '스쿼트 중심',
            color: const Color(0xFF10CEBD),
            exercises: catalog,
            accessTier: RoutineAccessTier.paid,
            sourceMarketRoutineId: 'market-routine-1',
            sourceCoachingRoutineId: 'coaching-routine-1',
            setPlans: const {
              'squat': [
                RoutineSetPlan(
                  number: 1,
                  weight: 82.5,
                  reps: 6,
                  type: '웜업',
                  restSeconds: 135,
                ),
              ],
            },
          ),
        ],
        communityPosts: [
          CommunityPost(
            id: 'post_1',
            author: '테스터',
            content: '운동 완료',
            metric: '하체 · 3세트',
            createdAt: date,
            visualKey: 'strength',
            color: const Color(0xFFFFB20C),
            likes: 3,
            imageUrl: 'https://example.com/workout.jpg',
            activeOverlays: const ['날짜', '완료 루틴'],
            comments: [
              PostComment(
                id: 'comment_1',
                author: '응원회원',
                content: '좋아요',
                createdAt: date,
              ),
            ],
          ),
        ],
        consultations: [
          ConsultationData(
            id: 'consult_1',
            trainerName: '김코치',
            specialty: '근력 향상',
            goal: '주 3회 운동',
            level: '초급',
            question: '운동 순서가 궁금해요.',
            createdAt: date,
            status: ConsultationStatus.answered,
            response: '큰 근육 운동부터 시작하세요.',
          ),
        ],
        businessDashboards: {
          UserRole.trainer: BusinessDashboardData(
            role: UserRole.trainer,
            facts: {'revenue': '2,480,000원'},
            tasks: [
              BusinessTaskData(
                id: 'task_1',
                title: '피드백 확인',
                subtitle: '4시간 남음',
                action: '확인',
                kind: 'timer',
              ),
            ],
            notifications: [
              BusinessNotificationData(
                id: 'notice_1',
                title: '새 알림',
                subtitle: '방금 전',
                kind: 'consultation',
                createdAt: date,
                isRead: true,
              ),
            ],
            lastSyncedAt: date,
          ),
        },
      );

      final encoded = AppSnapshotCodec.encode(snapshot);
      final decoded = AppSnapshotCodec.decode(encoded, catalog)!;

      expect(decoded.role, UserRole.member);
      expect(decoded.isDarkMode, isTrue);
      expect(decoded.weightUnit, 'lb');
      expect(decoded.restDefaultSeconds, 120);
      expect(decoded.autoRecommendNextExercise, isFalse);
      expect(decoded.customExercises.single.name, '나만의 프레스');
      expect(decoded.customExercises.single.muscle, '가슴');
      expect(decoded.goals, ['근육 증가', '체력 향상']);
      expect(decoded.heightCm, 175.5);
      expect(decoded.weight, 72.4);
      expect(decoded.age, 29);
      expect(decoded.gender, 'M');
      expect(
        decoded.sessions[date]!.exercises.first.sets.first.completed,
        isTrue,
      );
      expect(
        decoded.sessions[date]!.exercises.first.sets.first.restSeconds,
        150,
      );
      expect(decoded.routines.single.name, '하체 루틴');
      expect(decoded.routines.single.exercises.single.id, 'squat');
      expect(decoded.routines.single.accessTier, RoutineAccessTier.paid);
      final routineSet = decoded.routines.single.setsFor(catalog.first).single;
      expect(routineSet.weight, 82.5);
      expect(routineSet.reps, 6);
      expect(routineSet.type, '웜업');
      expect(routineSet.restSeconds, 135);
      expect(decoded.routines.single.sourceMarketRoutineId, 'market-routine-1');
      expect(
        decoded.routines.single.sourceCoachingRoutineId,
        'coaching-routine-1',
      );
      expect(decoded.communityPosts.single.likes, 3);
      expect(
        decoded.communityPosts.single.imageUrl,
        'https://example.com/workout.jpg',
      );
      expect(decoded.communityPosts.single.activeOverlays, ['날짜', '완료 루틴']);
      expect(decoded.communityPosts.single.comments.single.content, '좋아요');
      expect(decoded.consultations.single.status, ConsultationStatus.answered);
      expect(decoded.consultations.single.response, contains('큰 근육'));
      final dashboard = decoded.businessDashboards[UserRole.trainer]!;
      expect(dashboard.facts['revenue'], '2,480,000원');
      expect(dashboard.tasks.single.id, 'task_1');
      expect(dashboard.notifications.single.isRead, isTrue);
    });

    test('reads schema version 1 snapshots without social data', () {
      final decoded = AppSnapshotCodec.decode('''
        {
          "schemaVersion": 1,
          "preferences": {
            "role": "member",
            "isDarkMode": false,
            "weightUnit": "kg",
            "restDefaultSeconds": 90
          },
          "sessions": [],
          "routines": []
        }
        ''', const []);

      expect(decoded, isNotNull);
      expect(decoded!.role, UserRole.member);
      expect(decoded.communityPosts, isEmpty);
      expect(decoded.consultations, isEmpty);
      expect(decoded.businessDashboards, isEmpty);
    });

    test('reads schema version 2 snapshots without business data', () {
      final decoded = AppSnapshotCodec.decode('''
        {
          "schemaVersion": 2,
          "preferences": {
            "role": "trainer",
            "isDarkMode": false,
            "weightUnit": "kg",
            "restDefaultSeconds": 90
          },
          "sessions": [],
          "routines": [],
          "communityPosts": [],
          "consultations": []
        }
        ''', const []);

      expect(decoded, isNotNull);
      expect(decoded!.role, UserRole.trainer);
      expect(decoded.businessDashboards, isEmpty);
    });

    test('defaults legacy workout sets to a 90 second rest', () {
      const catalog = [
        ExerciseTemplate(
          id: 'squat',
          name: '스쿼트',
          muscle: '하체',
          icon: Icons.accessibility_new,
        ),
      ];
      final decoded = AppSnapshotCodec.decode('''
        {
          "schemaVersion": 4,
          "preferences": {"role": "member"},
          "sessions": [{
            "date": "2026-08-15T00:00:00.000",
            "exercises": [{
              "id": "legacy_squat",
              "templateId": "squat",
              "sets": [{"number": 1, "weight": 80, "reps": 8}]
            }]
          }],
          "routines": []
        }
        ''', catalog)!;

      expect(
        decoded.sessions.values.single.exercises.single.sets.single.restSeconds,
        90,
      );
    });

    test('returns null for an unsupported schema', () {
      expect(
        AppSnapshotCodec.decode('{"schemaVersion":999}', const []),
        isNull,
      );
    });

    test('restores sessions that reference a user-created exercise', () {
      const custom = ExerciseTemplate(
        id: 'custom_incline_press',
        name: '나만의 인클라인 프레스',
        muscle: '가슴',
        icon: Icons.fitness_center,
      );
      final date = DateTime(2026, 8, 18);
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
                id: 'custom_workout',
                template: custom,
                sets: [WorkoutSetEntry(number: 1, weight: 42.5, reps: 10)],
              ),
            ],
          ),
        },
        routines: const [],
        customExercises: const [custom],
      );

      final decoded = AppSnapshotCodec.decode(
        AppSnapshotCodec.encode(snapshot),
        const [],
      )!;

      expect(decoded.customExercises.single.id, custom.id);
      expect(
        decoded.sessions[date]!.exercises.single.template.name,
        custom.name,
      );
      expect(decoded.sessions[date]!.exercises.single.sets.single.weight, 42.5);
    });
  });

  test('AppState persists user changes through the repository', () async {
    final repository = MemoryAppRepository();
    final state = AppState(repository: repository);
    await state.initialize();

    state.chooseRole(UserRole.trainer);
    state.toggleTheme();
    state.setWeightUnit('lb');
    state.setRestDefaultSeconds(120);
    state.createRoutine('저장 테스트', '앱 재시작 후에도 유지');
    final workoutDate = DateTime(2026, 8, 15);
    state.addExercise(
      workoutDate,
      state.exercises.firstWhere((exercise) => exercise.id == 'cable_fly'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));

    final restored = AppState(repository: repository);
    await restored.initialize();

    expect(restored.role, UserRole.trainer);
    expect(restored.isDarkMode, isTrue);
    expect(restored.weightUnit, 'lb');
    expect(restored.restDefaultSeconds, 120);
    expect(restored.routines.any((item) => item.name == '저장 테스트'), isTrue);
    expect(
      restored.sessions[workoutDate]!.exercises.single.template.id,
      'cable_fly',
    );

    state.dispose();
    restored.dispose();
  });
}
