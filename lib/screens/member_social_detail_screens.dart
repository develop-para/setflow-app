import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

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
    return Padding(
      padding: EdgeInsets.fromLTRB(
        SetflowSpacing.xl,
        SetflowSpacing.xs,
        SetflowSpacing.xl,
        MediaQuery.viewInsetsOf(context).bottom + SetflowSpacing.xxl,
      ),
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '새 루틴 만들기',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
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
  const SocialPostComposerScreen({super.key});

  @override
  State<SocialPostComposerScreen> createState() =>
      _SocialPostComposerScreenState();
}

class _SocialPostComposerScreenState extends State<SocialPostComposerScreen> {
  final formKey = GlobalKey<FormState>();
  final contentController = TextEditingController();
  bool hasImage = false;
  bool includeWorkout = true;
  bool isSubmitting = false;
  String visualKey = 'strength';
  final overlays = <String>{'날짜', '시간', '위치', '완료 루틴'};

  @override
  void dispose() {
    contentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    setState(() => isSubmitting = true);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    AppScope.of(context).addCommunityPost(
      content: contentController.text.trim().isEmpty
          ? '오늘 운동 기록을 공유했습니다.'
          : contentController.text.trim(),
      includeWorkout: includeWorkout,
      visualKey: visualKey,
    );
    HapticFeedback.lightImpact();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
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
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            _WorkoutVisualPreview(
              hasImage: hasImage,
              visualKey: visualKey,
              overlays: overlays,
              onCamera: () => setState(() => hasImage = true),
              onGallery: () => setState(() => hasImage = true),
              onChange: () => setState(() => hasImage = false),
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
              children: ['날짜', '시간', '위치', '완료 루틴']
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
                if ((value?.trim().isEmpty ?? true) && !hasImage) {
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
              subtitle: const Text('하체 · 12세트 · 4.2t'),
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
                    color: Theme.of(context).colorScheme.primary,
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
                    color: context.setflowColors.success,
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

class _WorkoutVisualPreview extends StatelessWidget {
  const _WorkoutVisualPreview({
    required this.hasImage,
    required this.visualKey,
    required this.overlays,
    required this.onCamera,
    required this.onGallery,
    required this.onChange,
  });

  final bool hasImage;
  final String visualKey;
  final Set<String> overlays;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    if (!hasImage) {
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
              Text(
                '운동 결과 사진을 올려보세요.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final color = switch (visualKey) {
      'streak' => context.setflowColors.teal,
      'tip' => context.setflowColors.info,
      _ => context.setflowColors.orange,
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
                Center(
                  child: Icon(
                    icon,
                    size: 124,
                    color: color.withValues(alpha: .72),
                  ),
                ),
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
                if (overlays.contains('위치'))
                  const _PreviewLabel(
                    alignment: Alignment.bottomLeft,
                    text: '강남구 역삼동',
                  ),
                if (overlays.contains('완료 루틴'))
                  const _PreviewLabel(
                    alignment: Alignment.bottomRight,
                    text: '하체 집중 루틴',
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
              const SizedBox(height: SetflowSpacing.xs),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
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
          vertical: SetflowSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(SetflowRadii.sm),
        ),
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.white,
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
              TintedIconBadge(icon: icon, color: color, size: 46),
              const SizedBox(height: SetflowSpacing.sm),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rich action card meta line (pattern language item 4): bold tabular
/// numerals for exercise/set count and estimated duration.
class _RoutineMetaRow extends StatelessWidget {
  const _RoutineMetaRow({
    required this.exerciseCount,
    required this.setCount,
    required this.estimatedMinutes,
  });

  final int exerciseCount;
  final int setCount;
  final int estimatedMinutes;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final labelStyle = text.bodyMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: colors.onSurfaceVariant,
    );
    final numeralStyle = text.bodyMedium?.copyWith(
      fontWeight: FontWeight.w900,
      color: colors.onSurface,
    );
    return Wrap(
      spacing: SetflowSpacing.md,
      runSpacing: SetflowSpacing.xs,
      children: [
        Text.rich(
          TextSpan(
            style: labelStyle,
            children: [
              TextSpan(text: '$exerciseCount', style: numeralStyle),
              const TextSpan(text: ' 운동'),
            ],
          ),
        ),
        Text.rich(
          TextSpan(
            style: labelStyle,
            children: [
              TextSpan(text: '$setCount', style: numeralStyle),
              const TextSpan(text: ' 세트'),
            ],
          ),
        ),
        Text.rich(
          TextSpan(
            style: labelStyle,
            children: [
              const TextSpan(text: '약 '),
              TextSpan(text: '$estimatedMinutes', style: numeralStyle),
              const TextSpan(text: '분'),
            ],
          ),
        ),
      ],
    );
  }
}

class ExpertRoutineDetailScreen extends StatelessWidget {
  const ExpertRoutineDetailScreen({required this.routine, super.key});

  final RoutineData routine;

  void _import(BuildContext context) {
    final result = AppScope.of(context).importRoutine(routine);
    switch (result) {
      case RoutineImportResult.imported:
        HapticFeedback.lightImpact();
        AppSnackbar.success(context, '내 루틴에 저장했어요.');
      case RoutineImportResult.alreadySaved:
        AppSnackbar.info(context, '이미 내 루틴에 저장되어 있어요.');
      case RoutineImportResult.limitReached:
        AppSnackbar.error(context, '무료 플랜은 루틴을 4개까지 저장할 수 있어요.');
    }
  }

  Future<void> _requestConsultation(BuildContext context) async {
    final trainer = routine.author.split(' · ').first;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ConsultationCreateScreen(initialTrainer: trainer),
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
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
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
              Chip(label: Text('#${routine.level}')),
              Chip(label: Text('#${routine.exercises.first.muscle}')),
              const Chip(label: Text('#근력')),
            ],
          ),
          const SizedBox(height: SetflowSpacing.md),
          Text(
            routine.name,
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
              height: 1.2,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: SetflowSpacing.sm),
          _RoutineMetaRow(
            exerciseCount: routine.exercises.length,
            setCount: routine.exercises.length * 3,
            estimatedMinutes: routine.exercises.length * 12,
          ),
          const SizedBox(height: SetflowSpacing.lg),
          SetflowCard(
            child: Row(
              children: [
                TintedIconBadge(
                  icon: Icons.person_rounded,
                  color: routine.color,
                  size: 48,
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
                              routine.author,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: SetflowSpacing.xs),
                          Icon(
                            Icons.verified_rounded,
                            size: 17,
                            color: context.setflowColors.blue,
                          ),
                        ],
                      ),
                      Text(
                        '전문 루틴 12개 · 코칭 340회',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
          for (var index = 0; index < routine.exercises.length; index++)
            Padding(
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
                        borderRadius: BorderRadius.circular(SetflowRadii.sm),
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
                            routine.exercises[index].name,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            routine.exercises[index].muscle,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '3세트\n8~12회',
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: SetflowSpacing.xl),
          Row(
            children: [
              const Expanded(child: SectionTitle('생생한 후기')),
              Icon(
                Icons.star_rounded,
                color: context.setflowColors.orange,
                size: 18,
              ),
              const SizedBox(width: SetflowSpacing.xs),
              const Text('4.9 (128)'),
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
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: AppButton(
          label: '내 루틴으로 저장',
          icon: Icons.download_rounded,
          onPressed: () => _import(context),
        ),
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
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.star_rounded,
                size: 14,
                color: context.setflowColors.orange,
              ),
              Icon(
                Icons.star_rounded,
                size: 14,
                color: context.setflowColors.orange,
              ),
              Icon(
                Icons.star_rounded,
                size: 14,
                color: context.setflowColors.orange,
              ),
              Icon(
                Icons.star_rounded,
                size: 14,
                color: context.setflowColors.orange,
              ),
              Icon(
                Icons.star_rounded,
                size: 14,
                color: context.setflowColors.orange,
              ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.xs),
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

  void _addComment() {
    final value = commentController.text.trim();
    if (value.isEmpty) {
      AppSnackbar.error(context, '댓글 내용을 입력해주세요.');
      return;
    }
    AppScope.of(context).addPostComment(widget.post, value);
    commentController.clear();
    HapticFeedback.selectionClick();
    AppSnackbar.success(context, '댓글을 등록했어요.');
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

  Future<void> _showPostMenu(BuildContext context) async {
    final action = await showAppActionSheet<String>(
      context,
      title: '게시물 메뉴',
      actions: const [
        SheetAction(
          icon: Icons.flag_outlined,
          label: '신고하기',
          value: 'report',
          destructive: true,
        ),
      ],
    );
    if (action == 'report' && mounted) _reportPost();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final post = widget.post;
    return Scaffold(
      appBar: AppBar(
        title: const Text('게시물'),
        actions: [
          IconButton(
            tooltip: '게시물 메뉴',
            onPressed: () => _showPostMenu(context),
            icon: const Icon(Icons.more_vert_rounded),
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
                  child: ColoredBox(
                    color: post.color.withValues(alpha: .16),
                    child: Center(
                      child: Icon(post.icon, size: 126, color: post.color),
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
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.55,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: SetflowSpacing.sm),
                      Text(
                        post.metric,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: SetflowSpacing.md),
                      Row(
                        children: [
                          IconButton(
                            tooltip: post.isLiked ? '좋아요 취소' : '좋아요',
                            onPressed: () {
                              state.togglePostLike(post);
                              HapticFeedback.selectionClick();
                            },
                            icon: Icon(
                              post.isLiked
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: post.isLiked
                                  ? Theme.of(context).colorScheme.error
                                  : null,
                            ),
                          ),
                          Text('${post.likes}'),
                          const SizedBox(width: SetflowSpacing.md),
                          const Icon(Icons.chat_bubble_outline_rounded),
                          const SizedBox(width: SetflowSpacing.sm),
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
                              style: Theme.of(context).textTheme.bodySmall,
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
  const ConsultationCreateScreen({this.initialTrainer, super.key});

  final String? initialTrainer;

  @override
  State<ConsultationCreateScreen> createState() =>
      _ConsultationCreateScreenState();
}

class _ConsultationCreateScreenState extends State<ConsultationCreateScreen> {
  final formKey = GlobalKey<FormState>();
  final goalController = TextEditingController();
  final levelController = TextEditingController();
  final questionController = TextEditingController();
  late String trainer;
  bool isSubmitting = false;

  static const trainers = {
    '김코치': '초보자 근력 향상',
    '레이나 코치': '바디프로필 · 체지방 감량',
    '박트레이너': '직장인 단기 루틴',
  };

  @override
  void initState() {
    super.initState();
    trainer = trainers.containsKey(widget.initialTrainer)
        ? widget.initialTrainer!
        : trainers.keys.first;
  }

  @override
  void dispose() {
    goalController.dispose();
    levelController.dispose();
    questionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    setState(() => isSubmitting = true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    AppScope.of(context).addConsultation(
      trainerName: trainer,
      specialty: trainers[trainer]!,
      goal: goalController.text.trim(),
      level: levelController.text.trim(),
      question: questionController.text.trim(),
    );
    HapticFeedback.lightImpact();
    Navigator.pop(context, true);
  }

  String? _validate(String? value, String label, int minimum) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '$label 내용을 입력해주세요.';
    if (text.length < minimum) return '$label을 $minimum자 이상 입력해주세요.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('새 상담 신청')),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Text(
              '현재 상태를 자세히 알려주시면\n더 정확한 답변을 받을 수 있어요.',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                height: 1.25,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: SetflowSpacing.xl),
            DropdownButtonFormField<String>(
              initialValue: trainer,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '상담 트레이너'),
              items: trainers.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text('${entry.key} · ${entry.value}'),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => trainer = value ?? trainer),
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
            const SizedBox(height: SetflowSpacing.xl),
            AppButton(
              label: '상담 신청하기',
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

class ConsultationDetailScreen extends StatefulWidget {
  const ConsultationDetailScreen({required this.consultation, super.key});

  final ConsultationData consultation;

  @override
  State<ConsultationDetailScreen> createState() =>
      _ConsultationDetailScreenState();
}

class _ConsultationDetailScreenState extends State<ConsultationDetailScreen> {
  Future<void> _startCoaching() async {
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
                    color: context.setflowColors.orange,
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

  @override
  Widget build(BuildContext context) {
    final consultation = widget.consultation;
    final (statusLabel, statusColor) = _consultationStatusChip(
      context,
      consultation.status,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('상담 상세')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Row(
            children: [
              StatusChip(label: statusLabel, color: statusColor),
              const SizedBox(width: SetflowSpacing.sm),
              Text(
                '${DateFormat('yyyy.MM.dd').format(consultation.createdAt)} 신청',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                      TintedIconBadge(
                        icon: Icons.person_rounded,
                        color: context.setflowColors.blue,
                        size: 40,
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
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.verified_rounded,
                        color: context.setflowColors.blue,
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
                    Text(
                      '4주 1:1 비동기 코칭',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: SetflowSpacing.sm),
                    Text(
                      '맞춤 루틴 · 주 1회 피드백 · 72시간 응답 보장',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: SetflowSpacing.lg),
                    Row(
                      children: [
                        Text(
                          '149,000원',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const Spacer(),
                        AppButton(
                          expanded: false,
                          label: '코칭 시작',
                          onPressed: _startCoaching,
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else ...[
              InfoBanner(
                message: '코칭이 진행 중입니다. 결제 금액은 에스크로로 안전하게 보호됩니다.',
                icon: Icons.verified_user_outlined,
                color: context.setflowColors.success,
              ),
              const SizedBox(height: SetflowSpacing.md),
              AppButton(
                label: consultation.rating == null
                    ? '코칭 만족도 남기기'
                    : '만족도 ${consultation.rating}점 전송 완료',
                variant: AppButtonVariant.outlined,
                onPressed: consultation.rating == null ? _rate : null,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

(String, Color) _consultationStatusChip(
  BuildContext context,
  ConsultationStatus status,
) => switch (status) {
  ConsultationStatus.waiting => ('답변 대기', context.setflowColors.orange),
  ConsultationStatus.answered => ('상담 완료', context.setflowColors.success),
  ConsultationStatus.coaching => ('코칭 중', context.setflowColors.info),
};

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
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: SetflowSpacing.xs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(SetflowSpacing.md),
            decoration: BoxDecoration(
              color: highlighted
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: .12)
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
