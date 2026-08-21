// Design QA: renders live screens to PNGs under build/shots so a re-skin can
// be eyeballed without a device or a browser. Skipped by a normal test run.
//   flutter test test/tools/capture_screens_test.dart --dart-define=CAPTURE=true
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/main.dart';

const _enabled = bool.fromEnvironment('CAPTURE');

Future<void> _loadFonts() async {
  final loader = FontLoader('Pretendard');
  for (final name in const [
    'Pretendard-Regular',
    'Pretendard-Medium',
    'Pretendard-SemiBold',
    'Pretendard-Bold',
    'Pretendard-ExtraBold',
    'Pretendard-Black',
  ]) {
    loader.addFont(
      File('assets/fonts/$name.otf').readAsBytes().then(
        (bytes) => ByteData.view(Uint8List.fromList(bytes).buffer),
      ),
    );
  }
  await loader.load();

  // Without this every icon captures as a filled box: the test runtime ships
  // no MaterialIcons, so it has to come from the SDK cache.
  // resolvedExecutable points deep inside bin/cache, so walk up to the SDK
  // root by looking for the marker directory rather than counting parents.
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.parent.path != dir.path &&
      !Directory(
        '${dir.path}/bin/cache/artifacts/material_fonts',
      ).existsSync()) {
    dir = dir.parent;
  }
  final iconFont = File(
    '${dir.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (iconFont.existsSync()) {
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        iconFont.readAsBytes().then(
          (bytes) => ByteData.view(Uint8List.fromList(bytes).buffer),
        ),
      );
    await icons.load();
  } else {
    // ignore: avoid_print
    print('WARNING: MaterialIcons not found at ${iconFont.path}');
  }
}

Future<void> _shot(WidgetTester tester, String out) async {
  final boundary = tester.binding.rootElement!.findRenderObject()!;
  RenderRepaintBoundary? repaint;
  void visit(RenderObject node) {
    if (repaint != null) return;
    if (node is RenderRepaintBoundary) {
      repaint = node;
      return;
    }
    node.visitChildren(visit);
  }

  visit(boundary);
  await tester.runAsync(() async {
    final image = await repaint!.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(out);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('capture', (tester) async {
    await tester.runAsync(_loadFonts);
    await tester.binding.setSurfaceSize(const Size(400, 860));
    await tester.pumpWidget(const SetflowApp());
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/home.png');

    await tester.tap(find.byKey(const ValueKey('bottom-bar-center-action')));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/record.png');

    await tester.tap(find.byKey(const ValueKey('bottom-bar-center-action')));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/record_sheet.png');

    await tester.tap(find.text('마이'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/mypage.png');

    await tester.tap(find.text('통계'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/stats.png');

    await tester.binding.setSurfaceSize(null);
  }, skip: !_enabled);
}
