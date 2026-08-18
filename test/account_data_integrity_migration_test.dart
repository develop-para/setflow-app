import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/'
    '20260816144856_account_data_integrity_and_image_limits.sql',
  ).readAsStringSync();

  test('snapshot writes are account-bound and projected atomically', () {
    expect(sql, contains('project_app_snapshot_account_data'));
    expect(sql, contains('app_state_snapshot_project_account_data'));
    expect(sql, contains('save_my_account_snapshot'));
    expect(sql, contains('clear_my_account_data'));
    expect(
      sql,
      contains('(select auth.uid()) is distinct from p_expected_user_id'),
    );
    expect(sql, contains("'autoStartRestTimer'"));
    expect(sql, contains("when goal.value ~ '(근력|파워)' then 'strength'"));
    expect(sql, contains('delete from public.user_goals'));
    expect(sql, contains('revoke all on function public.save_my_app_snapshot'));
  });

  test('personal routine replay cannot recreate a deleted parent', () {
    final functionStart = sql.indexOf(
      'create or replace function private.upsert_personal_routine(',
    );
    final cacheLookup = sql.indexOf(
      'cached_response := private.begin_routine_rpc_request(',
      functionStart,
    );
    final parentLookup = sql.indexOf(
      'select routine.owner_user_id',
      functionStart,
    );
    final parentInsert = sql.indexOf(
      'insert into public.routines (',
      functionStart,
    );

    expect(functionStart, greaterThan(0));
    expect(cacheLookup, greaterThan(functionStart));
    expect(parentLookup, greaterThan(cacheLookup));
    expect(parentInsert, greaterThan(parentLookup));
    expect(sql, isNot(contains('on conflict (id) do nothing')));
    expect(
      sql,
      contains('revoke all on function private.save_personal_routine('),
    );
  });

  test('routine quota and sharing mutations are serialized and audited', () {
    expect(
      sql,
      contains('create or replace function public.tg_routine_limit()'),
    );
    expect(sql, contains('where account_user.id = new.owner_user_id'));
    expect(sql, contains('for update;'));
    expect(
      sql,
      contains('create or replace function private.revoke_routine_share'),
    );
    expect(sql, contains('responded_by_user_id = actor_user_id'));
    expect(sql, contains("'status', 'revoked'"));
    expect(
      sql,
      contains('drop constraint if exists routine_shares_response_shape'),
    );
    expect(sql, contains("status = 'accepted'"));
  });

  test('image evidence is constrained in app and storage boundaries', () {
    expect(sql, contains('validate_trainer_document_object'));
    expect(sql, contains('object_size not between 1 and 4194304'));
    expect(
      sql,
      contains("object_mime not in ('image/jpeg', 'image/png', 'image/webp')"),
    );
    expect(sql, contains('file_size_limit = 2097152'));
    expect(sql, contains('file_size_limit = 4194304'));
    expect(sql, isNot(contains("'image/heic', 'image/heif'")));
    expect(sql, contains('can_mutate_trainer_document_object'));
    expect(sql, contains('trainer_documents_linked_object_immutable_delete'));
    expect(sql, contains('trainer_documents_linked_object_immutable_update'));
  });

  test('account tables expose reads only to authenticated clients', () {
    expect(sql, contains('revoke all on table public.app_state_snapshots,'));
    expect(
      sql,
      isNot(
        contains(
          'grant insert, update on table public.user_settings, '
          'public.user_profiles',
        ),
      ),
    );
    expect(sql, contains('personal_routines_read_own'));
    expect(sql, contains('personal_routine_exercises_read_own'));
    expect(sql, contains('personal_routine_sets_read_own'));
    expect(sql, contains('grant select (user_id, goal)'));
    expect(sql, contains('can_read_member_goal'));

    final repository = File(
      'lib/data/supabase_business_repository.dart',
    ).readAsStringSync();
    expect(repository, contains(".from('user_profiles')"));
    expect(repository, contains(".select('user_id,goal')"));
    expect(repository, contains('goalProjection.containsKey(userId)'));
  });
}
