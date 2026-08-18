import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/'
    '20260816235258_cardio_metrics_account_and_routine_sync.sql',
  ).readAsStringSync();
  final appRepository = File(
    'lib/data/supabase_app_repository.dart',
  ).readAsStringSync();
  final businessRepository = File(
    'lib/data/supabase_business_repository.dart',
  ).readAsStringSync();

  test('cardio metrics have bounded nullable storage on every set table', () {
    expect(migration, contains('add column if not exists intensity_rpe'));
    expect(migration, contains('alter column target_reps drop not null'));
    expect(migration, contains('workout_sets_cardio_metrics_valid'));
    expect(migration, contains('routine_sets_content_valid'));
    expect(migration, contains('coaching_routine_sets_content_valid'));
    expect(migration, contains('duration_sec between 0 and 604800'));
    expect(migration, contains('distance_m between 0 and 999999.99'));
    expect(migration, contains('intensity_rpe between 1 and 10'));
  });

  test('account snapshots project time distance and RPE atomically', () {
    expect(
      migration,
      contains('create or replace function private.sync_my_workout_snapshot'),
    );
    expect(migration, contains("v_set ->> 'duration_sec'"));
    expect(migration, contains("v_set ->> 'distance_m'"));
    expect(migration, contains("v_set ->> 'intensity_rpe'"));
    expect(
      migration,
      contains('when v_has_duration then excluded.duration_sec'),
    );
    expect(migration, contains('when v_has_distance then excluded.distance_m'));
    expect(
      migration,
      contains('when v_has_intensity_rpe then excluded.intensity_rpe'),
    );

    expect(
      migration,
      contains(
        'create or replace function private.reject_snapshot_schema_downgrade',
      ),
    );
    expect(migration, contains('new.schema_version < old.schema_version'));
    expect(migration, contains('v_has_duration'));
    expect(migration, contains('v_has_distance'));
    expect(migration, contains('v_has_intensity_rpe'));

    expect(appRepository, contains("'duration_sec': set.durationSeconds"));
    expect(appRepository, contains('set.distanceKm * 1000'));
    expect(appRepository, contains("'intensity_rpe': set.intensityRpe"));
  });

  test('routine save clone apply and copy preserve cardio prescriptions', () {
    for (final functionName in const [
      'save_coaching_routine',
      'save_personal_routine',
      'clone_coaching_routine',
      'apply_routine',
      'copy_session',
    ]) {
      final functionStart = migration.indexOf(
        'create or replace function private.$functionName',
      );
      expect(functionStart, greaterThan(0), reason: functionName);
      final nextFunction = migration.indexOf(
        'create or replace function private.',
        functionStart + 40,
      );
      final functionSql = migration.substring(
        functionStart,
        nextFunction < 0 ? migration.length : nextFunction,
      );
      expect(functionSql, contains('duration_sec'), reason: functionName);
      expect(functionSql, contains('distance_m'), reason: functionName);
      expect(functionSql, contains('intensity_rpe'), reason: functionName);
    }
    expect(
      migration,
      contains('jsonb_array_length(sets_value) not between 1 and 20'),
    );
  });

  test('trainer member detail and Dart DTO mapping expose intensity RPE', () {
    final detailStart = migration.indexOf(
      'create or replace function private.get_business_member_detail',
    );
    expect(detailStart, greaterThan(0));
    expect(
      migration.substring(detailStart),
      contains("'intensity_rpe', workout_set.intensity_rpe"),
    );
    expect(
      businessRepository,
      contains("intensityRpe: _nullableDouble(row['intensity_rpe'])"),
    );
    expect(businessRepository, contains("'duration_sec': durationSeconds"));
    expect(businessRepository, contains("'distance_m': distanceMeters"));
    expect(businessRepository, contains("'intensity_rpe': intensityRpe"));
  });

  test(
    'e1RM projection ignores cardio, special sets, and high repetitions',
    () {
      expect(
        migration,
        contains('create or replace function public.tg_set_1rm()'),
      );
      expect(migration, contains('and not v_is_cardio'));
      expect(migration, contains("and new.type = 'normal'"));
      expect(migration, contains('coalesce(new.reps, 0) between 1 and 10'));
      expect(migration, contains('new.weight * 36 / (37 - new.reps)'));
      expect(migration, contains('new.estimated_1rm := null'));
      expect(migration, contains('update public.workout_sets workout_set'));
      expect(migration, contains("and v_type = 'normal'"));
      expect(migration, contains('and v_reps between 1 and 10'));
      expect(migration, contains('and v_duration_seconds is null'));
      expect(migration, contains('and v_distance_meters is null'));
    },
  );

  test('new columns retain the existing RLS and least privilege model', () {
    expect(migration, contains('alter table public.workout_sets enable row'));
    expect(migration, contains('alter table public.routine_sets enable row'));
    expect(
      migration,
      contains('alter table public.coaching_routine_sets enable row'),
    );
    expect(migration, contains('revoke all on table public.workout_sets,'));
    expect(
      migration,
      contains(
        'grant select, insert, update, delete on table public.workout_sets',
      ),
    );
    expect(migration, contains('private.sync_my_workout_snapshot(jsonb)'));
  });
}
