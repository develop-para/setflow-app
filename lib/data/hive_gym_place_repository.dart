import 'package:hive_ce_flutter/hive_flutter.dart';

import '../domain/gym_directory.dart';
import 'gym_directory_repository.dart';

/// Device owned, deliberately separate from authenticated account snapshots.
class HiveGymPlaceRepository implements GymPlaceRepository {
  HiveGymPlaceRepository({this.boxName = 'setflow_gym_places_v1'});

  final String boxName;

  Future<Box<String>> _box() => Hive.openBox<String>(boxName);

  @override
  Future<GymPlaceLibrary> load() async {
    final source = (await _box()).get('library');
    return source == null
        ? GymPlaceLibrary()
        : GymPlaceLibraryCodec.decode(source);
  }

  @override
  Future<void> save(GymPlaceLibrary library) async {
    final source = GymPlaceLibraryCodec.encode(library);
    GymPlaceLibraryCodec.decode(source);
    final box = await _box();
    await box.put('library', source);
    await box.flush();
  }
}
