import '../models.dart';

/// 트레이너가 관리하는 독립 회원 공간. 연락처는 계정 소유의 증거가 아니다.
class TrainerManagedClient {
  const TrainerManagedClient({
    required this.id,
    required this.name,
    required this.phone,
    required this.notes,
    this.memberUserId,
    this.canConnect = true,
  });

  final String id;
  final String name;
  final String phone;
  final String notes;
  final String? memberUserId;
  final bool canConnect;
}

enum TrainerClientWorkoutSource { trainer, member }

class TrainerClientWorkout {
  const TrainerClientWorkout({
    required this.id,
    required this.session,
    required this.notes,
    required this.authorName,
    required this.source,
    required this.version,
    required this.canEdit,
    this.clientId,
  });

  final String id;
  final String? clientId;
  final WorkoutSession session;
  final String notes;
  final String authorName;
  final TrainerClientWorkoutSource source;
  final int version;
  final bool canEdit;
}

class TrainerClientInvitation {
  const TrainerClientInvitation({
    required this.clientId,
    required this.token,
    required this.expiresAt,
  });

  final String clientId;
  final String token;
  final DateTime expiresAt;
}

class TrainerClientLink {
  const TrainerClientLink({
    required this.clientId,
    required this.trainerName,
    required this.clientName,
    required this.isSharing,
  });

  final String clientId;
  final String trainerName;
  final String clientName;
  final bool isSharing;
}

class TrainerClientWorkoutConflict implements Exception {
  const TrainerClientWorkoutConflict();
}

/// 과거 요청 이후 초대·공유 상태가 바뀌어 새 요청이 필요하다.
class TrainerClientInvitationUnavailable implements Exception {
  const TrainerClientInvitationUnavailable();
}

/// 가상 회원 기록은 트레이너 개인 운동 스냅샷과 완전히 분리한다.
/// 초대 수락만 계정을 연결하며 이름이나 번호로 자동 연결하지 않는다.
abstract interface class TrainerClientRepository {
  Future<List<TrainerManagedClient>> listTrainerClients();

  Future<TrainerManagedClient> createTrainerClient({
    required String name,
    required String phone,
    required String notes,
    required String requestId,
  });

  Future<TrainerManagedClient> updateTrainerClient({
    required String clientId,
    required String name,
    required String phone,
    required String notes,
    required String requestId,
  });

  Future<List<TrainerClientWorkout>> listTrainerClientWorkouts(String clientId);

  Future<TrainerClientWorkout> saveTrainerClientWorkout({
    required String clientId,
    required WorkoutSession session,
    required String notes,
    required String requestId,
    required String workoutId,
    required int expectedVersion,
  });

  Future<TrainerClientInvitation> createTrainerClientInvitation({
    required String clientId,
    required DateTime expiresAt,
    required String requestId,
  });

  /// 회원이 직접 수락하며 트레이너 기록 열람과 개인 운동 공유에 동의한다.
  Future<void> acceptTrainerClientInvitation(
    String token, {
    required String requestId,
  });

  Future<List<TrainerClientWorkout>> listMyTrainerClientWorkouts();

  Future<List<TrainerClientLink>> listMyTrainerClientLinks();

  /// 계정 연결과 개인 운동 공유 동의를 즉시 철회한다.
  Future<void> endMyTrainerClientLink(
    String clientId, {
    required String requestId,
  });
}
