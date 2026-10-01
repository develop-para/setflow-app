import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/business_repository.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../theme/icons.dart';
import 'coaching_workout_screens.dart' show CoachingAccountBoundary;

/// 상담 신청에서 시작한 대화를 회원과 담당자가 같은 화면에서 이어간다.
class ConsultationChatScreen extends StatelessWidget {
  const ConsultationChatScreen({
    required this.consultationId,
    required this.role,
    this.initialConsultation,
    this.onShowDetails,
    this.repository,
    this.viewerUserId,
    super.key,
  });

  final String consultationId;
  final UserRole role;
  final BusinessConsultation? initialConsultation;
  final VoidCallback? onShowDetails;
  final ConsultationChatRepository? repository;
  final String? viewerUserId;

  @override
  Widget build(BuildContext context) =>
      CoachingAccountBoundary(child: _ChatPage(screen: this));
}

class _ChatPage extends StatefulWidget {
  const _ChatPage({required this.screen});
  final ConsultationChatScreen screen;

  @override
  State<_ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<_ChatPage> with WidgetsBindingObserver {
  final _draft = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<BusinessConsultation>? _messagesSubscription;
  StreamSubscription<AuthChange>? _authSubscription;
  ConsultationChatRepository? _repository;
  BusinessConsultation? _consultation;
  String? _viewerId;
  String? _requestId;
  String? _requestText;
  String? _loadError;
  String? _sendError;
  bool _started = false;
  bool _loading = true;
  bool _verified = false;
  bool _sending = false;
  bool _denied = false;
  bool _hasNewMessages = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _draft.addListener(_draftChanged);
    _scroll.addListener(_scrollChanged);
    _authSubscription = Auth.instance.authChanges.listen((change) {
      if (change.event == AuthEvent.signedOut ||
          (_viewerId != null && change.user?.id != _viewerId)) {
        _denyAccess();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final state = AppScope.of(context);
    _viewerId =
        widget.screen.viewerUserId ??
        Auth.instance.currentUser?.id ??
        state.businessAccess?.userId;
    final repository = state.businessRepository;
    _repository =
        widget.screen.repository ??
        (repository is ConsultationChatRepository
            ? repository as ConsultationChatRepository
            : null);
    _consultation = widget.screen.initialConsultation;
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_denied) _connect();
  }

  @override
  void didChangeMetrics() {
    // Keep the newest reply above the keyboard without pulling someone away
    // from older messages they are reading.
    if (!_denied && _atLatest) _showLatest();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_messagesSubscription?.cancel());
    unawaited(_authSubscription?.cancel());
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _draftChanged() {
    if (mounted) setState(() {});
  }

  void _scrollChanged() {
    if (_hasNewMessages && _atLatest) {
      setState(() => _hasNewMessages = false);
    }
  }

  bool get _atLatest =>
      !_scroll.hasClients || _scroll.position.extentAfter < 96;

  void _denyAccess() {
    if (!mounted || _denied) return;
    _generation++;
    unawaited(_messagesSubscription?.cancel());
    _draft.clear();
    setState(() {
      _denied = true;
      _loading = false;
      _sending = false;
      _consultation = null;
      _loadError = null;
      _sendError = null;
      _requestId = null;
      _requestText = null;
    });
  }

  Future<void> _connect() async {
    if (!mounted || _denied) return;
    final generation = ++_generation;
    await _messagesSubscription?.cancel();
    if (!mounted || generation != _generation) return;
    setState(() {
      _loading = !_verified;
      _loadError = null;
    });
    try {
      final repository = _repository;
      if (repository == null) throw StateError('상담 채팅을 연결하지 못했어요.');
      final consultation = await repository.loadConsultation(
        widget.screen.consultationId,
      );
      if (!mounted || generation != _generation) return;
      _accept(consultation, scrollToLatest: !_verified);
      setState(() {
        _loading = false;
        _verified = true;
      });
      _messagesSubscription = repository
          .watchConsultation(widget.screen.consultationId)
          .listen(
            (value) {
              if (mounted && generation == _generation) _accept(value);
            },
            onError: (Object error) {
              if (!mounted || generation != _generation) return;
              _connectionError(error);
            },
            onDone: () {
              if (!mounted || generation != _generation || _denied) return;
              setState(() => _loadError = '대화 연결이 끊겼어요. 다시 연결해주세요.');
            },
          );
    } catch (error) {
      if (!mounted || generation != _generation) return;
      _connectionError(error);
    }
  }

  void _connectionError(Object error) {
    if (error is BusinessAccessDenied) {
      _denyAccess();
      return;
    }
    setState(() {
      _loading = false;
      _loadError = '대화를 불러오지 못했어요. 연결을 확인하고 다시 시도해주세요.';
    });
  }

  void _accept(BusinessConsultation value, {bool scrollToLatest = false}) {
    if (_denied || value.id != widget.screen.consultationId) return;
    final oldMessages = _consultation?.messages ?? const [];
    final followLatest = scrollToLatest || _atLatest;
    final byId = {
      for (final message in oldMessages) message.id: message,
      for (final message in value.messages) message.id: message,
    };
    final requestIds = <String>{};
    final messages =
        byId.values.where((message) {
          final requestId = message.requestId;
          return requestId == null ||
              requestIds.add(
                '${message.senderId ?? message.sender.name}:$requestId',
              );
        }).toList()..sort((a, b) {
          final time = (a.createdAt ?? DateTime(1970)).compareTo(
            b.createdAt ?? DateTime(1970),
          );
          return time == 0 ? a.id.compareTo(b.id) : time;
        });
    final hasAdded = messages.any(
      (message) => !oldMessages.any((old) => old.id == message.id),
    );
    final stale = oldMessages.any(
      (message) => !value.messages.any((newer) => newer.id == message.id),
    );
    final consultation = _withMessages(
      stale ? _consultation! : value,
      messages,
    );
    setState(() {
      _consultation = consultation;
      _loadError = null;
      if (hasAdded && !followLatest) _hasNewMessages = true;
    });
    AppScope.of(context).applyConsultationChatUpdate(consultation);
    if (followLatest) _showLatest();
  }

  void _showLatest() {
    if (mounted) setState(() => _hasNewMessages = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final text = _draft.text.trim();
    if (_sending ||
        !_verified ||
        _denied ||
        text.isEmpty ||
        text.length > 4000) {
      return;
    }
    final repository = _repository;
    if (repository == null || _consultation == null) return;
    // A timed-out request may already be stored. Retrying the same draft uses
    // the same key so a second tap cannot create a second message.
    if (_requestText != text) {
      _requestText = text;
      _requestId = _newRequestId();
    }
    final requestId = _requestId!;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      final result = await repository.sendConsultationMessage(
        SendConsultationMessageInput(
          consultationId: widget.screen.consultationId,
          text: text,
          requestId: requestId,
        ),
      );
      if (!mounted || _denied) return;
      _accept(result, scrollToLatest: true);
      if (_draft.text.trim() == text) _draft.clear();
      _requestId = null;
      _requestText = null;
    } catch (error) {
      if (!mounted || _denied) return;
      if (error is BusinessAccessDenied) {
        _denyAccess();
      } else {
        setState(() {
          _sendError = '전송을 확인하지 못했어요. 내용은 남아 있으니 다시 전송해주세요.';
        });
      }
    } finally {
      if (mounted && !_denied) setState(() => _sending = false);
    }
  }

  bool _isMine(BusinessConsultationMessage message) {
    if (_viewerId != null && message.senderId != null) {
      return message.senderId == _viewerId;
    }
    return message.sender ==
        switch (widget.screen.role) {
          UserRole.trainer => BusinessMessageSender.trainer,
          UserRole.gym => BusinessMessageSender.gym,
          _ => BusinessMessageSender.member,
        };
  }

  String _senderName(BusinessConsultationMessage message) =>
      switch (message.sender) {
        BusinessMessageSender.member => _consultation?.memberName ?? '회원',
        BusinessMessageSender.trainer => _consultation?.trainerName ?? '트레이너',
        BusinessMessageSender.gym => _consultation?.gymName ?? '헬스장',
        BusinessMessageSender.unknown => '상담 담당자',
      };

  @override
  Widget build(BuildContext context) {
    final consultation = _verified ? _consultation : null;
    final title = widget.screen.role == UserRole.member
        ? consultation?.trainerName ?? consultation?.gymName ?? '상담 채팅'
        : consultation?.memberName ?? '상담 채팅';
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.screen.onShowDetails != null && _verified && !_denied)
            IconButton(
              tooltip: '상담 정보 보기',
              onPressed: widget.screen.onShowDetails,
              icon: const Icon(SetflowIcons.guide),
            ),
        ],
      ),
      body: SafeArea(
        child: _denied
            ? ListView(
                padding: SetflowInsets.pageForm,
                children: const [
                  Text('상담에 접근할 수 없어요. 현재 계정의 상담 목록에서 다시 확인해주세요.'),
                ],
              )
            : _chatBody(context),
      ),
    );
  }

  Widget _chatBody(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final inputStyle = theme.textTheme.bodyLarge;
      final line = TextPainter(
        text: TextSpan(text: '한', style: inputStyle),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
      )..layout();
      final inputPadding = theme.inputDecorationTheme.contentPadding?.resolve(
        Directionality.of(context),
      );
      final availableForLines =
          constraints.maxHeight * .45 -
          SetflowInsets.bottomAction.vertical -
          (inputPadding?.vertical ?? SetflowSpacing.xxl);
      final maxLines = (availableForLines / line.preferredLineHeight)
          .floor()
          .clamp(1, 4);
      line.dispose();
      return Column(
        children: [
          if (_loadError != null || _sendError != null)
            Flexible(
              fit: FlexFit.loose,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * .35,
                ),
                child: SingleChildScrollView(
                  key: const ValueKey('consultation-chat-notices'),
                  padding: SetflowInsets.pageHeader,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_loadError != null) ...[
                        Text(
                          _loadError!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: context.setflowColors.error,
                          ),
                        ),
                        TextButton(
                          key: const ValueKey('consultation-chat-retry'),
                          onPressed: _connect,
                          child: const Text('다시 연결'),
                        ),
                      ],
                      if (_sendError != null)
                        Text(
                          _sendError!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: context.setflowColors.error,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _verified
                ? _conversation(context)
                : const SizedBox.shrink(),
          ),
          if (_hasNewMessages)
            TextButton(
              key: const ValueKey('consultation-chat-new-messages'),
              onPressed: _showLatest,
              child: const Text('새 메시지 보기'),
            ),
          if (_verified && _consultation != null)
            _composer(context, maxLines: maxLines, style: inputStyle),
        ],
      );
    },
  );

  Widget _conversation(BuildContext context) {
    final consultation = _consultation;
    if (consultation == null) return const SizedBox.shrink();
    final question = consultation.question?.trim();
    final initialQuestionAlreadyStored = consultation.messages.any(
      (message) =>
          message.sender == BusinessMessageSender.member &&
          message.text.trim() == question &&
          message.createdAt != null &&
          consultation.createdAt != null &&
          message.createdAt == consultation.createdAt,
    );
    final messages = [
      if (question != null &&
          question.isNotEmpty &&
          !initialQuestionAlreadyStored)
        BusinessConsultationMessage(
          id: 'initial-question',
          consultationId: consultation.id,
          sender: BusinessMessageSender.member,
          senderId: consultation.userId,
          text: question,
          createdAt: consultation.createdAt,
        ),
      ...consultation.messages,
    ];
    return ListView.builder(
      key: const ValueKey('consultation-chat-messages'),
      controller: _scroll,
      padding: SetflowInsets.pageForm,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final date = message.createdAt?.toLocal();
        final previousDate = index == 0
            ? null
            : messages[index - 1].createdAt?.toLocal();
        final showDate =
            date != null &&
            (previousDate == null || !_sameDay(date, previousDate));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showDate)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: SetflowSpacing.md,
                ),
                child: Text(
                  '${date.year}년 ${date.month}월 ${date.day}일',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            _MessageBubble(
              message: message,
              mine: _isMine(message),
              senderName: _senderName(message),
            ),
          ],
        );
      },
    );
  }

  Widget _composer(
    BuildContext context, {
    required int maxLines,
    required TextStyle? style,
  }) => Padding(
    key: const ValueKey('consultation-chat-composer'),
    padding: SetflowInsets.bottomAction,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('consultation-chat-draft'),
            controller: _draft,
            enabled: _verified && !_sending,
            minLines: 1,
            maxLines: maxLines,
            style: style,
            maxLength: 4000,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText: '메시지 입력',
              counterText: '',
            ),
          ),
        ),
        const SizedBox(width: SetflowSpacing.sm),
        FilledButton(
          key: const ValueKey('consultation-chat-send'),
          onPressed: !_verified || _sending || _draft.text.trim().isEmpty
              ? null
              : _send,
          child: Text(_sending ? '전송 중' : '전송'),
        ),
      ],
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.senderName,
  });
  final BusinessConsultationMessage message;
  final bool mine;
  final String senderName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = message.createdAt?.toLocal();
    final time = date == null
        ? null
        : '${date.hour.toString().padLeft(2, '0')}:'
              '${date.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: .86,
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: SetflowSpacing.md),
          child: Column(
            crossAxisAlignment: mine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (!mine) ...[
                Text(senderName, style: theme.textTheme.labelMedium),
                const SizedBox(height: SetflowSpacing.xs),
              ],
              Container(
                key: ValueKey('consultation-chat-bubble-${message.id}'),
                padding: const EdgeInsets.symmetric(
                  horizontal: SetflowSpacing.md,
                  vertical: SetflowSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: mine
                      ? theme.colorScheme.primary
                      : context.setflowColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(SetflowRadii.md),
                ),
                child: Text(
                  message.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: mine
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (time != null) ...[
                const SizedBox(height: SetflowSpacing.xs),
                Text(time, style: theme.textTheme.labelSmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _newRequestId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

BusinessConsultation _withMessages(
  BusinessConsultation value,
  List<BusinessConsultationMessage> messages,
) => BusinessConsultation(
  id: value.id,
  userId: value.userId,
  status: value.status,
  isRead: value.isRead,
  messages: messages,
  mode: value.mode,
  matchingSource: value.matchingSource,
  requestedRegionCode: value.requestedRegionCode,
  trainerId: value.trainerId,
  gymId: value.gymId,
  routineId: value.routineId,
  assignedTrainerId: value.assignedTrainerId,
  memberName: value.memberName,
  memberAvatarUrl: value.memberAvatarUrl,
  trainerName: value.trainerName,
  gymName: value.gymName,
  specialty: value.specialty,
  goal: value.goal,
  level: value.level,
  question: value.question,
  createdAt: value.createdAt,
  sharedRecommendationProfile: value.sharedRecommendationProfile,
  recommendationProfileSharedAt: value.recommendationProfileSharedAt,
  recommendationProfileShareRevokedAt:
      value.recommendationProfileShareRevokedAt,
);
