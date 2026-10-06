import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/data/coaching_management_repository.dart';
import 'package:setflow/screens/coaching_management_screen.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/theme/icons.dart';
import 'package:setflow/widgets/workout_history_calendar.dart';

const _template = ExerciseTemplate(
  id: 'squat',
  name: '스쿼트',
  muscle: '하체',
  icon: SetflowIcons.record,
);
final _day = DateTime(2026, 9, 11);

void main() {
  Future<void> confirmSharing(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('confirm-management-sharing')));
    await tester.pumpAndSettle();
  }

  Future<_State> mount(
    WidgetTester tester,
    _Repository repository, {
    double scale = 1,
    String? consultationId,
    String? linkId,
  }) async {
    await tester.binding.setSurfaceSize(Size(scale > 1 ? 320 : 432, 900));
    final state = _State(businessRepository: repository)
      ..changeAccount('member');
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: CoachingManagementScreen(
            consultationId: consultationId,
            linkId: linkId,
          ),
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

  testWidgets('알림으로 받은 연결 요청을 목록 맨 위에 표시한다', (tester) async {
    final repository = _Repository()
      ..status = 'pending'
      ..extraLinks = const [
        CoachingManagementLink(
          id: 'notified-link',
          memberName: '알림 회원',
          trainerName: '알림 트레이너',
          status: 'pending',
          viewerRole: 'member',
          canRespond: true,
        ),
      ];
    await mount(tester, repository, linkId: 'notified-link');
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('management-link-notified-link')),
          )
          .dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('management-link-link')))
            .dy,
      ),
    );
    expect(
      find.byKey(const ValueKey('accept-link-notified-link')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('받은 요청과 보낸 요청을 공유 중인 상대보다 먼저 보여주고 종료 이력은 접는다', (tester) async {
    final repository = _Repository()
      ..extraLinks = const [
        CoachingManagementLink(
          id: 'ended',
          memberName: '민지',
          trainerName: '종료 트레이너',
          status: 'ended',
          viewerRole: 'member',
          canRespond: false,
        ),
        CoachingManagementLink(
          id: 'sent',
          memberName: '민지',
          trainerName: '대기 트레이너',
          status: 'pending',
          viewerRole: 'member',
          canRespond: false,
        ),
        CoachingManagementLink(
          id: 'received',
          memberName: '민지',
          trainerName: '요청 트레이너',
          status: 'pending',
          viewerRole: 'member',
          canRespond: true,
        ),
      ];
    await mount(tester, repository);
    final received = find.byKey(const ValueKey('management-link-received'));
    final sent = find.byKey(const ValueKey('management-link-sent'));
    final active = find.byKey(const ValueKey('management-link-link'));
    expect(
      tester.getTopLeft(received).dy,
      lessThan(tester.getTopLeft(sent).dy),
    );
    expect(tester.getTopLeft(sent).dy, lessThan(tester.getTopLeft(active).dy));
    expect(find.text('요청 트레이너 트레이너'), findsOneWidget);
    expect(find.text('상대 수락 대기'), findsOneWidget);
    expect(find.byKey(const ValueKey('accept-link-sent')), findsNothing);
    expect(find.byKey(const ValueKey('management-link-ended')), findsNothing);
    final history = find.byKey(const ValueKey('management-link-history'));
    await tester.ensureVisible(history);
    await tester.tap(history);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('management-link-ended')), findsOneWidget);
    expect(find.text('공유 해제됨'), findsOneWidget);
    expect(
      DefaultTextStyle.of(tester.element(find.text('종료된 공유 · 1'))).style.color,
      SetflowColors.brandDeep,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('요청과 수락은 공유 범위를 확인하고 동의하기 전에는 전송하지 않는다', (tester) async {
    final repository = _Repository()..status = 'pending';
    await mount(tester, repository, consultationId: 'consultation');
    await tester.tap(find.byKey(const ValueKey('request-management-link')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(repository.requestCalls, 0);
    final accept = find.byKey(const ValueKey('accept-link-link'));
    await tester.ensureVisible(accept);
    final acceptAction = tester.widget<FilledButton>(accept).onPressed!;
    acceptAction();
    acceptAction();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('지훈 트레이너와 운동 기록 공유를 시작해요.'), findsOneWidget);
    expect(repository.accepted, isNull);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(repository.accepted, isNull);
    expect(tester.widget<FilledButton>(accept).onPressed, isNotNull);
  });

  testWidgets('공유 동의 중에 계정이 바뀌면 팝업과 요청 권한을 닫는다', (tester) async {
    final repository = _Repository()..status = 'pending';
    final state = await mount(tester, repository);
    await tester.tap(find.byKey(const ValueKey('accept-link-link')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('confirm-management-sharing')),
      findsOneWidget,
    );
    state.changeAccount('other-member');
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(repository.accepted, isNull);
    expect(
      find.byKey(const ValueKey('coaching-account-expired')),
      findsOneWidget,
    );
  });

  testWidgets('작은 화면과 큰 글자에서도 공유 범위 전체를 확인하고 수락할 수 있다', (tester) async {
    final repository = _Repository()..status = 'pending';
    await mount(tester, repository, scale: 2);
    final accept = find.byKey(const ValueKey('accept-link-link'));
    await tester.ensureVisible(accept);
    await tester.tap(accept);
    await tester.pumpAndSettle();
    expect(find.textContaining('이전 기록을 포함한 모든 운동 기록'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await confirmSharing(tester);
    expect(repository.accepted, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('운동 기록 공유 해제는 수업별 공유와 구분해 안내하고 확인한 뒤에만 요청한다', (tester) async {
    final repository = _Repository();
    await mount(tester, repository);
    await tester.tap(find.text('기록 공유 해제'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('수업별로 따로 허용한 공유는 해당 수업에서 관리해요.'),
      findsOneWidget,
    );
    expect(find.textContaining('전체 연결 해제'), findsNothing);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(repository.endedLinks, isEmpty);
    await tester.tap(find.text('기록 공유 해제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('해제'));
    await tester.pumpAndSettle();
    expect(repository.endedLinks, ['link']);
    expect(find.byKey(const ValueKey('management-history-link')), findsNothing);
    expect(
      find.byKey(const ValueKey('management-link-history')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'consultation requests explicit consent and receiver accepts the connection',
    (tester) async {
      final repository = _Repository()..status = 'pending';
      await mount(tester, repository, consultationId: 'consultation');
      expect(find.textContaining('수업·개인 운동 모두 종료 후 48시간'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('request-management-link')));
      await tester.pumpAndSettle();
      expect(repository.requestedConsultation, isNull);
      expect(find.textContaining('수업·개인 운동 모두 종료 후 48시간'), findsOneWidget);
      expect(find.textContaining('이전 기록을 포함한 모든 운동 기록'), findsOneWidget);
      expect(find.textContaining('종료 시각이 없는 기록도 승인을 받아요.'), findsOneWidget);
      await confirmSharing(tester);
      expect(repository.requestedConsultation, 'consultation');
      await tester.ensureVisible(
        find.byKey(const ValueKey('accept-link-link')),
      );
      await tester.tap(find.byKey(const ValueKey('accept-link-link')));
      await tester.pumpAndSettle();
      expect(repository.accepted, isNull);
      await confirmSharing(tester);
      expect(repository.accepted, isTrue);
      expect(find.text('전체 운동 기록'), findsOneWidget);
    },
  );

  testWidgets(
    'member reviews exact change and approving updates the local diary',
    (tester) async {
      final repository = _Repository()..hasCorrection = true;
      final state = await mount(tester, repository);
      state.sessions[_day] = _session();
      expect(find.text('무게: 40 → 45 kg'), findsOneWidget);
      expect(find.text('수정 이유: 함께 확인한 중량'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('approve-correction-correction')),
      );
      await tester.tap(
        find.byKey(const ValueKey('approve-correction-correction')),
      );
      await tester.pumpAndSettle();
      expect(repository.correctionAccepted, isTrue);
      expect(find.text('수정 반영됨'), findsNothing);
      final correctionHistory = find.byKey(
        const ValueKey('management-correction-history'),
      );
      await tester.ensureVisible(correctionHistory);
      await tester.tap(correctionHistory);
      await tester.pumpAndSettle();
      expect(find.text('수정 반영됨'), findsOneWidget);
      expect(state.sessions[_day]!.exercises.first.sets.first.weight, 45);
      // The same inbox entry must not overwrite a subsequent intentional member edit.
      state.sessions[_day]!.exercises.first.sets.first.weight = 46;
      await tester.tap(find.byTooltip('연결과 승인 요청 새로고침'));
      await tester.pumpAndSettle();
      expect(state.sessions[_day]!.exercises.first.sets.first.weight, 46);
    },
  );

  for (final viewer in ['member', 'trainer']) {
    testWidgets(
      '$viewer self connection shows the actual refusal and keeps retry enabled',
      (tester) async {
        final repository = _Repository()
          ..viewer = viewer
          ..requestFailure = const CoachingManagementFailure(
            CoachingManagementFailureReason.selfConnection,
          );
        await mount(tester, repository, consultationId: 'self-consultation');
        final request = find.byKey(const ValueKey('request-management-link'));
        await tester.tap(request);
        await tester.pumpAndSettle();
        await confirmSharing(tester);
        expect(
          find.text('본인 계정과는 연결할 수 없어요. 다른 회원 또는 트레이너와 상담해주세요.'),
          findsOneWidget,
        );
        expect(find.textContaining('처리하지 못했어요.'), findsNothing);
        expect(find.text('연결 목록에서 상태를 확인해주세요'), findsNothing);
        expect(tester.widget<FilledButton>(request).onPressed, isNotNull);
        expect(repository.requestedConsultation, 'self-consultation');
        expect(repository.requestCalls, 1);
      },
    );
  }

  testWidgets(
    'authorization refusal explains access without treating it as a network failure',
    (tester) async {
      final repository = _Repository()
        ..requestFailure = const CoachingManagementFailure(
          CoachingManagementFailureReason.accessDenied,
        );
      await mount(tester, repository, consultationId: 'assigned-elsewhere');
      final request = find.byKey(const ValueKey('request-management-link'));
      await tester.tap(request);
      await tester.pumpAndSettle();
      await confirmSharing(tester);
      expect(
        find.text('현재 이 상담의 연결을 요청할 권한이 없어요. 상담 목록과 담당 트레이너를 다시 확인해주세요.'),
        findsOneWidget,
      );
      expect(find.textContaining('처리하지 못했어요.'), findsNothing);
      expect(tester.widget<FilledButton>(request).onPressed, isNotNull);
    },
  );

  testWidgets(
    'temporary request failure preserves the consultation and succeeds on retry',
    (tester) async {
      final repository = _Repository()
        ..requestFailure = StateError('network failed');
      await mount(tester, repository, consultationId: 'retry-consultation');
      final request = find.byKey(const ValueKey('request-management-link'));
      await tester.tap(request);
      await tester.pumpAndSettle();
      await confirmSharing(tester);
      expect(find.text('처리하지 못했어요. 연결 상태와 최신 기록을 다시 확인해주세요.'), findsOneWidget);
      expect(tester.widget<FilledButton>(request).onPressed, isNotNull);
      expect(find.text('연결 목록에서 상태를 확인해주세요'), findsNothing);
      repository.requestFailure = null;
      await tester.pump(const Duration(seconds: 4));
      await tester.tap(request);
      await tester.pumpAndSettle();
      await confirmSharing(tester);
      expect(repository.requestCalls, 2);
      expect(repository.requestedConsultation, 'retry-consultation');
      expect(find.text('연결 목록에서 상태를 확인해주세요'), findsOneWidget);
      expect(tester.widget<FilledButton>(request).onPressed, isNull);
    },
  );

  testWidgets(
    'gym sees records and assignment controls, without edit or approval buttons',
    (tester) async {
      final repository = _Repository()
        ..viewer = 'gym'
        ..hasCorrection = true;
      await mount(tester, repository, scale: 2);
      expect(find.text('담당 트레이너 변경 요청'), findsOneWidget);
      expect(find.text('이 수정 승인'), findsNothing);
      await tester.tap(find.text('전체 운동 기록'));
      await tester.pumpAndSettle();
      expect(find.text('스쿼트'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('personal:2026-09-11-squat-1-weight')),
        findsNothing,
      );
      expect(find.text('무게 40 kg'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'trainer submits a dial change with a reason and original revision',
    (tester) async {
      final repository = _Repository()..viewer = 'trainer';
      await mount(tester, repository);
      await tester.tap(find.text('전체 운동 기록'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('personal:2026-09-11-squat-1-weight')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('number-dial-direct-input')),
        '47.5',
      );
      await tester.tap(find.text('적용'));
      await tester.pumpAndSettle();
      expect(find.text('무게: 40 → 47.5 kg'), findsOneWidget);
      expect(repository.proposedValue, isNull);
      await tester.enterText(find.byType(TextField), '중량 확인');
      await tester.pump();
      await tester.tap(find.text('승인 요청'));
      await tester.pumpAndSettle();
      expect(repository.proposedValue, 47.5);
      expect(repository.proposedRevision, 'revision-1');
      expect(repository.proposedReason, '중량 확인');
      expect(repository.requestId, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(
        find.text('무게 40 kg'),
        findsOneWidget,
      ); // Pending approval preserves the original.
    },
  );

  testWidgets('revoked read clears already visible records', (tester) async {
    final repository = _Repository();
    await mount(tester, repository);
    await tester.tap(find.text('전체 운동 기록'));
    await tester.pumpAndSettle();
    expect(find.text('스쿼트'), findsOneWidget);
    repository.failHistory = true;
    await tester.tap(find.byTooltip('운동 기록 새로고침'));
    await tester.pumpAndSettle();
    expect(find.text('스쿼트'), findsNothing);
    expect(find.textContaining('공유 권한을 확인'), findsOneWidget);
  });

  testWidgets('managed history switches days and loads older calendar months', (
    tester,
  ) async {
    final repository = _Repository()..hasOlderPage = true;
    await mount(tester, repository);
    await tester.tap(find.text('전체 운동 기록'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutHistoryCalendar), findsOneWidget);
    expect(find.text('2026.09'), findsOneWidget);
    expect(repository.historyCursors, [null, 'older']);
    expect(find.text('스쿼트'), findsOneWidget);
    expect(find.text('지난달 운동'), findsNothing);

    final emptyDay = find.byKey(
      const ValueKey('history-calendar-day-2026-09-10'),
    );
    await tester.tap(emptyDay);
    await tester.pumpAndSettle();
    expect(find.text('스쿼트'), findsNothing);
    expect(find.text('이 날짜에는 저장된 운동 기록이 없어요.'), findsOneWidget);
    await tester.tap(find.byTooltip('이전 달'));
    await tester.pumpAndSettle();
    expect(find.text('2026.08'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('history-calendar-day-2026-08-11')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('지난달 운동'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('personal:2026-09-11-squat-1-weight')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('late response after switching accounts cannot restore records', (
    tester,
  ) async {
    final repository = _Repository();
    final state = await mount(tester, repository);
    repository.historyGate = Completer<void>();
    await tester.tap(find.text('전체 운동 기록'));
    await tester.pump(const Duration(milliseconds: 400));
    state.changeAccount('someone-else');
    await tester.pumpAndSettle();
    repository.historyGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('스쿼트'), findsNothing);
    expect(
      find.byKey(const ValueKey('coaching-account-expired')),
      findsOneWidget,
    );
  });
}

WorkoutSession _session() => WorkoutSession(
  date: _day,
  exercises: [
    WorkoutExercise(
      id: 'squat',
      template: _template,
      sets: [WorkoutSetEntry(number: 1, weight: 40, reps: 10, completed: true)],
    ),
  ],
);

class _State extends AppState {
  _State({super.businessRepository});
  void changeAccount(String id) {
    businessAccess = BusinessAccess(
      userId: id,
      accountRole: UserRole.member,
      resolvedRole: UserRole.member,
      availableRoles: const {UserRole.member},
    );
    notifyListeners();
  }
}

class _Repository implements BusinessRepository, CoachingManagementRepository {
  String status = 'active';
  List<CoachingManagementLink> extraLinks = [];
  String viewer = 'member';
  bool hasCorrection = false;
  bool failHistory = false;
  bool? accepted;
  bool? correctionAccepted;
  String? requestedConsultation;
  Object? requestFailure;
  int requestCalls = 0;
  double? proposedValue;
  String? proposedRevision;
  String? proposedReason;
  String? requestId;
  Completer<void>? historyGate;
  bool hasOlderPage = false;
  final historyCursors = <String?>[];
  final endedLinks = <String>[];

  @override
  Future<List<CoachingManagementLink>> listManagementLinks() async => [
    CoachingManagementLink(
      id: 'link',
      memberName: '민지',
      trainerName: '지훈',
      status: status,
      viewerRole: viewer,
      canRespond: status == 'pending',
    ),
    ...extraLinks,
  ];
  @override
  Future<void> requestManagementLink(String consultationId) async {
    requestedConsultation = consultationId;
    requestCalls++;
    if (requestFailure case final failure?) throw failure;
  }

  @override
  Future<void> respondManagementLink(
    String linkId, {
    required bool accept,
  }) async {
    accepted = accept;
    status = accept ? 'active' : 'rejected';
  }

  @override
  Future<void> endManagementLink(String linkId) async {
    endedLinks.add(linkId);
    status = 'ended';
  }

  @override
  Future<ManagedWorkoutPage> listManagedWorkouts(
    String linkId, {
    String? before,
  }) async {
    historyCursors.add(before);
    await historyGate?.future;
    if (failHistory) throw StateError('Permission revoked');
    if (before != null) {
      return ManagedWorkoutPage(
        workouts: [
          ManagedWorkout(
            key: 'personal:2026-08-11',
            revision: 'older-revision',
            title: '지난달 운동',
            kind: 'personal',
            session: WorkoutSession(
              date: DateTime(2026, 8, 11),
              exercises: _session().exercises,
            ),
            canPropose: false,
            requiresApproval: true,
          ),
        ],
      );
    }
    return ManagedWorkoutPage(
      nextCursor: hasOlderPage ? 'older' : null,
      workouts: [
        ManagedWorkout(
          key: 'personal:2026-09-11',
          revision: 'revision-1',
          title: '개인 운동',
          kind: 'personal',
          session: _session(),
          canPropose: viewer == 'trainer',
          requiresApproval: true,
        ),
      ],
    );
  }

  @override
  Future<List<WorkoutCorrection>> listWorkoutCorrections() async =>
      hasCorrection
      ? [
          WorkoutCorrection(
            id: 'correction',
            memberName: '민지',
            trainerName: '지훈',
            viewerRole: viewer,
            recordKey: 'personal:2026-09-11',
            exerciseId: 'squat',
            correctionKey: '["squat", 1, "weight"]',
            workoutTitle: '개인 운동',
            date: _day,
            exerciseName: '스쿼트',
            setNumber: 1,
            metric: WorkoutMetric.weight,
            before: 40,
            after: 45,
            reason: '함께 확인한 중량',
            status: correctionAccepted == null
                ? 'pending'
                : correctionAccepted!
                ? 'applied'
                : 'rejected',
            canRespond: viewer == 'member' && correctionAccepted == null,
          ),
        ]
      : [];
  @override
  Future<void> respondWorkoutCorrection(
    String correctionId, {
    required bool accept,
  }) async {
    correctionAccepted = accept;
  }

  @override
  Future<void> proposeWorkoutCorrection({
    required String linkId,
    required ManagedWorkout workout,
    required String exerciseId,
    required int setNumber,
    required WorkoutMetric metric,
    required double value,
    required String reason,
    required String requestId,
  }) async {
    proposedValue = value;
    proposedRevision = workout.revision;
    proposedReason = reason;
    this.requestId = requestId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
