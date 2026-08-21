// Executable architecture rules.
//
// `docs/backend-portability.md` explains *why* the app is arranged the way it
// is. This file is what makes the arrangement stick: a document nobody has to
// obey is a suggestion, a failing test is a rule.
//
// The rules themselves live in `tool/architecture_rules.dart` so that this test
// and the fast CLI (`dart run tool/check_architecture.dart`, wired to the
// Claude Code edit hook) can never drift apart.
import 'package:flutter_test/flutter_test.dart';

import '../tool/architecture_rules.dart';

void main() {
  group('architecture', () {
    for (final rule in architectureRules) {
      test(rule.name, () {
        final violations = findViolations(rule);
        expect(violations, isEmpty, reason: describeFailure(rule, violations));
      });
    }
  });
}
