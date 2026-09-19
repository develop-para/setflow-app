import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/data/account_profile_repository.dart';
import 'package:setflow/screens/account_profile_screen.dart';
import 'package:setflow/services/auth_service.dart';
import 'package:setflow/theme.dart';

class _Auth extends Fake implements AuthService {
  AuthUser? user = const AuthUser(
    id: 'account-1',
    email: 'member@example.test',
    displayName: '회원',
  );
  final changes = StreamController<AuthChange>.broadcast();
  @override
  AuthUser? get currentUser => user;
  @override
  Stream<AuthChange> get authChanges => changes.stream;
}

class _Profiles implements AccountProfileRepository {
  DateTime? birthDate;
  Object? failure;
  Completer<AccountProfile>? pending;
  int saves = 0;

  AccountProfile get profile => AccountProfile(
    userId: 'account-1',
    email: 'member@example.test',
    providers: const {'google'},
    birthDate: birthDate,
  );
  @override
  Future<AccountProfile> loadMyProfile() async => pending?.future ?? profile;
  @override
  Future<AccountProfile> saveMyBirthDate(DateTime? value) async {
    saves++;
    if (failure != null) throw failure!;
    birthDate = value;
    return profile;
  }
}

void main() {
  test(
    'birth dates preserve leap days and reject normalization and the future',
    () {
      final today = DateTime(2026, 9, 20);
      expect(AccountBirthDate.parse('2000-02-29'), DateTime(2000, 2, 29));
      expect(AccountBirthDate.validate('2001-02-29', today: today), isNotNull);
      expect(AccountBirthDate.validate('2000-13-01', today: today), isNotNull);
      expect(AccountBirthDate.validate('1899-12-31', today: today), isNotNull);
      expect(AccountBirthDate.validate('2026-09-21', today: today), isNotNull);
      expect(AccountBirthDate.validate('2026-09-20', today: today), isNull);
      expect(AccountBirthDate.validate('', today: today), isNull);
    },
  );

  late _Auth auth;
  late _Profiles profiles;
  setUp(() {
    auth = _Auth();
    profiles = _Profiles();
    Auth.use(auth);
  });
  tearDown(() async {
    Auth.reset();
    await auth.changes.close();
  });

  Future<void> open(
    WidgetTester tester, {
    bool largeText = false,
    bool pendingLoad = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: SetflowTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(largeText ? 2 : 1),
            padding: const EdgeInsets.only(bottom: 28),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => AccountProfileScreen(repository: profiles),
                ),
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    if (pendingLoad) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    } else {
      await tester.pumpAndSettle();
    }
  }

  testWidgets('save persists a birth date and returns only after success', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('member@example.test'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '2000-02-29');
    await tester.tap(find.byKey(const ValueKey('account-profile-save')));
    await tester.pumpAndSettle();
    expect(profiles.birthDate, DateTime(2000, 2, 29));
    expect(find.byType(AccountProfileScreen), findsNothing);
  });

  testWidgets('invalid dates never reach the server', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextFormField), '2001-02-29');
    await tester.tap(find.byKey(const ValueKey('account-profile-save')));
    await tester.pumpAndSettle();
    expect(profiles.saves, 0);
    expect(find.textContaining('YYYY-MM-DD'), findsOneWidget);
  });

  testWidgets('blank input removes a previously stored birth date', (
    tester,
  ) async {
    profiles.birthDate = DateTime(2000, 2, 29);
    await open(tester);
    await tester.enterText(find.byType(TextFormField), '');
    await tester.tap(find.byKey(const ValueKey('account-profile-save')));
    await tester.pumpAndSettle();
    expect(profiles.saves, 1);
    expect(profiles.birthDate, isNull);
  });

  testWidgets(
    'failed save keeps the form and entered value available for retry',
    (tester) async {
      profiles.failure = Exception('offline');
      await open(tester);
      await tester.enterText(find.byType(TextFormField), '2000-02-29');
      await tester.tap(find.byKey(const ValueKey('account-profile-save')));
      await tester.pumpAndSettle();
      expect(find.byType(AccountProfileScreen), findsOneWidget);
      expect(find.text('2000-02-29'), findsOneWidget);
      expect(find.textContaining('저장하지 못했어요'), findsOneWidget);
    },
  );

  testWidgets('sign-out clears sensitive fields and prevents saving', (
    tester,
  ) async {
    profiles.birthDate = DateTime(2000, 2, 29);
    await open(tester);
    auth.user = null;
    auth.changes.add(const AuthChange(AuthEvent.signedOut, null));
    await tester.pumpAndSettle();
    expect(find.text('member@example.test'), findsNothing);
    expect(find.text('2000-02-29'), findsNothing);
    expect(find.byKey(const ValueKey('account-profile-save')), findsNothing);
  });

  testWidgets('small screens with large text keep save reachable', (
    tester,
  ) async {
    await open(tester, largeText: true);
    final save = find.byKey(const ValueKey('account-profile-save'));
    await tester.scrollUntilVisible(
      save,
      180,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(save).bottom, lessThanOrEqualTo(540));
  });

  testWidgets('a late response never exposes the previous account', (
    tester,
  ) async {
    profiles.pending = Completer<AccountProfile>();
    await open(tester, pendingLoad: true);
    auth.user = const AuthUser(id: 'account-2', displayName: '다른 회원');
    auth.changes.add(AuthChange(AuthEvent.signedIn, auth.user));
    await tester.pump();
    profiles.pending!.complete(profiles.profile);
    await tester.pumpAndSettle();
    expect(find.text('member@example.test'), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.textContaining('계정이 바뀌었어요'), findsOneWidget);
  });
}
