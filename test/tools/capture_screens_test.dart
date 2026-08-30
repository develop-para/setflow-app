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
import 'package:setflow/data/together_repository.dart';
import 'package:setflow/screens/business_screens.dart';
import 'package:setflow/screens/together_screens.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/services/auth_service.dart';
import 'package:setflow/services/location_service.dart';

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

    // 오늘 기록이 생긴 상태의 홈 — 달력 칸에 종목 이름이 들어간 모습.
    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/home_with_session.png');
    await tester.tap(find.byKey(const ValueKey('bottom-bar-center-action')));
    await tester.pumpAndSettle();

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
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/routine_editor.png');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 마이 하위 화면들.
    // 운동 목표는 설정 > 계정 & 프로필로 옮겼다 — 마이와 설정 양쪽에서 같은
    // 화면을 열던 중복을 지웠다.
    for (final (label, name) in [('코칭', 'coaching')]) {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      await _shot(tester, 'build/shots/my_$name.png');
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    // 이용권은 게스트에게 화면이 아니라 로그인 게이트를 연다 — 그 시트도
    // 사용자가 실제로 보는 화면이니 찍고, 시트의 닫기로 나온다.
    await tester.tap(find.text('이용권').first);
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/auth_gate.png');
    await tester.tap(find.byKey(const ValueKey('auth-gate-dismiss')));
    await tester.pumpAndSettle();

    // 설정과 그 하위.
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/settings.png');
    for (final (label, name) in [
      ('계정 & 프로필', 'account'),
      ('알림 설정', 'notifications'),
      ('데이터 & 개인정보', 'privacy'),
      ('운동 기록 환경설정', 'workout'),
    ]) {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      await _shot(tester, 'build/shots/settings_$name.png');
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    // 트레이너/헬스장 포털 전환("트레이너 화면 보기" 등)은 화면 push가 아니라
    // 앱 전체의 role을 바꾸는 동작이라 뒤로가기가 없다 — 이 순차 워크과 성격이
    // 달라 별도 캡처 경로로 다룬다. 설정에서 나가기만 한다.
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

    // 로그인 상태에서만 열리는 화면.
    await tester.tap(find.text('이용권').first);
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/my_membership.png');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.binding.setSurfaceSize(null);
  }, skip: !_enabled);

  // 폴드/태블릿 폭. 432 프레임을 걷어낸 뒤라, 넓은 화면이 섬이 아니라
  // 풀폭으로 그려지는지 눈으로 확인한다.
  testWidgets('capture fold width', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          const EventChannel('com.llfbandit.app_links/events'),
          MockStreamHandler.inline(onListen: (_, _) {}),
        );
    await tester.runAsync(_loadFonts);
    await tester.binding.setSurfaceSize(const Size(840, 900));
    await tester.pumpWidget(const SetflowApp());
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/fold_home.png');

    await tester.tap(find.byKey(const ValueKey('bottom-bar-center-action')));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/fold_record.png');

    // 모달 바텀시트도 섬이 아니라 풀폭인지 — M3 기본은 640 가운데다.
    await tester.tap(find.byKey(const Key('daily-load-routine')));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/fold_sheet.png');
    await tester.tapAt(const Offset(420, 80));
    await tester.pumpAndSettle();

    await tester.binding.setSurfaceSize(null);
    await tester.pump(const Duration(milliseconds: 400));
  }, skip: !_enabled);

  // 함께는 리포지토리가 있어야 로비/방이 열린다 — 메모리 백엔드를 물려서
  // 디자인 QA가 진짜 화면을 본다.
  testWidgets('capture together', (tester) async {
    await tester.runAsync(_loadFonts);
    await tester.binding.setSurfaceSize(const Size(400, 860));
    Auth.use(const _SignedInAuth());
    addTearDown(Auth.reset);
    final backend = MemoryTogetherBackend();
    addTearDown(backend.dispose);
    final repo = MemoryTogetherRepository(
      backend: backend,
      userId: 'capture-user',
      displayName: '나',
    );
    final state = AppState(togetherRepository: repo);
    await state.initialize();
    addTearDown(state.dispose);
    state.addExercise(
      state.dateOnly(DateTime.now()),
      state.exercises.firstWhere((e) => !e.isCardio),
    );

    // 다크도 찍어야 하므로 앱과 같은 테마 배선을 준다 — theme만 주면
    // toggleTheme이 아무것도 안 바꾸고 다크 캡처가 라이트로 나온다.
    Widget host() => AppScope(
      notifier: state,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: SetflowTheme.light,
        darkTheme: SetflowTheme.dark,
        themeMode: state.isDarkMode ? ThemeMode.dark : ThemeMode.light,
        home: const Scaffold(body: TogetherScreen()),
      ),
    );
    // 로비의 "근처 공개방"이 비어 보이지 않게 — 근처에 한 명이 방을 열어 둔다.
    Location.bind(const _CaptureLocation());
    addTearDown(() => Location.bind(const DisabledLocationService()));
    await MemoryTogetherRepository(
      backend: backend,
      userId: 'u-nearby',
      displayName: '민수',
    ).createParty(
      mode: PartyMode.free,
      visibility: PartyVisibility.public,
      location: const GeoPoint(37.5667, 126.9782),
    );
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/together_lobby.png');

    await tester.tap(find.byKey(const ValueKey('together-create')));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/together_create_sheet.png');
    await tester.tap(find.byKey(const ValueKey('together-create-confirm')));
    await tester.pumpAndSettle();
    // 첫 방은 화면 안내(딤 + 스포트라이트)가 먼저 뜬다. 첫 걸음과 마지막
    // 걸음(방식 설명)을 찍고 건너뛴 뒤에야 맨 방이 보인다.
    await _shot(tester, 'build/shots/together_room_guide.png');
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const ValueKey('coach-next')));
      await tester.pumpAndSettle();
    }
    await _shot(tester, 'build/shots/together_room_guide_mode.png');
    await tester.tap(find.byKey(const ValueKey('coach-next')));
    await tester.pumpAndSettle();
    await _shot(tester, 'build/shots/together_room_solo.png');

    // 친구 참가 + 세트 몇 개로 전광판 상태.
    final codeText = tester.widget<Text>(
      find.byKey(const ValueKey('together-code')),
    );
    final friend = MemoryTogetherRepository(
      backend: backend,
      userId: 'u-friend',
      displayName: '지훈',
    );
    await friend.joinParty(codeText.data!);
    await friend.reportSetDone(
      partyId: backend.partyByCode(codeText.data!)!.id,
      restSeconds: 90,
      exerciseName: '데드리프트',
      setNumber: 3,
      setTotal: 5,
      totalVolume: 540,
    );
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
    await _shot(tester, 'build/shots/together_room_race.png');

    // 방은 라이트에서 흰 판 위주라 다크에서 처음 무너지기 쉽다 — 전광판 테두리,
    // 하단 액션 바의 구분선, 고정 바의 배경이 검은 판에서 살아 있는지 본다.
    state.toggleTheme();
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    // 테마를 갈아끼운 직후 바로 찍으면 이전 트리의 잔상이 한 겹 남는다.
    await tester.pump(const Duration(milliseconds: 300));
    await _shot(tester, 'build/shots/dark_together_room.png');
    state.toggleTheme();
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    state.cancelRestTimer();
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(null);
    await tester.pump(const Duration(milliseconds: 400));
  }, skip: !_enabled);

  // 트레이너/헬스장/관리자 포털. role 전환은 셸 교체라 pageBack 워크과 성격이
  // 달라서, 포털 셸을 직접 띄우고 탭만 순회한다.
  testWidgets('capture business portals', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          const EventChannel('com.llfbandit.app_links/events'),
          MockStreamHandler.inline(onListen: (_, _) {}),
        );
    await tester.runAsync(_loadFonts);
    await tester.binding.setSurfaceSize(const Size(400, 860));

    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);

    Future<void> portal(UserRole role, String name, List<String> tabs) async {
      state.chooseRole(role, enforceAccess: false);
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: SetflowTheme.light,
            // 키가 없으면 이전 역할의 셸 상태(탭 인덱스)가 재사용된다.
            home: BusinessShell(key: ValueKey(role), role: role),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _shot(tester, 'build/shots/${name}_home.png');
      for (final (i, tab) in tabs.indexed) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        await _shot(tester, 'build/shots/${name}_tab${i + 1}.png');
      }
    }

    await portal(UserRole.trainer, 'trainer', ['회원', '루틴', '상담']);
    await portal(UserRole.gym, 'gym', ['회원', '운영', '정산']);
    await portal(UserRole.admin, 'admin', ['유저', '루틴', '심사', '정산']);

    await tester.binding.setSurfaceSize(null);
    await tester.pump(const Duration(milliseconds: 400));
  }, skip: !_enabled);
}

/// 캡처용 위치 — 서울시청 앞에 서 있다.
class _CaptureLocation implements LocationService {
  const _CaptureLocation();

  @override
  bool get isAvailable => true;

  @override
  Future<bool> isGranted() async => true;

  @override
  Future<LocationResult> current() async =>
      const LocationFix(GeoPoint(37.5665, 126.9780));

  @override
  Future<void> openSettings() async {}
}
