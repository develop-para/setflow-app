/// The project's boundary rules, in one place.
///
/// Two things run these: `test/architecture_test.dart` (CI, `flutter test`) and
/// `tool/check_architecture.dart` (a sub-second CLI the Claude Code hook fires
/// after every edit). They share this file so a rule can never be enforced in
/// one place and forgotten in the other.
///
/// Background for every rule: `docs/backend-portability.md`.
library;

import 'dart:io';

const architectureDocs = 'docs/backend-portability.md';

class ArchitectureRule {
  const ArchitectureRule({
    required this.name,
    required this.pattern,
    required this.searchIn,
    required this.allow,
    required this.why,
    required this.instead,
  });

  final String name;
  final RegExp pattern;

  /// Repo-relative files or directories the rule applies to.
  final List<String> searchIn;

  /// Repo-relative paths exempt from the rule.
  final List<String> allow;

  /// Why the rule exists — printed on failure so nobody has to guess.
  final String why;

  /// What to do instead — printed on failure so the fix is obvious.
  final String instead;
}

final architectureRules = <ArchitectureRule>[
  ArchitectureRule(
    name: '벤더 SDK는 어댑터 밖으로 나가지 않는다',
    pattern: RegExp(r'''import\s+['"]package:supabase'''),
    searchIn: const ['lib'],
    allow: const [
      'lib/main.dart', // composition root: binds the adapters
      'lib/data/supabase_app_repository.dart',
      'lib/data/supabase_business_repository.dart',
      'lib/data/supabase_community_repository.dart',
      'lib/data/supabase_routine_catalog_repository.dart',
      'lib/services/supabase_auth_service.dart',
    ],
    why: '앱이 Supabase 타입을 아는 파일이 늘수록 AWS 이전 비용이 그만큼 는다.',
    instead:
        '포트(AuthService / *Repository)를 통해 접근하고, 벤더 타입은 어댑터 안에서 앱 타입으로 변환할 것.',
  ),
  ArchitectureRule(
    name: '화면은 벤더 클래스 이름을 몰라야 한다',
    pattern: RegExp(
      r'\b(SupabaseClient|SupabaseAuthService|RealtimeChannel|'
      r'PostgresChangeEvent|PostgrestException|AuthResponse|GoTrue)\b',
    ),
    searchIn: const ['lib/screens', 'lib/widgets', 'lib/app_state.dart'],
    allow: const [],
    why: '화면이 벤더 타입을 알면 백엔드 교체가 화면 수정으로 번진다.',
    instead: 'Auth.instance / 레포지토리 포트를 쓰고, 필요한 타입은 앱 소유 타입으로 받을 것.',
  ),
  ArchitectureRule(
    name: '백엔드 주소를 코드에 박지 않는다',
    pattern: RegExp(r'supabase\.co'),
    searchIn: const ['lib'],
    allow: const ['lib/services/supabase_config.dart'],
    why: '주소가 흩어져 있으면 이전이 "설정 변경"이 아니라 "코드 수색"이 된다.',
    instead: 'SupabaseConfig에 두고 거기서만 참조할 것.',
  ),
  ArchitectureRule(
    name: '스토리지 URL은 읽는 시점에 만든다',
    pattern: RegExp(r'\b(getPublicUrl|createSignedUrl)\b'),
    searchIn: const ['lib'],
    allow: const [
      'lib/data/supabase_community_repository.dart',
      'lib/data/supabase_business_repository.dart',
    ],
    why: '렌더링된 URL이 DB나 화면에 굳으면 버킷 이전이 데이터 마이그레이션이 된다.',
    instead: 'DB에는 버킷 경로만 저장하고, 레포지토리가 읽을 때 URL로 변환할 것.',
  ),
  ArchitectureRule(
    name: '엣지 펑션 호출은 의도적으로만 늘린다',
    pattern: RegExp(r'functions\s*\.\s*invoke'),
    searchIn: const ['lib'],
    allow: const [],
    why: 'Deno 런타임에 묶여 이전 시 재작성이 확정되고, 회원가입이 실제로 이것 때문에 통째로 막혔다.',
    instead:
        '기본값은 Postgres 함수(RPC). 외부 API 호출처럼 정말 필요하면 tool/architecture_rules.dart의 '
        'allow에 파일을 추가하고 그 커밋에 이유를 남길 것.',
  ),
];

/// A single offending line.
class ArchitectureViolation {
  const ArchitectureViolation(this.path, this.line, this.source);

  final String path;
  final int line;
  final String source;

  @override
  String toString() => '  $path:$line  ${source.trim()}';
}

Iterable<File> _dartFilesUnder(String path) sync* {
  switch (FileSystemEntity.typeSync(path)) {
    case FileSystemEntityType.file:
      yield File(path);
    case FileSystemEntityType.directory:
      for (final entity in Directory(path).listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) yield entity;
      }
    default:
      return;
  }
}

/// Every line in scope that breaks [rule].
List<ArchitectureViolation> findViolations(ArchitectureRule rule) {
  final violations = <ArchitectureViolation>[];
  for (final root in rule.searchIn) {
    for (final file in _dartFilesUnder(root)) {
      final path = file.path.replaceAll(r'\', '/');
      if (rule.allow.contains(path)) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        // A rule can be named in a comment without being used.
        final trimmed = lines[i].trimLeft();
        if (trimmed.startsWith('//')) continue;
        if (rule.pattern.hasMatch(lines[i])) {
          violations.add(ArchitectureViolation(path, i + 1, lines[i]));
        }
      }
    }
  }
  return violations;
}

/// The failure text shown to whoever (or whatever) broke the rule.
String describeFailure(
  ArchitectureRule rule,
  List<ArchitectureViolation> violations,
) {
  return '\n[아키텍처 규칙 위반] ${rule.name}\n'
      '${violations.join('\n')}\n\n'
      '왜: ${rule.why}\n'
      '대신: ${rule.instead}\n'
      '자세히: $architectureDocs\n';
}
