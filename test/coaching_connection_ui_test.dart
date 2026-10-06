import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/services/auth_service.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/coaching_invite_accept_sheet.dart';

const _token =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _uri = 'com.teampara.setflow://coaching-invite/$_token';

void main() {
  late _Auth auth;
  setUp(() {
    auth = _Auth();
    Auth.use(auth);
  });
  tearDown(Auth.reset);

  Future<_State> mount(
    WidgetTester tester, {
    bool guest = false,
    bool existingConnection = false,
    double scale = 1,
  }) async {
    auth.userId = guest ? null : 'member';
    final state = _State()
      ..chooseRole(guest ? UserRole.guest : UserRole.member);
    if (!guest) state.bindAccount('member');
    if (existingConnection) state.connections = [_connection];
    await tester.binding.setSurfaceSize(Size(scale > 1 ? 320 : 432, 900));
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              viewInsets: EdgeInsets.only(bottom: scale > 1 ? 280 : 0),
              padding: const EdgeInsets.only(bottom: 28),
            ),
            child: child!,
          ),
          home: const CoachingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
      await tester.pump(const Duration(seconds: 4));
      await tester.binding.setSurfaceSize(null);
    });
    return state;
  }

  Future<void> openInput(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('coaching-connect-trainer')));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('coaching-invite-confirm'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'existing PT starts with the connected trainer before new consultation',
    (tester) async {
      await mount(tester, existingConnection: true);
      final trainer = find.byKey(
        const ValueKey('member-coaching-connection-connection'),
      );
      expect(trainer, findsOneWidget);
      expect(find.text('담당 트레이너'), findsOneWidget);
      expect(find.text('수업 연결됨'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('coaching-connected-schedules')),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(trainer).dy,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(const ValueKey('coaching-new-consultation-primary')),
              )
              .dy,
        ),
      );
      expect(find.text('전체 운동 기록은 별도로 동의한 뒤 공유해요.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'guests browse and enter a link without a login wall; malformed input sends nothing',
    (tester) async {
      final state = await mount(tester, guest: true);
      await openInput(tester);
      expect(find.text('트레이너와 연결'), findsOneWidget);
      expect(find.byKey(const ValueKey('auth-gate-sign-in')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('coaching-invite-input')),
        'https://example.com/unknown',
      );
      await confirm(tester);
      expect(find.text('올바른 트레이너 초대 링크를 입력해 주세요.'), findsOneWidget);
      expect(state.acceptedTokens, isEmpty);
      expect(find.byKey(const ValueKey('auth-gate-sign-in')), findsNothing);
    },
  );

  testWidgets(
    'clipboard paste preserves the link and asks for login only at consent',
    (tester) async {
      final state = await mount(tester, guest: true);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') return {'text': _uri};
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await openInput(tester);
      await tester.tap(find.byKey(const ValueKey('coaching-invite-paste')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('coaching-invite-input')),
            )
            .controller!
            .text,
        _uri,
      );
      expect(state.acceptedTokens, isEmpty);
      await confirm(tester);
      expect(find.textContaining('트레이너와 연결하려면'), findsOneWidget);
      expect(find.byKey(const ValueKey('auth-gate-sign-in')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('auth-gate-dismiss')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('coaching-invite-input')),
            )
            .controller!
            .text,
        _uri,
      );
      expect(state.acceptedTokens, isEmpty);
    },
  );

  testWidgets('successful acceptance refreshes the same coaching page', (
    tester,
  ) async {
    final state = await mount(tester);
    await openInput(tester);
    await tester.enterText(
      find.byKey(const ValueKey('coaching-invite-input')),
      _uri,
    );
    await confirm(tester);
    expect(state.acceptedTokens, [_token]);
    expect(find.byKey(const ValueKey('coaching-invite-input')), findsNothing);
    expect(find.text('담당 트레이너'), findsOneWidget);
    expect(state.refreshCount, greaterThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('expired invite stays editable without claiming a connection', (
    tester,
  ) async {
    (await mount(tester)).acceptResult = false;
    await openInput(tester);
    await tester.enterText(
      find.byKey(const ValueKey('coaching-invite-input')),
      _uri,
    );
    await confirm(tester);
    expect(find.textContaining('만료되었거나 사용할 수 없는 초대'), findsOneWidget);
    expect(find.text('수업 연결됨'), findsNothing);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('coaching-invite-input')),
          )
          .controller!
          .text,
      _uri,
    );
  });

  testWidgets(
    'failed send can retry the same link; large text and keyboard keep consent reachable',
    (tester) async {
      final state = (await mount(tester, scale: 2))..failNext = true;
      await openInput(tester);
      await tester.enterText(
        find.byKey(const ValueKey('coaching-invite-input')),
        _uri,
      );
      await confirm(tester);
      expect(find.textContaining('링크와 로그인 상태'), findsOneWidget);
      expect(find.text('수업 연결됨'), findsNothing);
      await confirm(tester);
      expect(state.acceptedTokens, [_token, _token]);
      expect(find.text('담당 트레이너'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('account switch during acceptance blocks a late success', (
    tester,
  ) async {
    final state = await mount(tester);
    state.pending = Completer<CoachingConnectionAcceptance>();
    await openInput(tester);
    await tester.enterText(
      find.byKey(const ValueKey('coaching-invite-input')),
      _uri,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('coaching-invite-confirm')),
    );
    await tester.tap(find.byKey(const ValueKey('coaching-invite-confirm')));
    await tester.pump();
    expect(state.acceptedTokens, [_token]);
    auth.userId = 'other-member';
    state.bindAccount('other-member');
    await tester.pump();
    state.pending!.complete(const CoachingConnectionAcceptance(accepted: true));
    await tester.pumpAndSettle();
    expect(find.textContaining('계정이 바뀌었어요.'), findsOneWidget);
    expect(find.text('수업 연결됨'), findsNothing);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('coaching-invite-confirm')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('a deep-link entry pre-fills the same consent sheet', (
    tester,
  ) async {
    await mount(tester);
    final context = tester.element(find.byType(CoachingScreen));
    unawaited(showCoachingInviteAcceptance(context, initialInput: _token));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('coaching-invite-input')),
          )
          .controller!
          .text,
      _token,
    );
    expect(find.textContaining('별도의 운동 기록 공유 동의'), findsOneWidget);
  });

  testWidgets(
    'closing a pending acceptance releases navigation and ignores its late response',
    (tester) async {
      final state = await mount(tester);
      state.pending = Completer<CoachingConnectionAcceptance>();
      await openInput(tester);
      await tester.enterText(
        find.byKey(const ValueKey('coaching-invite-input')),
        _uri,
      );
      final button = find.byKey(const ValueKey('coaching-invite-confirm'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(state.coachingInviteAcceptanceInProgress, isTrue);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.tap(button);
      expect(state.acceptedTokens, [_token]);
      Navigator.of(tester.element(button)).pop(false);
      await tester.pumpAndSettle();
      expect(state.coachingInviteAcceptanceInProgress, isFalse);
      state.pending!.complete(
        const CoachingConnectionAcceptance(accepted: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('수업 연결됨'), findsNothing);
      expect(find.textContaining('트레이너와 연결됐어요.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

final _connection = CoachingConnection(
  id: 'connection',
  trainerId: 'trainer',
  memberUserId: 'member',
  memberName: '회원',
  trainerName: '담당 트레이너',
  status: 'active',
  createdAt: DateTime(2026, 10, 7),
  sessionCount: 3,
);

class _State extends AppState {
  _State();
  List<CoachingConnection> connections = [];
  final acceptedTokens = <String>[];
  int refreshCount = 0;
  bool acceptResult = true;
  bool failNext = false;
  Completer<CoachingConnectionAcceptance>? pending;

  void bindAccount(String id) {
    businessAccess = BusinessAccess(
      userId: id,
      accountRole: UserRole.member,
      resolvedRole: UserRole.member,
      availableRoles: const {UserRole.member},
    );
    connections = [];
    notifyListeners();
  }

  @override
  List<CoachingConnection> get coachingConnections => connections;
  @override
  Future<void> refreshMemberCoachingConnections() async {
    refreshCount++;
  }

  @override
  Future<CoachingConnectionAcceptance> acceptCoachingConnectionInviteToken([
    String? token,
  ]) async {
    acceptedTokens.add(token!);
    if (pending != null) return pending!.future;
    if (failNext) {
      failNext = false;
      throw StateError('offline');
    }
    if (acceptResult) {
      connections = [_connection];
      notifyListeners();
    }
    return CoachingConnectionAcceptance(accepted: acceptResult);
  }
}

class _Auth extends Fake implements AuthService {
  String? userId;
  @override
  AuthUser? get currentUser =>
      userId == null ? null : AuthUser(id: userId!, displayName: '회원');
  @override
  bool get hasAuthenticatedUser => userId != null;
  @override
  Stream<AuthChange> get authChanges => const Stream.empty();
}
