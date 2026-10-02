import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/workout_history_calendar.dart';

final _days = [
  WorkoutHistoryDay(
    date: _Date.earlier,
    muscles: ['가슴'],
    completedSets: 0,
    totalSets: 2,
    volumeKg: 0,
    cardioSeconds: 0,
  ),
  WorkoutHistoryDay(
    date: _Date.latest,
    muscles: ['가슴'],
    completedSets: 2,
    totalSets: 2,
    volumeKg: 1200,
    cardioSeconds: 0,
  ),
  WorkoutHistoryDay(
    date: _Date.latest,
    muscles: ['유산소'],
    completedSets: 1,
    totalSets: 1,
    volumeKg: 0,
    cardioSeconds: 1200,
  ),
];

abstract final class _Date {
  static final earlier = DateTime(2026, 8, 14);
  static final latest = DateTime(2026, 8, 15);
}

void main() {
  Future<void> mount(
    WidgetTester tester, {
    ThemeData? theme,
    List<WorkoutHistoryDay>? days,
    DateTime? initialDate,
    double scale = 1,
    Future<void> Function(DateTime)? loadMonth,
  }) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? SetflowTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            padding: SetflowInsets.pageList,
            children: [
              WorkoutHistoryCalendar(
                days: days ?? _days,
                initialDate: initialDate,
                onMonthChanged: loadMonth,
                recordBuilder: (date) => Text('상세 ${date.day}일'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('latest day is selected; taps show one day or an empty state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await mount(tester);
    expect(find.text('2026.08'), findsOneWidget);
    expect(find.textContaining('운동 2일'), findsOneWidget);
    expect(find.text('상세 15일'), findsOneWidget);
    expect(find.text('1.2t · 20분'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('2026년 8월 15일, 가슴, 유산소 3/3 완료')),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(
        find.bySemanticsLabel(RegExp('2026년 8월 15일, 가슴, 유산소 3/3 완료')),
      ),
      matchesSemantics(
        label: '2026년 8월 15일, 가슴, 유산소 3/3 완료 1.2t · 20분',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('history-calendar-day-2026-08-14')),
    );
    await tester.pumpAndSettle();
    expect(find.text('상세 14일'), findsOneWidget);
    expect(find.text('상세 15일'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('history-calendar-day-2026-08-13')),
    );
    await tester.pumpAndSettle();
    expect(find.text('이 날짜에는 저장된 운동 기록이 없어요.'), findsOneWidget);
    expect(find.text('상세 14일'), findsNothing);
    semantics.dispose();
  });

  testWidgets('month navigation loads the month and blocks overlapping taps', (
    tester,
  ) async {
    final gate = Completer<void>();
    final requests = <DateTime>[];
    await mount(
      tester,
      initialDate: DateTime(2026, 1, 15),
      loadMonth: (month) {
        requests.add(month);
        return gate.future;
      },
    );
    await tester.tap(find.byTooltip('이전 달'));
    await tester.pump();
    expect(find.text('2025.12'), findsOneWidget);
    expect(requests, [DateTime(2025, 12)]);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '다음 달',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('이 날짜에는 저장된 운동 기록이 없어요.'), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('이 날짜에는 저장된 운동 기록이 없어요.'), findsOneWidget);
    await tester.tap(find.byTooltip('다음 달'));
    await tester.pumpAndSettle();
    expect(find.text('2026.01'), findsOneWidget);
    expect(requests, [DateTime(2025, 12), DateTime(2026, 1)]);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'calendar is readable at 2x text in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        final theme = dark ? SetflowTheme.dark : SetflowTheme.light;
        await mount(tester, theme: theme, scale: 2);
        expect(tester.takeException(), isNull);
        final fill = tester.widget<Ink>(
          find.byKey(const ValueKey('history-calendar-fill-2026-08-15')),
        );
        final gradient =
            (fill.decoration! as BoxDecoration).gradient! as LinearGradient;
        expect(gradient.colors.first, isNot(gradient.colors.last));
        // 조회용 셀은 테마와 무관하게 밝은 채움 위에 잉크를 올린다.
        for (final color in gradient.colors) {
          final contrast =
              (color.computeLuminance() + .05) /
              (SetflowColors.ink.computeLuminance() + .05);
          expect(contrast, greaterThanOrEqualTo(4.5));
        }
        final pending = tester.widget<Ink>(
          find.byKey(const ValueKey('history-calendar-fill-2026-08-14')),
        );
        final pendingGradient =
            (pending.decoration! as BoxDecoration).gradient! as LinearGradient;
        expect(
          pendingGradient.colors.first.computeLuminance(),
          greaterThan(gradient.colors.first.computeLuminance()),
        );
        final sunday = find.descendant(
          of: find.byKey(const ValueKey('history-calendar-day-2026-08-16')),
          matching: find.text('16'),
        );
        expect(
          tester.widget<Text>(sunday).style!.color,
          dark
              ? SetflowSemanticColors.dark.error
              : SetflowSemanticColors.light.error,
        );
      },
    );
  }

  testWidgets('empty history still allows month navigation', (tester) async {
    await mount(tester, days: [], initialDate: DateTime(2026, 8));
    expect(find.textContaining('운동 0일'), findsOneWidget);
    expect(find.text('이 날짜에는 저장된 운동 기록이 없어요.'), findsOneWidget);
    await tester.tap(find.byTooltip('다음 달'));
    await tester.pumpAndSettle();
    expect(find.text('2026.09'), findsOneWidget);
  });
}
