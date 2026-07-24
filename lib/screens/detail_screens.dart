import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Volt and other bright accents need dark text, not [HeroStatBanner]'s
/// white default — pick whichever reads legibly against [background].
Color _heroForeground(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark
    ? Colors.white
    : Colors.black;

class BodyCompositionScreen extends StatefulWidget {
  const BodyCompositionScreen({super.key});

  @override
  State<BodyCompositionScreen> createState() => _BodyCompositionScreenState();
}

class _BodyCompositionScreenState extends State<BodyCompositionScreen> {
  final entries = <({String date, double weight, double muscle, double fat})>[
    (date: '5월 3일', weight: 72.4, muscle: 31.2, fat: 21.8),
    (date: '6월 2일', weight: 71.6, muscle: 31.8, fat: 20.6),
    (date: '7월 18일', weight: 70.9, muscle: 32.5, fat: 19.7),
  ];

  @override
  Widget build(BuildContext context) {
    final latest = entries.last;
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('체성분 관리'),
        actions: [
          IconButton(
            tooltip: 'OCR 촬영',
            onPressed: () => showMessage(context, 'OCR 촬영은 서버 모델 연결 후 활성화됩니다.'),
            icon: const Icon(Icons.document_scanner_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: SetflowInsets.pageListTight,
        children: [
          // Hero stat block: 체중 is the screen's key number, so it leads as
          // a solid banner; 골격근량/체지방률 stay as quieter secondary cards.
          HeroStatBanner(
            caption: '체중',
            value: '${latest.weight.toStringAsFixed(1)}kg',
            color: theme.colorScheme.primary,
            foreground: _heroForeground(theme.colorScheme.primary),
            note: '지난 측정 대비 -1.5kg',
          ),
          const SizedBox(height: SetflowSpacing.md),
          Row(
            children: [
              MetricCard(
                label: '골격근량',
                value: latest.muscle.toStringAsFixed(1),
                suffix: 'kg',
                icon: Icons.fitness_center,
                tint: SetflowColors.teal,
              ),
              const SizedBox(width: SetflowSpacing.md),
              MetricCard(
                label: '체지방률',
                value: latest.fat.toStringAsFixed(1),
                suffix: '%',
                icon: Icons.water_drop_outlined,
                tint: SetflowColors.orange,
              ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.xxl),
          const SectionTitle('체중 변화'),
          const SizedBox(height: SetflowSpacing.md),
          SetflowCard(
            child: SizedBox(
              height: 170,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < entries.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: SetflowSpacing.md),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              '${entries[i].weight}',
                              style: text.bodySmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: SetflowSpacing.xs),
                            Container(
                              height: 76 + i * 18,
                              decoration: BoxDecoration(
                                color: i == entries.length - 1
                                    ? SetflowColors.primary
                                    : SetflowColors.teal.withValues(alpha: .55),
                                borderRadius: BorderRadius.circular(SetflowRadii.sm),
                              ),
                            ),
                            const SizedBox(height: SetflowSpacing.sm),
                            Text(
                              entries[i].date,
                              style: text.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: SetflowSpacing.xxl),
          const SectionTitle('측정 기록'),
          const SizedBox(height: SetflowSpacing.sm),
          for (final entry in entries.reversed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const TintedIconBadge(
                icon: Icons.analytics_outlined,
                color: SetflowColors.blue,
              ),
              title: Text(
                entry.date,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text('골격근 ${entry.muscle}kg · 체지방 ${entry.fat}%'),
              trailing: Text(
                '${entry.weight}kg',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addEntry(context),
        backgroundColor: SetflowColors.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        icon: const Icon(Icons.add),
        label: const Text('직접 입력'),
      ),
    );
  }

  void _addEntry(BuildContext context) {
    final weight = TextEditingController(text: '70.5');
    final muscle = TextEditingController(text: '32.6');
    final fat = TextEditingController(text: '19.4');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          SetflowSpacing.xl,
          SetflowSpacing.xs,
          SetflowSpacing.xl,
          MediaQuery.viewInsetsOf(sheetContext).bottom + SetflowSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '체성분 직접 입력',
              style: Theme.of(sheetContext).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: SetflowSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: weight,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '체중(kg)'),
                  ),
                ),
                const SizedBox(width: SetflowSpacing.md),
                Expanded(
                  child: TextField(
                    controller: muscle,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '골격근량'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SetflowSpacing.md),
            TextField(
              controller: fat,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '체지방률(%)'),
            ),
            const SizedBox(height: SetflowSpacing.xl),
            PrimaryButton(
              label: '기록 저장',
              onPressed: () {
                setState(
                  () => entries.add((
                    date: '오늘',
                    weight: double.tryParse(weight.text) ?? 0,
                    muscle: double.tryParse(muscle.text) ?? 0,
                    fat: double.tryParse(fat.text) ?? 0,
                  )),
                );
                Navigator.pop(sheetContext);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class PostComposerScreen extends StatefulWidget {
  const PostComposerScreen({super.key});

  @override
  State<PostComposerScreen> createState() => _PostComposerScreenState();
}

class _PostComposerScreenState extends State<PostComposerScreen> {
  final controller = TextEditingController();
  bool includeWorkout = true;
  String watermark = '오운완';

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('게시물 작성'),
        actions: [
          TextButton(
            onPressed: controller.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, controller.text.trim()),
            child: const Text('등록'),
          ),
        ],
      ),
      body: ListView(
        padding: SetflowInsets.pageList,
        children: [
          InkWell(
            onTap: () =>
                showMessage(context, '기기 사진 선택기는 네이티브 권한 연결 후 활성화됩니다.'),
            borderRadius: BorderRadius.circular(SetflowRadii.lg),
            child: Container(
              height: 220,
              decoration: BoxDecoration(
                color: context.setflowColors.surfaceContainer,
                borderRadius: BorderRadius.circular(SetflowRadii.lg),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 42,
                    color: context.setflowColors.disabled,
                  ),
                  const SizedBox(height: SetflowSpacing.md),
                  Text(
                    '운동 사진 추가',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: SetflowSpacing.xl),
          TextField(
            controller: controller,
            onChanged: (_) => setState(() {}),
            maxLines: 5,
            decoration: const InputDecoration(hintText: '오늘 운동은 어땠나요?'),
          ),
          const SizedBox(height: SetflowSpacing.xl),
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
          const SizedBox(height: SetflowSpacing.sm),
          LabeledField(
            label: '워터마크',
            child: Wrap(
              spacing: SetflowSpacing.sm,
              children: ['오운완', 'Setflow', '기록 없음']
                  .map(
                    (item) => ChoiceChip(
                      label: Text(item),
                      selected: watermark == item,
                      onSelected: (_) => setState(() => watermark = item),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: SetflowSpacing.xxl),
          PrimaryButton(
            label: '게시하기',
            onPressed: controller.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, controller.text.trim()),
          ),
        ],
      ),
    );
  }
}

class CoachingDetailScreen extends StatefulWidget {
  const CoachingDetailScreen({super.key});

  @override
  State<CoachingDetailScreen> createState() => _CoachingDetailScreenState();
}

class _CoachingDetailScreenState extends State<CoachingDetailScreen> {
  bool purchased = false;
  bool feedbackSent = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('김코치 상담')),
      body: ListView(
        padding: SetflowInsets.pageList,
        children: [
          SetflowCard(
            child: Row(
              children: [
                const TintedIconBadge(
                  icon: Icons.person,
                  color: SetflowColors.blue,
                  size: 56,
                ),
                const SizedBox(width: SetflowSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '김코치',
                            style: text.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: SetflowSpacing.xs),
                          const Icon(
                            Icons.verified,
                            color: SetflowColors.blue,
                            size: 17,
                          ),
                        ],
                      ),
                      Text(
                        '응답 평균 2시간 · 평점 4.9',
                        style: text.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.xl),
          const _MessageBubble(
            text: '주 3회 운동이 가능한데 무릎이 불편해도 진행할 수 있을까요?',
            mine: true,
          ),
          const _MessageBubble(
            text: '가능합니다. 스쿼트 깊이와 중량을 조절하고, 레그 익스텐션 대신 둔근 중심 동작으로 구성해드릴게요.',
            mine: false,
          ),
          const SizedBox(height: SetflowSpacing.xxl),
          if (!purchased)
            SetflowCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '4주 1:1 비동기 코칭',
                    style: text.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: SetflowSpacing.xs),
                  Text(
                    '맞춤 루틴 · 주 1회 피드백 · 72시간 응답 보장',
                    style: text.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: SetflowSpacing.lg),
                  Row(
                    children: [
                      Text(
                        '149,000원',
                        style: text.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      PrimaryButton(
                        expanded: false,
                        label: '코칭 구매',
                        onPressed: () => _purchase(context),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else ...[
            const InfoBanner(
              message: '코칭이 시작되었습니다. 결제 금액은 에스크로로 안전하게 보호됩니다.',
              icon: Icons.verified_user_outlined,
              color: SetflowColors.green,
            ),
            const SizedBox(height: SetflowSpacing.lg),
            PrimaryButton(
              label: feedbackSent ? '피드백 전송 완료' : '코칭 만족도 남기기',
              onPressed: feedbackSent ? null : () => _feedback(context),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _purchase(BuildContext context) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('코칭 구매'),
            content: const Text('4주 코칭 149,000원을 결제하고 김코치를 담당 트레이너로 지정합니다.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('결제'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) setState(() => purchased = true);
  }

  Future<void> _feedback(BuildContext context) async {
    var rating = 5;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('코칭 만족도'),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  onPressed: () => setDialogState(() => rating = i),
                  icon: Icon(
                    i <= rating ? Icons.star : Icons.star_border,
                    color: SetflowColors.primary,
                  ),
                ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () {
                setState(() => feedbackSent = true);
                Navigator.pop(dialogContext);
              },
              child: const Text('전송'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.text, required this.mine});
  final String text;
  final bool mine;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: SetflowSpacing.md),
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.all(SetflowSpacing.lg),
        decoration: BoxDecoration(
          color: mine ? SetflowColors.primary : context.setflowColors.surfaceContainer,
          borderRadius: BorderRadius.circular(SetflowRadii.lg),
        ),
        child: Text(
          text,
          style: TextStyle(
            height: 1.45,
            fontWeight: FontWeight.w600,
            color: mine ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

enum SettingSection { account, workout, notifications, privacy, display }

class SettingDetailScreen extends StatefulWidget {
  const SettingDetailScreen({required this.section, super.key});
  final SettingSection section;

  @override
  State<SettingDetailScreen> createState() => _SettingDetailScreenState();
}

class _SettingDetailScreenState extends State<SettingDetailScreen> {
  bool first = true;
  bool second = false;
  double timer = 90;

  String get title => switch (widget.section) {
    SettingSection.account => '계정 & 프로필',
    SettingSection.workout => '운동 기록 환경설정',
    SettingSection.notifications => '알림 설정',
    SettingSection.privacy => '데이터 & 개인정보',
    SettingSection.display => '디스플레이',
  };

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: SetflowInsets.pageList,
        children: switch (widget.section) {
          SettingSection.account => [
            SetflowCard(
              child: Row(
                children: [
                  const TintedIconBadge(
                    icon: Icons.person,
                    color: SetflowColors.orange,
                    size: 56,
                  ),
                  const SizedBox(width: SetflowSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '운동초보',
                          style: text.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '무료 플랜 · 루틴 2/4',
                          style: text.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.edit_outlined),
                ],
              ),
            ),
            const SizedBox(height: SetflowSpacing.lg),
            const TextField(
              decoration: InputDecoration(labelText: '닉네임'),
              controller: null,
            ),
            const SizedBox(height: SetflowSpacing.md),
            const TextField(
              decoration: InputDecoration(labelText: '몸무게', hintText: '70.9kg'),
            ),
            const SizedBox(height: SetflowSpacing.md),
            const TextField(
              decoration: InputDecoration(
                labelText: '운동 목표',
                hintText: '근육 증가',
              ),
            ),
            const SizedBox(height: SetflowSpacing.xl),
            PrimaryButton(
              label: '프로필 저장',
              onPressed: () => showMessage(context, '프로필을 저장했습니다.'),
            ),
          ],
          SettingSection.workout => [
            ListTile(
              title: const Text('무게 단위'),
              trailing: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'kg', label: Text('kg')),
                  ButtonSegment(value: 'lb', label: Text('lb')),
                ],
                selected: {state.weightUnit},
                onSelectionChanged: (value) => state.setWeightUnit(value.first),
              ),
            ),
            ListTile(
              title: const Text('휴식 타이머 기본값'),
              subtitle: Slider(
                value: timer,
                min: 30,
                max: 300,
                divisions: 9,
                label: '${timer.toInt()}초',
                onChanged: (value) => setState(() => timer = value),
              ),
              trailing: Text('${timer.toInt()}초'),
            ),
            SwitchListTile(
              title: const Text('RIR 입력 필드'),
              value: first,
              onChanged: (value) => setState(() => first = value),
            ),
            SwitchListTile(
              title: const Text('세트 완료 시 자동 타이머'),
              value: second,
              onChanged: (value) => setState(() => second = value),
            ),
            const ListTile(
              title: Text('1RM 공식'),
              subtitle: Text('Epley 공식'),
              trailing: Icon(Icons.chevron_right),
            ),
          ],
          SettingSection.notifications => [
            SwitchListTile(
              title: const Text('휴식 타이머 종료 알림'),
              value: first,
              onChanged: (value) => setState(() => first = value),
            ),
            SwitchListTile(
              title: const Text('진동'),
              value: second,
              onChanged: (value) => setState(() => second = value),
            ),
            SwitchListTile(
              title: const Text('코칭 피드백 알림'),
              value: true,
              onChanged: (_) {},
            ),
            SwitchListTile(
              title: const Text('커뮤니티 반응 알림'),
              value: false,
              onChanged: (_) {},
            ),
          ],
          SettingSection.privacy => [
            SwitchListTile(
              title: const Text('담당 트레이너에게 체성분 공유'),
              subtitle: const Text('별도 동의한 데이터만 공유됩니다.'),
              value: first,
              onChanged: (value) => setState(() => first = value),
            ),
            SwitchListTile(
              title: const Text('마케팅 정보 수신'),
              value: second,
              onChanged: (value) => setState(() => second = value),
            ),
            const Divider(height: 32),
            ListTile(
              leading: const Icon(Icons.pause_circle_outline),
              title: const Text('계정 비활성화'),
              onTap: () => showMessage(context, '계정 비활성화 안내를 확인했습니다.'),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_forever_outlined,
                color: SetflowColors.red,
              ),
              title: const Text(
                '회원 탈퇴',
                style: TextStyle(color: SetflowColors.red),
              ),
              onTap: () => showMessage(context, '탈퇴는 30일 유예 후 처리됩니다.'),
            ),
          ],
          SettingSection.display => [
            RadioGroup<ThemeMode>(
              groupValue: state.themeMode,
              onChanged: (mode) {
                if (mode != null) state.setThemeMode(mode);
              },
              child: const Column(
                children: [
                  RadioListTile<ThemeMode>(
                    title: Text('시스템 설정 따름'),
                    subtitle: Text('기기 설정에 맞춰 자동 전환'),
                    value: ThemeMode.system,
                  ),
                  RadioListTile<ThemeMode>(
                    title: Text('라이트 모드'),
                    value: ThemeMode.light,
                  ),
                  RadioListTile<ThemeMode>(
                    title: Text('다크 모드'),
                    value: ThemeMode.dark,
                  ),
                ],
              ),
            ),
          ],
        },
      ),
    );
  }
}
