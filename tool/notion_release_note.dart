// 배포 한 건을 노션 "셋플로우 배포 기록" 데이터베이스에 한 줄(페이지)로 남긴다.
//
//   dart run tool/notion_release_note.dart --build 138
//   dart run tool/notion_release_note.dart --build 138 --notes-file notes.md --by Claude --update
//
// 세 곳이 같은 스크립트를 부른다 — CI(android-distribute.yml, 배포 직후),
// 로컬 배포(tool/distribute-android.ps1), 그리고 에이전트 스킬
// (.claude/skills/release-notion). 노션 API를 아는 파일은 이것 하나다.
//
// 무엇이 들어가나:
//   이름       "1.12.0 (138)"
//   버전/빌드  pubspec의 x.y.z, versionCode
//   배포일     dist 태그의 커밋 시각
//   작업자     그 범위 커밋들의 author 이름(멀티셀렉트) — 기록한 사람이 아니라 만든 사람
//   요약 작성  자동 | Claude | Codex | 사람   (--by)
//   커밋 범위  "dist/136..dist/138"
//   변경 보기  GitHub compare 링크
//   본문       [요약] --notes/--notes-file 이 있으면 그 줄들, 그 아래 [커밋] 제목 목록
//
// 같은 빌드가 이미 있으면 새로 만들지 않는다(CI 재실행이 두 줄을 남기지 않게).
// --update 를 주면 그 페이지의 본문과 '요약 작성'을 갈아 끼운다 — 에이전트가
// CI의 자동 기록 위에 사람이 읽을 요약을 덧쓰는 길이다.
//
// 토큰: 환경변수 NOTION_TOKEN, 없으면 저장소의 .env.notion-mcp(Codex MCP와 같은 파일).
// DB:   tool/notion-release.json 의 databaseId (환경변수 NOTION_RELEASE_DB 가 우선).

import 'dart:convert';
import 'dart:io';

const _notionVersion = '2022-06-28';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options == null) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }
  final root = _repoRoot();
  final token = _token(root);
  final databaseId =
      Platform.environment['NOTION_RELEASE_DB'] ?? _databaseIdFromConfig(root);

  final tag = options.tag ?? 'dist/${options.build}';
  if (!_tagExists(root, tag)) {
    stderr.writeln('태그 $tag 가 없습니다. 배포가 끝난 빌드만 기록합니다.');
    exitCode = 1;
    return;
  }
  final previous = options.previousTag ?? _previousDistTag(root, tag);
  final range = previous == null ? tag : '$previous..$tag';
  final version = options.version ?? _versionAtTag(root, tag);
  final deployedAt = _commitDate(root, tag);
  final authors = _authors(root, range);
  final commits = _commits(root, range);
  final compareUrl = previous == null ? null : _compareUrl(root, previous, tag);
  final summary = options.notes;

  final page = _PageSpec(
    title: '$version (${options.build})',
    version: version,
    build: options.build,
    deployedAt: deployedAt,
    channel: options.channel,
    authors: authors,
    writtenBy: options.by,
    range: range,
    compareUrl: compareUrl,
    summary: summary,
    commits: commits,
  );

  if (options.dryRun) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(page.toJson()));
    return;
  }

  final api = _Notion(token);
  final existing = await api.findByBuild(databaseId, options.build);
  if (existing != null && !options.update) {
    stdout.writeln('이미 기록돼 있습니다: ${existing.url}');
    return;
  }
  if (existing == null) {
    final created = await api.createPage(databaseId, page);
    stdout.writeln('노션에 기록했습니다: ${created.url}');
    return;
  }
  await api.replacePage(existing.id, page);
  stdout.writeln('노션 기록을 갱신했습니다: ${existing.url}');
}

const _usage = '''
사용법: dart run tool/notion_release_note.dart --build <versionCode> [옵션]

  --build N            필수. dist/N 태그가 있어야 한다.
  --version x.y.z      생략하면 태그 시점의 pubspec에서 읽는다.
  --tag dist/N         기본 dist/<build>
  --prev-tag dist/M    기본: 그 아래 가장 최근 dist 태그
  --notes "텍스트"     요약. 줄마다 불릿 하나. 파일로 주려면 --notes-file
  --notes-file 경로
  --by 자동|Claude|Codex|사람   요약을 누가 썼나. 기본 자동
  --channel 이름       기본 "Android 테스터"
  --update             이미 있으면 본문·요약 작성을 갈아 끼운다
  --dry-run            보내지 않고 내용만 출력
''';

class _Options {
  _Options({
    required this.build,
    required this.version,
    required this.tag,
    required this.previousTag,
    required this.notes,
    required this.by,
    required this.channel,
    required this.update,
    required this.dryRun,
  });

  final int build;
  final String? version;
  final String? tag;
  final String? previousTag;
  final List<String> notes;
  final String by;
  final String channel;
  final bool update;
  final bool dryRun;

  static _Options? parse(List<String> args) {
    int? build;
    String? version;
    String? tag;
    String? previousTag;
    String? notes;
    String? notesFile;
    var by = '자동';
    var channel = 'Android 테스터';
    var update = false;
    var dryRun = false;
    for (var i = 0; i < args.length; i++) {
      String next() {
        if (i + 1 >= args.length) {
          throw FormatException('${args[i]} 뒤에 값이 없습니다.');
        }
        return args[++i];
      }

      switch (args[i]) {
        case '--build':
          build = int.tryParse(next());
        case '--version':
          version = next();
        case '--tag':
          tag = next();
        case '--prev-tag':
          previousTag = next();
        case '--notes':
          notes = next();
        case '--notes-file':
          notesFile = next();
        case '--by':
          by = next();
        case '--channel':
          channel = next();
        case '--update':
          update = true;
        case '--dry-run':
          dryRun = true;
        default:
          return null;
      }
    }
    if (build == null) return null;
    if (notesFile != null) notes = File(notesFile).readAsStringSync();
    final lines = (notes ?? '')
        .split(RegExp(r'\r?\n'))
        .map((line) => line.replaceFirst(RegExp(r'^\s*[-*•]\s*'), '').trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return _Options(
      build: build,
      version: version,
      tag: tag,
      previousTag: previousTag,
      notes: lines,
      by: by,
      channel: channel,
      update: update,
      dryRun: dryRun,
    );
  }
}

// --- git --------------------------------------------------------------------

String _repoRoot() =>
    _git(Directory.current.path, ['rev-parse', '--show-toplevel']).trim();

String _git(String cwd, List<String> args) {
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

bool _tagExists(String root, String tag) =>
    _git(root, ['tag', '-l', tag]).trim().isNotEmpty;

String? _previousDistTag(String root, String tag) {
  final number = int.tryParse(tag.replaceFirst('dist/', ''));
  final tags =
      _git(root, ['tag', '-l', 'dist/*'])
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .map((line) => (line, int.tryParse(line.replaceFirst('dist/', ''))))
          .where(
            (entry) => entry.$2 != null && number != null && entry.$2! < number,
          )
          .toList()
        ..sort((a, b) => b.$2!.compareTo(a.$2!));
  return tags.isEmpty ? null : tags.first.$1;
}

String _versionAtTag(String root, String tag) {
  final pubspec = _git(root, ['show', '$tag:pubspec.yaml']);
  final match = RegExp(
    r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
    multiLine: true,
  ).firstMatch(pubspec);
  return match?.group(1) ?? '?';
}

String _commitDate(String root, String tag) =>
    _git(root, ['log', '-1', '--format=%cI', tag]).trim();

List<String> _authors(String root, String range) {
  final names = _git(root, [
    'log',
    '--no-merges',
    '--format=%an',
    range,
  ]).split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty);
  // github-actions[bot]처럼 사람이 아닌 작성자는 뺀다 — 릴리스 커밋의 주인은 사람이다.
  final unique = <String>{};
  for (final name in names) {
    if (name.endsWith('[bot]')) continue;
    unique.add(name);
  }
  return unique.toList();
}

List<String> _commits(String root, String range) =>
    _git(root, ['log', '--no-merges', '--format=%h %s', range])
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

String? _compareUrl(String root, String from, String to) {
  final remote = _git(root, ['remote', 'get-url', 'origin']).trim();
  final match = RegExp(
    r'github\.com[:/]([^/]+)/([^/.]+)(?:\.git)?$',
  ).firstMatch(remote);
  if (match == null) return null;
  return 'https://github.com/${match.group(1)}/${match.group(2)}/compare/$from...$to';
}

// --- config -----------------------------------------------------------------

String _token(String root) {
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
    if (value.length >= 2 &&
        (value.startsWith('"') && value.endsWith('"') ||
            value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }
    if (value.isEmpty || value.contains('replace_with')) break;
    return value;
  }
  throw StateError('.env.notion-mcp 의 NOTION_TOKEN 이 비어 있거나 자리표시자입니다.');
}

String _databaseIdFromConfig(String root) {
  final file = File('$root/tool/notion-release.json');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final id = json['databaseId'] as String?;
  if (id == null || id.isEmpty) {
    throw StateError('tool/notion-release.json 에 databaseId 가 없습니다.');
  }
  return id;
}

// --- page -------------------------------------------------------------------

class _PageSpec {
  _PageSpec({
    required this.title,
    required this.version,
    required this.build,
    required this.deployedAt,
    required this.channel,
    required this.authors,
    required this.writtenBy,
    required this.range,
    required this.compareUrl,
    required this.summary,
    required this.commits,
  });

  final String title;
  final String version;
  final int build;
  final String deployedAt;
  final String channel;
  final List<String> authors;
  final String writtenBy;
  final String range;
  final String? compareUrl;
  final List<String> summary;
  final List<String> commits;

  Map<String, dynamic> properties() => {
    '이름': {'title': _text(title)},
    '버전': {'rich_text': _text(version)},
    '빌드': {'number': build},
    '배포일': {
      'date': {'start': deployedAt},
    },
    '채널': {
      'select': {'name': channel},
    },
    '작업자': {
      'multi_select': [
        for (final name in authors) {'name': name},
      ],
    },
    '요약 작성': {
      'select': {'name': writtenBy},
    },
    '커밋 범위': {'rich_text': _text(range)},
    if (compareUrl != null) '변경 보기': {'url': compareUrl},
  };

  /// 본문 블록. 노션은 한 요청에 100블록까지라 커밋은 80개에서 자른다.
  ///
  /// 요약이 있으면 커밋 원문은 **토글 아래로** 내린다 — 읽는 사람은 한글 요약을
  /// 보고, 해시가 필요한 사람만 펼친다("이건 왜 다 영어야"). 요약이 없는 자동
  /// 기록은 커밋 제목이 본문이므로 커밋 제목을 한글로 쓰는 규칙(AGENTS.md)이
  /// 여기 그대로 드러난다.
  List<Map<String, dynamic>> children() {
    final commitBlocks = [
      for (final line in commits.take(80)) _bullet(line),
      if (commits.length > 80) _paragraph('… 외 ${commits.length - 80}개'),
      if (commits.isEmpty) _paragraph('이 범위에 커밋이 없습니다.'),
    ];
    if (summary.isEmpty) return [_heading('커밋'), ...commitBlocks];
    return [
      _heading('요약'),
      for (final line in summary) _bullet(line),
      _toggle('커밋 ${commits.length}개 (원문)', commitBlocks),
    ];
  }

  static Map<String, dynamic> _toggle(
    String text,
    List<Map<String, dynamic>> children,
  ) => {
    'object': 'block',
    'type': 'toggle',
    'toggle': {'rich_text': _text(text), 'children': children},
  };

  Map<String, dynamic> toJson() => {
    'properties': properties(),
    'children': children(),
  };

  static List<Map<String, dynamic>> _text(String content) => [
    {
      'type': 'text',
      'text': {
        'content': content.length > 2000 ? content.substring(0, 2000) : content,
      },
    },
  ];

  static Map<String, dynamic> _heading(String text) => {
    'object': 'block',
    'type': 'heading_2',
    'heading_2': {'rich_text': _text(text)},
  };

  static Map<String, dynamic> _bullet(String text) => {
    'object': 'block',
    'type': 'bulleted_list_item',
    'bulleted_list_item': {'rich_text': _text(text)},
  };

  static Map<String, dynamic> _paragraph(String text) => {
    'object': 'block',
    'type': 'paragraph',
    'paragraph': {'rich_text': _text(text)},
  };
}

// --- notion -----------------------------------------------------------------

class _Existing {
  _Existing(this.id, this.url);
  final String id;
  final String url;
}

class _Notion {
  _Notion(this._token);

  final String _token;
  final _client = HttpClient();

  Future<_Existing?> findByBuild(String databaseId, int build) async {
    final json = await _call('POST', '/v1/databases/$databaseId/query', {
      'filter': {
        'property': '빌드',
        'number': {'equals': build},
      },
      'page_size': 1,
    });
    final results = json['results'] as List<dynamic>;
    if (results.isEmpty) return null;
    final page = results.first as Map<String, dynamic>;
    return _Existing(page['id'] as String, page['url'] as String);
  }

  Future<_Existing> createPage(String databaseId, _PageSpec page) async {
    final json = await _call('POST', '/v1/pages', {
      'parent': {'database_id': databaseId},
      'icon': {'type': 'emoji', 'emoji': '🚀'},
      'properties': page.properties(),
      'children': page.children(),
    });
    return _Existing(json['id'] as String, json['url'] as String);
  }

  /// 속성을 덮고 본문을 통째로 갈아 끼운다(기존 블록 삭제 후 추가).
  Future<void> replacePage(String pageId, _PageSpec page) async {
    await _call('PATCH', '/v1/pages/$pageId', {
      'properties': page.properties(),
    });
    final children = await _call(
      'GET',
      '/v1/blocks/$pageId/children?page_size=100',
      null,
    );
    for (final block in children['results'] as List<dynamic>) {
      await _call(
        'DELETE',
        '/v1/blocks/${(block as Map<String, dynamic>)['id']}',
        null,
      );
    }
    await _call('PATCH', '/v1/blocks/$pageId/children', {
      'children': page.children(),
    });
  }

  Future<Map<String, dynamic>> _call(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) async {
    final request = await _client.openUrl(
      method,
      Uri.parse('https://api.notion.com$path'),
    );
    request.headers.set('Authorization', 'Bearer $_token');
    request.headers.set('Notion-Version', _notionVersion);
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
}
