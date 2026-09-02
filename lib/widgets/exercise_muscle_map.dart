import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_body_atlas/flutter_body_atlas.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models.dart';
import '../theme/icons.dart';
import '../theme/tokens.dart';

const _muscleLabelsKo = <String, String>{
  'abdominals': '복직근·외복사근',
  'abductors': '중둔근(고관절 외전근)',
  'adductors': '고관절 내전근군',
  'biceps': '상완이두근',
  'calves': '종아리·하퇴 근육군',
  'chest': '대흉근',
  'forearms': '전완근군',
  'glutes': '대둔근·중둔근',
  'hamstrings': '햄스트링',
  'lats': '광배근',
  'lower back': '척추기립근(허리)',
  'middle back': '등 중앙부(능형근 등)',
  'neck': '목 근육군',
  'quadriceps': '대퇴사두근',
  'shoulders': '삼각근',
  'traps': '승모근',
  'triceps': '상완삼두근',
};

const _sourceMusclesByCategory = <String, List<String>>{
  '가슴': <String>['chest'],
  '등': <String>['lats', 'middle back', 'lower back', 'traps'],
  '어깨': <String>['shoulders'],
  '하체': <String>[
    'quadriceps',
    'hamstrings',
    'glutes',
    'calves',
    'adductors',
    'abductors',
  ],
  '팔': <String>['biceps', 'triceps', 'forearms'],
  '복근': <String>['abdominals'],
  '유산소': <String>[],
};

/// The Korean display name for one of free-exercise-db's muscle keys.
///
/// All 17 source values are covered. Unknown English values are deliberately
/// described as an unspecified area instead of leaking source text into the
/// Korean UI.
String exerciseMuscleNameKo(String sourceKey) {
  final normalized = _normalizeMuscleKey(sourceKey);
  final known = _muscleLabelsKo[normalized];
  if (known != null) return known;
  if (RegExp(r'[가-힣]').hasMatch(sourceKey)) return sourceKey.trim();
  return '기타 부위';
}

/// A ready-to-display Korean primary-muscle label.
///
/// A key without an anatomical SVG path, such as `lower back`, still appears
/// here. Callers should show this text instead of coloring a nearby muscle.
String exercisePrimaryMusclesLabel(Iterable<String> sourceKeys) =>
    _roleLabel('주동근', sourceKeys);

/// A ready-to-display Korean secondary-muscle label.
String exerciseSecondaryMusclesLabel(Iterable<String> sourceKeys) =>
    _roleLabel('보조근', sourceKeys);

/// A Korean subtitle for an exercise's target muscles.
///
/// This applies the same upper-category fallback as [ExerciseMuscleMap] when
/// old or custom catalog entries do not carry detailed muscle keys.
String exerciseMuscleSummaryKo(ExerciseTemplate exercise) {
  final resolved = _resolvedMusclesForExercise(exercise);
  final roles = <String>[
    exercisePrimaryMusclesLabel(resolved.primary),
    exerciseSecondaryMusclesLabel(resolved.secondary),
  ].where((label) => label.isNotEmpty).join(' · ');
  if (exercise.isCardio) {
    return roles.isEmpty ? '유산소 운동' : '유산소 · $roles';
  }
  if (roles.isNotEmpty) return roles;

  final category = exercise.muscle.trim();
  if (category.isEmpty || category == '기타') return '근육 정보 없음';
  return '운동 부위: $category';
}

String _roleLabel(String role, Iterable<String> sourceKeys) {
  final labels = <String>{};
  for (final sourceKey in sourceKeys) {
    if (sourceKey.trim().isEmpty) continue;
    labels.add(exerciseMuscleNameKo(sourceKey));
  }
  return labels.isEmpty ? '' : '$role: ${labels.join(' · ')}';
}

String _normalizeMuscleKey(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll('_', ' ')
    .replaceAll(RegExp(r'\s+'), ' ');

Set<String> _catalogPaths(
  Iterable<MuscleInfo> catalog, {
  bool Function(String id)? where,
}) {
  final result = <String>{};
  for (final info in catalog) {
    if (where != null && !where(info.id)) continue;
    result.addAll(info.muscle.parts);
  }
  return Set<String>.unmodifiable(result);
}

bool _isForearm(String id) =>
    id.startsWith('extensor_') ||
    id.startsWith('flexor_') ||
    id.startsWith('pronator_') ||
    id.startsWith('palmaris_') ||
    id.startsWith('brachioradialis_');

bool _isQuadriceps(String id) =>
    id.startsWith('vastus_') || id.startsWith('rectus_femoris_');

bool _isLowerLeg(String id) =>
    id.startsWith('gastrocnemius_') ||
    id.startsWith('tibialis_anterior_') ||
    id.startsWith('extensor_hallucis_') ||
    id.startsWith('fibularis_') ||
    id.startsWith('extensor_digitorum_');

/// A conservative bridge from the source taxonomy to paths that actually
/// exist in Ryan Graves' atlas. This stays private so package anatomy types and
/// SVG ids do not escape the presentation adapter.
final Map<String, Set<String>> _atlasPathsBySourceMuscle =
    Map<String, Set<String>>.unmodifiable(<String, Set<String>>{
      'abdominals': _catalogPaths(MuscleCatalog.core),
      'abductors': _catalogPaths(
        MuscleCatalog.glutes,
        where: (id) => id.startsWith('gluteus_medius_'),
      ),
      'adductors': _catalogPaths(MuscleCatalog.adductors),
      'biceps': _catalogPaths(
        MuscleCatalog.arms,
        where: (id) => id.startsWith('biceps_brachii_'),
      ),
      // free-exercise-db's `calves` also contains anterior-tibialis and
      // peroneal work, so highlight the atlas's whole lower-leg group rather
      // than falsely claiming every row is gastrocnemius-only.
      'calves': _catalogPaths(MuscleCatalog.legs, where: _isLowerLeg),
      'chest': _catalogPaths(MuscleCatalog.chest),
      'forearms': _catalogPaths(MuscleCatalog.arms, where: _isForearm),
      'glutes': _catalogPaths(MuscleCatalog.glutes),
      'hamstrings': _catalogPaths(MuscleCatalog.hamstrings),
      'lats': _catalogPaths(
        MuscleCatalog.back,
        where: (id) => id.startsWith('latissimus_dorsi_'),
      ),
      // The atlas has no erector-spinae or other faithful lower-back path.
      'lower back': const <String>{},
      // The atlas has no rhomboid paths. Coloring the middle/lower trapezius
      // would turn a source secondary muscle into a primary one.
      'middle back': const <String>{},
      // The source groups front, side, and rear neck exercises together, so a
      // single front-neck path would be a false anatomical claim.
      'neck': const <String>{},
      'quadriceps': _catalogPaths(MuscleCatalog.legs, where: _isQuadriceps),
      'shoulders': _catalogPaths(
        MuscleCatalog.shoulders,
        where: (id) => id.contains('deltoid'),
      ),
      'traps': _catalogPaths(
        MuscleCatalog.shoulders,
        where: (id) => id.startsWith('trapezius_'),
      ),
      'triceps': _catalogPaths(
        MuscleCatalog.arms,
        where: (id) => id.startsWith('triceps_brachii_'),
      ),
    });

/// A non-interactive, reusable front/back muscle illustration.
///
/// Unlike [BodyAtlasView], this widget does not load an SVG hit-test index for
/// every instance. [SvgPicture.asset] and an immutable, value-equal color
/// mapper allow flutter_svg's decoded-picture cache to be shared by identical
/// primary-muscle combinations. Secondary muscles stay in the adjacent Korean
/// label, and compact list rows render the most useful single body direction.
class ExerciseMuscleMap extends StatelessWidget {
  factory ExerciseMuscleMap.forExercise({
    Key? key,
    required ExerciseTemplate exercise,
    double size = defaultSize,
    bool decorative = false,
  }) {
    final resolved = _resolvedMusclesForExercise(exercise);
    final showCardioPlaceholder = exercise.isCardio && resolved.primary.isEmpty;

    return ExerciseMuscleMap._(
      key: key,
      subject: '${exercise.name} 근육 지도',
      category: exercise.muscle,
      primaryMuscles: resolved.primary,
      secondaryMuscles: resolved.secondary,
      placeholderIcon: showCardioPlaceholder ? SetflowIcons.cardio : null,
      placeholderSemantics: showCardioPlaceholder
          ? '${exercise.name} 근육 지도. 특정 근육 강조 없음.'
          : null,
      compactAsset: size < defaultSize
          ? _preferredAtlasAsset(resolved.primary)
          : null,
      decorative: decorative,
      size: size,
    );
  }

  factory ExerciseMuscleMap.forCategory({
    Key? key,
    required String category,
    double size = defaultSize,
    bool decorative = false,
  }) {
    final normalizedCategory = category.trim();
    final showAllPlaceholder = normalizedCategory == '전체';
    final showCardioPlaceholder = _isCardioCategory(normalizedCategory);
    final primaryMuscles = showCardioPlaceholder || showAllPlaceholder
        ? const <String>[]
        : _categoryMuscles(normalizedCategory);
    final keepBothCompactViews =
        normalizedCategory == '하체' || normalizedCategory == '팔';
    return ExerciseMuscleMap._(
      key: key,
      subject: showAllPlaceholder ? '전체 운동' : '$category 운동 부위',
      category: normalizedCategory,
      primaryMuscles: primaryMuscles,
      secondaryMuscles: const <String>[],
      placeholderIcon: showAllPlaceholder
          ? SetflowIcons.appMenu
          : showCardioPlaceholder
          ? SetflowIcons.cardio
          : null,
      placeholderSemantics: showAllPlaceholder
          ? '전체 운동'
          : showCardioPlaceholder
          ? '$category 운동 부위. 특정 근육 강조 없음.'
          : null,
      compactAsset: size < defaultSize && !keepBothCompactViews
          ? _preferredAtlasAsset(primaryMuscles)
          : null,
      decorative: decorative,
      size: size,
    );
  }

  const ExerciseMuscleMap._({
    super.key,
    required this.subject,
    required this.category,
    required this.primaryMuscles,
    required this.secondaryMuscles,
    required this.placeholderIcon,
    required this.placeholderSemantics,
    required this.compactAsset,
    required this.decorative,
    required this.size,
  }) : assert(size > 0);

  static const defaultSize = 72.0;

  final String subject;
  final String category;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;
  final IconData? placeholderIcon;
  final String? placeholderSemantics;
  final AtlasAsset? compactAsset;
  final bool decorative;
  final double size;

  String get primaryLabel => exercisePrimaryMusclesLabel(primaryMuscles);
  String get secondaryLabel => exerciseSecondaryMusclesLabel(secondaryMuscles);

  String get semanticsLabel {
    final placeholderLabel = placeholderSemantics;
    if (placeholderLabel != null) return placeholderLabel;
    final roles = <String>[
      primaryLabel,
      secondaryLabel,
    ].where((label) => label.isNotEmpty).join('. ');
    return roles.isEmpty ? '$subject. 근육 정보 없음.' : '$subject. $roles.';
  }

  bool get hasMappedPrimaryMuscles => _pathIdsFor(primaryMuscles).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final icon = placeholderIcon;
    final visual = icon != null
        ? Center(
            child: Icon(
              icon,
              size: size * 0.48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        : _StaticAtlas(
            primaryMuscles: primaryMuscles,
            color: _fillFor(category, primaryMuscles),
            compactAsset: compactAsset,
          );
    final sized = SizedBox.square(dimension: size, child: visual);

    if (decorative) return ExcludeSemantics(child: sized);

    return Semantics(
      container: true,
      image: true,
      label: semanticsLabel,
      child: ExcludeSemantics(child: sized),
    );
  }
}

({List<String> primary, List<String> secondary}) _resolvedMusclesForExercise(
  ExerciseTemplate exercise,
) {
  final explicitPrimary = _normalizedMuscles(exercise.primaryMuscles);
  final primary = explicitPrimary.isNotEmpty
      ? explicitPrimary
      : exercise.isCardio
      ? const <String>[]
      : _categoryMuscles(exercise.muscle);
  return (
    primary: primary,
    secondary: _normalizedMuscles(
      exercise.secondaryMuscles,
      excluding: primary,
    ),
  );
}

List<String> _normalizedMuscles(
  Iterable<String> values, {
  Iterable<String> excluding = const <String>[],
}) {
  final excluded = excluding.map(_normalizeMuscleKey).toSet();
  final result = <String>[];
  final seen = <String>{};
  for (final value in values) {
    final normalized = _normalizeMuscleKey(value);
    if (normalized.isEmpty ||
        excluded.contains(normalized) ||
        !seen.add(normalized)) {
      continue;
    }
    result.add(normalized);
  }
  return List<String>.unmodifiable(result);
}

List<String> _categoryMuscles(String category) =>
    _sourceMusclesByCategory[category.trim()] ?? const <String>[];

bool _isCardioCategory(String category) {
  final normalized = category.trim().toLowerCase();
  return normalized == '유산소' || normalized == 'cardio';
}

Set<String> _pathIdsFor(Iterable<String> sourceMuscles) {
  final result = <String>{};
  for (final sourceMuscle in sourceMuscles) {
    result.addAll(
      _atlasPathsBySourceMuscle[_normalizeMuscleKey(sourceMuscle)] ??
          const <String>{},
    );
  }
  return result;
}

AtlasAsset? _preferredAtlasAsset(Iterable<String> sourceMuscles) {
  final normalized = sourceMuscles.map(_normalizeMuscleKey).toSet();
  // The source's broad calves key spans the front and back of the lower leg.
  if (normalized.contains('calves')) return null;
  const backFocused = <String>{
    'abductors',
    'calves',
    'glutes',
    'hamstrings',
    'lats',
    'lower back',
    'middle back',
    'traps',
    'triceps',
  };
  var frontScore = 0;
  var backScore = 0;
  for (final sourceMuscle in normalized) {
    if (backFocused.contains(sourceMuscle)) {
      backScore++;
    } else {
      frontScore++;
    }
  }
  return backScore > frontScore
      ? AtlasAsset.musclesBack
      : AtlasAsset.musclesFront;
}

Color _fillFor(String category, Iterable<String> sourceMuscles) {
  final categoryFill = switch (category.trim()) {
    '가슴' => SetflowMuscleFill.chest,
    '등' => SetflowMuscleFill.back,
    '어깨' => SetflowMuscleFill.shoulders,
    '하체' => SetflowMuscleFill.legs,
    '팔' => SetflowMuscleFill.arms,
    '복근' => SetflowMuscleFill.core,
    '유산소' => SetflowMuscleFill.cardio,
    _ => null,
  };
  if (categoryFill != null) return categoryFill;

  for (final sourceMuscle in sourceMuscles) {
    return switch (_normalizeMuscleKey(sourceMuscle)) {
      'chest' => SetflowMuscleFill.chest,
      'lats' || 'lower back' || 'middle back' => SetflowMuscleFill.back,
      'neck' || 'shoulders' || 'traps' => SetflowMuscleFill.shoulders,
      'abductors' ||
      'adductors' ||
      'calves' ||
      'glutes' ||
      'hamstrings' ||
      'quadriceps' => SetflowMuscleFill.legs,
      'biceps' || 'forearms' || 'triceps' => SetflowMuscleFill.arms,
      'abdominals' => SetflowMuscleFill.core,
      _ => SetflowMuscleFill.core,
    };
  }
  return SetflowMuscleFill.core;
}

class _StaticAtlas extends StatelessWidget {
  const _StaticAtlas({
    required this.primaryMuscles,
    required this.color,
    required this.compactAsset,
  });

  final List<String> primaryMuscles;
  final Color color;
  final AtlasAsset? compactAsset;

  @override
  Widget build(BuildContext context) {
    final colorsByPath = <String, Color>{};
    for (final path in _pathIdsFor(primaryMuscles)) {
      colorsByPath[path] = color;
    }
    final mapper = _ExerciseMuscleColorMapper(colorsByPath);
    final singleAsset = compactAsset;

    return RepaintBoundary(
      child: singleAsset != null
          ? _atlasView(singleAsset, mapper)
          : Row(
              children: <Widget>[
                Expanded(child: _atlasView(AtlasAsset.musclesFront, mapper)),
                const SizedBox(width: SetflowSpacing.xxs),
                Expanded(child: _atlasView(AtlasAsset.musclesBack, mapper)),
              ],
            ),
    );
  }

  Widget _atlasView(AtlasAsset asset, _ExerciseMuscleColorMapper mapper) =>
      SvgPicture.asset(
        asset.path,
        package: AtlasAsset.package,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        colorMapper: mapper,
        excludeFromSemantics: true,
      );
}

@immutable
class _ExerciseMuscleColorMapper extends ColorMapper {
  _ExerciseMuscleColorMapper(Map<String, Color> colorsByPath)
    : colorsByPath = Map<String, Color>.unmodifiable(colorsByPath);

  final Map<String, Color> colorsByPath;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    if (id == null || attributeName != 'fill') return color;
    return colorsByPath[id] ?? color;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ExerciseMuscleColorMapper &&
          mapEquals(colorsByPath, other.colorsByPath);

  @override
  int get hashCode => Object.hashAllUnordered(
    colorsByPath.entries.map((entry) => Object.hash(entry.key, entry.value)),
  );
}
