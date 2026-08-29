import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/'
    '20260829231539_trainer_regions_workout_locations_consultation_modes.sql',
  ).readAsStringSync().toLowerCase();

  test('location tables are RLS protected with explicit client grants', () {
    for (final table in const [
      'service_regions',
      'trainer_service_areas',
      'member_workout_locations',
    ]) {
      expect(
        sql,
        contains('alter table public.$table enable row level security'),
      );
      expect(sql, contains('revoke all on table public.$table'));
    }
    expect(sql, contains('member_workout_locations_owner_read'));
    expect(sql, contains('(select auth.uid()) = user_id'));
    expect(sql, contains('trainer_service_areas_authenticated_read'));
  });

  test(
    'consultation mode and conditional location invariants are enforced',
    () {
      expect(sql, contains("consultation_mode in ('online', 'offline')"));
      expect(sql, contains("matching_source in ('direct', 'region', 'gym')"));
      expect(sql, contains('consultations_location_request_check'));
      expect(sql, contains("consultation_mode = 'offline'"));
      expect(sql, contains('requested_region_code is not null'));
    },
  );

  test(
    'matching RPC validates identity, ownership, and trainer availability',
    () {
      expect(sql, contains('private.create_location_aware_consultation'));
      expect(sql, contains('v_user_id uuid := auth.uid()'));
      expect(sql, contains('trainer.accepts_offline_consultation'));
      expect(sql, contains('member_workout_locations location'));
      expect(sql, contains('member.status = \'active\''));
      expect(sql, contains('pg_catalog.pg_advisory_xact_lock'));
      expect(
        sql,
        contains(
          'revoke all on function public.create_location_aware_consultation',
        ),
      );
      expect(
        sql,
        contains(
          'grant execute on function public.create_location_aware_consultation',
        ),
      );
    },
  );
}
