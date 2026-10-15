import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';

void main() {
  for (final remoteEmpty in [false, true]) {
    test('late cloud restore preserves edits made after local startup '
        '(remote empty: $remoteEmpty)', () async {
      final repository = _DelayedRestoreRepository();
      final state = AppState(repository: repository);
      addTearDown(state.dispose);
      final initialization = state.initialize();
      await repository.cloudStarted.future;
      expect(state.isInitialized, isTrue);
      final day = DateTime(2026, 10, 15);
      state.addExercise(day, state.exercises.first);
      state.setRestDefaultSeconds(120);
      await state.flushPersistence();
      repository.cloud.complete(remoteEmpty ? null : _snapshot());
      await initialization;
      expect(state.restDefaultSeconds, 120);
      expect(state.sessions[day]?.exercises, hasLength(1));
      await state.flushPersistence();
      expect(repository.saved!.restDefaultSeconds, 120);
      expect(repository.saved!.sessions[day]?.exercises, hasLength(1));
    });
  }
}

AppSnapshot _snapshot() => AppSnapshot(
  role: UserRole.member,
  isDarkMode: false,
  weightUnit: 'kg',
  restDefaultSeconds: 90,
  sessions: const {},
  routines: const [],
);

class _DelayedRestoreRepository
    implements AppRepository, LocalFirstAppRepository {
  final cloudStarted = Completer<void>();
  final cloud = Completer<AppSnapshot?>();
  AppSnapshot? saved;

  @override
  Future<AppSnapshot?> loadLocal(List<ExerciseTemplate> catalog) async =>
      _snapshot();

  @override
  Future<AppSnapshot?> load(List<ExerciseTemplate> catalog) {
    cloudStarted.complete();
    return cloud.future;
  }

  @override
  Future<void> save(AppSnapshot snapshot) async => saved = snapshot;

  @override
  Future<void> clear() async => saved = null;
}
