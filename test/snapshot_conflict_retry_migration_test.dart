import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('snapshot conflict migration stops serialization retry storms', () {
    final sql = File(
      'supabase/migrations/'
      '20260831123400_stop_snapshot_conflict_retry_storm.sql',
    ).readAsStringSync();

    expect(sql, contains('exception when serialization_failure'));
    expect(sql, contains("errcode = 'PT409'"));
    expect(sql, contains("detail = 'snapshot_version_conflict'"));
    expect(sql, contains('snapshot.payload = p_payload'));
    expect(sql, isNot(contains("raise exception 'Snapshot changed")));
  });
}
