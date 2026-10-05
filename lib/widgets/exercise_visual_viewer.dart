import 'dart:async';

import 'package:flutter/material.dart';

import '../data/exercise_visuals.dart';
import '../theme/icons.dart';
import '../theme/tokens.dart';

/// 로컬 GIF를 첫 프레임으로 열고, 사용자가 요청한 동안만 재생한다.
/// Flutter Image가 TickerMode를 통해 현재 프레임과 디코더를 유지하면서
/// 멀티프레임 재생을 멈추므로 별도 타이머나 전체 프레임 캐시가 필요 없다.
class ExerciseVisualViewer extends StatefulWidget {
  const ExerciseVisualViewer({
    required this.exerciseName,
    required this.visual,
    super.key,
  });

  final String exerciseName;
  final ExerciseVisual visual;

  @override
  State<ExerciseVisualViewer> createState() => _ExerciseVisualViewerState();
}

class _ExerciseVisualViewerState extends State<ExerciseVisualViewer>
    with WidgetsBindingObserver {
  final Object _imageSession = Object();
  final Set<ImageConfiguration> _imageConfigurations = {};
  late ImageProvider<Object> _imageProvider;
  bool _playRequested = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _imageProvider = _createImageProvider();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _imageConfigurations.add(createLocalImageConfiguration(context));
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion && !_reduceMotion) _playRequested = false;
    _reduceMotion = reduceMotion;
  }

  @override
  void didUpdateWidget(ExerciseVisualViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visual.assetPath != widget.visual.assetPath) {
      _evictImage(_imageProvider);
      _imageProvider = _createImageProvider();
    }
    if (oldWidget.visual.assetPath != widget.visual.assetPath ||
        widget.visual.isStaticPose) {
      _playRequested = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _playRequested) {
      setState(() => _playRequested = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _evictImage(_imageProvider);
    super.dispose();
  }

  ImageProvider<Object> _createImageProvider() => ResizeImage.resizeIfNeeded(
    384,
    null,
    _SessionAssetImage(widget.visual.assetPath, session: _imageSession),
  );

  void _evictImage(ImageProvider<Object> provider) {
    for (final configuration in _imageConfigurations) {
      unawaited(provider.evict(configuration: configuration));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parentTickerEnabled = TickerMode.valuesOf(context).enabled;
    final media = MediaQuery.of(context);
    final playing = _playRequested && !widget.visual.isStaticPose;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('동작 예시 (데모)', style: theme.textTheme.titleMedium),
        if (widget.visual.variantDescription case final variant?) ...[
          const SizedBox(height: SetflowSpacing.xxs),
          Text(variant, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: SetflowSpacing.sm),
        // 애니메이션 줄이기를 켜도 첫 프레임은 보인다. 명시적으로 재생을
        // 누른 경우에만 이 이미지의 재생을 허용하고, 바깥 TickerMode는 따른다.
        MediaQuery(
          data: media.copyWith(
            disableAnimations: playing ? false : media.disableAnimations,
          ),
          child: TickerMode(
            enabled: parentTickerEnabled && playing,
            child: Image(
              image: _imageProvider,
              key: ValueKey(widget.visual.assetPath),
              fit: BoxFit.contain,
              gaplessPlayback: true,
              semanticLabel:
                  '${widget.exerciseName} 동작 예시. 강조 부위: ${widget.visual.highlightedMuscles}.',
              frameBuilder: (context, image, frame, synchronous) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(SetflowRadii.md),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: frame == null
                          ? const Center(child: Text('동작 예시 불러오는 중'))
                          : image,
                    ),
                  ),
                  const SizedBox(height: SetflowSpacing.xs),
                  if (widget.visual.isStaticPose)
                    Text('자세를 유지하는 동작이에요.', style: theme.textTheme.bodySmall)
                  else
                    TextButton.icon(
                      onPressed: frame == null
                          ? null
                          : () => setState(
                              () => _playRequested = !_playRequested,
                            ),
                      icon: Icon(
                        _playRequested
                            ? SetflowIcons.pauseMotion
                            : SetflowIcons.playMotion,
                      ),
                      label: Text(_playRequested ? '동작 일시정지' : '동작 재생'),
                    ),
                ],
              ),
              errorBuilder: (context, error, stackTrace) => const Padding(
                padding: EdgeInsets.symmetric(vertical: SetflowSpacing.lg),
                child: Text('동작 예시를 불러오지 못했어요.'),
              ),
            ),
          ),
        ),
        const SizedBox(height: SetflowSpacing.xs),
        if (widget.visual.demonstratedSide case final side?) ...[
          Text(
            '영상은 $side 동작을 보여줘요. 반대쪽도 같은 방법으로 반복하세요.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: SetflowSpacing.xxs),
        ],
        Text(
          '붉은색 강조: ${widget.visual.highlightedMuscles}',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: SetflowSpacing.xxs),
        Text(
          '붉은색은 운동 부위를 안내하며, 실제 근육 활성도를 측정한 값은 아니에요.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 같은 화면의 재생/일시정지는 디코더를 유지하고, 새 화면은 첫 프레임으로
/// 시작한다. 공유 AssetImage 캐시는 건드리지 않고 이 세션의 키만 사용한다.
class _SessionAssetImage extends AssetImage {
  const _SessionAssetImage(super.assetName, {required this.session});

  final Object session;

  @override
  Future<AssetBundleImageKey> obtainKey(ImageConfiguration configuration) =>
      super
          .obtainKey(configuration)
          .then(
            (key) => _SessionAssetKey(
              bundle: key.bundle,
              name: key.name,
              scale: key.scale,
              session: session,
            ),
          );

  @override
  bool operator ==(Object other) =>
      other is _SessionAssetImage &&
      super == other &&
      identical(session, other.session);

  @override
  int get hashCode => Object.hash(super.hashCode, session);
}

class _SessionAssetKey extends AssetBundleImageKey {
  const _SessionAssetKey({
    required super.bundle,
    required super.name,
    required super.scale,
    required this.session,
  });

  final Object session;

  @override
  bool operator ==(Object other) =>
      other is _SessionAssetKey &&
      super == other &&
      identical(session, other.session);

  @override
  int get hashCode => Object.hash(super.hashCode, session);
}
