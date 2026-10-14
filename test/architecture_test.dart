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

  group('운동 추천 계획의 표현', () {
    final rule = architectureRules.singleWhere(
      (rule) => rule.name == '운동 추천의 기본 계획을 과학적 상한으로 표현하지 않는다',
    );

    test('계획 종료를 개인에게 검증된 최적량·안전 경계로 표현하지 못한다', () {
      for (final source in [
        "Text('권장 운동량 한도에 도달했어요.')",
        "Text('최적운동량상한을 넘었어요.')",
        "Text('안전 운동량의 상한에 도달했어요.')",
      ]) {
        expect(rule.pattern.hasMatch(source), isTrue, reason: source);
      }
    });

    test('앱 계획·관찰량·적용 한계·시간 조건은 설명할 수 있다', () {
      for (final source in [
        "Text('앱의 기본 추천 계획에 도달했어요.')",
        "Text('이번 주 완료량은 가슴 8세트예요.')",
        "Text('개인별 최적량이나 안전 상한을 뜻하지 않습니다.')",
        "Text('선택한 시간에 들어갈 추천이 없어요.')",
      ]) {
        expect(rule.pattern.hasMatch(source), isFalse, reason: source);
      }
    });

    test('운동 화면·엔진에 적용하고 예외 없이 출처 검토 한계를 밝힌다', () {
      expect(
        rule.searchIn,
        containsAll([
          'lib/app_state.dart',
          'lib/screens/workout_screens.dart',
          'lib/services/exercise_recommendation_engine.dart',
          'lib/services/resistance_prescription_engine.dart',
          'lib/services/personal_coaching_engine.dart',
        ]),
      );
      expect(rule.searchIn, isNot(contains('lib')));
      expect(rule.allow, isEmpty);
      expect(rule.why, contains('연구 근거의 타당성을 검증하지 않는다'));
      expect(rule.instead, contains('docs/workout-evidence-policy.md'));
    });
  });
}
