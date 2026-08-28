import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';

/// 실제 전광판의 팔레트 — 검은 판, 꺼진 LED, 켜진 LED.
///
/// 전광판은 라이트·다크 어느 테마에서도 **검다**. 경기장 전광판이 낮이라고
/// 하얘지지 않는 것과 같다. 그래서 `context.setflowColors`가 아니라 고정
/// 뉴트럴 램프와 브랜드 라임을 직접 쓴다 — 이 판은 테마 따라 뒤집히는 면이
/// 아니다. 라임 위 글자는 언제나 잉크(`onBrand`).
abstract final class LedPalette {
  static const panel = SetflowNeutral.n900;
  static const edge = SetflowNeutral.n700;
  static const off = SetflowNeutral.n800;
  static const lit = SetflowColors.brand;
  static const litInk = SetflowColors.onBrand;
  static const text = SetflowNeutral.n0;
  static const muted = SetflowNeutral.n400;
  static const dimText = SetflowNeutral.n500;
}

/// 7×11 도트 폰트. 숫자만 — 전광판이 도트로 쓰는 것은 점수뿐이고, 이름과
/// 종목은 글자로 남긴다(한글 도트 폰트를 만들어 쓰면 읽기 시험이 된다).
/// 5×7은 멀리서 보는 옛 전광판의 해상도였다. 손 안의 화면은 가까우니 점을
/// 작게, 많이 — 획이 둥글게 읽힌다.
const _cols = 7;
const _rows = 11;
const _glyphs = <String, List<String>>{
  '0': [
    '0011100',
    '0100010',
    '1000001',
    '1000001',
    '1000001',
    '1000001',
    '1000001',
    '1000001',
    '1000001',
    '0100010',
    '0011100',
  ],
  '1': [
    '0001000',
    '0011000',
    '0101000',
    '0001000',
    '0001000',
    '0001000',
    '0001000',
    '0001000',
    '0001000',
    '0001000',
    '0111110',
  ],
  '2': [
    '0011100',
    '0100010',
    '1000001',
    '0000001',
    '0000010',
    '0000100',
    '0001000',
    '0010000',
    '0100000',
    '1000000',
    '1111111',
  ],
  '3': [
    '0011100',
    '0100010',
    '1000001',
    '0000001',
    '0000010',
    '0001100',
    '0000010',
    '0000001',
    '1000001',
    '0100010',
    '0011100',
  ],
  '4': [
    '0000010',
    '0000110',
    '0001010',
    '0010010',
    '0100010',
    '1000010',
    '1111111',
    '0000010',
    '0000010',
    '0000010',
    '0000010',
  ],
  '5': [
    '1111111',
    '1000000',
    '1000000',
    '1000000',
    '1111100',
    '0000010',
    '0000001',
    '0000001',
    '1000001',
    '0100010',
    '0011100',
  ],
  '6': [
    '0001110',
    '0010000',
    '0100000',
    '1000000',
    '1011100',
    '1100010',
    '1000001',
    '1000001',
    '1000001',
    '0100010',
    '0011100',
  ],
  '7': [
    '1111111',
    '0000001',
    '0000010',
    '0000010',
    '0000100',
    '0000100',
    '0001000',
    '0001000',
    '0010000',
    '0010000',
    '0010000',
  ],
  '8': [
    '0011100',
    '0100010',
    '1000001',
    '1000001',
    '0100010',
    '0011100',
    '0100010',
    '1000001',
    '1000001',
    '0100010',
    '0011100',
  ],
  '9': [
    '0011100',
    '0100010',
    '1000001',
    '1000001',
    '1000001',
    '0100011',
    '0011101',
    '0000001',
    '0000010',
    '0000100',
    '0111000',
  ],
  '-': [
    '0000000',
    '0000000',
    '0000000',
    '0000000',
    '0000000',
    '1111111',
    '0000000',
    '0000000',
    '0000000',
    '0000000',
    '0000000',
  ],
};

/// 점 사이 간격. 지름의 절반보다 촘촘해야 가까이서 획으로 읽힌다.
double _gapFor(double dot) => dot * .45;

/// 도트 매트릭스로 그린 숫자. 켜진 점은 [lit], 꺼진 점도 희미하게 남겨
/// LED 판의 격자가 보이게 한다 — 그것이 "인쇄된 숫자"와 "전광판"의 차이다.
class DotMatrixNumber extends StatelessWidget {
  const DotMatrixNumber({
    required this.text,
    required this.dot,
    this.lit = LedPalette.lit,
    this.off = LedPalette.off,
    this.semanticsLabel,
    super.key,
  });

  /// 숫자와 '-'만. 다른 글자는 빈칸으로 그린다.
  final String text;

  /// 점 하나의 지름. 점 사이 간격은 지름의 0.45배.
  final double dot;
  final Color lit;
  final Color off;
  final String? semanticsLabel;

  static double widthFor(String text, double dot) {
    if (text.isEmpty) return 0;
    final gap = _gapFor(dot);
    final glyph = _cols * dot + (_cols - 1) * gap;
    return text.length * glyph + (text.length - 1) * (dot + gap) * 2;
  }

  static double heightFor(double dot) =>
      _rows * dot + (_rows - 1) * _gapFor(dot);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel ?? text,
      child: ExcludeSemantics(
        child: CustomPaint(
          size: Size(widthFor(text, dot), heightFor(dot)),
          painter: _DotMatrixPainter(text: text, dot: dot, lit: lit, off: off),
        ),
      ),
    );
  }
}

class _DotMatrixPainter extends CustomPainter {
  const _DotMatrixPainter({
    required this.text,
    required this.dot,
    required this.lit,
    required this.off,
  });

  final String text;
  final double dot;
  final Color lit;
  final Color off;

  @override
  void paint(Canvas canvas, Size size) {
    final gap = _gapFor(dot);
    final pitch = dot + gap;
    final offPaint = Paint()..color = off;
    final litPaint = Paint()..color = lit;
    // 켜진 점 둘레의 번짐 — LED가 종이 위 잉크와 다른 이유.
    final glowPaint = Paint()
      ..color = lit.withValues(alpha: .35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, dot * .6);
    var x = 0.0;
    for (final char in text.characters) {
      final rows = _glyphs[char];
      for (var r = 0; r < _rows; r++) {
        for (var c = 0; c < _cols; c++) {
          final center = Offset(x + c * pitch + dot / 2, r * pitch + dot / 2);
          final on = rows != null && rows[r][c] == '1';
          if (on) {
            canvas.drawCircle(center, dot * .7, glowPaint);
            canvas.drawCircle(center, dot / 2, litPaint);
          } else {
            canvas.drawCircle(center, dot / 2, offPaint);
          }
        }
      }
      x += _cols * pitch + (dot + gap);
    }
  }

  @override
  bool shouldRepaint(_DotMatrixPainter old) =>
      old.text != text || old.dot != dot || old.lit != lit || old.off != off;
}

/// LED 한 줄로 그린 진행 바. 폭에 들어가는 만큼 점을 놓고 [progress]만큼 켠다.
class LedBar extends StatelessWidget {
  const LedBar({
    required this.progress,
    this.dot = 6,
    this.lit = LedPalette.lit,
    this.off = LedPalette.off,
    super.key,
  });

  final double progress;
  final double dot;
  final Color lit;
  final Color off;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: dot,
      width: double.infinity,
      child: CustomPaint(
        painter: _LedBarPainter(
          progress: progress.clamp(0.0, 1.0),
          dot: dot,
          lit: lit,
          off: off,
        ),
      ),
    );
  }
}

class _LedBarPainter extends CustomPainter {
  const _LedBarPainter({
    required this.progress,
    required this.dot,
    required this.lit,
    required this.off,
  });

  final double progress;
  final double dot;
  final Color lit;
  final Color off;

  @override
  void paint(Canvas canvas, Size size) {
    final pitch = dot * 1.5;
    final count = (size.width / pitch).floor();
    if (count <= 0) return;
    final on = (progress * count).round();
    final litPaint = Paint()..color = lit;
    final offPaint = Paint()..color = off;
    for (var i = 0; i < count; i++) {
      canvas.drawCircle(
        Offset(i * pitch + dot / 2, size.height / 2),
        dot / 2,
        i < on ? litPaint : offPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_LedBarPainter old) =>
      old.progress != progress || old.dot != dot || old.lit != lit;
}

/// 검은 판 + 꺼진 LED 격자. 자식(전광판 줄들)이 그 위에 올라간다.
class LedPanel extends StatelessWidget {
  const LedPanel({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(SetflowRadii.lg),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: LedPalette.panel,
          borderRadius: BorderRadius.circular(SetflowRadii.lg),
          border: Border.all(color: LedPalette.edge),
        ),
        child: CustomPaint(painter: const _GridPainter(), child: child),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const pitch = 8.0;
    final points = <Offset>[
      for (var y = pitch / 2; y < size.height; y += pitch)
        for (var x = pitch / 2; x < size.width; x += pitch) Offset(x, y),
    ];
    // 한 번의 drawPoints — 매초 다시 그려도 값싸다.
    canvas.drawPoints(
      PointMode.points,
      points,
      Paint()
        ..color = LedPalette.off.withValues(alpha: .55)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}
