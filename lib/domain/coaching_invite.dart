/// 앱이 실제 발급하는 코칭 초대 링크와 코드를 읽는다.
///
/// 초대 코드는 다른 계정이 사용할 수 있는 값이므로 임의 URL에서 토큰을
/// 꺼내거나 짧은 숫자 코드로 추측하지 않는다. 수락 권한은 서버가 판단한다.
class CoachingInvite {
  const CoachingInvite._(this.token);

  final String token;

  Uri get uri => Uri(
    scheme: 'com.teampara.setflow',
    host: 'coaching-invite',
    path: '/$token',
  );

  static final _code = RegExp(r'^[0-9a-fA-F]{64}$');
  static final _link = RegExp(
    r'^com\.teampara\.setflow://coaching-invite/([0-9a-fA-F]{64})$',
  );

  /// 코드, 링크 또는 링크 하나가 포함된 공유 문구를 허용한다.
  /// 둘 이상의 링크가 있으면 어느 초대인지 선택할 수 없어 거절한다.
  static CoachingInvite? parse(String input) {
    final text = input.trim();
    if (_code.hasMatch(text)) return CoachingInvite._(text.toLowerCase());
    final direct = _link.firstMatch(text);
    if (direct != null) return CoachingInvite._(direct[1]!.toLowerCase());

    final candidates = <CoachingInvite>[];
    for (final word in text.split(RegExp(r'\s+'))) {
      final candidate = word
          .replaceFirst(RegExp(r'''^[<\(\[\{"']+'''), '')
          .replaceFirst(RegExp(r'''[>\)\]\}"'.,;]+$'''), '');
      final match = _link.firstMatch(candidate);
      if (match != null) {
        candidates.add(CoachingInvite._(match[1]!.toLowerCase()));
      }
    }
    return candidates.length == 1 ? candidates.single : null;
  }
}
