import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/data/gym_directory_repository.dart';
import 'package:setflow/domain/gym_directory.dart';
import 'package:setflow/screens/gym_directory_screen.dart';
import 'package:setflow/screens/member_membership_screen.dart';
import 'package:setflow/screens/member_mypage_screen.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/screens/member_social_detail_screens.dart';
import 'package:setflow/services/auth_service.dart';
import 'package:setflow/theme.dart';

const _first = GymPlace(
  id: 'public:first',
  name: '첫 운동 장소',
  address: '서울특별시 강남구 테헤란로 18',
  region: '서울특별시',
);
const _second = GymPlace(
  id: 'public:second',
  name: '둘째 운동 장소',
  address: '서울특별시 서초구 강남대로 18',
  region: '서울특별시',
);

class _Directory implements GymDirectoryRepository {
  @override
  Future<GymDirectoryCatalog> loadCatalog() async => GymDirectoryCatalog(
    source: const GymDirectorySource(
      label: '제공자 목록',
      fileName: 'provided.xlsx',
      sha256: 'source-hash',
    ),
    gyms: const [_first, _second],
  );
}

class _Auth extends Fake implements AuthService {
  AuthUser? user = const AuthUser(id: 'member-1', displayName: '운동 회원');
  int signOuts = 0;

  @override
  AuthUser? get currentUser => user;

  @override
  bool get hasAuthenticatedUser => user != null;

  @override
  String get currentDisplayName => user?.displayName ?? '회원';

  @override
  Future<void> signOut() async {
    signOuts++;
    user = null;
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<void> _pump(WidgetTester tester, AppState state, Widget screen) async {
  await tester.binding.setSurfaceSize(const Size(432, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await state.loadGymPlaces();
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(theme: SetflowTheme.light, home: screen),
    ),
  );
  await _settle(tester);
}

Finder _headerText(String name) => find.descendant(
  of: find.byKey(const ValueKey('home-workout-location')),
  matching: find.text(name),
);

void main() {
  setUp(Auth.reset);
  tearDown(Auth.reset);

  testWidgets('guest opens public gym search from My Page without a gate', (
    tester,
  ) async {
    final state = AppState(gymDirectoryRepository: _Directory());
    addTearDown(state.dispose);
    await _pump(tester, state, const MyPageScreen());
    await tester.ensureVisible(find.text('운동 장소 및 센터'));
    await tester.tap(find.text('운동 장소 및 센터'));
    await _settle(tester);

    expect(find.byType(MemberMembershipScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-gate-sign-in')), findsNothing);
    await tester.tap(find.text('헬스장 찾기'));
    await _settle(tester);
    expect(find.byType(GymDirectoryScreen), findsOneWidget);
    expect(find.text(_first.name), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-gate-sign-in')), findsNothing);
  });

  testWidgets(
    'empty home header opens search and saves the chosen place name',
    (tester) async {
      final store = MemoryGymPlaceRepository();
      final state = AppState(
        gymDirectoryRepository: _Directory(),
        gymPlaceRepository: store,
      );
      addTearDown(state.dispose);
      await _pump(tester, state, const MemberShell());
      expect(_headerText('운동 장소'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('home-workout-location')));
      await _settle(tester);
      expect(find.byType(GymDirectoryScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('find-workout-place')), findsNothing);
      await tester.tap(
        find.byKey(ValueKey('gym-directory-place-${_first.id}')),
      );
      await _settle(tester);

      expect(find.byType(GymDirectoryScreen), findsNothing);
      expect(_headerText(_first.name), findsOneWidget);
      expect((await store.load()).selectedGym?.id, _first.id);
      expect(state.currentWorkoutLocation, isNull);
      expect(state.memberMemberships, isEmpty);
      expect(find.byKey(const ValueKey('auth-gate-sign-in')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('header favourites stay selected through logout and reopening', (
    tester,
  ) async {
    final auth = _Auth();
    Auth.use(auth);
    final store = MemoryGymPlaceRepository(
      initialValue: GymPlaceLibrary(
        gyms: const [_first, _second],
        selectedId: _first.id,
      ),
    );
    final state = AppState(gymPlaceRepository: store)..role = UserRole.member;
    addTearDown(state.dispose);
    await _pump(tester, state, const MemberShell());
    expect(_headerText(_first.name), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-workout-location')));
    await _settle(tester);
    expect(
      find.byKey(ValueKey('header-public-gym-${_first.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('header-public-gym-${_second.id}')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(ValueKey('header-public-gym-${_second.id}')));
    await _settle(tester);
    expect(_headerText(_second.name), findsOneWidget);
    expect((await store.load()).selectedId, _second.id);

    await state.logout();
    await _settle(tester);
    expect(auth.signOuts, 1);
    expect(Auth.instance.hasAuthenticatedUser, isFalse);
    expect(state.role, UserRole.guest);
    expect(_headerText(_second.name), findsOneWidget);
    expect(state.memberMemberships, isEmpty);

    final restarted = AppState(gymPlaceRepository: store);
    addTearDown(restarted.dispose);
    await _pump(tester, restarted, const MemberShell());
    expect(_headerText(_second.name), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-workout-location')));
    await _settle(tester);
    expect(
      find.byKey(ValueKey('header-public-gym-${_first.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('header-public-gym-${_second.id}')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(ValueKey('header-public-gym-${_first.id}')));
    await _settle(tester);
    expect(_headerText(_first.name), findsOneWidget);
    expect((await store.load()).selectedId, _first.id);
    expect(find.byKey(const ValueKey('auth-gate-sign-in')), findsNothing);
    expect(restarted.businessAccess, isNull);
    expect(restarted.memberMemberships, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'public choice does not preselect a business gym for consultation',
    (tester) async {
      const businessGymId = '22222222-2222-4222-8222-222222222222';
      final state = AppState()
        ..workoutLocations = const [
          MemberWorkoutLocation(
            id: 'member-location',
            userId: 'member-1',
            gymId: businessGymId,
            gymName: '연결된 인증 센터',
            gymAddress: '서울특별시 강남구',
            isActive: true,
          ),
        ]
        ..serviceRegions = const [
          ServiceRegion(code: '11', name: '서울특별시', sortOrder: 1),
        ];
      addTearDown(state.dispose);
      await state.savePublicGymPlace(_first);
      expect(state.currentWorkoutPlaceName, _first.name);
      expect(state.currentWorkoutLocation?.gymId, businessGymId);
      expect(state.currentPublicGym?.id, isNot(businessGymId));

      await _pump(tester, state, const ConsultationCreateScreen());
      expect(
        tester
            .widget<ConsultationCreateScreen>(
              find.byType(ConsultationCreateScreen),
            )
            .initialGymId,
        isNull,
      );
      await tester.tap(find.text('오프라인'));
      await _settle(tester);
      expect(find.byKey(const ValueKey('consultation-region')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('consultation-workout-location')),
        findsNothing,
      );

      await tester.tap(find.text('내 헬스장'));
      await _settle(tester);
      final picker = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const ValueKey('consultation-workout-location')),
      );
      expect(picker.initialValue, isNull);
      await tester.tap(
        find.byKey(const ValueKey('consultation-workout-location')),
      );
      await _settle(tester);
      expect(find.text('연결된 인증 센터'), findsWidgets);
      expect(find.text(_first.name), findsNothing);
      expect(state.businessAccess, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
