import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/routine_catalog_repository.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/screens/member_social_detail_screens.dart';
import 'package:setflow/services/auth_service.dart';
import 'package:setflow/theme.dart';

void _fillFourRoutines(AppState state) {
  state.routines
    ..clear()
    ..addAll([
      for (var index = 1; index <= 4; index++)
        RoutineData(
          id: 'saved-$index',
          name: '기존 루틴 $index',
          description: '보존할 운동 구성 $index',
          color: SetflowColors.brand,
          exercises: [state.exercises.first],
        ),
    ]);
}

Future<void> _pumpRoutines(WidgetTester tester, AppState state) async {
  await tester.binding.setSurfaceSize(const Size(432, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(
        theme: SetflowTheme.light,
        home: const RoutinesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(Auth.reset);
  tearDown(Auth.reset);

  test(
    'free storage policy is shared by creation and import and ignores a role label',
    () async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.initialize();
      _fillFourRoutines(state);
      final original = List<RoutineData>.of(state.routines);
      state.role = UserRole.admin;

      expect(state.isAdmin, isFalse);
      expect(state.routineStorageLimit, 4);
      expect(state.hasReachedRoutineStorageLimit, isTrue);
      expect(state.createRoutine('막힌 루틴', '무료 저장 정책 확인'), isFalse);
      expect(
        await state.createPersonalRoutine('막힌 루틴', '무료 저장 정책 확인'),
        isFalse,
      );
      expect(
        state.importRoutine(
          RoutineData(
            id: 'import-extra',
            name: '추가 무료 루틴',
            description: '가져오기도 같은 저장 정책 적용',
            color: SetflowColors.brand,
            exercises: [state.exercises.first],
          ),
        ),
        RoutineImportResult.limitReached,
      );
      expect(state.routines, orderedEquals(original));
    },
  );

  testWidgets(
    'free users with four routines get the same limit from both create actions',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.initialize();
      _fillFourRoutines(state);
      final original = List<RoutineData>.of(state.routines);
      await _pumpRoutines(tester, state);

      expect(find.text('저장된 루틴 4/4'), findsOneWidget);
      expect(find.text('무료 플랜'), findsOneWidget);
      expect(find.text('제한 없음'), findsNothing);
      final footer = find.widgetWithText(OutlinedButton, '새 루틴 만들기');
      await tester.ensureVisible(footer);
      await tester.tap(footer);
      await tester.pumpAndSettle();
      expect(find.byType(RoutineCreateSheet), findsNothing);
      expect(find.text('무료 플랜은 루틴을 4개까지 저장할 수 있어요.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));

      await tester.tap(find.byTooltip('루틴 만들기'));
      await tester.pumpAndSettle();
      expect(find.byType(RoutineCreateSheet), findsNothing);
      expect(find.text('무료 플랜은 루틴을 4개까지 저장할 수 있어요.'), findsOneWidget);
      expect(state.routines, orderedEquals(original));
      await tester.pump(const Duration(seconds: 4));
    },
  );

  for (final verifiedAdmin in [false, true]) {
    testWidgets(
      '${verifiedAdmin ? 'verified admin' : 'paid member'} can create a fifth routine and keeps the existing four',
      (tester) async {
        Auth.use(_SessionAuth(verifiedAdmin: verifiedAdmin));
        final state = AppState(
          routineCatalogRepository: _RoutineAccess(paid: !verifiedAdmin),
        );
        addTearDown(state.dispose);
        await state.initialize();
        expect(state.isAdmin, verifiedAdmin);
        if (verifiedAdmin) {
          // Exercise the verified-admin exemption independently of paid status.
          state.hasPaidPlan = false;
        } else {
          expect(state.hasPaidPlan, isTrue);
        }
        _fillFourRoutines(state);
        final original = List<RoutineData>.of(state.routines);
        await _pumpRoutines(tester, state);

        expect(state.routineStorageLimit, isNull);
        expect(state.hasReachedRoutineStorageLimit, isFalse);
        expect(find.text('저장된 루틴 4개'), findsOneWidget);
        expect(find.text('제한 없음'), findsOneWidget);
        expect(find.text('무료 플랜'), findsNothing);
        expect(find.text('저장된 루틴 4/4'), findsNothing);

        if (verifiedAdmin) {
          await tester.tap(find.byTooltip('루틴 만들기'));
        } else {
          final footer = find.widgetWithText(OutlinedButton, '새 루틴 만들기');
          await tester.ensureVisible(footer);
          await tester.tap(footer);
        }
        await tester.pumpAndSettle();
        final sheet = find.byType(RoutineCreateSheet);
        expect(sheet, findsOneWidget);
        final fields = find.descendant(
          of: sheet,
          matching: find.byType(TextFormField),
        );
        await tester.enterText(fields.first, '다섯 번째 루틴');
        await tester.enterText(fields.at(1), '기존 기록을 보존하는 새 루틴');
        final save = find.descendant(of: sheet, matching: find.text('저장'));
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();

        expect(find.byType(RoutineCreateSheet), findsNothing);
        expect(state.routines, hasLength(5));
        expect(state.routines.take(4), orderedEquals(original));
        expect(state.routines.last.name, '다섯 번째 루틴');
        expect(find.text('저장된 루틴 5개'), findsOneWidget);
        expect(find.text('무료 플랜 저장 한도에 도달했어요.'), findsNothing);
        await tester.pump(const Duration(seconds: 4));
      },
    );
  }
}

class _RoutineAccess implements RoutineCatalogRepository {
  const _RoutineAccess({required this.paid});
  final bool paid;

  @override
  Future<List<RoutineCatalogItem>> listPublished() async => [];

  @override
  Future<bool> hasActivePaidPlan() async => paid;

  @override
  Future<void> updateAccessTier(
    String routineId,
    RoutineCatalogAccessTier accessTier,
  ) async {}
}

class _SessionAuth implements AuthService {
  const _SessionAuth({required this.verifiedAdmin});
  final bool verifiedAdmin;

  @override
  AuthUser get currentUser =>
      const AuthUser(id: 'routine-user', displayName: '루틴 테스터');

  @override
  bool get hasAuthenticatedUser => true;

  @override
  String get currentDisplayName => currentUser.displayName;

  @override
  Stream<AuthChange> get authChanges => const Stream<AuthChange>.empty();

  @override
  Future<bool> isVerifiedAdmin() async => verifiedAdmin;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
