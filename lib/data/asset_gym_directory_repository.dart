import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/gym_directory.dart';
import 'gym_directory_repository.dart';

class AssetGymDirectoryRepository implements GymDirectoryRepository {
  AssetGymDirectoryRepository({
    AssetBundle? bundle,
    this.assetPath = 'assets/gym_directory/gyms.json',
  }) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final String assetPath;
  Future<GymDirectoryCatalog>? _catalog;

  @override
  Future<GymDirectoryCatalog> loadCatalog() => _catalog ??= _load();

  Future<GymDirectoryCatalog> _load() async {
    try {
      final source = await _bundle.loadString(assetPath);
      return await compute(_decodeCatalog, source);
    } catch (_) {
      // A transient asset read must not permanently poison the cached future.
      _catalog = null;
      rethrow;
    }
  }
}

GymDirectoryCatalog _decodeCatalog(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) {
    throw const FormatException('헬스장 목록 형식을 확인해주세요.');
  }
  return GymDirectoryCatalog.fromJson(Map<String, dynamic>.from(decoded));
}
