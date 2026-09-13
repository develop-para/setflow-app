import 'package:hive_ce_flutter/hive_flutter.dart';
import 'local_equipment_repository.dart';

class HiveLocalEquipmentRepository implements LocalEquipmentRepository {
  Future<Box<String>> _box() =>
      Hive.openBox<String>('setflow_local_equipment_v1');

  @override
  Future<List<LocalEquipment>> load() async {
    final source = (await _box()).get('library');
    return source == null ? [] : EquipmentBackupCodec.decode(source);
  }

  @override
  Future<void> save(List<LocalEquipment> equipment) async {
    final source = EquipmentBackupCodec.encode(equipment);
    EquipmentBackupCodec.decode(source);
    final box = await _box();
    await box.put('library', source);
    await box.flush();
  }
}
