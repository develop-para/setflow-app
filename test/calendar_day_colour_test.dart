import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/korean_holidays.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/theme.dart';

/// The calendar follows the convention every Korean reader already knows:
/// Sunday and public holidays in red, Saturday in blue. Getting this wrong is
/// not a style slip — a red 15th says "광복절", and a grey one says nothing.
void main() {
  Future<void> pumpCalendar(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: const Scaffold(body: CalendarScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 250ms 저장 디바운스를 흘려보낸다 — 남아 있으면 바인딩이 테스트를 실패시킨다.
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// The colour the calendar actually painted on a day number.
  ///
  /// Matched on having an explicit colour rather than on a weight: the weight
  /// belongs to the type scale and moves when the scale does, which is exactly
  /// what this test must not care about.
  Color colourOf(WidgetTester tester, int day) {
    final texts = tester
        .widgetList<Text>(find.text('$day'))
        .where((text) => text.style?.color != null);
    expect(texts, isNotEmpty, reason: '$day일 칸을 찾지 못했다');
    return texts.first.style!.color!;
  }

  /// A day in the month the calendar is showing, matching [test].
  int dayIn(DateTime month, bool Function(DateTime) test) {
    for (var day = 1; day <= 28; day++) {
      final date = DateTime(month.year, month.month, day);
      if (test(date)) return day;
    }
    fail('이번 달에 조건에 맞는 날이 없다');
  }

  testWidgets('the calendar paints the week the way a Korean reader reads it', (
    tester,
  ) async {
    await pumpCalendar(tester);
    // The calendar opens on the real current month, so the days are picked from
    // it rather than hard-coded — the convention is what is under test, not a
    // particular August.
    final month = DateTime.now();
    final colors = SetflowTheme.light.extension<SetflowSemanticColors>()!;
    final onSurface = SetflowTheme.light.colorScheme.onSurface;

    final sunday = dayIn(month, (d) => d.weekday == DateTime.sunday);
    final saturday = dayIn(month, (d) => d.weekday == DateTime.saturday);
    final weekday = dayIn(
      month,
      (d) =>
          d.weekday != DateTime.sunday &&
          d.weekday != DateTime.saturday &&
          holidayOf(d) == null &&
          d.day != DateTime.now().day,
    );

    expect(colourOf(tester, sunday), colors.error, reason: '일요일이 빨강이 아니다');
    expect(colourOf(tester, saturday), colors.blue, reason: '토요일이 파랑이 아니다');
    expect(colourOf(tester, weekday), onSurface, reason: '평일이 주말 색으로 칠해졌다');
  });

  testWidgets('a holiday is red wherever it lands', (tester) async {
    await pumpCalendar(tester);
    final colors = SetflowTheme.light.extension<SetflowSemanticColors>()!;
    final month = DateTime.now();

    // Only meaningful in a month that actually has one; the holiday dates
    // themselves are pinned in korean_holidays_test.
    int? holiday;
    for (var day = 1; day <= 28; day++) {
      final date = DateTime(month.year, month.month, day);
      if (holidayOf(date) != null &&
          date.weekday != DateTime.sunday &&
          date.day != DateTime.now().day) {
        holiday = day;
        break;
      }
    }
    if (holiday == null) return;

    expect(
      colourOf(tester, holiday),
      colors.error,
      reason: '$holiday일은 공휴일인데 빨강이 아니다',
    );
  });
}
