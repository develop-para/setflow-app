import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/data/routine_catalog_repository.dart';
import 'package:setflow/data/supabase_routine_catalog_repository.dart';
import 'package:setflow/screens/member_social_detail_screens.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/common.dart';

const _authorTrainerId = '11111111-1111-4111-8111-111111111111';
const _otherTrainerId = '22222222-2222-4222-8222-222222222222';
const _gymId = '33333333-3333-4333-8333-333333333333';
const _routineId = '44444444-4444-4444-8444-444444444444';

void main() {
  test('catalog mapper preserves trainer, gym, and system authors', () async {
    final trainerRoutine = routineCatalogItemFromSupabaseRow(
      _catalogRow(trainerId: _authorTrainerId),
    );
    final gymRoutine = routineCatalogItemFromSupabaseRow(
      _catalogRow(gymId: _gymId),
    );
    final systemRoutine = routineCatalogItemFromSupabaseRow(_catalogRow());

    expect(trainerRoutine.authorTrainerId, _authorTrainerId);
    expect(trainerRoutine.authorGymId, isNull);
    expect(trainerRoutine.authorType, RoutineAuthorType.trainer);
    expect(gymRoutine.authorTrainerId, isNull);
    expect(gymRoutine.authorGymId, _gymId);
    expect(gymRoutine.authorType, RoutineAuthorType.gym);
    expect(systemRoutine.authorTrainerId, isNull);
    expect(systemRoutine.authorGymId, isNull);
    expect(systemRoutine.authorType, RoutineAuthorType.system);
    expect(
      () => routineCatalogItemFromSupabaseRow(
        _catalogRow(trainerId: _authorTrainerId, gymId: _gymId),
      ),
      throwsFormatException,
    );

    final state = AppState(
      routineCatalogRepository: _FakeRoutineCatalogRepository(trainerRoutine),
    );
    addTearDown(state.dispose);
    await state.initialize();
    expect(state.marketRoutines.single.authorTrainerId, _authorTrainerId);
    expect(state.marketRoutines.single.authorGymId, isNull);
    expect(state.marketRoutines.single.authorType, RoutineAuthorType.trainer);
  });

  testWidgets('trainer-authored routine submits its exact author UUID', (
    tester,
  ) async {
    final repository = _FakeBusinessRepository();
    await _pumpLiveScreen(
      tester,
      repository,
      const ConsultationCreateScreen(
        initialTrainerId: _authorTrainerId,
        initialTargetName: '작성자 정코치',
        routineId: _routineId,
      ),
      trainers: [_trainer(_otherTrainerId, '먼저 노출된 코치')],
    );

    expect(find.text('작성자 정코치'), findsOneWidget);
    await _completeConsultationForm(tester);

    expect(repository.createdInputs, hasLength(1));
    expect(repository.createdInputs.single.trainerId, _authorTrainerId);
    expect(repository.createdInputs.single.gymId, isNull);
    expect(repository.createdInputs.single.routineId, _routineId);
  });

  testWidgets('gym-authored routine submits its exact gym UUID', (
    tester,
  ) async {
    final repository = _FakeBusinessRepository();
    await _pumpLiveScreen(
      tester,
      repository,
      const ConsultationCreateScreen(
        initialGymId: _gymId,
        initialTargetName: '세트플로우 센터',
        routineId: _routineId,
      ),
      trainers: [_trainer(_otherTrainerId, '공개 코치')],
    );

    await _completeConsultationForm(tester);

    expect(repository.createdInputs, hasLength(1));
    expect(repository.createdInputs.single.trainerId, isNull);
    expect(repository.createdInputs.single.gymId, _gymId);
    expect(repository.createdInputs.single.routineId, _routineId);
  });

  testWidgets('system routine requires an explicit public trainer selection', (
    tester,
  ) async {
    final repository = _FakeBusinessRepository();
    await _pumpLiveScreen(
      tester,
      repository,
      const ConsultationCreateScreen(routineId: _routineId),
      trainers: [
        _trainer(_otherTrainerId, '첫 번째 코치'),
        _trainer(_authorTrainerId, '선택할 코치'),
      ],
    );

    expect(find.text('상담 트레이너 검색'), findsOneWidget);
    var submit = tester.widget<AppButton>(
      find.byKey(const ValueKey('consultation-submit')),
    );
    expect(submit.onPressed, isNull);

    await tester.tap(
      find.byKey(
        const ValueKey('consultation-trainer-result-$_authorTrainerId'),
      ),
    );
    await tester.pumpAndSettle();

    submit = tester.widget<AppButton>(
      find.byKey(const ValueKey('consultation-submit')),
    );
    expect(submit.onPressed, isNotNull);
    await _completeConsultationForm(tester);

    expect(repository.createdInputs, hasLength(1));
    expect(repository.createdInputs.single.trainerId, _authorTrainerId);
    expect(repository.createdInputs.single.trainerId, isNot(_otherTrainerId));
  });

  testWidgets('live coaching payment, escrow, and rating CTAs stay disabled', (
    tester,
  ) async {
    final repository = _FakeBusinessRepository();
    final consultation = _consultation(ConsultationStatus.answered);
    final state = await _pumpLiveScreen(
      tester,
      repository,
      ConsultationDetailScreen(consultation: consultation),
    );

    await tester.scrollUntilVisible(
      find.text('연동 준비 중'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('실제 결제·에스크로 API 연동 후 이용할 수 있어요.'), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('coaching-start')))
          .onPressed,
      isNull,
    );
    expect(consultation.status, ConsultationStatus.answered);

    consultation.status = ConsultationStatus.coaching;
    state.notifyListeners();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('평점 연동 준비 중'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text(
        '코칭 상태는 서버 기록으로 표시됩니다. '
        '결제·에스크로 연동은 준비 중입니다.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('coaching-rating')))
          .onPressed,
      isNull,
    );
    expect(find.textContaining('전송 완료'), findsNothing);
  });
}

Map<String, dynamic> _catalogRow({String? trainerId, String? gymId}) => {
  'id': '55555555-5555-4555-8555-555555555555',
  'coaching_routine_id': _routineId,
  'title': '작성자 매핑 루틴',
  'description': '테스트',
  'author_name': '작성자',
  'trainer_id': trainerId,
  'gym_id': gymId,
  'difficulty': 'beginner',
  'access_tier': 'free',
  'coaching_routine': {'id': _routineId, 'exercises': <Object>[]},
};

Future<AppState> _pumpLiveScreen(
  WidgetTester tester,
  _FakeBusinessRepository repository,
  Widget screen, {
  List<PublicTrainer> trainers = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(480, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = AppState(businessRepository: repository)
    ..publicTrainers = trainers;
  addTearDown(state.dispose);
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(theme: SetflowTheme.light, home: screen),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

Future<void> _completeConsultationForm(WidgetTester tester) async {
  await tester.enterText(_formField('운동 목표'), '주 3회 근력 향상');
  await tester.enterText(
    _formField('현재 운동 수준과 경험'),
    '헬스 3년 차이며 주 3회 꾸준히 운동합니다.',
  );
  await tester.enterText(_formField('가장 궁금한 점'), '해당 루틴의 중량 증가 방법을 알고 싶습니다.');
  final submit = find.byKey(const ValueKey('consultation-submit'));
  await tester.ensureVisible(submit);
  await tester.tap(submit);
  await tester.pumpAndSettle();
}

Finder _formField(String label) => find.byWidgetPredicate(
  (widget) => widget is AppTextField && widget.label == label,
  description: 'AppTextField labelled $label',
);

PublicTrainer _trainer(String id, String name) => PublicTrainer(
  profile: TrainerBusinessProfile(
    id: id,
    userId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    displayName: name,
    status: BusinessProfileStatus.verified,
    isPublic: true,
    verified: true,
    rating: 4.9,
    postCount: 1,
    coachingTotal: 10,
  ),
  specialties: const ['근력 향상'],
);

ConsultationData _consultation(ConsultationStatus status) => ConsultationData(
  id: '66666666-6666-4666-8666-666666666666',
  trainerName: '정코치',
  specialty: '근력 향상',
  goal: '벤치프레스 향상',
  level: '중급',
  question: '주간 구성이 궁금합니다.',
  createdAt: DateTime(2026, 8, 16),
  status: status,
  response: '주 3회 구성을 권장합니다.',
);

class _FakeBusinessRepository implements BusinessRepository {
  final List<CreateConsultationInput> createdInputs = [];

  @override
  Future<BusinessConsultation> createConsultation(
    CreateConsultationInput input,
  ) async {
    createdInputs.add(input);
    return BusinessConsultation(
      id: '77777777-7777-4777-8777-777777777777',
      userId: '88888888-8888-4888-8888-888888888888',
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

class _FakeRoutineCatalogRepository implements RoutineCatalogRepository {
  const _FakeRoutineCatalogRepository(this.item);

  final RoutineCatalogItem item;

  @override
  Future<bool> hasActivePaidPlan() async => false;

  @override
  Future<List<RoutineCatalogItem>> listPublished() async => [item];

  @override
  Future<void> updateAccessTier(
    String routineId,
    RoutineCatalogAccessTier accessTier,
  ) async {}
}
