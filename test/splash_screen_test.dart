import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/screens/splash_screen.dart';
import 'package:setflow/theme.dart';

void main() {
  testWidgets('loading screen shows the Setflow barbell mark', (tester) async {
    var finished = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: SetflowTheme.light,
        home: SplashScreen(onFinished: () => finished = true),
      ),
    );

    final logoFinder = find.byKey(
      const ValueKey<String>('setflow-loading-logo'),
    );
    expect(logoFinder, findsOneWidget);
    expect(find.byIcon(Icons.rocket_launch_rounded), findsNothing);

    final logo = tester.widget<Image>(logoFinder);
    expect(
      (logo.image as AssetImage).assetName,
      'assets/branding/setflow_mark.png',
    );

    await tester.pump(const Duration(milliseconds: 1800));
    expect(finished, isTrue);
  });
}
