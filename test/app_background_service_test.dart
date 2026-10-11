import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/services/app_background_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.teampara.setflow/app_background');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('네이티브에 작업을 백그라운드로 옮기도록 요청한다', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });

    expect(await AppBackgroundService.moveToBackground(), isTrue);
    expect(calls.single.method, 'moveToBackground');
    expect(calls.single.arguments, isNull);
  });

  test('작업을 옮기지 못하면 실패를 반환한다', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => false);

    expect(await AppBackgroundService.moveToBackground(), isFalse);
  });

  test('호스트의 응답이 없으면 성공으로 처리하지 않는다', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);

    expect(await AppBackgroundService.moveToBackground(), isFalse);
  });

  test('지원하지 않는 호스트에서는 실패를 반환한다', () async {
    messenger.setMockMethodCallHandler(channel, null);

    expect(await AppBackgroundService.moveToBackground(), isFalse);
  });

  test('네이티브 오류는 앱 종료로 이어지지 않는다', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'unavailable');
    });

    expect(await AppBackgroundService.moveToBackground(), isFalse);
  });
}
