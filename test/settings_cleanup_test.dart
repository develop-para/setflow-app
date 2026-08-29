import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/screens/detail_screens.dart';
import 'package:setflow/screens/member_mypage_screen.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

/// 설정 화면의 중복 제거와, 그 자리에 실제로 만들어 넣은 것들.
///
/// 예전에는 무게 단위가 두 곳, 다크 모드가 두 곳(스위치 + '디스플레이' 화면),
/// 운동 목표가 마이와 설정 양쪽에 있었다. 같은 값을 두 곳에서 고치면 어느 쪽이
/// 진짜인지 사용자가 알 수 없고, 한쪽만 고치는 회귀가 조용히 들어온다.
void main() {
  Future<AppState> pump(WidgetTester tester, Widget home) async {
    await tester.binding.setSurfaceSize(const Size(432, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(theme: SetflowTheme.light, home: home),
      ),
    );
    // initialize의 250ms 저장 디바운스를 여기서 비운다.
    await tester.pump(const Duration(milliseconds: 400));
    return state;
  }

  group('중복 제거', () {
    testWidgets('설정 본문에는 무게 단위 컨트롤이 없다', (tester) async {
      await pump(tester, const SettingsScreen());
      // 무게 단위는 '운동 기록 환경설정' 안에만 산다.
      expect(find.text('무게 단위'), findsNothing);
      expect(find.byKey(const ValueKey('settings-workout')), findsOneWidget);
    });

    testWidgets('다크 모드는 스위치 하나뿐 — 디스플레이 화면이 사라졌다', (tester) async {
      await pump(tester, const SettingsScreen());
      expect(find.text('다크 모드'), findsOneWidget);
      expect(find.text('디스플레이'), findsNothing);
    });

    testWidgets('운동 목표 진입점은 설정 > 계정 & 프로필 한 곳이다', (tester) async {
      await pump(tester, const MyPageScreen());
      expect(find.text('운동 목표'), findsNothing);

      await pump(
        tester,
        const SettingDetailScreen(section: SettingSection.account),
      );
      expect(find.text('운동 목표'), findsOneWidget);
    });

    testWidgets('운동 장소 진입점도 하나 — 설정의 연결 센터 관리가 사라졌다', (tester) async {
      await pump(tester, const SettingsScreen());
      expect(find.text('연결 센터 관리'), findsNothing);

      await pump(tester, const MyPageScreen());
      expect(find.text('운동 장소 및 센터'), findsOneWidget);
    });
  });

  group('1RM 공식', () {
    testWidgets('죽은 타일이 아니라 실제로 고를 수 있다', (tester) async {
      final state = await pump(
        tester,
        const SettingDetailScreen(section: SettingSection.workout),
      );
      expect(state.oneRepMaxFormula, OneRepMaxFormula.average);

      await tester.tap(
        find.byKey(const ValueKey('setting-one-rep-max-formula')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('formula-brzycki')));
      await tester.pumpAndSettle();

      expect(state.oneRepMaxFormula, OneRepMaxFormula.brzycki);
      expect(find.text('Brzycki'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
    });

    test('고른 공식이 추정값을 실제로 바꾼다', () {
      // 10회에서는 두 공식이 우연히 같은 값(133.3)이라 아무것도 구별하지
      // 못한다. 갈리는 곳에서 봐야 한다 — 5회면 116.7 대 112.5다.
      final epley = PerformanceEngine.estimate(
        100,
        5,
        formula: OneRepMaxFormula.epley,
      )!;
      final brzycki = PerformanceEngine.estimate(
        100,
        5,
        formula: OneRepMaxFormula.brzycki,
      )!;
      final average = PerformanceEngine.estimate(100, 5)!;

      expect(epley.value, closeTo(116.7, .1));
      expect(brzycki.value, closeTo(112.5, .1));
      expect(average.value, closeTo(114.6, .1));
      // 고른 것만 value가 되고, 두 원시값은 언제나 함께 실려 온다.
      expect(epley.brzycki, closeTo(brzycki.value, .001));
      expect(brzycki.epley, closeTo(epley.value, .001));
      expect(average.value, closeTo((epley.epley + brzycki.brzycki) / 2, .001));
    });

    test('1회는 공식과 무관하게 그 무게가 1RM이다', () {
      for (final formula in OneRepMaxFormula.values) {
        expect(
          PerformanceEngine.estimate(120, 1, formula: formula)!.value,
          120,
        );
      }
    });

    test('공식은 스냅샷 왕복에서 살아남고, 모르는 값은 평균으로 떨어진다', () {
      AppSnapshot base(OneRepMaxFormula formula) => AppSnapshot(
        role: UserRole.guest,
        isDarkMode: false,
        weightUnit: 'kg',
        restDefaultSeconds: 90,
        sessions: const {},
        routines: const [],
        oneRepMaxFormula: formula,
      );

      final decoded = AppSnapshotCodec.fromJson(
        AppSnapshotCodec.toJson(base(OneRepMaxFormula.epley)),
        exerciseCatalog,
      );
      expect(decoded!.oneRepMaxFormula, OneRepMaxFormula.epley);
      expect(oneRepMaxFormulaFromStorage('없는값'), OneRepMaxFormula.average);
      expect(oneRepMaxFormulaFromStorage(null), OneRepMaxFormula.average);
    });
  });

  group('RIR', () {
    test('0은 값이고 null은 미입력이다 — clearRir로만 지운다', () {
      final state = AppState();
      addTearDown(state.dispose);
      final set = WorkoutSetEntry(number: 1, weight: 60, reps: 10);
      expect(set.rir, isNull);

      state.updateSet(set, rir: 0);
      expect(set.rir, 0);

      // rir: null은 "안 바꿈"이다. 지우려면 말해야 한다.
      state.updateSet(set, reps: 8);
      expect(set.rir, 0);

      state.updateSet(set, clearRir: true);
      expect(set.rir, isNull);
    });

    test('RIR은 뒤 세트로 전파되지 않는다 — 피로에 따라 달라지는 관찰값이다', () {
      final state = AppState();
      addTearDown(state.dispose);
      final template = exerciseCatalog.firstWhere(
        (item) => item.measurement == ExerciseMeasurement.weightReps,
      );
      final first = WorkoutSetEntry(
        number: 1,
        weight: 60,
        reps: 8,
        completed: true,
        rir: 3,
      );
      final second = WorkoutSetEntry(number: 2, weight: 60, reps: 10);
      final exercise = WorkoutExercise(
        id: 'rir_test',
        template: template,
        sets: [first, second],
      );

      expect(state.adoptActualIntoPendingSets(exercise, first), 1);
      expect(second.reps, 8, reason: '횟수는 계획이라 전파된다');
      expect(second.rir, isNull, reason: 'RIR은 지어내면 안 된다');
    });

    test('RIR은 스냅샷 왕복에서 살아남고, 미입력은 키가 없다', () {
      final template = exerciseCatalog.first;
      final snapshot = AppSnapshot(
        role: UserRole.guest,
        isDarkMode: false,
        weightUnit: 'kg',
        restDefaultSeconds: 90,
        routines: const [],
        sessions: {
          DateTime.utc(2026, 8, 26): WorkoutSession(
            date: DateTime.utc(2026, 8, 26),
            exercises: [
              WorkoutExercise(
                id: 'rir_round_trip',
                template: template,
                sets: [
                  WorkoutSetEntry(
                    number: 1,
                    weight: 60,
                    reps: 10,
                    completed: true,
                    rir: 2,
                  ),
                  WorkoutSetEntry(number: 2, weight: 60, reps: 10),
                ],
              ),
            ],
          ),
        },
      );

      final decoded = AppSnapshotCodec.fromJson(
        AppSnapshotCodec.toJson(snapshot),
        exerciseCatalog,
      );
      final sets = decoded!.sessions.values.first.exercises.first.sets;
      expect(sets.first.rir, 2);
      expect(sets.last.rir, isNull);
    });

    testWidgets('스위치가 실제로 세트 행의 RIR을 켠다', (tester) async {
      // 이 스위치는 오래도록 값만 저장하고 아무것도 켜지 않았다.
      final date = DateTime(2026, 11, 1);
      final state = AppState();
      await state.initialize();
      addTearDown(state.dispose);
      state.addExercise(date, state.exercises.first);

      await tester.binding.setSurfaceSize(const Size(432, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: MaterialApp(
            theme: SetflowTheme.light,
            home: DailyWorkoutScreen(date: date),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('inline-set-rir-1-3')),
        findsNothing,
        reason: '꺼져 있으면 행이 늘어날 이유가 없다',
      );

      state.setUseRir(true);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('inline-set-rir-1-3')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('inline-set-rir-1-3')));
      await tester.pumpAndSettle();
      final set = state.sessions[date]!.exercises.single.sets.first;
      expect(set.rir, 3);

      // 같은 칩을 다시 누르면 해제된다 — 잘못 누른 것을 되돌릴 길.
      await tester.tap(find.byKey(const ValueKey('inline-set-rir-1-3')));
      await tester.pumpAndSettle();
      expect(set.rir, isNull);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('회원 탈퇴', () {
    testWidgets('계정 비활성화는 사라지고 탈퇴 하나만 남는다', (tester) async {
      await pump(
        tester,
        const SettingDetailScreen(section: SettingSection.privacy),
      );
      // 30일 유예가 곧 비활성화였다 — 같은 것을 두 이름으로 부르지 않는다.
      expect(find.text('계정 비활성화'), findsNothing);
      expect(
        find.byKey(const ValueKey('setting-account-deletion')),
        findsOneWidget,
      );
    });

    testWidgets('서버 없는 게스트에게는 눌리지 않고 이유가 적힌다', (tester) async {
      final state = await pump(
        tester,
        const SettingDetailScreen(section: SettingSection.privacy),
      );
      expect(state.supportsAccountDeletion, isFalse);
      final tile = tester.widget<ListTile>(
        find.byKey(const ValueKey('setting-account-deletion')),
      );
      expect(tile.onTap, isNull);
      expect(find.text('로그인한 계정에서만 신청할 수 있어요.'), findsOneWidget);
    });

    test('남은 날짜는 올림한다 — 반나절 남았어도 0일이라고 하지 않는다', () {
      final request = AccountDeletionRequest(
        requestedAt: DateTime(2026, 8, 26),
        purgeAfter: DateTime(2026, 9, 25),
      );
      expect(request.daysLeft(DateTime(2026, 9, 24, 12)), 1);
      expect(request.daysLeft(DateTime(2026, 9, 25)), 0);
      expect(request.daysLeft(DateTime(2026, 9, 26)), 0);
    });
  });
}
