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
        themeMode: ThemeMode.dark,
        weightUnit: 'lb',
        restDefaultSeconds: 120,
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
      expect(decoded.themeMode, ThemeMode.dark);
      expect(decoded.weightUnit, 'lb');
      expect(decoded.restDefaultSeconds, 120);
      expect(
        decoded.sessions[date]!.exercises.first.sets.first.completed,
        isTrue,
      );
      expect(decoded.routines.single.name, '하체 루틴');
      expect(decoded.routines.single.exercises.single.id, 'squat');
      expect(decoded.communityPosts.single.likes, 3);
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

    test('returns null for an unsupported schema', () {
      expect(
        AppSnapshotCodec.decode('{"schemaVersion":999}', const []),
        isNull,
      );
    });
  });

  test('AppState persists user changes through the repository', () async {
    final repository = MemoryAppRepository();
    final state = AppState(repository: repository);
    await state.initialize();

    state.chooseRole(UserRole.trainer);
    state.setThemeMode(ThemeMode.light);
    state.setWeightUnit('lb');
    state.setRestDefaultSeconds(120);
    state.createRoutine('저장 테스트', '앱 재시작 후에도 유지');
    await Future<void>.delayed(const Duration(milliseconds: 350));

    final restored = AppState(repository: repository);
    await restored.initialize();

    expect(restored.role, UserRole.trainer);
    // Theme follows the system by default; the explicit light choice above
    // must survive a restart.
    expect(restored.themeMode, ThemeMode.light);
    expect(restored.isDarkMode, isFalse);
    expect(restored.weightUnit, 'lb');
    expect(restored.restDefaultSeconds, 120);
    expect(restored.routines.any((item) => item.name == '저장 테스트'), isTrue);

    state.dispose();
    restored.dispose();
  });
}
