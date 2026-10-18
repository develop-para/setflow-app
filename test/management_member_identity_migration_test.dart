import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final original = File(
    'supabase/migrations/'
    '20261001063252_coaching_management_consent.sql',
  ).readAsStringSync();
  final migration = File(
    'supabase/migrations/'
    '20261018150956_management_member_identity.sql',
  ).readAsStringSync();

  for (final name in ['list_management_links', 'list_workout_corrections']) {
    test('$name adds member identity without widening access', () {
      final previous = _function(original, name);
      final updated = _function(migration, name);
      const identity = "'member_user_id',l.member_user_id,";
      expect(updated, contains(identity));
      expect(
        _normalized(updated.replaceFirst(identity, '')),
        _normalized(previous),
        reason:
            'Participant, consent, result ordering, and response permissions '
            'must remain the same when adding the member identity.',
      );
    });
  }

  test('identity migration preserves public wrappers and function grants', () {
    expect(
      RegExp('create or replace function').allMatches(migration).length,
      2,
    );
    expect(migration, isNot(contains('function public.')));
    expect(migration, isNot(contains('grant execute')));
    expect(migration, isNot(contains('revoke ')));
    expect(migration.trim(), startsWith('begin;'));
    expect(migration.trim(), endsWith('commit;'));
  });
}

String _function(String sql, String name) {
  final declaration = 'create or replace function private.$name()';
  final start = sql.indexOf(declaration);
  expect(start, greaterThanOrEqualTo(0));
  final end = sql.indexOf(r'$$;', start);
  expect(end, greaterThan(start));
  return sql.substring(start, end + 3);
}

String _normalized(String sql) => sql.replaceAll(RegExp(r'\s+'), ' ').trim();
