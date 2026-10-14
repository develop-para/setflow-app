import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/evidence_catalog.dart';
import 'package:setflow/domain/workout_design_rule.dart';
import 'package:setflow/screens/business_settings_screens.dart';
import 'package:setflow/screens/evidence_library_screen.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/theme.dart';

void main() {
  test('evidence catalog keeps complete, unique, official references', () {
    const requiredSourceIds = {
      'acsm_currier_2026_resistance',
      'acsm_garber_2011_prescription',
      'who_bull_2020_pa_guideline',
      'acsm_jakicic_2024_adiposity',
      'schoenfeld_2017_weekly_volume',
      'refalo_2023_proximity_failure',
      'nunes_2021_exercise_order',
      'lesuer_1997_e1rm',
      'reynolds_2006_rm_prediction',
      'schumann_2022_concurrent',
      'helgerud_2007_4x4',
      'pelland_2026_dose_response',
      'ramos_2024_split_full_body',
      'singer_2024_rest_hypertrophy',
      'robinson_2024_proximity_failure',
      'halperin_2022_rir_accuracy',
      'hickmott_2022_autoregulation',
      'cox_2026_mhealth_resistance',
    };
    expect(
      evidenceCatalog.map((reference) => reference.id).toSet(),
      containsAll(requiredSourceIds),
    );
    expect(
      evidenceCatalog.map((reference) => reference.id).toSet(),
      hasLength(evidenceCatalog.length),
    );
    expect(evidenceCatalogById, hasLength(evidenceCatalog.length));
    for (final reference in evidenceCatalog) {
      expect(reference.title, isNotEmpty);
      expect(reference.koreanTitle, isNotEmpty);
      expect(reference.takeaway, isNotEmpty);
      expect(DateTime.tryParse(reference.reviewedOn), isNotNull);
      expect(reference.reviewScope, isNotEmpty);
      expect(reference.authors, isNotEmpty);
      expect(reference.authors, isNot(contains(' 외')));
      expect(reference.source, isNotEmpty);
      expect(reference.evidenceType, isNotEmpty);
      expect(reference.doi, isNotEmpty);
      expect(reference.officialUrl.scheme, 'https');
      expect(reference.appRules, isNotEmpty);
      expect(reference.limitations, isNotEmpty);
    }

    final acsm2026 = evidenceCatalog.singleWhere(
      (reference) => reference.id == 'acsm_currier_2026_resistance',
    );
    expect(acsm2026.year, 2026);
    expect(acsm2026.doi, '10.1249/MSS.0000000000003897');
    expect(acsm2026.officialUrl.host, 'pubmed.ncbi.nlm.nih.gov');

    final reynolds = evidenceCatalog.singleWhere(
      (reference) => reference.id == 'reynolds_2006_rm_prediction',
    );
    expect(reynolds.limitations, contains('70명'));
    expect(reynolds.limitations, contains('남성 34명·여성 36명'));

    final brzycki = evidenceCatalog.singleWhere(
      (reference) => reference.id == 'brzycki-1993',
    );
    expect(brzycki.limitations, contains('직접 검증 근거는 없으며'));
  });

  testWidgets('evidence screen explains rules and opens the official link', (
    tester,
  ) async {
    Uri? openedUri;
    await _pumpEvidence(
      tester,
      EvidenceLibraryScreen(
        linkLauncher: (uri) async {
          openedUri = uri;
          return true;
        },
      ),
    );

    expect(find.text('관련 논문'), findsOneWidget);
    expect(find.text('Setflow의 추천 근거'), findsOneWidget);
    expect(find.text('근력 추정'), findsOneWidget);

    await _tapVisible(
      tester,
      find.text(evidenceCatalogById['brzycki-1993']!.koreanTitle),
    );

    expect(find.text('앱에서 참조한 규칙'), findsOneWidget);
    expect(find.text('공식 논문 제목'), findsOneWidget);
    expect(
      find.text(evidenceCatalogById['brzycki-1993']!.title),
      findsOneWidget,
    );
    expect(find.text('검토일 · 확인 범위'), findsOneWidget);
    expect(find.text('근거의 한계'), findsOneWidget);
    expect(find.text('10.1080/07303084.1993.10606684'), findsOneWidget);

    final link = find.byKey(const ValueKey('evidence-link-brzycki-1993'));
    await tester.scrollUntilVisible(link, 220, scrollable: _paperScrollable);
    await tester.pumpAndSettle();
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();

    expect(
      openedUri,
      Uri.parse('https://doi.org/10.1080/07303084.1993.10606684'),
    );
  });

  testWidgets('evidence screen reports an external link failure', (
    tester,
  ) async {
    await _pumpEvidence(
      tester,
      EvidenceLibraryScreen(linkLauncher: (_) async => false),
    );

    await _tapVisible(
      tester,
      find.text(evidenceCatalogById['brzycki-1993']!.koreanTitle),
    );
    final link = find.byKey(const ValueKey('evidence-link-brzycki-1993'));
    await tester.scrollUntilVisible(link, 220, scrollable: _paperScrollable);
    await tester.pumpAndSettle();
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();

    expect(find.text('공식 논문 페이지를 열지 못했어요.'), findsOneWidget);
  });

  testWidgets(
    'recommendation sources show only the papers used in that recommendation',
    (tester) async {
      await _pumpEvidence(
        tester,
        const EvidenceLibraryScreen(
          referenceIds: {
            'pelland_2026_dose_response',
            'ramos_2024_split_full_body',
          },
        ),
      );
      expect(find.text('근력 추정'), findsNothing);
      expect(
        find.text(
          evidenceCatalogById['pelland_2026_dose_response']!.koreanTitle,
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          evidenceCatalogById['ramos_2024_split_full_body']!.koreanTitle,
        ),
        findsOneWidget,
      );
      expect(
        find.text(evidenceCatalogById['brzycki-1993']!.koreanTitle),
        findsNothing,
      );

      await _tapVisible(tester, find.text('운동 기록·추천의 설계 이유'));
      const expectedRules = {
        WorkoutDesignRule.volumePlan,
        WorkoutDesignRule.volumeAccounting,
        WorkoutDesignRule.personalCoaching,
        WorkoutDesignRule.exerciseSelection,
      };
      for (final rule in WorkoutDesignRule.values) {
        expect(
          find.byKey(ValueKey('workout-rule-${rule.name}')),
          expectedRules.contains(rule) ? findsOneWidget : findsNothing,
          reason: '${rule.name}은 이 추천의 논문과 연결된 경우에만 표시합니다.',
        );
      }
    },
  );

  testWidgets('volume design explains why eight sets are a starting plan', (
    tester,
  ) async {
    await _pumpEvidence(tester, const EvidenceLibraryScreen());
    expect(find.byKey(const ValueKey('workout-design-rules')), findsOneWidget);
    expect(find.text(WorkoutDesignRule.volumePlan.limitations), findsNothing);

    await _tapVisible(tester, find.text('운동 기록·추천의 설계 이유'));
    await _tapVisible(tester, find.text(WorkoutDesignRule.volumePlan.title));

    expect(find.textContaining('부위별 하루 4/6/8세트'), findsOneWidget);
    expect(
      find.textContaining('4·6·8이라는 간격 자체는 연구가 정한 수치가 아닙니다'),
      findsOneWidget,
    );
    expect(find.textContaining('개인별 최적량·안전 상한·운동 종료 지시가 아닙니다'), findsOneWidget);
    expect(
      find.textContaining('8세트를 넘으면 효과가 없거나 위험하다는 뜻이 아닙니다'),
      findsOneWidget,
    );
    expect(find.text('연구에서 참고한 원칙'), findsOneWidget);
    expect(find.text('이렇게 정한 이유'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'design reasons and official links work at 320px and double text in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        Uri? openedUri;
        await _pumpEvidence(
          tester,
          EvidenceLibraryScreen(
            referenceIds: const {'pelland_2026_dose_response', 'brzycki-1993'},
            linkLauncher: (uri) async {
              openedUri = uri;
              return true;
            },
          ),
          small: true,
          dark: dark,
        );

        await _tapVisible(tester, find.text('운동 기록·추천의 설계 이유'));
        await _tapVisible(
          tester,
          find.text(WorkoutDesignRule.volumePlan.title),
        );
        final explanation = find.text(WorkoutDesignRule.volumePlan.limitations);
        await tester.ensureVisible(explanation);
        await tester.pumpAndSettle();
        expect(explanation.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);

        await _tapVisible(tester, find.text('운동 기록·추천의 설계 이유'));
        await _tapVisible(
          tester,
          find.text(evidenceCatalogById['brzycki-1993']!.koreanTitle),
        );
        final link = find.byKey(const ValueKey('evidence-link-brzycki-1993'));
        await _tapVisible(tester, link);

        expect(
          openedUri,
          Uri.parse('https://doi.org/10.1080/07303084.1993.10606684'),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('member settings opens the related papers screen', (
    tester,
  ) async {
    final state = AppState();
    addTearDown(state.dispose);
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: const SettingsScreen(),
        ),
      ),
    );

    final entry = find.byKey(const ValueKey('settings-evidence-library'));
    await tester.scrollUntilVisible(
      entry,
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byType(EvidenceLibraryScreen), findsOneWidget);
    expect(find.text('Setflow의 추천 근거'), findsOneWidget);
  });

  testWidgets(
    'paper search keeps the recommendation source scope and can be reset',
    (tester) async {
      await _pumpEvidence(
        tester,
        const EvidenceLibraryScreen(
          referenceIds: {
            'pelland_2026_dose_response',
            'ramos_2024_split_full_body',
          },
        ),
      );
      final search = find.descendant(
        of: find.byKey(const ValueKey('evidence-search')),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(search, ' PELLAND ');
      await tester.pumpAndSettle();
      expect(find.text('1건의 논문'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('evidence-pelland_2026_dose_response')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('evidence-ramos_2024_split_full_body')),
        findsNothing,
      );
      await tester.enterText(search, '10.1007/s40279-025-02344-w');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('evidence-pelland_2026_dose_response')),
        findsOneWidget,
      );
      await tester.enterText(search, '휴식');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('evidence-search-empty')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('evidence-singer_2024_rest_hypertrophy')),
        findsNothing,
      );
      await _tapVisible(tester, find.byTooltip('검색 지우기'));
      expect(
        find.byKey(const ValueKey('workout-design-rules')),
        findsOneWidget,
      );
      expect(tester.widget<TextFormField>(search).controller!.text, isEmpty);
    },
  );

  testWidgets(
    'Korean topics find new research and retain its official title and review scope',
    (tester) async {
      Uri? opened;
      await _pumpEvidence(
        tester,
        EvidenceLibraryScreen(
          linkLauncher: (uri) async {
            opened = uri;
            return true;
          },
        ),
      );
      final search = find.descendant(
        of: find.byKey(const ValueKey('evidence-search')),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(search, '휴식');
      await tester.pumpAndSettle();
      final paper = evidenceCatalogById['singer_2024_rest_hypertrophy']!;
      await _tapVisible(tester, find.text(paper.koreanTitle));
      expect(find.text(paper.title), findsOneWidget);
      expect(
        find.text('${paper.reviewedOn} · ${paper.reviewScope}'),
        findsOneWidget,
      );
      await _tapVisible(
        tester,
        find.byKey(ValueKey('evidence-link-${paper.id}')),
      );
      expect(opened, paper.officialUrl);
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'search and recovery stay usable with a keyboard and doubled text ($dark)',
      (tester) async {
        await _pumpEvidence(
          tester,
          const EvidenceLibraryScreen(),
          small: true,
          dark: dark,
          keyboardInset: 280,
        );
        final search = find.descendant(
          of: find.byKey(const ValueKey('evidence-search')),
          matching: find.byType(TextFormField),
        );
        await tester.enterText(search, '없는자료987');
        await tester.pumpAndSettle();
        await _tapVisible(tester, find.text('검색 초기화'));
        expect(search.hitTestable(), findsOneWidget);
        expect(tester.widget<TextFormField>(search).controller!.text, isEmpty);
        await tester.enterText(search, 'RIR');
        await tester.pumpAndSettle();
        final paper = evidenceCatalogById['halperin_2022_rir_accuracy']!;
        await _tapVisible(tester, find.text(paper.koreanTitle));
        expect(find.text(paper.limitations), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('trainer settings opens the same evidence catalog', (
    tester,
  ) async {
    final state = AppState();
    addTearDown(state.dispose);
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: const BusinessSettingsListScreen(role: UserRole.trainer),
        ),
      ),
    );

    final entry = find.byKey(
      const ValueKey('business-settings-evidence-library'),
    );
    await tester.scrollUntilVisible(
      entry,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byType(EvidenceLibraryScreen), findsOneWidget);
    expect(find.text('Setflow의 추천 근거'), findsOneWidget);
  });
}

Future<void> _pumpEvidence(
  WidgetTester tester,
  Widget screen, {
  bool small = false,
  bool dark = false,
  double keyboardInset = 0,
}) async {
  await tester.binding.setSurfaceSize(
    small ? const Size(320, 700) : const Size(430, 900),
  );
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? SetflowTheme.dark : SetflowTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(small ? 2 : 1),
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
          padding: small
              ? const EdgeInsets.only(top: 24, bottom: 28)
              : EdgeInsets.zero,
        ),
        child: child!,
      ),
      home: screen,
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _paperScrollable => find
    .descendant(
      of: find.byKey(const ValueKey('evidence-library-list')),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _tapVisible(WidgetTester tester, Finder target) async {
  if (!tester.any(target)) {
    await tester.scrollUntilVisible(target, 220, scrollable: _paperScrollable);
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
}
