import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';

void main() {
  test('new member question reopens a previously answered consultation', () {
    final live = AppState(businessRepository: _Repository());
    addTearDown(live.dispose);
    live.businessWorkspace = _workspace(_thread([_reply]));
    expect(live.isBusinessConsultationAnswered(UserRole.trainer, 0), isTrue);

    live.applyConsultationChatUpdate(_thread([_reply, _followUp]));

    expect(live.isBusinessConsultationAnswered(UserRole.trainer, 0), isFalse);
    expect(live.businessWorkspace!.profile, same(_profile));
    expect(live.businessWorkspace!.access, same(_access));
    expect(live.businessWorkspace!.dashboardStats, same(_metrics));
  });

  test(
    'late pre-send response cannot erase the sent message in either list',
    () {
      final state = AppState(businessRepository: _Repository());
      addTearDown(state.dispose);
      state.memberConsultations = [
        _thread([_reply]),
      ];
      state.businessWorkspace = _workspace(_thread([_reply]));

      state.applyConsultationChatUpdate(_thread([_reply, _followUp]));
      state.applyConsultationChatUpdate(_thread([_reply]));

      expect(state.memberConsultations.single.messages.last.id, _followUp.id);
      expect(state.businessConsultations.single.messages.last.id, _followUp.id);
      expect(state.consultations.single.response, _reply.text);
      expect(state.consultations.single.status, ConsultationStatus.waiting);
    },
  );

  test(
    'a thread opened from a push does not enter unrelated account lists',
    () {
      final state = AppState(businessRepository: _Repository());
      addTearDown(state.dispose);
      state.memberConsultations = const [];
      state.applyConsultationChatUpdate(_thread([_reply]));
      expect(state.memberConsultations, isEmpty);
      expect(state.businessConsultations, isEmpty);
    },
  );
}

const _reply = BusinessConsultationMessage(
  id: 'reply',
  consultationId: 'thread',
  sender: BusinessMessageSender.trainer,
  text: '네, 가벼운 무게로 시작해주세요.',
);
const _followUp = BusinessConsultationMessage(
  id: 'follow-up',
  consultationId: 'thread',
  sender: BusinessMessageSender.member,
  text: '몇 세트 할까요?',
);
const _profile = TrainerBusinessProfile(
  id: 'trainer',
  userId: 'trainer-user',
  displayName: '담당 트레이너',
  status: BusinessProfileStatus.approved,
  isPublic: true,
  verified: true,
  rating: 0,
  postCount: 0,
  coachingTotal: 0,
);
const _access = BusinessAccess(
  userId: 'trainer-user',
  accountRole: UserRole.trainer,
  resolvedRole: UserRole.trainer,
  availableRoles: {UserRole.member, UserRole.trainer},
  trainer: _profile,
);
const _metrics = BusinessDashboardMetrics();

BusinessConsultation _thread(List<BusinessConsultationMessage> messages) =>
    BusinessConsultation(
      id: 'thread',
      userId: 'member',
      status: messages.last.sender == BusinessMessageSender.member
          ? BusinessConsultationStatus.pending
          : BusinessConsultationStatus.replied,
      isRead: false,
      messages: messages,
    );

BusinessWorkspaceData _workspace(BusinessConsultation consultation) =>
    BusinessWorkspaceData(
      role: UserRole.trainer,
      access: _access,
      profile: _profile,
      dashboardStats: _metrics,
      consultations: [consultation],
    );

class _Repository implements BusinessRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
