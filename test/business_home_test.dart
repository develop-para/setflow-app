import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/screens/business_screens.dart';
import 'package:setflow/screens/business_settings_screens.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/common.dart';

void main() {
  Future<AppState> pumpBusiness(
    WidgetTester tester,
    UserRole role, {
    Widget? screen,
    AppRepository? repository,
    bool darkMode = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState(repository: repository);
    await state.initialize();
    state.role = role;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          darkTheme: SetflowTheme.dark,
          themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
          home: screen == null
              ? BusinessShell(role: role)
              : Scaffold(body: screen),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    return state;
  }

  testWidgets('trainer shell keeps role navigation and opens consultation', (
    tester,
  ) async {
    await pumpBusiness(tester, UserRole.trainer);

    expect(find.text('안녕하세요, 김코치님'), findsOneWidget);
    expect(find.text('관리 회원'), findsOneWidget);
    expect(find.text('상담'), findsOneWidget);

    await tester.tap(find.text('상담'));
    await tester.pumpAndSettle();
    expect(find.text('상담 수신함'), findsOneWidget);
  });

  testWidgets('business home refreshes and exposes notification empty state', (
    tester,
  ) async {
    await pumpBusiness(tester, UserRole.trainer, screen: const TrainerHome());

    await tester.tap(find.byTooltip('새로고침'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LoadingState), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('운영 현황을 최신 상태로 갱신했어요.'), findsOneWidget);

    await tester.tap(find.byTooltip('알림'));
    await tester.pumpAndSettle();
    expect(find.text('새 상담이 도착했어요'), findsWidgets);

    await tester.tap(find.text('모두 읽음'));
    await tester.pumpAndSettle();
    expect(find.text('새 알림이 없어요'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 350));
  });

  testWidgets('trainer action opens its real consultation queue', (
    tester,
  ) async {
    await pumpBusiness(tester, UserRole.trainer, screen: const TrainerHome());

    await tester.tap(find.text('새 상담이 도착했어요'));
    await tester.pumpAndSettle();
    expect(find.byType(ConsultationQueuePage), findsOneWidget);
  });

  testWidgets('gym and admin homes expose role-specific operations', (
    tester,
  ) async {
    await pumpBusiness(tester, UserRole.gym, screen: const GymHome());
    expect(find.text('모션짐 강남점'), findsOneWidget);
    expect(find.text('신규 회원 배정이 필요해요'), findsOneWidget);

    final adminState = AppState();
    await adminState.initialize();
    adminState.role = UserRole.admin;
    addTearDown(adminState.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: adminState,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: const Scaffold(body: AdminHome()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Setflow 운영 현황'), findsOneWidget);
    expect(find.text('긴급 신고 2건'), findsOneWidget);
    expect(find.text('SLA 처리 현황'), findsOneWidget);
  });

  testWidgets('business home offers persistence retry on repository failure', (
    tester,
  ) async {
    await pumpBusiness(
      tester,
      UserRole.trainer,
      screen: const TrainerHome(),
      repository: _FailingRepository(),
    );

    expect(find.text('운영 데이터 저장에 실패했어요.'), findsOneWidget);
    await tester.tap(find.text('재시도'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('저장을 다시 시도했어요.'), findsOneWidget);
  });

  testWidgets('business notifications persist read state through repository', (
    tester,
  ) async {
    final repository = MemoryAppRepository();
    await pumpBusiness(
      tester,
      UserRole.trainer,
      screen: const TrainerHome(),
      repository: repository,
    );

    await tester.tap(find.byTooltip('알림'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('모두 읽음'));
    await tester.pumpAndSettle();
    expect(find.text('새 알림이 없어요'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 350));

    final restored = AppState(repository: repository);
    await restored.initialize();
    addTearDown(restored.dispose);
    expect(restored.unreadBusinessNotifications(UserRole.trainer), 0);
  });

  testWidgets('business home exposes an empty state from repository data', (
    tester,
  ) async {
    final emptyDashboard = BusinessDashboardData(
      role: UserRole.trainer,
      facts: {},
      tasks: [],
      notifications: [],
      lastSyncedAt: DateTime(2026, 7, 23),
    );
    final repository = MemoryAppRepository(
      initialSnapshot: AppSnapshot(
        role: UserRole.trainer,
        themeMode: ThemeMode.light,
        weightUnit: 'kg',
        restDefaultSeconds: 90,
        sessions: const {},
        routines: const [],
        businessDashboards: {UserRole.trainer: emptyDashboard},
      ),
    );

    await pumpBusiness(
      tester,
      UserRole.trainer,
      screen: const TrainerHome(),
      repository: repository,
    );

    expect(find.text('표시할 운영 데이터가 없어요'), findsOneWidget);
    expect(find.text('다시 불러오기'), findsOneWidget);
  });

  testWidgets('trainer home renders without overflow in dark mode', (
    tester,
  ) async {
    await pumpBusiness(
      tester,
      UserRole.trainer,
      screen: const TrainerHome(),
      darkMode: true,
    );

    expect(find.text('안녕하세요, 김코치님'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final surface = tester.widget<Material>(find.byType(Material).first);
    expect(surface, isNotNull);
  });

  testWidgets('business settings exposes and persists dark mode control', (
    tester,
  ) async {
    final repository = MemoryAppRepository();
    final state = await pumpBusiness(
      tester,
      UserRole.trainer,
      screen: const BusinessSettingsListScreen(role: UserRole.trainer),
      repository: repository,
    );

    // Theme defaults to system, which resolves to light in the test harness.
    expect(find.text('밝은 화면 사용 중'), findsOneWidget);
    await tester.tap(find.text('다크 모드'));
    await tester.pump();
    expect(state.isDarkMode, isTrue);
    expect(state.themeMode, ThemeMode.dark);
    expect(find.text('어두운 화면 사용 중'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 350));

    final restored = AppState(repository: repository);
    await restored.initialize();
    addTearDown(restored.dispose);
    expect(restored.themeMode, ThemeMode.dark);
  });
}

class _FailingRepository implements AppRepository {
  @override
  Future<void> clear() async => throw StateError('clear failed');

  @override
  Future<AppSnapshot?> load(List<ExerciseTemplate> exerciseCatalog) async {
    throw StateError('load failed');
  }

  @override
  Future<void> save(AppSnapshot snapshot) async {
    throw StateError('save failed');
  }
}
