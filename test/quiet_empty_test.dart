import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/common.dart';

/// Nothing should be drawn loudly.
///
/// A grey plate behind a grey icon, or a column of grey boxes down the side of
/// an empty month, reads as a screen that has not finished loading. Both were
/// on the first two screens of the app, so the first impression of a fresh
/// account was "this is broken" rather than "there is nothing here yet".
///
/// The rule the app already applies to calendar days — an empty day is blank —
/// is the same one; these are the two places it had not reached.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 초기화가 걸어 둔 저장 타이머가 위젯 트리보다 오래 산다.
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('an empty state puts nothing behind its icon', (tester) async {
    await pump(
      tester,
      const EmptyState(
        icon: Icons.fitness_center_rounded,
        title: '아직 없어요',
        message: '먼저 하나 만들어보세요.',
      ),
    );

    final icon = find.byIcon(Icons.fitness_center_rounded);
    expect(icon, findsOneWidget);

    // 아이콘을 감싼 조상 중에 칠해진 상자가 있으면 안 된다.
    final painted = find
        .ancestor(of: icon, matching: find.byType(DecoratedBox))
        .evaluate()
        .map((e) => (e.widget as DecoratedBox).decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.color != null && d.color!.a > 0)
        .toList();
    expect(painted, isEmpty, reason: '아이콘 뒤에 판이 깔려 있다');
  });

  testWidgets('an empty month is a quiet grid, not a stack of loud boxes', (
    tester,
  ) async {
    await pump(tester, const CalendarScreen());

    // 빈 날에도 옅은 상자는 깐다(제품 결정). 하지만 기록이 있어야만 갖는
    // 진한 채움(surfaceContainer)이 빈 달에 나타나면, 위계가 무너져 어느
    // 날 운동했는지 상자만으로는 알 수 없게 된다.
    final loud = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where(
          (d) =>
              d.color == SetflowSemanticColors.light.surfaceContainer &&
              d.borderRadius != null,
        )
        .toList();
    expect(loud, isEmpty, reason: '기록 없는 달에 기록 있는 날의 채움이 나타났다');

    expect(find.textContaining('기록이 아직 없어요'), findsOneWidget);
  });
}
