import 'dart:convert';
import 'dart:typed_data';
import 'package:image/image.dart' as image;

import '../models.dart';
import '../theme/icons.dart';

/// Device-owned equipment, deliberately excluded from account snapshots.
class LocalEquipment {
  const LocalEquipment({
    required this.id,
    required this.name,
    required this.muscle,
    this.brand = '',
    this.model = '',
    this.notes = '',
    this.photo,
    this.measurement = ExerciseMeasurement.weightReps,
  });

  final String id, name, muscle, brand, model, notes;
  final Uint8List? photo;
  final ExerciseMeasurement measurement;

  ExerciseTemplate get exercise => ExerciseTemplate(
    id: id,
    name: name,
    muscle: muscle,
    icon: SetflowIcons.equipment,
    measurement: measurement,
    equipmentKey: measurement == ExerciseMeasurement.weightReps
        ? 'machine'
        : 'body_only',
    aliases: const ['내 기구'],
    sourceName: 'local-equipment',
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'muscle': muscle,
    'brand': brand,
    'model': model,
    'notes': notes,
    'measurement': measurement.name,
    if (photo != null) 'photo': base64Encode(photo!),
  };
}

abstract interface class LocalEquipmentRepository {
  Future<List<LocalEquipment>> load();

  /// Atomically replaces a validated device library, including photo bytes.
  Future<void> save(List<LocalEquipment> equipment);
}

class MemoryLocalEquipmentRepository implements LocalEquipmentRepository {
  List<LocalEquipment> _items = [];
  @override
  Future<List<LocalEquipment>> load() async => List.of(_items);
  @override
  Future<void> save(List<LocalEquipment> equipment) async {
    _items = List.of(equipment);
  }
}

abstract final class EquipmentBackupCodec {
  static const maxBytes = 64 * 1024 * 1024;
  static const maxPhotoBytes = 4 * 1024 * 1024;
  static const muscles = ['가슴', '등', '어깨', '하체', '팔', '복근', '유산소', '기타'];

  static String encode(List<LocalEquipment> items) => jsonEncode({
    'format': 'setflow-equipment',
    'version': 1,
    'equipment': items.map((item) => item.toJson()).toList(),
  });

  static List<LocalEquipment> decode(String source) {
    if (utf8.encode(source).length > maxBytes) {
      throw const FormatException('백업 파일은 64MB 이하여야 해요.');
    }
    try {
      final root = jsonDecode(source) as Map<String, dynamic>;
      if (root['format'] != 'setflow-equipment' || root['version'] != 1) {
        throw const FormatException('지원하지 않는 기구 백업이에요.');
      }
      final rows = root['equipment'] as List;
      if (rows.length > 500) throw const FormatException('기구는 최대 500개예요.');
      final ids = <String>{};
      return rows.map((raw) {
        final row = raw as Map<String, dynamic>;
        String field(String key, int limit, {bool required = false}) {
          final value = (row[key] as String? ?? '').trim();
          if (value.length > limit || (required && value.isEmpty)) {
            throw const FormatException('기구 정보의 길이를 확인해주세요.');
          }
          return value;
        }

        final id = field('id', 80, required: true);
        final muscle = field('muscle', 10, required: true);
        if (!RegExp(r'^equipment_[a-zA-Z0-9_]+$').hasMatch(id) ||
            !ids.add(id) ||
            !muscles.contains(muscle)) {
          throw const FormatException('기구 ID 또는 운동 부위가 올바르지 않아요.');
        }
        final measurement = ExerciseMeasurement.values.firstWhere(
          (value) => value.name == row['measurement'],
        );
        final encodedPhoto = row['photo'] as String?;
        if (encodedPhoto != null &&
            encodedPhoto.length > maxPhotoBytes * 4 ~/ 3 + 4) {
          throw const FormatException('사진 한 장은 4MB 이하여야 해요.');
        }
        final photo = encodedPhoto == null ? null : base64Decode(encodedPhoto);
        if (photo != null && (photo.isEmpty || photo.length > maxPhotoBytes)) {
          throw const FormatException('사진 크기를 확인해주세요.');
        }
        if (photo != null) {
          final info = image.findDecoderForData(photo)?.startDecode(photo);
          if (info == null ||
              info.width <= 0 ||
              info.height <= 0 ||
              info.width > 4096 ||
              info.height > 4096 ||
              info.numFrames > 1) {
            throw const FormatException('사진을 읽을 수 없거나 허용 크기를 넘었어요.');
          }
        }
        return LocalEquipment(
          id: id,
          name: field('name', 80, required: true),
          muscle: muscle,
          brand: field('brand', 80),
          model: field('model', 100),
          notes: field('notes', 1000),
          measurement: measurement,
          photo: photo,
        );
      }).toList();
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('올바른 셋플로우 기구 백업 파일이 아니에요.');
    }
  }
}
