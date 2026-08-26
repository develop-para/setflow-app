import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'account_deletion_screen.dart';
import 'member_goal_screen.dart';
import 'recommendation_profile_screen.dart';

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
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        children: [
          Row(
            children: [
              MetricCard(
                label: '체중',
                value: latest.weight.toStringAsFixed(1),
                suffix: 'kg',
                icon: Icons.monitor_weight_outlined,
                tint: context.setflowColors.blue,
              ),
              const SizedBox(width: SetflowSpacing.sm2),
              MetricCard(
                label: '골격근량',
                value: latest.muscle.toStringAsFixed(1),
                suffix: 'kg',
                icon: Icons.fitness_center,
                tint: context.setflowColors.teal,
              ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.md),
          Row(
            children: [
              MetricCard(
                label: '체지방률',
                value: latest.fat.toStringAsFixed(1),
                suffix: '%',
                icon: Icons.water_drop_outlined,
                tint: context.setflowColors.orange,
              ),
              const SizedBox(width: SetflowSpacing.sm2),
              MetricCard(
                label: '최근 변화',
                value: '-1.5',
                suffix: 'kg',
                icon: Icons.trending_down,
                tint: context.setflowColors.success,
              ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.xxl2),
          const SectionTitle('체중 변화'),
          const SizedBox(height: SetflowSpacing.sm2),
          SetflowCard(
            // 높이를 박지 않는다. 막대는 길이가 정해져 있고 글자는 배율을 타므로,
            // Row 가 가장 큰 자식만큼 높아지게 두는 편이 어떤 배율에서도 맞다.
            // (예전엔 170을 박아두고 배율만큼 더했는데, 배율이 커질수록 어김없이 모자랐다.)
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < entries.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            '${entries[i].weight}',
                            style: const TextStyle(
                              fontSize: SetflowFontSize.small,
                              fontWeight: SetflowWeight.medium,
                            ),
                          ),
                          const SizedBox(height: SetflowSpacing.xs2),
                          Container(
                            height: 76 + i * 18,
                            decoration: BoxDecoration(
                              color: i == entries.length - 1
                                  ? SetflowColors.primary
                                  : context.setflowColors.teal.withValues(
                                      alpha: .55,
                                    ),
                              borderRadius: BorderRadius.circular(
                                SetflowRadii.sm,
                              ),
                            ),
                          ),
                          const SizedBox(height: SetflowSpacing.sm),
                          Text(
                            entries[i].date,
                            style: TextStyle(
                              fontSize: SetflowFontSize.micro,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.xxl),
          const SectionTitle('측정 기록'),
          const SizedBox(height: SetflowSpacing.sm),
          for (final entry in entries.reversed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.analytics_outlined,
                color: context.setflowColors.blue,
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
        icon: const Icon(Icons.add),
        label: const Text('직접 입력'),
      ),
    );
  }

  Future<void> _addEntry(BuildContext context) async {
    final weight = TextEditingController(text: '70.5');
    final muscle = TextEditingController(text: '32.6');
    final fat = TextEditingController(text: '19.4');
    Future<void>? sheetCompleted;
    await showSetflowSheet<void>(
      context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        sheetCompleted ??= ModalRoute.of(sheetContext)?.completed;
        return KeyboardSafeBottomSheet(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '체성분 직접 입력',
                style: TextStyle(
                  fontSize: SetflowFontSize.headlineLarge,
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
                  const SizedBox(width: SetflowSpacing.sm2),
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
        );
      },
    );
    await sheetCompleted;
    weight.dispose();
    muscle.dispose();
    fat.dispose();
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
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          InkWell(
            onTap: () =>
                showMessage(context, '기기 사진 선택기는 네이티브 권한 연결 후 활성화됩니다.'),
            borderRadius: BorderRadius.circular(SetflowRadii.xl),
            child: Container(
              height: 220,
              decoration: BoxDecoration(
                color: SetflowColors.soft,
                borderRadius: BorderRadius.circular(SetflowRadii.xl),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 42,
                    color: SetflowColors.disabled,
                  ),
                  SizedBox(height: SetflowSpacing.sm2),
                  Text(
                    '운동 사진 추가',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
          const Text('워터마크', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: SetflowSpacing.sm2),
          Wrap(
            spacing: 8,
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
          const SizedBox(height: SetflowSpacing.xxl2),
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
    return Scaffold(
      appBar: AppBar(title: const Text('김코치 상담')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
        children: [
          SetflowCard(
            child: Row(
              children: [
                Icon(Icons.person, color: context.setflowColors.blue),
                SizedBox(width: SetflowSpacing.md2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '김코치',
                            style: TextStyle(
                              fontSize: SetflowFontSize.titleLarge,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(width: SetflowSpacing.xs2),
                          Icon(
                            Icons.verified,
                            color: context.setflowColors.blue,
                            size: 17,
                          ),
                        ],
                      ),
                      Text(
                        '응답 평균 2시간 · 평점 4.9',
                        style: TextStyle(
                          fontSize: SetflowFontSize.small,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                  const Text(
                    '4주 1:1 비동기 코칭',
                    style: TextStyle(
                      fontSize: SetflowFontSize.titleLarge,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: SetflowSpacing.xs2),
                  Text(
                    '맞춤 루틴 · 주 1회 피드백 · 72시간 응답 보장',
                    style: TextStyle(
                      fontSize: SetflowFontSize.caption,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: SetflowSpacing.lg),
                  Row(
                    children: [
                      // 320px 폰에서 가격과 버튼이 같이 안 들어갔다. 줄어드는 쪽은
                      // 가격이다 — 버튼은 눌러야 하므로 크기를 지킨다.
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '149,000원',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: SetflowFontSize.headline,
                              fontWeight: SetflowWeight.display,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: SetflowSpacing.md),
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
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.setflowColors.success.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(SetflowRadii.lg),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    color: context.setflowColors.success,
                  ),
                  SizedBox(width: SetflowSpacing.sm2),
                  Expanded(
                    child: Text(
                      '코칭이 시작되었습니다. 결제 금액은 에스크로로 안전하게 보호됩니다.',
                      style: TextStyle(
                        fontSize: SetflowFontSize.caption,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
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
                  // 별 하나하나가 버튼이라, 라벨이 없으면 스크린리더에는
                  // 이름 없는 버튼 다섯 개가 나란히 놓인다.
                  tooltip: '$i점',
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
  Widget build(BuildContext context) => Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: mine ? SetflowColors.primary : SetflowColors.soft,
        borderRadius: BorderRadius.circular(SetflowRadii.lg),
      ),
      child: Text(
        text,
        style: const TextStyle(height: 1.45, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

enum SettingSection { account, workout, notifications, privacy }

class SettingDetailScreen extends StatefulWidget {
  const SettingDetailScreen({required this.section, super.key});
  final SettingSection section;

  @override
  State<SettingDetailScreen> createState() => _SettingDetailScreenState();
}

class _SettingDetailScreenState extends State<SettingDetailScreen> {
  // One field per switch. These used to be `first` and `second`, reused across
  // sections, so the same name meant RIR here and vibration there.
  bool _useRir = false;
  bool _autoStartRestTimer = true;
  bool _restTimerNotifications = true;
  bool _timerVibration = true;
  bool _shareBodyData = false;
  bool _shareWorkoutRecords = false;
  bool _marketing = false;
  bool _privacyLoaded = false;
  bool _savingPrivacy = false;
  double timer = 90;
  bool _settingsLoaded = false;
  final _nicknameController = TextEditingController();
  final _weightController = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    if (!_settingsLoaded) {
      timer = state.restDefaultSeconds.toDouble();
      switch (widget.section) {
        case SettingSection.account:
          _nicknameController.text = state.memberDisplayName;
          _weightController.text = state.weight?.toStringAsFixed(1) ?? '';
        case SettingSection.workout:
          _useRir = state.useRir;
          _autoStartRestTimer = state.autoStartRestTimer;
        case SettingSection.notifications:
          _restTimerNotifications = state.restTimerNotifications;
          _timerVibration = state.timerVibration;
        case SettingSection.privacy:
          break;
      }
      _settingsLoaded = true;
    }
    if (widget.section != SettingSection.privacy || _privacyLoaded) return;
    final preferences = state.memberSharingPreferences;
    if (preferences == null) return;
    _shareBodyData = preferences.shareBodyData;
    _shareWorkoutRecords = preferences.shareWorkoutRecords;
    _marketing = preferences.marketing;
    _privacyLoaded = true;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  String get title => switch (widget.section) {
    SettingSection.account => '계정 & 프로필',
    SettingSection.workout => '운동 기록 환경설정',
    SettingSection.notifications => '알림 설정',
    SettingSection.privacy => '데이터 & 개인정보',
  };

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          SetflowSpacing.gutter,
          6,
          SetflowSpacing.gutter,
          28,
        ),
        children: switch (widget.section) {
          SettingSection.account => [
            SetflowCard(
              child: Row(
                children: [
                  Icon(Icons.person, color: context.setflowColors.orange),
                  SizedBox(width: SetflowSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.memberDisplayName,
                          style: const TextStyle(
                            fontSize: SetflowFontSize.titleLarge,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '${state.hasPaidPlan ? '유료' : '무료'} 플랜 · 루틴 ${state.routines.length}/${state.hasPaidPlan ? '무제한' : '4'}',
                          style: TextStyle(
                            fontSize: SetflowFontSize.small,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: SetflowSpacing.lg),
            TextField(
              decoration: InputDecoration(labelText: '닉네임'),
              controller: _nicknameController,
              maxLength: 30,
            ),
            const SizedBox(height: SetflowSpacing.md),
            TextField(
              decoration: InputDecoration(labelText: '몸무게', hintText: '70.9kg'),
              controller: _weightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: SetflowSpacing.md),
            ListTile(
              leading: const Icon(Icons.track_changes_rounded),
              title: const Text('운동 목표'),
              subtitle: Text(
                state.goals.isEmpty ? '목표를 선택해주세요' : state.goals.join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MemberGoalScreen()),
              ),
            ),
            ListTile(
              key: const ValueKey('recommendation-profile-settings'),
              leading: const Icon(Icons.tune_rounded),
              title: const Text('정밀 운동 추천 정보'),
              subtitle: Text(
                state.recommendationProfile == null
                    ? '부상·통증, 장비, 숙련도와 회복 상태를 설정하세요'
                    : '${state.recommendationProfile!.experienceLevel.label} · 장비 ${state.recommendationProfile!.availableEquipment.length}개',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const RecommendationProfileScreen(),
                ),
              ),
            ),
            const SizedBox(height: SetflowSpacing.xl),
            PrimaryButton(label: '프로필 저장', onPressed: _saveAccountProfile),
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
                onChangeEnd: (value) =>
                    state.setRestDefaultSeconds(value.round()),
              ),
              trailing: Text('${timer.toInt()}초'),
            ),
            SwitchListTile(
              key: const ValueKey('setting-use-rir'),
              title: const Text('RIR 입력 필드'),
              subtitle: const Text('세트마다 «몇 회 더 할 수 있었는지»를 함께 기록해요.'),
              value: _useRir,
              onChanged: (value) {
                setState(() => _useRir = value);
                state.setUseRir(value);
              },
            ),
            SwitchListTile(
              title: const Text('세트 완료 시 자동 타이머'),
              value: _autoStartRestTimer,
              onChanged: (value) {
                setState(() => _autoStartRestTimer = value);
                state.setAutoStartRestTimer(value);
              },
            ),
            ListTile(
              key: const ValueKey('setting-one-rep-max-formula'),
              title: const Text('1RM 공식'),
              subtitle: Text(state.oneRepMaxFormula.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showFormulaSheet(context, state),
            ),
          ],
          SettingSection.notifications => [
            SwitchListTile(
              title: const Text('휴식 타이머 종료 알림'),
              value: _restTimerNotifications,
              onChanged: (value) {
                setState(() => _restTimerNotifications = value);
                state.setRestTimerNotifications(value);
              },
            ),
            SwitchListTile(
              title: const Text('진동'),
              value: _timerVibration,
              onChanged: (value) {
                setState(() => _timerVibration = value);
                state.setTimerVibration(value);
              },
            ),
            SwitchListTile(
              key: const ValueKey('setting-timer-sound'),
              title: const Text('타이머 소리'),
              subtitle: const Text('마지막 3초는 초마다, 끝나는 순간 한 번 울려요.'),
              value: state.timerSound,
              onChanged: state.setTimerSound,
            ),
            if (state.timerSound) ...[
              const ListTile(
                title: Text('카운트다운 예고'),
                subtitle: Text('휴식이 이만큼 남으면 미리 소리로 알려드려요.'),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: SetflowSpacing.md),
                child: Wrap(
                  spacing: SetflowSpacing.sm,
                  children: [
                    for (final (label, seconds) in const [
                      ('끄기', 0),
                      ('10초', 10),
                      ('20초', 20),
                      ('30초', 30),
                      ('60초', 60),
                    ])
                      ChoiceChip(
                        key: ValueKey('countdown-$seconds'),
                        label: Text(label),
                        selected: state.timerCountdownSeconds == seconds,
                        onSelected: (_) =>
                            state.setTimerCountdownSeconds(seconds),
                      ),
                  ],
                ),
              ),
            ],
            SwitchListTile(
              title: const Text('코칭 피드백 알림'),
              value: state.pushCoachingFeedback,
              onChanged: state.setPushCoachingFeedback,
            ),
            SwitchListTile(
              title: const Text('커뮤니티 반응 알림'),
              value: state.communityReactionNotifications,
              onChanged: state.setCommunityReactionNotifications,
            ),
          ],
          SettingSection.privacy => [
            SwitchListTile(
              title: const Text('담당 트레이너에게 체성분 공유'),
              subtitle: const Text('몸무게·체성분처럼 별도 동의한 정보만 공유됩니다.'),
              value: _shareBodyData,
              onChanged: _savingPrivacy
                  ? null
                  : (value) => _savePrivacy(shareBodyData: value),
            ),
            SwitchListTile(
              title: const Text('담당자에게 운동 기록 공유'),
              subtitle: const Text('운동 종목·세트·중량·횟수와 담당자 피드백에 사용됩니다.'),
              value: _shareWorkoutRecords,
              onChanged: _savingPrivacy
                  ? null
                  : (value) => _savePrivacy(shareWorkoutRecords: value),
            ),
            SwitchListTile(
              title: const Text('마케팅 정보 수신'),
              value: _marketing,
              onChanged: _savingPrivacy
                  ? null
                  : (value) => _savePrivacy(marketing: value),
            ),
            if (_savingPrivacy) const LinearProgressIndicator(),
            const Divider(height: 32),
            // '계정 비활성화'는 따로 두지 않는다 — 탈퇴의 30일 유예가 곧
            // 비활성화라서, 두 항목은 같은 것을 다르게 부르던 중복이었다.
            ListTile(
              key: const ValueKey('setting-account-deletion'),
              leading: Icon(
                Icons.delete_forever_outlined,
                color: state.supportsAccountDeletion
                    ? context.setflowColors.error
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              title: Text(
                '회원 탈퇴',
                style: TextStyle(
                  color: state.supportsAccountDeletion
                      ? context.setflowColors.error
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              subtitle: Text(
                state.supportsAccountDeletion
                    ? '30일 유예 후 삭제되고, 그 안에는 되돌릴 수 있어요.'
                    : '로그인한 계정에서만 신청할 수 있어요.',
              ),
              trailing: state.supportsAccountDeletion
                  ? const Icon(Icons.chevron_right)
                  : null,
              onTap: state.supportsAccountDeletion
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AccountDeletionScreen(),
                      ),
                    )
                  : null,
            ),
          ],
        },
      ),
    );
  }

  /// 공식은 세 개뿐이고 고른 뒤 바로 돌아가는 선택이라 화면을 하나 더 쌓지
  /// 않는다. 설명을 같이 보여주는 이유는 이름만으로는 무엇이 다른지 모르기
  /// 때문이다.
  Future<void> _showFormulaSheet(BuildContext context, AppState state) {
    return showSetflowSheet<void>(
      context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SetflowSpacing.gutter,
                SetflowSpacing.sm,
                SetflowSpacing.gutter,
                SetflowSpacing.xs,
              ),
              child: Text(
                '1RM 공식',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            RadioGroup<OneRepMaxFormula>(
              groupValue: state.oneRepMaxFormula,
              onChanged: (value) {
                if (value != null) state.setOneRepMaxFormula(value);
                Navigator.of(sheetContext).pop();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final formula in OneRepMaxFormula.values)
                    RadioListTile<OneRepMaxFormula>(
                      key: ValueKey('formula-${formula.storageKey}'),
                      value: formula,
                      title: Text(formula.label),
                      subtitle: Text(formula.description),
                    ),
                ],
              ),
            ),
            const SizedBox(height: SetflowSpacing.sm),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAccountProfile() async {
    final rawWeight = _weightController.text
        .trim()
        .replaceAll('kg', '')
        .replaceAll(',', '');
    final parsedWeight = rawWeight.isEmpty ? null : double.tryParse(rawWeight);
    if (rawWeight.isNotEmpty && parsedWeight == null) {
      AppSnackbar.error(context, '몸무게를 숫자로 입력해주세요.');
      return;
    }
    final state = AppScope.of(context);
    final updated = state.updateMemberAccountProfile(
      nickname: _nicknameController.text,
      weight: parsedWeight,
    );
    if (!updated) {
      AppSnackbar.error(context, '닉네임은 2~30자, 몸무게는 20~1000kg로 입력해주세요.');
      return;
    }
    try {
      await state.flushPersistence();
      if (mounted) AppSnackbar.success(context, '프로필을 계정에 저장했어요.');
    } catch (_) {
      if (mounted) {
        AppSnackbar.info(context, '기기에 안전하게 보관했어요. 연결되면 서버에 다시 저장합니다.');
      }
    }
  }

  Future<void> _savePrivacy({
    bool? shareBodyData,
    bool? shareWorkoutRecords,
    bool? marketing,
  }) async {
    final state = AppScope.of(context);
    final previousBody = _shareBodyData;
    final previousWorkout = _shareWorkoutRecords;
    final previousMarketing = _marketing;
    setState(() {
      _shareBodyData = shareBodyData ?? _shareBodyData;
      _shareWorkoutRecords = shareWorkoutRecords ?? _shareWorkoutRecords;
      _marketing = marketing ?? _marketing;
      _savingPrivacy = true;
    });
    if (!state.usesLiveBusinessData) {
      setState(() => _savingPrivacy = false);
      return;
    }
    try {
      await state.updateMemberSharingPreferences(
        shareBodyData: _shareBodyData,
        shareWorkoutRecords: _shareWorkoutRecords,
        marketing: _marketing,
      );
      if (!mounted) return;
      setState(() => _savingPrivacy = false);
      AppSnackbar.success(context, '공유 설정을 저장했어요.');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _shareBodyData = previousBody;
        _shareWorkoutRecords = previousWorkout;
        _marketing = previousMarketing;
        _savingPrivacy = false;
      });
      AppSnackbar.error(context, '공유 설정을 저장하지 못했어요.');
    }
  }
}
