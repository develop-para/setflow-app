import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/main.dart';
import 'package:setflow/screens/member_screens.dart';

/// 폭에 대한 계약은 하나다: **셸과 그 위에 밀린 라우트의 폭이 같아야 한다.**
/// 이 테스트가 태어난 버그가 그 폭 점프였다 — 셸은 432, 루틴 편집기는 1400.
///
/// 한때는 432px 폰 프레임으로 고정해 그 계약을 지켰지만, 폴드·태블릿에서
/// 콘텐츠가 좌우 여백에 뜬 섬으로 보인다는 실기기 피드백으로 프레임을
/// 걷어냈다. 지금의 계약: 어떤 기기든 **화면 폭을 그대로** 쓰고, 밀린
/// 라우트도 같은 폭이다.
void main() {
  const desktop = Size(1400, 900);

  Future<void> launch(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(desktop);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const SetflowApp());
    // The splash runs an explicit timer; pumpAndSettle alone would race it.
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();
  }

  testWidgets('a route pushed over the shell keeps the shell width', (
    tester,
  ) async {
    await launch(tester);

    final home = tester.getSize(find.byType(MemberShell)).width;
    expect(home, desktop.width, reason: '셸이 화면 폭을 다 쓰지 않는다');

    // Push the way every real screen does — onto the root navigator, above
    // `home:`. This is the exact mechanism that used to escape the frame.
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(
            key: ValueKey('pushed-probe'),
            body: SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pushed = tester
        .getSize(find.byKey(const ValueKey('pushed-probe')))
        .width;
    expect(
      pushed,
      home,
      reason: 'a pushed route must not be wider than the shell it covers',
    );
  });

  testWidgets('a phone-sized viewport is not letterboxed', (tester) async {
    // The frame is a cap, not a fixed width: on a real phone it must not leave
    // grey gutters down the sides.
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const SetflowApp());
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(MemberShell)).width, 390.0);
  });
}

/// Pushing returns a future that only completes on pop; awaiting it would hang.
void unawaited(Future<void> future) {}
