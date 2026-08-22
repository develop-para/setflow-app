import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/common.dart';

/// 토스트는 하단에 뜨면 안 된다. 하단은 엄지·기록 디스크·휴식 타이머가 이미 쓰고 있어서
/// 방금 고친 세트 행을 가린다. 이 파일은 "상단 30%"를 회귀로 잠근다.
void main() {
  const size = Size(400, 800);

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: SetflowTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => AppSnackbar.success(context, '1세트를 저장했어요.'),
                  child: const Text('저장'),
                ),
                TextButton(
                  onPressed: () => AppSnackbar.error(context, '저장하지 못했어요.'),
                  child: const Text('실패'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('토스트는 화면 상단 30% 지점에 뜬다', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    final toast = find.text('1세트를 저장했어요.');
    expect(toast, findsOneWidget);
    final top = tester.getRect(toast).top;
    expect(top, greaterThanOrEqualTo(size.height * .3));
    // 30% 지점에서 시작해 텍스트 패딩만큼만 내려온다 — 화면 절반을 넘기면 실패.
    expect(top, lessThan(size.height * .4));
  });

  testWidgets('다음 토스트가 이전 토스트를 갈아치운다', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('실패'));
    await tester.pumpAndSettle();

    expect(find.text('1세트를 저장했어요.'), findsNothing);
    expect(find.text('저장하지 못했어요.'), findsOneWidget);
  });

  testWidgets('토스트는 스스로 사라지고 타이머를 남기지 않는다', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.text('1세트를 저장했어요.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('1세트를 저장했어요.'), findsNothing);
  });

  testWidgets('탭하면 기다리지 않고 바로 닫힌다', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('1세트를 저장했어요.'));
    await tester.pumpAndSettle();
    expect(find.text('1세트를 저장했어요.'), findsNothing);
  });
}
