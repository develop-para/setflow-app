import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/screens/member_membership_screen.dart';
import 'package:setflow/theme.dart';

void main() {
  testWidgets('member switches and adds multiple workout locations', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _WorkoutLocationRepository();
    final state = AppState(businessRepository: repository)
      ..workoutLocations = List.unmodifiable(repository.locations);
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: const MemberMembershipScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('첫 번째 헬스장'), findsOneWidget);
    expect(find.text('두 번째 헬스장'), findsOneWidget);

    await tester.tap(find.text('두 번째 헬스장'));
    await tester.pumpAndSettle();
    expect(state.currentWorkoutLocation?.gymName, '두 번째 헬스장');
    expect(repository.selectedLocationId, 'location-2');

    await tester.tap(find.text('추가'));
    await tester.pumpAndSettle();
    expect(find.text('새 헬스장'), findsOneWidget);
    await tester.tap(find.text('새 헬스장'));
    await tester.pumpAndSettle();

    expect(state.workoutLocations, hasLength(3));
    expect(state.currentWorkoutLocation?.gymName, '새 헬스장');
    expect(repository.savedGymId, 'gym-3');
  });
}

class _WorkoutLocationRepository
    implements BusinessRepository, WorkoutLocationRepository {
  final List<MemberWorkoutLocation> locations = [
    const MemberWorkoutLocation(
      id: 'location-1',
      userId: 'user-1',
      gymId: 'gym-1',
      gymName: '첫 번째 헬스장',
      gymAddress: '서울특별시',
      isActive: true,
    ),
    const MemberWorkoutLocation(
      id: 'location-2',
      userId: 'user-1',
      gymId: 'gym-2',
      gymName: '두 번째 헬스장',
      gymAddress: '경기도',
      isActive: false,
    ),
  ];

  String? selectedLocationId;
  String? savedGymId;

  @override
  Future<List<GymDirectoryEntry>> listVerifiedGyms() async => const [
    GymDirectoryEntry(id: 'gym-1', name: '첫 번째 헬스장'),
    GymDirectoryEntry(id: 'gym-2', name: '두 번째 헬스장'),
    GymDirectoryEntry(id: 'gym-3', name: '새 헬스장', address: '인천광역시'),
  ];

  @override
  Future<List<MemberWorkoutLocation>> listMyWorkoutLocations() async =>
      List.unmodifiable(locations);

  @override
  Future<List<ServiceRegion>> listServiceRegions() async => const [
    ServiceRegion(code: '11', name: '서울특별시', sortOrder: 1),
  ];

  @override
  Future<void> saveWorkoutLocation(String gymId) async {
    savedGymId = gymId;
    for (var index = 0; index < locations.length; index++) {
      final item = locations[index];
      locations[index] = MemberWorkoutLocation(
        id: item.id,
        userId: item.userId,
        gymId: item.gymId,
        gymName: item.gymName,
        gymAddress: item.gymAddress,
        isActive: false,
      );
    }
    locations.add(
      const MemberWorkoutLocation(
        id: 'location-3',
        userId: 'user-1',
        gymId: 'gym-3',
        gymName: '새 헬스장',
        gymAddress: '인천광역시',
        isActive: true,
      ),
    );
  }

  @override
  Future<void> selectWorkoutLocation(String locationId) async {
    selectedLocationId = locationId;
    for (var index = 0; index < locations.length; index++) {
      final item = locations[index];
      locations[index] = MemberWorkoutLocation(
        id: item.id,
        userId: item.userId,
        gymId: item.gymId,
        gymName: item.gymName,
        gymAddress: item.gymAddress,
        isActive: item.id == locationId,
      );
    }
  }

  @override
  Future<void> removeWorkoutLocation(String locationId) async {
    locations.removeWhere((item) => item.id == locationId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
