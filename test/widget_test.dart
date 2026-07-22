import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/main.dart';

void main() {
  testWidgets('shows role selection on launch', (tester) async {
    await tester.pumpWidget(const SetflowApp());
    await tester.pumpAndSettle();

    expect(find.text('Setflow'), findsOneWidget);
    expect(find.text('일반 회원'), findsOneWidget);
    expect(find.text('트레이너'), findsOneWidget);
    expect(find.text('헬스장 / 센터장'), findsOneWidget);
  });
}
