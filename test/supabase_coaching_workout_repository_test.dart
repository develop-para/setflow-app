import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/data/coaching_workout_repository.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/data/supabase_coaching_workout_repository.dart';
import 'package:setflow/models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late SupabaseCoachingWorkoutRepository repository;
  late List<(String, Map<String, dynamic>)> calls;
  late WorkoutSession session;
  late Map<String, dynamic> response;
  bool conflict = false;

  setUp(() async {
    calls = [];
    conflict = false;
    session = WorkoutSession(
      date: DateTime(2026, 9, 11),
      exercises: [
        WorkoutExercise(
          id: 'bench-session',
          template: exerciseCatalog.first,
          sets: [
            WorkoutSetEntry(
              number: 1,
              weight: 42.5,
              reps: 8,
              completed: true,
              restSeconds: 90,
            ),
          ],
        ),
      ],
    );
    response = {
      'id': 'workout-id',
      'kind': 'lesson',
      'status': 'in_progress',
      'trainer_id': 'trainer-id',
      'member_user_id': 'member-id',
      'trainer_name': '김코치',
      'member_name': '이회원',
      'title': '오늘 수업',
      'instruction': '',
      'date': '2026-09-11',
      'session': AppSnapshotCodec.sessionToJson(session),
      'version': 3,
      'can_edit': false,
      'recording_allowed': true,
      'schedule_id': 'schedule-id',
      'starts_at': '2026-09-11T04:00:00+00:00',
      'ends_at': '2026-09-11T05:00:00+00:00',
      'edit_blocked_reason': '수업 시간이 끝났어요',
      'last_editor_name': '김코치',
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = SupabaseClient(
      'http://${server.address.host}:${server.port}',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    repository = SupabaseCoachingWorkoutRepository(client);
    server.listen((request) async {
      final payload = await utf8.decoder.bind(request).join();
      final args = payload.isEmpty || payload == 'null'
          ? <String, dynamic>{}
          : jsonDecode(payload) as Map<String, dynamic>;
      final name = request.uri.pathSegments.last;
      calls.add((name, args));
      request.response.headers.contentType = ContentType.json;
      if (conflict) {
        request.response.statusCode = 409;
        request.response.write(
          jsonEncode({
            'code': 'PT409',
            'message': 'Coaching workout changed; reload before saving',
            'details': 'coaching_workout_version_conflict',
          }),
        );
      } else {
        final Object? body = switch (name) {
          'list_coaching_workouts' => [response],
          'set_lesson_recording_consent' => null,
          'get_my_coaching_reminder' => {'enabled': false, 'hour': 19},
          'set_my_coaching_reminder' => args,
          _ => response,
        };
        request.response.write(jsonEncode(body));
      }
      await request.response.close();
    });
  });
  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  test(
    'inline templates and completed sets survive the canonical RPC boundary',
    () async {
      final workout = await repository.saveCoachingWorkout(
        workoutId: 'workout-id',
        expectedVersion: 2,
        session: session,
        requestId: 'request-id',
      );
      expect(workout.kind, CoachingWorkoutKind.lesson);
      expect(workout.canEdit, isFalse);
      expect(workout.recordingAllowed, isTrue);
      expect(workout.endsAt, DateTime.utc(2026, 9, 11, 5));
      expect(workout.session.exercises.single.sets.single.completed, isTrue);
      expect(workout.session.exercises.single.sets.single.weight, 42.5);
      expect(calls.single.$1, 'save_coaching_workout');
      expect(calls.single.$2['request_id'], 'request-id');
      expect(calls.single.$2['expected_version'], 2);
      final sent = calls.single.$2['session'] as Map;
      expect(
        (sent['exercises'] as List).single['template']['name'],
        exerciseCatalog.first.name,
      );
      expect(
        (sent['exercises'] as List).single['sets'].single['completed'],
        isTrue,
      );
    },
  );

  test(
    'read, consent and reminder calls use the public domain RPC arguments',
    () async {
      final records = await repository.listCoachingWorkouts(
        memberUserId: 'member-id',
      );
      expect(records.single.memberName, '이회원');
      expect(calls.last.$2, {'member_user_id': 'member-id'});
      await repository.openLessonWorkout('schedule-id');
      expect(calls.last.$2, {'schedule_id': 'schedule-id'});
      await repository.setLessonRecordingConsent('schedule-id', false);
      expect(calls.last.$2, {'schedule_id': 'schedule-id', 'allowed': false});
      final initial = await repository.loadMyCoachingReminder();
      expect(initial.enabled, isFalse);
      final changed = await repository.setMyCoachingReminder(true, 20);
      expect(changed.hour, 20);
      expect(changed.enabled, isTrue);
    },
  );

  test(
    'assignment creation retains target member, planned date and message',
    () async {
      await repository.createWorkoutAssignment(
        memberUserId: 'member-id',
        date: session.date,
        title: '하체 과제',
        instruction: '천천히 내려가세요',
        session: session,
        requestId: 'create-id',
      );
      expect(calls.last.$2['member_user_id'], 'member-id');
      expect(calls.last.$2['date'], '2026-09-11');
      expect(calls.last.$2['instruction'], '천천히 내려가세요');
      await repository.cancelWorkoutAssignment(
        workoutId: 'workout-id',
        expectedVersion: 3,
        requestId: 'cancel-id',
      );
      expect(calls.last.$1, 'cancel_workout_assignment');
      expect(calls.last.$2, {
        'workout_id': 'workout-id',
        'expected_version': 3,
        'request_id': 'cancel-id',
      });
    },
  );

  test(
    'stale version errors are propagated so the editor cannot show false success',
    () async {
      conflict = true;
      await expectLater(
        repository.saveCoachingWorkout(
          workoutId: 'workout-id',
          expectedVersion: 2,
          session: session,
          requestId: 'retry-id',
        ),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', 'PT409'),
        ),
      );
      expect(calls, hasLength(1));
    },
  );
}
