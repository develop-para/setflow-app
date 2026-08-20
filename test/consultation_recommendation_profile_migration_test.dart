import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('consultation survey sharing migration preserves least privilege', () {
    final migrations = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .where(
          (file) => file.path.endsWith(
            '_consultation_recommendation_profile_sharing.sql',
          ),
        )
        .toList(growable: false);

    expect(migrations, hasLength(1));
    final sql = migrations.single.readAsStringSync().toLowerCase();
    final normalized = sql.replaceAll(RegExp(r'\s+'), ' ');

    expect(
      normalized,
      contains(
        'create table public.consultation_recommendation_profile_shares',
      ),
    );
    expect(
      normalized,
      contains(
        'alter table public.consultation_recommendation_profile_shares enable row level security',
      ),
    );
    expect(
      normalized,
      contains(
        'revoke all on table public.consultation_recommendation_profile_shares from public, anon, authenticated',
      ),
    );
    expect(
      normalized,
      contains(
        'grant select on table public.consultation_recommendation_profile_shares to authenticated',
      ),
    );
    expect(
      normalized,
      isNot(
        contains(
          'grant insert on table public.consultation_recommendation_profile_shares to authenticated',
        ),
      ),
    );

    final readHelper = RegExp(
      r'create or replace function private\.can_read_consultation_recommendation_profile\(.*?\$function\$;',
      dotAll: true,
    ).firstMatch(sql)!.group(0)!;
    expect(readHelper, contains('join public.trainers'));
    expect(readHelper, contains('t.user_id = (select auth.uid())'));
    expect(
      readHelper,
      contains('coalesce(c.assigned_trainer_id, c.trainer_id)'),
    );
    expect(readHelper, contains("t.status = 'approved'"));
    expect(readHelper, isNot(contains('public.admin_users')));
    expect(readHelper, isNot(contains('g.owner_user_id')));

    final policyStart = sql.indexOf(
      'create policy consultation_recommendation_profile_participant_read',
    );
    final policyEnd = sql.indexOf(
      'create or replace function private.revoke_consultation',
      policyStart,
    );
    final policy = sql.substring(policyStart, policyEnd);
    expect(policy, contains('from public.consultations owned_consultation'));
    expect(
      policy,
      contains('owned_consultation.user_id = (select auth.uid())'),
    );
    expect(policy, contains('revoked_at is null'));
    expect(
      policy,
      contains('private.can_read_consultation_recommendation_profile'),
    );

    expect(
      normalized,
      contains(
        'private.create_business_consultation( p_request_id uuid, p_trainer_id uuid, p_gym_id uuid, p_routine_id uuid, p_specialty text, p_goal text, p_level text, p_question text, p_recommendation_profile jsonb',
      ),
    );
    expect(
      normalized,
      contains('private.is_valid_recommendation_profile_snapshot'),
    );
    expect(normalized, contains('language plpgsql immutable strict'));
    expect(normalized, contains("'treadmill'"));
    expect(normalized, contains("'shoulderraise'"));
    expect(
      normalized,
      contains('v_existing_profile is distinct from p_recommendation_profile'),
    );
    expect(
      normalized,
      contains('insert into public.consultation_recommendation_profile_shares'),
    );
    expect(
      normalized,
      contains(
        'grant execute on function public.create_business_consultation( uuid, uuid, uuid, uuid, text, text, text, text, jsonb ) to authenticated, service_role',
      ),
    );
    expect(
      normalized,
      isNot(
        contains(
          'grant execute on function public.create_business_consultation( uuid, uuid, uuid, uuid, text, text, text, text, jsonb ) to anon',
        ),
      ),
    );
    expect(
      normalized,
      contains(
        'grant execute on function public.revoke_consultation_recommendation_profile_share(uuid) to authenticated, service_role',
      ),
    );
    expect(
      normalized,
      isNot(
        contains(
          'grant execute on function public.revoke_consultation_recommendation_profile_share(uuid) to anon',
        ),
      ),
    );

    expect(normalized, contains("'share_body_data', v_share_body"));
    expect(normalized, contains("'share_workout_records', v_share_workout"));
  });
}
