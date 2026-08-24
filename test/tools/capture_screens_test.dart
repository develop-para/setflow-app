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
import 'package:setflow/services/auth_service.dart';

const _enabled = bool.fromEnvironment('CAPTURE');

/// 로그인 상태의 화면도 찍어야 한다 — 게스트만 찍으면 "회원" 카드, 계정 설정,
/// 소유자 있는 데이터 화면이 전부 사각이 된다.
class _SignedInAuth implements AuthService {
  const _SignedInAuth();

  @override
  AuthUser? get currentUser => const AuthUser(
    id: 'capture-user',
    email: 'qa@setflow.app',
    displayName: '김세트',
  );

  @override
  bool get hasAuthenticatedUser => true;

  @override
  String get currentDisplayName => '김세트';

  @override
  Stream<AuthChange> get authChanges => const Stream<AuthChange>.empty();

  @override
  bool isConfigured(SocialLoginProvider provider) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
  // 루트 레이어에서 장면 전체를 찍는다. 첫 RepaintBoundary를 찍는 방식은
  // 푸시된 화면에서 흰 이미지를 냈다 — 불투명한 라우트가 위에 있으면 아래
  // 라우트는 그리기가 꺼지는데, DFS의 첫 경계가 바로 그 꺼진 쪽이었다.
  final renderView = tester.binding.renderViews.first;
  final layer = renderView.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(renderView.paintBounds, pixelRatio: 2);
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

    // 푸시로 열리는 화면들 — 탭 루트만 찍으면 이쪽은 영영 안 보인다.
    await tester.tap(find.text('마이'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/mypage.png');

    await tester.tap(find.text('내 루틴'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/routines.png');

    await tester.tap(find.byKey(const ValueKey('routines-open-market')));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/market.png');

    // 전문가 루틴 상세 — 첫 카드를 연다.
    final marketCard = find.byKey(const ValueKey('market-card-0'));
    if (marketCard.evaluate().isNotEmpty) {
      await tester.tap(marketCard);
      await tester.pumpAndSettle();
      await _shot(tester, 'build/shots/market_detail.png');
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 루틴 편집기 — 카드의 편집 버튼이 여는 실제 편집 화면.
    await tester.tap(find.text('루틴 편집').first);
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/routine_editor.png');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 설정.
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/settings.png');
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 로그인 화면 — 게스트의 "로그인" 버튼이 여는 곳.
    await tester.tap(find.text('로그인').first);
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/signin.png');
    // 로그인 화면의 뒤로가기는 표준 back이 아니라 '닫기'다.
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

    // 로그인 상태의 마이 — 회원 카드가 계정으로 바뀌는 화면.
    Auth.use(const _SignedInAuth());
    addTearDown(Auth.reset);
    state.notifyListeners();
    await tester.pumpAndSettle();
    await tester.tap(find.text('마이'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/mypage_signed_in.png');

    await tester.binding.setSurfaceSize(null);
  }, skip: !_enabled);
}
