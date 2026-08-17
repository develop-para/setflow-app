import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final file = File(
    'supabase/migrations/'
    '20260816131928_harden_legacy_security_definer_rpcs.sql',
  );

  test('all six exposed legacy functions become security invoker wrappers', () {
    final sql = file.readAsStringSync();
    for (final name in const [
      'apply_routine',
      'can_access_member',
      'copy_session',
      'reconcile_ledger',
      'request_approval',
      'resolve_approval',
    ]) {
      expect(
        sql,
        contains('create or replace function private.$name'),
        reason: '$name needs a checked private implementation',
      );
      expect(
        RegExp(
          'create or replace function public\\.$name[\\s\\S]*?'
          'security invoker[\\s\\S]*?set search_path = \'\'',
        ).hasMatch(sql),
        isTrue,
        reason: '$name must no longer be a public SECURITY DEFINER',
      );
    }
  });

  test('member RLS helper and mutation payload checks fail closed', () {
    final sql = file.readAsStringSync();

    expect(sql, contains("m.status = 'active'"));
    expect(sql, contains("g.status = 'verified'"));
    expect(sql, contains("t.status = 'approved'"));
    expect(sql, contains("gt.status = 'active'"));
    expect(sql, contains('r.owner_user_id = v_uid'));
    expect(sql, contains('p_from = p_to'));
    expect(sql, contains('not private.is_admin()'));
    expect(sql, contains("jsonb_typeof(v_payload) <> 'object'"));
    expect(sql, contains('octet_length(v_payload::text) > 65536'));
    expect(sql, contains('for update'));
    expect(sql, contains('Maker cannot resolve the same approval'));
  });

  test('application has no direct dependency on admin-only legacy RPCs', () {
    final source = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((item) => item.path.endsWith('.dart'))
        .map((item) => item.readAsStringSync())
        .join('\n');

    for (final name in const [
      'reconcile_ledger',
      'request_approval',
      'resolve_approval',
    ]) {
      expect(source, isNot(contains("rpc('$name'")));
      expect(source, isNot(contains('rpc("$name"')));
    }
  });

  test('legacy consent and contract ALL policies are split by command', () {
    final sql = file.readAsStringSync();

    expect(sql, contains('drop policy if exists rw_marketing'));
    expect(sql, contains('marketing_consents_participant_read'));
    expect(sql, contains('marketing_consents_member_insert'));
    expect(sql, contains('marketing_consents_member_update'));
    expect(sql, contains('marketing_consents_member_delete'));
    expect(sql, contains('m.user_id = (select auth.uid())'));
    expect(sql, contains("m.status = 'active'"));
    expect(sql, contains('grant update (opt_in)'));
    expect(sql, isNot(contains('grant update (member_id, opt_in)')));

    expect(sql, contains('drop policy if exists rw_contracts'));
    expect(sql, contains('coaching_contracts_participant_read'));
    expect(sql, contains('coaching_contracts_business_insert'));
    expect(sql, contains('coaching_contracts_business_update'));
    expect(sql, contains('coaching_contracts_admin_delete'));
    expect(sql, contains('using ((select private.is_admin()))'));
    expect(sql, contains('grant update (product_name, start_date, end_date)'));
    expect(sql, contains('coaching_contracts_member_id_idx'));
  });
}
