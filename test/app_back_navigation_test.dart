import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/main.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/widgets/common.dart';

void main() {
  const backgroundChannel = MethodChannel(
    'com.teampara.setflow/app_background',
  );
  const restChannel = MethodChannel('com.teampara.setflow/rest_timer');
  const hint = '한 번 더 누르면 백그라운드로 이동해요';
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final backgroundCalls = <MethodCall>[];
  final platformCalls = <MethodCall>[];
  final restCalls = <MethodCall>[];

  setUp(() {
    backgroundCalls.clear();
    platformCalls.clear();
    restCalls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(backgroundChannel, (
      call,
    ) async {
      backgroundCalls.add(call);
      return true;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(restChannel, (
      call,
    ) async {
      restCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      backgroundChannel,
      null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(restChannel, null);
  });

  Future<AppState> launch(
    WidgetTester tester, {
    AppRepository? repository,
  }) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    await tester.pumpWidget(SetflowApp(repository: repository));
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();
    addTearDown(() async {
      AppSnackbar.dismiss();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.binding.setSurfaceSize(null);
    });
    return AppScope.of(tester.element(find.byType(MemberShell)));
  }

  Future<void> back(WidgetTester tester) async {
    final handled = tester.binding.handlePopRoute();
    await tester.pump();
    // The second back commits focused edits on the next event-loop turn.
    await tester.pump(const Duration(milliseconds: 20));
    expect(await handled, isTrue);
    await tester.pump(const Duration(milliseconds: 350));
  }

  NavigatorState navigator(WidgetTester tester) =>
      tester.state<NavigatorState>(find.byType(Navigator).first);

  testWidgets(
    'root back warns once and double back backgrounds without exiting',
    (tester) async {
      await launch(tester);
      expect(
        platformCalls.where(
          (call) => call.method == 'SystemNavigator.setFrameworkHandlesBack',
        ),
        isNotEmpty,
        reason: 'Android predictive back must reach the root guard',
      );
      expect(
        platformCalls
            .where(
              (call) =>
                  call.method == 'SystemNavigator.setFrameworkHandlesBack',
            )
            .every((call) => call.arguments == true),
        isTrue,
      );

      await back(tester);
      expect(find.text(hint), findsOneWidget);
      expect(backgroundCalls, isEmpty);
      expect(find.byType(MemberShell), findsOneWidget);

      await back(tester);
      expect(backgroundCalls.map((call) => call.method), ['moveToBackground']);
      expect(find.byType(MemberShell), findsOneWidget);
      expect(
        platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
        isEmpty,
      );
    },
  );

  testWidgets('timeout and an intervening tap each require a new double back', (
    tester,
  ) async {
    await launch(tester);
    await back(tester);
    await tester.pump(const Duration(seconds: 2));
    await back(tester);
    expect(backgroundCalls, isEmpty);

    await tester.tapAt(const Offset(420, 400));
    await back(tester);
    expect(backgroundCalls, isEmpty);
    await back(tester);
    expect(backgroundCalls, hasLength(1));
  });

  testWidgets(
    'a cancelled edge pointer does not break consecutive system backs',
    (tester) async {
      await launch(tester);
      await back(tester);
      final gesture = await tester.startGesture(const Offset(1, 400));
      await gesture.moveBy(const Offset(25, 0));
      // Android steals the pointer stream when recognizing the system gesture.
      await gesture.cancel();
      await back(tester);
      expect(backgroundCalls, hasLength(1));
    },
  );

  testWidgets('returning from the background clears the first back press', (
    tester,
  ) async {
    await launch(tester);
    await back(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await back(tester);
    expect(backgroundCalls, isEmpty);
    await back(tester);
    expect(backgroundCalls, hasLength(1));
  });

  testWidgets('detail screens pop before starting a fresh root back sequence', (
    tester,
  ) async {
    await launch(tester);
    await back(tester);
    unawaited(
      navigator(tester).push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(
            key: ValueKey('back-detail'),
            body: SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await back(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('back-detail')), findsNothing);
    expect(backgroundCalls, isEmpty);
    await back(tester);
    expect(backgroundCalls, isEmpty);
    await back(tester);
    expect(backgroundCalls, hasLength(1));
  });

  testWidgets('dialogs and modal sheets close without counting as root backs', (
    tester,
  ) async {
    await launch(tester);
    final context = tester.element(find.byType(MemberShell));
    await back(tester);
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('뒤로가기 확인')),
      ),
    );
    await tester.pumpAndSettle();
    await back(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(backgroundCalls, isEmpty);
    unawaited(
      showSetflowSheet<void>(
        context,
        builder: (_) => const SizedBox(height: 100, child: Text('테스트 시트')),
      ),
    );
    await tester.pumpAndSettle();
    await back(tester);
    expect(find.text('테스트 시트'), findsNothing);
    await back(tester);
    expect(backgroundCalls, isEmpty);
    await back(tester);
    expect(backgroundCalls, hasLength(1));
  });

  testWidgets('two committed predictive root gestures move to background', (
    tester,
  ) async {
    await launch(tester);
    Future<void> gesture() async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/backgesture',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('startBackGesture', {
            'touchOffset': [1.0, 400.0],
            'progress': 0.0,
            'swipeEdge': 0,
          }),
        ),
        (_) {},
      );
      final committed = tester.binding.defaultBinaryMessenger
          .handlePlatformMessage(
            'flutter/backgesture',
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('commitBackGesture'),
            ),
            (_) {},
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await committed;
      await tester.pump(const Duration(milliseconds: 350));
    }

    await gesture();
    expect(find.text(hint), findsOneWidget);
    expect(backgroundCalls, isEmpty);
    await gesture();
    expect(backgroundCalls, hasLength(1));
    expect(
      platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
      isEmpty,
    );
  });

  testWidgets(
    'inline record sheet and tab history are handled before root backs',
    (tester) async {
      await launch(tester);
      final record = find.byKey(const ValueKey('bottom-bar-center-action'));
      await tester.tap(record);
      await tester.pumpAndSettle();
      await tester.tap(record);
      await tester.pumpAndSettle();
      expect(find.text('무엇으로 기록할까요?'), findsOneWidget);
      await back(tester);
      expect(find.text('무엇으로 기록할까요?'), findsNothing);
      await back(tester); // Record -> previous tab (home).
      expect(find.byType(HomeScreen), findsOneWidget);
      await back(tester); // First root back.
      expect(backgroundCalls, isEmpty);
      await back(tester);
      expect(backgroundCalls, hasLength(1));
    },
  );

  testWidgets(
    'local workout save completes before backgrounding and rest continues',
    (tester) async {
      final repository = _BlockedSaveRepository();
      final state = await launch(tester, repository: repository);
      state.startRestTimer(90);
      await tester.pump(const Duration(milliseconds: 100));
      await back(tester);
      repository.blockSave = true;
      final today = state.dateOnly(DateTime.now());
      state.addExercise(today, state.exercises.first);
      final handled = tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(repository.saveStarted, isTrue);
      expect(
        backgroundCalls,
        isEmpty,
        reason: 'Leave only after local storage is durable',
      );
      repository.releaseSave.complete();
      await tester.pump();
      expect(await handled, isTrue);
      expect(backgroundCalls, hasLength(1));
      expect(repository.snapshot!.sessions[today]!.exercises, hasLength(1));
      expect(state.restRemaining, greaterThan(0));
      expect(restCalls.where((call) => call.method == 'cancel'), isEmpty);
      expect(restCalls.where((call) => call.method == 'start'), hasLength(1));
    },
  );
}

class _BlockedSaveRepository extends MemoryAppRepository {
  bool blockSave = false;
  bool saveStarted = false;
  final releaseSave = Completer<void>();

  @override
  Future<void> save(AppSnapshot snapshot) async {
    if (blockSave) {
      saveStarted = true;
      await releaseSave.future;
    }
    await super.save(snapshot);
  }
}
