// Brand asset generator — renders the SetflowMark widget (the single source
// of truth for the Rep Stack glyph) into the PNG files consumed by
// flutter_launcher_icons and flutter_native_splash.
//
// Normal `flutter test` runs skip this file; regenerate assets with:
//   flutter test test/tools/generate_brand_assets_test.dart --dart-define=GEN_BRAND_ASSETS=true
// then:
//   dart run flutter_launcher_icons
//   dart run flutter_native_splash:create
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:setflow/theme.dart';
import 'package:setflow/widgets/brand.dart';

const _enabled = bool.fromEnvironment('GEN_BRAND_ASSETS');

Future<void> _capture(
  WidgetTester tester, {
  required Widget child,
  required double canvasSize,
  required String outPath,
}) async {
  final key = GlobalKey();
  await tester.binding.setSurfaceSize(Size.square(canvasSize));
  tester.view.physicalSize = Size.square(canvasSize);
  tester.view.devicePixelRatio = 1.0;

  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: Center(child: child),
    ),
  );

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(outPath);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('generate launcher icon + splash PNGs from SetflowMark', (
    tester,
  ) async {
    await _capture(
      tester,
      child: const SetflowMark(
        size: 1024,
        background: SetflowColors.primary,
        color: SetflowColors.ink,
        radius: 0,
      ),
      canvasSize: 1024,
      outPath: 'assets/icon/icon_full.png',
    );

    await _capture(
      tester,
      child: const SetflowMark(size: 820, color: SetflowColors.ink),
      canvasSize: 1024,
      outPath: 'assets/icon/icon_fg.png',
    );

    await _capture(
      tester,
      child: SetflowMark(
        size: 768,
        background: SetflowColors.primary,
        color: SetflowColors.ink,
        radius: 768 * (28 / 96),
      ),
      canvasSize: 768,
      outPath: 'assets/splash/logo.png',
    );

    await _capture(
      tester,
      child: SetflowMark(
        size: 512,
        background: SetflowColors.primary,
        color: SetflowColors.ink,
        radius: 512 * (28 / 96),
      ),
      canvasSize: 1152,
      outPath: 'assets/splash/logo_android12.png',
    );

    // Flutter's native icon generator does not touch PWA assets, so keep the
    // installable web app and favicon on the same brand mark here.
    for (final size in const [192.0, 512.0]) {
      await _capture(
        tester,
        child: SetflowMark(
          size: size,
          background: SetflowColors.primary,
          color: SetflowColors.ink,
          radius: 0,
        ),
        canvasSize: size,
        outPath: 'web/icons/Icon-${size.toInt()}.png',
      );
      await _capture(
        tester,
        child: SetflowMark(
          size: size,
          background: SetflowColors.primary,
          color: SetflowColors.ink,
          radius: 0,
        ),
        canvasSize: size,
        outPath: 'web/icons/Icon-maskable-${size.toInt()}.png',
      );
    }

    await _capture(
      tester,
      child: const SetflowMark(
        size: 48,
        background: SetflowColors.primary,
        color: SetflowColors.ink,
        radius: 0,
      ),
      canvasSize: 48,
      outPath: 'web/favicon.png',
    );

    await tester.binding.setSurfaceSize(null);
  }, skip: !_enabled);
}
