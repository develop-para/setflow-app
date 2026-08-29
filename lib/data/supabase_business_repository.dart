import 'dart:convert';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../services/user_image_optimizer.dart';
import 'business_repository.dart';

const _memberConsultationPageSize = 200;

const _consultationSelect = '''
  id,
  user_id,
  trainer_id,
  gym_id,
  routine_id,
  status,
  requester_name,
  specialty,
  goal,
  level,
  question,
  is_read,
  assigned_trainer_id,
  consultation_mode,
  matching_source,
  requested_region_code,
  created_at,
  recommendation_profile_share:consultation_recommendation_profile_shares(
    schema_version,
    profile_snapshot,
    consented_at,
    revoked_at
  ),
  member:users!consultations_user_id_fkey(
    id,
    nickname,
    avatar_url
  ),
  trainer:trainers!consultations_trainer_id_fkey(
    id,
    display_name
  ),
  assigned_trainer:trainers!consultations_assigned_trainer_id_fkey(
    id,
    display_name
  ),
  gym:gyms!fk_consult_gym(
    id,
    name
  ),
  messages:consultation_messages(
    id,
    consultation_id,
    sender_type,
    sender_id,
    text,
    created_at
  )
''';

const _routineSelect = '''
  id,
  trainer_id,
  gym_id,
  title,
  intro,
  price,
  difficulty,
  status,
  reject_reason,
  cumulative_users,
  created_at,
  updated_at,
  exercises:coaching_routine_exercises(
    id,
    routine_id,
    base_exercise_id,
    name,
    target_muscle,
    order_index,
    sets:coaching_routine_sets(
      id,
      routine_exercise_id,
      set_no,
      type,
      target_weight,
      target_reps,
      duration_sec,
      distance_m,
      intensity_rpe,
      rest_seconds
    )
  )
''';

const _personalRoutineSelect = '''
  id,
  owner_user_id,
  name,
  description,
  color,
  source,
  market_routine_id,
  source_coaching_routine_id,
  created_at,
  updated_at,
  exercises:routine_exercises(
    id,
    routine_id,
    base_exercise_id,
    name,
    target_muscle,
    order_index,
    sets:routine_sets(
      id,
      routine_exercise_id,
      set_no,
      type,
      target_weight,
      target_reps,
      duration_sec,
      distance_m,
      intensity_rpe,
      rest_seconds
    )
  )
''';

const _routineShareSelect =
    '''
  id,
  coaching_routine_id,
  share_type,
  sender_user_id,
  recipient_user_id,
  message,
  status,
  expires_at,
  accepted_routine_id,
  created_at,
  responded_at,
  routine:coaching_routines!routine_shares_coaching_routine_id_fkey(
    $_routineSelect
  ),
  sender_trainer:trainers!routine_shares_sender_trainer_id_fkey(
    display_name
  ),
  sender_gym:gyms!routine_shares_sender_gym_id_fkey(
    name
  ),
  sender:users!routine_shares_sender_user_id_fkey(
    nickname
  )
''';

const _businessInviteSelect = '''
  id,
  gym_id,
  invite_kind,
  member_id,
  created_by_user_id,
  recipient_name,
  recipient_phone,
  role_title,
  status,
  expires_at,
  accepted_by_user_id,
  accepted_member_id,
  accepted_trainer_id,
  accepted_gym_trainer_id,
  accepted_at,
  revoked_at,
  created_at,
  updated_at
''';

const _coachingScheduleSelect = '''
  id,
  trainer_id,
  member_user_id,
  gym_id,
  title,
  date,
  start_time,
  end_time,
  completed_at,
  created_at,
  trainer:trainers!coaching_schedules_trainer_id_fkey(
    display_name
  ),
  member:users!coaching_schedules_member_user_id_fkey(
    nickname
  ),
  gym:gyms(
    name
  )
''';

class SupabaseBusinessRepository
    implements
        BusinessRepository,
        PublicTrainerSearchRepository,
        TopCoachingTrainerRepository,
        MemberSessionFeedbackRepository,
        BusinessMembershipRepository,
        WorkoutLocationRepository,
        TrainerConsultationSettingsRepository,
        RoutineShareRevocationRepository,
        ConsultationRecommendationProfileShareRepository {
  const SupabaseBusinessRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<BusinessAccess> loadAccess() async {
    final authUser = _requireUser();
    final results = await Future.wait<Object?>([
      _client
          .from('users')
          .select('id,email,role')
          .eq('id', authUser.id)
          .maybeSingle(),
      _client.rpc('get_my_trainer_profile'),
      _client.rpc('get_my_gym_profile'),
      _client
          .from('trainer_applications')
          .select(
            'id,trainer_id,user_id,name,submitted_at,sla_due_at,status,'
            'reject_reason,reviewer_id',
          )
          .eq('user_id', authUser.id)
          .order('submitted_at', ascending: false)
          .limit(1)
          .maybeSingle(),
      _client
          .from('gym_applications')
          .select(
            'id,gym_id,owner_user_id,gym_name,owner_name,biz_reg_no,'
            'submitted_at,sla_due_at,status,reject_reason,reviewer_id',
          )
          .eq('owner_user_id', authUser.id)
          .order('submitted_at', ascending: false)
          .limit(1)
          .maybeSingle(),
      _client.rpc('is_admin'),
    ]);

    final userRow = _mapValue(results[0]);
    if (userRow == null) {
      throw StateError('Authenticated user has no public users row.');
    }
    final userId = _requiredUuid(userRow, 'id');
    final accountRole = _userRoleFromDatabase(userRow['role']);
    final trainerRow = _mapValue(results[1]);
    final gymRow = _mapValue(results[2]);
    final trainer = trainerRow == null ? null : _trainerFromRow(trainerRow);
    final gym = gymRow == null ? null : _gymFromRow(gymRow);
    final trainerApplicationRow = _mapValue(results[3]);
    final gymApplicationRow = _mapValue(results[4]);
    final isActiveAdmin = _boolValue(results[5]);
    final trainerApplication = trainerApplicationRow == null
        ? null
        : _applicationFromRow(
            trainerApplicationRow,
            BusinessApplicationKind.trainer,
          );
    final gymApplication = gymApplicationRow == null
        ? null
        : _applicationFromRow(gymApplicationRow, BusinessApplicationKind.gym);

    final availableRoles = <UserRole>{};
    if (accountRole == UserRole.guest) {
      availableRoles.add(UserRole.guest);
    } else {
      availableRoles.add(UserRole.member);
    }
    if (trainer?.status == BusinessProfileStatus.approved) {
      availableRoles.add(UserRole.trainer);
    }
    if (gym?.status == BusinessProfileStatus.verified) {
      availableRoles.add(UserRole.gym);
    }
    if (isActiveAdmin) availableRoles.add(UserRole.admin);

    final resolvedRole = availableRoles.contains(accountRole)
        ? accountRole
        : availableRoles.contains(UserRole.admin)
        ? UserRole.admin
        : availableRoles.contains(UserRole.trainer)
        ? UserRole.trainer
        : availableRoles.contains(UserRole.gym)
        ? UserRole.gym
        : availableRoles.first;
    final currentApplication = _currentApplication(
      accountRole,
      trainerApplication,
      gymApplication,
    );

    return BusinessAccess(
      userId: userId,
      email: _nullableString(userRow['email']) ?? authUser.email,
      accountRole: accountRole,
      resolvedRole: resolvedRole,
      availableRoles: Set.unmodifiable(availableRoles),
      trainer: trainer,
      gym: gym,
      trainerApplication: trainerApplication,
      gymApplication: gymApplication,
      applicationStatus: currentApplication?.status,
      rejectReason: currentApplication?.rejectReason,
    );
  }

  @override
  Future<BusinessWorkspaceData> loadWorkspace(UserRole role) async {
    final access = await loadAccess();
    if (!access.canUse(role)) {
      throw StateError(
        'The current user cannot access the ${role.name} workspace.',
      );
    }

    return switch (role) {
      UserRole.trainer => _loadTrainerWorkspace(access),
      UserRole.gym => _loadGymWorkspace(access),
      UserRole.admin => _loadAdminWorkspace(access),
      UserRole.member => _loadMemberWorkspace(access),
      UserRole.guest => BusinessWorkspaceData(
        role: role,
        access: access,
        dashboardStats: const BusinessDashboardMetrics(),
      ),
    };
  }

  Future<BusinessWorkspaceData> _loadTrainerWorkspace(
    BusinessAccess access,
  ) async {
    final trainer = access.trainer;
    if (trainer == null || trainer.status != BusinessProfileStatus.approved) {
      throw StateError('An approved trainer profile is required.');
    }

    final results = await Future.wait<Object?>([
      _loadTrainerDashboardRow(trainer.id),
      _client
          .from('member_assignments')
          .select('''
            id,
            gym_id,
            member_id,
            trainer_id,
            assigned_at,
            active,
            trainer:trainers!member_assignments_trainer_id_fkey(
              id,
              display_name
            ),
            member:members!member_assignments_member_id_fkey(
              id,
              gym_id,
              user_id,
              name,
              phone,
              goal,
              remaining_pt_sessions,
               completion_rate,
               status,
               ended_at,
               last_activity_at,
              created_at,
              user:users!members_user_id_fkey(
                id,
                nickname,
                avatar_url
              )
            )
          ''')
          .eq('trainer_id', trainer.id)
          .eq('active', true)
          .order('assigned_at', ascending: false),
      _client
          .from('consultations')
          .select(_consultationSelect)
          .or(
            'trainer_id.eq.${trainer.id},assigned_trainer_id.eq.${trainer.id}',
          )
          .order('created_at', ascending: false),
      _client
          .from('coaching_routines')
          .select(_routineSelect)
          .eq('trainer_id', trainer.id)
          .order('updated_at', ascending: false),
    ]);

    final assignmentRows = _mapListValue(results[1]);
    final assignmentMemberRows = assignmentRows
        .map((row) => _mapValue(row['member']))
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final memberGoalProjection = await _loadMemberGoalProjection(
      assignmentMemberRows,
    );
    final members = <BusinessMember>[];
    final memberIds = <String>{};
    for (final row in assignmentRows) {
      final memberRow = _mapValue(row['member']);
      if (memberRow == null) continue;
      final member = _memberFromRow(
        memberRow,
        goalProjection: memberGoalProjection,
      );
      if (memberIds.add(member.id)) members.add(member);
    }

    return BusinessWorkspaceData(
      role: UserRole.trainer,
      access: access,
      profile: trainer,
      dashboardStats: _trainerDashboardFromRow(_mapValue(results[0])),
      members: List.unmodifiable(members),
      assignments: List.unmodifiable(assignmentRows.map(_assignmentFromRow)),
      consultations: _consultationList(results[2]),
      ownedRoutines: _routineList(results[3]),
    );
  }

  Future<Map<String, dynamic>?> _loadTrainerDashboardRow(
    String trainerId,
  ) async {
    try {
      return await _client
          .from('v_trainer_dashboard')
          .select(
            'unread_consults,active_members,pending_settlement,'
            'month_settled,overdue_feedbacks',
          )
          .eq('trainer_id', trainerId)
          .maybeSingle();
    } on Exception {
      // Dashboard aggregates are supplementary. A view permission or rollout
      // issue must not hide consultations, assignments, or owned routines that
      // the trainer is still authorized to read.
      return null;
    }
  }

  Future<BusinessWorkspaceData> _loadGymWorkspace(BusinessAccess access) async {
    final gym = access.gym;
    if (gym == null || gym.status != BusinessProfileStatus.verified) {
      throw StateError('A verified gym profile is required.');
    }

    final results = await Future.wait<Object?>([
      _client
          .from('v_gym_settlement_summary')
          .select()
          .eq('gym_id', gym.id)
          .maybeSingle(),
      _client
          .from('members')
          .select('''
            id,
            gym_id,
            user_id,
            name,
            phone,
            goal,
            remaining_pt_sessions,
             completion_rate,
             status,
             ended_at,
             last_activity_at,
            created_at,
            user:users!members_user_id_fkey(
              id,
              nickname,
              avatar_url
            )
           ''')
          .eq('gym_id', gym.id)
          .eq('status', 'active')
          .order('created_at', ascending: false),
      _client
          .from('member_assignments')
          .select('''
            id,
            gym_id,
            member_id,
            trainer_id,
            assigned_at,
            active,
            trainer:trainers!member_assignments_trainer_id_fkey(
              id,
              display_name
            )
          ''')
          .eq('gym_id', gym.id)
          .eq('active', true)
          .order('assigned_at', ascending: false),
      _client
          .from('gym_trainers')
          .select('''
            id,
            gym_id,
            trainer_user_id,
            trainer_id,
            role_title,
            member_count,
            avg_rating,
            monthly_sales,
            feedback_fulfillment_rate,
            status,
            created_at,
            trainer:trainers!gym_trainers_trainer_id_fkey(
              id,
              display_name,
              profile_image_url
            )
          ''')
          .eq('gym_id', gym.id)
          .eq('status', 'active')
          .order('created_at'),
      _client
          .from('consultations')
          .select(_consultationSelect)
          .eq('gym_id', gym.id)
          .order('created_at', ascending: false),
      _client
          .from('coaching_routines')
          .select(_routineSelect)
          .eq('gym_id', gym.id)
          .order('updated_at', ascending: false),
    ]);

    final consultations = _consultationList(results[4]);
    final baseDashboard = _gymDashboardFromRow(_mapValue(results[0]));
    final gymMemberRows = _mapListValue(results[1]);
    final memberGoalProjection = await _loadMemberGoalProjection(gymMemberRows);
    return BusinessWorkspaceData(
      role: UserRole.gym,
      access: access,
      profile: gym,
      dashboardStats: BusinessDashboardMetrics(
        unreadConsultations: consultations
            .where(
              (item) =>
                  !item.isRead ||
                  item.status == BusinessConsultationStatus.pending,
            )
            .length,
        activeMembers: baseDashboard.activeMembers,
        totalRevenue: baseDashboard.totalRevenue,
        trainerCount: baseDashboard.trainerCount,
      ),
      members: List.unmodifiable(
        gymMemberRows.map(
          (row) => _memberFromRow(row, goalProjection: memberGoalProjection),
        ),
      ),
      assignments: List.unmodifiable(
        _mapListValue(results[2]).map(_assignmentFromRow),
      ),
      trainers: List.unmodifiable(
        _mapListValue(results[3]).map(_gymTrainerFromRow),
      ),
      consultations: consultations,
      ownedRoutines: _routineList(results[5]),
    );
  }

  /// Reads only the goal projection authorized by the server's active
  /// member-business relationship policy. Body profile columns are never
  /// selected. A present row with a null goal is preserved so clearing a goal
  /// does not resurrect the stale value stored on an old membership row.
  Future<Map<String, String?>> _loadMemberGoalProjection(
    Iterable<Map<String, dynamic>> memberRows,
  ) async {
    final userIds = memberRows
        .map((row) => _nullableUuid(row['user_id']))
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    if (userIds.isEmpty) return const {};
    final projection = <String, String?>{};
    for (var offset = 0; offset < userIds.length; offset += 100) {
      final end = offset + 100 < userIds.length ? offset + 100 : userIds.length;
      final rows = await _client
          .from('user_profiles')
          .select('user_id,goal')
          .inFilter('user_id', userIds.sublist(offset, end));
      for (final row in _mapListValue(rows)) {
        final userId = _nullableUuid(row['user_id']);
        if (userId != null) projection[userId] = _nullableString(row['goal']);
      }
    }
    return projection;
  }

  Future<BusinessWorkspaceData> _loadAdminWorkspace(
    BusinessAccess access,
  ) async {
    final results = await Future.wait<Object?>([
      _listApplicationsUnchecked(),
      _listRoutineReviewsUnchecked(),
    ]);
    return BusinessWorkspaceData(
      role: UserRole.admin,
      access: access,
      dashboardStats: const BusinessDashboardMetrics(),
      applications: results[0] as List<BusinessApplication>,
      ownedRoutines: results[1] as List<OwnedCoachingRoutine>,
    );
  }

  Future<BusinessWorkspaceData> _loadMemberWorkspace(
    BusinessAccess access,
  ) async {
    final results = await Future.wait<Object?>([
      listMyConsultations(),
      loadMySharingPreferences(),
    ]);
    return BusinessWorkspaceData(
      role: UserRole.member,
      access: access,
      dashboardStats: const BusinessDashboardMetrics(),
      consultations: results[0] as List<BusinessConsultation>,
      memberSharingPreferences: results[1] as MemberSharingPreferences,
    );
  }

  @override
  Future<MemberSharingPreferences> loadMySharingPreferences() async {
    final user = _requireUser();
    final row = await _client
        .from('user_consents')
        .select('share_body_data,share_workout_records,marketing')
        .eq('user_id', user.id)
        .maybeSingle();
    if (row == null) {
      return const MemberSharingPreferences(
        shareBodyData: false,
        shareWorkoutRecords: false,
        marketing: false,
      );
    }
    return _sharingPreferencesFromRow(row);
  }

  @override
  Future<MemberSharingPreferences> updateMySharingPreferences(
    MemberSharingPreferences preferences,
  ) async {
    final user = _requireUser();
    final row = await _client
        .from('user_consents')
        .update({
          'share_body_data': preferences.shareBodyData,
          'share_workout_records': preferences.shareWorkoutRecords,
          'marketing': preferences.marketing,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('user_id', user.id)
        .select('share_body_data,share_workout_records,marketing')
        .maybeSingle();
    if (row == null) {
      throw StateError('Sharing preferences were not updated.');
    }
    return _sharingPreferencesFromRow(row);
  }

  @override
  Future<List<PublicTrainer>> listPublicTrainers() async {
    return (await searchPublicTrainers(pageSize: 30)).items;
  }

  @override
  Future<PublicTrainerSearchPage> searchPublicTrainers({
    String query = '',
    String? cursor,
    int pageSize = 20,
  }) async {
    _requireUser();
    final normalizedQuery = normalizePublicTrainerSearchQuery(query);
    final normalizedPageSize = validatePublicTrainerSearchPageSize(pageSize);
    final decodedCursor = cursor == null
        ? null
        : _decodePublicTrainerSearchCursor(cursor);
    final result = await _client.rpc(
      'search_public_trainers',
      params: {
        'search_query': normalizedQuery.isEmpty ? null : normalizedQuery,
        'cursor_rank': decodedCursor?.rank,
        'cursor_rating': decodedCursor?.rating,
        'cursor_id': decodedCursor?.id,
        'page_size': normalizedPageSize,
      },
    );
    final rows = _mapListValue(result);
    if (rows.length > normalizedPageSize + 1) {
      throw const FormatException(
        'Trainer search returned more rows than requested.',
      );
    }
    final hasMore = rows.length > normalizedPageSize;
    final visibleRows = rows.take(normalizedPageSize).toList(growable: false);
    final items = visibleRows
        .map(_publicTrainerFromSearchRow)
        .toList(growable: false);
    final lastRow = visibleRows.isEmpty ? null : visibleRows.last;
    return PublicTrainerSearchPage(
      items: List.unmodifiable(items),
      nextCursor: hasMore && lastRow != null
          ? _encodePublicTrainerSearchCursor(lastRow)
          : null,
    );
  }

  @override
  Future<List<TopCoachingTrainer>> listTopCoachingTrainers({
    int limit = 3,
  }) async {
    _requireUser();
    final normalizedLimit = validateTopCoachingTrainerLimit(limit);
    final result = await _client.rpc(
      'list_top_current_coaching_trainers',
      params: {'result_limit': normalizedLimit},
    );
    final rows = _mapListValue(result);
    if (rows.length > normalizedLimit) {
      throw const FormatException(
        'Top coaching trainer query returned more rows than requested.',
      );
    }
    return List.unmodifiable(rows.map(_topCoachingTrainerFromRow));
  }

  @override
  Future<List<BusinessConsultation>> listMyConsultations() async {
    final user = _requireUser();
    final consultations = <BusinessConsultation>[];
    DateTime? cursorCreatedAt;
    String? cursorId;
    while (true) {
      var query = _client
          .from('consultations')
          .select(_consultationSelect)
          .eq('user_id', user.id);
      if (cursorCreatedAt != null && cursorId != null) {
        final cursorTimestamp = cursorCreatedAt.toUtc().toIso8601String();
        query = query.or(
          'created_at.lt.$cursorTimestamp,'
          'and(created_at.eq.$cursorTimestamp,id.lt.$cursorId)',
        );
      }
      final value = await query
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .limit(_memberConsultationPageSize);
      final rows = _mapListValue(value);
      consultations.addAll(rows.map(_consultationFromRow));
      if (rows.length < _memberConsultationPageSize) break;
      final lastRow = rows.last;
      cursorCreatedAt = _nullableDateTime(lastRow['created_at']);
      cursorId = _nullableUuid(lastRow['id']);
      if (cursorCreatedAt == null || cursorId == null) {
        throw const FormatException(
          'Consultation history cursor fields are missing.',
        );
      }
    }
    return List.unmodifiable(consultations);
  }

  @override
  Future<List<BusinessCoachingSchedule>> listCoachingSchedules({
    DateTime? from,
    DateTime? to,
  }) async {
    _requireUser();
    var query = _client
        .from('coaching_schedules')
        .select(_coachingScheduleSelect);
    if (from != null) query = query.gte('date', _dateOnly(from));
    if (to != null) query = query.lte('date', _dateOnly(to));
    final rows = await query.order('date').order('start_time').order('id');
    return List.unmodifiable(rows.map(_coachingScheduleFromRow));
  }

  @override
  Future<BusinessCoachingSchedule> createCoachingSchedule(
    CreateCoachingScheduleInput input,
  ) async {
    _requireUser();
    final requestId = _validatedUuid(input.requestId, 'requestId');
    final trainerId = _validatedUuid(input.trainerId, 'trainerId');
    final memberUserId = _validatedOptionalUuid(
      input.memberUserId,
      'memberUserId',
    );
    final gymId = _validatedOptionalUuid(input.gymId, 'gymId');
    final title = _requiredTrimmed(input.title, 'title');
    if (title.length > 120) {
      throw ArgumentError.value(
        input.title,
        'title',
        'Must be at most 120 characters.',
      );
    }
    _validateScheduleMinutes(input.startMinutes, input.endMinutes);

    late final Object? result;
    try {
      result = await _client.rpc(
        'create_coaching_schedule',
        params: {
          'request_id': requestId,
          'trainer_id': trainerId,
          'member_user_id': memberUserId,
          'gym_id': gymId,
          'title': title,
          'schedule_date': _dateOnly(input.date),
          'start_at': _timeOnly(input.startMinutes),
          'end_at': _timeOnly(input.endMinutes),
        },
      );
    } on PostgrestException catch (error) {
      if (error.message.contains('COACHING_SCHEDULE_TRAINER_OVERLAP')) {
        throw const CoachingScheduleConflictException(
          CoachingScheduleConflictTarget.trainer,
        );
      }
      if (error.message.contains('COACHING_SCHEDULE_MEMBER_OVERLAP')) {
        throw const CoachingScheduleConflictException(
          CoachingScheduleConflictTarget.member,
        );
      }
      rethrow;
    }
    final row = _mapValue(result);
    if (row == null) {
      throw const FormatException('Coaching schedule RPC returned no row.');
    }
    return _coachingScheduleFromRow(row);
  }

  @override
  Future<BusinessCoachingSchedule> setCoachingScheduleCompleted(
    String scheduleId, {
    required String trainerId,
    required bool completed,
  }) async {
    _requireUser();
    final normalizedScheduleId = _validatedUuid(scheduleId, 'scheduleId');
    final normalizedTrainerId = _validatedUuid(trainerId, 'trainerId');
    final row = await _client
        .from('coaching_schedules')
        .update({
          'completed_at': completed
              ? DateTime.now().toUtc().toIso8601String()
              : null,
        })
        .eq('id', normalizedScheduleId)
        .eq('trainer_id', normalizedTrainerId)
        .select(_coachingScheduleSelect)
        .maybeSingle();
    if (row == null) {
      throw StateError('Coaching schedule was not updated.');
    }
    return _coachingScheduleFromRow(row);
  }

  @override
  Future<void> deleteCoachingSchedule(
    String scheduleId, {
    required String trainerId,
  }) async {
    _requireUser();
    final normalizedScheduleId = _validatedUuid(scheduleId, 'scheduleId');
    final normalizedTrainerId = _validatedUuid(trainerId, 'trainerId');
    final rows = await _client
        .from('coaching_schedules')
        .delete()
        .eq('id', normalizedScheduleId)
        .eq('trainer_id', normalizedTrainerId)
        .select('id');
    if (rows.isEmpty) throw StateError('Coaching schedule was not deleted.');
  }

  @override
  Future<BusinessConsultation> createConsultation(
    CreateConsultationInput input,
  ) async {
    final user = _requireUser();
    final requestId = _validatedUuid(input.requestId, 'requestId');
    final question = input.question.trim();
    if (question.isEmpty) {
      throw ArgumentError.value(input.question, 'question', 'Cannot be empty.');
    }
    final trainerId = _validatedOptionalUuid(input.trainerId, 'trainerId');
    final gymId = _validatedOptionalUuid(input.gymId, 'gymId');
    final routineId = _validatedOptionalUuid(input.routineId, 'routineId');
    final regionCode = _nullableString(input.regionCode);
    switch (input.mode) {
      case ConsultationMode.online:
        if ((trainerId == null) == (gymId == null) || regionCode != null) {
          throw ArgumentError(
            'Online consultation requires one trainerId or gymId.',
          );
        }
      case ConsultationMode.offline:
        if (gymId != null) {
          if (trainerId != null || regionCode != null) {
            throw ArgumentError('Gym matching accepts only one gymId.');
          }
        } else if (regionCode == null) {
          throw ArgumentError(
            'Offline consultation requires a gymId or regionCode.',
          );
        }
    }

    final result = await _client.rpc(
      'create_location_aware_consultation',
      params: {
        'request_id': requestId,
        'consultation_mode': input.mode.databaseValue,
        'trainer_id': trainerId,
        'gym_id': gymId,
        'region_code': regionCode,
        'routine_id': routineId,
        'specialty': _nullableString(input.specialty),
        'goal': _nullableString(input.goal),
        'level': _nullableString(input.level),
        'question': question,
        'recommendation_profile': input.recommendationProfile?.toJson(),
      },
    );
    final consultation = await _loadConsultation(
      _uuidFromRpc(result) ??
          (throw const FormatException(
            'Consultation create RPC returned no UUID.',
          )),
    );
    if (consultation.userId != user.id ||
        consultation.mode != input.mode ||
        consultation.gymId != gymId ||
        consultation.requestedRegionCode != regionCode ||
        consultation.routineId != routineId ||
        (trainerId != null && consultation.trainerId != trainerId)) {
      throw StateError('Server returned a different consultation create.');
    }
    return consultation;
  }

  @override
  Future<List<ServiceRegion>> listServiceRegions() async {
    final rows = await _client
        .from('service_regions')
        .select('code,name,sort_order')
        .eq('active', true)
        .order('sort_order');
    return List.unmodifiable(_mapListValue(rows).map(_serviceRegionFromRow));
  }

  @override
  Future<List<GymDirectoryEntry>> listVerifiedGyms() async {
    final rows = await _client
        .from('gyms')
        .select('id,name,address')
        .eq('status', 'verified')
        .order('name')
        .limit(200);
    return List.unmodifiable(_mapListValue(rows).map(_gymDirectoryFromRow));
  }

  @override
  Future<List<MemberWorkoutLocation>> listMyWorkoutLocations() async {
    final user = _requireUser();
    final rows = await _client
        .from('member_workout_locations')
        .select('''
          id,
          user_id,
          gym_id,
          is_active,
          last_selected_at,
          created_at,
          gym:gyms!member_workout_locations_gym_id_fkey(
            id,
            name,
            address
          )
        ''')
        .eq('user_id', user.id)
        .order('is_active', ascending: false)
        .order('last_selected_at', ascending: false, nullsFirst: false)
        .order('created_at', ascending: false);
    return List.unmodifiable(
      _mapListValue(rows).map(_memberWorkoutLocationFromRow),
    );
  }

  @override
  Future<void> saveWorkoutLocation(String gymId) async {
    await _client.rpc(
      'set_my_workout_location',
      params: {'gym_id': _validatedUuid(gymId, 'gymId')},
    );
  }

  @override
  Future<void> selectWorkoutLocation(String locationId) async {
    await _client.rpc(
      'select_my_workout_location',
      params: {'location_id': _validatedUuid(locationId, 'locationId')},
    );
  }

  @override
  Future<void> removeWorkoutLocation(String locationId) async {
    await _client.rpc(
      'remove_my_workout_location',
      params: {'location_id': _validatedUuid(locationId, 'locationId')},
    );
  }

  @override
  Future<void> updateTrainerConsultationSettings(
    TrainerConsultationSettingsInput input,
  ) async {
    if (!input.acceptsOnline && !input.acceptsOffline) {
      throw ArgumentError('At least one consultation mode is required.');
    }
    final regionCodes = input.regionCodes
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (input.acceptsOffline && regionCodes.isEmpty) {
      throw ArgumentError('Offline consultation requires a service region.');
    }
    await _client.rpc(
      'update_my_trainer_consultation_settings',
      params: {
        'accepts_online': input.acceptsOnline,
        'accepts_offline': input.acceptsOffline,
        'region_codes': regionCodes,
      },
    );
  }

  @override
  Future<void> revokeRecommendationProfileShare(String consultationId) async {
    await _client.rpc(
      'revoke_consultation_recommendation_profile_share',
      params: {
        'consultation_id': _validatedUuid(consultationId, 'consultationId'),
      },
    );
  }

  @override
  Future<BusinessApplication> submitTrainerApplication(
    TrainerApplicationInput input,
  ) async {
    final user = _requireUser();
    final displayName = input.displayName.trim();
    if (displayName.isEmpty) {
      throw ArgumentError.value(
        input.displayName,
        'displayName',
        'Cannot be empty.',
      );
    }
    final documents = _validatedTrainerApplicationDocuments(input.documents);
    final requestId = _newRepositoryUuidV4();
    final uploadedPaths = <String>[];
    final payload = <Map<String, String>>[];
    var rpcStarted = false;
    try {
      for (final document in documents) {
        final optimized = await const UserImageOptimizer().optimize(
          bytes: document.bytes,
          fileName: document.fileName,
          reportedContentType: document.contentType,
          purpose: UserImagePurpose.trainerDocument,
        );
        final extension = _trainerDocumentExtension(optimized.contentType);
        final path =
            '${user.id}/pending/$requestId/'
            '${document.type.databaseValue}.$extension';
        await _client.storage
            .from('trainer-documents')
            .uploadBinary(
              path,
              optimized.bytes,
              fileOptions: FileOptions(
                cacheControl: '3600',
                contentType: optimized.contentType,
                upsert: false,
              ),
            );
        uploadedPaths.add(path);
        payload.add({
          'doc_type': document.type.databaseValue,
          'file_path': path,
        });
      }
      rpcStarted = true;
      final result = await _client.rpc(
        'submit_trainer_application',
        params: {
          'name': displayName,
          'certification_number': _requiredTrimmed(
            input.credentialNumber,
            'credentialNumber',
          ),
          'documents': payload,
        },
      );
      return _applicationFromRpc(result, BusinessApplicationKind.trainer);
    } catch (error) {
      // A transport error after the RPC started has an unknown commit state;
      // never delete possibly-referenced evidence in that case. A PostgREST
      // response error is transactional and known to have rolled back.
      final canSafelyCleanUp = !rpcStarted || error is PostgrestException;
      if (canSafelyCleanUp && uploadedPaths.isNotEmpty) {
        try {
          await _client.storage.from('trainer-documents').remove(uploadedPaths);
        } catch (_) {
          // Preserve the original upload/RPC error. The private bucket owner
          // cannot mutate submitted evidence; an admin/service cleanup job
          // removes any unlinked request folder left by a failed submission.
        }
      }
      rethrow;
    }
  }

  @override
  Future<BusinessApplication> submitGymApplication(
    GymApplicationInput input,
  ) async {
    final gymName = input.gymName.trim();
    final businessNumber = input.businessNumber.trim();
    if (gymName.isEmpty || businessNumber.isEmpty) {
      throw ArgumentError('Gym name and business number are required.');
    }
    final result = await _client.rpc(
      'submit_gym_application',
      params: {'name': gymName, 'business_number': businessNumber},
    );
    return _applicationFromRpc(result, BusinessApplicationKind.gym);
  }

  @override
  Future<List<BusinessApplication>> listApplications({
    BusinessApplicationStatus? status,
  }) async {
    final access = await loadAccess();
    if (!access.canUse(UserRole.admin)) {
      throw StateError('Administrator access is required.');
    }
    return _listApplicationsUnchecked(status: status);
  }

  Future<List<BusinessApplication>> _listApplicationsUnchecked({
    BusinessApplicationStatus? status,
  }) async {
    var trainerQuery = _client
        .from('trainer_applications')
        .select(
          'id,trainer_id,user_id,name,submitted_at,sla_due_at,status,'
          'reject_reason,reviewer_id',
        );
    var gymQuery = _client
        .from('gym_applications')
        .select(
          'id,gym_id,owner_user_id,gym_name,owner_name,biz_reg_no,'
          'submitted_at,sla_due_at,status,reject_reason,reviewer_id',
        );
    if (status != null && status != BusinessApplicationStatus.unknown) {
      trainerQuery = trainerQuery.eq('status', status.databaseValue);
      gymQuery = gymQuery.eq('status', status.databaseValue);
    }
    final results = await Future.wait<Object?>([
      trainerQuery.order('submitted_at', ascending: false),
      gymQuery.order('submitted_at', ascending: false),
    ]);
    final applications =
        <BusinessApplication>[
          ..._mapListValue(results[0]).map(
            (row) => _applicationFromRow(row, BusinessApplicationKind.trainer),
          ),
          ..._mapListValue(
            results[1],
          ).map((row) => _applicationFromRow(row, BusinessApplicationKind.gym)),
        ]..sort((left, right) {
          final leftAt =
              left.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final rightAt =
              right.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return rightAt.compareTo(leftAt);
        });
    return List.unmodifiable(applications);
  }

  @override
  Future<BusinessApplication> reviewApplication(
    ReviewBusinessApplicationInput input,
  ) async {
    final applicationId = _validatedUuid(input.applicationId, 'applicationId');
    final rejectReason = _nullableString(input.rejectReason);
    if (!input.approve && rejectReason == null) {
      throw ArgumentError('A rejectReason is required when rejecting.');
    }
    final result = await _client.rpc(
      'review_business_application',
      params: {
        'kind': input.kind.databaseValue,
        'application_id': applicationId,
        'decision': input.approve ? 'approved' : 'rejected',
        'reason': input.approve ? null : rejectReason,
      },
    );
    return _applicationFromRpc(result, input.kind);
  }

  @override
  Future<void> updateProfile(UpdateBusinessProfileInput input) async {
    final access = await loadAccess();
    final profileId = _validatedUuid(input.profileId, 'profileId');
    final isAdmin = access.canUse(UserRole.admin);

    switch (input.role) {
      case UserRole.trainer:
        if (!isAdmin && access.trainer?.id != profileId) {
          throw StateError('The trainer profile is not owned by this user.');
        }
        final values = <String, Object?>{
          if (input.displayName != null)
            'display_name': _requiredTrimmed(input.displayName!, 'displayName'),
          if (input.keyword != null) 'keyword': _nullableString(input.keyword),
          if (input.intro != null) 'intro': _nullableString(input.intro),
          if (input.imageUrl != null)
            'profile_image_url': _nullableString(input.imageUrl),
          if (input.careerYears != null) 'career_years': input.careerYears,
          if (input.centerName != null)
            'center_name': _nullableString(input.centerName),
          if (input.isPublic != null) 'is_public': input.isPublic,
        };
        if (values.isEmpty) throw ArgumentError('No profile fields to update.');
        await _requireUpdatedRow('trainers', profileId, values);
      case UserRole.gym:
        if (!isAdmin && access.gym?.id != profileId) {
          throw StateError('The gym profile is not owned by this user.');
        }
        final values = <String, Object?>{
          if (input.name != null) 'name': _requiredTrimmed(input.name!, 'name'),
          if (input.representativeName != null)
            'rep_name': _nullableString(input.representativeName),
          if (input.gymType != null) 'gym_type': _nullableString(input.gymType),
          if (input.address != null) 'address': _nullableString(input.address),
          if (input.description != null)
            'description': _nullableString(input.description),
          if (input.imageUrl != null)
            'cover_image_url': _nullableString(input.imageUrl),
        };
        if (values.isEmpty) throw ArgumentError('No profile fields to update.');
        await _requireUpdatedRow('gyms', profileId, values);
      case UserRole.guest || UserRole.member || UserRole.admin:
        throw ArgumentError.value(
          input.role,
          'role',
          'Only trainer and gym profiles can be updated.',
        );
    }
  }

  Future<void> _requireUpdatedRow(
    String table,
    String id,
    Map<String, Object?> values,
  ) async {
    final row = await _client
        .from(table)
        .update(values)
        .eq('id', id)
        .select('id')
        .maybeSingle();
    if (row == null) throw StateError('Profile was not updated.');
    _requiredUuid(row, 'id');
  }

  @override
  Future<BusinessMemberAssignment?> assignMember(
    AssignMemberInput input,
  ) async {
    final gymId = _validatedUuid(input.gymId, 'gymId');
    final memberId = _validatedUuid(input.memberId, 'memberId');
    final trainerId = _validatedOptionalUuid(input.trainerId, 'trainerId');
    final result = await _client.rpc(
      'assign_gym_member',
      params: {'member_id': memberId, 'trainer_id': trainerId},
    );
    final row = _mapValue(result);
    final returnedGymId = _nullableUuid(row?['gym_id']);
    if (returnedGymId != null && returnedGymId != gymId) {
      throw StateError('Assignment belongs to a different gym.');
    }
    if (row != null && row.containsKey('id')) {
      return _assignmentFromRow(row);
    }
    if (trainerId == null) return null;

    final assignmentId = _uuidFromRpc(result);
    final query = _client.from('member_assignments').select('''
          id,
          gym_id,
          member_id,
          trainer_id,
          assigned_at,
          active,
          trainer:trainers!member_assignments_trainer_id_fkey(
            id,
            display_name
          )
        ''');
    final assignment = assignmentId == null
        ? await query
              .eq('gym_id', gymId)
              .eq('member_id', memberId)
              .eq('active', true)
              .maybeSingle()
        : await query.eq('id', assignmentId).maybeSingle();
    if (assignment == null) {
      throw StateError('Member assignment was not returned by the server.');
    }
    return _assignmentFromRow(assignment);
  }

  @override
  Future<BusinessInviteCreation> createBusinessInvite(
    CreateBusinessInviteInput input,
  ) async {
    _requireUser();
    final gymId = _validatedUuid(input.gymId, 'gymId');
    final requestId = _validatedUuid(input.requestId, 'requestId');
    final memberId = _validatedOptionalUuid(input.memberId, 'memberId');
    if (input.kind == BusinessInviteKind.unknown) {
      throw ArgumentError.value(input.kind, 'kind', 'Unknown invite kind.');
    }
    final recipientName = _boundedOptionalText(
      input.recipientName,
      'recipientName',
      120,
    );
    final recipientPhone = _boundedOptionalText(
      input.recipientPhone,
      'recipientPhone',
      40,
    );
    final roleTitle = _boundedOptionalText(input.roleTitle, 'roleTitle', 80);
    if (input.kind == BusinessInviteKind.member &&
        memberId == null &&
        recipientName == null) {
      throw ArgumentError.value(
        input.recipientName,
        'recipientName',
        'A new member invite requires a recipient name.',
      );
    }
    if (input.kind == BusinessInviteKind.trainer &&
        (memberId != null || recipientPhone != null)) {
      throw ArgumentError(
        'Trainer invites cannot include memberId or recipientPhone.',
      );
    }
    final expiresAt = input.expiresAt.toUtc();
    final now = DateTime.now().toUtc();
    if (!expiresAt.isAfter(now.add(const Duration(minutes: 4))) ||
        expiresAt.isAfter(now.add(const Duration(days: 31)))) {
      throw ArgumentError.value(
        input.expiresAt,
        'expiresAt',
        'Must be between 5 minutes and 30 days from now.',
      );
    }

    final result = await _client.rpc(
      'create_business_invite',
      params: {
        'gym_id': gymId,
        'invite_kind': input.kind.databaseValue,
        'request_id': requestId,
        'expires_at': expiresAt.toIso8601String(),
        'member_id': memberId,
        'recipient_name': recipientName,
        'recipient_phone': recipientPhone,
        'role_title': roleTitle,
      },
    );
    final row = _mapValue(result);
    final inviteRow = _mapValue(row?['invite']);
    if (row == null || inviteRow == null) {
      throw StateError('Business invite was not returned by the server.');
    }
    final tokenIssued = _boolValue(row['token_issued']);
    final token = _nullableString(row['token']);
    if (tokenIssued &&
        (token == null || !_inviteTokenPattern.hasMatch(token))) {
      throw const FormatException('Server returned an invalid invite token.');
    }
    return BusinessInviteCreation(
      invite: _businessInviteFromRow(inviteRow),
      tokenIssued: tokenIssued,
      token: token,
      uri: token == null
          ? null
          : Uri(
              scheme: 'com.teampara.setflow',
              host: 'business-invite',
              path: '/$token',
            ),
    );
  }

  @override
  Future<List<BusinessInviteRecord>> listBusinessInvites(
    String gymId, {
    BusinessInviteStatus? status,
  }) async {
    _requireUser();
    final normalizedGymId = _validatedUuid(gymId, 'gymId');
    final rows = await _client
        .from('business_invites')
        .select(_businessInviteSelect)
        .eq('gym_id', normalizedGymId)
        .order('created_at', ascending: false)
        .limit(200);
    final invites = _mapListValue(rows)
        .map(_businessInviteFromRow)
        .where((invite) => status == null || invite.status == status)
        .toList(growable: false);
    return List.unmodifiable(invites);
  }

  @override
  Future<BusinessInviteAcceptance> acceptBusinessInvite(
    String token, {
    required String requestId,
  }) async {
    _requireUser();
    final normalizedToken = token.trim().toLowerCase();
    if (!_inviteTokenPattern.hasMatch(normalizedToken)) {
      throw ArgumentError.value(token, 'token', 'Invalid invite token.');
    }
    final result = await _client.rpc(
      'accept_business_invite',
      params: {
        'token': normalizedToken,
        'request_id': _validatedUuid(requestId, 'requestId'),
      },
    );
    final row = _mapValue(result);
    final inviteRow = _mapValue(row?['invite']);
    if (row == null || inviteRow == null) {
      throw StateError('Invite acceptance was not returned by the server.');
    }
    return BusinessInviteAcceptance(
      accepted: _boolValue(row['accepted']),
      invite: _businessInviteFromRow(inviteRow),
      memberId: _nullableUuid(row['member_id']),
      trainerId: _nullableUuid(row['trainer_id']),
      gymTrainerId: _nullableUuid(row['gym_trainer_id']),
    );
  }

  @override
  Future<BusinessInviteRecord> revokeBusinessInvite(
    String inviteId, {
    required String requestId,
  }) async {
    _requireUser();
    final result = await _client.rpc(
      'revoke_business_invite',
      params: {
        'invite_id': _validatedUuid(inviteId, 'inviteId'),
        'request_id': _validatedUuid(requestId, 'requestId'),
      },
    );
    final row = _mapValue(result);
    if (row == null) {
      throw StateError('Revoked invite was not returned by the server.');
    }
    return _businessInviteFromRow(row);
  }

  @override
  Future<BusinessMemberDetail> loadMemberDetail(
    String memberId, {
    DateTime? from,
    DateTime? to,
  }) async {
    _requireUser();
    final normalizedMemberId = _validatedUuid(memberId, 'memberId');
    final rangeEnd = to ?? DateTime.now();
    final rangeStart = from ?? rangeEnd.subtract(const Duration(days: 90));
    final startDate = DateTime(
      rangeStart.year,
      rangeStart.month,
      rangeStart.day,
    );
    final endDate = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
    if (startDate.isAfter(endDate) ||
        endDate.difference(startDate).inDays > 366) {
      throw ArgumentError('Member workout range must be within 366 days.');
    }
    final result = await _client.rpc(
      'get_business_member_detail',
      params: {
        'member_id': normalizedMemberId,
        'from_date': _dateOnly(startDate),
        'to_date': _dateOnly(endDate),
      },
    );
    final row = _mapValue(result);
    if (row == null) {
      throw StateError('Member detail was not returned by the server.');
    }
    return _memberDetailFromRow(row);
  }

  @override
  Future<BusinessSessionFeedback> sendSessionFeedback(
    SendSessionFeedbackInput input,
  ) async {
    _requireUser();
    final message = input.text.trim();
    if (message.isEmpty || message.length > 2000) {
      throw ArgumentError.value(
        input.text,
        'text',
        'Feedback must be between 1 and 2000 characters.',
      );
    }
    final result = await _client.rpc(
      'send_business_session_feedback',
      params: {
        'session_id': _validatedUuid(input.sessionId, 'sessionId'),
        'text': message,
        'request_id': _validatedOptionalUuid(input.requestId, 'requestId'),
      },
    );
    final row = _mapValue(result);
    if (row == null) {
      throw StateError('Session feedback was not returned by the server.');
    }
    return _sessionFeedbackFromRow(row);
  }

  @override
  Future<List<MemberSessionFeedback>> listMySessionFeedback({
    DateTime? from,
    DateTime? to,
  }) async {
    _requireUser();
    final now = DateTime.now();
    final rangeStart = from ?? DateTime(now.year, now.month, now.day - 90);
    final rangeEnd = to ?? DateTime(now.year, now.month, now.day);
    final startDate = DateTime(
      rangeStart.year,
      rangeStart.month,
      rangeStart.day,
    );
    final endDate = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
    if (startDate.isAfter(endDate) ||
        endDate.difference(startDate).inDays > 366) {
      throw ArgumentError('Member feedback range must be within 366 days.');
    }
    final result = await _client.rpc(
      'list_my_session_feedback',
      params: {
        'from_date': _dateOnly(startDate),
        'to_date': _dateOnly(endDate),
      },
    );
    return List.unmodifiable(
      _mapListValue(result).map(_memberSessionFeedbackFromRow),
    );
  }

  @override
  Future<List<BusinessMember>> listMyBusinessMemberships() async {
    _requireUser();
    final result = await _client.rpc('list_my_business_memberships');
    return List.unmodifiable(_mapListValue(result).map(_memberFromRow));
  }

  @override
  Future<BusinessMember> endBusinessMembership(
    EndBusinessMembershipInput input,
  ) async {
    _requireUser();
    final memberId = _validatedUuid(input.memberId, 'memberId');
    final requestId = _validatedUuid(input.requestId, 'requestId');
    final result = await _client.rpc(
      'end_business_membership',
      params: {'member_id': memberId, 'request_id': requestId},
    );
    final row = _mapValue(result);
    if (row == null) {
      throw StateError('Ended membership was not returned by the server.');
    }
    final membership = _memberFromRow(row);
    if (membership.id != memberId || membership.status != 'ended') {
      throw StateError('Server returned a different membership lifecycle.');
    }
    return membership;
  }

  @override
  Future<BusinessConsultation> assignConsultation(
    AssignConsultationInput input,
  ) async {
    _requireUser();
    final requestId = _validatedUuid(input.requestId, 'requestId');
    final consultationId = _validatedUuid(
      input.consultationId,
      'consultationId',
    );
    final gymId = _validatedUuid(input.gymId, 'gymId');
    final trainerId = _validatedUuid(input.trainerId, 'trainerId');
    final result = await _client.rpc(
      'assign_business_consultation',
      params: {
        'request_id': requestId,
        'consultation_id': consultationId,
        'gym_id': gymId,
        'trainer_id': trainerId,
      },
    );
    final returnedId = _uuidFromRpc(result) ?? consultationId;
    if (returnedId != consultationId) {
      throw StateError('Server returned a different consultation.');
    }
    final consultation = await _loadConsultation(consultationId);
    final acceptedStatus = switch (consultation.status) {
      BusinessConsultationStatus.assigned ||
      BusinessConsultationStatus.replied ||
      BusinessConsultationStatus.answered => true,
      _ => false,
    };
    if (consultation.gymId != gymId ||
        consultation.assignedTrainerId != trainerId ||
        !acceptedStatus) {
      throw StateError('Server returned a different consultation handoff.');
    }
    return consultation;
  }

  @override
  Future<BusinessConsultation> replyConsultation(
    ReplyConsultationInput input,
  ) async {
    final user = _requireUser();
    final requestId = _validatedUuid(input.requestId, 'requestId');
    final consultationId = _validatedUuid(
      input.consultationId,
      'consultationId',
    );
    final message = input.message.trim();
    if (message.isEmpty) {
      throw ArgumentError.value(input.message, 'message', 'Cannot be empty.');
    }
    final result = await _client.rpc(
      'reply_business_consultation',
      params: {
        'request_id': requestId,
        'consultation_id': consultationId,
        'text': message,
      },
    );
    final returnedId = _uuidFromRpc(result) ?? consultationId;
    if (returnedId != consultationId) {
      throw StateError('Server returned a different consultation reply.');
    }
    final consultation = await _loadConsultation(consultationId);
    if (!consultation.messages.any(
      (item) => item.senderId == user.id && item.text == message,
    )) {
      throw StateError(
        'Server did not return the persisted consultation reply.',
      );
    }
    return consultation;
  }

  Future<BusinessConsultation> _loadConsultation(String id) async {
    final row = await _client
        .from('consultations')
        .select(_consultationSelect)
        .eq('id', id)
        .maybeSingle();
    if (row == null) throw StateError('Consultation was not found.');
    return _consultationFromRow(row);
  }

  @override
  Future<OwnedCoachingRoutine> createOwnedRoutine(
    CreateOwnedRoutineInput input,
  ) async {
    return _saveOwnedRoutine(
      ownerRole: input.ownerRole,
      title: input.title,
      intro: input.intro,
      price: input.price,
      difficulty: input.difficulty,
      exercises: input.exercises,
      requestId: input.requestId,
    );
  }

  @override
  Future<OwnedCoachingRoutine> updateOwnedRoutine(
    UpdateOwnedRoutineInput input,
  ) async {
    return _saveOwnedRoutine(
      routineId: input.routineId,
      ownerRole: input.ownerRole,
      title: input.title,
      intro: input.intro,
      price: input.price,
      difficulty: input.difficulty,
      exercises: input.exercises,
      requestId: input.requestId,
    );
  }

  Future<OwnedCoachingRoutine> _saveOwnedRoutine({
    String? routineId,
    required UserRole ownerRole,
    required String title,
    required BusinessRoutineDifficulty difficulty,
    required List<CreateOwnedRoutineExerciseInput> exercises,
    String? intro,
    double? price,
    String? requestId,
  }) async {
    _requireUser();
    if (ownerRole != UserRole.trainer && ownerRole != UserRole.gym) {
      throw ArgumentError.value(
        ownerRole,
        'ownerRole',
        'Only trainer or gym can own a coaching routine.',
      );
    }
    final normalizedTitle = _requiredTrimmed(title, 'title');
    if (normalizedTitle.length > 120) {
      throw ArgumentError.value(
        title,
        'title',
        'Must be at most 120 characters.',
      );
    }
    final normalizedIntro = _nullableString(intro);
    if (normalizedIntro != null && normalizedIntro.length > 2000) {
      throw ArgumentError.value(
        intro,
        'intro',
        'Must be at most 2000 characters.',
      );
    }
    if (difficulty == BusinessRoutineDifficulty.unknown) {
      throw ArgumentError.value(
        difficulty,
        'difficulty',
        'Unknown is not a writable difficulty.',
      );
    }
    if (price != null && (!price.isFinite || price < 0 || price > 100000000)) {
      throw ArgumentError.value(
        price,
        'price',
        'Must be a finite value between 0 and 100000000.',
      );
    }

    final normalizedRoutineId = routineId == null
        ? null
        : _validatedUuid(routineId, 'routineId');
    final normalizedRequestId = _validatedOptionalUuid(requestId, 'requestId');
    final result = await _client.rpc(
      'save_coaching_routine',
      params: {
        'routine_id': normalizedRoutineId,
        'owner_role': ownerRole.name,
        'title': normalizedTitle,
        'intro': normalizedIntro,
        'difficulty': difficulty.databaseValue,
        'price': price,
        'exercises': _routineExercisesPayload(exercises),
        'request_id': normalizedRequestId,
      },
    );
    return _ownedRoutineFromRpc(result, fallbackId: normalizedRoutineId);
  }

  @override
  Future<OwnedCoachingRoutine> submitOwnedRoutineForReview(
    String routineId, {
    String? requestId,
  }) async {
    final id = _validatedUuid(routineId, 'routineId');
    final result = await _client.rpc(
      'submit_coaching_routine_review',
      params: {
        'routine_id': id,
        'request_id': _validatedOptionalUuid(requestId, 'requestId'),
      },
    );
    return _ownedRoutineFromRpc(result, fallbackId: id);
  }

  @override
  Future<List<OwnedCoachingRoutine>> listRoutineReviews() async {
    final access = await loadAccess();
    if (!access.canUse(UserRole.admin)) {
      throw StateError('Administrator access is required.');
    }
    return _listRoutineReviewsUnchecked();
  }

  Future<List<OwnedCoachingRoutine>> _listRoutineReviewsUnchecked() async {
    final rows = await _client
        .from('coaching_routines')
        .select(_routineSelect)
        .eq('status', BusinessRoutineStatus.review.databaseValue)
        .order('updated_at', ascending: false);
    return _routineList(rows);
  }

  @override
  Future<OwnedCoachingRoutine> reviewOwnedRoutine(
    ReviewOwnedRoutineInput input,
  ) async {
    final id = _validatedUuid(input.routineId, 'routineId');
    final reason = _nullableString(input.rejectReason);
    if (!input.approve && reason == null) {
      throw ArgumentError('A rejectReason is required when rejecting.');
    }
    final result = await _client.rpc(
      'review_coaching_routine',
      params: {
        'routine_id': id,
        'decision': input.approve ? 'approve' : 'reject',
        'reason': input.approve ? null : reason,
        'access_tier': input.accessTier.name,
        'request_id': _validatedOptionalUuid(input.requestId, 'requestId'),
      },
    );
    return _ownedRoutineFromRpc(result, fallbackId: id);
  }

  @override
  Future<List<RoutineShareRecord>> shareOwnedRoutine(
    ShareOwnedRoutineInput input,
  ) async {
    final id = _validatedUuid(input.routineId, 'routineId');
    final memberIds = input.memberIds
        .map((memberId) => _validatedUuid(memberId, 'memberIds'))
        .toSet()
        .toList(growable: false);
    if (memberIds.isEmpty || memberIds.length > 100) {
      throw ArgumentError.value(
        input.memberIds,
        'memberIds',
        'Select between 1 and 100 members.',
      );
    }
    final message = _nullableString(input.message);
    if (message != null && message.length > 1000) {
      throw ArgumentError.value(
        input.message,
        'message',
        'Must be at most 1000 characters.',
      );
    }
    final result = await _client.rpc(
      'share_coaching_routine',
      params: {
        'routine_id': id,
        'member_ids': memberIds,
        'message': message,
        'expires_at': input.expiresAt?.toUtc().toIso8601String(),
        'request_id': _validatedOptionalUuid(input.requestId, 'requestId'),
      },
    );
    final shareIds = _mapListValue(
      result,
    ).map((row) => _requiredUuid(row, 'id')).toList(growable: false);
    if (shareIds.isEmpty) {
      throw const FormatException('Share RPC result did not contain a share.');
    }
    return _loadRoutineShares(shareIds);
  }

  @override
  Future<RoutineShareLink> createRoutineShareLink(
    String routineId, {
    DateTime? expiresAt,
    String? requestId,
  }) async {
    final id = _validatedUuid(routineId, 'routineId');
    try {
      final result = await _client.rpc(
        'create_routine_share_link',
        params: {
          'routine_id': id,
          'expires_at': expiresAt?.toUtc().toIso8601String(),
          'request_id': _validatedOptionalUuid(requestId, 'requestId'),
        },
      );
      final row = _mapValue(result);
      if (row == null) {
        throw const FormatException(
          'Share link RPC returned an invalid value.',
        );
      }
      final token = _requiredTrimmed(
        _stringValue(row['token']),
        'shareLink.token',
      );
      final resolvedExpiresAt = _nullableDateTime(row['expires_at']);
      if (resolvedExpiresAt == null) {
        throw const FormatException('Share link RPC result has no expiry.');
      }
      return RoutineShareLink(
        shareId: _requiredUuid(row, 'id'),
        token: token,
        uri: Uri(
          scheme: 'com.teampara.setflow',
          host: 'routine-share',
          pathSegments: [token],
        ),
        expiresAt: resolvedExpiresAt,
      );
    } on PostgrestException {
      // A PostgREST response means the transaction outcome is known. Server
      // validation failures can be corrected without an ambiguity warning.
      rethrow;
    } on RoutineShareLinkResultUncertainException {
      rethrow;
    } catch (error, stackTrace) {
      // Transport loss or an invalid post-commit response can hide the only
      // copy of the raw token. Never pretend that retrying can recover it.
      Error.throwWithStackTrace(
        RoutineShareLinkResultUncertainException(error),
        stackTrace,
      );
    }
  }

  @override
  Future<List<RoutineShareRecord>> listIncomingRoutineShares() async {
    final user = _requireUser();
    final rows = await _client
        .from('routine_shares')
        .select(_routineShareSelect)
        .eq('recipient_user_id', user.id)
        .order('created_at', ascending: false);
    return _routineShareList(rows);
  }

  @override
  Future<List<RoutineShareRecord>> listOutgoingRoutineShares({
    String? routineId,
  }) async {
    final user = _requireUser();
    final normalizedRoutineId = _validatedOptionalUuid(routineId, 'routineId');
    var query = _client
        .from('routine_shares')
        .select(_routineShareSelect)
        .eq('sender_user_id', user.id);
    if (normalizedRoutineId != null) {
      query = query.eq('coaching_routine_id', normalizedRoutineId);
    }
    final rows = await query.order('created_at', ascending: false);
    return _routineShareList(rows);
  }

  Future<List<RoutineShareRecord>> _loadRoutineShares(
    List<String> shareIds,
  ) async {
    final rows = await _client
        .from('routine_shares')
        .select(_routineShareSelect)
        .inFilter('id', shareIds)
        .order('created_at', ascending: false);
    return _routineShareList(rows);
  }

  @override
  Future<RoutineShareRecord> revokeRoutineShare(
    String shareId, {
    required String requestId,
  }) async {
    _requireUser();
    final id = _validatedUuid(shareId, 'shareId');
    final result = await _client.rpc(
      'revoke_routine_share',
      params: {
        'share_id': id,
        'request_id': _validatedUuid(requestId, 'requestId'),
      },
    );
    final resultRow = _mapValue(result);
    if (resultRow == null ||
        _nullableUuid(resultRow['share_id']) != id ||
        _normalizedEnum(resultRow['status']) != 'revoked') {
      throw const FormatException(
        'Routine share revoke RPC returned an invalid result.',
      );
    }
    final rows = await _loadRoutineShares([id]);
    if (rows.length != 1 || rows.single.status != RoutineShareStatus.revoked) {
      throw StateError('Routine share was not revoked by the server.');
    }
    return rows.single;
  }

  @override
  Future<PersonalRoutineRecord?> respondRoutineShare(
    String shareId, {
    required bool accept,
    String? requestId,
  }) async {
    final result = await _client.rpc(
      'respond_routine_share',
      params: {
        'share_id': _validatedUuid(shareId, 'shareId'),
        'decision': accept ? 'accept' : 'decline',
        'request_id': _validatedOptionalUuid(requestId, 'requestId'),
      },
    );
    return _personalRoutineFromRpc(result);
  }

  @override
  Future<PersonalRoutineRecord> acceptRoutineShareToken(
    String token, {
    String? requestId,
  }) async {
    final normalizedToken = _requiredTrimmed(token, 'token');
    final result = await _client.rpc(
      'accept_routine_share_token',
      params: {
        'token': normalizedToken,
        'request_id': _validatedOptionalUuid(requestId, 'requestId'),
      },
    );
    final routine = _personalRoutineFromRpc(result);
    if (routine == null) {
      throw const FormatException('Share token RPC returned no routine.');
    }
    return routine;
  }

  @override
  Future<PersonalRoutineRecord> importMarketRoutine(
    String marketRoutineId, {
    String? requestId,
  }) async {
    final result = await _client.rpc(
      'import_market_routine',
      params: {
        'market_routine_id': _validatedUuid(marketRoutineId, 'marketRoutineId'),
        'request_id': _validatedOptionalUuid(requestId, 'requestId'),
      },
    );
    final routine = _personalRoutineFromRpc(result);
    if (routine == null) {
      throw const FormatException('Market import RPC returned no routine.');
    }
    return routine;
  }

  @override
  Future<List<PersonalRoutineRecord>> listPersonalRoutines() async {
    final user = _requireUser();
    final rows = await _client
        .from('routines')
        .select(_personalRoutineSelect)
        .eq('owner_user_id', user.id)
        .order('updated_at', ascending: false);
    return List.unmodifiable(rows.map(_personalRoutineFromRow));
  }

  @override
  Future<PersonalRoutineRecord> savePersonalRoutine(
    SavePersonalRoutineInput input,
  ) async {
    final routineId = _validatedUuid(input.routineId, 'routineId');
    final name = _requiredTrimmed(input.name, 'name');
    if (name.length > 120) {
      throw ArgumentError.value(
        input.name,
        'name',
        'Must be at most 120 characters.',
      );
    }
    final description = input.description?.trim();
    if (description != null && description.length > 2000) {
      throw ArgumentError.value(
        input.description,
        'description',
        'Must be at most 2000 characters.',
      );
    }
    final color = _requiredTrimmed(input.color, 'color').toUpperCase();
    if (!RegExp(r'^#[0-9A-F]{6}$').hasMatch(color)) {
      throw ArgumentError.value(
        input.color,
        'color',
        'Must use #RRGGBB format.',
      );
    }

    final result = await _client.rpc(
      'save_personal_routine',
      params: {
        'routine_id': routineId,
        'name': name,
        'description': (description?.isEmpty ?? true) ? null : description,
        'color': color,
        'exercises': _routineExercisesPayload(
          input.exercises,
          allowZeroTargetReps: true,
        ),
        'request_id': _validatedOptionalUuid(input.requestId, 'requestId'),
      },
    );
    final routine = _personalRoutineFromRpc(result);
    if (routine == null) {
      throw const FormatException('Personal routine RPC returned no routine.');
    }
    return routine;
  }

  @override
  Future<void> deletePersonalRoutine(
    String routineId, {
    String? requestId,
  }) async {
    final id = _validatedUuid(routineId, 'routineId');
    final result = await _client.rpc(
      'delete_personal_routine',
      params: {
        'routine_id': id,
        'request_id': _validatedOptionalUuid(requestId, 'requestId'),
      },
    );
    final resultRow = _mapValue(result);
    if (_nullableUuid(resultRow?['deleted_routine_id']) != id) {
      throw const FormatException(
        'Personal routine delete RPC returned an invalid result.',
      );
    }
  }

  Future<OwnedCoachingRoutine> _loadOwnedRoutine(String id) async {
    final row = await _client
        .from('coaching_routines')
        .select(_routineSelect)
        .eq('id', id)
        .maybeSingle();
    if (row == null) throw StateError('Created routine was not found.');
    return _routineFromRow(row);
  }

  Future<OwnedCoachingRoutine> _ownedRoutineFromRpc(
    Object? result, {
    String? fallbackId,
  }) async {
    final resultRow = _mapValue(result);
    final routineRow = _mapValue(resultRow?['routine']) ?? resultRow;
    if (routineRow != null &&
        routineRow.containsKey('id') &&
        routineRow.containsKey('exercises')) {
      return _routineFromRow(routineRow);
    }
    final resolvedId = _uuidFromRpc(result) ?? fallbackId;
    if (resolvedId == null) {
      throw const FormatException('Routine RPC result is missing a routine.');
    }
    return _loadOwnedRoutine(resolvedId);
  }

  Future<BusinessApplication> _applicationFromRpc(
    Object? result,
    BusinessApplicationKind kind,
  ) async {
    final resultRow = _mapValue(result);
    if (resultRow != null &&
        resultRow.containsKey('status') &&
        resultRow.containsKey('id')) {
      return _applicationFromRow(resultRow, kind);
    }
    final id = _uuidFromRpc(result);
    if (id == null) {
      throw const FormatException('RPC result is missing an application UUID.');
    }
    final table = kind == BusinessApplicationKind.trainer
        ? 'trainer_applications'
        : 'gym_applications';
    final select = kind == BusinessApplicationKind.trainer
        ? 'id,trainer_id,user_id,name,submitted_at,sla_due_at,status,'
              'reject_reason,reviewer_id'
        : 'id,gym_id,owner_user_id,gym_name,owner_name,biz_reg_no,'
              'submitted_at,sla_due_at,status,reject_reason,reviewer_id';
    final row = await _client
        .from(table)
        .select(select)
        .eq('id', id)
        .maybeSingle();
    if (row == null) throw StateError('Application was not found.');
    return _applicationFromRow(row, kind);
  }

  User _requireUser() {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Authentication is required.');
    return user;
  }
}

TrainerBusinessProfile _trainerFromRow(Map<String, dynamic> row) {
  final serviceAreas = _mapListValue(
    row['service_areas'],
  ).map(_trainerServiceAreaFromRow).toList(growable: false);
  return TrainerBusinessProfile(
    id: _requiredUuid(row, 'id'),
    userId: _nullableUuid(row['user_id']) ?? '',
    displayName: _stringValue(row['display_name'], fallback: '트레이너'),
    keyword: _nullableString(row['keyword']),
    intro: _nullableString(row['intro']),
    imageUrl: _nullableString(row['profile_image_url']),
    careerYears: _nullableInt(row['career_years']),
    centerName: _nullableString(row['center_name']),
    rating: _doubleValue(row['rating_avg']),
    postCount: _intValue(row['post_count']),
    coachingTotal: _intValue(row['coaching_total']),
    acceptsOnlineConsultation: row.containsKey('accepts_online_consultation')
        ? _boolValue(row['accepts_online_consultation'])
        : true,
    acceptsOfflineConsultation: _boolValue(row['accepts_offline_consultation']),
    serviceAreas: List.unmodifiable(serviceAreas),
    isPublic: _boolValue(row['is_public']),
    verified: _boolValue(row['verified_badge']),
    status: _profileStatusFromDatabase(row['status']),
    createdAt: _nullableDateTime(row['created_at']),
    updatedAt: _nullableDateTime(row['updated_at']),
  );
}

ServiceRegion _serviceRegionFromRow(Map<String, dynamic> row) {
  return ServiceRegion(
    code: _stringValue(row['code']),
    name: _stringValue(row['name']),
    sortOrder: _intValue(row['sort_order']),
  );
}

TrainerServiceArea _trainerServiceAreaFromRow(Map<String, dynamic> row) {
  return TrainerServiceArea(
    regionCode: _stringValue(row['region_code']),
    regionName: _stringValue(row['region_name']),
    isPrimary: _boolValue(row['is_primary']),
  );
}

GymDirectoryEntry _gymDirectoryFromRow(Map<String, dynamic> row) {
  return GymDirectoryEntry(
    id: _requiredUuid(row, 'id'),
    name: _stringValue(row['name'], fallback: '헬스장'),
    address: _nullableString(row['address']),
  );
}

MemberWorkoutLocation _memberWorkoutLocationFromRow(Map<String, dynamic> row) {
  final gym = _mapValue(row['gym']);
  if (gym == null) {
    throw const FormatException('Workout location has no gym.');
  }
  return MemberWorkoutLocation(
    id: _requiredUuid(row, 'id'),
    userId: _requiredUuid(row, 'user_id'),
    gymId: _requiredUuid(row, 'gym_id'),
    gymName: _stringValue(gym['name'], fallback: '헬스장'),
    gymAddress: _nullableString(gym['address']),
    isActive: _boolValue(row['is_active']),
    lastSelectedAt: _nullableDateTime(row['last_selected_at']),
    createdAt: _nullableDateTime(row['created_at']),
  );
}

PublicTrainer _publicTrainerFromSearchRow(Map<String, dynamic> row) {
  final rank = _nullableInt(row['match_rank']);
  if (rank == null || rank < 0 || rank > 2) {
    throw const FormatException('Trainer search returned an invalid rank.');
  }
  final keyword = _nullableString(row['keyword']);
  final specialties = keyword == null
      ? const <String>[]
      : keyword
            .split(RegExp(r'[,/#]'))
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
  return PublicTrainer(
    profile: _trainerFromRow({
      ...row,
      // Eligibility is enforced inside search_public_trainers and these
      // fields are deliberately not exposed in its result projection.
      'is_public': true,
      'status': 'approved',
    }),
    specialties: List.unmodifiable(specialties),
  );
}

TopCoachingTrainer _topCoachingTrainerFromRow(Map<String, dynamic> row) {
  final activeCoachingCount = _nullableInt(row['active_coaching_count']);
  if (activeCoachingCount == null || activeCoachingCount < 0) {
    throw const FormatException(
      'Top coaching trainer query returned an invalid active count.',
    );
  }
  return TopCoachingTrainer(
    trainer: _publicTrainerFromSearchRow({...row, 'match_rank': 0}),
    activeCoachingCount: activeCoachingCount,
  );
}

String _encodePublicTrainerSearchCursor(Map<String, dynamic> row) {
  final rank = _nullableInt(row['match_rank']);
  final rating = _nullableDouble(row['rating_avg']);
  final id = _nullableUuid(row['id']);
  if (rank == null || rank < 0 || rank > 2 || rating == null || id == null) {
    throw const FormatException('Trainer search returned an invalid cursor.');
  }
  final payload = jsonEncode({
    'v': 1,
    'rank': rank,
    'rating': rating,
    'id': id,
  });
  return base64Url.encode(utf8.encode(payload)).replaceAll('=', '');
}

_PublicTrainerSearchCursor _decodePublicTrainerSearchCursor(String cursor) {
  final normalized = cursor.trim();
  if (normalized.isEmpty || normalized.length > 256) {
    throw ArgumentError.value(cursor, 'cursor', 'Invalid search cursor.');
  }
  try {
    final padding = (4 - normalized.length % 4) % 4;
    final decoded = jsonDecode(
      utf8.decode(
        base64Url.decode(normalized.padRight(normalized.length + padding, '=')),
      ),
    );
    if (decoded is! Map || decoded['v'] != 1) {
      throw const FormatException();
    }
    final rank = _nullableInt(decoded['rank']);
    final rating = _nullableDouble(decoded['rating']);
    final id = _nullableUuid(decoded['id']);
    if (rank == null ||
        rank < 0 ||
        rank > 2 ||
        rating == null ||
        rating < 0 ||
        id == null) {
      throw const FormatException();
    }
    return _PublicTrainerSearchCursor(rank: rank, rating: rating, id: id);
  } on Object {
    throw ArgumentError.value(cursor, 'cursor', 'Invalid search cursor.');
  }
}

class _PublicTrainerSearchCursor {
  const _PublicTrainerSearchCursor({
    required this.rank,
    required this.rating,
    required this.id,
  });

  final int rank;
  final double rating;
  final String id;
}

GymBusinessProfile _gymFromRow(Map<String, dynamic> row) {
  return GymBusinessProfile(
    id: _requiredUuid(row, 'id'),
    ownerUserId: _requiredUuid(row, 'owner_user_id'),
    name: _stringValue(row['name'], fallback: '센터'),
    representativeName: _nullableString(row['rep_name']),
    gymType: _nullableString(row['gym_type']),
    address: _nullableString(row['address']),
    description: _nullableString(row['description']),
    coverImageUrl: _nullableString(row['cover_image_url']),
    businessNumber: _nullableString(row['business_number']),
    planTier: _nullableString(row['plan_tier']),
    status: _profileStatusFromDatabase(row['status']),
    createdAt: _nullableDateTime(row['created_at']),
    updatedAt: _nullableDateTime(row['updated_at']),
  );
}

BusinessMember _memberFromRow(
  Map<String, dynamic> row, {
  Map<String, String?> goalProjection = const {},
}) {
  final user = _mapValue(row['user']);
  final profile = _mapValue(user?['profile']);
  final gym = _mapValue(row['gym']);
  final userId = _nullableUuid(row['user_id']);
  final hasProjectedGoal = userId != null && goalProjection.containsKey(userId);
  return BusinessMember(
    id: _requiredUuid(row, 'id'),
    gymId: _requiredUuid(row, 'gym_id'),
    userId: userId,
    name:
        _nullableString(row['name']) ??
        _nullableString(user?['nickname']) ??
        '회원',
    phone: _nullableString(row['phone']),
    avatarUrl: _nullableString(user?['avatar_url']),
    goal: hasProjectedGoal
        ? goalProjection[userId]
        : _nullableString(profile?['goal']) ?? _nullableString(row['goal']),
    level: _nullableString(profile?['level']),
    remainingPtSessions: _intValue(row['remaining_pt_sessions']),
    completionRate: _doubleValue(row['completion_rate']),
    createdAt: _nullableDateTime(row['created_at']),
    lastActivityAt: _nullableDateTime(row['last_activity_at']),
    gymName: _nullableString(row['gym_name']) ?? _nullableString(gym?['name']),
    status: _stringValue(row['status'], fallback: 'active'),
    endedAt: _nullableDateTime(row['ended_at']),
  );
}

BusinessMemberDetail _memberDetailFromRow(Map<String, dynamic> row) {
  final sessions =
      _mapListValue(
          row['sessions'],
        ).map(_businessWorkoutSessionFromRow).toList(growable: false)
        ..sort((left, right) => right.date.compareTo(left.date));
  return BusinessMemberDetail(
    memberId: _requiredUuid(row, 'member_id'),
    memberUserId: _nullableUuid(row['member_user_id']),
    shareBodyData: _boolValue(row['share_body_data']),
    shareWorkoutRecords: _boolValue(row['share_workout_records']),
    canReadWorkouts: _boolValue(row['can_read_workouts']),
    sessions: List.unmodifiable(sessions),
  );
}

MemberSharingPreferences _sharingPreferencesFromRow(Map<String, dynamic> row) {
  return MemberSharingPreferences(
    shareBodyData: _boolValue(row['share_body_data']),
    shareWorkoutRecords: _boolValue(row['share_workout_records']),
    marketing: _boolValue(row['marketing']),
  );
}

BusinessWorkoutSession _businessWorkoutSessionFromRow(
  Map<String, dynamic> row,
) {
  final date = _nullableDateTime(row['date']);
  if (date == null) throw const FormatException('Workout date is missing.');
  final exercises =
      _mapListValue(
          row['exercises'],
        ).map(_businessWorkoutExerciseFromRow).toList(growable: false)
        ..sort((left, right) => left.orderIndex.compareTo(right.orderIndex));
  final feedbacks =
      _mapListValue(
          row['feedbacks'],
        ).map(_sessionFeedbackFromRow).toList(growable: false)
        ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
  return BusinessWorkoutSession(
    id: _requiredUuid(row, 'id'),
    userId: _requiredUuid(row, 'user_id'),
    date: DateTime(date.year, date.month, date.day),
    category: _nullableString(row['category']),
    intensity: _nullableString(row['intensity']),
    feedback: _nullableString(row['feedback']),
    startedAt: _nullableDateTime(row['started_at']),
    endedAt: _nullableDateTime(row['ended_at']),
    exercises: List.unmodifiable(exercises),
    feedbacks: List.unmodifiable(feedbacks),
  );
}

BusinessWorkoutExercise _businessWorkoutExerciseFromRow(
  Map<String, dynamic> row,
) {
  final sets =
      _mapListValue(
          row['sets'],
        ).map(_businessWorkoutSetFromRow).toList(growable: false)
        ..sort((left, right) => left.setNumber.compareTo(right.setNumber));
  return BusinessWorkoutExercise(
    id: _requiredUuid(row, 'id'),
    baseExerciseId: _nullableUuid(row['base_exercise_id']),
    name: _stringValue(row['name'], fallback: '운동'),
    targetMuscle: _nullableString(row['target_muscle']),
    orderIndex: _intValue(row['order_index']),
    sets: List.unmodifiable(sets),
  );
}

BusinessWorkoutSet _businessWorkoutSetFromRow(Map<String, dynamic> row) {
  return BusinessWorkoutSet(
    id: _requiredUuid(row, 'id'),
    setNumber: _intValue(row['set_no']),
    type: _stringValue(row['type'], fallback: 'normal'),
    weight: _doubleValue(row['weight']),
    reps: _intValue(row['reps']),
    durationSeconds: _nullableInt(row['duration_sec']),
    distanceMeters: _nullableDouble(row['distance_m']),
    intensityRpe: _nullableDouble(row['intensity_rpe']),
    rir: _nullableInt(row['rir']),
    memo: _nullableString(row['memo']),
    completed: _boolValue(row['completed']),
    completedAt: _nullableDateTime(row['completed_at']),
    estimated1Rm: _nullableDouble(row['estimated_1rm']),
    restSeconds: _nullableInt(row['rest_seconds']) ?? 90,
  );
}

BusinessSessionFeedback _sessionFeedbackFromRow(Map<String, dynamic> row) {
  final createdAt = _nullableDateTime(row['created_at']);
  if (createdAt == null) {
    throw const FormatException('Session feedback timestamp is missing.');
  }
  return BusinessSessionFeedback(
    id: _requiredUuid(row, 'id'),
    sessionId: _requiredUuid(row, 'session_id'),
    trainerUserId:
        _nullableUuid(row['trainer_user_id']) ??
        _nullableUuid(row['trainer_id']),
    authorName: _stringValue(row['author_name'], fallback: '담당자'),
    text: _stringValue(row['text']),
    createdAt: createdAt,
  );
}

MemberSessionFeedback _memberSessionFeedbackFromRow(Map<String, dynamic> row) {
  final sessionDate = _nullableDateTime(row['session_date']);
  final createdAt = _nullableDateTime(row['created_at']);
  if (sessionDate == null || createdAt == null) {
    throw const FormatException('Member session feedback date is missing.');
  }
  return MemberSessionFeedback(
    id: _requiredUuid(row, 'id'),
    sessionId: _requiredUuid(row, 'session_id'),
    sessionDate: DateTime(sessionDate.year, sessionDate.month, sessionDate.day),
    trainerUserId:
        _nullableUuid(row['trainer_user_id']) ??
        _nullableUuid(row['trainer_id']),
    authorName: _stringValue(row['author_name'], fallback: '담당자'),
    text: _stringValue(row['text']),
    createdAt: createdAt,
  );
}

BusinessCoachingSchedule _coachingScheduleFromRow(Map<String, dynamic> row) {
  final date = _nullableDateTime(row['date']);
  final createdAt = _nullableDateTime(row['created_at']);
  if (date == null || createdAt == null) {
    throw const FormatException('Coaching schedule timestamps are missing.');
  }
  final trainer = _mapValue(row['trainer']);
  final member = _mapValue(row['member']);
  final gym = _mapValue(row['gym']);
  return BusinessCoachingSchedule(
    id: _requiredUuid(row, 'id'),
    trainerId: _requiredUuid(row, 'trainer_id'),
    memberUserId: _nullableUuid(row['member_user_id']),
    gymId: _nullableUuid(row['gym_id']),
    title: _stringValue(row['title'], fallback: '코칭 일정'),
    date: DateTime(date.year, date.month, date.day),
    startMinutes: _timeMinutes(row['start_time'], 'start_time'),
    endMinutes: _timeMinutes(row['end_time'], 'end_time'),
    trainerName: _nullableString(trainer?['display_name']),
    memberName: _nullableString(member?['nickname']),
    gymName: _nullableString(gym?['name']),
    createdAt: createdAt,
    completedAt: _nullableDateTime(row['completed_at']),
  );
}

BusinessMemberAssignment _assignmentFromRow(Map<String, dynamic> row) {
  final trainer = _mapValue(row['trainer']);
  return BusinessMemberAssignment(
    id: _requiredUuid(row, 'id'),
    gymId: _requiredUuid(row, 'gym_id'),
    memberId: _requiredUuid(row, 'member_id'),
    trainerId: _nullableUuid(row['trainer_id']),
    trainerName: _nullableString(trainer?['display_name']),
    active: _boolValue(row['active']),
    assignedAt: _nullableDateTime(row['assigned_at']),
  );
}

GymTrainerRecord _gymTrainerFromRow(Map<String, dynamic> row) {
  final trainer = _mapValue(row['trainer']);
  return GymTrainerRecord(
    id: _requiredUuid(row, 'id'),
    gymId: _requiredUuid(row, 'gym_id'),
    trainerId: _nullableUuid(row['trainer_id']),
    trainerUserId:
        _nullableUuid(row['trainer_user_id']) ??
        _nullableUuid(trainer?['user_id']),
    displayName: _nullableString(trainer?['display_name']),
    roleTitle: _nullableString(row['role_title']),
    imageUrl: _nullableString(trainer?['profile_image_url']),
    status: _stringValue(row['status'], fallback: 'unknown'),
    memberCount: _intValue(row['member_count']),
    averageRating: _doubleValue(row['avg_rating']),
    monthlySales: _doubleValue(row['monthly_sales']),
    feedbackFulfillmentRate: _doubleValue(row['feedback_fulfillment_rate']),
    createdAt: _nullableDateTime(row['created_at']),
  );
}

BusinessInviteRecord _businessInviteFromRow(Map<String, dynamic> row) {
  final expiresAt = _nullableDateTime(row['expires_at']);
  final createdAt = _nullableDateTime(row['created_at']);
  final updatedAt = _nullableDateTime(row['updated_at']);
  if (expiresAt == null || createdAt == null || updatedAt == null) {
    throw const FormatException('Business invite timestamps are missing.');
  }
  var status = _businessInviteStatusFromDatabase(row['status']);
  if (status == BusinessInviteStatus.pending &&
      !expiresAt.isAfter(DateTime.now())) {
    status = BusinessInviteStatus.expired;
  }
  return BusinessInviteRecord(
    id: _requiredUuid(row, 'id'),
    gymId: _requiredUuid(row, 'gym_id'),
    kind: _businessInviteKindFromDatabase(row['invite_kind']),
    status: status,
    createdByUserId: _requiredUuid(row, 'created_by_user_id'),
    memberId: _nullableUuid(row['member_id']),
    recipientName: _nullableString(row['recipient_name']),
    recipientPhone: _nullableString(row['recipient_phone']),
    roleTitle: _nullableString(row['role_title']),
    expiresAt: expiresAt,
    acceptedByUserId: _nullableUuid(row['accepted_by_user_id']),
    acceptedMemberId: _nullableUuid(row['accepted_member_id']),
    acceptedTrainerId: _nullableUuid(row['accepted_trainer_id']),
    acceptedGymTrainerId: _nullableUuid(row['accepted_gym_trainer_id']),
    acceptedAt: _nullableDateTime(row['accepted_at']),
    revokedAt: _nullableDateTime(row['revoked_at']),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

BusinessDashboardMetrics _trainerDashboardFromRow(Map<String, dynamic>? row) {
  if (row == null) return const BusinessDashboardMetrics();
  return BusinessDashboardMetrics(
    unreadConsultations: _intValue(row['unread_consults']),
    activeMembers: _intValue(row['active_members']),
    pendingSettlement: _doubleValue(row['pending_settlement']),
    monthSettled: _doubleValue(row['month_settled']),
    overdueFeedbacks: _intValue(row['overdue_feedbacks']),
  );
}

BusinessDashboardMetrics _gymDashboardFromRow(Map<String, dynamic>? row) {
  if (row == null) return const BusinessDashboardMetrics();
  return BusinessDashboardMetrics(
    activeMembers: _intValue(row['member_count']),
    totalRevenue: _doubleValue(row['total_revenue']),
    trainerCount: _intValue(row['trainer_count']),
  );
}

List<BusinessConsultation> _consultationList(Object? value) {
  return List.unmodifiable(_mapListValue(value).map(_consultationFromRow));
}

BusinessConsultation _consultationFromRow(Map<String, dynamic> row) {
  final member = _mapValue(row['member']);
  final trainer = _mapValue(row['trainer']);
  final assignedTrainer = _mapValue(row['assigned_trainer']);
  final gym = _mapValue(row['gym']);
  final recommendationProfileShare = _mapValue(
    row['recommendation_profile_share'],
  );
  final messages =
      _mapListValue(
        row['messages'],
      ).map(_consultationMessageFromRow).toList(growable: false)..sort((
        left,
        right,
      ) {
        final leftAt = left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final rightAt =
            right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final byTime = leftAt.compareTo(rightAt);
        return byTime != 0 ? byTime : left.id.compareTo(right.id);
      });
  return BusinessConsultation(
    id: _requiredUuid(row, 'id'),
    userId: _requiredUuid(row, 'user_id'),
    trainerId: _nullableUuid(row['trainer_id']),
    gymId: _nullableUuid(row['gym_id']),
    routineId: _nullableUuid(row['routine_id']),
    assignedTrainerId: _nullableUuid(row['assigned_trainer_id']),
    mode: _consultationModeFromDatabase(row['consultation_mode']),
    matchingSource: _consultationMatchingSourceFromDatabase(
      row['matching_source'],
    ),
    requestedRegionCode: _nullableString(row['requested_region_code']),
    status: _consultationStatusFromDatabase(row['status']),
    isRead: _boolValue(row['is_read']),
    memberName:
        _nullableString(member?['nickname']) ??
        _nullableString(row['requester_name']),
    memberAvatarUrl: _nullableString(member?['avatar_url']),
    trainerName:
        _nullableString(assignedTrainer?['display_name']) ??
        _nullableString(trainer?['display_name']),
    gymName: _nullableString(gym?['name']),
    specialty: _nullableString(row['specialty']),
    goal: _nullableString(row['goal']),
    level: _nullableString(row['level']),
    question: _nullableString(row['question']),
    createdAt: _nullableDateTime(row['created_at']),
    sharedRecommendationProfile: RecommendationProfile.tryFromJson(
      recommendationProfileShare?['profile_snapshot'],
    ),
    recommendationProfileSharedAt: _nullableDateTime(
      recommendationProfileShare?['consented_at'],
    ),
    recommendationProfileShareRevokedAt: _nullableDateTime(
      recommendationProfileShare?['revoked_at'],
    ),
    messages: List.unmodifiable(messages),
  );
}

ConsultationMode _consultationModeFromDatabase(Object? value) {
  return switch (value) {
    'offline' => ConsultationMode.offline,
    _ => ConsultationMode.online,
  };
}

ConsultationMatchingSource _consultationMatchingSourceFromDatabase(
  Object? value,
) {
  return switch (value) {
    'region' => ConsultationMatchingSource.region,
    'gym' => ConsultationMatchingSource.gym,
    _ => ConsultationMatchingSource.direct,
  };
}

BusinessConsultationMessage _consultationMessageFromRow(
  Map<String, dynamic> row,
) {
  return BusinessConsultationMessage(
    id: _requiredUuid(row, 'id'),
    consultationId: _requiredUuid(row, 'consultation_id'),
    sender: _messageSenderFromDatabase(row['sender_type']),
    senderId: _nullableUuid(row['sender_id']),
    text: _stringValue(row['text']),
    createdAt: _nullableDateTime(row['created_at']),
  );
}

List<OwnedCoachingRoutine> _routineList(Object? value) {
  return List.unmodifiable(_mapListValue(value).map(_routineFromRow));
}

List<Map<String, Object?>> _routineExercisesPayload(
  List<CreateOwnedRoutineExerciseInput> exercises, {
  bool allowZeroTargetReps = false,
}) {
  if (exercises.isEmpty || exercises.length > 50) {
    throw ArgumentError.value(
      exercises,
      'exercises',
      'A routine requires between 1 and 50 exercises.',
    );
  }

  return List.generate(exercises.length, (exerciseIndex) {
    final exercise = exercises[exerciseIndex];
    final name = _requiredTrimmed(
      exercise.name,
      'exercises[$exerciseIndex].name',
    );
    final targetMuscle = _requiredTrimmed(
      exercise.targetMuscle,
      'exercises[$exerciseIndex].targetMuscle',
    );
    if (name.length > 120) {
      throw ArgumentError.value(
        exercise.name,
        'exercises[$exerciseIndex].name',
        'Must be at most 120 characters.',
      );
    }
    if (targetMuscle.length > 80) {
      throw ArgumentError.value(
        exercise.targetMuscle,
        'exercises[$exerciseIndex].targetMuscle',
        'Must be at most 80 characters.',
      );
    }
    if (exercise.sets.isEmpty || exercise.sets.length > 20) {
      throw ArgumentError.value(
        exercise.sets,
        'exercises[$exerciseIndex].sets',
        'Every exercise requires between 1 and 20 sets.',
      );
    }

    final sets = [...exercise.sets]
      ..sort((left, right) => left.setNumber.compareTo(right.setNumber));
    final normalizedTargetMuscle = targetMuscle.trim().toLowerCase();
    final isCardioExercise = const {
      '유산소',
      'cardio',
      'aerobic',
    }.contains(normalizedTargetMuscle);
    final seenSetNumbers = <int>{};
    final setPayloads = List.generate(sets.length, (setIndex) {
      final set = sets[setIndex];
      if (set.setNumber < 1 || !seenSetNumbers.add(set.setNumber)) {
        throw ArgumentError.value(
          set.setNumber,
          'exercises[$exerciseIndex].sets[$setIndex].setNumber',
          'Must be a unique positive number.',
        );
      }
      final normalizedType = set.type.trim().toLowerCase();
      if (!const {
        'normal',
        'warmup',
        'drop',
        'failure',
        '일반',
        '웜업',
        '드랍',
        '실패',
      }.contains(normalizedType)) {
        throw ArgumentError.value(
          set.type,
          'exercises[$exerciseIndex].sets[$setIndex].type',
          'Unknown routine set type.',
        );
      }
      final weight = set.targetWeight;
      if (weight != null && (!weight.isFinite || weight < 0 || weight > 5000)) {
        throw ArgumentError.value(
          weight,
          'exercises[$exerciseIndex].sets[$setIndex].targetWeight',
          'Must be between 0 and 5000.',
        );
      }
      final reps = set.targetReps;
      final durationSeconds = set.durationSeconds;
      if (durationSeconds != null &&
          (durationSeconds < 1 || durationSeconds > 604800)) {
        throw ArgumentError.value(
          durationSeconds,
          'exercises[$exerciseIndex].sets[$setIndex].durationSeconds',
          'Must be between 1 second and 7 days.',
        );
      }
      final distanceMeters = set.distanceMeters;
      if (distanceMeters != null &&
          (!distanceMeters.isFinite ||
              distanceMeters < 0.01 ||
              distanceMeters > 999999.99)) {
        throw ArgumentError.value(
          distanceMeters,
          'exercises[$exerciseIndex].sets[$setIndex].distanceMeters',
          'Must be between 0.01 and 999999.99 metres.',
        );
      }
      final intensityRpe = set.intensityRpe;
      if (intensityRpe != null &&
          (!intensityRpe.isFinite || intensityRpe < 1 || intensityRpe > 10)) {
        throw ArgumentError.value(
          intensityRpe,
          'exercises[$exerciseIndex].sets[$setIndex].intensityRpe',
          'Must be between 1 and 10.',
        );
      }
      if (isCardioExercise &&
          durationSeconds == null &&
          distanceMeters == null) {
        throw ArgumentError.value(
          set,
          'exercises[$exerciseIndex].sets[$setIndex]',
          'Cardio sets require a duration or distance.',
        );
      }
      final minimumReps = allowZeroTargetReps ? 0 : 1;
      if (!isCardioExercise &&
          (reps == null || reps < minimumReps || reps > 1000)) {
        throw ArgumentError.value(
          reps,
          'exercises[$exerciseIndex].sets[$setIndex].targetReps',
          'Must be between $minimumReps and 1000.',
        );
      }
      if (set.restSeconds < 0 || set.restSeconds > 3600) {
        throw ArgumentError.value(
          set.restSeconds,
          'exercises[$exerciseIndex].sets[$setIndex].restSeconds',
          'Must be between 0 and 3600.',
        );
      }
      return <String, Object?>{
        'type': workoutSetTypeDatabaseValue(normalizedType),
        'target_weight': isCardioExercise ? null : weight,
        'target_reps': isCardioExercise ? null : reps,
        'duration_sec': durationSeconds,
        'distance_m': distanceMeters,
        'intensity_rpe': intensityRpe,
        'rest_seconds': set.restSeconds,
      };
    });

    return <String, Object?>{
      'base_exercise_id': _validatedOptionalUuid(
        exercise.baseExerciseId,
        'exercises[$exerciseIndex].baseExerciseId',
      ),
      'name': name,
      'target_muscle': targetMuscle,
      'sets': setPayloads,
    };
  });
}

OwnedCoachingRoutine _routineFromRow(Map<String, dynamic> row) {
  final routineId = _requiredUuid(row, 'id');
  final exercises =
      _mapListValue(row['exercises'])
          .map((exercise) => _routineExerciseFromRow(exercise, routineId))
          .toList(growable: false)
        ..sort((left, right) {
          final byOrder = left.orderIndex.compareTo(right.orderIndex);
          return byOrder != 0 ? byOrder : left.id.compareTo(right.id);
        });
  return OwnedCoachingRoutine(
    id: routineId,
    trainerId: _nullableUuid(row['trainer_id']),
    gymId: _nullableUuid(row['gym_id']),
    title: _stringValue(row['title'], fallback: '루틴'),
    intro: _nullableString(row['intro']),
    price: _nullableDouble(row['price']),
    difficulty: _routineDifficultyFromDatabase(row['difficulty']),
    status: _routineStatusFromDatabase(row['status']),
    rejectReason: _nullableString(row['reject_reason']),
    cumulativeUsers: _intValue(row['cumulative_users']),
    createdAt: _nullableDateTime(row['created_at']),
    updatedAt: _nullableDateTime(row['updated_at']),
    exercises: List.unmodifiable(exercises),
  );
}

List<RoutineShareRecord> _routineShareList(Object? value) {
  return List.unmodifiable(_mapListValue(value).map(_routineShareFromRow));
}

RoutineShareRecord _routineShareFromRow(Map<String, dynamic> row) {
  final routineRow = _mapValue(row['routine']);
  final routine = routineRow == null ? null : _routineFromRow(routineRow);
  final trainer = _mapValue(row['sender_trainer']);
  final gym = _mapValue(row['sender_gym']);
  final sender = _mapValue(row['sender']);
  final expiresAt = _nullableDateTime(row['expires_at']);
  var status = _routineShareStatusFromDatabase(row['status']);
  if (status == RoutineShareStatus.pending &&
      expiresAt != null &&
      !expiresAt.isAfter(DateTime.now())) {
    status = RoutineShareStatus.expired;
  }
  return RoutineShareRecord(
    id: _requiredUuid(row, 'id'),
    routineId:
        _nullableUuid(row['coaching_routine_id']) ??
        routine?.id ??
        (throw const FormatException('Routine share has no source routine.')),
    senderUserId: _requiredUuid(row, 'sender_user_id'),
    recipientUserId: _nullableUuid(row['recipient_user_id']),
    status: status,
    kind: _routineShareKindFromDatabase(row['share_type']),
    routineTitle:
        _nullableString(row['routine_title']) ?? routine?.title ?? '공유 루틴',
    senderName:
        _nullableString(trainer?['display_name']) ??
        _nullableString(gym?['name']) ??
        _nullableString(sender?['nickname']) ??
        'Setflow 전문가',
    message: _nullableString(row['message']),
    expiresAt: expiresAt,
    respondedAt: _nullableDateTime(row['responded_at']),
    acceptedRoutineId: _nullableUuid(row['accepted_routine_id']),
    createdAt: _nullableDateTime(row['created_at']),
    routine: routine,
  );
}

PersonalRoutineRecord? _personalRoutineFromRpc(Object? result) {
  final resultRow = _mapValue(result);
  if (resultRow == null) return null;
  final routineRow = resultRow.containsKey('owner_user_id')
      ? resultRow
      : _mapValue(resultRow['routine']) ??
            _mapValue(resultRow['personal_routine']);
  return routineRow == null ? null : _personalRoutineFromRow(routineRow);
}

PersonalRoutineRecord _personalRoutineFromRow(Map<String, dynamic> row) {
  final routineId = _requiredUuid(row, 'id');
  final exercises =
      _mapListValue(row['exercises'])
          .map((exercise) => _routineExerciseFromRow(exercise, routineId))
          .toList(growable: false)
        ..sort((left, right) {
          final byOrder = left.orderIndex.compareTo(right.orderIndex);
          return byOrder != 0 ? byOrder : left.id.compareTo(right.id);
        });
  return PersonalRoutineRecord(
    id: routineId,
    ownerUserId: _requiredUuid(row, 'owner_user_id'),
    name: _stringValue(row['name'], fallback: '루틴'),
    description: _nullableString(row['description']),
    color: _nullableString(row['color']),
    source: _nullableString(row['source']),
    marketRoutineId: _nullableUuid(row['market_routine_id']),
    sourceCoachingRoutineId: _nullableUuid(row['source_coaching_routine_id']),
    createdAt: _nullableDateTime(row['created_at']),
    updatedAt: _nullableDateTime(row['updated_at']),
    exercises: List.unmodifiable(exercises),
  );
}

OwnedRoutineExercise _routineExerciseFromRow(
  Map<String, dynamic> row,
  String fallbackRoutineId,
) {
  final id = _requiredUuid(row, 'id');
  final sets =
      _mapListValue(
          row['sets'],
        ).map((set) => _routineSetFromRow(set, id)).toList(growable: false)
        ..sort((left, right) {
          final byNumber = left.setNumber.compareTo(right.setNumber);
          return byNumber != 0 ? byNumber : left.id.compareTo(right.id);
        });
  return OwnedRoutineExercise(
    id: id,
    routineId: _nullableUuid(row['routine_id']) ?? fallbackRoutineId,
    baseExerciseId: _nullableUuid(row['base_exercise_id']),
    name: _stringValue(row['name'], fallback: '운동'),
    targetMuscle: _stringValue(row['target_muscle'], fallback: '전신'),
    orderIndex: _intValue(row['order_index']),
    sets: List.unmodifiable(sets),
  );
}

OwnedRoutineSet _routineSetFromRow(
  Map<String, dynamic> row,
  String fallbackExerciseId,
) {
  return OwnedRoutineSet(
    id: _requiredUuid(row, 'id'),
    exerciseId: _nullableUuid(row['routine_exercise_id']) ?? fallbackExerciseId,
    setNumber: _intValue(row['set_no']),
    type: _stringValue(row['type'], fallback: 'normal'),
    targetWeight: _nullableDouble(row['target_weight']),
    targetReps: _nullableInt(row['target_reps']),
    durationSeconds: _nullableInt(row['duration_sec']),
    distanceMeters: _nullableDouble(row['distance_m']),
    intensityRpe: _nullableDouble(row['intensity_rpe']),
    restSeconds: _nullableInt(row['rest_seconds']) ?? 90,
  );
}

BusinessApplication _applicationFromRow(
  Map<String, dynamic> row,
  BusinessApplicationKind kind,
) {
  final isTrainer = kind == BusinessApplicationKind.trainer;
  return BusinessApplication(
    id: _requiredUuid(row, 'id'),
    kind: kind,
    status: _applicationStatusFromDatabase(row['status']),
    applicantName:
        _nullableString(row[isTrainer ? 'name' : 'owner_name']) ??
        _nullableString(row['gym_name']) ??
        '신청자',
    userId: _nullableUuid(row[isTrainer ? 'user_id' : 'owner_user_id']),
    profileId: _nullableUuid(row[isTrainer ? 'trainer_id' : 'gym_id']),
    businessNumber: isTrainer ? null : _nullableString(row['biz_reg_no']),
    rejectReason: _nullableString(row['reject_reason']),
    reviewerId: _nullableUuid(row['reviewer_id']),
    submittedAt: _nullableDateTime(row['submitted_at']),
    slaDueAt: _nullableDateTime(row['sla_due_at']),
  );
}

BusinessApplication? _currentApplication(
  UserRole accountRole,
  BusinessApplication? trainer,
  BusinessApplication? gym,
) {
  if (accountRole == UserRole.trainer && trainer != null) return trainer;
  if (accountRole == UserRole.gym && gym != null) return gym;
  if (trainer == null) return gym;
  if (gym == null) return trainer;
  final trainerAt =
      trainer.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final gymAt = gym.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  return trainerAt.isAfter(gymAt) ? trainer : gym;
}

UserRole _userRoleFromDatabase(Object? value) {
  return switch (_normalizedEnum(value)) {
    'general' || 'member' => UserRole.member,
    'trainer' => UserRole.trainer,
    'gym' => UserRole.gym,
    'admin' => UserRole.admin,
    'guest' => UserRole.guest,
    _ => UserRole.guest,
  };
}

BusinessApplicationStatus _applicationStatusFromDatabase(Object? value) {
  return switch (_normalizedEnum(value)) {
    'pending' => BusinessApplicationStatus.pending,
    'approved' => BusinessApplicationStatus.approved,
    'rejected' => BusinessApplicationStatus.rejected,
    _ => BusinessApplicationStatus.unknown,
  };
}

BusinessProfileStatus _profileStatusFromDatabase(Object? value) {
  return switch (_normalizedEnum(value)) {
    'onboarding' => BusinessProfileStatus.onboarding,
    'pending' => BusinessProfileStatus.pending,
    'approved' => BusinessProfileStatus.approved,
    'verified' => BusinessProfileStatus.verified,
    'rejected' => BusinessProfileStatus.rejected,
    'suspended' => BusinessProfileStatus.suspended,
    'grace_period' => BusinessProfileStatus.gracePeriod,
    'withdraw_pending' => BusinessProfileStatus.withdrawPending,
    _ => BusinessProfileStatus.unknown,
  };
}

BusinessConsultationStatus _consultationStatusFromDatabase(Object? value) {
  return switch (_normalizedEnum(value)) {
    'pending' => BusinessConsultationStatus.pending,
    'answered' => BusinessConsultationStatus.answered,
    'assigned' => BusinessConsultationStatus.assigned,
    'replied' => BusinessConsultationStatus.replied,
    _ => BusinessConsultationStatus.unknown,
  };
}

BusinessMessageSender _messageSenderFromDatabase(Object? value) {
  return switch (_normalizedEnum(value)) {
    'user' => BusinessMessageSender.member,
    'trainer' => BusinessMessageSender.trainer,
    'gym' => BusinessMessageSender.gym,
    _ => BusinessMessageSender.unknown,
  };
}

BusinessRoutineStatus _routineStatusFromDatabase(Object? value) {
  return switch (_normalizedEnum(value)) {
    'draft' => BusinessRoutineStatus.draft,
    'review' => BusinessRoutineStatus.review,
    'approved' => BusinessRoutineStatus.approved,
    'rejected' => BusinessRoutineStatus.rejected,
    _ => BusinessRoutineStatus.unknown,
  };
}

BusinessRoutineDifficulty _routineDifficultyFromDatabase(Object? value) {
  return switch (_normalizedEnum(value)) {
    'beginner' => BusinessRoutineDifficulty.beginner,
    'intermediate' => BusinessRoutineDifficulty.intermediate,
    'advanced' => BusinessRoutineDifficulty.advanced,
    _ => BusinessRoutineDifficulty.unknown,
  };
}

RoutineShareStatus _routineShareStatusFromDatabase(Object? value) {
  return switch (_normalizedEnum(value)) {
    'pending' => RoutineShareStatus.pending,
    'accepted' => RoutineShareStatus.accepted,
    'declined' => RoutineShareStatus.declined,
    'revoked' => RoutineShareStatus.revoked,
    'expired' => RoutineShareStatus.expired,
    _ => RoutineShareStatus.unknown,
  };
}

RoutineShareKind _routineShareKindFromDatabase(Object? value) {
  return switch (_normalizedEnum(value)) {
    'direct' => RoutineShareKind.direct,
    'link' => RoutineShareKind.link,
    _ => RoutineShareKind.unknown,
  };
}

BusinessInviteKind _businessInviteKindFromDatabase(Object? value) {
  return switch (_normalizedEnum(value)) {
    'member' => BusinessInviteKind.member,
    'trainer' => BusinessInviteKind.trainer,
    _ => BusinessInviteKind.unknown,
  };
}

BusinessInviteStatus _businessInviteStatusFromDatabase(Object? value) {
  return switch (_normalizedEnum(value)) {
    'pending' => BusinessInviteStatus.pending,
    'accepted' => BusinessInviteStatus.accepted,
    'revoked' => BusinessInviteStatus.revoked,
    'expired' => BusinessInviteStatus.expired,
    _ => BusinessInviteStatus.unknown,
  };
}

String _normalizedEnum(Object? value) {
  return value?.toString().trim().toLowerCase() ?? '';
}

Map<String, dynamic>? _mapValue(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is List && value.isNotEmpty && value.first is Map) {
    return Map<String, dynamic>.from(value.first as Map);
  }
  return null;
}

List<Map<String, dynamic>> _mapListValue(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
}

String _requiredUuid(Map<String, dynamic> row, String key) {
  final value = _nullableString(row[key]);
  if (value == null || !_uuidPattern.hasMatch(value)) {
    throw FormatException('Missing or invalid required UUID: $key');
  }
  return value;
}

String _validatedUuid(String value, String name) {
  final normalized = value.trim();
  if (!_uuidPattern.hasMatch(normalized)) {
    throw ArgumentError.value(value, name, 'Must be a UUID.');
  }
  return normalized;
}

String? _validatedOptionalUuid(String? value, String name) {
  if (value == null || value.trim().isEmpty) return null;
  return _validatedUuid(value, name);
}

String _dateOnly(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

String _timeOnly(int minutes) {
  final hour = (minutes ~/ 60).toString().padLeft(2, '0');
  final minute = (minutes % 60).toString().padLeft(2, '0');
  return '$hour:$minute:00';
}

int _timeMinutes(Object? value, String name) {
  final normalized = _nullableString(value);
  final parts = normalized?.split(':');
  if (parts == null || parts.length < 2) {
    throw FormatException('Missing or invalid schedule time: $name');
  }
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    throw FormatException('Missing or invalid schedule time: $name');
  }
  return hour * 60 + minute;
}

void _validateScheduleMinutes(int startMinutes, int endMinutes) {
  if (startMinutes < 0 || startMinutes >= 24 * 60) {
    throw ArgumentError.value(
      startMinutes,
      'startMinutes',
      'Must be within one day.',
    );
  }
  if (endMinutes <= startMinutes || endMinutes > 24 * 60) {
    throw ArgumentError.value(
      endMinutes,
      'endMinutes',
      'Must be after startMinutes.',
    );
  }
}

List<TrainerApplicationDocumentInput> _validatedTrainerApplicationDocuments(
  List<TrainerApplicationDocumentInput> documents,
) {
  if (documents.length < 2 || documents.length > 4) {
    throw ArgumentError.value(
      documents,
      'documents',
      'Between 2 and 4 documents are required.',
    );
  }
  final types = documents.map((item) => item.type).toSet();
  if (types.length != documents.length ||
      !types.contains(TrainerApplicationDocumentType.identity) ||
      !types.any(
        (type) =>
            type == TrainerApplicationDocumentType.nationalCertificate ||
            type == TrainerApplicationDocumentType.privateCertificate,
      )) {
    throw ArgumentError.value(
      documents,
      'documents',
      'Identity and one unique certification document are required.',
    );
  }
  for (final document in documents) {
    if (document.bytes.isEmpty ||
        document.bytes.length >
            UserImagePolicy.trainerDocument.maxSourceBytes) {
      throw ArgumentError.value(
        document.fileName,
        'documents',
        'Every document must be a supported image between 1 byte and 32 MB.',
      );
    }
  }
  return List.unmodifiable(documents);
}

String _trainerDocumentExtension(String contentType) => switch (contentType) {
  'image/png' => 'png',
  'image/webp' => 'webp',
  _ => 'jpg',
};

String _newRepositoryUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

String? _nullableUuid(Object? value) {
  final normalized = _nullableString(value);
  if (normalized == null || !_uuidPattern.hasMatch(normalized)) return null;
  return normalized;
}

String? _uuidFromRpc(Object? value) {
  final direct = _nullableUuid(value);
  if (direct != null) return direct;
  if (value is List) {
    for (final item in value) {
      final found = _uuidFromRpc(item);
      if (found != null) return found;
    }
    return null;
  }
  final row = _mapValue(value);
  if (row == null) return null;
  for (final key in const [
    'id',
    'application_id',
    'assignment_id',
    'consultation_id',
    'routine_id',
    'profile_id',
  ]) {
    final found = _nullableUuid(row[key]);
    if (found != null) return found;
  }
  for (final nested in row.values) {
    final found = _uuidFromRpc(nested);
    if (found != null) return found;
  }
  return null;
}

String _requiredTrimmed(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'Cannot be empty.');
  }
  return normalized;
}

String? _boundedOptionalText(String? value, String name, int maxLength) {
  final normalized = _nullableString(value);
  if (normalized == null) return null;
  if (normalized.length > maxLength) {
    throw ArgumentError.value(
      value,
      name,
      'Must be at most $maxLength characters.',
    );
  }
  return normalized;
}

String _stringValue(Object? value, {String fallback = ''}) {
  return _nullableString(value) ?? fallback;
}

String? _nullableString(Object? value) {
  if (value == null) return null;
  final normalized = value.toString().trim();
  return normalized.isEmpty ? null : normalized;
}

int _intValue(Object? value) => _nullableInt(value) ?? 0;

int? _nullableInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString().trim() ?? '') ??
      num.tryParse(value?.toString().trim() ?? '')?.toInt();
}

double _doubleValue(Object? value) => _nullableDouble(value) ?? 0;

double? _nullableDouble(Object? value) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString().trim() ?? '');
  return parsed != null && parsed.isFinite ? parsed : null;
}

bool _boolValue(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return switch (value?.toString().trim().toLowerCase()) {
    'true' || 't' || '1' || 'yes' => true,
    _ => false,
  };
}

DateTime? _nullableDateTime(Object? value) {
  if (value is DateTime) return value;
  final normalized = _nullableString(value);
  return normalized == null ? null : DateTime.tryParse(normalized);
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

final RegExp _inviteTokenPattern = RegExp(r'^[0-9a-f]{64}$');
