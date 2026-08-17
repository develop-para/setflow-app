import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';

void main() {
  group('top current coaching trainer contract', () {
    test('accepts only the bounded TOP 3 range', () {
      expect(validateTopCoachingTrainerLimit(1), 1);
      expect(validateTopCoachingTrainerLimit(3), 3);
      expect(() => validateTopCoachingTrainerLimit(0), throwsArgumentError);
      expect(() => validateTopCoachingTrainerLimit(4), throwsArgumentError);
    });

    test(
      'AppState preserves server ranking and caches exact trainers',
      () async {
        final repository = _TopTrainerRepository([
          _rankedTrainer('11111111-1111-4111-8111-111111111111', '첫 번째 코치', 7),
          _rankedTrainer('22222222-2222-4222-8222-222222222222', '두 번째 코치', 5),
        ]);
        final state = AppState(businessRepository: repository);
        addTearDown(state.dispose);

        final result = await state.loadTopCoachingTrainers(limit: 2);

        expect(repository.limit, 2);
        expect(result.map((item) => item.activeCoachingCount), [7, 5]);
        expect(
          state.topCoachingTrainers.map((item) => item.trainer.profile.id),
          [
            '11111111-1111-4111-8111-111111111111',
            '22222222-2222-4222-8222-222222222222',
          ],
        );
        expect(state.publicTrainers, hasLength(2));
      },
    );

    test('legacy fallback is deterministic and remains bounded', () async {
      final state = AppState(businessRepository: _LegacyRepository());
      addTearDown(state.dispose);
      state.publicTrainers = [
        _trainer(
          '33333333-3333-4333-8333-333333333333',
          '낮은 평점',
          coachingTotal: 2,
          rating: 4.2,
        ),
        _trainer(
          '22222222-2222-4222-8222-222222222222',
          '동률 두 번째',
          coachingTotal: 5,
          rating: 4.8,
        ),
        _trainer(
          '11111111-1111-4111-8111-111111111111',
          '동률 첫 번째',
          coachingTotal: 5,
          rating: 4.8,
        ),
      ];

      final result = await state.loadTopCoachingTrainers(limit: 2);

      expect(result.map((item) => item.trainer.profile.id), [
        '11111111-1111-4111-8111-111111111111',
        '22222222-2222-4222-8222-222222222222',
      ]);
    });

    test(
      'a slower earlier TOP request cannot overwrite the latest result',
      () async {
        final slow = Completer<List<TopCoachingTrainer>>();
        final latest = [
          _rankedTrainer('22222222-2222-4222-8222-222222222222', '최신 순위 코치', 9),
        ];
        final repository = _SequencedTopTrainerRepository([
          slow.future,
          Future.value(latest),
        ]);
        final state = AppState(businessRepository: repository);
        addTearDown(state.dispose);

        final earlierRequest = state.loadTopCoachingTrainers();
        final latestResult = await state.loadTopCoachingTrainers();
        expect(
          latestResult.single.trainer.profile.id,
          '22222222-2222-4222-8222-222222222222',
        );

        slow.complete([
          _rankedTrainer(
            '11111111-1111-4111-8111-111111111111',
            '느린 이전 코치',
            12,
          ),
        ]);
        final earlierResult = await earlierRequest;

        expect(
          earlierResult.single.trainer.profile.id,
          '22222222-2222-4222-8222-222222222222',
        );
        expect(
          state.topCoachingTrainers.single.trainer.profile.id,
          '22222222-2222-4222-8222-222222222222',
        );
      },
    );

    test(
      'answered status remains completed even before a reply row is present',
      () async {
        final repository = _AnsweredConsultationRepository();
        final state = AppState(
          businessRepository: repository,
          loadBusinessWithoutAuth: true,
        );
        addTearDown(state.dispose);

        await state.initialize();

        expect(state.consultations, hasLength(1));
        expect(state.consultations.single.status, ConsultationStatus.answered);
        expect(state.consultations.single.response, isNull);
      },
    );

    test(
      'a dedicated consultation refresh wins over an older workspace refresh',
      () async {
        final slow = Completer<List<BusinessConsultation>>();
        final latest = [
          _consultation(
            '33333333-3333-4333-8333-333333333333',
            BusinessConsultationStatus.replied,
          ),
        ];
        final repository = _SequencedConsultationRepository([
          slow.future,
          Future.value(latest),
        ]);
        final state = AppState(
          businessRepository: repository,
          loadBusinessWithoutAuth: true,
        );
        addTearDown(state.dispose);

        final workspaceRefresh = state.refreshBusinessDashboard(
          UserRole.member,
        );
        await repository.firstConsultationRequest.future;
        await state.refreshMemberConsultations();

        slow.complete([
          _consultation(
            '44444444-4444-4444-8444-444444444444',
            BusinessConsultationStatus.pending,
          ),
        ]);
        await workspaceRefresh;

        expect(state.memberConsultations, hasLength(1));
        expect(
          state.memberConsultations.single.id,
          '33333333-3333-4333-8333-333333333333',
        );
        expect(state.memberConsultationsError, isNull);
        expect(state.memberConsultationsLoading, isFalse);
      },
    );

    test('migration ranks a minimal auth-only current coaching projection', () {
      final sql = File(
        'supabase/migrations/'
        '20260817000803_list_top_current_coaching_trainers.sql',
      ).readAsStringSync().toLowerCase();

      expect(
        sql,
        contains(
          'create or replace function private.'
          'list_top_current_coaching_trainers',
        ),
      );
      expect(sql, contains('security definer'));
      expect(sql, contains('set search_path = \'\''));
      expect(sql, contains('(select auth.uid()) is null'));
      expect(sql, contains('result_limit < 1 or result_limit > 3'));
      expect(sql, contains("coaching.status = 'active'"));
      expect(sql, contains("now() at time zone 'asia/seoul'"));
      expect(sql, contains('coaching.start_date <= v_today'));
      expect(sql, contains('coaching.end_date >= v_today'));
      expect(sql, contains("trainer.status = 'approved'"));
      expect(sql, contains('and trainer.is_public'));
      expect(sql, contains('left join current_coaching_counts'));
      expect(sql, contains('coalesce(coaching_count.active_count, 0) desc'));
      expect(sql, contains('coalesce(trainer.rating_avg, 0) desc'));
      expect(sql, contains('trainer.id asc'));
      expect(sql, contains('limit result_limit'));
      expect(sql, contains('where status = \'active\''));
      expect(sql, contains('consultations_user_created_id_idx'));
      expect(sql, contains('(user_id, created_at desc, id desc)'));

      final publicWrapper = sql.substring(
        sql.indexOf('create or replace function public.'),
      );
      expect(publicWrapper, contains('security invoker'));
      expect(publicWrapper, isNot(contains('security definer')));
      expect(
        publicWrapper,
        contains('from private.list_top_current_coaching_trainers'),
      );
      expect(sql, contains('from public, anon, authenticated'));
      expect(sql, contains('to authenticated, service_role'));

      final projection = sql.substring(
        sql.indexOf('returns table ('),
        sql.indexOf('language plpgsql'),
      );
      expect(projection, contains('active_coaching_count bigint'));
      expect(projection, isNot(contains('user_id')));
    });
  });
}

BusinessConsultation _consultation(
  String id,
  BusinessConsultationStatus status,
) => BusinessConsultation(
  id: id,
  userId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  trainerId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  status: status,
  isRead: status == BusinessConsultationStatus.replied,
  question: '상담 동시성 확인',
  messages: const [],
);

TopCoachingTrainer _rankedTrainer(
  String id,
  String name,
  int activeCoachingCount,
) => TopCoachingTrainer(
  trainer: _trainer(id, name),
  activeCoachingCount: activeCoachingCount,
);

PublicTrainer _trainer(
  String id,
  String name, {
  int coachingTotal = 0,
  double rating = 4.8,
}) => PublicTrainer(
  profile: TrainerBusinessProfile(
    id: id,
    userId: '',
    displayName: name,
    status: BusinessProfileStatus.approved,
    isPublic: true,
    verified: true,
    rating: rating,
    postCount: 0,
    coachingTotal: coachingTotal,
  ),
);

class _TopTrainerRepository
    implements BusinessRepository, TopCoachingTrainerRepository {
  _TopTrainerRepository(this.result);

  final List<TopCoachingTrainer> result;
  int? limit;

  @override
  Future<List<TopCoachingTrainer>> listTopCoachingTrainers({
    int limit = 3,
  }) async {
    this.limit = limit;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LegacyRepository implements BusinessRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SequencedTopTrainerRepository
    implements BusinessRepository, TopCoachingTrainerRepository {
  _SequencedTopTrainerRepository(this.results);

  final List<Future<List<TopCoachingTrainer>>> results;
  var callCount = 0;

  @override
  Future<List<TopCoachingTrainer>> listTopCoachingTrainers({int limit = 3}) {
    return results[callCount++];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AnsweredConsultationRepository implements BusinessRepository {
  @override
  Future<BusinessAccess> loadAccess() async => const BusinessAccess(
    userId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    accountRole: UserRole.member,
    resolvedRole: UserRole.member,
    availableRoles: {UserRole.member},
  );

  @override
  Future<List<PublicTrainer>> listPublicTrainers() async => const [];

  @override
  Future<List<BusinessConsultation>> listMyConsultations() async => [
    BusinessConsultation(
      id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      userId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      status: BusinessConsultationStatus.answered,
      isRead: true,
      trainerName: '답변 완료 코치',
      question: '답변 상태 동기화 확인',
      messages: const [],
    ),
  ];

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

class _SequencedConsultationRepository implements BusinessRepository {
  _SequencedConsultationRepository(this.results);

  final List<Future<List<BusinessConsultation>>> results;
  final firstConsultationRequest = Completer<void>();
  var consultationCalls = 0;

  @override
  Future<BusinessAccess> loadAccess() async => const BusinessAccess(
    userId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    accountRole: UserRole.member,
    resolvedRole: UserRole.member,
    availableRoles: {UserRole.member},
  );

  @override
  Future<List<PublicTrainer>> listPublicTrainers() async => const [];

  @override
  Future<List<BusinessConsultation>> listMyConsultations() {
    consultationCalls++;
    if (consultationCalls == 1) firstConsultationRequest.complete();
    return results[consultationCalls - 1];
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
