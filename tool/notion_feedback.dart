// 노션 "요청 사항" 보드(비개발자가 앱을 써 보고 남기는 버그·기능 요청·질문)를
// 에이전트가 읽고 처리 결과를 되돌려 쓰는 통로.
//
//   dart tool/notion_feedback.dart list                # 완료 아닌 카드 목록
//   dart tool/notion_feedback.dart list --all
//   dart tool/notion_feedback.dart show <id|url>       # 속성 + 본문 + 첨부 이미지 내려받기 + 댓글
//   dart tool/notion_feedback.dart update <id|url> [--status 진행중|완료|시작전]
//        [--result "처리 결과 한 줄"] [--comment "요청자에게 남길 말"] [--build 140]
//
// show 는 첨부 이미지를 build/notion-feedback/<id>/ 에 내려받고 경로를 찍는다 —
// 에이전트는 그 파일을 열어 보면 된다(노션 첨부 URL 은 1시간짜리 서명 URL 이라
// 링크만 넘기면 곧 죽는다). update 의 --build 는 "반영 배포" 관계를 배포 기록의
// 그 빌드 행에 건다.
//
// 노션 API 를 아는 파일은 tool/notion_api.dart 와 이 파일뿐이다. 스킬(.claude/skills/
// feedback-inbox)이 이 스크립트를 부른다 — 노션 MCP 로 보드를 직접 고치지 말 것.

import 'dart:io';

import 'notion_api.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }
  final root = repoRoot();
  final api = NotionClient(notionToken(root));
  final databaseId =
      Platform.environment['NOTION_FEEDBACK_DB'] ??
      configValue(root, 'notion-feedback.json', 'databaseId');
  final releaseDatabaseId =
      Platform.environment['NOTION_RELEASE_DB'] ??
      configValue(root, 'notion-release.json', 'databaseId');
  try {
    switch (args.first) {
      case 'list':
        await _list(api, databaseId, all: args.contains('--all'));
      case 'show':
        if (args.length < 2) throw const FormatException('show <id|url>');
        await _show(
          api,
          root,
          normalizePageId(args[1]),
          _option(args, '--out'),
        );
      case 'update':
        if (args.length < 2) throw const FormatException('update <id|url> ...');
        await _update(
          api,
          normalizePageId(args[1]),
          releaseDatabaseId,
          status: _option(args, '--status'),
          result: _option(args, '--result'),
          comment: _option(args, '--comment'),
          build: _option(args, '--build'),
        );
      default:
        stderr.writeln(_usage);
        exitCode = 64;
    }
  } finally {
    api.close();
  }
}

const _usage = '''
사용법:
  dart tool/notion_feedback.dart list [--all]
  dart tool/notion_feedback.dart show <id|url> [--out 디렉터리]
  dart tool/notion_feedback.dart update <id|url> [--status 진행중|완료|시작전]
       [--result "처리 결과"] [--comment "요청자에게"] [--build N]
''';

/// 댓글 API 는 통합의 추가 권한이다. notion.so/my-integrations 에서 "MCP" 통합 →
/// 기능 → 댓글 읽기·삽입을 켜면 된다. 켜기 전까지 댓글은 못 읽고 못 단다.
const _commentPermissionHint =
    '노션 통합(MCP)에 "댓글 읽기/삽입" 권한을 켜야 합니다: '
    'notion.so/my-integrations → MCP → 기능(Capabilities)';

String? _option(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i < 0 || i + 1 >= args.length) return null;
  return args[i + 1];
}

// --- list -------------------------------------------------------------------

Future<void> _list(
  NotionClient api,
  String databaseId, {
  required bool all,
}) async {
  final pages = await api.collect('POST', '/v1/databases/$databaseId/query', {
    if (!all)
      'filter': {
        'property': '상태',
        'status': {'does_not_equal': '완료'},
      },
    'sorts': [
      {'property': '접수일', 'direction': 'ascending'},
    ],
  });
  if (pages.isEmpty) {
    stdout.writeln(all ? '카드가 없습니다.' : '처리할 카드가 없습니다.');
    return;
  }
  final rank = {'급함': 0, '보통': 1, '낮음': 2};
  pages.sort((a, b) {
    final pa = rank[_select(a, '우선순위')] ?? 1;
    final pb = rank[_select(b, '우선순위')] ?? 1;
    return pa.compareTo(pb);
  });
  for (final page in pages) {
    final props = page['properties'] as Map<String, dynamic>;
    final title = plain((props['이름'] as Map<String, dynamic>)['title']);
    final status = _status(page);
    final created =
        (props['접수일'] as Map<String, dynamic>?)?['created_time'] as String?;
    final who = _person(page, '요청자');
    stdout.writeln(
      '[${_select(page, '유형') ?? '유형 없음'}]'
      '[${_select(page, '우선순위') ?? '보통'}]'
      '[${_select(page, '화면') ?? '화면 없음'}] '
      '$title — $status · $who · ${created?.substring(0, 10) ?? ''}\n'
      '    ${page['id']}',
    );
  }
}

String? _select(Map<String, dynamic> page, String name) {
  final prop =
      (page['properties'] as Map<String, dynamic>)[name]
          as Map<String, dynamic>?;
  return (prop?['select'] as Map<String, dynamic>?)?['name'] as String?;
}

String _status(Map<String, dynamic> page) {
  final prop =
      (page['properties'] as Map<String, dynamic>)['상태']
          as Map<String, dynamic>?;
  return (prop?['status'] as Map<String, dynamic>?)?['name'] as String? ?? '';
}

String _person(Map<String, dynamic> page, String name) {
  final prop =
      (page['properties'] as Map<String, dynamic>)[name]
          as Map<String, dynamic>?;
  final user = prop?['created_by'] as Map<String, dynamic>?;
  return user?['name'] as String? ?? '?';
}

// --- show -------------------------------------------------------------------

Future<void> _show(
  NotionClient api,
  String root,
  String pageId,
  String? outDir,
) async {
  final page = await api.call('GET', '/v1/pages/$pageId');
  final props = page['properties'] as Map<String, dynamic>;
  final short = pageId.replaceAll('-', '').substring(0, 8);
  final dir = Directory(outDir ?? '$root/build/notion-feedback/$short');

  stdout.writeln('# ${plain((props['이름'] as Map<String, dynamic>)['title'])}');
  stdout.writeln('URL: ${page['url']}');
  for (final name in const ['유형', '우선순위', '화면', '기기', '상태']) {
    final value = name == '상태' ? _status(page) : _select(page, name);
    if (value != null && value.isNotEmpty) stdout.writeln('$name: $value');
  }
  final version = plain((props['앱 버전'] as Map<String, dynamic>?)?['rich_text']);
  if (version.isNotEmpty) stdout.writeln('앱 버전: $version');
  stdout.writeln(
    '요청자: ${_person(page, '요청자')} · 접수일: '
    '${((props['접수일'] as Map<String, dynamic>?)?['created_time'] as String? ?? '').substring(0, 10)}',
  );
  final result = plain((props['처리 결과'] as Map<String, dynamic>?)?['rich_text']);
  if (result.isNotEmpty) stdout.writeln('처리 결과(기존): $result');

  stdout.writeln('\n## 본문');
  var images = 0;
  Future<void> walk(String blockId, String indent) async {
    final blocks = await api.collect(
      'GET',
      '/v1/blocks/$blockId/children?page_size=100',
    );
    for (final block in blocks) {
      final type = block['type'] as String;
      final data = block[type] as Map<String, dynamic>? ?? const {};
      switch (type) {
        case 'image' || 'file' || 'pdf' || 'video':
          final source = data[data['type']] as Map<String, dynamic>?;
          final url = source?['url'] as String?;
          if (url == null) break;
          images++;
          final ext = _extension(url, type);
          final target = File('${dir.path}/$type-$images$ext');
          try {
            await api.download(url, target);
            stdout.writeln('$indent[첨부 $type → ${target.path}]');
          } on Object catch (error) {
            stdout.writeln('$indent[첨부 $type 내려받기 실패: $error]');
          }
          final caption = plain(data['caption']);
          if (caption.isNotEmpty) stdout.writeln('$indent  캡션: $caption');
        case 'bulleted_list_item' || 'numbered_list_item':
          stdout.writeln('$indent- ${plain(data['rich_text'])}');
        case 'to_do':
          final done = data['checked'] == true ? 'x' : ' ';
          stdout.writeln('$indent- [$done] ${plain(data['rich_text'])}');
        case 'heading_1' || 'heading_2' || 'heading_3':
          stdout.writeln('$indent## ${plain(data['rich_text'])}');
        case 'code':
          stdout.writeln('$indent```\n${plain(data['rich_text'])}\n$indent```');
        case 'divider':
          stdout.writeln('$indent---');
        case 'child_page':
          stdout.writeln('$indent[하위 페이지: ${data['title']}]');
        default:
          final content = plain(data['rich_text']);
          if (content.isNotEmpty) stdout.writeln('$indent$content');
      }
      if (block['has_children'] == true && type != 'child_page') {
        await walk(block['id'] as String, '$indent  ');
      }
    }
  }

  await walk(pageId, '');
  if (images == 0) stdout.writeln('(첨부 없음)');

  // 댓글은 통합에 "댓글 읽기/삽입" 권한이 켜져 있어야 보인다. 없으면 본문까지는
  // 보여 주고 그 사실만 적는다 — 권한 하나 때문에 카드를 못 읽으면 안 된다.
  List<Map<String, dynamic>> comments;
  try {
    comments = await api.collect(
      'GET',
      '/v1/comments?block_id=$pageId&page_size=100',
    );
  } on HttpException catch (error) {
    if (!error.message.contains('403')) rethrow;
    stdout.writeln('\n(댓글 권한 없음 — $_commentPermissionHint)');
    comments = const [];
  }
  if (comments.isNotEmpty) {
    stdout.writeln('\n## 댓글');
    for (final comment in comments) {
      final who =
          ((comment['created_by'] as Map<String, dynamic>?)?['name']
              as String?) ??
          'bot';
      final when = (comment['created_time'] as String).substring(0, 16);
      stdout.writeln('- $who ($when): ${plain(comment['rich_text'])}');
    }
  }
}

String _extension(String url, String type) {
  final path = Uri.parse(url).path;
  final dot = path.lastIndexOf('.');
  if (dot >= 0 && path.length - dot <= 6) return path.substring(dot);
  return switch (type) {
    'image' => '.png',
    'pdf' => '.pdf',
    'video' => '.mp4',
    _ => '',
  };
}

// --- update -----------------------------------------------------------------

Future<void> _update(
  NotionClient api,
  String pageId,
  String releaseDatabaseId, {
  String? status,
  String? result,
  String? comment,
  String? build,
}) async {
  final properties = <String, dynamic>{};
  if (status != null) {
    final name = switch (status.replaceAll(' ', '')) {
      '진행중' => '진행 중',
      '완료' => '완료',
      '시작전' => '시작 전',
      _ => throw FormatException('--status 는 진행중|완료|시작전 중 하나: $status'),
    };
    properties['상태'] = {
      'status': {'name': name},
    };
  }
  if (result != null) properties['처리 결과'] = {'rich_text': text(result)};
  if (build != null) {
    final number = int.tryParse(build);
    if (number == null) throw FormatException('--build 는 숫자: $build');
    final rows = await api.call(
      'POST',
      '/v1/databases/$releaseDatabaseId/query',
      {
        'filter': {
          'property': '빌드',
          'number': {'equals': number},
        },
        'page_size': 1,
      },
    );
    final results = rows['results'] as List<dynamic>;
    if (results.isEmpty) {
      throw StateError('배포 기록에 빌드 $number 행이 없습니다. 배포가 끝난 뒤에 거세요.');
    }
    properties['반영 배포'] = {
      'relation': [
        {'id': (results.first as Map<String, dynamic>)['id']},
      ],
    };
  }
  if (properties.isNotEmpty) {
    await api.call('PATCH', '/v1/pages/$pageId', {'properties': properties});
  }
  if (comment != null) {
    try {
      await api.call('POST', '/v1/comments', {
        'parent': {'page_id': pageId},
        'rich_text': text(comment),
      });
    } on HttpException catch (error) {
      if (!error.message.contains('403')) rethrow;
      // 속성은 이미 바뀌었다. 댓글만 못 단 것이니 그 사실과 고치는 법을 말한다.
      stderr.writeln('댓글을 달지 못했습니다 — $_commentPermissionHint');
      exitCode = 2;
    }
  }
  if (properties.isEmpty && comment == null) {
    stdout.writeln(
      '바꿀 것이 없습니다. --status / --result / --comment / --build 중 하나를 주세요.',
    );
    return;
  }
  final page = await api.call('GET', '/v1/pages/$pageId');
  stdout.writeln('갱신했습니다: ${page['url']}');
}
