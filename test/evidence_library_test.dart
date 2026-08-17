import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/evidence_catalog.dart';
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

    await tester.tap(find.textContaining('Strength Testing—Predicting'));
    await tester.pumpAndSettle();

    expect(find.text('앱에서 참조한 규칙'), findsOneWidget);
    expect(find.text('근거의 한계'), findsOneWidget);
    expect(find.text('10.1080/07303084.1993.10606684'), findsOneWidget);

    final link = find.byKey(const ValueKey('evidence-link-brzycki-1993'));
    await tester.scrollUntilVisible(
      link,
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
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

    await tester.tap(find.textContaining('Strength Testing—Predicting'));
    await tester.pumpAndSettle();
    final link = find.byKey(const ValueKey('evidence-link-brzycki-1993'));
    await tester.scrollUntilVisible(
      link,
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(link);
    await tester.pumpAndSettle();

    expect(find.text('공식 논문 페이지를 열지 못했어요.'), findsOneWidget);
  });

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

Future<void> _pumpEvidence(WidgetTester tester, Widget screen) async {
  await tester.binding.setSurfaceSize(const Size(430, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(theme: SetflowTheme.light, home: screen));
  await tester.pumpAndSettle();
}
