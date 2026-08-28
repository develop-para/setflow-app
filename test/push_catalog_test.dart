import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/screens/business_screens.dart';
import 'package:setflow/screens/business_settings_screens.dart';
import 'package:setflow/screens/detail_screens.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/services/push_service.dart';
import 'package:setflow/theme.dart';

/// 푸시 카탈로그의 앱 쪽 절반. 서버 트리거는 스냅샷의 설정 키를 읽으므로
/// (1) 스위치가 그 키로 저장되는지, (2) 탭한 알림이 맞는 탭을 여는지 본다.
void main() {
  setUp(() => Push.bind(_FakePush()));
  tearDown(() => Push.bind(const DisabledPushService()));

  group('설정 스위치', () {
    Future<AppState> pumpNotifications(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(432, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final state = AppState();
      await state.initialize();
      addTearDown(state.dispose);
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: MaterialApp(
            theme: SetflowTheme.light,
            home: const SettingDetailScreen(
              section: SettingSection.notifications,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      return state;
    }

    testWidgets('함께 운동은 기본 켜짐, 리마인더는 기본 꺼짐이고 시각 칩은 켜야 보인다', (tester) async {
      final state = await pumpNotifications(tester);
      expect(state.pushTogether, isTrue);
      expect(state.pushWorkoutReminder, isFalse);
      expect(
        find.byKey(const ValueKey('setting-push-together')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('reminder-hour-19')), findsNothing);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('setting-push-reminder')),
        120,
      );
      await tester.tap(find.byKey(const ValueKey('setting-push-reminder')));
      await tester.pumpAndSettle();
      expect(state.pushWorkoutReminder, isTrue);
      expect(find.byKey(const ValueKey('reminder-hour-19')), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('reminder-hour-7')),
        120,
      );
      await tester.tap(find.byKey(const ValueKey('reminder-hour-7')));
      await tester.pumpAndSettle();
      expect(state.workoutReminderHour, 7);
      await tester.pump(const Duration(milliseconds: 400));
    });

    test('리마인더 시각은 새벽으로 내려가지 않는다', () async {
      final state = AppState();
      await state.initialize();
      addTearDown(state.dispose);
      state.setWorkoutReminderHour(3);
      expect(state.workoutReminderHour, AppSnapshot.earliestReminderHour);
      state.setWorkoutReminderHour(23);
      expect(state.workoutReminderHour, AppSnapshot.latestReminderHour);
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });

    test('네 설정이 서버가 읽는 키로 스냅샷을 왕복한다', () {
      final snapshot = AppSnapshot(
        role: UserRole.guest,
        isDarkMode: false,
        weightUnit: 'kg',
        restDefaultSeconds: 90,
        sessions: const {},
        routines: const [],
        pushTogether: false,
        pushWorkoutReminder: true,
        workoutReminderHour: 7,
        businessNotifications: const {'primary': false, 'feedback': true},
      );
      final json = AppSnapshotCodec.toJson(snapshot);
      final preferences = json['preferences'] as Map<String, dynamic>;
      // 키 이름은 supabase/migrations의 private.push_enabled와 계약이다.
      expect(preferences['pushTogether'], isFalse);
      expect(preferences['pushWorkoutReminder'], isTrue);
      expect(preferences['workoutReminderHour'], 7);
      expect(preferences['businessNotifications'], {
        'primary': false,
        'feedback': true,
      });

      final decoded = AppSnapshotCodec.fromJson(json, exerciseCatalog)!;
      expect(decoded.pushTogether, isFalse);
      expect(decoded.pushWorkoutReminder, isTrue);
      expect(decoded.workoutReminderHour, 7);
      expect(decoded.businessNotifications, {
        'primary': false,
        'feedback': true,
      });
    });

    test('키가 없는 옛 스냅샷은 앱 기본값으로 읽힌다', () {
      final base = AppSnapshotCodec.toJson(
        AppSnapshot(
          role: UserRole.guest,
          isDarkMode: false,
          weightUnit: 'kg',
          restDefaultSeconds: 90,
          sessions: const {},
          routines: const [],
        ),
      );
      (base['preferences'] as Map<String, dynamic>)
        ..remove('pushTogether')
        ..remove('pushWorkoutReminder')
        ..remove('workoutReminderHour')
        ..remove('businessNotifications');
      final decoded = AppSnapshotCodec.fromJson(base, exerciseCatalog)!;
      expect(decoded.pushTogether, isTrue);
      expect(decoded.pushWorkoutReminder, isFalse);
      expect(decoded.workoutReminderHour, 19);
      expect(decoded.businessNotifications, isEmpty);
    });

    testWidgets('업무 알림 스위치는 라이브에서도 저장된다', (tester) async {
      final state = AppState();
      await state.initialize();
      addTearDown(state.dispose);
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: MaterialApp(
            theme: SetflowTheme.light,
            home: const BusinessSettingsNotificationsScreen(
              role: UserRole.trainer,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        state.businessNotificationPreference(
          UserRole.trainer,
          'primary',
          fallback: true,
        ),
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('business-push-primary')));
      await tester.pumpAndSettle();
      expect(state.businessNotifications['primary'], isFalse);
      // 정산·마케팅 스위치는 뒤에 보낼 알림이 없어서 없다.
      expect(find.text('정산 및 환불 현황'), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('탭한 알림이 여는 탭', () {
    PushOpen open(String kind, [String? event]) =>
        PushOpen(kind: kind, data: {'event': ?event});

    test('회원 셸', () {
      expect(memberPageForPush(open('together', 'party_joined')), 1);
      expect(memberPageForPush(open('workout_reminder')), 2);
      expect(memberPageForPush(open('community_reaction')), 3);
      expect(
        memberPageForPush(open('account', 'trainer_application_approved')),
        4,
      );
      expect(memberPageForPush(open('coaching_feedback', 'routine_share')), 2);
      expect(
        memberPageForPush(open('coaching_feedback', 'member_assigned')),
        4,
      );
      expect(
        memberPageForPush(open('coaching_feedback', 'session_feedback')),
        0,
      );
      expect(
        memberPageForPush(open('business', 'consultation_created')),
        isNull,
      );
    });

    test('업무 셸', () {
      const trainer = UserRole.trainer;
      expect(
        businessPageForPush(trainer, open('business', 'consultation_created')),
        3,
      );
      expect(
        businessPageForPush(
          UserRole.gym,
          open('business', 'consultation_message'),
        ),
        2,
      );
      expect(
        businessPageForPush(
          trainer,
          open('business_activity', 'routine_review_approved'),
        ),
        2,
      );
      expect(
        businessPageForPush(trainer, open('business', 'member_assigned')),
        1,
      );
      expect(businessPageForPush(trainer, open('account')), 0);
      expect(businessPageForPush(trainer, open('together')), isNull);
      expect(
        businessPageForPush(
          UserRole.admin,
          open('business', 'consultation_created'),
        ),
        isNull,
      );
    });

    test('같은 알림은 한 번만 처리된다 — 일련번호가 다르다', () {
      final first = open('together');
      final second = open('together');
      expect(first.serial, isNot(second.serial));
      expect(first.event, isNull);
    });
  });
}

class _FakePush implements PushService {
  final _opens = StreamController<PushOpen>.broadcast();

  @override
  bool get isAvailable => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<String?> currentToken() async => 'token';

  @override
  Stream<String> get tokenChanges => const Stream<String>.empty();

  @override
  Future<void> deleteToken() async {}

  @override
  Stream<PushOpen> get opens => _opens.stream;

  @override
  Future<PushOpen?> initialOpen() async => null;
}
