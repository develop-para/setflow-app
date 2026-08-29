// tool/ 아래 노션 스크립트들이 공유하는 바닥 — 토큰 찾기, 저장소 루트, HTTP 호출.
//
// 토큰: 환경변수 NOTION_TOKEN, 없으면 저장소의 .env.notion-mcp(Codex 노션 MCP와 같은 파일).
// API 버전은 2022-06-28 로 고정한다 — 데이터베이스를 `database_id` 부모로 다루는
// 마지막 버전이라 스크립트가 단순하다.

import 'dart:convert';
import 'dart:io';

const notionVersion = '2022-06-28';

String repoRoot() =>
    runGit(Directory.current.path, ['rev-parse', '--show-toplevel']).trim();

String runGit(String cwd, List<String> args) {
  final result = Process.runSync(
    'git',
    args,
    workingDirectory: cwd,
    stdoutEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw ProcessException('git', args, '${result.stderr}', result.exitCode);
  }
  return result.stdout as String;
}

String notionToken(String root) {
  final fromEnv = Platform.environment['NOTION_TOKEN'];
  if (fromEnv != null && fromEnv.trim().isNotEmpty) return fromEnv.trim();
  final file = File('$root/.env.notion-mcp');
  if (!file.existsSync()) {
    throw StateError(
      'NOTION_TOKEN 환경변수도, .env.notion-mcp 파일도 없습니다. '
      '.env.notion-mcp.example 을 복사해 토큰을 넣으세요.',
    );
  }
  for (final line in file.readAsLinesSync()) {
    final match = RegExp(r'^\s*NOTION_TOKEN\s*=\s*(.+)$').firstMatch(line);
    if (match == null) continue;
    var value = match.group(1)!.trim();
    final quoted =
        value.length >= 2 &&
        (value.startsWith('"') && value.endsWith('"') ||
            value.startsWith("'") && value.endsWith("'"));
    if (quoted) value = value.substring(1, value.length - 1);
    if (value.isEmpty || value.contains('replace_with')) break;
    return value;
  }
  throw StateError('.env.notion-mcp 의 NOTION_TOKEN 이 비어 있거나 자리표시자입니다.');
}

/// `tool/<name>.json` 의 한 키를 읽는다 — DB id 같은 비밀 아닌 설정.
String configValue(String root, String fileName, String key) {
  final file = File('$root/tool/$fileName');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final value = json[key] as String?;
  if (value == null || value.isEmpty) {
    throw StateError('tool/$fileName 에 $key 가 없습니다.');
  }
  return value;
}

/// 노션 페이지 URL 이나 하이픈 없는 id 를 하이픈 있는 UUID 로.
String normalizePageId(String input) {
  final hex = RegExp(r'[0-9a-fA-F]{32}').allMatches(input).lastOrNull?.group(0);
  if (hex == null) {
    final dashed = RegExp(
      r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
    ).firstMatch(input);
    if (dashed != null) return dashed.group(0)!.toLowerCase();
    throw FormatException('노션 페이지 id 나 URL 이 아닙니다: $input');
  }
  final h = hex.toLowerCase();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

class NotionClient {
  NotionClient(this._token);

  final String _token;
  final _client = HttpClient();

  Future<Map<String, dynamic>> call(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final request = await _client.openUrl(
      method,
      Uri.parse('https://api.notion.com$path'),
    );
    request.headers.set('Authorization', 'Bearer $_token');
    request.headers.set('Notion-Version', notionVersion);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    if (response.statusCode >= 300) {
      throw HttpException(
        'Notion $method $path → ${response.statusCode}: $text',
      );
    }
    return jsonDecode(text) as Map<String, dynamic>;
  }

  /// 페이지네이션을 끝까지 따라가 `results` 를 모은다.
  Future<List<Map<String, dynamic>>> collect(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final all = <Map<String, dynamic>>[];
    String? cursor;
    while (true) {
      final page = method == 'GET'
          ? await call(
              'GET',
              cursor == null
                  ? path
                  : '$path${path.contains('?') ? '&' : '?'}start_cursor=$cursor',
            )
          : await call('POST', path, {
              ...?body,
              // 노션은 `start_cursor: null` 을 거부한다 — 값이 null 이면 키를 뺀다
              // (`?` 는 값 쪽에 붙는다. 키 쪽에 붙이면 null 이 그대로 나간다).
              'start_cursor': ?cursor,
            });
      all.addAll(
        (page['results'] as List<dynamic>).cast<Map<String, dynamic>>(),
      );
      if (page['has_more'] != true) return all;
      cursor = page['next_cursor'] as String?;
    }
  }

  /// 임시 URL(S3)의 파일을 내려받는다 — 노션 첨부는 1시간짜리 서명 URL 이다.
  Future<void> download(String url, File target) async {
    final request = await _client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode >= 300) {
      throw HttpException('download ${response.statusCode}: $url');
    }
    await target.parent.create(recursive: true);
    await response.pipe(target.openWrite());
  }

  void close() => _client.close();
}

/// rich_text 배열을 평문으로.
String plain(dynamic richText) => (richText as List<dynamic>? ?? const [])
    .map((t) => (t as Map<String, dynamic>)['plain_text'] as String? ?? '')
    .join();

List<Map<String, dynamic>> text(String content) => [
  {
    'type': 'text',
    'text': {
      'content': content.length > 2000 ? content.substring(0, 2000) : content,
    },
  },
];
