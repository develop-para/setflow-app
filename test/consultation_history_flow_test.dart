import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/theme.dart';

const _userId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _trainerId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

void main() {
  testWidgets(
    'coaching exposes one new request action and separates active from history',
    (tester) async {
      final consultations = [
        _consultation(
          id: 'pending-consultation',
          status: BusinessConsultationStatus.pending,
        ),
        _consultation(
          id: 'assigned-consultation',
          status: BusinessConsultationStatus.assigned,
        ),
        _consultation(
          id: 'answered-consultation',
          status: BusinessConsultationStatus.answered,
        ),
        _consultation(
          id: 'replied-consultation',
          status: BusinessConsultationStatus.replied,
          withAnswer: true,
        ),
      ];
      final state = AppState(
        businessRepository: _ConsultationRepository(consultations),
      )..memberConsultations = consultations;
      addTearDown(state.dispose);

      await _pump(tester, state, const CoachingScreen());

      expect(find.text('새 상담 신청'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('coaching-new-consultation-primary')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('coaching-consultation-history')),
        findsOneWidget,
      );
      expect(find.text('진행 중 상담 2건'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('coaching-active-consultation-pending-consultation'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('coaching-active-consultation-assigned-consultation'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('coaching-active-consultation-answered-consultation'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('coaching-active-consultation-replied-consultation'),
        ),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('coaching-consultation-history')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('consultation-history-list')),
        findsOneWidget,
      );
      expect(find.text('답변이 완료된 상담 2건'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('consultation-history-item-answered-consultation'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('consultation-history-item-replied-consultation'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('consultation-history-item-pending-consultation'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('consultation-history-item-assigned-consultation'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('consultation history renders loading then empty states', (
    tester,
  ) async {
    final state = AppState(
      businessRepository: _ConsultationRepository(const []),
    )..memberConsultationsLoading = true;
    addTearDown(state.dispose);

    await _pump(tester, state, const ConsultationHistoryScreen());

    expect(
      find.byKey(const ValueKey('consultation-history-loading')),
      findsOneWidget,
    );

    state.memberConsultationsLoading = false;
    state.notifyListeners();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('consultation-history-empty')),
      findsOneWidget,
    );
    expect(find.text('아직 과거 상담 이력이 없어요'), findsOneWidget);
  });

  testWidgets('consultation history error retries the server and recovers', (
    tester,
  ) async {
    final completed = [
      _consultation(
        id: 'retry-answered-consultation',
        status: BusinessConsultationStatus.answered,
      ),
      _consultation(
        id: 'retry-replied-consultation',
        status: BusinessConsultationStatus.replied,
        withAnswer: true,
      ),
    ];
    final repository = _ConsultationRepository(completed);
    final state = AppState(
      businessRepository: repository,
      loadBusinessWithoutAuth: true,
    )..memberConsultationsError = StateError('consultations unavailable');
    addTearDown(state.dispose);

    await _pump(tester, state, const ConsultationHistoryScreen());

    expect(
      find.byKey(const ValueKey('consultation-history-error')),
      findsOneWidget,
    );
    expect(find.text('과거 상담 이력을 불러오지 못했어요.'), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(repository.listCalls, 1);
    expect(
      find.byKey(
        const ValueKey('consultation-history-item-retry-answered-consultation'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('consultation-history-item-retry-replied-consultation'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('consultation-history-error')),
      findsNothing,
    );
  });

  testWidgets(
    'consultation history shows its own error when only active cache exists',
    (tester) async {
      final active = [
        _consultation(
          id: 'cached-active-consultation',
          status: BusinessConsultationStatus.assigned,
        ),
      ];
      final state =
          AppState(businessRepository: _ConsultationRepository(active))
            ..memberConsultations = active
            ..memberConsultationsError = StateError('consultations unavailable')
            ..businessError = StateError('unrelated workspace failure');
      addTearDown(state.dispose);

      await _pump(tester, state, const ConsultationHistoryScreen());

      expect(
        find.byKey(const ValueKey('consultation-history-error')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('consultation-history-empty')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'consultation history ignores unrelated business errors and warns on stale history',
    (tester) async {
      final completed = [
        _consultation(
          id: 'cached-completed-consultation',
          status: BusinessConsultationStatus.replied,
          withAnswer: true,
        ),
      ];
      final state =
          AppState(businessRepository: _ConsultationRepository(completed))
            ..memberConsultations = completed
            ..businessError = StateError('unrelated workspace failure');
      addTearDown(state.dispose);

      await _pump(tester, state, const ConsultationHistoryScreen());

      expect(
        find.byKey(const ValueKey('consultation-history-list')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('consultation-history-error')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('consultation-history-stale-warning')),
        findsNothing,
      );

      state.memberConsultationsError = StateError('consultations unavailable');
      state.notifyListeners();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('consultation-history-list')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('consultation-history-stale-warning')),
        findsOneWidget,
      );
    },
  );
}

Future<void> _pump(WidgetTester tester, AppState state, Widget screen) async {
  await tester.binding.setSurfaceSize(const Size(480, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(theme: SetflowTheme.light, home: screen),
    ),
  );
  await tester.pump();
}

BusinessConsultation _consultation({
  required String id,
  required BusinessConsultationStatus status,
  bool withAnswer = false,
}) => BusinessConsultation(
  id: id,
  userId: _userId,
  trainerId: _trainerId,
  status: status,
  isRead:
      status == BusinessConsultationStatus.answered ||
      status == BusinessConsultationStatus.replied,
  trainerName: '정코치 $id',
  specialty: '근력 향상',
  goal: '근력 향상',
  level: '중급',
  question: '$id 질문입니다.',
  createdAt: DateTime.utc(2026, 8, 17, 9),
  messages: withAnswer
      ? [
          BusinessConsultationMessage(
            id: '$id-answer',
            consultationId: id,
            sender: BusinessMessageSender.trainer,
            senderId: _trainerId,
            text: '$id 답변입니다.',
            createdAt: DateTime.utc(2026, 8, 17, 10),
          ),
        ]
      : const [],
);

class _ConsultationRepository implements BusinessRepository {
  _ConsultationRepository(this.consultations);

  final List<BusinessConsultation> consultations;
  int listCalls = 0;

  @override
  Future<BusinessAccess> loadAccess() async => const BusinessAccess(
    userId: _userId,
    accountRole: UserRole.member,
    resolvedRole: UserRole.member,
    availableRoles: {UserRole.member},
  );

  @override
  Future<List<PublicTrainer>> listPublicTrainers() async => const [];

  @override
  Future<List<BusinessConsultation>> listMyConsultations() async {
    listCalls++;
    return consultations;
  }

  @override
  Future<MemberSharingPreferences> loadMySharingPreferences() async =>
      const MemberSharingPreferences(
        shareBodyData: false,
        shareWorkoutRecords: false,
        marketing: false,
      );

  @override
  Future<List<BusinessCoachingSchedule>> listCoachingSchedules({
    DateTime? from,
    DateTime? to,
  }) async => const [];

  @override
  Future<List<RoutineShareRecord>> listIncomingRoutineShares() async =>
      const [];

  @override
  Future<List<PersonalRoutineRecord>> listPersonalRoutines() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
