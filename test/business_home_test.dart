import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/screens/business_screens.dart';
import 'package:setflow/theme.dart';

void main() {
  Future<AppState> pumpBusiness(
    WidgetTester tester,
    UserRole role, {
    Widget? screen,
    AppRepository? repository,
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
          home: screen == null
              ? BusinessShell(role: role)
              : Scaffold(body: screen),
        ),
      ),
    );
    await tester.pumpAndSettle();
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
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('운영 현황을 최신 상태로 갱신했어요.'), findsOneWidget);

    await tester.tap(find.byTooltip('알림'));
    await tester.pumpAndSettle();
    expect(find.text('새 상담이 도착했어요'), findsWidgets);

    await tester.tap(find.text('모두 읽음'));
    await tester.pumpAndSettle();
    expect(find.text('새 알림이 없어요'), findsOneWidget);
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
