import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/screens/member_detail_screens.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/common.dart';

const _memberId = '44444444-4444-4444-8444-444444444444';
const _memberUserId = '11111111-1111-4111-8111-111111111111';
const _sessionId = '55555555-5555-4555-8555-555555555555';

void main() {
  Future<AppState> pumpMemberDetail(
    WidgetTester tester,
    _FakeBusinessRepository repository,
  ) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState(businessRepository: repository);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: MemberDetailScreen(member: _member(), role: UserRole.trainer),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets(
    'live detail requests the selected member UUID and blocks unconsented records',
    (tester) async {
      final repository = _FakeBusinessRepository(
        detail: _memberDetail(canReadWorkouts: false),
      );

      await pumpMemberDetail(tester, repository);

      expect(repository.requestedMemberIds, [_memberId]);
      expect(find.text('운동 기록 공유가 꺼져 있어요'), findsOneWidget);
      expect(find.text('바벨 벤치 프레스 · E2E'), findsNothing);
      expect(find.textContaining('82.5'), findsNothing);
    },
  );

  testWidgets('consented live detail renders nested exercises and sets', (
    tester,
  ) async {
    final repository = _FakeBusinessRepository(
      detail: _memberDetail(canReadWorkouts: true),
    );

    await pumpMemberDetail(tester, repository);
    await _expandSession(tester);

    expect(find.text('바벨 벤치 프레스 · E2E'), findsOneWidget);
    expect(find.textContaining('82.5'), findsOneWidget);
    expect(find.textContaining('8회'), findsOneWidget);
    expect(find.textContaining('120초'), findsOneWidget);
  });

  testWidgets(
    'session feedback sends the session UUID once and disables duplicate submission',
    (tester) async {
      final feedbackCompleter = Completer<BusinessSessionFeedback>();
      final repository = _FakeBusinessRepository(
        detail: _memberDetail(canReadWorkouts: true),
        feedbackCompleter: feedbackCompleter,
      );
      await pumpMemberDetail(tester, repository);
      await _expandSession(tester);

      final field = find.byKey(
        const ValueKey('session-feedback-field-$_sessionId'),
      );
      final submit = find.byKey(
        const ValueKey('session-feedback-submit-$_sessionId'),
      );
      await tester.ensureVisible(field);
      await tester.enterText(field, '다음 세션에서는 하강 구간을 2초간 유지해주세요.');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();

      expect(repository.feedbackInputs, hasLength(1));
      expect(repository.feedbackInputs.single.sessionId, _sessionId);
      expect(
        repository.feedbackInputs.single.text,
        '다음 세션에서는 하강 구간을 2초간 유지해주세요.',
      );
      final pendingButton = tester.widget<AppButton>(submit);
      expect(pendingButton.onPressed, isNull);
      expect(find.text('전송 중...'), findsOneWidget);

      await tester.tap(submit, warnIfMissed: false);
      await tester.pump();
      expect(repository.feedbackInputs, hasLength(1));

      feedbackCompleter.complete(
        BusinessSessionFeedback(
          id: '99999999-9999-4999-8999-999999999999',
          sessionId: _sessionId,
          trainerUserId: '22222222-2222-4222-8222-222222222222',
          authorName: '정코치',
          text: repository.feedbackInputs.single.text,
          createdAt: DateTime.utc(2026, 8, 16, 2),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.feedbackInputs, hasLength(1));
    },
  );
}

Future<void> _expandSession(WidgetTester tester) async {
  final card = find.byKey(const ValueKey('member-session-$_sessionId'));
  expect(card, findsOneWidget);
  await tester.tap(
    find.descendant(of: card, matching: find.byType(ListTile)).first,
  );
  await tester.pumpAndSettle();
}

BusinessMember _member() => const BusinessMember(
  id: _memberId,
  gymId: '33333333-3333-4333-8333-333333333333',
  userId: _memberUserId,
  name: '실회원',
  goal: '근력 향상',
  level: '중급',
  remainingPtSessions: 8,
  completionRate: 75,
);

BusinessMemberDetail _memberDetail({required bool canReadWorkouts}) {
  return BusinessMemberDetail(
    memberId: _memberId,
    memberUserId: _memberUserId,
    shareBodyData: canReadWorkouts,
    canReadWorkouts: canReadWorkouts,
    // The server may still return a defensive payload. The UI must honor the
    // explicit consent decision before rendering any nested workout data.
    sessions: [_session()],
  );
}

BusinessWorkoutSession _session() => BusinessWorkoutSession(
  id: _sessionId,
  userId: _memberUserId,
  date: DateTime(2026, 8, 15),
  category: 'strength',
  intensity: 'moderate',
  startedAt: DateTime.utc(2026, 8, 15, 9),
  endedAt: DateTime.utc(2026, 8, 15, 10),
  exercises: [
    BusinessWorkoutExercise(
      id: '66666666-6666-4666-8666-666666666666',
      name: '바벨 벤치 프레스 · E2E',
      targetMuscle: '가슴',
      orderIndex: 0,
      sets: [
        BusinessWorkoutSet(
          id: '77777777-7777-4777-8777-777777777777',
          setNumber: 1,
          type: 'normal',
          weight: 82.5,
          reps: 8,
          rir: 2,
          memo: '하강 2초',
          completed: true,
          completedAt: DateTime.utc(2026, 8, 15, 9, 15),
          estimated1Rm: 104.5,
          restSeconds: 120,
        ),
      ],
    ),
  ],
  feedbacks: const [],
);

class _FakeBusinessRepository implements BusinessRepository {
  _FakeBusinessRepository({required this.detail, this.feedbackCompleter});

  final BusinessMemberDetail detail;
  final Completer<BusinessSessionFeedback>? feedbackCompleter;
  final List<String> requestedMemberIds = [];
  final List<SendSessionFeedbackInput> feedbackInputs = [];

  @override
  Future<MemberSharingPreferences> loadMySharingPreferences() async {
    return const MemberSharingPreferences(
      shareBodyData: false,
      shareWorkoutRecords: false,
      marketing: false,
    );
  }

  @override
  Future<MemberSharingPreferences> updateMySharingPreferences(
    MemberSharingPreferences preferences,
  ) async => preferences;

  @override
  Future<BusinessMemberDetail> loadMemberDetail(
    String memberId, {
    DateTime? from,
    DateTime? to,
  }) async {
    requestedMemberIds.add(memberId);
    return detail;
  }

  @override
  Future<BusinessSessionFeedback> sendSessionFeedback(
    SendSessionFeedbackInput input,
  ) {
    feedbackInputs.add(input);
    final pending = feedbackCompleter;
    if (pending != null) return pending.future;
    return Future.value(
      BusinessSessionFeedback(
        id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        sessionId: input.sessionId,
        trainerUserId: '22222222-2222-4222-8222-222222222222',
        authorName: '정코치',
        text: input.text,
        createdAt: DateTime.utc(2026, 8, 16),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
