import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

/// 화면 안내의 한 걸음. [target]이 가리키는 위젯만 밝게 남기고 나머지를 어둡게
/// 덮은 뒤, 그 옆에 말풍선으로 [title]·[body]를 보여준다.
class CoachStep {
  const CoachStep({
    required this.target,
    required this.title,
    required this.body,
  });

  final GlobalKey target;
  final String title;
  final String body;
}

/// 게임의 첫 판처럼 — 딤 위에 스포트라이트 하나, 말풍선 하나, "다음".
///
/// 텍스트 시트로 된 사용법은 읽고 나면 화면과 연결이 안 된다. 실기기 피드백은
/// "버튼마다 딤되면서 설명이 있어야 할 것 같다"였고, 그것이 이 위젯이다.
/// 대상이 아직 화면에 없으면(예: 친구가 없어 전광판이 없음) 그 걸음은 건너뛴다.
///
/// 루트 [Overlay]에 올라가므로 앱바의 버튼도 비출 수 있다. 끝나면 [Future]가
/// 완료된다 — 다 봤든 건너뛰었든.
Future<void> showCoachMarks(
  BuildContext context, {
  required List<CoachStep> steps,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final done = Completer<void>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => CoachMarks(
      steps: steps,
      onFinished: () {
        entry.remove();
        if (!done.isCompleted) done.complete();
      },
    ),
  );
  overlay.insert(entry);
  return done.future;
}

class CoachMarks extends StatefulWidget {
  const CoachMarks({required this.steps, required this.onFinished, super.key});

  final List<CoachStep> steps;
  final VoidCallback onFinished;

  @override
  State<CoachMarks> createState() => _CoachMarksState();
}

class _CoachMarksState extends State<CoachMarks>
    with SingleTickerProviderStateMixin {
  int _index = 0;

  /// 등장 페이드 한 번뿐. 반복 애니메이션은 두지 않는다 — pumpAndSettle이
  /// 영원히 돈다.
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: SetflowMotion.standard,
  )..forward();

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  /// 대상의 사각형을 **이 오버레이의 좌표**로. 전역 좌표와 MediaQuery 크기를
  /// 믿었더니 캡처 하네스에서 말풍선이 화면 밖으로 나갔다 — 오버레이 박스가
  /// 기준이고, 크기는 LayoutBuilder가 준다.
  Rect? _rectOf(CoachStep step, RenderBox? overlay) {
    final box = step.target.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    return origin & box.size;
  }

  RenderBox? get _overlayBox {
    final object = context.findRenderObject();
    return object is RenderBox && object.hasSize ? object : null;
  }

  void _advance() {
    final overlay = _overlayBox;
    var next = _index + 1;
    while (next < widget.steps.length &&
        _rectOf(widget.steps[next], overlay) == null) {
      next++;
    }
    if (next >= widget.steps.length) {
      widget.onFinished();
      return;
    }
    setState(() => _index = next);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final overlay = _overlayBox;
        // 첫 걸음의 대상이 없으면 앞으로 민다. build 안에서 setState는 못 하므로
        // 그리는 데 쓰는 값만 옮긴다.
        var index = _index;
        Rect? rect;
        while (index < widget.steps.length) {
          rect = _rectOf(widget.steps[index], overlay);
          if (rect != null) break;
          index++;
        }
        if (rect == null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => widget.onFinished(),
          );
          return const SizedBox.shrink();
        }
        final step = widget.steps[index];
        final reachable = widget.steps
            .where((s) => _rectOf(s, overlay) != null)
            .toList();
        final position = reachable.indexOf(step) + 1;
        final last = position >= reachable.length;

        final theme = Theme.of(context);
        final padding = MediaQuery.paddingOf(context);
        final hole = rect.inflate(SetflowSpacing.xs2);
        // 말풍선은 대상 아래가 기본, 아래가 모자라면 위로. 200은 말풍선의
        // 넉넉한 높이 — 큰 글자 배율에서도 버튼 줄이 화면 안에 남는다.
        final below = hole.bottom + 200 < size.height - padding.bottom;
        final cardWidth = (size.width - SetflowSpacing.gutter * 2).clamp(
          200.0,
          400.0,
        );

        return FadeTransition(
          opacity: _fade,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 딤 전체가 "다음"이다 — 게임 튜토리얼처럼 아무 데나 눌러도 넘어간다.
              GestureDetector(
                key: const ValueKey('coach-dim'),
                behavior: HitTestBehavior.opaque,
                onTap: _advance,
                child: CustomPaint(
                  painter: _SpotlightPainter(
                    hole: hole,
                    radius: SetflowRadii.md,
                    dim: theme.colorScheme.scrim.withValues(alpha: .66),
                    ring: theme.colorScheme.primary,
                  ),
                ),
              ),
              Positioned(
                left: (size.width - cardWidth) / 2,
                width: cardWidth,
                top: below ? hole.bottom + SetflowSpacing.md : null,
                bottom: below
                    ? null
                    : (size.height - hole.top + SetflowSpacing.md).clamp(
                        padding.bottom,
                        size.height - padding.top - 200,
                      ),
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  child: Material(
                    color: theme.colorScheme.surface,
                    // 딤 위라 그림자는 필요 없다 — 얇은 외곽선이 판을 잡아 준다.
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(SetflowRadii.lg),
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        SetflowSpacing.lg,
                        SetflowSpacing.lg,
                        SetflowSpacing.lg,
                        SetflowSpacing.sm,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.title,
                            key: const ValueKey('coach-title'),
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: SetflowSpacing.xs),
                          Text(
                            step.body,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: SetflowSpacing.md),
                          Row(
                            children: [
                              Text(
                                '$position / ${reachable.length}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              if (!last)
                                TextButton(
                                  key: const ValueKey('coach-skip'),
                                  onPressed: widget.onFinished,
                                  child: const Text('건너뛰기'),
                                ),
                              const SizedBox(width: SetflowSpacing.xs),
                              FilledButton(
                                key: const ValueKey('coach-next'),
                                onPressed: _advance,
                                child: Text(last ? '시작하기' : '다음'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 전체를 어둡게 칠하고 [hole]만 뚫는다. 구멍 둘레에 브랜드색 링을 두어
/// "여기"가 한눈에 읽히게 한다.
class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({
    required this.hole,
    required this.radius,
    required this.dim,
    required this.ring,
  });

  final Rect hole;
  final double radius;
  final Color dim;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final rounded = RRect.fromRectAndRadius(hole, Radius.circular(radius));
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(rounded),
    );
    canvas.drawPath(path, Paint()..color = dim);
    canvas.drawRRect(
      rounded,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.hole != hole || old.dim != dim || old.ring != ring;
}
