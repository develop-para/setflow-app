/// 앱의 웹 주소 — 초대 링크처럼 **앱 밖에서 열리는** https 주소의 근거지.
///
/// `setflow.app`이 아니다. 그 도메인은 남의 것(DJ 셋 사이트)이고, 우리 웹 빌드는
/// Vercel(`docs/web-deploy.md`)에 있다. 링크가 착지하는 정적 페이지(`web/join.html`)와
/// 안드로이드 앱링크 검증 파일(`web/.well-known/assetlinks.json`)이 같은 곳에서
/// 서빙되므로, 도메인을 바꾸면 이 값과 `AndroidManifest.xml`의 host를 같이 바꾼다.
abstract final class SetflowWeb {
  static const origin = String.fromEnvironment(
    'SETFLOW_WEB_URL',
    defaultValue: 'https://setflow-app.vercel.app',
  );

  static Uri get _base => Uri.parse(origin);

  /// 이 host로 온 https 링크만 앱이 제 것으로 받는다.
  static String get host => _base.host;

  /// 함께 방 초대 링크. `vercel.json`이 `/together/join`을 `join.html`로 보낸다.
  static Uri togetherJoin(String code) => _base.replace(
    path: '/together/join',
    queryParameters: {'code': code.trim().toUpperCase()},
  );
}
