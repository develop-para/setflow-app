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

void main() {
  testWidgets('trainer search debounces and renders only the latest query', (
    tester,
  ) async {
    final repository = _SearchBusinessRepository(
      onSearch: (query, _, _) async => PublicTrainerSearchPage(
        items: query == '근력 코치'
            ? [_trainer(_secondTrainerId, '근력 코치')]
            : const [],
      ),
    );
    await _pumpSearchScreen(tester, repository);
    repository.searchCalls.clear();

    await tester.enterText(
      find.byKey(const ValueKey('consultation-trainer-search')),
      '근력',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(
      find.byKey(const ValueKey('consultation-trainer-search')),
      '  근력   코치  ',
    );

    await tester.pump(const Duration(milliseconds: 299));
    expect(repository.searchCalls, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(repository.searchCalls, hasLength(1));
    expect(repository.searchCalls.single.query, '근력 코치');
    expect(
      find.byKey(
        const ValueKey('consultation-trainer-result-$_secondTrainerId'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a slow stale response cannot replace a newer search result', (
    tester,
  ) async {
    final firstResponse = Completer<PublicTrainerSearchPage>();
    final secondResponse = Completer<PublicTrainerSearchPage>();
    final repository = _SearchBusinessRepository(
      onSearch: (query, _, _) {
        return switch (query) {
          '첫 검색' => firstResponse.future,
          '둘째 검색' => secondResponse.future,
          _ => Future.value(const PublicTrainerSearchPage(items: [])),
        };
      },
    );
    await _pumpSearchScreen(tester, repository);

    await _typeDebouncedQuery(tester, '첫 검색');
    await _typeDebouncedQuery(tester, '둘째 검색');
    expect(
      repository.searchCalls.map((call) => call.query),
      containsAllInOrder(['첫 검색', '둘째 검색']),
    );

    secondResponse.complete(
      PublicTrainerSearchPage(items: [_trainer(_secondTrainerId, '최신 검색 코치')]),
    );
    await tester.pump();
    expect(
      find.byKey(
        const ValueKey('consultation-trainer-result-$_secondTrainerId'),
      ),
      findsOneWidget,
    );

    firstResponse.complete(
      PublicTrainerSearchPage(items: [_trainer(_firstTrainerId, '느린 이전 코치')]),
    );
    await tester.pump();

    expect(
      find.byKey(
        const ValueKey('consultation-trainer-result-$_secondTrainerId'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('consultation-trainer-result-$_firstTrainerId'),
      ),
      findsNothing,
    );
  });

  testWidgets('an empty search can be cleared back to the public directory', (
    tester,
  ) async {
    final repository = _SearchBusinessRepository(
      onSearch: (query, _, _) async => PublicTrainerSearchPage(
        items: query.isEmpty
            ? [_trainer(_firstTrainerId, '전체 목록 코치')]
            : const [],
      ),
    );
    await _pumpSearchScreen(tester, repository);

    await _typeDebouncedQuery(tester, '존재하지 않는 트레이너');
    expect(find.text('검색 결과가 없어요'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('consultation-trainer-clear')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(repository.searchCalls.last.query, isEmpty);
    expect(
      find.byKey(
        const ValueKey('consultation-trainer-result-$_firstTrainerId'),
      ),
      findsOneWidget,
    );
    expect(find.text('검색 결과가 없어요'), findsNothing);
  });

  testWidgets('trainer search error exposes retry and recovers', (
    tester,
  ) async {
    var failedOnce = false;
    final repository = _SearchBusinessRepository(
      onSearch: (query, _, _) async {
        if (query == '재시도' && !failedOnce) {
          failedOnce = true;
          throw StateError('directory unavailable');
        }
        return PublicTrainerSearchPage(
          items: query == '재시도'
              ? [_trainer(_secondTrainerId, '복구된 코치')]
              : const [],
        );
      },
    );
    await _pumpSearchScreen(tester, repository);

    await _typeDebouncedQuery(tester, '재시도');
    expect(
      find.byKey(const ValueKey('consultation-trainer-retry')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('consultation-trainer-retry')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(
      repository.searchCalls.where((call) => call.query == '재시도'),
      hasLength(2),
    );
    expect(
      find.byKey(
        const ValueKey('consultation-trainer-result-$_secondTrainerId'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('consultation-trainer-retry')),
      findsNothing,
    );
  });

  testWidgets('selected search result submits its exact trainer UUID', (
    tester,
  ) async {
    final repository = _SearchBusinessRepository(
      onSearch: (query, _, _) async => PublicTrainerSearchPage(
        items: query == '동명이인'
            ? [
                _trainer(_firstTrainerId, '정코치'),
                _trainer(_secondTrainerId, '정코치'),
              ]
            : const [],
      ),
    );
    await _pumpSearchScreen(tester, repository);
    await _typeDebouncedQuery(tester, '동명이인');

    final target = find.byKey(
      const ValueKey('consultation-trainer-result-$_secondTrainerId'),
    );
    await tester.ensureVisible(target);
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
}

Finder _formField(String label) => find.byWidgetPredicate(
  (widget) => widget is AppTextField && widget.label == label,
  description: 'AppTextField labelled $label',
);

Future<void> _typeDebouncedQuery(WidgetTester tester, String query) async {
  await tester.enterText(
    find.byKey(const ValueKey('consultation-trainer-search')),
    query,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

Future<AppState> _pumpSearchScreen(
  WidgetTester tester,
  _SearchBusinessRepository repository,
) async {
  await tester.binding.setSurfaceSize(const Size(480, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = AppState(businessRepository: repository);
  addTearDown(state.dispose);
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(
        theme: SetflowTheme.light,
        home: const ConsultationCreateScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  return state;
}

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

typedef _SearchHandler =
    Future<PublicTrainerSearchPage> Function(
      String query,
      String? cursor,
      int pageSize,
    );

class _SearchBusinessRepository
    implements BusinessRepository, PublicTrainerSearchRepository {
  _SearchBusinessRepository({required this.onSearch});

  final _SearchHandler onSearch;
  final List<({String query, String? cursor, int pageSize})> searchCalls = [];
  final List<CreateConsultationInput> createdInputs = [];

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
      id: '33333333-3333-4333-8333-333333333333',
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
