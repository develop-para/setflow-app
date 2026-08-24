import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// An icon button with no label is an unnamed button to a screen reader, and
/// a guess to everyone else. Every one in the app says what it does — through
/// `tooltip`, or through a `Semantics` wrapper where the tooltip would collide
/// with the layout.
///
/// Checked over the source rather than by rendering: these live on screens that
/// need data to reach, and the property is static anyway.
void main() {
  test('every IconButton says what it does', () {
    final allowed = {
      // Semantics 로 감싸 이름을 준다 — 툴팁을 겹쳐 띄우지 않기 위해서다.
      'common.dart',
      // 개발용 토큰 미리보기. 제품 화면이 아니다.
      'kinetic_preview.dart',
    };
    final offenders = <String>[];

    for (final dir in ['lib/screens', 'lib/widgets']) {
      for (final file in Directory(dir).listSync().whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final name = file.uri.pathSegments.last;
        if (allowed.contains(name)) continue;
        final source = file.readAsStringSync();

        for (final match in RegExp(r'IconButton\(').allMatches(source)) {
          var depth = 1;
          var i = match.end;
          while (i < source.length && depth > 0) {
            if (source[i] == '(') depth++;
            if (source[i] == ')') depth--;
            i++;
          }
          final body = source.substring(match.end, i - 1);
          if (!body.contains('tooltip:')) {
            final line =
                '\n'.allMatches(source.substring(0, match.start)).length + 1;
            offenders.add('$name:$line');
          }
        }
      }
    }

    expect(offenders, isEmpty, reason: '이 아이콘 버튼들이 이름을 갖고 있지 않다');
  });
}
