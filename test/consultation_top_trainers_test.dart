import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/screens/member_social_detail_screens.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/common.dart';

const _firstTrainerId = '11111111-1111-4111-8111-111111111111';
const _secondTrainerId = '22222222-2222-4222-8222-222222222222';
const _thirdTrainerId = '33333333-3333-4333-8333-333333333333';
const _searchTrainerId = '44444444-4444-4444-8444-444444444444';

void main() {
  testWidgets('TOP 3 renders in server order with current coaching counts', (
    tester,
  ) async {
    final repository = _TopTrainerBusinessRepository(
      onTop: (_) async => [
        _top(_thirdTrainerId, '서버 1위', 18),
        _top(_firstTrainerId, '서버 2위', 11),
        _top(_secondTrainerId, '서버 3위', 7),
      ],
      onSearch: (query, _, _) async => PublicTrainerSearchPage(
        items: query == '검색 코치'
            ? [_trainer(_searchTrainerId, '검색 코치')]
            : const [],
      ),
    );
    final state = await _pumpTopScreen(tester, repository);

    expect(repository.topLimits, [3]);
    expect(
      find.byKey(const ValueKey('consultation-top-trainers')),
      findsOneWidget,
    );
    final first = find.byKey(
      const ValueKey('consultation-top-trainer-$_thirdTrainerId'),
    );
    final second = find.byKey(
      const ValueKey('consultation-top-trainer-$_firstTrainerId'),
    );
    final third = find.byKey(
      const ValueKey('consultation-top-trainer-$_secondTrainerId'),
    );
    expect(state.topCoachingTrainers.map((item) => item.trainer.profile.id), [
      _thirdTrainerId,
      _firstTrainerId,
      _secondTrainerId,
    ]);
    expect(first, findsOneWidget);
    expect(
      find.descendant(of: first, matching: find.text('1')),
      findsOneWidget,
    );
    expect(find.text('현재 코칭 18건'), findsOneWidget);
    expect(second, findsOneWidget);
    expect(
      find.descendant(of: second, matching: find.text('2')),
      findsOneWidget,
    );
    expect(find.text('현재 코칭 11건'), findsOneWidget);
    expect(third, findsOneWidget);
    expect(
      find.descendant(of: third, matching: find.text('3')),
      findsOneWidget,
    );
    expect(find.text('현재 코칭 7건'), findsOneWidget);
    expect(tester.getTopLeft(first).dx, lessThan(tester.getTopLeft(second).dx));
    expect(tester.getTopLeft(second).dx, lessThan(tester.getTopLeft(third).dx));

    final search = find.byKey(const ValueKey('consultation-trainer-search'));
    await tester.ensureVisible(search);
    await tester.enterText(search, '검색 코치');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(repository.searchCalls.last.query, '검색 코치');
    expect(
      find.byKey(
        const ValueKey('consultation-trainer-result-$_searchTrainerId'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('selecting a TOP trainer submits its exact trainer UUID', (
    tester,
  ) async {
    final repository = _TopTrainerBusinessRepository(
      onTop: (_) async => [
        _top(_firstTrainerId, '동명이인 코치', 12),
        _top(_secondTrainerId, '동명이인 코치', 9),
      ],
      onSearch: (_, _, _) async => const PublicTrainerSearchPage(items: []),
    );
    await _pumpTopScreen(tester, repository);

    final target = find.byKey(
      const ValueKey('consultation-top-trainer-$_secondTrainerId'),
    );
    await tester.tap(target);
    await tester.pump();

    await tester.enterText(_formField('운동 목표'), '주 3회 근력 향상');
    await tester.enterText(
      _formField('현재 운동 수준과 경험'),
      '헬스 3년 차이며 주 3회 꾸준히 운동합니다.',
    );
    await tester.enterText(
      _formField('가장 궁금한 점'),
      '벤치프레스 중량 증가 방법을 자세히 알고 싶습니다.',
    );
    final submit = find.byKey(const ValueKey('consultation-submit'));
    await tester.ensureVisible(submit);
    expect(tester.widget<AppButton>(submit).onPressed, isNotNull);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(repository.createdInputs, hasLength(1));
    expect(repository.createdInputs.single.trainerId, _secondTrainerId);
    expect(repository.createdInputs.single.trainerId, isNot(_firstTrainerId));
  });

  testWidgets('TOP trainers exposes loading and empty states', (tester) async {
    final response = Completer<List<TopCoachingTrainer>>();
    final repository = _TopTrainerBusinessRepository(
      onTop: (_) => response.future,
      onSearch: (_, _, _) async => const PublicTrainerSearchPage(items: []),
    );
    await _pumpTopScreen(tester, repository);

    expect(
      find.byKey(const ValueKey('consultation-top-trainers-loading')),
      findsOneWidget,
    );

    response.complete(const []);
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('consultation-top-trainers-empty')),
      findsOneWidget,
    );
    expect(find.text('현재 상담 가능한 트레이너가 없어요.'), findsOneWidget);
  });

  testWidgets('TOP trainer error retries independently and recovers', (
    tester,
  ) async {
    var failedOnce = false;
    final repository = _TopTrainerBusinessRepository(
      onTop: (_) async {
        if (!failedOnce) {
          failedOnce = true;
          throw StateError('ranking unavailable');
        }
        return [_top(_thirdTrainerId, '복구된 1위 코치', 6)];
      },
      onSearch: (query, _, _) async => PublicTrainerSearchPage(
        items: query == '검색 유지'
            ? [_trainer(_searchTrainerId, '검색 유지')]
            : const [],
      ),
    );
    await _pumpTopScreen(tester, repository);

    expect(
      find.byKey(const ValueKey('consultation-top-trainers-error')),
      findsOneWidget,
    );
    expect(find.text('현재 코칭 TOP 3를 불러오지 못했어요.'), findsOneWidget);

    final search = find.byKey(const ValueKey('consultation-trainer-search'));
    await tester.ensureVisible(search);
    await tester.enterText(search, '검색 유지');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(
      find.byKey(
        const ValueKey('consultation-trainer-result-$_searchTrainerId'),
      ),
      findsOneWidget,
    );

    final retry = find.byKey(const ValueKey('consultation-top-trainers-retry'));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pump();
    await tester.pump();

    expect(repository.topLimits, [3, 3]);
    expect(
      find.byKey(const ValueKey('consultation-top-trainer-$_thirdTrainerId')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('consultation-top-trainers-error')),
      findsNothing,
    );
  });

  testWidgets('TOP trainer cards grow without overflow at large text scale', (
    tester,
  ) async {
    final repository = _TopTrainerBusinessRepository(
      onTop: (_) async => [_top(_firstTrainerId, '아주 긴 이름의 접근성 테스트 트레이너', 12)],
      onSearch: (_, _, _) async => const PublicTrainerSearchPage(items: []),
    );

    await _pumpTopScreen(
      tester,
      repository,
      surfaceSize: const Size(360, 1200),
      textScaler: const TextScaler.linear(2),
    );

    final card = find.byKey(
      const ValueKey('consultation-top-trainer-$_firstTrainerId'),
    );
    expect(card, findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(card).height, greaterThan(154));
  });
}

Finder _formField(String label) => find.byWidgetPredicate(
  (widget) => widget is AppTextField && widget.label == label,
  description: 'AppTextField labelled $label',
);

Future<AppState> _pumpTopScreen(
  WidgetTester tester,
  _TopTrainerBusinessRepository repository, {
  Size surfaceSize = const Size(520, 1400),
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = AppState(businessRepository: repository);
  addTearDown(state.dispose);
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(
        theme: SetflowTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: const ConsultationCreateScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  return state;
}

TopCoachingTrainer _top(String id, String name, int activeCount) =>
    TopCoachingTrainer(
      trainer: _trainer(id, name),
      activeCoachingCount: activeCount,
    );

PublicTrainer _trainer(String id, String name) => PublicTrainer(
  profile: TrainerBusinessProfile(
    id: id,
    userId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    displayName: name,
    status: BusinessProfileStatus.approved,
    isPublic: true,
    verified: true,
    rating: 4.9,
    postCount: 3,
    coachingTotal: 20,
    centerName: '세트플로우 센터',
    keyword: '근력 향상',
  ),
  specialties: const ['근력 향상'],
);

typedef _TopHandler = Future<List<TopCoachingTrainer>> Function(int limit);
typedef _SearchHandler =
    Future<PublicTrainerSearchPage> Function(
      String query,
      String? cursor,
      int pageSize,
    );

class _TopTrainerBusinessRepository
    implements
        BusinessRepository,
        TopCoachingTrainerRepository,
        PublicTrainerSearchRepository {
  _TopTrainerBusinessRepository({required this.onTop, required this.onSearch});

  final _TopHandler onTop;
  final _SearchHandler onSearch;
  final List<int> topLimits = [];
  final List<({String query, String? cursor, int pageSize})> searchCalls = [];
  final List<CreateConsultationInput> createdInputs = [];

  @override
  Future<List<TopCoachingTrainer>> listTopCoachingTrainers({int limit = 3}) {
    topLimits.add(limit);
    return onTop(limit);
  }

  @override
  Future<PublicTrainerSearchPage> searchPublicTrainers({
    String query = '',
    String? cursor,
    int pageSize = 20,
  }) {
    searchCalls.add((query: query, cursor: cursor, pageSize: pageSize));
    return onSearch(query, cursor, pageSize);
  }

  @override
  Future<BusinessConsultation> createConsultation(
    CreateConsultationInput input,
  ) async {
    createdInputs.add(input);
    return BusinessConsultation(
      id: '55555555-5555-4555-8555-555555555555',
      userId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      trainerId: input.trainerId,
      gymId: input.gymId,
      routineId: input.routineId,
      status: BusinessConsultationStatus.pending,
      isRead: false,
      question: input.question,
      messages: const [],
    );
  }

  @override
  Future<List<BusinessConsultation>> listMyConsultations() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
