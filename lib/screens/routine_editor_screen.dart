import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class RoutineEditorScreen extends StatefulWidget {
  const RoutineEditorScreen({required this.routine, super.key});

  final RoutineData routine;

  @override
  State<RoutineEditorScreen> createState() => _RoutineEditorScreenState();
}

class _RoutineEditorScreenState extends State<RoutineEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late List<ExerciseTemplate> _exercises;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.routine.name);
    _descriptionController = TextEditingController(
      text: widget.routine.description,
    );
    _exercises = List.of(widget.routine.exercises);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('루틴 편집')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
            children: [
              AppTextField(
                controller: _nameController,
                label: '루틴 이름',
                textInputAction: TextInputAction.next,
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.length < 2) return '루틴 이름을 2자 이상 입력해주세요.';
                  if (text.length > 30) return '루틴 이름은 30자 이하로 입력해주세요.';
                  return null;
                },
              ),
              const SizedBox(height: SetflowSpacing.md),
              AppTextField(
                controller: _descriptionController,
                label: '설명',
                minLines: 2,
                maxLines: 4,
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.length < 5) return '설명을 5자 이상 입력해주세요.';
                  if (text.length > 120) return '설명은 120자 이하로 입력해주세요.';
                  return null;
                },
              ),
              const SizedBox(height: SetflowSpacing.xxl),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '운동 구성 ${_exercises.length}개',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    '핸들을 끌어 순서 변경',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SetflowSpacing.sm),
              if (_exercises.isEmpty)
                Container(
                  padding: const EdgeInsets.all(SetflowSpacing.xl),
                  decoration: BoxDecoration(
                    color: context.setflowColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(SetflowRadii.md),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: const Text(
                    '운동을 한 개 이상 추가해주세요.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: _exercises.length,
                  onReorderItem: _reorder,
                  itemBuilder: (context, index) {
                    final exercise = _exercises[index];
                    return Padding(
                      key: ValueKey(exercise.id),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: context.setflowColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(SetflowRadii.md),
                        child: ListTile(
                          leading: Icon(
                            exercise.icon,
                            color: widget.routine.color,
                          ),
                          title: Text(
                            exercise.name,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(exercise.muscle),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '${exercise.name} 제거',
                                onPressed: () =>
                                    setState(() => _exercises.removeAt(index)),
                                icon: const Icon(
                                  Icons.remove_circle_outline_rounded,
                                  color: SetflowColors.red,
                                ),
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Icon(Icons.drag_handle_rounded),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: SetflowSpacing.sm),
              AppButton(
                label: '운동 추가·삭제',
                icon: Icons.playlist_add_rounded,
                variant: AppButtonVariant.outlined,
                onPressed: _chooseExercises,
              ),
              const SizedBox(height: SetflowSpacing.xl),
              AppButton(
                label: _saving ? '저장 중...' : '변경사항 저장',
                icon: Icons.save_rounded,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final exercise = _exercises.removeAt(oldIndex);
      _exercises.insert(newIndex, exercise);
    });
  }

  Future<void> _chooseExercises() async {
    final catalog = AppScope.of(context).exercises;
    final selected = await showSetflowSheet<List<ExerciseTemplate>>(
      context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RoutineExercisePickerSheet(
        catalog: catalog,
        initialSelection: _exercises,
      ),
    );
    if (selected != null && mounted) setState(() => _exercises = selected);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_exercises.isEmpty) {
      AppSnackbar.error(context, '루틴에는 운동이 한 개 이상 필요해요.');
      return;
    }
    setState(() => _saving = true);
    bool updated;
    try {
      updated = await AppScope.of(context).updateRoutine(
        routine: widget.routine,
        name: _nameController.text,
        description: _descriptionController.text,
        exercises: _exercises,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppSnackbar.error(context, '루틴을 서버에 저장하지 못했어요. 다시 시도해주세요.');
      return;
    }
    if (!mounted) return;
    if (!updated) {
      setState(() => _saving = false);
      AppSnackbar.error(context, '루틴을 저장하지 못했어요.');
      return;
    }
    Navigator.of(context).pop(true);
  }
}

class _RoutineExercisePickerSheet extends StatefulWidget {
  const _RoutineExercisePickerSheet({
    required this.catalog,
    required this.initialSelection,
  });

  final List<ExerciseTemplate> catalog;
  final List<ExerciseTemplate> initialSelection;

  @override
  State<_RoutineExercisePickerSheet> createState() =>
      _RoutineExercisePickerSheetState();
}

class _RoutineExercisePickerSheetState
    extends State<_RoutineExercisePickerSheet> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _searchFieldKey = GlobalKey();
  late final Set<String> _selectedIds = widget.initialSelection
      .map((exercise) => exercise.id)
      .toSet();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.catalog.where((exercise) {
      final query = _search.trim().toLowerCase();
      return query.isEmpty ||
          exercise.name.toLowerCase().contains(query) ||
          exercise.muscle.toLowerCase().contains(query);
    }).toList();
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final sheetHeight =
                constraints.maxHeight * (keyboardInset > 0 ? 1 : .78);
            final compactHeight = sheetHeight < 320;
            return SizedBox(
              height: sheetHeight,
              child: compactHeight
                  ? CustomScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      slivers: [
                        SliverToBoxAdapter(child: _buildHeader()),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) =>
                                  _buildExerciseTile(filtered[index]),
                              childCount: filtered.length,
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(child: _buildFooter()),
                      ],
                    )
                  : Column(
                      children: [
                        _buildHeader(),
                        Expanded(
                          child: ListView.builder(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) =>
                                _buildExerciseTile(filtered[index]),
                          ),
                        ),
                        _buildFooter(),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '루틴 운동 선택',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: SetflowSpacing.md),
          AppTextField(
            key: _searchFieldKey,
            controller: _searchController,
            focusNode: _searchFocusNode,
            label: '운동 검색',
            prefixIcon: const Icon(Icons.search_rounded),
            onChanged: (value) => setState(() => _search = value),
          ),
        ],
      ),
    );
  }

  Widget _buildExerciseTile(ExerciseTemplate exercise) {
    final selected = _selectedIds.contains(exercise.id);
    return CheckboxListTile(
      value: selected,
      onChanged: (_) => setState(
        () => selected
            ? _selectedIds.remove(exercise.id)
            : _selectedIds.add(exercise.id),
      ),
      secondary: Icon(exercise.icon),
      title: Text(exercise.name),
      subtitle: Text(exercise.muscle),
      controlAffinity: ListTileControlAffinity.trailing,
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: AppButton(
        label: '선택 완료 (${_selectedIds.length})',
        onPressed: _selectedIds.isEmpty ? null : _finish,
      ),
    );
  }

  void _finish() {
    final current = widget.initialSelection
        .where((exercise) => _selectedIds.contains(exercise.id))
        .toList();
    final currentIds = current.map((exercise) => exercise.id).toSet();
    final additions = widget.catalog.where(
      (exercise) =>
          _selectedIds.contains(exercise.id) &&
          !currentIds.contains(exercise.id),
    );
    Navigator.of(
      context,
    ).pop<List<ExerciseTemplate>>([...current, ...additions]);
  }
}
