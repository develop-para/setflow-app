import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/business_repository.dart';
import '../data/community_repository.dart';
import '../services/post_media_picker.dart';
import '../theme.dart';
import '../widgets/auth_gate.dart';
import '../widgets/common.dart';
import '../widgets/recommendation_profile_summary.dart';
import 'recommendation_profile_screen.dart';

typedef RoutineDraft = ({String name, String description});

class RoutineCreateSheet extends StatefulWidget {
  const RoutineCreateSheet({super.key});

  @override
  State<RoutineCreateSheet> createState() => _RoutineCreateSheetState();
}

class _RoutineCreateSheetState extends State<RoutineCreateSheet> {
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final descriptionController = TextEditingController();

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(formKey.currentState?.validate() ?? false)) return;
    Navigator.pop<RoutineDraft>(context, (
      name: nameController.text.trim(),
      description: descriptionController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardSafeBottomSheet(
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '새 루틴 만들기',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: SetflowSpacing.xl),
            AppTextField(
              controller: nameController,
              label: '루틴 이름',
              hint: '예: 월요일 상체 집중',
              textInputAction: TextInputAction.next,
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return '루틴 이름을 입력해주세요.';
                if (text.length < 2) return '루틴 이름을 2자 이상 입력해주세요.';
                return null;
              },
            ),
            const SizedBox(height: SetflowSpacing.md),
            AppTextField(
              controller: descriptionController,
              label: '설명',
              hint: '목표와 운동 구성을 간단히 설명해주세요.',
              minLines: 2,
              maxLines: 3,
              validator: (value) {
                if ((value?.trim().length ?? 0) < 5) {
                  return '설명을 5자 이상 입력해주세요.';
                }
                return null;
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: SetflowSpacing.xl),
            AppButton(label: '저장', onPressed: _submit),
          ],
        ),
      ),
    );
  }
}

class SocialPostComposerScreen extends StatefulWidget {
  const SocialPostComposerScreen({this.mediaPicker, super.key});

  final PostMediaPicker? mediaPicker;

  @override
  State<SocialPostComposerScreen> createState() =>
      _SocialPostComposerScreenState();
}

class _SocialPostComposerScreenState extends State<SocialPostComposerScreen> {
  final formKey = GlobalKey<FormState>();
  final contentController = TextEditingController();
  late final PostMediaPicker mediaPicker;
  CommunityPostMedia? selectedMedia;
  bool includeWorkout = true;
  bool isSubmitting = false;
  bool isSelectingMedia = false;
  String visualKey = 'strength';
  final overlays = <String>{'날짜', '시간', '완료 루틴'};

  @override
  void initState() {
    super.initState();
    mediaPicker = widget.mediaPicker ?? ImagePickerPostMediaPicker();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recoverLostMedia());
  }

  @override
  void dispose() {
    contentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    setState(() => isSubmitting = true);
    try {
      await AppScope.of(context).addCommunityPost(
        content: contentController.text.trim().isEmpty
            ? '오늘 운동 기록을 공유했습니다.'
            : contentController.text.trim(),
        includeWorkout: includeWorkout,
        visualKey: visualKey,
        media: selectedMedia,
        activeOverlays: overlays.toList(growable: false),
      );
      if (!mounted) return;
      HapticFeedback.lightImpact();
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => isSubmitting = false);
      AppSnackbar.error(context, _communityErrorMessage(error));
    }
  }

  Future<void> _recoverLostMedia() async {
    try {
      final media = await mediaPicker.recoverLostImage();
      if (media != null && mounted) setState(() => selectedMedia = media);
    } catch (error) {
      if (mounted) AppSnackbar.error(context, _mediaErrorMessage(error));
    }
  }

  Future<void> _pickMedia(PostMediaSource source) async {
    if (isSelectingMedia || isSubmitting) return;
    setState(() => isSelectingMedia = true);
    try {
      final media = await mediaPicker.pick(source);
      if (media != null && mounted) setState(() => selectedMedia = media);
    } catch (error) {
      if (mounted) AppSnackbar.error(context, _mediaErrorMessage(error));
    } finally {
      if (mounted) setState(() => isSelectingMedia = false);
    }
  }

  Future<void> _showMediaOptions() async {
    final source = await showModalBottomSheet<PostMediaSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                '사진 변경',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('카메라로 촬영'),
              onTap: () => Navigator.pop(sheetContext, PostMediaSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('갤러리에서 선택'),
              onTap: () => Navigator.pop(sheetContext, PostMediaSource.gallery),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: SetflowColors.red,
              ),
              title: const Text(
                '사진 삭제',
                style: TextStyle(color: SetflowColors.red),
              ),
              onTap: () {
                setState(() => selectedMedia = null);
                Navigator.pop(sheetContext);
              },
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pickMedia(source);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('새 글 쓰기'),
        actions: [
          TextButton(
            onPressed: isSubmitting ? null : _submit,
            child: const Text('게시'),
          ),
        ],
      ),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
          children: [
            _WorkoutVisualPreview(
              media: selectedMedia,
              isLoading: isSelectingMedia,
              visualKey: visualKey,
              overlays: overlays,
              onCamera: () => _pickMedia(PostMediaSource.camera),
              onGallery: () => _pickMedia(PostMediaSource.gallery),
              onChange: _showMediaOptions,
            ),
            const SizedBox(height: SetflowSpacing.xl),
            const SectionTitle('사진 스타일'),
            const SizedBox(height: SetflowSpacing.sm),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'strength',
                  icon: Icon(Icons.fitness_center_rounded),
                  label: Text('근력'),
                ),
                ButtonSegment(
                  value: 'streak',
                  icon: Icon(Icons.local_fire_department_rounded),
                  label: Text('연속'),
                ),
                ButtonSegment(
                  value: 'tip',
                  icon: Icon(Icons.lightbulb_rounded),
                  label: Text('팁'),
                ),
              ],
              selected: {visualKey},
              onSelectionChanged: (value) =>
                  setState(() => visualKey = value.single),
            ),
            const SizedBox(height: SetflowSpacing.xl),
            const SectionTitle('오버레이'),
            const SizedBox(height: SetflowSpacing.sm),
            Wrap(
              spacing: SetflowSpacing.sm,
              runSpacing: SetflowSpacing.sm,
              children: ['날짜', '시간', '완료 루틴']
                  .map(
                    (item) => FilterChip(
                      label: Text(item),
                      selected: overlays.contains(item),
                      onSelected: (selected) => setState(
                        () => selected
                            ? overlays.add(item)
                            : overlays.remove(item),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: SetflowSpacing.xl),
            AppTextField(
              controller: contentController,
              label: '오늘 운동 기록',
              hint: '오늘 운동은 어땠나요? 기분 좋은 변화를 기록해보세요.',
              minLines: 4,
              maxLines: 6,
              validator: (value) {
                if ((value?.trim().isEmpty ?? true) && selectedMedia == null) {
                  return '사진을 추가하거나 운동 기록을 입력해주세요.';
                }
                if ((value?.trim().length ?? 0) > 500) {
                  return '운동 기록은 500자 이내로 작성해주세요.';
                }
                return null;
              },
            ),
            const SizedBox(height: SetflowSpacing.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                '오늘 운동 기록 첨부',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(state.todayWorkoutMetric),
              value: includeWorkout,
              onChanged: (value) => setState(() => includeWorkout = value),
            ),
            const SizedBox(height: SetflowSpacing.xl),
            const SectionTitle('외부 공유'),
            const SizedBox(height: SetflowSpacing.sm),
            SizedBox(
              height: 76,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _ShareTarget(
                    icon: Icons.chat_bubble_rounded,
                    label: '카카오톡',
                    color: SetflowColors.primary,
                    onTap: () =>
                        AppSnackbar.info(context, '게시 후 카카오톡으로 공유할 수 있어요.'),
                  ),
                  _ShareTarget(
                    icon: Icons.ios_share_rounded,
                    label: '더보기',
                    color: context.setflowColors.info,
                    onTap: () =>
                        AppSnackbar.info(context, '게시 후 공유 메뉴를 열 수 있어요.'),
                  ),
                  _ShareTarget(
                    icon: Icons.download_rounded,
                    label: '저장',
                    color: SetflowColors.green,
                    onTap: () =>
                        AppSnackbar.info(context, '게시 후 이미지로 저장할 수 있어요.'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: SetflowSpacing.xl),
            AppButton(
              label: '게시하기',
              icon: Icons.send_rounded,
              isLoading: isSubmitting,
              onPressed: isSubmitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

String _mediaErrorMessage(Object error) {
  if (error is FormatException) return error.message.toString();
  if (error is PlatformException) {
    final code = error.code.toLowerCase();
    if (code.contains('camera_access_denied')) {
      return '카메라 권한이 필요해요. 기기 설정에서 Setflow의 카메라 접근을 허용해주세요.';
    }
    if (code.contains('photo_access_denied')) {
      return '사진 접근 권한이 필요해요. 기기 설정에서 사진 접근을 허용해주세요.';
    }
  }
  return '사진을 불러오지 못했어요. 잠시 후 다시 시도해주세요.';
}

String _communityErrorMessage(Object error) {
  if (error is CommunityValidationException) return error.message;
  if (error is CommunityAuthenticationRequired) return error.toString();
  return '게시물을 등록하지 못했어요. 네트워크를 확인한 뒤 다시 시도해주세요.';
}

class _WorkoutVisualPreview extends StatelessWidget {
  const _WorkoutVisualPreview({
    required this.media,
    required this.isLoading,
    required this.visualKey,
    required this.overlays,
    required this.onCamera,
    required this.onGallery,
    required this.onChange,
  });

  final CommunityPostMedia? media;
  final bool isLoading;
  final String visualKey;
  final Set<String> overlays;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    if (media == null) {
      return AspectRatio(
        aspectRatio: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.setflowColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(SetflowRadii.lg),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                const CircularProgressIndicator()
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _MediaButton(
                      icon: Icons.camera_alt_outlined,
                      label: '촬영',
                      onTap: onCamera,
                    ),
                    const SizedBox(width: SetflowSpacing.md),
                    _MediaButton(
                      icon: Icons.photo_library_outlined,
                      label: '갤러리',
                      onTap: onGallery,
                    ),
                  ],
                ),
              const SizedBox(height: SetflowSpacing.lg),
              const Text(
                '운동 결과 사진을 올려보세요.',
                style: TextStyle(
                  color: SetflowColors.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final color = switch (visualKey) {
      'streak' => SetflowColors.teal,
      'tip' => context.setflowColors.info,
      _ => SetflowColors.orange,
    };
    final icon = switch (visualKey) {
      'streak' => Icons.local_fire_department_rounded,
      'tip' => Icons.lightbulb_rounded,
      _ => Icons.fitness_center_rounded,
    };
    final now = DateTime.now();

    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SetflowRadii.lg),
        child: Material(
          color: color.withValues(alpha: .18),
          child: InkWell(
            onTap: onChange,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  media!.bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => ColoredBox(
                    color: color.withValues(alpha: .18),
                    child: Center(child: Icon(icon, size: 124, color: color)),
                  ),
                ),
                ColoredBox(color: Colors.black.withValues(alpha: .12)),
                if (overlays.contains('날짜'))
                  _PreviewLabel(
                    alignment: Alignment.topLeft,
                    text: '${now.month}월 ${now.day}일',
                  ),
                if (overlays.contains('시간'))
                  _PreviewLabel(
                    alignment: Alignment.topRight,
                    text: DateFormat('HH:mm').format(now),
                  ),
                if (overlays.contains('완료 루틴'))
                  const _PreviewLabel(
                    alignment: Alignment.bottomLeft,
                    text: '오늘 운동 완료',
                  ),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SetflowSpacing.md,
                      vertical: SetflowSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(SetflowRadii.md),
                    ),
                    child: const Text(
                      '사진 변경',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaButton extends StatelessWidget {
  const _MediaButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(SetflowRadii.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SetflowRadii.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewLabel extends StatelessWidget {
  const _PreviewLabel({required this.alignment, required this.text});

  final Alignment alignment;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.all(SetflowSpacing.md),
        padding: const EdgeInsets.symmetric(
          horizontal: SetflowSpacing.sm,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(SetflowRadii.sm),
        ),
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ShareTarget extends StatelessWidget {
  const _ShareTarget({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: SetflowSpacing.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SetflowRadii.md),
        child: SizedBox(
          width: 62,
          child: Column(
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ExpertRoutineDetailScreen extends StatelessWidget {
  const ExpertRoutineDetailScreen({required this.routine, super.key});

  final RoutineData routine;

  Future<void> _import(BuildContext context) async {
    RoutineImportResult result;
    try {
      result = await AppScope.of(context).importMarketRoutine(routine);
    } catch (_) {
      if (context.mounted) {
        AppSnackbar.error(context, '루틴을 저장하지 못했어요. 잠시 후 다시 시도해주세요.');
      }
      return;
    }
    if (!context.mounted) return;
    switch (result) {
      case RoutineImportResult.imported:
        HapticFeedback.lightImpact();
        AppSnackbar.success(context, '내 루틴에 저장했어요.');
      case RoutineImportResult.alreadySaved:
        AppSnackbar.info(context, '이미 내 루틴에 저장되어 있어요.');
      case RoutineImportResult.limitReached:
        AppSnackbar.error(context, '무료 플랜은 루틴을 4개까지 저장할 수 있어요.');
      case RoutineImportResult.paidPlanRequired:
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.workspace_premium_rounded),
            title: const Text('유료 플랜이 필요해요'),
            content: const Text(
              '이 루틴은 유료 회원 전용이에요. 결제 기능이 연결되면 이 화면에서 바로 업그레이드할 수 있습니다.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('확인'),
              ),
            ],
          ),
        );
    }
  }

  Future<void> _requestConsultation(BuildContext context) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ConsultationCreateScreen(
          initialTrainerId: routine.authorTrainerId,
          initialGymId: routine.authorGymId,
          initialTargetName: routine.author,
          routineId: routine.sourceCoachingRoutineId,
        ),
      ),
    );
    if (created == true && context.mounted) {
      AppSnackbar.success(context, '상담을 신청했어요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('전문가 루틴 상세'),
        actions: [
          IconButton(
            tooltip: '공유',
            onPressed: () => AppSnackbar.info(context, '공유 메뉴를 준비했어요.'),
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
        children: [
          Container(
            height: 210,
            decoration: BoxDecoration(
              color: routine.color.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(SetflowRadii.xl),
            ),
            child: Icon(
              Icons.fitness_center_rounded,
              size: 108,
              color: routine.color,
            ),
          ),
          const SizedBox(height: SetflowSpacing.xl),
          Wrap(
            spacing: SetflowSpacing.sm,
            runSpacing: SetflowSpacing.sm,
            children: [
              Chip(
                avatar: Icon(
                  routine.isPaid
                      ? Icons.workspace_premium_rounded
                      : Icons.lock_open_rounded,
                  size: 16,
                ),
                label: Text(routine.accessTier.label),
              ),
              Chip(label: Text('#${routine.level}')),
              if (routine.exercises.isNotEmpty)
                Chip(label: Text('#${routine.exercises.first.muscle}')),
              Chip(
                label: Text(
                  routine.exercises.every((exercise) => exercise.isCardio)
                      ? '#유산소'
                      : routine.exercises.any((exercise) => exercise.isCardio)
                      ? '#근력·유산소'
                      : '#근력',
                ),
              ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.md),
          Text(
            routine.name,
            style: const TextStyle(
              fontSize: 27,
              height: 1.2,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: SetflowSpacing.md),
          SetflowCard(
            child: Row(
              children: [
                Icon(Icons.person_rounded, color: routine.color),
                const SizedBox(width: SetflowSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              routine.author,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified_rounded,
                            size: 17,
                            color: SetflowColors.blue,
                          ),
                        ],
                      ),
                      const Text(
                        '전문 루틴 12개 · 코칭 340회',
                        style: TextStyle(
                          color: SetflowColors.secondaryText,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.lg),
          Text(
            routine.description,
            style: const TextStyle(
              color: SetflowColors.secondaryText,
              height: 1.6,
            ),
          ),
          const SizedBox(height: SetflowSpacing.lg),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: '상담 요청',
                  variant: AppButtonVariant.outlined,
                  onPressed: () => _requestConsultation(context),
                ),
              ),
              const SizedBox(width: SetflowSpacing.sm),
              Expanded(
                child: AppButton(
                  label: '코칭 문의',
                  variant: AppButtonVariant.tonal,
                  onPressed: () => _requestConsultation(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.section),
          const SectionTitle('루틴 리스트'),
          const SizedBox(height: SetflowSpacing.sm),
          if (routine.isPaid && routine.exercises.isEmpty)
            const SetflowCard(
              child: Column(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 38,
                    color: SetflowColors.purple,
                  ),
                  SizedBox(height: SetflowSpacing.sm),
                  Text(
                    '유료 플랜에서 전체 구성을 확인할 수 있어요',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: SetflowSpacing.xs),
                  Text(
                    '저항운동의 세트·중량·횟수와 유산소의 시간·거리·RPE는 플랜 인증 후 안전하게 불러옵니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: SetflowColors.secondaryText,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          for (var index = 0; index < routine.exercises.length; index++)
            Builder(
              builder: (context) {
                final exercise = routine.exercises[index];
                final sets = routine.setsFor(exercise);
                final reps = sets
                    .map((set) => set.reps)
                    .where((value) => value > 0);
                final minReps = reps.isEmpty
                    ? null
                    : reps.reduce((a, b) => a < b ? a : b);
                final maxReps = reps.isEmpty
                    ? null
                    : reps.reduce((a, b) => a > b ? a : b);
                final repsLabel = minReps == null
                    ? '횟수 미정'
                    : minReps == maxReps
                    ? '$minReps회'
                    : '$minReps~$maxReps회';
                final cardioDurationSeconds = sets.fold<int>(
                  0,
                  (sum, set) => sum + set.durationSeconds,
                );
                final cardioDistanceKm = sets.fold<double>(
                  0,
                  (sum, set) => sum + set.distanceKm,
                );
                final cardioRpes = sets
                    .map((set) => set.intensityRpe)
                    .where((value) => value > 0)
                    .toList(growable: false);
                final cardioRpeMin = cardioRpes.isEmpty
                    ? null
                    : cardioRpes.reduce((a, b) => a < b ? a : b);
                final cardioRpeMax = cardioRpes.isEmpty
                    ? null
                    : cardioRpes.reduce((a, b) => a > b ? a : b);
                final cardioRpeLabel = cardioRpeMin == null
                    ? ''
                    : cardioRpeMin == cardioRpeMax
                    ? '\nRPE ${cardioRpeMin.toStringAsFixed(cardioRpeMin % 1 == 0 ? 0 : 1)}'
                    : '\nRPE ${cardioRpeMin.toStringAsFixed(cardioRpeMin % 1 == 0 ? 0 : 1)}–${cardioRpeMax!.toStringAsFixed(cardioRpeMax % 1 == 0 ? 0 : 1)}';
                final planLabel = exercise.isCardio
                    ? cardioDurationSeconds <= 0
                          ? '시간 미정'
                          : '${(cardioDurationSeconds / 60).round()}분'
                                '${cardioDistanceKm > 0 ? '\n${cardioDistanceKm.toStringAsFixed(1)}km' : ''}'
                                '$cardioRpeLabel'
                    : sets.isEmpty
                    ? '세트 미정\n$repsLabel'
                    : '${sets.length}세트\n$repsLabel';
                return Padding(
                  padding: const EdgeInsets.only(bottom: SetflowSpacing.sm),
                  child: SetflowCard(
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: routine.color.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(
                              SetflowRadii.sm,
                            ),
                          ),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: SetflowSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                exercise.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                exercise.muscle,
                                style: const TextStyle(
                                  color: SetflowColors.secondaryText,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          planLabel,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: SetflowColors.secondaryText,
                            fontSize: 11,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: SetflowSpacing.xl),
          const Row(
            children: [
              Expanded(child: SectionTitle('생생한 후기')),
              Icon(Icons.star_rounded, color: SetflowColors.orange, size: 18),
              SizedBox(width: 3),
              Text('4.9 (128)'),
            ],
          ),
          const SizedBox(height: SetflowSpacing.sm),
          const _RoutineReview(
            author: '운동하는 직장인',
            content: '설명이 명확하고 운동 순서가 좋아서 꾸준히 따라가기 쉬웠어요.',
          ),
          const _RoutineReview(
            author: '헬린이 탈출기',
            content: '초보자가 놓치기 쉬운 포인트가 잘 정리되어 있습니다.',
          ),
          const SizedBox(height: SetflowSpacing.xl),
          AppButton(
            label: routine.isPaid ? '유료 루틴 저장' : '무료로 내 루틴에 저장',
            icon: Icons.download_rounded,
            onPressed: () => _import(context),
          ),
        ],
      ),
    );
  }
}

class _RoutineReview extends StatelessWidget {
  const _RoutineReview({required this.author, required this.content});

  final String author;
  final String content;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        author,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.star_rounded, size: 14, color: SetflowColors.orange),
              Icon(Icons.star_rounded, size: 14, color: SetflowColors.orange),
              Icon(Icons.star_rounded, size: 14, color: SetflowColors.orange),
              Icon(Icons.star_rounded, size: 14, color: SetflowColors.orange),
              Icon(Icons.star_rounded, size: 14, color: SetflowColors.orange),
            ],
          ),
          const SizedBox(height: 4),
          Text(content),
        ],
      ),
    );
  }
}

class CommunityPostDetailScreen extends StatefulWidget {
  const CommunityPostDetailScreen({required this.post, super.key});

  final CommunityPost post;

  @override
  State<CommunityPostDetailScreen> createState() =>
      _CommunityPostDetailScreenState();
}

class _CommunityPostDetailScreenState extends State<CommunityPostDetailScreen> {
  final commentController = TextEditingController();

  @override
  void dispose() {
    commentController.dispose();
    super.dispose();
  }

  Future<void> _addComment() async {
    final value = commentController.text.trim();
    if (value.isEmpty) {
      AppSnackbar.error(context, '댓글 내용을 입력해주세요.');
      return;
    }
    // Reading the post needed no account; leaving something on it does.
    if (!await requireSignIn(context, reason: AuthReason.community)) return;
    if (!mounted) return;
    try {
      await AppScope.of(context).addPostComment(widget.post, value);
      if (!mounted) return;
      commentController.clear();
      HapticFeedback.selectionClick();
      AppSnackbar.success(context, '댓글을 등록했어요.');
    } catch (error) {
      if (mounted) AppSnackbar.error(context, _communityErrorMessage(error));
    }
  }

  Future<void> _toggleLike(AppState state, CommunityPost post) async {
    if (!await requireSignIn(context, reason: AuthReason.community)) return;
    if (!mounted) return;
    try {
      await state.togglePostLike(post);
      HapticFeedback.selectionClick();
    } catch (error) {
      if (mounted) AppSnackbar.error(context, _communityErrorMessage(error));
    }
  }

  Future<void> _reportPost() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('게시물을 신고할까요?'),
            content: const Text('운영자가 게시물 내용을 확인합니다. 허위 신고는 제한될 수 있습니다.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('신고'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed && mounted) {
      AppSnackbar.success(context, '신고가 접수되었습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final post = widget.post;
    return Scaffold(
      appBar: AppBar(
        title: const Text('게시물'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '게시물 메뉴',
            onSelected: (value) {
              if (value == 'report') _reportPost();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'report', child: Text('신고하기')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: SetflowSpacing.lg),
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: post.color.withValues(alpha: .2),
                    child: Text(
                      post.author.characters.first,
                      style: TextStyle(
                        color: post.color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  title: Text(
                    post.author,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(_relativeTime(post.createdAt)),
                ),
                AspectRatio(
                  aspectRatio: 1,
                  child: post.imageUrl == null
                      ? ColoredBox(
                          color: post.color.withValues(alpha: .16),
                          child: Center(
                            child: Icon(
                              post.icon,
                              size: 126,
                              color: post.color,
                            ),
                          ),
                        )
                      : Image.network(
                          post.imageUrl!,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) =>
                              progress == null
                              ? child
                              : ColoredBox(
                                  color: post.color.withValues(alpha: .1),
                                  child: const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                          errorBuilder: (_, _, _) => ColoredBox(
                            color: post.color.withValues(alpha: .16),
                            child: Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                size: 64,
                                color: post.color,
                              ),
                            ),
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(SetflowSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.content,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.55,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: SetflowSpacing.sm),
                      Text(
                        post.metric,
                        style: const TextStyle(
                          color: SetflowColors.secondaryText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: SetflowSpacing.md),
                      Row(
                        children: [
                          IconButton(
                            tooltip: post.isLiked ? '좋아요 취소' : '좋아요',
                            onPressed: () => _toggleLike(state, post),
                            icon: Icon(
                              post.isLiked
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: post.isLiked ? SetflowColors.red : null,
                            ),
                          ),
                          Text('${post.likes}'),
                          const SizedBox(width: SetflowSpacing.md),
                          const Icon(Icons.chat_bubble_outline_rounded),
                          const SizedBox(width: 6),
                          Text('${post.comments.length}'),
                          const Spacer(),
                          IconButton(
                            tooltip: '공유',
                            onPressed: () =>
                                AppSnackbar.info(context, '공유 메뉴를 준비했어요.'),
                            icon: const Icon(Icons.ios_share_rounded),
                          ),
                        ],
                      ),
                      const Divider(height: SetflowSpacing.xl),
                      SectionTitle('댓글 ${post.comments.length}'),
                      const SizedBox(height: SetflowSpacing.sm),
                      if (post.comments.isEmpty)
                        const EmptyState(
                          icon: Icons.chat_bubble_outline_rounded,
                          title: '첫 댓글을 남겨보세요',
                          message: '응원과 경험을 나누면 운동을 이어가는 데 도움이 됩니다.',
                        )
                      else
                        for (final comment in post.comments)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 18,
                              child: Text(comment.author.characters.first),
                            ),
                            title: Text(
                              comment.author,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(comment.content),
                            trailing: Text(
                              _relativeTime(comment.createdAt),
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                SetflowSpacing.lg,
                SetflowSpacing.sm,
                SetflowSpacing.sm,
                SetflowSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: commentController,
                      hint: '댓글을 입력하세요',
                      maxLines: 3,
                      inputFormatters: [LengthLimitingTextInputFormatter(100)],
                      onSubmitted: (_) => _addComment(),
                    ),
                  ),
                  IconButton(
                    tooltip: '댓글 등록',
                    onPressed: _addComment,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ConsultationCreateScreen extends StatefulWidget {
  const ConsultationCreateScreen({
    this.initialTrainerId,
    this.initialGymId,
    this.initialTargetName,
    this.routineId,
    super.key,
  }) : assert(initialTrainerId == null || initialGymId == null);

  final String? initialTrainerId;
  final String? initialGymId;
  final String? initialTargetName;
  final String? routineId;

  @override
  State<ConsultationCreateScreen> createState() =>
      _ConsultationCreateScreenState();
}

class _ConsultationCreateScreenState extends State<ConsultationCreateScreen> {
  final formKey = GlobalKey<FormState>();
  final goalController = TextEditingController();
  final levelController = TextEditingController();
  final questionController = TextEditingController();
  final trainerSearchController = TextEditingController();
  Timer? trainerSearchDebounce;
  List<PublicTrainer> trainerSearchResults = const [];
  List<TopCoachingTrainer> topCoachingTrainers = const [];
  PublicTrainer? selectedTrainer;
  String? selectedTrainerId;
  String? trainerSearchNextCursor;
  String? trainerSearchError;
  String? demoTrainer;
  bool isSubmitting = false;
  bool trainerSearchInitialized = false;
  bool isTrainerSearchLoading = false;
  bool isTrainerSearchLoadingMore = false;
  bool isTopCoachingTrainersLoading = false;
  bool shareRecommendationProfile = false;
  String? topCoachingTrainersError;
  int trainerSearchRevision = 0;
  int topCoachingTrainersRevision = 0;

  static const demoTrainers = {
    '김코치': '초보자 근력 향상',
    '레이나 코치': '바디프로필 · 체지방 감량',
    '박트레이너': '직장인 단기 루틴',
  };

  @override
  void initState() {
    super.initState();
    final initialDemoTrainer = widget.initialTargetName?.split(' · ').first;
    demoTrainer = demoTrainers.containsKey(initialDemoTrainer)
        ? initialDemoTrainer
        : demoTrainers.keys.first;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (trainerSearchInitialized) return;
    final state = AppScope.of(context);
    final hasDirectTarget =
        widget.initialTrainerId != null || widget.initialGymId != null;
    if (!state.usesLiveBusinessData || hasDirectTarget) return;
    trainerSearchInitialized = true;
    trainerSearchResults = List.unmodifiable(state.publicTrainers.take(20));
    topCoachingTrainers = List.unmodifiable(state.topCoachingTrainers.take(3));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _retryTrainerSearch();
      _retryTopCoachingTrainers();
    });
  }

  @override
  void dispose() {
    trainerSearchDebounce?.cancel();
    goalController.dispose();
    levelController.dispose();
    questionController.dispose();
    trainerSearchController.dispose();
    super.dispose();
  }

  void _scheduleTrainerSearch(String query) {
    trainerSearchDebounce?.cancel();
    final revision = ++trainerSearchRevision;
    setState(() {
      isTrainerSearchLoading = true;
      isTrainerSearchLoadingMore = false;
      trainerSearchError = null;
      trainerSearchNextCursor = null;
    });
    trainerSearchDebounce = Timer(
      const Duration(milliseconds: 300),
      () => _loadTrainerSearch(query: query, revision: revision),
    );
  }

  Future<void> _retryTrainerSearch() async {
    trainerSearchDebounce?.cancel();
    final revision = ++trainerSearchRevision;
    setState(() {
      isTrainerSearchLoading = true;
      isTrainerSearchLoadingMore = false;
      trainerSearchError = null;
      trainerSearchNextCursor = null;
    });
    await _loadTrainerSearch(
      query: trainerSearchController.text,
      revision: revision,
    );
  }

  Future<void> _loadMoreTrainers() async {
    final cursor = trainerSearchNextCursor;
    if (cursor == null || isTrainerSearchLoadingMore) return;
    final revision = ++trainerSearchRevision;
    setState(() {
      isTrainerSearchLoadingMore = true;
      trainerSearchError = null;
    });
    await _loadTrainerSearch(
      query: trainerSearchController.text,
      cursor: cursor,
      append: true,
      revision: revision,
    );
  }

  Future<void> _retryTopCoachingTrainers() async {
    final revision = ++topCoachingTrainersRevision;
    setState(() {
      isTopCoachingTrainersLoading = true;
      topCoachingTrainersError = null;
    });
    try {
      final trainers = await AppScope.of(
        context,
      ).loadTopCoachingTrainers(limit: 3);
      if (!mounted || revision != topCoachingTrainersRevision) return;
      setState(() {
        topCoachingTrainers = List.unmodifiable(trainers.take(3));
        topCoachingTrainersError = null;
        isTopCoachingTrainersLoading = false;
      });
    } catch (_) {
      if (!mounted || revision != topCoachingTrainersRevision) return;
      setState(() {
        topCoachingTrainersError = '현재 코칭 TOP 3를 불러오지 못했어요.';
        isTopCoachingTrainersLoading = false;
      });
    }
  }

  Future<void> _loadTrainerSearch({
    required String query,
    required int revision,
    String? cursor,
    bool append = false,
  }) async {
    if (!mounted || revision != trainerSearchRevision) return;
    try {
      final page = await AppScope.of(
        context,
      ).searchPublicTrainers(query: query, cursor: cursor, pageSize: 20);
      if (!mounted || revision != trainerSearchRevision) return;
      final merged = <String, PublicTrainer>{
        if (append)
          for (final trainer in trainerSearchResults)
            trainer.profile.id: trainer,
        for (final trainer in page.items) trainer.profile.id: trainer,
      };
      setState(() {
        trainerSearchResults = List.unmodifiable(merged.values);
        trainerSearchNextCursor = page.nextCursor;
        trainerSearchError = null;
        isTrainerSearchLoading = false;
        isTrainerSearchLoadingMore = false;
      });
    } catch (_) {
      if (!mounted || revision != trainerSearchRevision) return;
      setState(() {
        trainerSearchError = '트레이너 목록을 불러오지 못했어요.';
        isTrainerSearchLoading = false;
        isTrainerSearchLoadingMore = false;
      });
    }
  }

  void _selectTrainer(PublicTrainer trainer) {
    setState(() {
      selectedTrainer = trainer;
      selectedTrainerId = trainer.profile.id;
    });
  }

  void _clearTrainerSearch() {
    trainerSearchController.clear();
    _scheduleTrainerSearch('');
  }

  Future<void> _submit() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    final state = AppScope.of(context);
    String? trainerId;
    String? gymId;
    late String targetName;
    late String specialty;

    if (state.usesLiveBusinessData) {
      trainerId = widget.initialTrainerId ?? selectedTrainerId;
      gymId = widget.initialGymId;
      if (trainerId == null && gymId == null) {
        AppSnackbar.error(context, '상담할 트레이너를 선택해주세요.');
        return;
      }

      final selectedTrainer = trainerId == null
          ? null
          : this.selectedTrainer?.profile.id == trainerId
          ? this.selectedTrainer
          : state.publicTrainers
                .where((item) => item.profile.id == trainerId)
                .firstOrNull;
      if (widget.initialTrainerId == null &&
          trainerId != null &&
          selectedTrainer == null) {
        AppSnackbar.error(context, '선택한 트레이너 정보를 다시 확인해주세요.');
        return;
      }
      targetName =
          widget.initialTargetName ??
          selectedTrainer?.profile.displayName ??
          (gymId == null ? '루틴 작성 트레이너' : '루틴 작성 센터');
      specialty =
          selectedTrainer?.specialties.firstOrNull ??
          (gymId == null ? '맞춤 운동 상담' : '센터 루틴 상담');
    } else {
      targetName = demoTrainer ?? demoTrainers.keys.first;
      specialty = demoTrainers[targetName] ?? '맞춤 운동 상담';
    }

    setState(() => isSubmitting = true);
    try {
      if (!state.usesLiveBusinessData) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      await state.addConsultation(
        trainerId: trainerId,
        gymId: gymId,
        routineId: widget.routineId,
        trainerName: targetName,
        specialty: specialty,
        goal: goalController.text.trim(),
        level: levelController.text.trim(),
        question: questionController.text.trim(),
        sharedRecommendationProfile: shareRecommendationProfile
            ? state.recommendationProfile
            : null,
      );
      if (!mounted) return;
      HapticFeedback.lightImpact();
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => isSubmitting = false);
      AppSnackbar.error(context, '상담 신청에 실패했어요. 잠시 후 다시 시도해주세요.');
    }
  }

  String? _validate(String? value, String label, int minimum) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '$label 내용을 입력해주세요.';
    if (text.length < minimum) return '$label을 $minimum자 이상 입력해주세요.';
    return null;
  }

  Widget _buildRecommendationProfileSharing(
    BuildContext context,
    AppState state,
  ) {
    final profile = state.recommendationProfile;
    return SetflowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.health_and_safety_outlined, color: SetflowColors.teal),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '정밀 추천 정보 공유',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            profile == null
                ? '저장된 설문이 없습니다. 먼저 부상·통증, 장비, 숙련도와 회복 상태를 입력할 수 있어요.'
                : '이 상담을 위해 아래 설문 사본을 선택되거나 배정된 트레이너에게만 제공할 수 있어요.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          if (profile == null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              key: const ValueKey('consultation-create-profile'),
              onPressed: isSubmitting
                  ? null
                  : () async {
                      await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => const RecommendationProfileScreen(),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('정밀 추천 정보 입력'),
            ),
          ] else ...[
            SwitchListTile.adaptive(
              key: const ValueKey('consultation-share-profile'),
              contentPadding: EdgeInsets.zero,
              value: shareRecommendationProfile,
              title: const Text(
                '이 상담에 설문 사본 함께 제공',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('기본은 꺼짐이며, 상담을 보낼 때 저장된 내용의 사본만 공유합니다.'),
              onChanged: isSubmitting
                  ? null
                  : (value) =>
                        setState(() => shareRecommendationProfile = value),
            ),
            if (shareRecommendationProfile) ...[
              const Divider(height: 22),
              RecommendationProfileSummary(profile: profile, compact: true),
              Text(
                '센터 상담은 배정된 트레이너만 볼 수 있고 센터 대표에게는 이 설문이 공개되지 않습니다. '
                '회복 상태에는 기록 날짜가 함께 전달됩니다.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildTrainerSearch(BuildContext context) {
    final query = trainerSearchController.text.trim();
    final selectedIsOutsideResults =
        selectedTrainer != null &&
        !trainerSearchResults.any(
          (trainer) => trainer.profile.id == selectedTrainer!.profile.id,
        ) &&
        !topCoachingTrainers.any(
          (entry) => entry.trainer.profile.id == selectedTrainer!.profile.id,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          key: const ValueKey('consultation-trainer-search'),
          controller: trainerSearchController,
          label: '상담 트레이너 검색',
          hint: '이름, 센터, 전문분야를 검색하세요',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  key: const ValueKey('consultation-trainer-clear-input'),
                  tooltip: '검색어 지우기',
                  onPressed: _clearTrainerSearch,
                  icon: const Icon(Icons.close_rounded),
                ),
          inputFormatters: [LengthLimitingTextInputFormatter(50)],
          onChanged: _scheduleTrainerSearch,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _retryTrainerSearch(),
        ),
        const SizedBox(height: SetflowSpacing.md),
        if (selectedIsOutsideResults) ...[
          Text(
            '선택한 트레이너',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: SetflowSpacing.sm),
          _trainerResultCard(context, selectedTrainer!),
          const SizedBox(height: SetflowSpacing.md),
        ],
        if (isTrainerSearchLoading && trainerSearchResults.isEmpty)
          const LoadingState(
            key: ValueKey('consultation-trainer-loading'),
            message: '상담 가능한 트레이너를 찾고 있어요',
            itemCount: 2,
            compact: true,
          )
        else if (trainerSearchError != null && trainerSearchResults.isEmpty)
          SetflowCard(
            child: Column(
              children: [
                const Icon(Icons.cloud_off_rounded, size: 34),
                const SizedBox(height: SetflowSpacing.sm),
                Text(
                  trainerSearchError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: SetflowSpacing.md),
                AppButton(
                  key: const ValueKey('consultation-trainer-retry'),
                  label: '다시 시도',
                  icon: Icons.refresh_rounded,
                  expanded: false,
                  variant: AppButtonVariant.tonal,
                  onPressed: _retryTrainerSearch,
                ),
              ],
            ),
          )
        else if (trainerSearchResults.isEmpty)
          SetflowCard(
            child: Column(
              children: [
                const Icon(Icons.person_search_rounded, size: 36),
                const SizedBox(height: SetflowSpacing.sm),
                Text(
                  query.isEmpty ? '상담 가능한 트레이너가 없어요' : '검색 결과가 없어요',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: SetflowSpacing.xs),
                Text(
                  query.isEmpty
                      ? '인증된 트레이너가 등록되면 상담을 신청할 수 있어요.'
                      : '다른 이름, 센터 또는 전문분야로 검색해보세요.',
                  textAlign: TextAlign.center,
                ),
                if (query.isNotEmpty) ...[
                  const SizedBox(height: SetflowSpacing.md),
                  AppButton(
                    key: const ValueKey('consultation-trainer-clear'),
                    label: '검색 초기화',
                    icon: Icons.restart_alt_rounded,
                    expanded: false,
                    variant: AppButtonVariant.tonal,
                    onPressed: _clearTrainerSearch,
                  ),
                ],
              ],
            ),
          )
        else ...[
          Text(
            query.isEmpty
                ? '상담 가능한 트레이너'
                : '검색 결과 ${trainerSearchResults.length}명',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: SetflowSpacing.sm),
          for (final trainer in trainerSearchResults) ...[
            _trainerResultCard(context, trainer),
            const SizedBox(height: SetflowSpacing.sm),
          ],
          if (trainerSearchError != null) ...[
            Text(
              trainerSearchError!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: SetflowSpacing.sm),
            AppButton(
              key: const ValueKey('consultation-trainer-retry'),
              label: '다시 시도',
              icon: Icons.refresh_rounded,
              expanded: false,
              variant: AppButtonVariant.tonal,
              onPressed: _retryTrainerSearch,
            ),
          ] else if (trainerSearchNextCursor != null)
            AppButton(
              key: const ValueKey('consultation-trainer-load-more'),
              label: '트레이너 더 보기',
              isLoading: isTrainerSearchLoadingMore,
              expanded: false,
              variant: AppButtonVariant.outlined,
              onPressed: isTrainerSearchLoadingMore ? null : _loadMoreTrainers,
            ),
        ],
      ],
    );
  }

  Widget _buildTopCoachingTrainers(BuildContext context) {
    return Column(
      key: const ValueKey('consultation-top-trainers'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: SetflowColors.primary.withValues(alpha: .22),
                borderRadius: BorderRadius.circular(SetflowRadii.sm),
              ),
              child: const Icon(
                Icons.emoji_events_rounded,
                size: 20,
                color: SetflowColors.ink,
              ),
            ),
            const SizedBox(width: SetflowSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '현재 코칭 TOP 3',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '현재 진행 중인 코칭 건수 기준',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: SetflowSpacing.md),
        if (isTopCoachingTrainersLoading && topCoachingTrainers.isEmpty)
          const LoadingState(
            key: ValueKey('consultation-top-trainers-loading'),
            message: '현재 코칭 TOP 3를 불러오고 있어요',
            itemCount: 2,
            compact: true,
          )
        else if (topCoachingTrainersError != null &&
            topCoachingTrainers.isEmpty)
          SetflowCard(
            key: const ValueKey('consultation-top-trainers-error'),
            padding: const EdgeInsets.all(SetflowSpacing.md),
            child: Column(
              children: [
                const Icon(Icons.cloud_off_rounded, size: 32),
                const SizedBox(height: SetflowSpacing.sm),
                Text(
                  topCoachingTrainersError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: SetflowSpacing.md),
                AppButton(
                  key: const ValueKey('consultation-top-trainers-retry'),
                  label: '다시 시도',
                  icon: Icons.refresh_rounded,
                  expanded: false,
                  variant: AppButtonVariant.tonal,
                  onPressed: _retryTopCoachingTrainers,
                ),
              ],
            ),
          )
        else if (topCoachingTrainers.isEmpty)
          const SetflowCard(
            key: ValueKey('consultation-top-trainers-empty'),
            padding: EdgeInsets.all(SetflowSpacing.md),
            child: Row(
              children: [
                Icon(Icons.people_outline_rounded),
                SizedBox(width: SetflowSpacing.sm),
                Expanded(
                  child: Text(
                    '현재 상담 가능한 트레이너가 없어요.',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          )
        else ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (
                  var index = 0;
                  index < topCoachingTrainers.length;
                  index++
                ) ...[
                  SizedBox(
                    width: 308,
                    child: _trainerResultCard(
                      context,
                      topCoachingTrainers[index].trainer,
                      cardKey: ValueKey(
                        'consultation-top-trainer-${topCoachingTrainers[index].trainer.profile.id}',
                      ),
                      rank: index + 1,
                      activeCoachingCount:
                          topCoachingTrainers[index].activeCoachingCount,
                    ),
                  ),
                  if (index < topCoachingTrainers.length - 1)
                    const SizedBox(width: SetflowSpacing.sm),
                ],
              ],
            ),
          ),
          if (topCoachingTrainersError != null) ...[
            const SizedBox(height: SetflowSpacing.sm),
            Text(
              topCoachingTrainersError!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: SetflowSpacing.sm),
            AppButton(
              key: const ValueKey('consultation-top-trainers-retry'),
              label: '다시 시도',
              icon: Icons.refresh_rounded,
              expanded: false,
              variant: AppButtonVariant.tonal,
              onPressed: _retryTopCoachingTrainers,
            ),
          ],
        ],
      ],
    );
  }

  Widget _trainerResultCard(
    BuildContext context,
    PublicTrainer trainer, {
    Key? cardKey,
    int? rank,
    int? activeCoachingCount,
  }) {
    final profile = trainer.profile;
    final isSelected = selectedTrainerId == profile.id;
    final specialty =
        trainer.specialties.firstOrNull ?? profile.keyword ?? '맞춤 운동 상담';
    final details = <String>[
      if (profile.centerName != null && profile.centerName!.trim().isNotEmpty)
        profile.centerName!,
      specialty,
      if (profile.careerYears != null) '경력 ${profile.careerYears}년',
    ];
    return SetflowCard(
      key: cardKey ?? ValueKey('consultation-trainer-result-${profile.id}'),
      color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
      onTap: () => _selectTrainer(trainer),
      padding: const EdgeInsets.all(SetflowSpacing.md),
      child: Row(
        children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
            child: Text(
              rank != null
                  ? '$rank'
                  : profile.displayName.characters.isEmpty
                  ? 'T'
                  : profile.displayName.characters.first,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: SetflowSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        profile.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    if (profile.verified) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.verified_rounded,
                        size: 17,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  details.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                if (activeCoachingCount != null) ...[
                  Text(
                    '현재 코칭 $activeCoachingCount건',
                    key: ValueKey(
                      'consultation-top-trainer-active-count-${profile.id}',
                    ),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '평점 ${profile.rating.toStringAsFixed(1)} · 누적 코칭 ${profile.coachingTotal}회',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else
                  Text(
                    '평점 ${profile.rating.toStringAsFixed(1)} · 코칭 ${profile.coachingTotal}회',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: SetflowSpacing.sm),
          Icon(
            isSelected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final liveData = state.usesLiveBusinessData;
    final hasDirectTarget =
        widget.initialTrainerId != null || widget.initialGymId != null;
    final selectableTrainerId =
        selectedTrainer?.profile.id == selectedTrainerId ||
            state.publicTrainers.any(
              (item) => item.profile.id == selectedTrainerId,
            )
        ? selectedTrainerId
        : null;
    final canSubmit =
        !isSubmitting &&
        (!liveData || hasDirectTarget || selectableTrainerId != null);
    return Scaffold(
      appBar: AppBar(title: const Text('새 상담 신청')),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
          children: [
            const Text(
              '현재 상태를 자세히 알려주시면\n더 정확한 답변을 받을 수 있어요.',
              style: TextStyle(
                fontSize: 24,
                height: 1.25,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: SetflowSpacing.xl),
            if (liveData && hasDirectTarget)
              InputDecorator(
                decoration: const InputDecoration(labelText: '상담 대상'),
                child: Text(
                  widget.initialTargetName ??
                      (widget.initialGymId == null ? '루틴 작성 트레이너' : '루틴 작성 센터'),
                  key: const ValueKey('consultation-direct-target'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              )
            else if (liveData)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTopCoachingTrainers(context),
                  const SizedBox(height: SetflowSpacing.xl),
                  _buildTrainerSearch(context),
                ],
              )
            else
              DropdownButtonFormField<String>(
                initialValue: demoTrainer,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '상담 트레이너'),
                items: demoTrainers.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text('${entry.key} · ${entry.value}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => demoTrainer = value ?? demoTrainer),
              ),
            const SizedBox(height: SetflowSpacing.md),
            AppTextField(
              controller: goalController,
              label: '운동 목표',
              hint: '예: 체지방 5kg 감량, 3대 500 달성',
              validator: (value) => _validate(value, '운동 목표', 5),
            ),
            const SizedBox(height: SetflowSpacing.md),
            AppTextField(
              controller: levelController,
              label: '현재 운동 수준과 경험',
              hint: '운동 기간과 주당 횟수를 알려주세요.',
              minLines: 3,
              maxLines: 4,
              validator: (value) => _validate(value, '운동 수준과 경험', 10),
            ),
            const SizedBox(height: SetflowSpacing.md),
            AppTextField(
              controller: questionController,
              label: '가장 궁금한 점',
              hint: '트레이너에게 묻고 싶은 내용을 구체적으로 작성해주세요.',
              minLines: 4,
              maxLines: 6,
              validator: (value) => _validate(value, '질문', 10),
            ),
            const SizedBox(height: SetflowSpacing.lg),
            _buildRecommendationProfileSharing(context, state),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            18,
            SetflowSpacing.sm,
            18,
            SetflowSpacing.md,
          ),
          child: AppButton(
            key: const ValueKey('consultation-submit'),
            label: '상담 신청하기',
            icon: Icons.send_rounded,
            isLoading: isSubmitting,
            onPressed: canSubmit ? _submit : null,
          ),
        ),
      ),
    );
  }
}

class ConsultationDetailScreen extends StatefulWidget {
  const ConsultationDetailScreen({required this.consultation, super.key});

  final ConsultationData consultation;

  @override
  State<ConsultationDetailScreen> createState() =>
      _ConsultationDetailScreenState();
}

class _ConsultationDetailScreenState extends State<ConsultationDetailScreen> {
  Future<void> _startCoaching() async {
    if (AppScope.of(context).usesLiveBusinessData) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('결제 API 연동 준비 중'),
          content: const Text('실제 결제와 에스크로 연동이 완료된 후 코칭을 시작할 수 있어요.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return;
    }
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('1:1 코칭을 시작할까요?'),
            content: const Text(
              '4주 코칭 149,000원을 결제하고 담당 트레이너를 지정합니다. 결제 금액은 에스크로로 보호됩니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('결제하고 시작'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    AppScope.of(context).startCoaching(widget.consultation);
    HapticFeedback.lightImpact();
    AppSnackbar.success(context, '1:1 코칭이 시작되었습니다.');
  }

  Future<void> _rate() async {
    if (AppScope.of(context).usesLiveBusinessData) {
      AppSnackbar.info(context, '평점 API 연동을 준비하고 있어요.');
      return;
    }
    var rating = widget.consultation.rating ?? 5;
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('코칭 만족도'),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 1; index <= 5; index++)
                IconButton(
                  tooltip: '$index점',
                  onPressed: () => setDialogState(() => rating = index),
                  icon: Icon(
                    index <= rating ? Icons.star_rounded : Icons.star_border,
                    color: SetflowColors.orange,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, rating),
              child: const Text('전송'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    AppScope.of(context).rateConsultation(widget.consultation, result);
    AppSnackbar.success(context, '만족도 $result점을 전달했어요.');
  }

  Future<void> _revokeRecommendationProfileShare() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('설문 공유를 철회할까요?'),
            content: const Text(
              '철회하면 트레이너 화면에서 이 설문 사본을 더 이상 볼 수 없습니다. 이미 확인하거나 별도로 기록한 정보까지 되돌릴 수는 없습니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소'),
              ),
              FilledButton(
                key: const ValueKey('consultation-profile-revoke-confirm'),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('공유 철회'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    try {
      await AppScope.of(
        context,
      ).revokeConsultationRecommendationProfileShare(widget.consultation.id);
      if (!mounted) return;
      setState(() {
        widget.consultation.recommendationProfileShareRevokedAt ??=
            DateTime.now();
      });
      AppSnackbar.success(context, '정밀 추천 정보 공유를 철회했어요.');
    } catch (_) {
      if (!mounted) return;
      AppSnackbar.error(context, '공유 철회에 실패했어요. 잠시 후 다시 시도해주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final consultation = widget.consultation;
    final liveData = AppScope.of(context).usesLiveBusinessData;
    return Scaffold(
      appBar: AppBar(title: const Text('상담 상세')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
        children: [
          Row(
            children: [
              _StatusChip(status: consultation.status),
              const SizedBox(width: SetflowSpacing.sm),
              Text(
                '${DateFormat('yyyy.MM.dd').format(consultation.createdAt)} 신청',
                style: const TextStyle(
                  color: SetflowColors.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.lg),
          SetflowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(child: Text('나')),
                    const SizedBox(width: SetflowSpacing.sm),
                    const Text(
                      '나의 신청 내용',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const Divider(height: SetflowSpacing.xl),
                _ConsultField(label: '목표', value: consultation.goal),
                _ConsultField(label: '현재 운동 수준과 경험', value: consultation.level),
                _ConsultField(
                  label: '가장 궁금한 점',
                  value: consultation.question,
                  highlighted: true,
                ),
              ],
            ),
          ),
          if (consultation.sharedRecommendationProfile case final profile?) ...[
            const SizedBox(height: SetflowSpacing.lg),
            SetflowCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '이 상담에 함께 제공한 정밀 추천 정보',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '상담을 신청할 때 저장된 설문의 사본입니다.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Divider(height: SetflowSpacing.xl),
                  RecommendationProfileSummary(profile: profile, compact: true),
                  const SizedBox(height: 8),
                  if (consultation.recommendationProfileShareRevokedAt != null)
                    const Row(
                      children: [
                        Icon(
                          Icons.visibility_off_outlined,
                          size: 18,
                          color: SetflowColors.secondaryText,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '공유 철회됨 · 트레이너 화면에서는 더 이상 보이지 않습니다.',
                            style: TextStyle(
                              color: SetflowColors.secondaryText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        key: const ValueKey('consultation-profile-revoke'),
                        onPressed: _revokeRecommendationProfileShare,
                        icon: const Icon(Icons.visibility_off_outlined),
                        label: const Text('공유 철회'),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: SetflowSpacing.lg),
          if (consultation.status == ConsultationStatus.waiting)
            const LoadingState(
              message: '트레이너가 상담 내용을 확인하고 있어요.\n답변이 등록되면 알려드릴게요.',
            )
          else ...[
            SetflowCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.person_rounded,
                        color: SetflowColors.blue,
                      ),
                      const SizedBox(width: SetflowSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              consultation.trainerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              consultation.specialty,
                              style: const TextStyle(
                                color: SetflowColors.secondaryText,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.verified_rounded,
                        color: SetflowColors.blue,
                      ),
                    ],
                  ),
                  const Divider(height: SetflowSpacing.xl),
                  Text(
                    consultation.response ??
                        '상담 답변이 완료되었습니다. 코칭을 시작하면 맞춤 루틴과 정기 피드백을 받을 수 있어요.',
                    style: const TextStyle(height: 1.6),
                  ),
                ],
              ),
            ),
            const SizedBox(height: SetflowSpacing.lg),
            if (consultation.status == ConsultationStatus.answered)
              SetflowCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '4주 1:1 비동기 코칭',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      liveData
                          ? '실제 결제·에스크로 API 연동 후 이용할 수 있어요.'
                          : '맞춤 루틴 · 주 1회 피드백 · 72시간 응답 보장',
                      style: const TextStyle(
                        color: SetflowColors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: SetflowSpacing.lg),
                    Row(
                      children: [
                        Text(
                          liveData ? '결제 API 준비 중' : '149,000원',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Spacer(),
                        AppButton(
                          key: const ValueKey('coaching-start'),
                          expanded: false,
                          label: liveData ? '연동 준비 중' : '코칭 시작',
                          onPressed: liveData ? null : _startCoaching,
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else ...[
              Container(
                padding: const EdgeInsets.all(SetflowSpacing.lg),
                decoration: BoxDecoration(
                  color: SetflowColors.green.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(SetflowRadii.lg),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      color: SetflowColors.green,
                    ),
                    const SizedBox(width: SetflowSpacing.sm),
                    Expanded(
                      child: Text(
                        liveData
                            ? '코칭 상태는 서버 기록으로 표시됩니다. 결제·에스크로 연동은 준비 중입니다.'
                            : '코칭이 진행 중입니다. 결제 금액은 에스크로로 안전하게 보호됩니다.',
                        style: const TextStyle(height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SetflowSpacing.md),
              AppButton(
                key: const ValueKey('coaching-rating'),
                label: liveData
                    ? '평점 연동 준비 중'
                    : consultation.rating == null
                    ? '코칭 만족도 남기기'
                    : '만족도 ${consultation.rating}점 전송 완료',
                variant: AppButtonVariant.outlined,
                onPressed: !liveData && consultation.rating == null
                    ? _rate
                    : null,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ConsultationStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ConsultationStatus.waiting => ('답변 대기', SetflowColors.orange),
      ConsultationStatus.answered => ('상담 완료', SetflowColors.green),
      ConsultationStatus.coaching => ('코칭 중', context.setflowColors.info),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(SetflowRadii.sm),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ConsultField extends StatelessWidget {
  const _ConsultField({
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SetflowSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: SetflowColors.secondaryText,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(SetflowSpacing.md),
            decoration: BoxDecoration(
              color: highlighted
                  ? SetflowColors.primary.withValues(alpha: .12)
                  : context.setflowColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(SetflowRadii.md),
            ),
            child: Text(value, style: const TextStyle(height: 1.45)),
          ),
        ],
      ),
    );
  }
}

String _relativeTime(DateTime date) {
  final difference = DateTime.now().difference(date);
  if (difference.inMinutes < 1) return '방금';
  if (difference.inMinutes < 60) return '${difference.inMinutes}분 전';
  if (difference.inHours < 24) return '${difference.inHours}시간 전';
  return '${difference.inDays}일 전';
}
