import 'dart:typed_data';

import '../models.dart';

enum BusinessApplicationKind {
  trainer('trainer'),
  gym('gym');

  const BusinessApplicationKind(this.databaseValue);

  final String databaseValue;
}

enum BusinessApplicationStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected'),
  unknown('unknown');

  const BusinessApplicationStatus(this.databaseValue);

  final String databaseValue;
}

enum BusinessProfileStatus {
  onboarding('onboarding'),
  pending('pending'),
  approved('approved'),
  verified('verified'),
  rejected('rejected'),
  suspended('suspended'),
  gracePeriod('grace_period'),
  withdrawPending('withdraw_pending'),
  unknown('unknown');

  const BusinessProfileStatus(this.databaseValue);

  final String databaseValue;
}

enum BusinessConsultationStatus {
  pending('pending'),
  answered('answered'),
  assigned('assigned'),
  replied('replied'),
  unknown('unknown');

  const BusinessConsultationStatus(this.databaseValue);

  final String databaseValue;
}

enum BusinessMessageSender {
  member('user'),
  trainer('trainer'),
  gym('gym'),
  unknown('unknown');

  const BusinessMessageSender(this.databaseValue);

  final String databaseValue;
}

enum BusinessRoutineStatus {
  draft('draft'),
  review('review'),
  approved('approved'),
  rejected('rejected'),
  unknown('unknown');

  const BusinessRoutineStatus(this.databaseValue);

  final String databaseValue;
}

enum BusinessRoutineDifficulty {
  beginner('beginner'),
  intermediate('intermediate'),
  advanced('advanced'),
  unknown('unknown');

  const BusinessRoutineDifficulty(this.databaseValue);

  final String databaseValue;
}

enum RoutineShareStatus {
  pending('pending'),
  accepted('accepted'),
  declined('declined'),
  revoked('revoked'),
  expired('expired'),
  unknown('unknown');

  const RoutineShareStatus(this.databaseValue);

  final String databaseValue;
}

enum RoutineShareKind {
  direct('direct'),
  link('link'),
  unknown('unknown');

  const RoutineShareKind(this.databaseValue);

  final String databaseValue;
}

enum BusinessInviteKind {
  member('member'),
  trainer('trainer'),
  unknown('unknown');

  const BusinessInviteKind(this.databaseValue);

  final String databaseValue;
}

enum BusinessInviteStatus {
  pending('pending'),
  accepted('accepted'),
  revoked('revoked'),
  expired('expired'),
  unknown('unknown');

  const BusinessInviteStatus(this.databaseValue);

  final String databaseValue;
}

class BusinessAccess {
  const BusinessAccess({
    required this.userId,
    required this.accountRole,
    required this.resolvedRole,
    required this.availableRoles,
    this.email,
    this.trainer,
    this.gym,
    this.trainerApplication,
    this.gymApplication,
    this.applicationStatus,
    this.rejectReason,
  });

  final String userId;
  final String? email;
  final UserRole accountRole;
  final UserRole resolvedRole;
  final Set<UserRole> availableRoles;
  final TrainerBusinessProfile? trainer;
  final GymBusinessProfile? gym;
  final BusinessApplication? trainerApplication;
  final BusinessApplication? gymApplication;
  final BusinessApplicationStatus? applicationStatus;
  final String? rejectReason;

  bool canUse(UserRole role) => availableRoles.contains(role);
}

sealed class BusinessWorkspaceProfile {
  const BusinessWorkspaceProfile();

  String get id;

  BusinessProfileStatus get status;
}

class TrainerBusinessProfile extends BusinessWorkspaceProfile {
  const TrainerBusinessProfile({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.status,
    required this.isPublic,
    required this.verified,
    required this.rating,
    required this.postCount,
    required this.coachingTotal,
    this.keyword,
    this.intro,
    this.imageUrl,
    this.careerYears,
    this.centerName,
    this.createdAt,
    this.updatedAt,
  });

  @override
  final String id;
  final String userId;
  final String displayName;
  @override
  final BusinessProfileStatus status;
  final bool isPublic;
  final bool verified;
  final double rating;
  final int postCount;
  final int coachingTotal;
  final String? keyword;
  final String? intro;
  final String? imageUrl;
  final int? careerYears;
  final String? centerName;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

class GymBusinessProfile extends BusinessWorkspaceProfile {
  const GymBusinessProfile({
    required this.id,
    required this.ownerUserId,
    required this.name,
    required this.status,
    this.representativeName,
    this.gymType,
    this.address,
    this.description,
    this.coverImageUrl,
    this.businessNumber,
    this.planTier,
    this.createdAt,
    this.updatedAt,
  });

  @override
  final String id;
  final String ownerUserId;
  final String name;
  @override
  final BusinessProfileStatus status;
  final String? representativeName;
  final String? gymType;
  final String? address;
  final String? description;
  final String? coverImageUrl;
  final String? businessNumber;
  final String? planTier;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

class BusinessDashboardMetrics {
  const BusinessDashboardMetrics({
    this.unreadConsultations = 0,
    this.activeMembers = 0,
    this.pendingSettlement = 0,
    this.monthSettled = 0,
    this.overdueFeedbacks = 0,
    this.totalRevenue = 0,
    this.trainerCount = 0,
  });

  final int unreadConsultations;
  final int activeMembers;
  final double pendingSettlement;
  final double monthSettled;
  final int overdueFeedbacks;
  final double totalRevenue;
  final int trainerCount;
}

class BusinessWorkspaceData {
  const BusinessWorkspaceData({
    required this.role,
    required this.access,
    required this.dashboardStats,
    this.profile,
    this.members = const [],
    this.assignments = const [],
    this.trainers = const [],
    this.consultations = const [],
    this.ownedRoutines = const [],
    this.applications = const [],
    this.memberSharingPreferences,
  });

  final UserRole role;
  final BusinessAccess access;
  final BusinessWorkspaceProfile? profile;
  final BusinessDashboardMetrics dashboardStats;
  final List<BusinessMember> members;
  final List<BusinessMemberAssignment> assignments;
  final List<GymTrainerRecord> trainers;
  final List<BusinessConsultation> consultations;
  final List<OwnedCoachingRoutine> ownedRoutines;
  final List<BusinessApplication> applications;
  final MemberSharingPreferences? memberSharingPreferences;

  BusinessDashboardMetrics get dashboard => dashboardStats;

  List<GymTrainerRecord> get gymTrainers => trainers;

  List<OwnedCoachingRoutine> get routines => ownedRoutines;
}

typedef BusinessWorkspace = BusinessWorkspaceData;

class BusinessMember {
  const BusinessMember({
    required this.id,
    required this.gymId,
    required this.name,
    required this.remainingPtSessions,
    this.completionRate = 0,
    this.userId,
    this.phone,
    this.avatarUrl,
    this.goal,
    this.level,
    this.createdAt,
    this.lastActivityAt,
    this.gymName,
    this.status = 'active',
    this.endedAt,
  });

  final String id;
  final String gymId;
  final String? userId;
  final String name;
  final String? phone;
  final String? avatarUrl;
  final String? goal;
  final String? level;
  final int remainingPtSessions;
  final double completionRate;
  final DateTime? createdAt;
  final DateTime? lastActivityAt;
  final String? gymName;
  final String status;
  final DateTime? endedAt;

  bool get isActive => status == 'active';
}

class EndBusinessMembershipInput {
  const EndBusinessMembershipInput({
    required this.memberId,
    required this.requestId,
  });

  final String memberId;
  final String requestId;
}

class BusinessMemberDetail {
  const BusinessMemberDetail({
    required this.memberId,
    required this.shareBodyData,
    required this.shareWorkoutRecords,
    required this.canReadWorkouts,
    required this.sessions,
    this.memberUserId,
  });

  final String memberId;
  final String? memberUserId;
  final bool shareBodyData;
  final bool shareWorkoutRecords;
  final bool canReadWorkouts;
  final List<BusinessWorkoutSession> sessions;
}

class MemberSharingPreferences {
  const MemberSharingPreferences({
    required this.shareBodyData,
    required this.shareWorkoutRecords,
    required this.marketing,
  });

  final bool shareBodyData;
  final bool shareWorkoutRecords;
  final bool marketing;
}

class BusinessWorkoutSession {
  const BusinessWorkoutSession({
    required this.id,
    required this.userId,
    required this.date,
    required this.exercises,
    required this.feedbacks,
    this.category,
    this.intensity,
    this.feedback,
    this.startedAt,
    this.endedAt,
  });

  final String id;
  final String userId;
  final DateTime date;
  final String? category;
  final String? intensity;
  final String? feedback;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final List<BusinessWorkoutExercise> exercises;
  final List<BusinessSessionFeedback> feedbacks;

  int get totalSets =>
      exercises.fold(0, (sum, exercise) => sum + exercise.sets.length);

  int get completedSets => exercises.fold(
    0,
    (sum, exercise) => sum + exercise.sets.where((set) => set.completed).length,
  );

  double get completionRate => totalSets == 0 ? 0 : completedSets / totalSets;

  double get totalVolumeKg => exercises.fold(
    0,
    (sum, exercise) =>
        sum +
        exercise.sets
            .where((set) => set.completed)
            .fold(0, (value, set) => value + set.weight * set.reps),
  );

  int get cardioDurationSeconds => exercises.fold(
    0,
    (sum, exercise) =>
        sum +
        exercise.sets
            .where((set) => set.completed)
            .fold(0, (value, set) => value + (set.durationSeconds ?? 0)),
  );
}

class BusinessWorkoutExercise {
  const BusinessWorkoutExercise({
    required this.id,
    required this.name,
    required this.orderIndex,
    required this.sets,
    this.baseExerciseId,
    this.targetMuscle,
  });

  final String id;
  final String? baseExerciseId;
  final String name;
  final String? targetMuscle;
  final int orderIndex;
  final List<BusinessWorkoutSet> sets;
}

class BusinessWorkoutSet {
  const BusinessWorkoutSet({
    required this.id,
    required this.setNumber,
    required this.type,
    required this.weight,
    required this.reps,
    required this.completed,
    required this.restSeconds,
    this.durationSeconds,
    this.distanceMeters,
    this.intensityRpe,
    this.rir,
    this.memo,
    this.completedAt,
    this.estimated1Rm,
  });

  final String id;
  final int setNumber;
  final String type;
  final double weight;
  final int reps;
  final int? durationSeconds;
  final double? distanceMeters;
  final double? intensityRpe;
  final int? rir;
  final String? memo;
  final bool completed;
  final DateTime? completedAt;
  final double? estimated1Rm;
  final int restSeconds;
}

class BusinessSessionFeedback {
  const BusinessSessionFeedback({
    required this.id,
    required this.sessionId,
    required this.authorName,
    required this.text,
    required this.createdAt,
    this.trainerUserId,
  });

  final String id;
  final String sessionId;
  final String? trainerUserId;
  final String authorName;
  final String text;
  final DateTime createdAt;
}

class MemberSessionFeedback {
  const MemberSessionFeedback({
    required this.id,
    required this.sessionId,
    required this.sessionDate,
    required this.authorName,
    required this.text,
    required this.createdAt,
    this.trainerUserId,
  });

  final String id;
  final String sessionId;
  final DateTime sessionDate;
  final String? trainerUserId;
  final String authorName;
  final String text;
  final DateTime createdAt;
}

class SendSessionFeedbackInput {
  const SendSessionFeedbackInput({
    required this.sessionId,
    required this.text,
    this.requestId,
  });

  final String sessionId;
  final String text;
  final String? requestId;
}

class BusinessCoachingSchedule {
  const BusinessCoachingSchedule({
    required this.id,
    required this.trainerId,
    required this.title,
    required this.date,
    required this.startMinutes,
    required this.endMinutes,
    required this.createdAt,
    this.memberUserId,
    this.gymId,
    this.trainerName,
    this.memberName,
    this.gymName,
    this.completedAt,
  });

  final String id;
  final String trainerId;
  final String? memberUserId;
  final String? gymId;
  final String title;
  final DateTime date;
  final int startMinutes;
  final int endMinutes;
  final String? trainerName;
  final String? memberName;
  final String? gymName;
  final DateTime createdAt;
  final DateTime? completedAt;

  bool get isCompleted => completedAt != null;
}

class CreateCoachingScheduleInput {
  const CreateCoachingScheduleInput({
    required this.requestId,
    required this.trainerId,
    required this.title,
    required this.date,
    required this.startMinutes,
    required this.endMinutes,
    this.memberUserId,
    this.gymId,
  });

  final String requestId;
  final String trainerId;
  final String? memberUserId;
  final String? gymId;
  final String title;
  final DateTime date;
  final int startMinutes;
  final int endMinutes;
}

enum CoachingScheduleConflictTarget { trainer, member }

class CoachingScheduleConflictException implements Exception {
  const CoachingScheduleConflictException(this.target);

  final CoachingScheduleConflictTarget target;

  @override
  String toString() => switch (target) {
    CoachingScheduleConflictTarget.trainer => '선택한 시간에 트레이너의 다른 일정이 있습니다.',
    CoachingScheduleConflictTarget.member => '선택한 시간에 회원의 다른 일정이 있습니다.',
  };
}

class BusinessMemberAssignment {
  const BusinessMemberAssignment({
    required this.id,
    required this.gymId,
    required this.memberId,
    required this.active,
    this.trainerId,
    this.trainerName,
    this.assignedAt,
  });

  final String id;
  final String gymId;
  final String memberId;
  final String? trainerId;
  final String? trainerName;
  final bool active;
  final DateTime? assignedAt;
}

class GymTrainerRecord {
  const GymTrainerRecord({
    required this.id,
    required this.gymId,
    required this.status,
    required this.memberCount,
    required this.averageRating,
    required this.monthlySales,
    this.feedbackFulfillmentRate = 0,
    this.trainerId,
    this.trainerUserId,
    this.displayName,
    this.roleTitle,
    this.imageUrl,
    this.createdAt,
  });

  final String id;
  final String gymId;
  final String? trainerId;
  final String? trainerUserId;
  final String? displayName;
  final String? roleTitle;
  final String? imageUrl;
  final String status;
  final int memberCount;
  final double averageRating;
  final double monthlySales;
  final double feedbackFulfillmentRate;
  final DateTime? createdAt;
}

class BusinessInviteRecord {
  const BusinessInviteRecord({
    required this.id,
    required this.gymId,
    required this.kind,
    required this.status,
    required this.createdByUserId,
    required this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
    this.memberId,
    this.recipientName,
    this.recipientPhone,
    this.roleTitle,
    this.acceptedByUserId,
    this.acceptedMemberId,
    this.acceptedTrainerId,
    this.acceptedGymTrainerId,
    this.acceptedAt,
    this.revokedAt,
  });

  final String id;
  final String gymId;
  final BusinessInviteKind kind;
  final BusinessInviteStatus status;
  final String createdByUserId;
  final String? memberId;
  final String? recipientName;
  final String? recipientPhone;
  final String? roleTitle;
  final DateTime expiresAt;
  final String? acceptedByUserId;
  final String? acceptedMemberId;
  final String? acceptedTrainerId;
  final String? acceptedGymTrainerId;
  final DateTime? acceptedAt;
  final DateTime? revokedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class BusinessInviteCreation {
  const BusinessInviteCreation({
    required this.invite,
    required this.tokenIssued,
    this.token,
    this.uri,
  });

  final BusinessInviteRecord invite;
  final bool tokenIssued;
  final String? token;
  final Uri? uri;
}

class BusinessInviteAcceptance {
  const BusinessInviteAcceptance({
    required this.accepted,
    required this.invite,
    this.memberId,
    this.trainerId,
    this.gymTrainerId,
  });

  final bool accepted;
  final BusinessInviteRecord invite;
  final String? memberId;
  final String? trainerId;
  final String? gymTrainerId;
}

class PublicTrainer {
  const PublicTrainer({
    required this.profile,
    this.certifications = const [],
    this.specialties = const [],
  });

  final TrainerBusinessProfile profile;
  final List<String> certifications;
  final List<String> specialties;
}

class PublicTrainerSearchPage {
  const PublicTrainerSearchPage({required this.items, this.nextCursor});

  final List<PublicTrainer> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

class TopCoachingTrainer {
  const TopCoachingTrainer({
    required this.trainer,
    required this.activeCoachingCount,
  });

  final PublicTrainer trainer;
  final int activeCoachingCount;
}

/// Normalizes a directory query before it is sent to the server.
///
/// An empty query means "browse". One-character searches are intentionally
/// supported for Korean surnames, while the upper bound keeps every request
/// small and predictable.
String normalizePublicTrainerSearchQuery(String query) {
  final normalized = query.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.runes.length > 50) {
    throw ArgumentError.value(query, 'query', 'Must be at most 50 characters.');
  }
  return normalized;
}

int validatePublicTrainerSearchPageSize(int pageSize) {
  if (pageSize < 1 || pageSize > 30) {
    throw ArgumentError.value(
      pageSize,
      'pageSize',
      'Must be between 1 and 30.',
    );
  }
  return pageSize;
}

int validateTopCoachingTrainerLimit(int limit) {
  if (limit < 1 || limit > 3) {
    throw ArgumentError.value(limit, 'limit', 'Must be between 1 and 3.');
  }
  return limit;
}

/// Optional capability so existing repositories and test doubles do not need
/// to implement directory pagination until they support the server contract.
abstract interface class PublicTrainerSearchRepository {
  Future<PublicTrainerSearchPage> searchPublicTrainers({
    String query = '',
    String? cursor,
    int pageSize = 20,
  });
}

/// Optional capability so existing repositories and test doubles remain
/// compatible while live repositories use the server-owned active count.
abstract interface class TopCoachingTrainerRepository {
  Future<List<TopCoachingTrainer>> listTopCoachingTrainers({int limit = 3});
}

/// Optional capability for withdrawing a consultation-scoped survey share.
abstract interface class ConsultationRecommendationProfileShareRepository {
  Future<void> revokeRecommendationProfileShare(String consultationId);
}

class BusinessConsultation {
  const BusinessConsultation({
    required this.id,
    required this.userId,
    required this.status,
    required this.isRead,
    required this.messages,
    this.trainerId,
    this.gymId,
    this.routineId,
    this.assignedTrainerId,
    this.memberName,
    this.memberAvatarUrl,
    this.trainerName,
    this.gymName,
    this.specialty,
    this.goal,
    this.level,
    this.question,
    this.createdAt,
    this.sharedRecommendationProfile,
    this.recommendationProfileSharedAt,
    this.recommendationProfileShareRevokedAt,
  });

  final String id;
  final String userId;
  final String? trainerId;
  final String? gymId;
  final String? routineId;
  final String? assignedTrainerId;
  final BusinessConsultationStatus status;
  final bool isRead;
  final String? memberName;
  final String? memberAvatarUrl;
  final String? trainerName;
  final String? gymName;
  final String? specialty;
  final String? goal;
  final String? level;
  final String? question;
  final DateTime? createdAt;
  final RecommendationProfile? sharedRecommendationProfile;
  final DateTime? recommendationProfileSharedAt;
  final DateTime? recommendationProfileShareRevokedAt;
  final List<BusinessConsultationMessage> messages;
}

class BusinessConsultationMessage {
  const BusinessConsultationMessage({
    required this.id,
    required this.consultationId,
    required this.sender,
    required this.text,
    this.senderId,
    this.createdAt,
  });

  final String id;
  final String consultationId;
  final BusinessMessageSender sender;
  final String? senderId;
  final String text;
  final DateTime? createdAt;
}

class BusinessApplication {
  const BusinessApplication({
    required this.id,
    required this.kind,
    required this.status,
    required this.applicantName,
    this.userId,
    this.profileId,
    this.businessNumber,
    this.rejectReason,
    this.reviewerId,
    this.submittedAt,
    this.slaDueAt,
  });

  final String id;
  final BusinessApplicationKind kind;
  final BusinessApplicationStatus status;
  final String applicantName;
  final String? userId;
  final String? profileId;
  final String? businessNumber;
  final String? rejectReason;
  final String? reviewerId;
  final DateTime? submittedAt;
  final DateTime? slaDueAt;
}

class OwnedCoachingRoutine {
  const OwnedCoachingRoutine({
    required this.id,
    required this.title,
    required this.status,
    required this.difficulty,
    required this.exercises,
    required this.cumulativeUsers,
    this.trainerId,
    this.gymId,
    this.intro,
    this.price,
    this.rejectReason,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? trainerId;
  final String? gymId;
  final String title;
  final String? intro;
  final double? price;
  final BusinessRoutineDifficulty difficulty;
  final BusinessRoutineStatus status;
  final String? rejectReason;
  final int cumulativeUsers;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<OwnedRoutineExercise> exercises;
}

class OwnedRoutineExercise {
  const OwnedRoutineExercise({
    required this.id,
    required this.routineId,
    required this.name,
    required this.targetMuscle,
    required this.orderIndex,
    required this.sets,
    this.baseExerciseId,
  });

  final String id;
  final String routineId;
  final String? baseExerciseId;
  final String name;
  final String targetMuscle;
  final int orderIndex;
  final List<OwnedRoutineSet> sets;
}

class OwnedRoutineSet {
  const OwnedRoutineSet({
    required this.id,
    required this.exerciseId,
    required this.setNumber,
    required this.type,
    this.targetWeight,
    this.targetReps,
    this.restSeconds = 90,
    this.durationSeconds,
    this.distanceMeters,
    this.intensityRpe,
  });

  final String id;
  final String exerciseId;
  final int setNumber;
  final String type;
  final double? targetWeight;
  final int? targetReps;
  final int restSeconds;
  final int? durationSeconds;
  final double? distanceMeters;
  final double? intensityRpe;
}

class RoutineShareRecord {
  const RoutineShareRecord({
    required this.id,
    required this.routineId,
    required this.senderUserId,
    required this.status,
    required this.kind,
    required this.routineTitle,
    required this.senderName,
    this.recipientUserId,
    this.message,
    this.expiresAt,
    this.respondedAt,
    this.acceptedRoutineId,
    this.createdAt,
    this.routine,
  });

  final String id;
  final String routineId;
  final String senderUserId;
  final String? recipientUserId;
  final RoutineShareStatus status;
  final RoutineShareKind kind;
  final String routineTitle;
  final String senderName;
  final String? message;
  final DateTime? expiresAt;
  final DateTime? respondedAt;
  final String? acceptedRoutineId;
  final DateTime? createdAt;
  final OwnedCoachingRoutine? routine;
}

class RoutineShareLink {
  const RoutineShareLink({
    required this.shareId,
    required this.token,
    required this.uri,
    required this.expiresAt,
  });

  final String shareId;
  final String token;
  final Uri uri;
  final DateTime expiresAt;
}

/// The link RPC may have committed, but its one-time raw bearer token did not
/// reach the client. The token is intentionally not persisted or replayed.
class RoutineShareLinkResultUncertainException implements Exception {
  const RoutineShareLinkResultUncertainException([this.cause]);

  final Object? cause;

  @override
  String toString() =>
      'RoutineShareLinkResultUncertainException: '
      'the one-time share token could not be confirmed';
}

class PersonalRoutineRecord {
  const PersonalRoutineRecord({
    required this.id,
    required this.ownerUserId,
    required this.name,
    required this.exercises,
    this.description,
    this.color,
    this.source,
    this.marketRoutineId,
    this.sourceCoachingRoutineId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String ownerUserId;
  final String name;
  final String? description;
  final String? color;
  final String? source;
  final String? marketRoutineId;
  final String? sourceCoachingRoutineId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<OwnedRoutineExercise> exercises;
}

class CreateConsultationInput {
  const CreateConsultationInput({
    required this.requestId,
    required this.question,
    this.trainerId,
    this.gymId,
    this.routineId,
    this.specialty,
    this.goal,
    this.level,
    this.recommendationProfile,
  });

  final String requestId;
  final String? trainerId;
  final String? gymId;
  final String? routineId;
  final String? specialty;
  final String? goal;
  final String? level;
  final RecommendationProfile? recommendationProfile;
  final String question;
}

class TrainerApplicationInput {
  const TrainerApplicationInput({
    required this.displayName,
    required this.credentialNumber,
    required this.documents,
    this.keyword,
    this.intro,
    this.profileImageUrl,
    this.careerYears,
    this.centerName,
  });

  final String displayName;
  final String credentialNumber;
  final List<TrainerApplicationDocumentInput> documents;
  final String? keyword;
  final String? intro;
  final String? profileImageUrl;
  final int? careerYears;
  final String? centerName;
}

enum TrainerApplicationDocumentType {
  nationalCertificate('national'),
  privateCertificate('private'),
  identity('id'),
  award('award');

  const TrainerApplicationDocumentType(this.databaseValue);

  final String databaseValue;
}

class TrainerApplicationDocumentInput {
  const TrainerApplicationDocumentInput({
    required this.type,
    required this.bytes,
    required this.fileName,
    required this.contentType,
  });

  final TrainerApplicationDocumentType type;
  final Uint8List bytes;
  final String fileName;
  final String contentType;
}

class GymApplicationInput {
  const GymApplicationInput({
    required this.gymName,
    required this.businessNumber,
    this.ownerName,
    this.gymType,
    this.address,
    this.description,
    this.coverImageUrl,
  });

  final String gymName;
  final String? ownerName;
  final String businessNumber;
  final String? gymType;
  final String? address;
  final String? description;
  final String? coverImageUrl;
}

class ReviewBusinessApplicationInput {
  const ReviewBusinessApplicationInput({
    required this.kind,
    required this.applicationId,
    required this.approve,
    this.rejectReason,
  });

  final BusinessApplicationKind kind;
  final String applicationId;
  final bool approve;
  final String? rejectReason;
}

class UpdateBusinessProfileInput {
  const UpdateBusinessProfileInput.trainer({
    required this.profileId,
    this.displayName,
    this.keyword,
    this.intro,
    this.imageUrl,
    this.careerYears,
    this.centerName,
    this.isPublic,
  }) : role = UserRole.trainer,
       name = null,
       representativeName = null,
       gymType = null,
       address = null,
       description = null;

  const UpdateBusinessProfileInput.gym({
    required this.profileId,
    this.name,
    this.representativeName,
    this.gymType,
    this.address,
    this.description,
    this.imageUrl,
  }) : role = UserRole.gym,
       displayName = null,
       keyword = null,
       intro = null,
       careerYears = null,
       centerName = null,
       isPublic = null;

  final UserRole role;
  final String profileId;
  final String? displayName;
  final String? keyword;
  final String? intro;
  final String? imageUrl;
  final int? careerYears;
  final String? centerName;
  final bool? isPublic;
  final String? name;
  final String? representativeName;
  final String? gymType;
  final String? address;
  final String? description;
}

class AssignMemberInput {
  const AssignMemberInput({
    required this.gymId,
    required this.memberId,
    this.trainerId,
  });

  final String gymId;
  final String memberId;
  final String? trainerId;
}

class CreateBusinessInviteInput {
  const CreateBusinessInviteInput({
    required this.gymId,
    required this.kind,
    required this.expiresAt,
    required this.requestId,
    this.memberId,
    this.recipientName,
    this.recipientPhone,
    this.roleTitle,
  });

  final String gymId;
  final BusinessInviteKind kind;
  final DateTime expiresAt;
  final String requestId;
  final String? memberId;
  final String? recipientName;
  final String? recipientPhone;
  final String? roleTitle;
}

class ReplyConsultationInput {
  const ReplyConsultationInput({
    required this.requestId,
    required this.consultationId,
    required this.message,
  });

  final String requestId;
  final String consultationId;
  final String message;
}

class AssignConsultationInput {
  const AssignConsultationInput({
    required this.requestId,
    required this.consultationId,
    required this.gymId,
    required this.trainerId,
  });

  final String requestId;
  final String consultationId;
  final String gymId;
  final String trainerId;
}

class CreateOwnedRoutineInput {
  const CreateOwnedRoutineInput({
    required this.ownerRole,
    required this.title,
    required this.difficulty,
    required this.exercises,
    this.intro,
    this.price,
    this.requestId,
  });

  final UserRole ownerRole;
  final String title;
  final String? intro;
  final double? price;
  final BusinessRoutineDifficulty difficulty;
  final List<CreateOwnedRoutineExerciseInput> exercises;
  final String? requestId;
}

class CreateOwnedRoutineExerciseInput {
  const CreateOwnedRoutineExerciseInput({
    required this.name,
    required this.targetMuscle,
    required this.sets,
    this.baseExerciseId,
  });

  final String? baseExerciseId;
  final String name;
  final String targetMuscle;
  final List<CreateOwnedRoutineSetInput> sets;
}

class CreateOwnedRoutineSetInput {
  const CreateOwnedRoutineSetInput({
    required this.setNumber,
    this.type = 'normal',
    this.targetWeight,
    this.targetReps,
    this.restSeconds = 90,
    this.durationSeconds,
    this.distanceMeters,
    this.intensityRpe,
  });

  final int setNumber;
  final String type;
  final double? targetWeight;
  final int? targetReps;
  final int restSeconds;
  final int? durationSeconds;
  final double? distanceMeters;
  final double? intensityRpe;
}

class UpdateOwnedRoutineInput {
  const UpdateOwnedRoutineInput({
    required this.routineId,
    required this.ownerRole,
    required this.title,
    required this.difficulty,
    required this.exercises,
    this.intro,
    this.price,
    this.requestId,
  });

  final String routineId;
  final UserRole ownerRole;
  final String title;
  final String? intro;
  final double? price;
  final BusinessRoutineDifficulty difficulty;
  final List<CreateOwnedRoutineExerciseInput> exercises;
  final String? requestId;
}

class SavePersonalRoutineInput {
  const SavePersonalRoutineInput({
    required this.routineId,
    required this.name,
    required this.color,
    required this.exercises,
    this.description,
    this.requestId,
  });

  final String routineId;
  final String name;
  final String? description;
  final String color;
  final List<CreateOwnedRoutineExerciseInput> exercises;
  final String? requestId;
}

class ReviewOwnedRoutineInput {
  const ReviewOwnedRoutineInput({
    required this.routineId,
    required this.approve,
    this.rejectReason,
    this.accessTier = RoutineAccessTier.free,
    this.requestId,
  });

  final String routineId;
  final bool approve;
  final String? rejectReason;
  final RoutineAccessTier accessTier;
  final String? requestId;
}

class ShareOwnedRoutineInput {
  const ShareOwnedRoutineInput({
    required this.routineId,
    required this.memberIds,
    this.message,
    this.expiresAt,
    this.requestId,
  });

  final String routineId;
  final List<String> memberIds;
  final String? message;
  final DateTime? expiresAt;
  final String? requestId;
}

abstract interface class BusinessRepository {
  Future<BusinessAccess> loadAccess();

  Future<BusinessWorkspaceData> loadWorkspace(UserRole role);

  Future<List<PublicTrainer>> listPublicTrainers();

  Future<List<BusinessConsultation>> listMyConsultations();

  Future<MemberSharingPreferences> loadMySharingPreferences();

  Future<MemberSharingPreferences> updateMySharingPreferences(
    MemberSharingPreferences preferences,
  );

  Future<BusinessConsultation> createConsultation(
    CreateConsultationInput input,
  );

  Future<BusinessApplication> submitTrainerApplication(
    TrainerApplicationInput input,
  );

  Future<BusinessApplication> submitGymApplication(GymApplicationInput input);

  Future<List<BusinessApplication>> listApplications({
    BusinessApplicationStatus? status,
  });

  Future<BusinessApplication> reviewApplication(
    ReviewBusinessApplicationInput input,
  );

  Future<void> updateProfile(UpdateBusinessProfileInput input);

  Future<BusinessMemberAssignment?> assignMember(AssignMemberInput input);

  Future<BusinessInviteCreation> createBusinessInvite(
    CreateBusinessInviteInput input,
  );

  Future<List<BusinessInviteRecord>> listBusinessInvites(
    String gymId, {
    BusinessInviteStatus? status,
  });

  Future<BusinessInviteAcceptance> acceptBusinessInvite(
    String token, {
    required String requestId,
  });

  Future<BusinessInviteRecord> revokeBusinessInvite(
    String inviteId, {
    required String requestId,
  });

  Future<BusinessMemberDetail> loadMemberDetail(
    String memberId, {
    DateTime? from,
    DateTime? to,
  });

  Future<BusinessSessionFeedback> sendSessionFeedback(
    SendSessionFeedbackInput input,
  );

  Future<List<BusinessCoachingSchedule>> listCoachingSchedules({
    DateTime? from,
    DateTime? to,
  });

  Future<BusinessCoachingSchedule> createCoachingSchedule(
    CreateCoachingScheduleInput input,
  );

  Future<BusinessCoachingSchedule> setCoachingScheduleCompleted(
    String scheduleId, {
    required String trainerId,
    required bool completed,
  });

  Future<void> deleteCoachingSchedule(
    String scheduleId, {
    required String trainerId,
  });

  Future<BusinessConsultation> replyConsultation(ReplyConsultationInput input);

  Future<BusinessConsultation> assignConsultation(
    AssignConsultationInput input,
  );

  Future<OwnedCoachingRoutine> createOwnedRoutine(
    CreateOwnedRoutineInput input,
  );

  Future<OwnedCoachingRoutine> updateOwnedRoutine(
    UpdateOwnedRoutineInput input,
  );

  Future<OwnedCoachingRoutine> submitOwnedRoutineForReview(
    String routineId, {
    String? requestId,
  });

  Future<List<OwnedCoachingRoutine>> listRoutineReviews();

  Future<OwnedCoachingRoutine> reviewOwnedRoutine(
    ReviewOwnedRoutineInput input,
  );

  Future<List<RoutineShareRecord>> shareOwnedRoutine(
    ShareOwnedRoutineInput input,
  );

  Future<RoutineShareLink> createRoutineShareLink(
    String routineId, {
    DateTime? expiresAt,
    String? requestId,
  });

  Future<List<RoutineShareRecord>> listIncomingRoutineShares();

  Future<List<RoutineShareRecord>> listOutgoingRoutineShares({
    String? routineId,
  });

  Future<PersonalRoutineRecord?> respondRoutineShare(
    String shareId, {
    required bool accept,
    String? requestId,
  });

  Future<PersonalRoutineRecord> acceptRoutineShareToken(
    String token, {
    String? requestId,
  });

  Future<PersonalRoutineRecord> importMarketRoutine(
    String marketRoutineId, {
    String? requestId,
  });

  Future<List<PersonalRoutineRecord>> listPersonalRoutines();

  Future<PersonalRoutineRecord> savePersonalRoutine(
    SavePersonalRoutineInput input,
  );

  Future<void> deletePersonalRoutine(String routineId, {String? requestId});
}

/// Optional live-data capability for the signed-in member's coach feedback.
///
/// This is separate from [BusinessRepository] so existing implementations can
/// keep serving business workspaces without pretending to support this feed.
abstract interface class MemberSessionFeedbackRepository {
  Future<List<MemberSessionFeedback>> listMySessionFeedback({
    DateTime? from,
    DateTime? to,
  });
}

abstract interface class BusinessMembershipRepository {
  Future<List<BusinessMember>> listMyBusinessMemberships();

  Future<BusinessMember> endBusinessMembership(
    EndBusinessMembershipInput input,
  );
}

/// Optional capability for revoking a still-pending routine share.
///
/// Kept separate from [BusinessRepository] so lightweight/demo repositories do
/// not claim that they can cancel server shares. Implementations must enforce
/// sender ownership and the pending-state transition on the server.
abstract interface class RoutineShareRevocationRepository {
  Future<RoutineShareRecord> revokeRoutineShare(
    String shareId, {
    required String requestId,
  });
}
