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
      'lib/data/supabase_together_repository.dart',
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
    name: '토스트는 AppSnackbar 한 곳에서만 띄운다',
    pattern: RegExp(r'(showSnackBar|ScaffoldMessenger)'),
    searchIn: const ['lib'],
    allow: const ['lib/widgets/common.dart'],
    why:
        '토스트는 화면 상단 30%에 떠야 한다(하단은 엄지·기록 디스크·휴식 타이머가 쓴다). '
        'SnackBar는 Scaffold 하단에 고정이라 직접 부르면 그 규칙을 조용히 우회한다.',
    instead:
        'AppSnackbar.success / error / info (또는 showMessage)를 쓸 것. '
        '위치는 AppSnackbar.topFraction 한 곳에서 정한다.',
  ),
  ArchitectureRule(
    name: '바텀시트는 showSetflowSheet 한 곳에서만 연다',
    pattern: RegExp(r'showModalBottomSheet'),
    searchIn: const ['lib'],
    allow: const ['lib/widgets/common.dart'],
    why:
        'showModalBottomSheet는 하단 세이프에리어를 콘텐츠에 넘긴다(useSafeArea: true도 '
        'SafeArea(bottom: false)라 하단은 제외된다). 직접 부르면 그걸 잊기 쉽고, 실제로 숫자 '
        '다이얼의 "적용"이 내비게이션 바 아래 28px에 깔려 세트를 저장할 수 없었다.',
    instead:
        'showSetflowSheet(context, builder: ...)를 쓸 것. 하단 인셋을 거기서 한 번만 넣는다 '
        '(SafeArea는 중첩해도 이중으로 들어가지 않으니 시트 안의 SafeArea는 그대로 둬도 된다).',
  ),
  ArchitectureRule(
    name: '글자 크기는 사다리에서만 고른다',
    pattern: RegExp(r'fontSize:\s*[0-9]'),
    searchIn: const ['lib'],
    allow: const [
      'lib/theme/tokens.dart', // 사다리 자체를 정의하는 곳
      'lib/theme.dart', // textTheme의 역할별 크기
      'lib/widgets/kinetic.dart', // 알파 .035 워터마크 숫자 — 글자가 아니라 그래픽
    ],
    why:
        '화면에 fontSize가 307군데 박혀 있었고 서로 다른 값이 25종이었다. '
        '13과 13.5, 17과 18, 25·26·27이 한 앱 안에 같이 있었고, '
        '거의 같지만 미묘하게 다른 값은 눈에 "안 맞는다"로만 보인다.',
    instead:
        'SetflowFontSize에서 고르거나(촘촘한 캡션 등), 역할이 맞으면 '
        'theme.textTheme.*를 쓸 것. 사다리에 없는 크기가 정말 필요하면 '
        'tokens.dart의 SetflowFontSize에 이름을 붙여 추가한다.',
  ),
  ArchitectureRule(
    name: '여백은 짝수 그리드를 벗어나지 않는다',
    pattern: RegExp(
      // 여백은 EdgeInsets 로도 SizedBox 로도 만들어진다. 둘 다 같은 그리드다.
      r'(?:EdgeInsets\.(?:all|symmetric|only|fromLTRB)\([^)]*'
      r'|SizedBox\((?:width|height):\s*)'
      r'(?<![\w.])\d*[13579](?![\d.])',
    ),
    searchIn: const ['lib'],
    allow: const [],
    why:
        'SetflowSpacing은 전부 짝수다(작은 쪽 2씩, 20 위로 4씩). 홀수가 들어오면 그리드를 '
        '벗어난 것이고, 실제로 5·7·9·11·13·15가 65군데 섞여 1px씩 어긋나 있었다. '
        '그 어긋남은 "레이아웃이 안 맞는다"로만 보이고 원인은 안 보인다.',
    instead:
        '위아래 짝수 중 하나로 붙일 것. SetflowSpacing에서 고르면 확실하다. '
        '정말 홀수여야 하는 자리라면 tokens.dart에 이름을 붙여 추가하고 allow에 파일을 넣는다.',
  ),
  ArchitectureRule(
    name: '모서리 반경은 사다리에서만 고른다',
    pattern: RegExp(r'BorderRadius\.circular\(\s*[0-9]'),
    searchIn: const ['lib'],
    allow: const ['lib/theme/tokens.dart'],
    why:
        '반경이 76군데에 숫자로 박혀 있었고 서로 다른 값이 17종이었다. 16과 14, 17과 18, '
        '20과 18이 한 화면 안에 섞이면 카드마다 모서리가 미묘하게 달라 보인다.',
    instead: 'SetflowRadii(xs·sm·md·lg·xl·full)에서 고를 것.',
  ),
  ArchitectureRule(
    name: '색은 토큰에서만 꺼낸다',
    pattern: RegExp(r'Color\(0x'),
    searchIn: const ['lib/screens', 'lib/widgets'],
    allow: const [],
    why:
        '화면에 hex가 박히면 그 값이 무엇을 뜻하는지 아무도 모르고, 라이트·다크 어느 쪽을 '
        '위한 값인지도 남지 않는다. 실제로 이미 SetflowNeutral에 있는 값을 다시 적은 곳이 있었다.',
    instead:
        'SetflowColors / SetflowNeutral에서 고를 것. 테마 따라 뒤집히는 면 위에서는 '
        'context.setflowColors를 쓴다. 정말 새 값이면 tokens.dart에 이름을 붙여 추가한다.',
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
