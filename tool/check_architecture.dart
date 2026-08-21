// Sub-second architecture check.
//
//   dart run tool/check_architecture.dart
//
// Same rules as `test/architecture_test.dart`, but without booting the Flutter
// test harness — fast enough to run after every file edit. The Claude Code hook
// in `.claude/settings.json` fires this so an agent sees its own violation
// immediately and fixes it inside the same turn, instead of the human finding
// out in CI.
//
// Exit code 1 with the offending lines on failure, silent on success.
import 'dart:io';

import 'architecture_rules.dart';

void main(List<String> args) {
  final failures = <String>[];
  for (final rule in architectureRules) {
    final violations = findViolations(rule);
    if (violations.isNotEmpty) failures.add(describeFailure(rule, violations));
  }

  if (failures.isEmpty) {
    // Quiet on success: a hook that chatters on every edit gets muted.
    exit(0);
  }

  stderr.writeln(failures.join('\n'));
  stderr.writeln(
    '이 규칙들은 AWS 이전 비용을 낮추려고 존재한다. 예외가 정말 필요하면 '
    'tool/architecture_rules.dart의 allow에 추가하고 커밋 메시지에 이유를 남길 것.',
  );
  exit(1);
}
