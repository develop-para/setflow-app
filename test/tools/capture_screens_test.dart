// Design QA: renders live screens to PNGs under build/shots so a re-skin can
// be eyeballed without a device or a browser. Skipped by a normal test run.
//   flutter test test/tools/capture_screens_test.dart --dart-define=CAPTURE=true
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
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
    // 딥링크 플러그인은 테스트 런타임에 구현이 없다. 앱이 시작하자마자
    // 스트림을 열기 때문에, 막아 두지 않으면 첫 프레임에서 터진다.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          const EventChannel('com.llfbandit.app_links/events'),
          MockStreamHandler.inline(onListen: (_, _) {}),
        );
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

    // 세트 행이 이 앱의 본체다. 빈 화면만 찍으면 정작 사람이 제일 오래 보는
    // 화면을 한 번도 안 보고 넘어간다.
    // 시트를 닫고 찍는다 — 막 위로 찍으면 정작 볼 것이 흐려진다.
    await tester.tap(find.byKey(const ValueKey('bottom-bar-center-action')));
    await tester.pumpAndSettle();
    final seedState = tester.widget<AppScope>(find.byType(AppScope)).notifier!;
    final today = seedState.dateOnly(DateTime.now());
    for (final template
        in seedState.exercises.where((e) => !e.isCardio).take(2)) {
      seedState.addExercise(today, template);
    }
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/record_sets.png');

    await tester.tap(find.text('마이'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/mypage.png');

    await tester.tap(find.text('커뮤니티'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/community.png');

    await tester.tap(find.text('함께'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/together.png');

    // 다크는 눈으로 보지 않으면 절대 안 보인다 — 라이트에서 멀쩡한 대비가 검은
    // 판 위에서 무너지는 것이 이 앱이 반복해서 겪은 일이다. 설정 화면을 거치는
    // 대신 상태를 직접 뒤집는다: 캡처는 QA 도구지 흐름 테스트가 아니다.
    // 위젯에서 바로 꺼낸다. AppScope.of는 build 중에 부르는 API고, 여기는
    // 테스트 본문이라 의존성 등록 경로를 타지 않는다.
    final state = tester.widget<AppScope>(find.byType(AppScope)).notifier!;
    state.toggleTheme();
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/dark_together.png');

    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/dark_home.png');

    await tester.tap(find.byKey(const ValueKey('bottom-bar-center-action')));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/dark_record.png');

    state.toggleTheme();
    await tester.binding.setSurfaceSize(null);
  }, skip: !_enabled);
}
