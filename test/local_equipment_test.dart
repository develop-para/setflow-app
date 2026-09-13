import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:image/image.dart' as image;
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/data/bodyweight_exercise_catalog.dart';
import 'package:setflow/data/community_repository.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/data/exercise_catalog_crosswalk.dart';
import 'package:setflow/data/hive_local_equipment_repository.dart';
import 'package:setflow/data/local_equipment_repository.dart';
import 'package:setflow/data/machine_exercise_catalog.dart';
import 'package:setflow/data/offline_exercise_catalog.dart';
import 'package:setflow/screens/local_equipment_screen.dart';
import 'package:setflow/services/equipment_backup_files.dart';
import 'package:setflow/services/post_media_picker.dart';
import 'package:setflow/theme.dart';

Uint8List photoBytes() =>
    Uint8List.fromList(image.encodePng(image.Image(width: 2, height: 2)));

LocalEquipment equipment({
  String id = 'equipment_test',
  String name = '우리 헬스장 로우',
  String notes = '좌석 3, 중립 그립',
  Uint8List? photo,
}) => LocalEquipment(
  id: id,
  name: name,
  muscle: '등',
  brand: '뉴텍',
  model: '로터리 로우',
  notes: notes,
  photo: photo,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'backup preserves photo bytes, identities, settings and measurements',
    () {
      final original = equipment(photo: photoBytes());
      final decoded = EquipmentBackupCodec.decode(
        EquipmentBackupCodec.encode([original]),
      ).single;
      expect(decoded.id, original.id);
      expect(decoded.name, original.name);
      expect(decoded.photo, orderedEquals(original.photo!));
      expect(decoded.brand, original.brand);
      expect(decoded.model, original.model);
      expect(decoded.notes, original.notes);
      expect(decoded.measurement, original.measurement);
    },
  );

  test('invalid backup never partially replaces the library', () async {
    final state = AppState();
    addTearDown(state.dispose);
    await state.initialize();
    await state.saveLocalEquipment(equipment());
    final valid = equipment(id: 'equipment_new').toJson();
    for (final bad in [
      {
        ...valid,
        'photo': base64Encode([1, 2, 3]),
      },
      {...valid, 'muscle': 'invalid'},
      {...valid, 'id': '../../outside'},
      {...valid, 'measurement': 'unknown'},
    ]) {
      final source = jsonEncode({
        'format': 'setflow-equipment',
        'version': 1,
        'equipment': [valid, bad],
      });
      await expectLater(state.restoreEquipment(source), throwsFormatException);
      expect(state.localEquipment.single.id, 'equipment_test');
    }
    expect(
      () => EquipmentBackupCodec.decode(
        '{"format":"setflow-equipment","version":2}',
      ),
      throwsFormatException,
    );
    expect(
      () => EquipmentBackupCodec.decode('not JSON'),
      throwsFormatException,
    );
  });

  test(
    'restore merges by stable ID and preserves newer local settings',
    () async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.initialize();
      await state.saveLocalEquipment(equipment(notes: '좌석 5'));
      final backup = EquipmentBackupCodec.encode([
        equipment(notes: '좌석 1'),
        equipment(id: 'equipment_other', photo: photoBytes()),
      ]);
      expect(await state.restoreEquipment(backup), 1);
      expect(await state.restoreEquipment(backup), 0);
      expect(state.localEquipment.first.notes, '좌석 5');
      expect(state.localEquipment.last.photo, orderedEquals(photoBytes()));
      expect(
        state.exercises
            .where((item) => item.id.startsWith('equipment_'))
            .length,
        2,
      );
    },
  );

  test(
    'failed storage write does not report or expose an unsaved machine',
    () async {
      final store = _FailingStore();
      final state = AppState(localEquipmentRepository: store);
      addTearDown(state.dispose);
      await state.initialize();
      await expectLater(
        state.saveLocalEquipment(equipment()),
        throwsStateError,
      );
      expect(state.localEquipment, isEmpty);
      expect(
        state.exercises.any((item) => item.id == 'equipment_test'),
        isFalse,
      );
    },
  );

  test(
    'Hive survives close and reopen with photos, without an account',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'setflow-equipment-test-',
      );
      Hive.init(directory.path);
      try {
        final repository = HiveLocalEquipmentRepository();
        await repository.save([equipment(photo: photoBytes())]);
        await Hive.close();
        Hive.init(directory.path);
        final reopened = await HiveLocalEquipmentRepository().load();
        expect(reopened.single.photo, orderedEquals(photoBytes()));
        expect(reopened.single.notes, equipment().notes);
      } finally {
        await Hive.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'workout survives without local equipment backup; photos and notes never enter snapshot',
    () async {
      final appStore = MemoryAppRepository();
      final localStore = MemoryLocalEquipmentRepository();
      final state = AppState(
        repository: appStore,
        localEquipmentRepository: localStore,
      );
      addTearDown(state.dispose);
      await state.initialize();
      final item = equipment(photo: photoBytes());
      await state.saveLocalEquipment(item);
      final date = DateTime(2026, 9, 13);
      state.addExercise(date, item.exercise);
      await state.flushPersistence();
      final snapshot = await appStore.load(offlineExerciseCatalog);
      final encoded = AppSnapshotCodec.encode(snapshot!);
      expect(encoded, isNot(contains(base64Encode(item.photo!))));
      expect(encoded, isNot(contains(item.notes)));
      expect(encoded, isNot(contains(item.model)));
      final decoded = AppSnapshotCodec.decode(encoded, offlineExerciseCatalog)!;
      expect(decoded.sessions[date]!.exercises.single.template.id, item.id);
      expect(decoded.sessions[date]!.exercises.single.template.name, item.name);
      final restarted = AppState(
        repository: appStore,
        localEquipmentRepository: localStore,
      );
      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(restarted.localEquipment.single.photo, orderedEquals(item.photo!));
      expect(restarted.sessions[date]!.exercises.single.template.id, item.id);
    },
  );

  test(
    'offline catalog has unique IDs and Korean model names without false generic merges',
    () {
      expect(
        offlineExerciseCatalog.map((item) => item.id).toSet().length,
        offlineExerciseCatalog.length,
      );
      expect(machineCatalog.length, 187);
      expect(bodyweightExerciseCatalog.length, 100);
      for (final item in machineCatalog) {
        expect(item.name, matches(RegExp('[가-힣]')));
        expect(item.name, isNot(contains('?')));
        expect(EquipmentBackupCodec.muscles, contains(item.muscle));
        expect(Uri.parse(item.sourceUrl).scheme, 'https');
        expect(item.exercise.id, startsWith('machine_'));
        expect(
          exerciseCatalog.any((generic) => generic.id == item.exercise.id),
          isFalse,
        );
      }
      for (final item in bodyweightExerciseCatalog) {
        expect(item.usesWeight, isFalse);
        expect(EquipmentBackupCodec.muscles, contains(item.muscle));
        expect(freeExerciseDbBuiltInIds.containsKey(item.sourceId), isFalse);
        expect(item.databaseId, item.id);
      }
      final advance = machineExerciseCatalog
          .where((item) => item.id.startsWith('machine_newtech_advance_'))
          .toList();
      expect(advance, hasLength(23));
      for (final item in advance) {
        expect(item.name, startsWith('뉴텍 어드벤스 '));
        for (final query in ['뉴텍 어드벤스', '뉴텍 어드밴스', 'Newtech ADVANCE']) {
          expect(item.matchesCatalogQuery(query), isTrue);
        }
      }
      expect(
        machineExerciseCatalog.where(
          (item) => item.matchesCatalogQuery('MG2500'),
        ),
        hasLength(1),
      );
      expect(
        machineExerciseCatalog.where(
          (item) => item.matchesCatalogQuery('해머스랭스 하이 로우'),
        ),
        hasLength(1),
      );
      expect(
        machineCatalog
            .firstWhere((item) => item.id == 'hammer_iso_lateral_bench_press')
            .muscle,
        '가슴',
      );
      expect(
        machineCatalog
            .firstWhere((item) => item.id == 'newtech_advance_adduction')
            .focus,
        '내전근',
      );
    },
  );

  Future<AppState> pumpEquipment(
    WidgetTester tester, {
    LocalEquipmentRepository? store,
    _PhotoPicker? picker,
    EquipmentBackupFiles? files,
    double scale = 1,
    bool dark = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState(localEquipmentRepository: store);
    addTearDown(state.dispose);
    await state.initialize();
    await state.flushPersistence();
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: dark ? SetflowTheme.dark : SetflowTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              padding: const EdgeInsets.only(top: 24, bottom: 34),
            ),
            child: child!,
          ),
          home: LocalEquipmentScreen(
            date: DateTime(2026, 9, 13),
            photoPicker: picker ?? _PhotoPicker(),
            backupFiles: files,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets('camera photo is saved locally and can be added to a workout', (
    tester,
  ) async {
    final picker = _PhotoPicker();
    final state = await pumpEquipment(tester, picker: picker);
    await tester.tap(find.widgetWithText(FilledButton, '기구 등록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('사진 촬영'));
    await tester.pumpAndSettle();
    expect(picker.lastSource, PostMediaSource.camera);
    expect(find.byType(Image), findsOneWidget);
    final field = find.byKey(const ValueKey('equipment-field-기구 이름'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '우리 헬스장 체스트 프레스');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    final save = find.text('기기에 저장');
    await tester.scrollUntilVisible(
      save,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(state.localEquipment.single.photo, orderedEquals(photoBytes()));
    await tester.ensureVisible(find.text('오늘 운동에 추가'));
    await tester.tap(find.text('오늘 운동에 추가'));
    await tester.pumpAndSettle();
    expect(
      state.sessions[DateTime(2026, 9, 13)]!.exercises.single.template.id,
      state.localEquipment.single.id,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'manufacturer autocomplete fills the actual brand, model and target',
    (tester) async {
      final state = await pumpEquipment(tester);
      await tester.tap(find.widgetWithText(FilledButton, '기구 등록'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'MG2500');
      await tester.pumpAndSettle();
      await tester.tap(find.text('테크노짐 퓨어 로우 로우'));
      await tester.pumpAndSettle();
      final save = find.text('기기에 저장');
      await tester.scrollUntilVisible(
        save,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(state.localEquipment.single.brand, '테크노짐');
      expect(state.localEquipment.single.model, contains('MG2500'));
      expect(state.localEquipment.single.muscle, '등');
    },
  );

  testWidgets(
    'backup import confirms before writing and exports real photo content',
    (tester) async {
      final files = _BackupFiles(
        EquipmentBackupCodec.encode([equipment(photo: photoBytes())]),
      );
      final state = await pumpEquipment(tester, files: files);
      await tester.tap(find.text('백업 복원'));
      // The import remains busy while its confirmation dialog is open.
      await tester.pump(const Duration(milliseconds: 400));
      expect(state.localEquipment, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, '복원'));
      await tester.pumpAndSettle();
      expect(state.localEquipment.single.photo, orderedEquals(photoBytes()));
      await tester.tap(find.text('사진 포함 백업'));
      await tester.pumpAndSettle();
      expect(
        EquipmentBackupCodec.decode(files.exported!).single.photo,
        orderedEquals(photoBytes()),
      );
    },
  );

  testWidgets('large text and bottom insets leave the editor scrollable', (
    tester,
  ) async {
    await pumpEquipment(tester, scale: 2);
    await tester.tap(find.byTooltip('기구 등록'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('기기에 저장'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester.getBottomRight(find.widgetWithText(FilledButton, '기기에 저장')).dy,
      lessThanOrEqualTo(844 - 34),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark selected filters use readable ink on the lime fill', (
    tester,
  ) async {
    await pumpEquipment(tester, dark: true);
    final chip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, '전체'),
    );
    expect(
      (chip.label as Text).style!.color,
      SetflowTheme.dark.colorScheme.onPrimary,
    );
    expect(chip.checkmarkColor, SetflowTheme.dark.colorScheme.onPrimary);
  });

  testWidgets('cancelling gallery selection keeps the saved photo', (
    tester,
  ) async {
    final picker = _PhotoPicker(cancel: true);
    final state = await pumpEquipment(tester, picker: picker);
    await state.saveLocalEquipment(equipment(photo: photoBytes()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('사진·설정 수정'));
    await tester.tap(find.text('사진·설정 수정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('앨범에서 선택'));
    await tester.pumpAndSettle();
    expect(picker.lastSource, PostMediaSource.gallery);
    await tester.scrollUntilVisible(
      find.text('기기에 저장'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('기기에 저장'));
    await tester.pumpAndSettle();
    expect(state.localEquipment.single.photo, orderedEquals(photoBytes()));
  });

  testWidgets(
    'Android lost photo can be recovered when reopening registration',
    (tester) async {
      final state = await pumpEquipment(
        tester,
        picker: _PhotoPicker(recover: true),
      );
      await tester.tap(find.widgetWithText(FilledButton, '기구 등록'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(state.localEquipment, isEmpty);
    },
  );
}

class _FailingStore implements LocalEquipmentRepository {
  @override
  Future<List<LocalEquipment>> load() async => [];
  @override
  Future<void> save(List<LocalEquipment> equipment) async =>
      throw StateError('disk full');
}

class _PhotoPicker implements PostMediaPicker {
  _PhotoPicker({this.cancel = false, this.recover = false});
  final bool cancel;
  final bool recover;
  PostMediaSource? lastSource;
  @override
  Future<CommunityPostMedia?> pick(PostMediaSource source) async {
    lastSource = source;
    if (cancel) return null;
    return CommunityPostMedia(
      bytes: photoBytes(),
      fileName: 'equipment.png',
      contentType: 'image/png',
    );
  }

  @override
  Future<CommunityPostMedia?> recoverLostImage() async => recover
      ? CommunityPostMedia(
          bytes: photoBytes(),
          fileName: 'recovered.png',
          contentType: 'image/png',
        )
      : null;
}

class _BackupFiles implements EquipmentBackupFiles {
  _BackupFiles(this.source);
  final String source;
  String? exported;
  @override
  Future<void> export(String source, Rect origin) async {
    exported = source;
  }

  @override
  Future<String?> import() async => source;
}
