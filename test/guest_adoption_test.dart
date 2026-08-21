import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/main.dart';
import 'package:setflow/models.dart';
import 'package:setflow/services/auth_service.dart';

/// The moment a guest signs in is where their records are either carried over
/// or stranded, and it is driven by an auth *stream* rather than a button — so
/// nothing about it is exercised by the repository tests. These drive the real
/// wiring in `main.dart`: fake auth emits a sign-in, the app decides whether to
/// ask, and the answer decides whether the claim happens.
void main() {
  AppSnapshot guestSnapshot({int routines = 2}) => AppSnapshot(
    role: UserRole.guest,
    isDarkMode: false,
    weightUnit: 'kg',
    restDefaultSeconds: 90,
    sessions: const {},
    routines: [
      for (var i = 0; i < routines; i++)
        RoutineData(
          id: 'guest-$i',
          name: 'guest-$i',
          description: '',
          color: Colors.grey,
          exercises: const [],
        ),
    ],
  );

  Future<_FakeAuth> launch(
    WidgetTester tester,
    _AdoptionRepository repository,
  ) async {
    final auth = _FakeAuth();
    Auth.use(auth);
    addTearDown(() {
      auth.dispose();
      Auth.reset();
    });
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(SetflowApp(repository: repository));
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();
    return auth;
  }

  final confirm = find.byKey(const ValueKey('guest-adopt-confirm'));
  final decline = find.byKey(const ValueKey('guest-adopt-decline'));

  testWidgets('signing in offers the device records and adopts on yes', (
    tester,
  ) async {
    final repository = _AdoptionRepository(guest: guestSnapshot());
    final auth = await launch(tester, repository);
    repository.calls.clear();

    auth.emitSignIn('account-a');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('guest-adopt-title')), findsOneWidget);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(repository.adoptedBy, 'account-a');
    // The import happens inside load(). Claiming afterwards would show an
    // empty account first and then change under the user.
    expect(
      repository.calls.indexOf('adopt'),
      lessThan(repository.calls.indexOf('load')),
      reason: 'the claim must settle before the account loads',
    );
  });

  testWidgets('declining leaves the records unclaimed', (tester) async {
    final repository = _AdoptionRepository(guest: guestSnapshot());
    final auth = await launch(tester, repository);

    auth.emitSignIn('account-a');
    await tester.pumpAndSettle();
    await tester.tap(decline);
    await tester.pumpAndSettle();

    expect(repository.adoptedBy, isNull);
    // Declining is not deleting -- the guest snapshot is still there to be
    // offered again, or seen again after a sign-out.
    expect(repository.guest, isNotNull);
    expect(repository.calls, contains('load'));
  });

  testWidgets('an empty device does not interrupt sign-in', (tester) async {
    // Someone who signs up on a fresh install has nothing to carry over. A
    // prompt here would be a question with only one sensible answer.
    final repository = _AdoptionRepository(guest: guestSnapshot(routines: 0));
    final auth = await launch(tester, repository);

    auth.emitSignIn('account-a');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('guest-adopt-title')), findsNothing);
    expect(repository.calls, contains('load'));
  });

  testWidgets('no local snapshot at all does not prompt', (tester) async {
    final repository = _AdoptionRepository(guest: null);
    final auth = await launch(tester, repository);

    auth.emitSignIn('account-a');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('guest-adopt-title')), findsNothing);
  });

  testWidgets('a declined offer is not repeated on the next auth event', (
    tester,
  ) async {
    final repository = _AdoptionRepository(guest: guestSnapshot());
    final auth = await launch(tester, repository);

    auth.emitSignIn('account-a');
    await tester.pumpAndSettle();
    await tester.tap(decline);
    await tester.pumpAndSettle();

    // Session restores re-emit signedIn. Asking every time would be nagging,
    // and the answer has not changed.
    auth.emitSignOut();
    await tester.pumpAndSettle();
    auth.emitSignIn('account-a');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('guest-adopt-title')), findsNothing);
    expect(repository.adoptedBy, isNull);
  });

  testWidgets('the sheet cannot be dismissed by tapping the barrier', (
    tester,
  ) async {
    // Losing the question loses the records: there is no second prompt, and a
    // stray tap is not an answer.
    final repository = _AdoptionRepository(guest: guestSnapshot());
    final auth = await launch(tester, repository);

    auth.emitSignIn('account-a');
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(216, 40));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('guest-adopt-title')), findsOneWidget);
  });
}

class _AdoptionRepository implements AppRepository, GuestDataAdoption {
  _AdoptionRepository({required this.guest});

  AppSnapshot? guest;
  final calls = <String>[];
  String? adoptedBy;

  @override
  Future<AppSnapshot?> load(List<ExerciseTemplate> exerciseCatalog) async {
    calls.add('load');
    return adoptedBy == null ? null : guest;
  }

  @override
  Future<void> save(AppSnapshot snapshot) async => calls.add('save');

  @override
  Future<void> clear() async => calls.add('clear');

  @override
  Future<AppSnapshot?> peekGuestSnapshot(
    List<ExerciseTemplate> exerciseCatalog,
  ) async {
    calls.add('peek');
    return guest;
  }

  @override
  Future<bool> adoptGuestSnapshot(String userId) async {
    calls.add('adopt');
    adoptedBy = userId;
    return true;
  }
}

class _FakeAuth implements AuthService {
  final _controller = StreamController<AuthChange>.broadcast();
  AuthUser? _user;

  /// Named apart from [signIn] because that one is the interface method the
  /// app calls; these two are the test driving the stream.
  void emitSignIn(String id) {
    _user = AuthUser(id: id, email: '$id@example.com', displayName: id);
    _controller.add(AuthChange(AuthEvent.signedIn, _user));
  }

  void emitSignOut() {
    _user = null;
    _controller.add(const AuthChange(AuthEvent.signedOut, null));
  }

  void dispose() => _controller.close();

  @override
  AuthUser? get currentUser => _user;

  @override
  bool get hasAuthenticatedUser => _user != null;

  @override
  String get currentDisplayName => _user?.displayName ?? '회원';

  @override
  Stream<AuthChange> get authChanges => _controller.stream;

  @override
  bool isConfigured(SocialLoginProvider provider) => false;

  @override
  Future<AuthSignUpResult> signUp({
    required String email,
    required String password,
    required String nickname,
  }) async => const AuthSignUpResult(signedIn: false);

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<bool> signInWithSocial(SocialLoginProvider provider) async => false;

  @override
  Future<void> sendPasswordReset({required String email}) async {}

  @override
  Future<void> resendConfirmationEmail({required String email}) async {}

  @override
  Future<void> updatePassword({required String newPassword}) async {}

  @override
  Future<bool> verifyPassword(String password) async => false;

  @override
  Future<void> signOut() async {}

  @override
  Future<bool> isVerifiedAdmin() async => false;

  @override
  String messageFor(Object error) => '$error';
}
