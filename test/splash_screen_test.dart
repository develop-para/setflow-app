import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/screens/splash_screen.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/brand.dart';

void main() {
  testWidgets('loading screen shows the wordmark, not a logo image', (
    tester,
  ) async {
    var finished = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: SetflowTheme.light,
        home: SplashScreen(onFinished: () => finished = true),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('setflow-loading-logo')),
      findsOneWidget,
    );
    expect(find.byType(SetflowWordmark), findsOneWidget);
    // The drawn mark and its tinted tile are gone for good.
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.rocket_launch_rounded), findsNothing);

    await tester.pump(const Duration(milliseconds: 1800));
    expect(finished, isTrue);
  });
}
