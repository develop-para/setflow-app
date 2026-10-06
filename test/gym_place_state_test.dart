import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/data/gym_directory_repository.dart';
import 'package:setflow/domain/gym_directory.dart';
import 'package:setflow/services/auth_service.dart';

const _gym = GymPlace(
  id: 'place-seoul',
  name: '서울 피트니스',
  address: '서울특별시 종로구 청계천로 18',
  region: '서울특별시',
);
const _otherGym = GymPlace(
  id: 'place-busan',
  name: '부산 피트니스',
  address: '부산광역시 해운대구 센텀로 18',
  region: '부산광역시',
);
const _thirdGym = GymPlace(
  id: 'place-jeju',
  name: '제주 피트니스',
  address: '제주특별자치도 제주시 중앙로 18',
  region: '제주특별자치도',
);
const _accountA = AuthUser(id: 'account-a', displayName: '첫 번째 회원');
const _accountB = AuthUser(id: 'account-b', displayName: '두 번째 회원');

Future<GymDirectoryRequest> _draft(AppState state) =>
    state.saveGymDirectorySuggestion(
      kind: GymDirectoryRequestKind.correction,
      facilityId: _gym.id,
      gymName: _gym.name,
      address: _gym.address,
      note: '상호와 층을 확인해주세요.',
    );

AppState _state({
  GymPlaceRepository? store,
  GymDirectoryRequestRepository? requests,
  BusinessRepository? businessRepository,
}) {
  final state = AppState(
    gymPlaceRepository: store,
    gymDirectoryRequestRepository: requests,
    businessRepository: businessRepository,
  );
  addTearDown(state.dispose);
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(Auth.reset);
  tearDown(Auth.reset);

  test(
    'a guest choice survives another AppState and later authentication',
    () async {
      final store = MemoryGymPlaceRepository();
      final first = _state(store: store);
      await first.initialize();
      await first.savePublicGymPlace(_gym);
      await first.savePublicGymPlace(_otherGym);
      await first.selectPublicGymPlace(_gym.id);
      expect(first.currentWorkoutPlaceName, _gym.name);
      expect(Auth.instance.hasAuthenticatedUser, isFalse);

      final second = _state(store: store);
      await second.initialize();
      expect(second.currentPublicGym?.id, _gym.id);
      expect(second.currentWorkoutPlaceName, _gym.name);
      expect(second.gymPlaceLibrary.gyms.map((gym) => gym.id), [
        _gym.id,
        _otherGym.id,
      ]);

      Auth.use(_Auth(_accountA));
      await second.syncAfterAuthentication();
      expect(second.currentPublicGym?.id, _gym.id);
      await second.selectPublicGymPlace(null);
      final third = _state(store: store);
      await third.initialize();
      expect(third.currentPublicGym, isNull);
      expect(third.gymPlaceLibrary.gyms, hasLength(2));
    },
  );

  test(
    'overlapping favourite writes and a draft preserve every change',
    () async {
      final store = _DeviceStore(
        GymPlaceLibrary(gyms: [_gym], selectedId: _gym.id),
      );
      final state = _state(store: store);
      await state.initialize();
      final gate = store.pauseNextSave();
      final first = state.savePublicGymPlace(_otherGym);
      await gate.started.future;
      final second = state.savePublicGymPlace(_thirdGym);
      final suggestion = _draft(state);
      expect(state.currentPublicGym?.id, _gym.id);
      gate.release.complete();
      await Future.wait([first, second, suggestion]);

      expect(state.gymPlaceLibrary.gyms.map((gym) => gym.id), [
        _gym.id,
        _otherGym.id,
        _thirdGym.id,
      ]);
      expect(state.currentPublicGym?.id, _thirdGym.id);
      expect(state.gymDirectoryRequests.single.id, (await suggestion).id);
      expect(store.library.gyms, hasLength(3));
      expect(store.library.requests, hasLength(1));
      expect(store.maxConcurrentSaves, 1);
    },
  );

  for (final operation in ['select', 'save']) {
    for (final latestPlace in [_otherGym, _gym]) {
      test(
        'a slow verified $operation cannot erase the later ${latestPlace.id} choice',
        () async {
          Auth.use(_Auth(_accountA));
          final store = MemoryGymPlaceRepository(
            initialValue: GymPlaceLibrary(
              gyms: [_gym, _otherGym],
              selectedId: _gym.id,
            ),
          );
          final verified = _DelayedVerifiedLocations();
          final state = _state(store: store, businessRepository: verified);
          await state.loadGymPlaces();
          final changingCentre = operation == 'select'
              ? state.selectWorkoutLocation(
                  _DelayedVerifiedLocations.locationId,
                )
              : state.saveWorkoutLocation(_DelayedVerifiedLocations.gymId);
          await verified.gate.started.future;
          await state.selectPublicGymPlace(latestPlace.id);
          verified.gate.release.complete();
          await changingCentre;

          expect(state.currentPublicGym?.id, latestPlace.id);
          expect(state.currentWorkoutPlaceName, latestPlace.name);
          expect((await store.load()).selectedId, latestPlace.id);
          expect(
            state.currentWorkoutLocation?.gymId,
            _DelayedVerifiedLocations.gymId,
          );
          expect(
            verified.attemptedIds.single,
            operation == 'select'
                ? _DelayedVerifiedLocations.locationId
                : _DelayedVerifiedLocations.gymId,
          );
        },
      );
    }

    test(
      'a verified $operation clears the older public choice when no later choice was made',
      () async {
        Auth.use(_Auth(_accountA));
        final store = MemoryGymPlaceRepository(
          initialValue: GymPlaceLibrary(gyms: [_gym], selectedId: _gym.id),
        );
        final verified = _DelayedVerifiedLocations();
        final state = _state(store: store, businessRepository: verified);
        await state.loadGymPlaces();
        final changingCentre = operation == 'select'
            ? state.selectWorkoutLocation(_DelayedVerifiedLocations.locationId)
            : state.saveWorkoutLocation(_DelayedVerifiedLocations.gymId);
        await verified.gate.started.future;
        verified.gate.release.complete();
        await changingCentre;

        expect(state.currentPublicGym, isNull);
        expect((await store.load()).selectedId, isNull);
        expect(state.currentWorkoutPlaceName, '인증 센터');
        expect(state.gymPlaceLibrary.gyms.single.id, _gym.id);
      },
    );
  }

  test(
    'a failed save retains the pinned place and does not invent a receipt',
    () async {
      final store = _DeviceStore(
        GymPlaceLibrary(gyms: [_gym], selectedId: _gym.id),
      );
      final requests = _ServerRequests();
      final auth = _Auth(_accountA);
      Auth.use(auth);
      final state = _state(store: store, requests: requests);
      await state.initialize();
      store.failSave = true;
      await expectLater(state.savePublicGymPlace(_otherGym), throwsStateError);
      expect(state.currentPublicGym?.id, _gym.id);
      expect(store.library.selectedGym?.id, _gym.id);
      expect(state.gymPlacesError, isNotNull);
      store.failSave = false;
      final draft = await _draft(state);

      // Owner binding is the first write; the receipt is the second write.
      store.failSaveNumber = store.saveCalls + 2;
      await expectLater(
        state.submitSavedGymDirectoryRequest(draft.id),
        throwsStateError,
      );
      expect(requests.attempts, hasLength(1));
      expect(state.gymDirectoryRequests.single.submittedAt, isNull);
      expect(store.library.requests.single.submittedAt, isNull);
      expect(state.currentPublicGym?.id, _gym.id);

      store.failSaveNumber = null;
      await state.submitSavedGymDirectoryRequest(draft.id);
      expect(requests.attempts.map((request) => request.id), [
        draft.id,
        draft.id,
      ]);
      expect(
        state.gymDirectoryRequests.single.submittedAt,
        requests.receivedAt,
      );
      expect(store.library.requests.single.submittedAt, requests.receivedAt);
      expect(requests.receipts, hasLength(1));
    },
  );

  test(
    'a failed initial read cannot overwrite an existing library with an empty one',
    () async {
      final store = _DeviceStore(
        GymPlaceLibrary(gyms: [_gym], selectedId: _gym.id),
      )..failLoad = true;
      final state = _state(store: store);
      await state.initialize();
      expect(state.gymPlacesError, isNotNull);
      await expectLater(state.savePublicGymPlace(_otherGym), throwsStateError);
      await expectLater(_draft(state), throwsStateError);
      expect(store.saveCalls, 0);
      expect(store.library.selectedGym?.id, _gym.id);
      expect(store.library.requests, isEmpty);

      store.failLoad = false;
      await state.savePublicGymPlace(_otherGym);
      expect(state.gymPlaceLibrary.gyms.map((gym) => gym.id), [
        _gym.id,
        _otherGym.id,
      ]);
      expect(state.currentPublicGym?.id, _otherGym.id);
    },
  );

  test(
    'account-owned drafts are hidden and cannot be resent by another account',
    () async {
      final store = MemoryGymPlaceRepository();
      final requests = _ServerRequests();
      final auth = _Auth(_accountA);
      Auth.use(auth);
      final state = _state(store: store, requests: requests);
      await state.initialize();
      final draft = await _draft(state);
      expect(draft.ownerUserId, _accountA.id);

      auth.user = _accountB;
      await state.syncAfterAuthentication();
      expect(state.gymDirectoryRequests, isEmpty);
      await expectLater(
        state.submitSavedGymDirectoryRequest(draft.id),
        throwsA(isA<AuthFailure>()),
      );
      expect(requests.attempts, isEmpty);
      expect((await store.load()).requests.single.ownerUserId, _accountA.id);

      auth.user = null;
      state.handleExternalAuthSignedOut();
      expect(state.gymDirectoryRequests, isEmpty);
      auth.user = _accountA;
      await state.syncAfterAuthentication();
      expect(state.gymDirectoryRequests.single.id, draft.id);
      expect(state.gymDirectoryRequests.single.isSubmitted, isFalse);
    },
  );

  test(
    'a guest draft is bound to an account only by explicit submit and persists its receipt',
    () async {
      final store = MemoryGymPlaceRepository();
      final requests = _ServerRequests();
      final state = _state(store: store, requests: requests);
      await state.initialize();
      final draft = await _draft(state);
      expect(draft.ownerUserId, isNull);
      expect(draft.isSubmitted, isFalse);
      await expectLater(
        state.submitSavedGymDirectoryRequest(draft.id),
        throwsA(isA<AuthFailure>()),
      );
      expect(requests.attempts, isEmpty);

      Auth.use(_Auth(_accountA));
      await state.syncAfterAuthentication();
      expect(state.gymDirectoryRequests.single.ownerUserId, isNull);
      expect(requests.attempts, isEmpty);
      await state.submitSavedGymDirectoryRequest(draft.id);
      expect(requests.attempts.single.ownerUserId, _accountA.id);
      final received = state.gymDirectoryRequests.single;
      expect(received.ownerUserId, _accountA.id);
      expect(received.submittedAt, requests.receivedAt);
      await state.submitSavedGymDirectoryRequest(draft.id);
      expect(requests.attempts, hasLength(1));

      final restored = _state(store: store);
      await restored.initialize();
      expect(
        restored.gymDirectoryRequests.single.submittedAt,
        requests.receivedAt,
      );
      expect(restored.gymDirectoryRequests.single.ownerUserId, _accountA.id);
    },
  );

  test('owner binding must be durable before a draft is sent', () async {
    final store = _DeviceStore(GymPlaceLibrary());
    final requests = _ServerRequests();
    final state = _state(store: store, requests: requests);
    await state.initialize();
    final draft = await _draft(state);
    Auth.use(_Auth(_accountA));
    store.failSave = true;
    await expectLater(
      state.submitSavedGymDirectoryRequest(draft.id),
      throwsStateError,
    );
    expect(requests.attempts, isEmpty);
    expect(state.gymDirectoryRequests.single.ownerUserId, isNull);
    expect(store.library.requests.single.ownerUserId, isNull);
  });

  test(
    'a lost response leaves an owned draft and an explicit retry keeps its ID',
    () async {
      Auth.use(_Auth(_accountA));
      final store = MemoryGymPlaceRepository();
      final requests = _ServerRequests()..loseNextResponse = true;
      final state = _state(store: store, requests: requests);
      await state.initialize();
      final draft = await _draft(state);
      await expectLater(
        state.submitSavedGymDirectoryRequest(draft.id),
        throwsStateError,
      );
      expect(state.gymDirectoryRequests.single.isSubmitted, isFalse);
      expect((await store.load()).requests.single.ownerUserId, _accountA.id);
      final restarted = _state(store: store, requests: requests);
      await restarted.initialize();
      await restarted.submitSavedGymDirectoryRequest(draft.id);
      expect(requests.attempts.map((request) => request.id), [
        draft.id,
        draft.id,
      ]);
      expect(requests.receipts, hasLength(1));
      expect(
        restarted.gymDirectoryRequests.single.submittedAt,
        requests.receivedAt,
      );
    },
  );

  test(
    'an account switch during submission keeps the original owner receipt private',
    () async {
      final auth = _Auth(_accountA);
      Auth.use(auth);
      final store = MemoryGymPlaceRepository();
      final requests = _ServerRequests();
      final state = _state(store: store, requests: requests);
      await state.initialize();
      await state.savePublicGymPlace(_gym);
      final draft = await _draft(state);
      final gate = requests.pauseNextResponse();
      final sending = state.submitSavedGymDirectoryRequest(draft.id);
      await gate.started.future;
      await expectLater(
        state.submitSavedGymDirectoryRequest(draft.id),
        throwsStateError,
      );
      auth.user = _accountB;
      await state.syncAfterAuthentication();
      expect(state.gymDirectoryRequests, isEmpty);
      gate.release.complete();
      await sending;

      expect(state.gymDirectoryRequests, isEmpty);
      expect(state.currentPublicGym?.id, _gym.id);
      final stored = (await store.load()).requests.single;
      expect(stored.ownerUserId, _accountA.id);
      expect(stored.submittedAt, requests.receivedAt);
      await expectLater(
        state.submitSavedGymDirectoryRequest(draft.id),
        throwsA(isA<AuthFailure>()),
      );
      expect(requests.attempts, hasLength(1));
      auth.user = _accountA;
      await state.syncAfterAuthentication();
      expect(
        state.gymDirectoryRequests.single.submittedAt,
        requests.receivedAt,
      );
    },
  );
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

class _Gate {
  final started = Completer<void>();
  final release = Completer<void>();
}

class _DeviceStore implements GymPlaceRepository {
  _DeviceStore(this.library);

  GymPlaceLibrary library;
  bool failLoad = false;
  bool failSave = false;
  int? failSaveNumber;
  int saveCalls = 0;
  int concurrentSaves = 0;
  int maxConcurrentSaves = 0;
  _Gate? _gate;

  _Gate pauseNextSave() => _gate = _Gate();

  @override
  Future<GymPlaceLibrary> load() async {
    if (failLoad) throw StateError('Cannot read disk');
    return library;
  }

  @override
  Future<void> save(GymPlaceLibrary next) async {
    saveCalls++;
    concurrentSaves++;
    if (concurrentSaves > maxConcurrentSaves) {
      maxConcurrentSaves = concurrentSaves;
    }
    try {
      if (failSave || saveCalls == failSaveNumber) {
        throw StateError('Disk full');
      }
      final gate = _gate;
      _gate = null;
      if (gate != null) {
        gate.started.complete();
        await gate.release.future;
      }
      library = GymPlaceLibraryCodec.decode(GymPlaceLibraryCodec.encode(next));
    } finally {
      concurrentSaves--;
    }
  }
}

class _ServerRequests implements GymDirectoryRequestRepository {
  final attempts = <GymDirectoryRequest>[];
  final receipts = <String, DateTime>{};
  final receivedAt = DateTime.utc(2026, 10, 6, 13);
  bool loseNextResponse = false;
  _Gate? _gate;

  _Gate pauseNextResponse() => _gate = _Gate();

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<DateTime> submitRequest(GymDirectoryRequest request) async {
    attempts.add(request);
    final receipt = receipts.putIfAbsent(
      '${request.ownerUserId}:${request.id}',
      () => receivedAt,
    );
    final gate = _gate;
    _gate = null;
    if (gate != null) {
      gate.started.complete();
      await gate.release.future;
    }
    if (loseNextResponse) {
      loseNextResponse = false;
      throw StateError('Response was lost after server commit');
    }
    return receipt;
  }
}

class _DelayedVerifiedLocations extends Fake
    implements BusinessRepository, WorkoutLocationRepository {
  static const gymId = '33333333-3333-4333-8333-333333333333';
  static const locationId = '44444444-4444-4444-8444-444444444444';
  final gate = _Gate();
  final attemptedIds = <String>[];

  @override
  Future<List<MemberWorkoutLocation>> listMyWorkoutLocations() async => const [
    MemberWorkoutLocation(
      id: locationId,
      userId: 'account-a',
      gymId: gymId,
      gymName: '인증 센터',
      isActive: true,
    ),
  ];

  Future<void> _pause(String id) async {
    attemptedIds.add(id);
    gate.started.complete();
    await gate.release.future;
  }

  @override
  Future<void> saveWorkoutLocation(String gymId) => _pause(gymId);

  @override
  Future<void> selectWorkoutLocation(String locationId) => _pause(locationId);
}
