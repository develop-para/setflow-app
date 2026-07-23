import 'package:hive_ce_flutter/hive_flutter.dart';

import '../models.dart';
import 'app_repository.dart';
import 'app_snapshot_codec.dart';

class HiveAppRepository implements AppRepository {
  HiveAppRepository._(this._box);

  static const _snapshotKey = 'snapshot';
  static const _boxName = 'setflow_app_state_v1';

  final Box<String> _box;

  static Future<HiveAppRepository> open() async {
    await Hive.initFlutter('setflow');
    final box = await Hive.openBox<String>(_boxName);
    return HiveAppRepository._(box);
  }

  @override
  Future<AppSnapshot?> load(List<ExerciseTemplate> exerciseCatalog) async {
    final source = _box.get(_snapshotKey);
    if (source == null || source.isEmpty) return null;
    return AppSnapshotCodec.decode(source, exerciseCatalog);
  }

  @override
  Future<void> save(AppSnapshot snapshot) async {
    await _box.put(_snapshotKey, AppSnapshotCodec.encode(snapshot));
  }

  @override
  Future<void> clear() => _box.delete(_snapshotKey);
}
