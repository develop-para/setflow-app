import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/screens/consultation_chat_screen.dart';
import 'package:setflow/theme.dart';

final _created = DateTime(2026, 10, 1, 10);
const _draftKey = ValueKey('consultation-chat-draft');
const _sendKey = ValueKey('consultation-chat-send');

void main() {
  Future<_State> mount(
    WidgetTester tester,
    _Repository repository, {
    UserRole role = UserRole.member,
    double scale = 1,
    Size size = const Size(360, 700),
    BusinessConsultation? initialConsultation,
    VoidCallback? onShowDetails,
  }) async {
    await tester.binding.setSurfaceSize(size);
    final state = _State()..changeAccount(repository.senderId);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              padding: const EdgeInsets.only(bottom: 34),
            ),
            child: child!,
          ),
          home: ConsultationChatScreen(
            consultationId: 'consultation',
            role: role,
            repository: repository,
            viewerUserId: repository.senderId,
            initialConsultation: initialConsultation,
            onShowDetails: onShowDetails,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.stream.close();
      state.dispose();
      await tester.pump();
      await tester.binding.setSurfaceSize(null);
    });
    return state;
  }

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(_draftKey), text);
    await tester.pump();
    await tester.tap(find.byKey(_sendKey));
    await tester.pumpAndSettle();
  }

  testWidgets('initial request and messages align by authenticated sender', (
    tester,
  ) async {
    final repository = _Repository()
      ..value = _consultation([
        _message('reply', '네, 함께 살펴볼게요.', senderId: 'trainer'),
      ]);
    var details = 0;
    await mount(tester, repository, onShowDetails: () => details++);
    expect(find.text('허리 통증이 있는데 운동해도 될까요?'), findsOneWidget);
    expect(find.text('네, 함께 살펴볼게요.'), findsOneWidget);
    final own = tester.getRect(
      find.byKey(const ValueKey('consultation-chat-bubble-initial-question')),
    );
    final other = tester.getRect(
      find.byKey(const ValueKey('consultation-chat-bubble-reply')),
    );
    expect(own.right, greaterThan(other.right));
    expect(find.text('2026년 10월 1일'), findsOneWidget);
    expect(find.text('10:01'), findsOneWidget);
    await tester.tap(find.byTooltip('상담 정보 보기'));
    expect(details, 1);
  });

  testWidgets(
    'member can send one character and stream ack is not duplicated',
    (tester) async {
      final repository = _Repository()..emitWhileSending = true;
      await mount(tester, repository);
      await send(tester, '네');
      expect(repository.sent.single.text, '네');
      expect(
        repository.sent.single.requestId,
        matches(RegExp(r'^[0-9a-f-]{36}$')),
      );
      expect(find.text('네'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(_draftKey)).controller!.text,
        '',
      );
    },
  );

  testWidgets('trainer follows up repeatedly without a minimum reply length', (
    tester,
  ) async {
    final repository = _Repository()..senderId = 'trainer';
    await mount(tester, repository, role: UserRole.trainer);
    await send(tester, '네');
    await send(tester, '어디가 아프세요?');
    expect(repository.sent.map((input) => input.text), ['네', '어디가 아프세요?']);
    expect(repository.sent[0].requestId, isNot(repository.sent[1].requestId));
    expect(find.text('네'), findsOneWidget);
    expect(find.text('어디가 아프세요?'), findsOneWidget);
  });

  testWidgets(
    'failed delivery retains draft and retries the same request key',
    (tester) async {
      final repository = _Repository()..failSend = true;
      await mount(tester, repository);
      await send(tester, '질문이 하나 더 있어요.');
      expect(
        tester.widget<TextField>(find.byKey(_draftKey)).controller!.text,
        '질문이 하나 더 있어요.',
      );
      expect(find.textContaining('내용은 남아 있으니'), findsOneWidget);
      repository.failSend = false;
      await tester.tap(find.byKey(_sendKey));
      await tester.pumpAndSettle();
      expect(repository.sent[0].requestId, repository.sent[1].requestId);
      expect(find.text('질문이 하나 더 있어요.'), findsOneWidget);
    },
  );

  testWidgets(
    'send is locked until ack and changing a failed draft uses a new key',
    (tester) async {
      final repository = _Repository()
        ..sendGate = Completer<BusinessConsultation>();
      await mount(tester, repository);
      await tester.enterText(find.byKey(_draftKey), '첫 질문');
      await tester.pump();
      await tester.tap(find.byKey(_sendKey));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byKey(_sendKey)).onPressed,
        isNull,
      );
      expect(tester.widget<TextField>(find.byKey(_draftKey)).enabled, isFalse);
      expect(repository.sent, hasLength(1));
      repository.sendGate!.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      repository.sendGate = null;
      await send(tester, '수정한 질문');
      expect(repository.sent[0].requestId, isNot(repository.sent[1].requestId));
    },
  );

  testWidgets('a stale poll cannot remove an acknowledged message', (
    tester,
  ) async {
    final repository = _Repository();
    await mount(tester, repository);
    await send(tester, '운동은 내일부터 할게요.');
    repository.stream.add(_consultation([]));
    await tester.pumpAndSettle();
    expect(find.text('운동은 내일부터 할게요.'), findsOneWidget);
  });

  testWidgets('lost authorization clears messages and blocks further input', (
    tester,
  ) async {
    final repository = _Repository();
    await mount(tester, repository);
    await tester.enterText(find.byKey(_draftKey), '저장하면 안 되는 초안');
    repository.stream.addError(const BusinessAccessDenied());
    await tester.pumpAndSettle();
    expect(find.textContaining('상담에 접근할 수 없어요'), findsOneWidget);
    expect(find.text('허리 통증이 있는데 운동해도 될까요?'), findsNothing);
    expect(find.byKey(_draftKey), findsNothing);
    expect(repository.sent, isEmpty);
  });

  testWidgets(
    'account change disposes the previous account draft and late send',
    (tester) async {
      final repository = _Repository()
        ..sendGate = Completer<BusinessConsultation>();
      final state = await mount(tester, repository);
      await tester.enterText(find.byKey(_draftKey), '이전 계정 메시지');
      await tester.pump();
      await tester.tap(find.byKey(_sendKey));
      await tester.pump();
      state.changeAccount('another-member');
      await tester.pumpAndSettle();
      repository.sendGate!.complete(_consultation([_message('late', '늦은 응답')]));
      await tester.pumpAndSettle();
      expect(find.textContaining('계정이 바뀌어'), findsOneWidget);
      expect(find.byKey(_draftKey), findsNothing);
      expect(find.text('늦은 응답'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('loading failure can reconnect and send afterward', (
    tester,
  ) async {
    final repository = _Repository()..failLoad = true;
    await mount(tester, repository);
    expect(find.textContaining('대화를 불러오지 못했어요'), findsOneWidget);
    repository.failLoad = false;
    await tester.tap(find.byKey(const ValueKey('consultation-chat-retry')));
    await tester.pumpAndSettle();
    expect(find.text('허리 통증이 있는데 운동해도 될까요?'), findsOneWidget);
    await send(tester, '연결됐어요');
    expect(repository.sent, hasLength(1));
  });

  testWidgets(
    'cached consultation stays private until server access is verified',
    (tester) async {
      final repository = _Repository()
        ..senderId = 'trainer'
        ..failLoad = true;
      await mount(
        tester,
        repository,
        role: UserRole.trainer,
        initialConsultation: repository.value,
        onShowDetails: () {},
      );
      expect(find.text('상담 채팅'), findsOneWidget);
      expect(find.text('민지'), findsNothing);
      expect(find.text('허리 통증이 있는데 운동해도 될까요?'), findsNothing);
      expect(find.byTooltip('상담 정보 보기'), findsNothing);
      expect(find.byKey(_draftKey), findsNothing);
      expect(find.textContaining('대화를 불러오지 못했어요'), findsOneWidget);

      repository.failLoad = false;
      await tester.tap(find.byKey(const ValueKey('consultation-chat-retry')));
      await tester.pumpAndSettle();
      expect(find.text('민지'), findsWidgets);
      expect(find.text('허리 통증이 있는데 운동해도 될까요?'), findsOneWidget);
      expect(find.byTooltip('상담 정보 보기'), findsOneWidget);
      expect(find.byKey(_draftKey), findsOneWidget);

      repository.stream.addError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('허리 통증이 있는데 운동해도 될까요?'), findsOneWidget);
      expect(find.byTooltip('상담 정보 보기'), findsOneWidget);
      expect(find.byKey(_draftKey), findsOneWidget);
    },
  );

  testWidgets(
    'reading history holds scroll position until new messages are opened',
    (tester) async {
      final history = List.generate(
        30,
        (index) => _message('old-$index', '이전 대화 $index', minute: index + 1),
      );
      final repository = _Repository()..value = _consultation(history);
      await mount(tester, repository, initialConsultation: repository.value);
      final list = find.byKey(const ValueKey('consultation-chat-messages'));
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)),
      );
      expect(scrollable.position.extentAfter, 0);
      scrollable.position.jumpTo(0);
      await tester.pump();
      repository.stream.add(
        _consultation([...history, _message('new', '새 답변', minute: 50)]),
      );
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, 0);
      expect(find.text('새 메시지 보기'), findsOneWidget);
      await tester.tap(find.text('새 메시지 보기'));
      await tester.pumpAndSettle();
      expect(find.text('새 답변'), findsOneWidget);
      expect(scrollable.position.extentAfter, 0);
    },
  );

  testWidgets(
    'identical request keys from different participants both remain',
    (tester) async {
      final repository = _Repository()
        ..value = _consultation([
          _message('member', '회원 답변', senderId: 'member', requestId: 'same'),
          _message(
            'trainer',
            '트레이너 답변',
            senderId: 'trainer',
            requestId: 'same',
          ),
        ]);
      await mount(tester, repository);
      expect(find.text('회원 답변'), findsOneWidget);
      expect(find.text('트레이너 답변'), findsOneWidget);
    },
  );

  testWidgets('an already stored initial question is displayed once', (
    tester,
  ) async {
    final repository = _Repository()
      ..value = _consultation([
        _message(
          'initial',
          '허리 통증이 있는데 운동해도 될까요?',
          senderId: 'member',
          minute: 0,
        ),
      ]);
    await mount(tester, repository);
    expect(find.text('허리 통증이 있는데 운동해도 될까요?'), findsOneWidget);
  });

  testWidgets('large text and keyboard keep the send button within safe area', (
    tester,
  ) async {
    final repository = _Repository();
    await mount(tester, repository, scale: 2);
    await tester.enterText(find.byKey(_draftKey), '여러 줄 메시지\n두 번째 줄\n세 번째 줄');
    tester.view.viewInsets = FakeViewPadding(
      bottom: 200 * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final button = tester.getRect(find.byKey(_sendKey));
    expect(button.bottom, lessThanOrEqualTo(700 - 200));
    expect(button.right, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(_sendKey));
    await tester.pumpAndSettle();
    expect(repository.sent.single.text, contains('\n'));
  });

  testWidgets(
    'small display fits four-line drafts with keyboard and connection errors',
    (tester) async {
      final repository = _Repository()..failSend = true;
      await mount(tester, repository, scale: 2, size: const Size(320, 568));
      const text = '첫 줄\n두 줄\n셋 줄\n넷 줄';
      await tester.enterText(find.byKey(_draftKey), text);
      tester.view.viewInsets = FakeViewPadding(
        bottom: 240 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetViewInsets);
      repository.stream.addError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<TextField>(find.byKey(_draftKey)).maxLines,
        lessThanOrEqualTo(2),
      );
      final button = tester.getRect(find.byKey(_sendKey));
      expect(button.bottom, lessThanOrEqualTo(568 - 240));
      expect(button.right, lessThanOrEqualTo(320));
      await tester.tap(find.byKey(_sendKey));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<TextField>(find.byKey(_draftKey)).controller!.text,
        text,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('consultation-chat-retry')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      repository.failSend = false;
      await tester.tap(find.byKey(_sendKey));
      await tester.pumpAndSettle();
      expect(repository.sent.last.text, text);
      expect(
        tester.widget<TextField>(find.byKey(_draftKey)).controller!.text,
        '',
      );
    },
  );
}

class _State extends AppState {
  void changeAccount(String userId) {
    businessAccess = BusinessAccess(
      userId: userId,
      accountRole: UserRole.member,
      resolvedRole: UserRole.member,
      availableRoles: const {UserRole.member},
    );
    notifyListeners();
  }
}

class _Repository implements ConsultationChatRepository {
  final stream = StreamController<BusinessConsultation>.broadcast();
  final sent = <SendConsultationMessageInput>[];
  BusinessConsultation value = _consultation([]);
  String senderId = 'member';
  bool failLoad = false;
  bool failSend = false;
  bool emitWhileSending = false;
  Completer<BusinessConsultation>? sendGate;

  @override
  Future<BusinessConsultation> loadConsultation(String consultationId) async {
    if (failLoad) throw StateError('offline');
    return value;
  }

  @override
  Stream<BusinessConsultation> watchConsultation(String consultationId) =>
      stream.stream;

  @override
  Future<BusinessConsultation> sendConsultationMessage(
    SendConsultationMessageInput input,
  ) async {
    sent.add(input);
    if (sendGate != null) return sendGate!.future;
    if (failSend) throw StateError('offline');
    value = _consultation([
      ...value.messages,
      _message(
        'sent-${sent.length}',
        input.text,
        senderId: senderId,
        requestId: input.requestId,
      ),
    ]);
    if (emitWhileSending) stream.add(value);
    return value;
  }
}

BusinessConsultation _consultation(
  List<BusinessConsultationMessage> messages,
) => BusinessConsultation(
  id: 'consultation',
  userId: 'member',
  status: BusinessConsultationStatus.pending,
  isRead: false,
  messages: messages,
  question: '허리 통증이 있는데 운동해도 될까요?',
  memberName: '민지',
  trainerName: '지훈',
  createdAt: _created,
);

BusinessConsultationMessage _message(
  String id,
  String text, {
  String senderId = 'trainer',
  int minute = 1,
  String? requestId,
}) => BusinessConsultationMessage(
  id: id,
  consultationId: 'consultation',
  sender: senderId == 'member'
      ? BusinessMessageSender.member
      : BusinessMessageSender.trainer,
  senderId: senderId,
  text: text,
  createdAt: _created.add(Duration(minutes: minute)),
  requestId: requestId,
);
