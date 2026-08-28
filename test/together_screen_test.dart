import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/together_repository.dart';
import 'package:setflow/main.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/screens/together_screens.dart';
import 'package:setflow/services/auth_service.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/bottom_bar.dart';
import 'package:setflow/widgets/common.dart';

void main() {
  late MemoryTogetherBackend backend;

  setUp(() {
    backend = MemoryTogetherBackend();
    // 함께 is gated on having an account — a room cannot say whose turn it is
    // otherwise — so every test here signs in first.
    Auth.use(_SignedInAuth());
  });

  tearDown(() {
    backend.dispose();
    Auth.reset();
  });

  MemoryTogetherRepository client(String id, String name) =>
      MemoryTogetherRepository(backend: backend, userId: id, displayName: name);

  Future<AppState> pumpTogether(
    WidgetTester tester, {
    TogetherRepository? repository,
    bool guideSeen = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(432, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState(togetherRepository: repository);
    await state.initialize();
    addTearDown(state.dispose);
    // 첫 방에서는 화면 안내(코치마크)가 딤을 깔고 뜬다. 방을 다루는 테스트는
    // 이미 본 사람의 눈으로 본다 — 안내 자체는 'the guide' 그룹이 본다.
    if (guideSeen) state.markTogetherGuideSeen();
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: const TogetherScreen(),
        ),
      ),
    );
    // initialize() arms AppState's 250ms persist debounce. A screen with no
    // animation settles instantly and would leave that timer pending.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    return state;
  }

  group('the bar', () {
    testWidgets('통계 is gone and 함께 took its slot', (tester) async {
      await tester.binding.setSurfaceSize(const Size(432, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const SetflowApp());
      await tester.pump(const Duration(milliseconds: 1900));
      await tester.pumpAndSettle();

      final bar = tester.widget<SetflowActionNavBar>(
        find.byType(SetflowActionNavBar),
      );
      expect(bar.items.map((item) => item.label).toList(), [
        '홈',
        '함께',
        '커뮤니티',
        '마이',
      ]);
    });

    testWidgets('the slot opens 함께', (tester) async {
      await tester.binding.setSurfaceSize(const Size(432, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const SetflowApp());
      await tester.pump(const Duration(milliseconds: 1900));
      await tester.pumpAndSettle();

      await tester.tap(find.text('함께').last);
      await tester.pumpAndSettle();

      expect(find.byType(TogetherScreen), findsOneWidget);
    });

    testWidgets('방에 들어가면 바가 접히고, 나오면 돌아온다', (tester) async {
      // 방은 운동 중 전용 화면이다. 전광판과 하단 액션이 화면을 다 쓰려면
      // 셸의 헤더와 바텀바가 비켜야 한다 — 대신 나갈 길이 사라지면 안 되므로
      // 방을 나가는 순간 되돌아와야 한다.
      await tester.binding.setSurfaceSize(const Size(432, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final state = AppState(togetherRepository: client('u-me', '나'));
      await state.initialize();
      addTearDown(state.dispose);
      // 첫 방의 화면 안내는 여기 관심사가 아니다 — 딤이 메뉴 탭을 삼킨다.
      state.markTogetherGuideSeen();
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: MaterialApp(
            theme: SetflowTheme.light,
            home: const MemberShell(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      await tester.tap(find.text('함께').last);
      await tester.pumpAndSettle();
      expect(find.byType(SetflowActionNavBar), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('together-create')));
      await tester.pumpAndSettle();
      expect(
        find.byType(SetflowActionNavBar),
        findsNothing,
        reason: '방 안에서는 바가 접힌다',
      );

      await tester.tap(find.byKey(const ValueKey('together-room-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('방 나가기'));
      await tester.pumpAndSettle();
      expect(
        find.byType(SetflowActionNavBar),
        findsOneWidget,
        reason: '방을 나가면 나갈 길이 돌아와야 한다',
      );
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('the stats screen still exists, it is only unlisted', (
      tester,
    ) async {
      // "나중에 쓸 건데 메뉴에서만 빼 달라" — deleting the screen would make
      // putting it back a rebuild instead of a one-line nav change.
      expect(const DashboardScreen(), isA<Widget>());
    });
  });

  group('the lobby', () {
    testWidgets('a build with no partner server says so plainly', (
      tester,
    ) async {
      await pumpTogether(tester);

      expect(
        find.byKey(const ValueKey('together-unavailable')),
        findsOneWidget,
      );
    });

    testWidgets('creating a room shows the code to read out', (tester) async {
      await pumpTogether(tester, repository: client('u-me', '나'));

      await tester.tap(find.byKey(const ValueKey('together-create')));
      await tester.pumpAndSettle();

      // 혼자 있는 방은 본문이 통째로 초대 화면이다 — 코드가 거기 있다.
      final code = tester.widget<Text>(
        find.byKey(const ValueKey('together-code')),
      );
      expect(code.data, hasLength(6));
      expect(find.text('친구를 초대하세요'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('a bad code reports back instead of opening a room', (
      tester,
    ) async {
      await pumpTogether(tester, repository: client('u-me', '나'));

      await tester.tap(find.byKey(const ValueKey('together-join')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('together-code-input')),
        'ZZZZZZ',
      );
      await tester.tap(find.byKey(const ValueKey('together-code-submit')));
      await tester.pumpAndSettle();

      expect(find.textContaining('그런 코드의 방이 없어요'), findsOneWidget);
      expect(find.byKey(const ValueKey('together-code')), findsNothing);
    });
  });

  group('the lobby', () {
    testWidgets('the how-to lives behind the question mark, not on the page', (
      tester,
    ) async {
      await pumpTogether(tester, repository: client('u-me', '나'));

      // 페이지에는 설명이 늘어서 있지 않다 — 행동 둘과 그림 하나뿐.
      expect(find.text('방을 만들고 코드를 공유해요'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('together-help')));
      await tester.pumpAndSettle();
      expect(find.text('함께 운동 사용법'), findsOneWidget);
      expect(find.text('방을 만들고 코드를 공유해요'), findsOneWidget);
      expect(find.textContaining('최대 6명'), findsOneWidget);
    });
  });

  group('the room comes back', () {
    testWidgets('reopening the tab returns to the remembered room', (
      tester,
    ) async {
      // "방을 만들고 같이 쓰는 중인데 로비의 방 만들기가 보인다" — 복원이
      // 없어서 앱을 껐다 켜면 방을 잃던 문제의 잠금.
      final repo = client('u-me', '나');
      final state = await pumpTogether(tester, repository: repo);
      await tester.tap(find.byKey(const ValueKey('together-create')));
      await tester.pumpAndSettle();
      expect(state.activeTrainingPartyId, isNotNull);

      // 화면을 통째로 버리고(앱 재시작에 해당) 같은 상태로 다시 띄운다.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: MaterialApp(
            theme: SetflowTheme.light,
            home: const TogetherScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 로비의 방 만들기가 아니라 방이 보인다.
      expect(find.byKey(const ValueKey('together-create')), findsNothing);
      expect(find.byKey(const ValueKey('together-code')), findsOneWidget);
      state.cancelRestTimer();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('a dead room is forgotten instead of restored', (tester) async {
      final repo = client('u-me', '나');
      final state = await pumpTogether(tester, repository: repo);
      state.setActiveTrainingParty('no-such-party');

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: MaterialApp(
            theme: SetflowTheme.light,
            home: const TogetherScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('together-create')), findsOneWidget);
      expect(state.activeTrainingPartyId, isNull);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('the room', () {
    Future<TrainingParty> seatTwo(PartyMode mode) async {
      final host = client('u-me', '나');
      final party = await host.createParty(mode: mode);
      await client('u-friend', '친구').joinParty(party.code);
      return backend.partyById(party.id)!;
    }

    testWidgets('a partner finishing a set starts my rest', (tester) async {
      final room = await seatTwo(PartyMode.together);
      final state = await pumpTogether(tester, repository: client('u-me', '나'));
      await tester.tap(find.byKey(const ValueKey('together-join')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('together-code-input')),
        room.code,
      );
      await tester.tap(find.byKey(const ValueKey('together-code-submit')));
      await tester.pumpAndSettle();

      expect(state.restRemaining, 0);

      // The partner's phone reports the set. Nothing on this device was
      // touched — which is exactly the moment "같이 쉰다" has to become real.
      await client(
        'u-friend',
        '친구',
      ).reportSetDone(partyId: room.id, restSeconds: 60);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        state.restRemaining,
        greaterThan(0),
        reason: 'the shared rest has to drive the same timer a solo rest does',
      );
      state.cancelRestTimer();
    });

    testWidgets("각자 mode: a partner's set never starts my rest", (
      tester,
    ) async {
      // 떨어져서 각자 헬스장에 있을 때의 모드 — 기구 대기·다른 종목 때문에
      // 같은 시계로 묶을 수 없다는 피드백에서 나왔다. 상대의 세트는 전광판만
      // 움직이고, 내 타이머는 내 것이다.
      final room = await seatTwo(PartyMode.free);
      final state = await pumpTogether(tester, repository: client('u-me', '나'));
      await tester.tap(find.byKey(const ValueKey('together-join')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('together-code-input')),
        room.code,
      );
      await tester.tap(find.byKey(const ValueKey('together-code-submit')));
      await tester.pumpAndSettle();

      // 각자 모드에는 같이 시작 신호가 없다.
      expect(find.byKey(const ValueKey('together-start')), findsNothing);

      await client('u-friend', '친구').reportSetDone(
        partyId: room.id,
        restSeconds: 60,
        exerciseName: '스쿼트',
        setNumber: 1,
        setTotal: 5,
        totalVolume: 100,
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(state.restRemaining, 0, reason: '각자 모드에서 상대 세트가 내 휴식을 시작시켰다');
      // 전광판에는 올라간다.
      expect(find.text('스쿼트 · 1/5세트'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('교대 refuses a set that is not my turn', (tester) async {
      final room = await seatTwo(PartyMode.alternating);
      // The friend created nothing; the host is 'u-me', so after starting it
      // is the host's turn and the friend's button must be inert.
      await client('u-me', '나').startTogether(room.id);

      final state = await pumpTogether(
        tester,
        repository: client('u-friend', '친구'),
      );
      final today = state.dateOnly(DateTime.now());
      state.addExercise(today, state.exercises.firstWhere((e) => !e.isCardio));
      await tester.tap(find.byKey(const ValueKey('together-join')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('together-code-input')),
        room.code,
      );
      await tester.tap(find.byKey(const ValueKey('together-code-submit')));
      await tester.pumpAndSettle();

      final button = tester.widget<AppButton>(
        find.byKey(const ValueKey('together-set-done')),
      );
      expect(button.onPressed, isNull);
      // 누구 차례인지 이름으로 말한다 — "상대"는 익명이라 애매했다.
      expect(find.text('나님 차례예요'), findsOneWidget);
    });

    testWidgets("세트 끝냈어요 logs the set in today's record, not just the room", (
      tester,
    ) async {
      // 방의 버튼이 신호에 그치면 같은 세트를 기록 탭에서 한 번 더 밀어야
      // 한다 — 실기기 피드백("어떤 세트를 하는지 보여야 하는 것 아닌가")의
      // 핵심이 이 연결이다.
      final state = await pumpTogether(tester, repository: client('u-me', '나'));
      final today = state.dateOnly(DateTime.now());
      state.addExercise(today, state.exercises.firstWhere((e) => !e.isCardio));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('together-create')));
      await tester.pumpAndSettle();

      // 방이 오늘 기록의 차례 세트를 보여준다.
      expect(find.byKey(const ValueKey('together-live-set')), findsOneWidget);
      expect(find.text('1세트 끝냈어요'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('together-set-done')),
      );
      await tester.tap(find.byKey(const ValueKey('together-set-done')));
      await tester.pumpAndSettle();

      final session = state.sessions[today]!;
      expect(
        session.exercises.first.sets.first.completed,
        isTrue,
        reason: '방에서 끝낸 세트가 오늘 기록에 남지 않았다',
      );
      // 다음 차례 세트로 넘어간 것도 화면에 보인다.
      expect(find.text('2세트 끝냈어요'), findsOneWidget);
      state.cancelRestTimer();
    });

    testWidgets('the room edits the set through the same dial as the record', (
      tester,
    ) async {
      // 방에서 무게를 고치러 기록 탭으로 왔다 갔다 하는 것이 실기기 불만이었다.
      // 방의 숫자 상자가 기록과 같은 다이얼 시트를 열고, 적용이 오늘 기록의
      // 그 세트에 저장돼야 한다.
      final state = await pumpTogether(tester, repository: client('u-me', '나'));
      final today = state.dateOnly(DateTime.now());
      state.addExercise(today, state.exercises.firstWhere((e) => !e.isCardio));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('together-create')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('together-dial-weight')));
      await tester.pumpAndSettle();
      // 기록과 같은 시트: 숫자를 입력하고 적용이 유일한 저장 지점이다.
      await tester.enterText(find.byType(TextField).last, '80');
      await tester.tap(find.text('적용'));
      await tester.pumpAndSettle();

      final set = state.sessions[today]!.exercises.first.sets.first;
      expect(set.weight, 80, reason: '방의 다이얼 적용이 오늘 기록의 세트에 저장되지 않았다');
      // 칩은 값+단위를 한 Text.rich("80kg")로 그린다.
      expect(find.text('80kg', findRichText: true), findsWidgets);
    });

    testWidgets(
      'an empty day points at the record tab instead of a bare button',
      (tester) async {
        await pumpTogether(tester, repository: client('u-me', '나'));
        await tester.tap(find.byKey(const ValueKey('together-create')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('together-live-set-empty')),
          findsOneWidget,
        );
        expect(find.text('오늘 기록에 운동이 없어요'), findsOneWidget);
        // 끝낼 세트가 없는데 "세트 끝냈어요"가 있으면 안 된다 — 실기기 피드백.
        expect(find.byKey(const ValueKey('together-set-done')), findsNothing);
        expect(
          find.byKey(const ValueKey('together-add-workout')),
          findsOneWidget,
        );
        await tester.pump(const Duration(milliseconds: 400));
      },
    );

    testWidgets('the hero always answers "what do I do now"', (tester) async {
      // "기능은 있는데 뭘 해야 할지 모르겠다"던 피드백의 잠금 — 방 맨 위에는
      // 언제나 지금 할 일 한 문장이 있어야 한다.
      final state = await pumpTogether(tester, repository: client('u-me', '나'));
      await tester.tap(find.byKey(const ValueKey('together-create')));
      await tester.pumpAndSettle();

      // 혼자: 초대가 할 일이다.
      expect(
        find.byKey(const ValueKey('together-status-hero')),
        findsOneWidget,
      );
      expect(find.text('친구를 초대하세요'), findsOneWidget);

      // 친구가 들어오면: 시작이 할 일이다. 코드는 화면의 코드 카드에서 읽는다.
      final codeText = tester.widget<Text>(
        find.byKey(const ValueKey('together-code')),
      );
      await client('u-friend', '친구').joinParty(codeText.data!);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.text('준비되면 같이 시작'), findsOneWidget);
      state.cancelRestTimer();
    });

    testWidgets('the scoreboard shows how far the partner has gone', (
      tester,
    ) async {
      // "친구가 어디까지 했는지 전광판처럼" — 상대의 세트 보고가 순위·종목·
      // 진행으로 내 화면에 나타나야 한다.
      final room = await seatTwo(PartyMode.together);
      final state = await pumpTogether(tester, repository: client('u-me', '나'));
      await tester.tap(find.byKey(const ValueKey('together-join')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('together-code-input')),
        room.code,
      );
      await tester.tap(find.byKey(const ValueKey('together-code-submit')));
      await tester.pumpAndSettle();

      await client('u-friend', '친구').reportSetDone(
        partyId: room.id,
        restSeconds: 60,
        exerciseName: '데드리프트',
        setNumber: 2,
        setTotal: 5,
        totalVolume: 360,
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // 상대 줄: 1위 배지 + 무슨 종목의 몇 세트째인지 + 볼륨.
      expect(find.text('1위'), findsOneWidget);
      expect(find.text('데드리프트 · 2/5세트'), findsOneWidget);
      expect(find.textContaining('360kg', findRichText: true), findsWidgets);
      // 격차 응원 줄 — 내가 쫓는 쪽이다.
      expect(find.textContaining('따라잡아요'), findsOneWidget);
      state.cancelRestTimer();
    });

    test('a seventh member is refused — the room caps at six', () async {
      final host = client('u-1', '1번');
      final party = await host.createParty(mode: PartyMode.together);
      for (var i = 2; i <= 6; i++) {
        await client('u-$i', '$i번').joinParty(party.code);
      }
      expect(backend.partyById(party.id)!.members, hasLength(6));

      await expectLater(
        client('u-7', '7번').joinParty(party.code),
        throwsA(
          isA<TogetherFailure>().having(
            (f) => f.message,
            'message',
            contains('최대 6명'),
          ),
        ),
      );
      // 이미 들어와 있는 사람의 재입장은 정원과 무관하다.
      final rejoined = await client('u-3', '3번').joinParty(party.code);
      expect(rejoined.members, hasLength(6));
    });

    testWidgets('leaving puts me back in the lobby', (tester) async {
      await pumpTogether(tester, repository: client('u-me', '나'));
      await tester.tap(find.byKey(const ValueKey('together-create')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('together-code')), findsOneWidget);

      // 나가기는 늘 보일 필요가 없어 방 메뉴 뒤로 갔다.
      await tester.tap(find.byKey(const ValueKey('together-room-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('방 나가기'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('together-create')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('the guide', () {
    testWidgets('the first room dims the screen and walks the buttons once', (
      tester,
    ) async {
      final state = await pumpTogether(
        tester,
        repository: client('u-me', '나'),
        guideSeen: false,
      );
      await tester.tap(find.byKey(const ValueKey('together-create')));
      await tester.pumpAndSettle();

      // 혼자인 방: 첫 걸음은 초대 코드다.
      expect(find.byKey(const ValueKey('coach-dim')), findsOneWidget);
      expect(find.text('먼저 친구를 초대하세요'), findsOneWidget);
      expect(state.hasSeenTogetherGuide, isFalse);

      // 게임처럼 딤 아무 데나 눌러도 넘어간다.
      await tester.tapAt(const Offset(20, 700));
      await tester.pumpAndSettle();
      expect(find.text('지금 할 일은 이 한 줄'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('coach-next')));
      await tester.pumpAndSettle();
      expect(find.text('세트를 끝내면 여기서'), findsOneWidget);

      // 마지막 걸음은 방식 설명 — "교대가 뭔지 모르겠다"의 답이 여기 있다.
      await tester.tap(find.byKey(const ValueKey('coach-next')));
      await tester.pumpAndSettle();
      expect(find.text('지금 방식은 "같이"'), findsOneWidget);
      expect(find.byKey(const ValueKey('coach-skip')), findsNothing);
      expect(find.text('시작하기'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('coach-next')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('coach-dim')), findsNothing);
      expect(state.hasSeenTogetherGuide, isTrue);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('skipping counts as seen, and the menu brings it back', (
      tester,
    ) async {
      final state = await pumpTogether(
        tester,
        repository: client('u-me', '나'),
        guideSeen: false,
      );
      await tester.tap(find.byKey(const ValueKey('together-create')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('coach-skip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('coach-dim')), findsNothing);
      expect(state.hasSeenTogetherGuide, isTrue);

      await tester.tap(find.byKey(const ValueKey('together-room-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('사용법'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('coach-dim')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('coach-skip')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('a room already seen opens without the dim', (tester) async {
      await pumpTogether(tester, repository: client('u-me', '나'));
      await tester.tap(find.byKey(const ValueKey('together-create')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('coach-dim')), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('a room already underway never dims the newcomer', (
      tester,
    ) async {
      // 운동 중 화면에 끼어드는 설명은 불편이다. 친구가 이미 세트를 오가는
      // 방에 들어온 사람은 지금 당장 들어야 한다 — 안내는 메뉴로 미룬다.
      final host = client('u-me', '나');
      final room = await host.createParty(mode: PartyMode.free);
      await host.reportSetDone(partyId: room.id, restSeconds: 60);

      await pumpTogether(
        tester,
        repository: client('u-friend', '친구'),
        guideSeen: false,
      );
      await tester.tap(find.byKey(const ValueKey('together-join')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('together-code-input')),
        room.code,
      );
      await tester.tap(find.byKey(const ValueKey('together-code-submit')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('together-status-hero')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('coach-dim')), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    });

    test('every mode says how it runs and when to pick it', () {
      for (final mode in PartyMode.values) {
        expect(mode.detail, isNotEmpty);
        expect(mode.when, isNotEmpty);
      }
      expect(PartyMode.alternating.detail, contains('번갈아'));
    });
  });
}

/// Signed in, and nothing else. 함께 only ever asks whether there is an account.
class _SignedInAuth implements AuthService {
  @override
  AuthUser? get currentUser =>
      const AuthUser(id: 'u-me', email: 'me@example.com', displayName: '나');

  @override
  bool get hasAuthenticatedUser => true;

  @override
  String get currentDisplayName => '나';

  @override
  Stream<AuthChange> get authChanges => const Stream<AuthChange>.empty();

  @override
  bool isConfigured(SocialLoginProvider provider) => false;

  @override
  Future<AuthSignUpResult> signUp({
    required String email,
    required String password,
    required String nickname,
  }) async => const AuthSignUpResult(signedIn: true);

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<bool> signInWithSocial(SocialLoginProvider provider) async => false;

  @override
  Future<void> sendPasswordReset({required String email}) async {}

  @override
  Future<void> resendConfirmationEmail({required String email}) async {}

  @override
  Future<void> updatePassword({required String newPassword}) async {}

  @override
  Future<bool> verifyPassword(String password) async => true;

  @override
  Future<void> signOut() async {}

  @override
  Future<bool> isVerifiedAdmin() async => false;

  @override
  String messageFor(Object error) => '$error';
}
