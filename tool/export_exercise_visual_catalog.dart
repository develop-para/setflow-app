import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:setflow/services/supabase_config.dart';

const _defaultOutput = 'output/exercise_visuals/catalog.json';
const _defaultSharedSnapshot =
    'output/exercise_visuals/production/shared_catalog_snapshot.json';

/// Exports the selectable catalog without using credentials for private data.
/// Flutter evaluates the canonical models because they depend on dart:ui.
Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options == null) {
    stdout.writeln(
      'Usage: dart run tool/export_exercise_visual_catalog.dart '
      '[--refresh-shared] [--shared-snapshot PATH] [--output PATH] '
      '[--personal-json PATH] [--offline-only]',
    );
    return;
  }
  final project = File.fromUri(Platform.script).parent.parent;
  final outputFile = _projectFile(project, options.output);
  if (await outputFile.exists()) {
    final existing = _object(jsonDecode(await outputFile.readAsString()));
    final existingRows = _rows(existing['exercises']);
    if (existingRows.any((row) => row['status'] != 'queued')) {
      throw StateError(
        'Output already contains production progress. Export to another '
        '--output path, then merge by exerciseId in the production runner.',
      );
    }
  }
  final sharedFile = _projectFile(project, options.sharedSnapshot);
  if (options.refreshShared) {
    final snapshot = await _readPublicCatalog();
    await _writeJson(sharedFile, snapshot);
    stdout.writeln(
      'Public shared snapshot saved: ${snapshot['rowCount']} rows.',
    );
  }
  if (!options.offlineOnly && !await sharedFile.exists()) {
    throw StateError(
      'Shared snapshot is missing. Run once with --refresh-shared, or use '
      '--offline-only. No private account data is read.',
    );
  }

  final scratch = Directory(
    '${project.path}/artifacts/exercise_visuals/catalog',
  );
  await scratch.create(recursive: true);
  final modelSnapshot = File('${scratch.path}/canonical_catalog.json');
  final environment = <String, String>{
    'SETFLOW_VISUAL_CATALOG_OUTPUT': modelSnapshot.absolute.path,
    'SETFLOW_VISUAL_SHARED_SNAPSHOT': options.offlineOnly
        ? ''
        : sharedFile.absolute.path,
  };
  final result = await Process.run(
    Platform.isWindows ? 'flutter.bat' : 'flutter',
    [
      'test',
      'tool/export_exercise_visual_snapshot_test.dart',
      '--reporter=compact',
    ],
    workingDirectory: project.path,
    environment: environment,
    runInShell: Platform.isWindows,
  );
  if (result.exitCode != 0) {
    stderr.write(result.stdout);
    stderr.write(result.stderr);
    throw StateError('Canonical Flutter catalog export failed.');
  }
  final canonical = _object(jsonDecode(await modelSnapshot.readAsString()));
  final rows = _rows(canonical['exercises']);
  final personal = options.personalJson == null
      ? <Map<String, dynamic>>[]
      : _rows(
          jsonDecode(
            await _projectFile(project, options.personalJson!).readAsString(),
          ),
        );
  final inputHashes = <String, String>{};
  for (final path in [
    'lib/data/offline_exercise_catalog.dart',
    'lib/data/exercise_catalog.dart',
    'lib/data/bodyweight_exercise_catalog.dart',
    'lib/data/machine_exercise_catalog.dart',
    'lib/data/exercise_catalog_crosswalk.dart',
    'lib/data/supabase_exercise_catalog_repository.dart',
    'lib/models.dart',
    'lib/domain/exercise_display_name.dart',
  ]) {
    inputHashes[path] = sha256
        .convert(await _projectFile(project, path).readAsBytes())
        .toString();
  }
  if (!options.offlineOnly) {
    inputHashes[options.sharedSnapshot] = sha256
        .convert(await sharedFile.readAsBytes())
        .toString();
  }
  if (options.personalJson != null) {
    inputHashes[options.personalJson!] = sha256
        .convert(
          await _projectFile(project, options.personalJson!).readAsBytes(),
        )
        .toString();
  }
  final manifest = buildExerciseVisualManifest(
    canonicalRows: rows,
    personalRows: personal,
    catalogCounts: _object(canonical['counts']),
    inputHashes: inputHashes,
  );
  await _writeJson(outputFile, manifest);
  stdout.writeln(
    'Visual production manifest saved: '
    '${(manifest['exercises'] as List).length} unique exercise IDs; all queued.',
  );
}

/// Production states deliberately begin queued. Existing films are attached
/// only by the production runner after their files and review state are checked.
Map<String, dynamic> buildExerciseVisualManifest({
  required List<Map<String, dynamic>> canonicalRows,
  required List<Map<String, dynamic>> personalRows,
  required Map<String, dynamic> catalogCounts,
  required Map<String, String> inputHashes,
  DateTime? generatedAt,
}) {
  final byId = <String, Map<String, dynamic>>{};
  for (final row in canonicalRows) {
    final id = _requiredString(row, 'exerciseId');
    _requiredString(row, 'name');
    if (byId.containsKey(id)) {
      throw FormatException('Duplicate canonical exerciseId: $id');
    }
    byId[id] = Map<String, dynamic>.from(row);
  }
  final personalIds = <String>{};
  for (final row in personalRows) {
    final id = _requiredString(row, 'exerciseId');
    _requiredString(row, 'name');
    if (!personalIds.add(id)) {
      throw FormatException('Duplicate personal exerciseId: $id');
    }
    byId[id] = {
      ...row,
      'metadata': {
        ..._optionalObject(row['metadata']),
        'catalogOrigins': ['personal-json'],
      },
    };
  }
  final rows = byId.values.map((row) {
    final origins = _optionalObject(row['metadata'])['catalogOrigins'];
    final phase = productionPhaseFor(origins is List ? origins : const []);
    return <String, dynamic>{
      ...row,
      'phase': phase,
      'status': 'queued',
      'reviewStatus': 'not_started',
      'motionKey': null,
      'visualAssets': null,
    };
  }).toList();
  rows.sort((left, right) {
    final phase = (left['phase'] as Map)['order'] as int;
    final otherPhase = (right['phase'] as Map)['order'] as int;
    final byPhase = phase.compareTo(otherPhase);
    if (byPhase != 0) return byPhase;
    return (left['exerciseId'] as String).compareTo(
      right['exerciseId'] as String,
    );
  });
  return {
    'schemaVersion': 1,
    'generatedAt': (generatedAt ?? DateTime.now()).toUtc().toIso8601String(),
    'scope': 'selectable-shared-and-offline-catalog',
    'counts': {
      ...catalogCounts,
      'personalInputRows': personalRows.length,
      'totalExercises': rows.length,
      'queued': rows.length,
      'rendered': 0,
      'approved': 0,
    },
    'provenance': {
      'mergeOrder': [
        'offline',
        'shared',
        'bodyweight-support-equipment',
        'personal',
      ],
      'inputSha256': inputHashes,
      'privateRemoteDataRead': false,
      'externalExerciseImagesUsed': false,
      'phaseLabelsAreMotionMappings': false,
    },
    'exercises': rows,
  };
}

Map<String, dynamic> productionPhaseFor(List<Object?> origins) {
  if (origins.contains('personal-json')) {
    return {'order': 0, 'key': 'personal', 'label': '직접 추가한 운동'};
  }
  if (origins.contains('curated')) {
    return {'order': 1, 'key': 'core', 'label': '주요 운동'};
  }
  if (origins.contains('manufacturer')) {
    return {'order': 3, 'key': 'manufacturer', 'label': '제조사별 머신'};
  }
  return {'order': 2, 'key': 'public-variants', 'label': '공유 종목·변형 동작'};
}

Future<Map<String, dynamic>> _readPublicCatalog() async {
  final client = HttpClient()..userAgent = 'setflow-visual-catalog/1.0';
  final rows = <Map<String, dynamic>>[];
  String? afterName;
  String? afterId;
  try {
    while (true) {
      final request = await client.postUrl(
        Uri.parse(
          '${SupabaseConfig.projectUrl}/rest/v1/rpc/list_master_exercises',
        ),
      );
      // This is the app's publishable key. No user token or service key is read.
      request.headers.set('apikey', SupabaseConfig.publishableKey);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'p_after_name': afterName,
          'p_after_id': afterId,
          'p_limit': 500,
        }),
      );
      final response = await request.close();
      final payload = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        throw HttpException(
          'Public catalog read failed with HTTP ${response.statusCode}.',
        );
      }
      final page = _rows(jsonDecode(payload));
      rows.addAll(page);
      if (page.length < 500) break;
      final last = page.last;
      final nextName = _requiredString(last, 'name');
      final nextId = _requiredString(last, 'id');
      if (nextName == afterName && nextId == afterId) {
        throw const FormatException('Public catalog cursor did not advance.');
      }
      afterName = nextName;
      afterId = nextId;
    }
  } finally {
    client.close(force: true);
  }
  final ids = rows.map((row) => _requiredString(row, 'id')).toSet();
  if (rows.length != ids.length) {
    throw const FormatException('Public catalog has duplicate database IDs.');
  }
  return {
    'schemaVersion': 1,
    'fetchedAt': DateTime.now().toUtc().toIso8601String(),
    'source': {
      'procedure': 'list_master_exercises',
      'visibility': 'public-active-non-custom',
      'projectHost': Uri.parse(SupabaseConfig.projectUrl).host,
      'credentialsStored': false,
      'rowsSha256': sha256.convert(utf8.encode(jsonEncode(rows))).toString(),
    },
    'rowCount': rows.length,
    'rows': rows,
  };
}

Future<void> _writeJson(File file, Object value) async {
  await file.parent.create(recursive: true);
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
  );
}

File _projectFile(Directory project, String path) {
  final file = File(path);
  return file.isAbsolute ? file : File('${project.path}/$path');
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map) throw const FormatException('Expected a JSON object.');
  return Map<String, dynamic>.from(value);
}

Map<String, dynamic> _optionalObject(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<Map<String, dynamic>> _rows(Object? value) {
  if (value is! List) throw const FormatException('Expected a JSON row array.');
  return value.map(_object).toList();
}

String _requiredString(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing or invalid $key.');
  }
  return value.trim();
}

class _Options {
  const _Options({
    this.output = _defaultOutput,
    this.sharedSnapshot = _defaultSharedSnapshot,
    this.personalJson,
    this.refreshShared = false,
    this.offlineOnly = false,
  });

  final String output;
  final String sharedSnapshot;
  final String? personalJson;
  final bool refreshShared;
  final bool offlineOnly;

  static _Options? parse(List<String> args) {
    var output = _defaultOutput;
    var sharedSnapshot = _defaultSharedSnapshot;
    String? personalJson;
    var refreshShared = false;
    var offlineOnly = false;
    for (var index = 0; index < args.length; index++) {
      final arg = args[index];
      switch (arg) {
        case '--help':
          return null;
        case '--refresh-shared':
          refreshShared = true;
        case '--offline-only':
          offlineOnly = true;
        case '--output' || '--shared-snapshot' || '--personal-json':
          if (++index >= args.length || args[index].startsWith('--')) {
            throw FormatException('$arg requires a path.');
          }
          switch (arg) {
            case '--output':
              output = args[index];
            case '--shared-snapshot':
              sharedSnapshot = args[index];
            case '--personal-json':
              personalJson = args[index];
          }
        default:
          throw FormatException('Unknown option: $arg');
      }
    }
    if (offlineOnly && refreshShared) {
      throw const FormatException(
        '--offline-only and --refresh-shared conflict.',
      );
    }
    return _Options(
      output: output,
      sharedSnapshot: sharedSnapshot,
      personalJson: personalJson,
      refreshShared: refreshShared,
      offlineOnly: offlineOnly,
    );
  }
}
