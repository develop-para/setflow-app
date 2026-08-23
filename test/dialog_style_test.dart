import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/theme.dart';

/// Thirty-eight dialogs in this app, none of which style themselves. That makes
/// the theme the only place their type and spacing are decided — and the only
/// place a regression can come from.
///
/// It also means a dialog that quietly opts out of the theme (its own
/// titleTextStyle, its own padding) breaks the set without anyone noticing, so
/// the values are asserted here rather than left to look right in one screen.
void main() {
  DialogThemeData dialogOf(ThemeData theme) => theme.dialogTheme;

  test('dialog type comes from the app scale, not Material headlines', () {
    for (final theme in [SetflowTheme.light, SetflowTheme.dark]) {
      final dialog = dialogOf(theme);
      final title = dialog.titleTextStyle;
      final content = dialog.contentTextStyle;

      expect(title, isNotNull, reason: '다이얼로그 제목 스타일이 테마에 없다');
      expect(content, isNotNull, reason: '다이얼로그 본문 스타일이 테마에 없다');

      // Material's default dialog title is headlineSmall — 24sp, a size this
      // app uses nowhere else, which is what made every dialog look borrowed.
      expect(title!.fontSize, lessThan(22));
      expect(title.fontWeight, FontWeight.w800);

      // Body copy in these dialogs runs several lines of Korean; it needs the
      // leading or it sets as a block.
      expect(content!.height, greaterThanOrEqualTo(1.5));
    }
  });

  test('a dialog title reads against the dialog, not the page', () {
    for (final theme in [SetflowTheme.light, SetflowTheme.dark]) {
      final dialog = dialogOf(theme);
      final surface = dialog.backgroundColor!;
      // The dialog sits on its own container colour, so the text has to be
      // checked against that rather than the scaffold behind it.
      expect(
        _contrast(dialog.titleTextStyle!.color!, surface),
        greaterThanOrEqualTo(4.5),
        reason: '다이얼로그 제목이 다이얼로그 배경에서 안 읽힌다',
      );
      expect(
        _contrast(dialog.contentTextStyle!.color!, surface),
        greaterThanOrEqualTo(4.5),
        reason: '다이얼로그 본문이 다이얼로그 배경에서 안 읽힌다',
      );
    }
  });

  test('dialogs keep a margin on a narrow phone', () {
    for (final theme in [SetflowTheme.light, SetflowTheme.dark]) {
      final inset = dialogOf(theme).insetPadding!.resolve(TextDirection.ltr);
      // 360px phones exist; Material's default leaves the dialog nearly edge
      // to edge on one.
      expect(inset.left, greaterThanOrEqualTo(24));
      expect(inset.right, greaterThanOrEqualTo(24));
    }
  });

  testWidgets('the buttons do not sit on the dialog edge', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SetflowTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('삭제할까요?'),
                  content: const Text('되돌릴 수 없습니다.'),
                  actions: [
                    TextButton(onPressed: () {}, child: const Text('취소')),
                    FilledButton(onPressed: () {}, child: const Text('삭제')),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final dialog = tester.getRect(find.byType(AlertDialog));
    final action = tester.getRect(find.widgetWithText(FilledButton, '삭제'));
    expect(
      dialog.bottom - action.bottom,
      greaterThanOrEqualTo(12),
      reason: '확인 버튼이 다이얼로그 바닥에 붙어 있다',
    );
    expect(
      dialog.right - action.right,
      greaterThanOrEqualTo(12),
      reason: '확인 버튼이 다이얼로그 오른쪽 끝에 붙어 있다',
    );
  });

  testWidgets('a dialog title starts at the edge, never centred', (
    tester,
  ) async {
    // Material 3 centres the title as soon as an icon is given, which is what
    // split the seven decorated dialogs off from the other thirty-one. The
    // icons are gone; this is what keeps them gone.
    await tester.pumpWidget(
      MaterialApp(
        theme: SetflowTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    const AlertDialog(title: Text('제목'), content: Text('본문')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Not the title's centre: a Text fills the width it is given, so its box is
    // centred in the dialog whether the glyphs are or not. The start edge is
    // what actually moves, and Material 3 indents the title when it centres it.
    final title = tester.getRect(find.text('제목'));
    final content = tester.getRect(find.text('본문'));
    expect(
      (title.left - content.left).abs(),
      lessThan(1),
      reason: '제목과 본문의 시작선이 어긋난다 — icon 슬롯이 다시 들어왔는지 확인할 것',
    );
    expect(
      tester.widget<Text>(find.text('제목')).textAlign,
      isNot(TextAlign.center),
    );
  });
}

double _contrast(Color a, Color b) {
  double lum(Color c) {
    double channel(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(c.r) +
        0.7152 * channel(c.g) +
        0.0722 * channel(c.b);
  }

  final la = lum(a);
  final lb = lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}
