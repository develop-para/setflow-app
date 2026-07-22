import 'package:flutter/material.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class DailyWorkoutScreen extends StatelessWidget {
  const DailyWorkoutScreen({required this.date, super.key});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final session = state.sessionFor(date);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${date.month}월 ${date.day}일 (${['월', '화', '수', '목', '금', '토', '일'][date.weekday - 1]})',
        ),
        actions: [
          IconButton(
            onPressed: () => showMessage(context, '운동 메모를 저장할 수 있습니다.'),
            icon: const Icon(Icons.note_alt_outlined),
          ),
          IconButton(
            onPressed: () => showMessage(context, '오늘 기록 공유 링크를 준비했습니다.'),
            icon: const Icon(Icons.ios_share_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: SetflowColors.primary,
        foregroundColor: SetflowColors.ink,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ExerciseLibraryScreen(date: date)),
        ),
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
            child: Row(
              children: [
                MetricCard(
                  label: '총 볼륨',
                  value: session.volume > 1000
                      ? (session.volume / 1000).toStringAsFixed(1)
                      : session.volume.toStringAsFixed(0),
                  suffix: session.volume > 1000 ? 't' : state.weightUnit,
                  icon: Icons.monitor_weight_outlined,
                  tint: SetflowColors.teal,
                ),
                const SizedBox(width: 10),
                MetricCard(
                  label: '완료 세트',
                  value: '${session.completedSets}',
                  suffix: '/ ${session.totalSets}',
                  icon: Icons.check_circle_outline_rounded,
                  tint: SetflowColors.orange,
                ),
              ],
            ),
          ),
          Expanded(
            child: session.exercises.isEmpty
                ? const EmptyState(
                    icon: Icons.fitness_center_rounded,
                    title: '오늘은 어떤 운동을 할까요?',
                    message: '오른쪽 아래 + 버튼을 눌러\n운동을 추가해보세요.',
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 100),
                    itemCount: session.exercises.length,
                    onReorderItem: (oldIndex, newIndex) =>
                        state.reorderExercise(session, oldIndex, newIndex),
                    itemBuilder: (_, index) {
                      final exercise = session.exercises[index];
                      return Padding(
                        key: ValueKey(exercise.id),
                        padding: const EdgeInsets.only(bottom: 13),
                        child: _ExerciseCard(date: date, exercise: exercise),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.date, required this.exercise});
  final DateTime date;
  final WorkoutExercise exercise;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return SetflowCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    ExerciseSetScreen(date: date, exercise: exercise),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: SetflowColors.primary.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      exercise.template.icon,
                      color: SetflowColors.orange,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          exercise.template.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          exercise.template.muscle,
                          style: const TextStyle(
                            fontSize: 11,
                            color: SetflowColors.secondaryText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.drag_handle_rounded,
                    color: SetflowColors.disabled,
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white10
                  : SetflowColors.soft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 42,
                  child: Center(
                    child: Text(
                      '세트',
                      style: TextStyle(
                        fontSize: 10,
                        color: SetflowColors.secondaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '무게',
                      style: TextStyle(
                        fontSize: 10,
                        color: SetflowColors.secondaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '횟수',
                      style: TextStyle(
                        fontSize: 10,
                        color: SetflowColors.secondaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Center(
                    child: Text(
                      '완료',
                      style: TextStyle(
                        fontSize: 10,
                        color: SetflowColors.secondaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final set in exercise.sets)
            InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ExerciseSetScreen(date: date, exercise: exercise),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    SizedBox(
                      width: 42,
                      child: Center(
                        child: Text(
                          '${set.number}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          '${set.weight.toStringAsFixed(set.weight % 1 == 0 ? 0 : 1)} ${state.weightUnit}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: set.completed
                                ? SetflowColors.secondaryText
                                : null,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          '${set.reps} 회',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: set.completed
                                ? SetflowColors.secondaryText
                                : null,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Center(
                        child: Checkbox(
                          value: set.completed,
                          activeColor: SetflowColors.teal,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          onChanged: (_) => state.toggleSet(set),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          TextButton.icon(
            onPressed: () => state.addSet(exercise),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('세트 추가'),
          ),
        ],
      ),
    );
  }
}

class ExerciseLibraryScreen extends StatefulWidget {
  const ExerciseLibraryScreen({required this.date, super.key});
  final DateTime date;

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  String search = '';
  String muscle = '전체';
  final selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final filtered = state.exercises.where((item) {
      final matchesSearch =
          item.name.toLowerCase().contains(search.toLowerCase()) ||
          item.muscle.contains(search);
      final matchesMuscle = muscle == '전체' || item.muscle == muscle;
      return matchesSearch && matchesMuscle;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('운동 선택'),
        actions: [
          if (selected.isNotEmpty)
            TextButton(
              onPressed: () => _addSelected(context),
              child: Text('${selected.length}개 추가'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
            child: TextField(
              onChanged: (value) => setState(() => search = value),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '어떤 운동을 할까요? (한국어/영문)',
              ),
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              children: ['전체', '가슴', '등', '어깨', '하체', '팔', '복근', '유산소']
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(item),
                        selected: muscle == item,
                        onSelected: (_) => setState(() => muscle = item),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const Divider(height: 14),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 100),
              itemCount: filtered.length + 1,
              itemBuilder: (_, index) {
                if (index == filtered.length) {
                  return Padding(
                    padding: const EdgeInsets.all(8),
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          showMessage(context, '커스텀 운동 입력 폼을 준비했습니다.'),
                      icon: const Icon(Icons.add),
                      label: const Text('새로운 운동 만들기'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  );
                }
                final exercise = filtered[index];
                final isSelected = selected.contains(exercise.id);
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: SetflowColors.soft,
                    child: Icon(
                      exercise.icon,
                      color: SetflowColors.secondaryText,
                    ),
                  ),
                  title: Text(
                    exercise.name,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(exercise.muscle),
                  trailing: IconButton(
                    onPressed: () => setState(
                      () => isSelected
                          ? selected.remove(exercise.id)
                          : selected.add(exercise.id),
                    ),
                    icon: Icon(
                      isSelected
                          ? Icons.check_circle
                          : Icons.add_circle_outline,
                      color: isSelected
                          ? SetflowColors.primary
                          : SetflowColors.disabled,
                    ),
                  ),
                  onTap: () => setState(
                    () => isSelected
                        ? selected.remove(exercise.id)
                        : selected.add(exercise.id),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: selected.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addSelected(context),
              backgroundColor: SetflowColors.primary,
              foregroundColor: SetflowColors.ink,
              icon: const Icon(Icons.check),
              label: Text('${selected.length}개 운동 추가'),
            ),
    );
  }

  void _addSelected(BuildContext context) {
    final state = AppScope.of(context);
    for (final template in state.exercises.where(
      (item) => selected.contains(item.id),
    )) {
      state.addExercise(widget.date, template);
    }
    Navigator.of(context).pop();
  }
}

class ExerciseSetScreen extends StatefulWidget {
  const ExerciseSetScreen({
    required this.date,
    required this.exercise,
    super.key,
  });
  final DateTime date;
  final WorkoutExercise exercise;

  @override
  State<ExerciseSetScreen> createState() => _ExerciseSetScreenState();
}

class _ExerciseSetScreenState extends State<ExerciseSetScreen> {
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final exercise = widget.exercise;
    final best = exercise.sets.fold<double>(
      0,
      (value, set) => set.weight > value ? set.weight : value,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(exercise.template.name),
        actions: [
          IconButton(
            onPressed: () => showMessage(context, '운동 기록 히스토리를 불러왔습니다.'),
            icon: const Icon(Icons.history_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SetflowColors.primary.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.trending_up_rounded,
                  color: SetflowColors.orange,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '이전 최고 기록',
                        style: TextStyle(
                          fontSize: 11,
                          color: SetflowColors.secondaryText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${best.toStringAsFixed(0)} ${state.weightUnit} × 10회',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const Text(
                  '+5.0kg',
                  style: TextStyle(
                    color: SetflowColors.green,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Row(
            children: [
              SizedBox(
                width: 44,
                child: Center(
                  child: Text(
                    '세트',
                    style: TextStyle(
                      fontSize: 11,
                      color: SetflowColors.secondaryText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '무게',
                    style: TextStyle(
                      fontSize: 11,
                      color: SetflowColors.secondaryText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '횟수',
                    style: TextStyle(
                      fontSize: 11,
                      color: SetflowColors.secondaryText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 50,
                child: Center(
                  child: Text(
                    '완료',
                    style: TextStyle(
                      fontSize: 11,
                      color: SetflowColors.secondaryText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final set in exercise.sets)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SetflowCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                color: set.completed
                    ? SetflowColors.teal.withValues(alpha: .1)
                    : null,
                child: Column(
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 36,
                          child: Center(
                            child: Text(
                              '${set.number}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: _NumberStepper(
                            value: set.weight.toStringAsFixed(
                              set.weight % 1 == 0 ? 0 : 1,
                            ),
                            suffix: state.weightUnit,
                            onMinus: () =>
                                state.updateSet(set, weight: set.weight - 2.5),
                            onPlus: () =>
                                state.updateSet(set, weight: set.weight + 2.5),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: _NumberStepper(
                            value: '${set.reps}',
                            suffix: '회',
                            onMinus: () =>
                                state.updateSet(set, reps: set.reps - 1),
                            onPlus: () =>
                                state.updateSet(set, reps: set.reps + 1),
                          ),
                        ),
                        SizedBox(
                          width: 50,
                          child: Checkbox(
                            value: set.completed,
                            activeColor: SetflowColors.teal,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(7),
                            ),
                            onChanged: (_) => state.toggleSet(set),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const SizedBox(width: 36),
                        for (final type in ['일반', '웜업', '드랍', '실패'])
                          Padding(
                            padding: const EdgeInsets.only(right: 5),
                            child: ChoiceChip(
                              label: Text(
                                type,
                                style: const TextStyle(fontSize: 10),
                              ),
                              selected: set.type == type,
                              visualDensity: VisualDensity.compact,
                              onSelected: (_) =>
                                  state.updateSet(set, type: type),
                            ),
                          ),
                        const Spacer(),
                        Text(
                          '1RM ${(set.weight * (1 + set.reps / 30)).toStringAsFixed(1)}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: SetflowColors.secondaryText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: () => state.addSet(exercise),
            icon: const Icon(Icons.add),
            label: const Text('세트 추가'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(17),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const SetflowCard(
            child: Row(
              children: [
                Icon(Icons.info_outline, color: SetflowColors.blue),
                SizedBox(width: 11),
                Expanded(
                  child: Text(
                    '완료 체크 한 번으로 기록 저장, 볼륨 계산, 휴식 타이머가 동시에 시작됩니다.',
                    style: TextStyle(
                      color: SetflowColors.secondaryText,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberStepper extends StatelessWidget {
  const _NumberStepper({
    required this.value,
    required this.suffix,
    required this.onMinus,
    required this.onPlus,
  });
  final String value;
  final String suffix;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white10
            : SetflowColors.soft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          InkWell(
            onTap: onMinus,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(5),
              child: Icon(Icons.remove, size: 15),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  suffix,
                  style: const TextStyle(
                    fontSize: 8,
                    color: SetflowColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: onPlus,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(5),
              child: Icon(Icons.add, size: 15),
            ),
          ),
        ],
      ),
    );
  }
}
