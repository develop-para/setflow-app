import 'package:flutter_test/flutter_test.dart';

import '../tool/export_exercise_visual_catalog.dart';

void main() {
  test('production export never accepts unverified films as complete', () {
    final manifest = buildExerciseVisualManifest(
      canonicalRows: [
        {
          'exerciseId': 'bodyweight_squat',
          'name': '맨몸 스쿼트',
          'status': 'approved',
          'reviewStatus': 'approved',
          'motionKey': 'barbell_squat',
          'visualAssets': {'video': 'missing.mp4'},
          'metadata': {
            'catalogOrigins': ['curated'],
          },
        },
      ],
      personalRows: const [],
      catalogCounts: const {'canonicalExercises': 1},
      inputHashes: const {'source.dart': 'hash'},
      generatedAt: DateTime.utc(2026, 10, 5),
    );
    final row = (manifest['exercises'] as List).single as Map;
    expect(row['status'], 'queued');
    expect(row['reviewStatus'], 'not_started');
    expect(row['motionKey'], isNull);
    expect(row['visualAssets'], isNull);
    expect(manifest['counts'], containsPair('approved', 0));
  });

  test('personal export overrides the same ID without duplicating history', () {
    final manifest = buildExerciseVisualManifest(
      canonicalRows: [
        {'exerciseId': 'custom-id', 'name': '이전 이름'},
      ],
      personalRows: [
        {'exerciseId': 'custom-id', 'name': '내 운동'},
        {'exerciseId': 'custom-id-2', 'name': '내 다른 운동'},
      ],
      catalogCounts: const {'canonicalExercises': 1},
      inputHashes: const {},
    );
    final rows = manifest['exercises'] as List;
    expect(rows.length, 2);
    expect((rows.first as Map)['name'], '내 운동');
    expect((rows.first as Map)['phase'], containsPair('key', 'personal'));
    expect(manifest['counts'], containsPair('personalInputRows', 2));
    expect(manifest['counts'], containsPair('totalExercises', 2));
  });

  test(
    'duplicate personal identities fail instead of silently losing rows',
    () {
      expect(
        () => buildExerciseVisualManifest(
          canonicalRows: const [],
          personalRows: [
            {'exerciseId': 'custom-id', 'name': '첫 운동'},
            {'exerciseId': 'custom-id', 'name': '다른 운동'},
          ],
          catalogCounts: const {},
          inputHashes: const {},
        ),
        throwsFormatException,
      );
    },
  );

  test('manufacturer phase preserves identity without assigning motion', () {
    final manifest = buildExerciseVisualManifest(
      canonicalRows: [
        {
          'exerciseId': 'machine_technogym_mg7500',
          'name': '퓨어 리니어 레그 프레스',
          'model': 'MG7500',
          'metadata': {
            'catalogOrigins': ['manufacturer'],
          },
        },
      ],
      personalRows: const [],
      catalogCounts: const {},
      inputHashes: const {},
    );
    final row = (manifest['exercises'] as List).single as Map;
    expect(row['model'], 'MG7500');
    expect(row['phase'], containsPair('key', 'manufacturer'));
    expect(row['motionKey'], isNull);
    expect(
      manifest['provenance'],
      containsPair('phaseLabelsAreMotionMappings', false),
    );
  });
}
