import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/local_equipment_repository.dart';
import '../data/machine_exercise_catalog.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/equipment_backup_files.dart';
import '../services/post_media_picker.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/common.dart';

class LocalEquipmentScreen extends StatefulWidget {
  const LocalEquipmentScreen({
    super.key,
    this.date,
    this.photoPicker,
    this.backupFiles,
  });
  final DateTime? date;
  final PostMediaPicker? photoPicker;
  final EquipmentBackupFiles? backupFiles;

  @override
  State<LocalEquipmentScreen> createState() => _LocalEquipmentScreenState();
}

class _LocalEquipmentScreenState extends State<LocalEquipmentScreen> {
  String query = '';
  String? muscle;
  bool busy = false;

  Future<void> edit([LocalEquipment? item]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            EquipmentEditorScreen(item: item, photoPicker: widget.photoPicker),
      ),
    );
  }

  Future<void> backup(bool restore) async {
    final state = AppScope.of(context);
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() => busy = true);
    try {
      final files = widget.backupFiles ?? PlatformEquipmentBackupFiles();
      if (restore) {
        final source = await files.import();
        if (source == null || !mounted) return;
        final incoming = EquipmentBackupCodec.decode(source);
        final approved = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('기구 복원'),
            content: Text(
              '${incoming.length}개 기구와 사진을 불러올까요? 같은 ID의 기구는 현재 내용을 유지해요. 운동 기록은 이 백업에 포함되지 않아요.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('복원'),
              ),
            ],
          ),
        );
        if (approved != true || !mounted) return;
        final count = await state.restoreEquipment(source);
        if (mounted) AppSnackbar.success(context, '$count개 기구를 복원했어요.');
      } else {
        await files.export(
          EquipmentBackupCodec.encode(state.localEquipment),
          origin,
        );
      }
    } catch (error) {
      if (mounted) {
        AppSnackbar.error(
          context,
          error is FormatException
              ? error.message
              : '백업 파일을 처리하지 못했어요. 다시 시도해주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final items = state.localEquipment
        .where(
          (item) =>
              (muscle == null || item.muscle == muscle) &&
              query
                  .toLowerCase()
                  .split(RegExp(r'\s+'))
                  .every(
                    (word) =>
                        '${item.name} ${item.muscle} ${item.brand} ${item.model} ${item.notes}'
                            .toLowerCase()
                            .contains(word),
                  ),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 기구'),
        actions: [
          IconButton(
            tooltip: '기구 등록',
            onPressed: busy ? null : edit,
            icon: const Icon(SetflowIcons.addExercise),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: SetflowInsets.pageList,
          children: [
            const Text(
              '사진과 기구 정보는 이 기기에 보관해요. 기기를 바꾸기 전 사진을 포함한 백업 파일을 저장해주세요.',
            ),
            const SizedBox(height: SetflowSpacing.sm),
            Wrap(
              spacing: SetflowSpacing.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: busy || state.localEquipmentError != null
                      ? null
                      : () => backup(false),
                  icon: const Icon(SetflowIcons.backup),
                  label: const Text('사진 포함 백업'),
                ),
                OutlinedButton.icon(
                  onPressed: busy || state.localEquipmentError != null
                      ? null
                      : () => backup(true),
                  icon: const Icon(SetflowIcons.restore),
                  label: const Text('백업 복원'),
                ),
              ],
            ),
            if (busy) const LinearProgressIndicator(),
            if (state.localEquipmentError != null) ...[
              const Text('기구 목록을 읽지 못했어요. 저장된 자료를 보호하려고 등록을 잠시 멈췄어요.'),
              TextButton(
                onPressed: state.loadLocalEquipment,
                child: const Text('다시 불러오기'),
              ),
            ],
            const SizedBox(height: SetflowSpacing.md),
            TextField(
              decoration: const InputDecoration(labelText: '기구·브랜드·메모 검색'),
              onChanged: (value) => setState(() => query = value),
            ),
            const SizedBox(height: SetflowSpacing.sm),
            Wrap(
              spacing: SetflowSpacing.sm,
              children: [
                for (final category in ['전체', ...EquipmentBackupCodec.muscles])
                  FilterChip(
                    label: Text(
                      category,
                      style: TextStyle(
                        color: (muscle ?? '전체') == category
                            ? Theme.of(context).colorScheme.onPrimary
                            : null,
                      ),
                    ),
                    checkmarkColor: Theme.of(context).colorScheme.onPrimary,
                    selected: (muscle ?? '전체') == category,
                    onSelected: (_) => setState(
                      () => muscle = category == '전체' ? null : category,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: SetflowSpacing.md),
            if (items.isEmpty) ...[
              Text(
                state.localEquipment.isEmpty
                    ? '우리 헬스장의 기구를 사진으로 등록해보세요.'
                    : '조건에 맞는 기구가 없어요.',
              ),
              const SizedBox(height: SetflowSpacing.md),
              FilledButton(
                onPressed: state.localEquipmentError != null ? null : edit,
                child: const Text('기구 등록'),
              ),
            ],
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: SetflowSpacing.md),
                child: SetflowCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.photo != null)
                        EquipmentPhoto(bytes: item.photo!),
                      Text(
                        item.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        [
                          item.muscle,
                          item.brand,
                          item.model,
                        ].where((part) => part.isNotEmpty).join(' · '),
                      ),
                      if (item.notes.isNotEmpty) Text(item.notes),
                      Wrap(
                        spacing: SetflowSpacing.sm,
                        children: [
                          TextButton(
                            onPressed: () => edit(item),
                            child: const Text('사진·설정 수정'),
                          ),
                          if (widget.date != null)
                            FilledButton(
                              onPressed: () {
                                state.addExercise(widget.date!, item.exercise);
                                AppSnackbar.success(
                                  context,
                                  '${item.name}을 운동에 추가했어요.',
                                );
                              },
                              child: const Text('오늘 운동에 추가'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class EquipmentPhoto extends StatelessWidget {
  const EquipmentPhoto({required this.bytes, super.key});
  final Uint8List bytes;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: SetflowSpacing.md),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(SetflowRadii.md),
      child: Image.memory(
        bytes,
        height: 200,
        width: double.infinity,
        fit: BoxFit.contain,
        semanticLabel: '직접 등록한 기구 사진',
        errorBuilder: (_, _, _) => const Text('사진을 표시할 수 없어요. 사진을 다시 선택해주세요.'),
      ),
    ),
  );
}

class EquipmentEditorScreen extends StatefulWidget {
  const EquipmentEditorScreen({super.key, this.item, this.photoPicker});
  final LocalEquipment? item;
  final PostMediaPicker? photoPicker;
  @override
  State<EquipmentEditorScreen> createState() => _EquipmentEditorScreenState();
}

class _EquipmentEditorScreenState extends State<EquipmentEditorScreen> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.item?.name);
  late final brand = TextEditingController(text: widget.item?.brand);
  late final model = TextEditingController(text: widget.item?.model);
  late final notes = TextEditingController(text: widget.item?.notes);
  late String muscle = widget.item?.muscle ?? '가슴';
  late ExerciseMeasurement measurement =
      widget.item?.measurement ?? ExerciseMeasurement.weightReps;
  late Uint8List? photo = widget.item?.photo;
  late final picker = widget.photoPicker ?? ImagePickerPostMediaPicker();
  MachineExercise? catalogSelection;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    recoverPhoto();
  }

  Future<void> recoverPhoto() async {
    try {
      final recovered = await picker.recoverLostImage();
      if (mounted && recovered != null && photo == null) {
        setState(() => photo = recovered.bytes);
      }
    } catch (_) {
      // An unavailable platform recovery API must not prevent manual selection.
    }
  }

  Future<void> pickPhoto(PostMediaSource source) async {
    setState(() => busy = true);
    try {
      final picked = await picker.pick(source);
      if (picked != null && mounted) {
        if (picked.bytes.length > EquipmentBackupCodec.maxPhotoBytes) {
          throw const FormatException('사진은 4MB 이하여야 해요.');
        }
        setState(() => photo = picked.bytes);
      }
    } catch (_) {
      if (mounted) {
        AppSnackbar.error(context, '사진을 가져오지 못했어요. 카메라 권한을 확인하거나 앨범에서 선택해주세요.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (!(form.currentState?.validate() ?? false)) return;
    final state = AppScope.of(context);
    setState(() => busy = true);
    try {
      await state.saveLocalEquipment(
        LocalEquipment(
          id:
              widget.item?.id ??
              'equipment_${DateTime.now().microsecondsSinceEpoch}',
          name: name.text.trim(),
          muscle: muscle,
          brand: brand.text.trim(),
          model: model.text.trim(),
          notes: notes.text.trim(),
          photo: photo,
          measurement: measurement,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) AppSnackbar.error(context, '기구를 기기에 저장하지 못했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [name, brand, model, notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.item == null ? '기구 등록' : '기구 수정')),
    body: SafeArea(
      top: false,
      child: Form(
        key: form,
        child: ListView(
          padding: SetflowInsets.pageForm,
          children: [
            const Text('사진·좌석 높이·그립을 남기면 다음에도 같은 기구와 설정으로 기록할 수 있어요.'),
            const SizedBox(height: SetflowSpacing.md),
            if (widget.item == null) ...[
              Autocomplete<MachineExercise>(
                displayStringForOption: (item) => item.exercise.name,
                optionsBuilder: (value) => value.text.trim().isEmpty
                    ? const Iterable<MachineExercise>.empty()
                    : machineCatalog
                          .where(
                            (item) =>
                                item.exercise.matchesCatalogQuery(value.text),
                          )
                          .take(12),
                fieldViewBuilder:
                    (context, controller, focusNode, onSubmitted) => TextField(
                      controller: controller,
                      focusNode: focusNode,
                      enabled: !busy,
                      decoration: const InputDecoration(
                        labelText: '브랜드·모델로 찾아 채우기',
                        hintText: '예: 뉴텍 어드벤스, 파나타 하이 로우',
                      ),
                    ),
                onSelected: (item) => setState(() {
                  name.text = item.exercise.name;
                  brand.text = item.brand;
                  model.text = '${item.line} · ${item.model}';
                  muscle = item.muscle;
                  measurement = ExerciseMeasurement.weightReps;
                  catalogSelection = item;
                  FocusManager.instance.primaryFocus?.unfocus();
                }),
              ),
              const SizedBox(height: SetflowSpacing.md),
            ],
            if (catalogSelection case final item?) ...[
              Text(
                '${item.model} · ${item.focus}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Text('같은 부위라도 기구의 궤도와 좌석·그립 설정이 달라요. 내 설정은 아래 메모에 남겨주세요.'),
              TextButton(
                onPressed: () async {
                  try {
                    if (!await launchUrl(Uri.parse(item.sourceUrl))) {
                      throw StateError('launch failed');
                    }
                  } catch (_) {
                    if (context.mounted) {
                      AppSnackbar.error(context, '제조사 페이지를 열지 못했어요.');
                    }
                  }
                },
                child: const Text('제조사 기구 정보'),
              ),
              const SizedBox(height: SetflowSpacing.md),
            ],
            if (photo != null) EquipmentPhoto(bytes: photo!),
            Wrap(
              spacing: SetflowSpacing.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => pickPhoto(PostMediaSource.camera),
                  icon: const Icon(SetflowIcons.camera),
                  label: const Text('사진 촬영'),
                ),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => pickPhoto(PostMediaSource.gallery),
                  icon: const Icon(SetflowIcons.gallery),
                  label: const Text('앨범에서 선택'),
                ),
                if (photo != null)
                  TextButton(
                    onPressed: busy ? null : () => setState(() => photo = null),
                    child: const Text('사진 제거'),
                  ),
              ],
            ),
            const SizedBox(height: SetflowSpacing.md),
            for (final (controller, label, limit) in [
              (name, '기구 이름', 80),
              (brand, '브랜드', 80),
              (model, '모델·제품군', 100),
              (notes, '헬스장·좌석·그립 메모', 1000),
            ]) ...[
              TextFormField(
                key: ValueKey('equipment-field-$label'),
                controller: controller,
                enabled: !busy,
                maxLength: limit,
                maxLines: controller == notes ? 3 : 1,
                decoration: InputDecoration(labelText: label),
                validator: (value) =>
                    controller == name && (value?.trim().isEmpty ?? true)
                    ? '기구 이름을 입력해주세요.'
                    : null,
              ),
              const SizedBox(height: SetflowSpacing.sm),
            ],
            DropdownButtonFormField<String>(
              key: ValueKey(muscle),
              initialValue: muscle,
              decoration: const InputDecoration(labelText: '운동 부위'),
              items: EquipmentBackupCodec.muscles
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: busy
                  ? null
                  : (value) => setState(() => muscle = value!),
            ),
            const SizedBox(height: SetflowSpacing.md),
            Wrap(
              spacing: SetflowSpacing.sm,
              children: [
                for (final (value, label) in [
                  (ExerciseMeasurement.weightReps, '무게 × 횟수'),
                  (ExerciseMeasurement.repsOnly, '횟수만'),
                  (ExerciseMeasurement.duration, '시간 버티기'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: measurement == value,
                    onSelected: busy || widget.item != null
                        ? null
                        : (_) => setState(() => measurement = value),
                  ),
              ],
            ),
            const SizedBox(height: SetflowSpacing.lg),
            FilledButton(
              onPressed: busy ? null : save,
              child: Text(busy ? '처리 중…' : '기기에 저장'),
            ),
            const SizedBox(height: SetflowSpacing.lg),
          ],
        ),
      ),
    ),
  );
}
