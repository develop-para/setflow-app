import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _revision = 'a859101d633a01c4a1a920d6a8ce41dabba0705f';
const _expectedSha256 =
    '5bb747e3fc658f095a60dcbf6d53c96627acdcc6ffb6fffde86f7e26995d40bf';
const _expectedCount = 876;
const _sourceUrl =
    'https://raw.githubusercontent.com/yuhonas/free-exercise-db/'
    '$_revision/dist/exercises.json';

Future<void> main(List<String> args) async {
  if (args.any((argument) => argument != '--verify-only')) {
    stderr.writeln(
      'Usage: dart run tool/import_exercise_catalog.dart '
      '[--verify-only]',
    );
    exitCode = 64;
    return;
  }
  final verifyOnly = args.contains('--verify-only');
  final client = HttpClient()..userAgent = 'setflow-catalog-import/1.0';
  try {
    stdout.writeln('Downloading pinned free-exercise-db revision...');
    final bytes = await _getBytes(client, Uri.parse(_sourceUrl));
    final actualHash = sha256.convert(bytes).toString();
    if (actualHash != _expectedSha256) {
      throw StateError(
        'SHA-256 mismatch: expected $_expectedSha256, got $actualHash.',
      );
    }

    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! List) {
      throw const FormatException('Catalog payload is not a JSON array.');
    }
    final ids = decoded
        .whereType<Map>()
        .map((row) => row['id']?.toString().trim() ?? '')
        .toSet();
    if (decoded.length != _expectedCount ||
        ids.length != _expectedCount ||
        ids.contains('')) {
      throw StateError(
        'Expected $_expectedCount rows and unique IDs; got '
        '${decoded.length} rows / ${ids.length} IDs.',
      );
    }

    if (verifyOnly) {
      stdout.writeln(
        'Source verified: $_expectedCount unique exercises; no DB changes.',
      );
      return;
    }

    final supabaseUrl = _requiredEnvironment(
      'SUPABASE_URL',
    ).replaceFirst(RegExp(r'/+$'), '');
    final serviceRoleKey =
        Platform.environment['SUPABASE_SERVICE_ROLE_KEY']?.trim() ?? '';
    final modernSecretKey =
        Platform.environment['SUPABASE_SECRET_KEY']?.trim() ?? '';
    final secret = serviceRoleKey.isNotEmpty ? serviceRoleKey : modernSecretKey;
    if (secret.isEmpty) {
      throw const FormatException(
        'SUPABASE_SERVICE_ROLE_KEY or SUPABASE_SECRET_KEY is required.',
      );
    }
    // Legacy service-role keys are JWTs. Modern sb_secret_* keys are opaque
    // and must only be sent as apikey; Bearer would produce Invalid JWT.
    final bearerToken = secret.startsWith('eyJ') ? secret : null;

    stdout.writeln('Source verified. Importing $_expectedCount exercises...');
    final result = await _postJson(
      client,
      Uri.parse('$supabaseUrl/rest/v1/rpc/import_free_exercise_db_catalog'),
      secret,
      bearerToken,
      {
        'p_payload': decoded,
        'p_revision': _revision,
        'p_payload_sha256': actualHash,
      },
    );
    if (result.toString().trim() != '$_expectedCount') {
      throw StateError('Unexpected import response: $result');
    }

    final rows = await _getJsonList(
      client,
      Uri.parse(
        '$supabaseUrl/rest/v1/master_exercises'
        '?select=source_id,aliases'
        '&source_name=eq.free-exercise-db'
        '&is_active=eq.true'
        '&limit=1000',
      ),
      secret,
      bearerToken,
    );
    final importedIds = rows
        .map((row) => row['source_id']?.toString().trim() ?? '')
        .toSet();
    final invalidAliases = rows.where((row) {
      final aliases = row['aliases'];
      return aliases is! List || aliases.length < 2;
    }).length;
    if (rows.length != _expectedCount ||
        importedIds.length != _expectedCount ||
        importedIds.contains('') ||
        invalidAliases > 0) {
      throw StateError(
        'Post-import validation failed: ${rows.length} rows, '
        '${importedIds.length} IDs, $invalidAliases invalid alias arrays.',
      );
    }
    stdout.writeln(
      'Import complete: $_expectedCount unique exercises; aliases verified.',
    );
  } finally {
    client.close(force: true);
  }
}

String _requiredEnvironment(String name) {
  final value = Platform.environment[name]?.trim() ?? '';
  if (value.isEmpty) {
    stderr.writeln('$name is required.');
    exit(64);
  }
  return value;
}

Future<List<int>> _getBytes(HttpClient client, Uri uri) async {
  final request = await client.getUrl(uri);
  final response = await request.close();
  final bytes = await response.fold<List<int>>(<int>[], (buffer, chunk) {
    buffer.addAll(chunk);
    return buffer;
  });
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException(
      'Download failed with HTTP ${response.statusCode}.',
      uri: uri,
    );
  }
  return bytes;
}

Future<Object?> _postJson(
  HttpClient client,
  Uri uri,
  String secret,
  String? bearerToken,
  Object body,
) async {
  final request = await client.postUrl(uri);
  _authorize(request, secret, bearerToken);
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode(body));
  final response = await request.close();
  final responseBody = await utf8.decoder.bind(response).join();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException(
      'Import failed with HTTP ${response.statusCode}: $responseBody',
      uri: uri,
    );
  }
  return responseBody.isEmpty ? null : jsonDecode(responseBody);
}

Future<List<Map<String, dynamic>>> _getJsonList(
  HttpClient client,
  Uri uri,
  String secret,
  String? bearerToken,
) async {
  final request = await client.getUrl(uri);
  _authorize(request, secret, bearerToken);
  final response = await request.close();
  final responseBody = await utf8.decoder.bind(response).join();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException(
      'Validation failed with HTTP ${response.statusCode}: $responseBody',
      uri: uri,
    );
  }
  final decoded = jsonDecode(responseBody);
  if (decoded is! List) {
    throw const FormatException('Validation response is not a JSON array.');
  }
  return decoded
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
}

void _authorize(HttpClientRequest request, String secret, String? bearerToken) {
  request.headers
    ..set('apikey', secret)
    ..set(HttpHeaders.acceptHeader, 'application/json');
  if (bearerToken != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
  }
}
