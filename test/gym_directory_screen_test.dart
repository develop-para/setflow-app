import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/gym_directory_repository.dart';
import 'package:setflow/domain/gym_directory.dart';
import 'package:setflow/screens/gym_directory_screen.dart';
import 'package:setflow/services/auth_service.dart';
import 'package:setflow/theme.dart';

const _gym = GymPlace(
  id: 'public-gangnam',
  name: '셋플로우 피트니스',
  aliases: ['인허가 상호'],
  address: '서울특별시 강남구 테헤란로 18',
  region: '서울특별시',
  district: '강남구',
);
const _otherGym = GymPlace(
  id: 'public-busan',
  name: '부산 피트니스',
  address: '부산광역시 해운대구 센텀로 18',
  region: '부산광역시',
);
const _source = GymDirectorySource(
  label: '행안부 인허가 자료 · 제공자 보완',
  fileName: 'provided.xlsx',
  sha256: 'source-hash',
);

class _Directory implements GymDirectoryRepository {
  _Directory({this.gyms = const [_gym, _otherGym]});

  final List<GymPlace> gyms;
  bool fail = false;
  int loads = 0;

  @override
  Future<GymDirectoryCatalog> loadCatalog() async {
    loads++;
    if (fail) throw StateError('목록을 읽을 수 없어요.');
    return GymDirectoryCatalog(source: _source, gyms: gyms);
  }
}

class _Requests implements GymDirectoryRequestRepository {
  bool available = true;
  bool fail = false;
  final attempts = <GymDirectoryRequest>[];
  final receivedAt = DateTime.utc(2026, 10, 6, 3);

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<DateTime> submitRequest(GymDirectoryRequest request) async {
    attempts.add(request);
    if (fail) throw StateError('네트워크 오류');
    return receivedAt;
  }
}

class _Auth extends Fake implements AuthService {
  _Auth(this.user);

  AuthUser? user;

  @override
  AuthUser? get currentUser => user;

  @override
  bool get hasAuthenticatedUser => user != null;

  @override
  String get currentDisplayName => user?.displayName ?? '회원';

  @override
  Future<void> signOut() async => user = null;
}

Future<void> _pump(
  WidgetTester tester,
  AppState state,
  Widget screen, {
  double textScale = 1,
  double keyboardInset = 0,
  Size surfaceSize = const Size(432, 1000),
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await state.loadGymPlaces();
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(
        theme: SetflowTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            viewInsets: EdgeInsets.only(bottom: keyboardInset),
          ),
          child: child!,
        ),
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapSave(WidgetTester tester, {bool settle = true}) async {
  final save = find.byKey(const ValueKey('gym-directory-request-save'));
  await tester.ensureVisible(save);
  await tester.tap(save);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  setUp(Auth.reset);
  tearDown(Auth.reset);

  testWidgets(
    'guest searches aliases and address together then saves a place',
    (tester) async {
      final store = MemoryGymPlaceRepository();
      final state = AppState(
        gymDirectoryRepository: _Directory(),
        gymPlaceRepository: store,
      );
      addTearDown(state.dispose);
      await _pump(tester, state, const GymDirectoryScreen());

      await tester.enterText(
        find.byKey(const ValueKey('gym-directory-search')),
        '강남 인허가',
      );
      await tester.pumpAndSettle();
      expect(find.text(_gym.name), findsOneWidget);
      expect(find.text(_otherGym.name), findsNothing);
      expect(find.byKey(const ValueKey('auth-gate-sign-in')), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('gym-directory-place-public-gangnam')),
      );
      await tester.pumpAndSettle();
      final restored = await store.load();
      expect(restored.selectedGym?.id, _gym.id);
      expect(restored.selectedGym?.address, _gym.address);
      expect(state.memberMemberships, isEmpty);
      expect(find.byKey(const ValueKey('auth-gate-sign-in')), findsNothing);
    },
  );

  testWidgets('directory loading failure has a working retry', (tester) async {
    final directory = _Directory()..fail = true;
    final state = AppState(gymDirectoryRepository: directory);
    addTearDown(state.dispose);
    await _pump(tester, state, const GymDirectoryScreen());
    expect(find.text('헬스장 목록을 불러오지 못했어요.'), findsOneWidget);

    directory.fail = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text(_gym.name), findsOneWidget);
    expect(directory.loads, 2);
  });

  testWidgets('region selection filters the directory with large text', (
    tester,
  ) async {
    final state = AppState(gymDirectoryRepository: _Directory());
    addTearDown(state.dispose);
    await _pump(tester, state, const GymDirectoryScreen(), textScale: 2);
    await tester.tap(find.byKey(const ValueKey('gym-directory-region')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('부산광역시').last);
    await tester.pumpAndSettle();
    expect(find.text(_otherGym.name), findsOneWidget);
    expect(find.text(_gym.name), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('more places loads the next page without losing the query', (
    tester,
  ) async {
    final gyms = List.generate(
      65,
      (index) => GymPlace(
        id: 'public-$index',
        name: '목록 헬스장 $index',
        address: '서울특별시 강남구 테스트로 $index',
        region: '서울특별시',
      ),
    );
    final state = AppState(gymDirectoryRepository: _Directory(gyms: gyms));
    addTearDown(state.dispose);
    await _pump(tester, state, const GymDirectoryScreen());
    await tester.enterText(
      find.byKey(const ValueKey('gym-directory-search')),
      '목록',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('gym-directory-more')),
      600,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('gym-directory-results')),
            matching: find.byType(Scrollable),
          )
          .first,
      maxScrolls: 30,
    );
    await tester.pumpAndSettle();
    expect(find.text('목록 헬스장 64'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('gym-directory-more')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('목록 헬스장 64'),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('gym-directory-results')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('목록 헬스장 64'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('gym-directory-search')),
      -600,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('gym-directory-results')),
            matching: find.byType(Scrollable),
          )
          .first,
      maxScrolls: 30,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('gym-directory-search')))
          .controller!
          .text,
      '목록',
    );
  });

  testWidgets('search remains scrollable with large text and a keyboard', (
    tester,
  ) async {
    final state = AppState(gymDirectoryRepository: _Directory());
    addTearDown(state.dispose);
    await _pump(
      tester,
      state,
      const GymDirectoryScreen(),
      textScale: 2,
      keyboardInset: 280,
      surfaceSize: const Size(360, 640),
    );
    await tester.enterText(
      find.byKey(const ValueKey('gym-directory-search')),
      '강남 인허가',
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(_gym.name),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('gym-directory-results')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text(_gym.name), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing gym draft validates and survives an AppState restart', (
    tester,
  ) async {
    final store = MemoryGymPlaceRepository();
    final state = AppState(gymPlaceRepository: store);
    addTearDown(state.dispose);
    await _pump(
      tester,
      state,
      const GymDirectoryRequestScreen(kind: GymDirectoryRequestKind.add),
    );
    await _tapSave(tester);
    expect(find.text('헬스장 이름을 입력해주세요.'), findsOneWidget);
    expect(state.gymDirectoryRequests, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('gym-directory-request-name')),
      '새로 연 헬스장',
    );
    await tester.enterText(
      find.byKey(const ValueKey('gym-directory-request-address')),
      '서울특별시 서초구 강남대로 18',
    );
    await _tapSave(tester);
    expect(find.text('기기에 보관됨 · 아직 보내지 않음'), findsOneWidget);
    expect(find.text('운영팀에 접수됨'), findsNothing);
    expect(find.byKey(const ValueKey('auth-gate-sign-in')), findsNothing);

    final restarted = AppState(gymPlaceRepository: store);
    addTearDown(restarted.dispose);
    await restarted.loadGymPlaces();
    expect(restarted.gymDirectoryRequests.single.gymName, '새로 연 헬스장');
    expect(restarted.gymDirectoryRequests.single.submittedAt, isNull);
    expect(restarted.gymDirectoryRequests.single.ownerUserId, isNull);
  });

  testWidgets(
    'guest draft is saved before sign in and is not called received',
    (tester) async {
      final requests = _Requests();
      final state = AppState(gymDirectoryRequestRepository: requests);
      addTearDown(state.dispose);
      await _pump(
        tester,
        state,
        const GymDirectoryRequestScreen(
          kind: GymDirectoryRequestKind.correction,
          gym: _gym,
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('gym-directory-request-note')),
        '도로명 주소의 건물 번호를 확인해주세요.',
      );
      await _tapSave(tester, settle: false);
      expect(find.byKey(const ValueKey('auth-gate-sign-in')), findsOneWidget);
      expect(state.gymDirectoryRequests, hasLength(1));
      expect(state.gymDirectoryRequests.single.facilityId, _gym.id);
      expect(requests.attempts, isEmpty);

      await tester.tap(find.byKey(const ValueKey('auth-gate-dismiss')));
      await tester.pumpAndSettle();
      expect(find.text('기기에 보관됨 · 아직 보내지 않음'), findsOneWidget);
      expect(find.text('운영팀에 접수됨'), findsNothing);
    },
  );

  testWidgets('failed owner claim retries the same draft and stores receipt', (
    tester,
  ) async {
    Auth.use(_Auth(const AuthUser(id: 'owner-1', displayName: '운영자')));
    final requests = _Requests()..fail = true;
    final store = MemoryGymPlaceRepository();
    final state = AppState(
      gymPlaceRepository: store,
      gymDirectoryRequestRepository: requests,
    );
    addTearDown(state.dispose);
    await _pump(
      tester,
      state,
      const GymDirectoryRequestScreen(
        kind: GymDirectoryRequestKind.claim,
        gym: _gym,
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('gym-directory-request-note')),
      '강남 지점 운영자입니다. 홈페이지에서 운영 지점을 확인할 수 있어요.',
    );
    await _tapSave(tester);
    expect(find.text('기기에 보관됨 · 아직 보내지 않음'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gym-directory-request-error')),
      findsOneWidget,
    );
    expect(requests.attempts, hasLength(1));
    expect(
      state.gymDirectoryRequests.single.kind,
      GymDirectoryRequestKind.claim,
    );
    expect(
      state.businessAccess?.availableRoles ?? const <UserRole>[],
      isNot(contains(UserRole.gym)),
    );

    requests.fail = false;
    await tester.ensureVisible(
      find.byKey(const ValueKey('gym-directory-request-retry')),
    );
    await tester.tap(find.byKey(const ValueKey('gym-directory-request-retry')));
    await tester.pumpAndSettle();
    expect(requests.attempts, hasLength(2));
    expect(requests.attempts.first.id, requests.attempts.last.id);
    expect(find.text('운영팀에 접수됨'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gym-directory-request-error')),
      findsNothing,
    );

    final restored = await store.load();
    expect(restored.requests.single.ownerUserId, 'owner-1');
    expect(restored.requests.single.submittedAt, requests.receivedAt);
  });

  testWidgets('request list hides drafts and receipts of another account', (
    tester,
  ) async {
    Auth.use(_Auth(const AuthUser(id: 'owner-1', displayName: '운영자')));
    final state = AppState(
      gymPlaceRepository: MemoryGymPlaceRepository(
        initialValue: GymPlaceLibrary(
          requests: [
            GymDirectoryRequest(
              id: 'own-draft',
              kind: GymDirectoryRequestKind.add,
              gymName: '내 계정의 제안',
              address: _gym.address,
              note: '',
              createdAt: DateTime.utc(2026, 10, 6),
              ownerUserId: 'owner-1',
            ),
            GymDirectoryRequest(
              id: 'other-receipt',
              kind: GymDirectoryRequestKind.add,
              gymName: '다른 계정의 제안',
              address: _gym.address,
              note: '이전 사용자의 내용',
              createdAt: DateTime.utc(2026, 10, 5),
              submittedAt: DateTime.utc(2026, 10, 5),
              ownerUserId: 'owner-2',
            ),
          ],
        ),
      ),
    );
    addTearDown(state.dispose);
    await _pump(tester, state, const GymDirectoryRequestsScreen());
    expect(find.text('내 계정의 제안'), findsOneWidget);
    expect(find.text('다른 계정의 제안'), findsNothing);
    expect(find.text('이전 사용자의 내용'), findsNothing);
  });

  testWidgets('public details identify unknown dates and handle large text', (
    tester,
  ) async {
    final state = AppState(gymDirectoryRepository: _Directory());
    addTearDown(state.dispose);
    await _pump(
      tester,
      state,
      const GymPlaceDetailScreen(gym: _gym, source: _source),
      textScale: 2,
    );
    expect(find.text('출처: ${_source.label}'), findsOneWidget);
    expect(find.text('자료 기준일 미등록'), findsOneWidget);
    expect(find.text('자료 확인일 미등록'), findsOneWidget);
    expect(find.text('영업 중'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('사업주 확인 신청'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
