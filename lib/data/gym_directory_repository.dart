import 'dart:convert';

import '../domain/gym_directory.dart';

abstract interface class GymDirectoryRepository {
  Future<GymDirectoryCatalog> loadCatalog();
}

abstract interface class GymPlaceRepository {
  Future<GymPlaceLibrary> load();

  /// Replaces the device library only after validating the entire document.
  Future<void> save(GymPlaceLibrary library);
}

abstract interface class GymDirectoryRequestRepository {
  /// Availability means the server endpoint exists, not that a draft was sent.
  Future<bool> isAvailable();

  /// A retry with the same ID and payload returns the original server receipt.
  Future<DateTime> submitRequest(GymDirectoryRequest request);
}

class MemoryGymPlaceRepository implements GymPlaceRepository {
  MemoryGymPlaceRepository({GymPlaceLibrary? initialValue})
    : _library = initialValue ?? GymPlaceLibrary();

  GymPlaceLibrary _library;

  @override
  Future<GymPlaceLibrary> load() async => _library;

  @override
  Future<void> save(GymPlaceLibrary library) async {
    _library = GymPlaceLibraryCodec.decode(
      GymPlaceLibraryCodec.encode(library),
    );
  }
}

abstract final class GymPlaceLibraryCodec {
  static const maxBytes = 5 * 1024 * 1024;

  static String encode(GymPlaceLibrary library) => jsonEncode({
    'format': 'setflow-gym-places',
    'version': 1,
    'gyms': library.gyms.map((gym) => gym.toJson()).toList(),
    'selectedId': library.selectedId,
    'requests': library.requests.map((request) => request.toJson()).toList(),
  });

  static GymPlaceLibrary decode(String source) {
    if (utf8.encode(source).length > maxBytes) {
      throw const FormatException('운동 장소 보관함이 허용 크기를 넘었어요.');
    }
    try {
      final root = jsonDecode(source);
      if (root is! Map ||
          root['format'] != 'setflow-gym-places' ||
          root['version'] != 1 ||
          root['gyms'] is! List ||
          root['requests'] is! List) {
        throw const FormatException('운동 장소 보관함 형식을 확인해주세요.');
      }
      final gyms = (root['gyms'] as List)
          .map((row) {
            if (row is! Map) throw const FormatException('운동 장소를 확인해주세요.');
            return GymPlace.fromJson(Map<String, dynamic>.from(row));
          })
          .toList(growable: false);
      final requests = (root['requests'] as List)
          .map((row) {
            if (row is! Map) throw const FormatException('보관한 제안을 확인해주세요.');
            return GymDirectoryRequest.fromJson(Map<String, dynamic>.from(row));
          })
          .toList(growable: false);
      final gymIds = gyms.map((gym) => gym.id).toSet();
      final requestIds = requests.map((request) => request.id).toSet();
      final selectedId = root['selectedId'];
      if (gymIds.length != gyms.length ||
          requestIds.length != requests.length ||
          (selectedId != null &&
              (selectedId is! String || !gymIds.contains(selectedId)))) {
        throw const FormatException('운동 장소의 선택 또는 중복 정보를 확인해주세요.');
      }
      return GymPlaceLibrary(
        gyms: gyms,
        selectedId: selectedId as String?,
        requests: requests,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('운동 장소 보관함을 읽을 수 없어요.');
    }
  }
}
