import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/widgets/pro_access_gate.dart';

/// Builds the access shape `loadAccess()` would return for each situation.
BusinessAccess _access({
  required Set<UserRole> roles,
  BusinessApplicationStatus? application,
  String? rejectReason,
}) {
  return BusinessAccess(
    userId: '00000000-0000-0000-0000-000000000001',
    accountRole: UserRole.member,
    resolvedRole: roles.contains(UserRole.trainer)
        ? UserRole.trainer
        : UserRole.member,
    availableRoles: roles,
    trainerApplication: application == null
        ? null
        : BusinessApplication(
            id: 'app-1',
            kind: BusinessApplicationKind.trainer,
            status: application,
            applicantName: '김트레이너',
            submittedAt: DateTime(2026, 8, 21),
            rejectReason: rejectReason,
          ),
    applicationStatus: application,
    rejectReason: rejectReason,
  );
}

void main() {
  group('pro access policy', () {
    // 회원은 가입 즉시 끝. 트레이너만 관리자 승인을 기다린다.
    test('signed out has no pro access', () {
      final state = AppState();
      addTearDown(state.dispose);
      expect(proAccessStateOf(state), ProAccessState.signedOut);
    });

    test('a member who never applied is not pending, just unapplied', () {
      final state = AppState();
      addTearDown(state.dispose);
      state.businessAccess = _access(roles: {UserRole.member});
      expect(proAccessStateOf(state), ProAccessState.notApplied);
    });

    test('an application under review reads as pending', () {
      final state = AppState();
      addTearDown(state.dispose);
      state.businessAccess = _access(
        roles: {UserRole.member},
        application: BusinessApplicationStatus.pending,
      );
      expect(proAccessStateOf(state), ProAccessState.pending);
    });

    test('a rejection keeps the reason so the sheet can show it', () {
      final state = AppState();
      addTearDown(state.dispose);
      state.businessAccess = _access(
        roles: {UserRole.member},
        application: BusinessApplicationStatus.rejected,
        rejectReason: '자격증 사본이 흐릿해요.',
      );
      expect(proAccessStateOf(state), ProAccessState.rejected);
      expect(state.businessAccess?.rejectReason, '자격증 사본이 흐릿해요.');
    });

    // This is the line the whole feature turns on: approval comes from the
    // granted role, not from the application row.
    test('only a granted trainer role opens the portal', () {
      final state = AppState();
      addTearDown(state.dispose);
      state.businessAccess = _access(
        roles: {UserRole.member, UserRole.trainer},
        application: BusinessApplicationStatus.approved,
      );
      expect(proAccessStateOf(state), ProAccessState.approved);
    });

    test('an approved application without the role does not open the portal', () {
      final state = AppState();
      addTearDown(state.dispose);
      // The admin approved the paperwork but the trainer row is not active yet
      // — the server would still refuse, so the app must not promise otherwise.
      state.businessAccess = _access(
        roles: {UserRole.member},
        application: BusinessApplicationStatus.pending,
      );
      expect(proAccessStateOf(state), isNot(ProAccessState.approved));
    });
  });
}
