import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/domain/coaching_invite.dart';

const _token =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _link = 'com.teampara.setflow://coaching-invite/$_token';

void main() {
  test('발급된 코드는 공백과 대문자를 정규화한다', () {
    final invite = CoachingInvite.parse('  ${_token.toUpperCase()}\n');
    expect(invite?.token, _token);
    expect(invite?.uri.toString(), _link);
  });

  test('발급된 링크와 공유 문구의 링크 하나를 읽는다', () {
    expect(CoachingInvite.parse(_link)?.token, _token);
    expect(
      CoachingInvite.parse('트레이너 초대 링크\n($_link).\n앱에서 수락해주세요.')?.token,
      _token,
    );
  });

  test('다른 URL이나 변형된 경로에서 초대 코드를 추측하지 않는다', () {
    for (final input in [
      '',
      '123456',
      '${_token}0',
      'https://example.com/$_token',
      'https://setflow.app/invite/coaching?token=$_token',
      'setflow://coaching-invite/$_token',
      'com.teampara.setflow://business-invite/$_token',
      'com.teampara.setflow://coaching-invite/$_token/extra',
      'com.teampara.setflow://coaching-invite/$_token?redirect=evil',
      'com.teampara.setflow://coaching-invite/$_token#fragment',
      'com.teampara.setflow://coaching-invite:123/$_token',
      'com.teampara.setflow://user@coaching-invite/$_token',
      'evil$_link',
      '초대 $_link?redirect=evil',
      '초대 $_token',
      '$_link\n$_link',
    ]) {
      expect(CoachingInvite.parse(input), isNull, reason: input);
    }
  });
}
