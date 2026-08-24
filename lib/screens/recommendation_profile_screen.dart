import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/recommendation_profile_summary.dart';

final _precisionSurveyPromptInFlight = <AppState, Future<void>>{};

Future<void> ensurePrecisionRecommendationSurvey(BuildContext context) {
  final state = AppScope.of(context);
  if (state.precisionRecommendationPrompted) return Future<void>.value();
  final active = _precisionSurveyPromptInFlight[state];
  if (active != null) return active;
  late final Future<void> operation;
  operation = _ensurePrecisionRecommendationSurvey(context, state).whenComplete(
    () {
      if (identical(_precisionSurveyPromptInFlight[state], operation)) {
        _precisionSurveyPromptInFlight.remove(state);
      }
    },
  );
  _precisionSurveyPromptInFlight[state] = operation;
  return operation;
}

Future<void> _ensurePrecisionRecommendationSurvey(
  BuildContext context,
  AppState state,
) async {
  final wantsSurvey = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        // 한글은 어절 단위로 안 끊긴다 — Flutter가 글자 사이 어디서든 줄을 바꿔서
        // 긴 제목은 '싶다 / 면?' 처럼 낱말 가운데가 갈린다. 제목은 한 줄에 들어갈
        // 길이로 쓰고 나머지는 본문으로 내린다.
        title: const Text('추천을 더 정확하게'),
        content: const Text(
          '부상·통증, 사용 장비, 숙련도와 오늘의 회복 상태를 1분만 알려주시면 '
          '피하고 싶은 동작을 추천에서 빼드려요.\n\n'
          '지금 넘어가도 기존 추천은 그대로 씁니다.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('precision-survey-skip'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('기본 추천 받기'),
          ),
          FilledButton(
            key: const ValueKey('precision-survey-start'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('정보 입력'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || wantsSurvey == null) return;
  state.markPrecisionRecommendationPrompted();
  try {
    await state.flushPersistence();
  } catch (_) {
    if (context.mounted) {
      AppSnackbar.info(context, '제안 선택을 저장하지 못했어요. 연결되면 다시 시도합니다.');
    }
  }
  unawaited(state.syncPersistenceToServer().catchError((_) {}));
  if (!wantsSurvey || !context.mounted) return;
  await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => const RecommendationProfileScreen()),
  );
}

class RecommendationProfileScreen extends StatefulWidget {
  const RecommendationProfileScreen({super.key});

  @override
  State<RecommendationProfileScreen> createState() =>
      _RecommendationProfileScreenState();
}

class _RecommendationProfileScreenState
    extends State<RecommendationProfileScreen> {
  final injuryNoteController = TextEditingController();
  bool initialized = false;
  bool isSaving = false;
  RecommendationProfile? initialProfile;
  bool recoveryAnsweredForToday = false;
  late TrainingExperienceLevel experienceLevel;
  late Set<TrainingEquipment> availableEquipment;
  late Set<TrainingPainRegion> painRegions;
  late double painLevel;
  late Set<TrainingMovementRestriction> restrictedMovements;
  late TrainingRecoveryStatus recoveryStatus;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialized) return;
    final profile = AppScope.of(context).recommendationProfile;
    initialProfile = profile;
    final hasCurrentRecovery = profile?.hasRecoveryFor(DateTime.now()) ?? false;
    experienceLevel =
        profile?.experienceLevel ?? TrainingExperienceLevel.beginner;
    availableEquipment = profile == null
        ? {TrainingEquipment.bodyweight}
        : Set.of(profile.availableEquipment);
    painRegions = Set.of(profile?.painRegions ?? const {});
    painLevel = (profile?.painLevel ?? 0).toDouble();
    restrictedMovements = Set.of(profile?.restrictedMovements ?? const {});
    recoveryStatus = hasCurrentRecovery
        ? profile!.recoveryStatus
        : TrainingRecoveryStatus.normal;
    recoveryAnsweredForToday = profile == null || hasCurrentRecovery;
    injuryNoteController.text = profile?.injuryNote ?? '';
    initialized = true;
  }

  @override
  void dispose() {
    injuryNoteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (availableEquipment.isEmpty) {
      AppSnackbar.info(context, '사용할 수 있는 장비를 하나 이상 선택해주세요.');
      return;
    }
    if (isSaving) return;
    setState(() => isSaving = true);
    final now = DateTime.now().toUtc();
    final previousProfile = initialProfile;
    final recordsRecoveryNow =
        previousProfile == null || recoveryAnsweredForToday;
    final profile = RecommendationProfile(
      experienceLevel: experienceLevel,
      availableEquipment: availableEquipment,
      painRegions: painRegions,
      painLevel: painRegions.isEmpty ? 0 : painLevel.round(),
      restrictedMovements: restrictedMovements,
      injuryNote: injuryNoteController.text,
      recoveryStatus: recordsRecoveryNow
          ? recoveryStatus
          : previousProfile.recoveryStatus,
      recoveryRecordedAt: recordsRecoveryNow
          ? now
          : previousProfile.recoveryRecordedAt,
      updatedAt: now,
    );
    final state = AppScope.of(context);
    state.setRecommendationProfile(profile);
    try {
      await state.syncPersistenceToServer();
      if (!mounted) return;
      AppSnackbar.success(context, '정밀 추천 정보를 계정에 저장했어요.');
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      if (state.persistenceError != null) {
        setState(() => isSaving = false);
        AppSnackbar.error(context, '정보를 기기에 저장하지 못했어요. 다시 시도해주세요.');
        return;
      }
      AppSnackbar.info(context, '기기에 저장했어요. 클라우드는 연결되는 즉시 다시 동기화합니다.');
      Navigator.pop(context, true);
    }
  }

  Future<void> _deleteProfile() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('정밀 추천 정보를 삭제할까요?'),
            content: const Text(
              '계정에 저장된 설문 답변을 삭제합니다. 이미 상담에 동의해 첨부한 사본은 상담 기록에서 별도로 관리됩니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소'),
              ),
              FilledButton(
                key: const ValueKey('recommendation-profile-delete-confirm'),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('삭제'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    final state = AppScope.of(context);
    state.clearRecommendationProfile();
    try {
      await state.syncPersistenceToServer();
      if (!mounted) return;
      AppSnackbar.success(context, '정밀 추천 정보를 삭제했어요.');
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      AppSnackbar.info(context, '기기에서 삭제했어요. 클라우드는 연결되는 즉시 동기화합니다.');
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!initialized) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(
        title: const Text('정밀 운동 추천 설문'),
        actions: [
          if (initialProfile != null)
            IconButton(
              key: const ValueKey('recommendation-profile-delete'),
              tooltip: '정밀 추천 정보 삭제',
              onPressed: isSaving ? null : _deleteProfile,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
        children: [
          const Text(
            '내 상황에 맞지 않는 운동을\n먼저 걸러낼게요.',
            style: TextStyle(
              fontSize: SetflowFontSize.headlineLarge,
              height: 1.25,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: SetflowSpacing.sm2),
          Text(
            '답변은 계정에 저장되며 언제든 수정할 수 있습니다. 통증 부위만으로 진단하지 않고, 직접 선택한 제외 동작만 추천에서 뺍니다.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: SetflowSpacing.xxl),
          _SurveySection(
            title: '1. 운동 숙련도',
            subtitle: '동작 난이도와 종목 후보를 조정합니다.',
            child: RadioGroup<TrainingExperienceLevel>(
              groupValue: experienceLevel,
              onChanged: isSaving
                  ? (_) {}
                  : (value) {
                      if (value != null) {
                        setState(() => experienceLevel = value);
                      }
                    },
              child: Column(
                children: [
                  for (final level in TrainingExperienceLevel.values)
                    RadioListTile<TrainingExperienceLevel>(
                      key: ValueKey('experience-${level.name}'),
                      value: level,
                      contentPadding: EdgeInsets.zero,
                      title: Text(level.label),
                      enabled: !isSaving,
                    ),
                ],
              ),
            ),
          ),
          _SurveySection(
            title: '2. 사용할 수 있는 장비',
            subtitle: '자동 추천에서 사용할 수 있는 장비를 모두 선택하세요. 설정에서 언제든 바꿀 수 있습니다.',
            trailing: TextButton(
              onPressed: isSaving
                  ? null
                  : () => setState(
                      () =>
                          availableEquipment = Set.of(TrainingEquipment.values),
                    ),
              child: const Text('전체 선택'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 7,
                  children: [
                    for (final equipment in TrainingEquipment.values)
                      FilterChip(
                        key: ValueKey('equipment-${equipment.name}'),
                        label: Text(equipment.label),
                        selected: availableEquipment.contains(equipment),
                        onSelected: isSaving
                            ? null
                            : (selected) => setState(() {
                                if (selected) {
                                  availableEquipment.add(equipment);
                                } else {
                                  availableEquipment.remove(equipment);
                                }
                              }),
                      ),
                  ],
                ),
                const SizedBox(height: SetflowSpacing.sm2),
                Text(
                  '일반 웨이트 머신은 머신 구역 전체를 뜻합니다. 직접 만든 운동은 안전 태그가 없어 자동 추천 후보에서 제외됩니다.',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          _SurveySection(
            title: '3. 현재 통증 또는 최근 부상',
            subtitle: '해당 부위를 모두 선택하세요. 이 정보만으로 운동을 진단하지 않습니다.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 7,
                  children: [
                    for (final region in TrainingPainRegion.values)
                      FilterChip(
                        key: ValueKey('pain-${region.name}'),
                        label: Text(region.label),
                        selected: painRegions.contains(region),
                        onSelected: isSaving
                            ? null
                            : (selected) => setState(() {
                                if (selected) {
                                  painRegions.add(region);
                                } else {
                                  painRegions.remove(region);
                                  if (painRegions.isEmpty) painLevel = 0;
                                }
                              }),
                      ),
                  ],
                ),
                if (painRegions.isNotEmpty) ...[
                  const SizedBox(height: SetflowSpacing.lg),
                  Text(
                    '현재 통증 정도 · ${painLevel.round()}/10',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Slider(
                    key: const ValueKey('pain-level-slider'),
                    value: painLevel,
                    min: 0,
                    max: 10,
                    divisions: 10,
                    label: '${painLevel.round()}',
                    onChanged: isSaving
                        ? null
                        : (value) => setState(() => painLevel = value),
                  ),
                ],
                const SizedBox(height: SetflowSpacing.sm2),
                AppTextField(
                  key: const ValueKey('injury-note'),
                  controller: injuryNoteController,
                  label: '부상 · 통증 메모 (선택)',
                  hint: '예: 오른쪽 어깨를 올릴 때 불편함, 치료 중인 부상 등',
                  helperText: '진단명 대신 추천에 참고할 사실만 적어주세요. 최대 500자',
                  minLines: 2,
                  maxLines: 4,
                  inputFormatters: [LengthLimitingTextInputFormatter(500)],
                ),
              ],
            ),
          ),
          _SurveySection(
            title: '4. 피해야 할 동작',
            subtitle: '전문가에게 피하라고 안내받았거나 직접 불편한 동작만 선택하세요.',
            child: Wrap(
              spacing: 8,
              runSpacing: 7,
              children: [
                for (final movement in TrainingMovementRestriction.values)
                  FilterChip(
                    key: ValueKey('restriction-${movement.name}'),
                    label: Text(movement.label),
                    selected: restrictedMovements.contains(movement),
                    onSelected: isSaving
                        ? null
                        : (selected) => setState(() {
                            if (selected) {
                              restrictedMovements.add(movement);
                            } else {
                              restrictedMovements.remove(movement);
                            }
                          }),
                  ),
              ],
            ),
          ),
          _SurveySection(
            title: '5. 오늘의 회복 상태',
            subtitle: recoveryAnsweredForToday
                ? '회복 응답은 오늘 추천에만 사용하고 이후 날짜에는 자동 적용하지 않습니다.'
                : '오늘 상태를 다시 선택하지 않으면 이전 기록 날짜를 유지하며 오늘 추천에는 적용하지 않습니다.',
            child: RadioGroup<TrainingRecoveryStatus>(
              groupValue: recoveryStatus,
              onChanged: isSaving
                  ? (_) {}
                  : (value) {
                      if (value != null) {
                        setState(() {
                          recoveryStatus = value;
                          recoveryAnsweredForToday = true;
                        });
                      }
                    },
              child: Column(
                children: [
                  for (final status in TrainingRecoveryStatus.values)
                    RadioListTile<TrainingRecoveryStatus>(
                      key: ValueKey('recovery-${status.name}'),
                      value: status,
                      contentPadding: EdgeInsets.zero,
                      title: Text(status.label),
                      enabled: !isSaving,
                    ),
                ],
              ),
            ),
          ),
          if (painLevel >= 7) ...[
            const SizedBox(height: SetflowSpacing.xxs),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.setflowColors.error.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(SetflowRadii.md),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: context.setflowColors.error,
                  ),
                  SizedBox(width: SetflowSpacing.sm2),
                  Expanded(
                    child: Text(
                      '통증이 7/10 이상이면 자동 추천을 중단합니다. 통증이 심하거나 갑자기 생겼다면 의료 전문가의 평가를 먼저 받아주세요.',
                      style: TextStyle(
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(18),
        child: AppButton(
          key: const ValueKey('recommendation-profile-save'),
          label: '정밀 추천 정보 저장',
          icon: Icons.check_rounded,
          isLoading: isSaving,
          onPressed: isSaving ? null : _save,
        ),
      ),
    );
  }
}

class _SurveySection extends StatelessWidget {
  const _SurveySection({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SetflowCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: SetflowFontSize.title,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: SetflowSpacing.xs),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: SetflowSpacing.md2),
            child,
          ],
        ),
      ),
    );
  }
}

class RecommendationProfilePreviewCard extends StatelessWidget {
  const RecommendationProfilePreviewCard({required this.profile, super.key});

  final RecommendationProfile profile;

  @override
  Widget build(BuildContext context) {
    return SetflowCard(
      child: RecommendationProfileSummary(profile: profile, compact: true),
    );
  }
}
