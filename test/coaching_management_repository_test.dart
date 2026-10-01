import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/data/coaching_management_repository.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/data/supabase_coaching_management_repository.dart';
import 'package:setflow/models.dart';

void main() {
  test(
    'history preserves server permission, original revision, and cursor',
    () async {
      final adapter = _Adapter();
      final session = WorkoutSession(
        date: DateTime(2026, 9, 11),
        exercises: [
          WorkoutExercise(
            id: 'exercise',
            template: exerciseCatalog.first,
            sets: [WorkoutSetEntry(number: 1, weight: 40, reps: 10)],
          ),
        ],
      );
      adapter.response = {
        'workouts': [
          {
            'key': 'personal:2026-09-11',
            'revision': 'opaque-server-revision',
            'title': '개인 운동',
            'kind': 'personal',
            'session': AppSnapshotCodec.sessionToJson(session),
            'can_propose': false,
            'requires_approval': true,
          },
        ],
        'next_cursor': '2026-09-11/personal:2026-09-11',
      };
      final page = await adapter.listManagedWorkouts('link', before: 'cursor');
      expect(
        [adapter.calls.single.$1, adapter.calls.single.$2],
        [
          'list_managed_workouts',
          {'link_id': 'link', 'before_key': 'cursor'},
        ],
      );
      expect(page.nextCursor, '2026-09-11/personal:2026-09-11');
      expect(page.workouts.single.canPropose, isFalse);
      expect(page.workouts.single.requiresApproval, isTrue);
      expect(
        page.workouts.single.session.exercises.single.sets.single.weight,
        40,
      );
      adapter.response = null;
      await adapter.proposeWorkoutCorrection(
        linkId: 'link',
        workout: page.workouts.single,
        exerciseId: 'exercise',
        setNumber: 1,
        metric: WorkoutMetric.weight,
        value: 42.5,
        reason: '중량 확인',
        requestId: 'request',
      );
      expect(
        [adapter.calls.last.$1, adapter.calls.last.$2],
        [
          'propose_workout_correction',
          {
            'link_id': 'link',
            'record_key': 'personal:2026-09-11',
            'expected_revision': 'opaque-server-revision',
            'exercise_id': 'exercise',
            'set_number': 1,
            'metric': 'weight',
            'value': 42.5,
            'reason': '중량 확인',
            'request_id': 'request',
          },
        ],
      );
    },
  );

  test('consent responses and gym reassignment stay domain RPCs', () async {
    final adapter = _Adapter();
    await adapter.requestManagementLink('consultation');
    await adapter.respondManagementLink('link', accept: true);
    await adapter.setManagementGym('link', null);
    await adapter.requestManagementTrainerChange('link', 'trainer');
    await adapter.respondWorkoutCorrection('correction', accept: false);
    await adapter.endManagementLink('link');
    expect(adapter.calls.map((c) => [c.$1, c.$2]), [
      [
        'request_management_link',
        {'consultation_id': 'consultation'},
      ],
      [
        'respond_management_link',
        {'link_id': 'link', 'accept': true},
      ],
      [
        'set_management_gym',
        {'link_id': 'link', 'gym_id': null},
      ],
      [
        'request_management_trainer_change',
        {'link_id': 'link', 'trainer_id': 'trainer'},
      ],
      [
        'respond_workout_correction',
        {'correction_id': 'correction', 'accept': false},
      ],
      [
        'end_management_link',
        {'link_id': 'link'},
      ],
    ]);
  });
}

class _Adapter with SupabaseCoachingManagement {
  Object? response;
  final calls = <(String, Map<String, dynamic>?)>[];
  @override
  Future<dynamic> managementRpc(
    String name, {
    Map<String, dynamic>? params,
  }) async {
    calls.add((name, params));
    return response;
  }
}
