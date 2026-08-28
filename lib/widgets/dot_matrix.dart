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
const ledGlyphCols = 7;
const ledGlyphRows = 11;

/// 글자 사이 빈 칸.
const ledGlyphGap = 2;

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

/// 판 위의 한 칸. (x, y)는 칸 좌표다 — 픽셀이 아니다.
typedef LedCell = ({int x, int y});

/// [text]를 [origin]에서 시작해 켜야 할 칸들. 모르는 글자는 빈칸.
Iterable<LedCell> ledDigitCells(String text, {required LedCell origin}) sync* {
  var x = origin.x;
  for (final char in text.characters) {
    final rows = _glyphs[char];
    if (rows != null) {
      for (var r = 0; r < ledGlyphRows; r++) {
        for (var c = 0; c < ledGlyphCols; c++) {
          if (rows[r][c] == '1') yield (x: x + c, y: origin.y + r);
        }
      }
    }
    x += ledGlyphCols + ledGlyphGap;
  }
}

/// [text]가 차지하는 칸 수(가로).
int ledDigitsWidth(String text) => text.isEmpty
    ? 0
    : text.length * ledGlyphCols + (text.length - 1) * ledGlyphGap;

/// 판의 한 구역을 칠하는 띠 — 내 줄을 한 톤 밝게 하는 데 쓴다.
typedef LedBand = ({int fromY, int toY, Color color});

/// 판 한 장이 **하나의 격자**다. 숫자는 그 격자의 칸을 켜는 것이지 자기
/// 격자를 따로 갖지 않는다 — 그래야 실제 LED 판처럼 빈 자리와 숫자 자리의
/// 점이 같은 점이다. 글자(이름·종목·볼륨)는 이 위에 위젯으로 올린다.
class LedBoard extends StatelessWidget {
  const LedBoard({
    required this.pitch,
    required this.cols,
    required this.rows,
    required this.lit,
    this.bands = const [],
    this.edges = const [],
    super.key,
  });

  /// 칸 하나의 크기(픽셀). 점 지름은 이것의 0.68배.
  final double pitch;
  final int cols;
  final int rows;
  final Set<LedCell> lit;
  final List<LedBand> bands;

  /// 왼쪽 첫 열을 켜는 구간(y 범위) — 지금 세트 중인 사람의 줄.
  final List<({int fromY, int toY})> edges;

  Size get size => Size(cols * pitch, rows * pitch);

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: size,
        painter: _LedBoardPainter(
          pitch: pitch,
          cols: cols,
          rows: rows,
          lit: lit,
          bands: bands,
          edges: edges,
        ),
      ),
    );
  }
}

class _LedBoardPainter extends CustomPainter {
  const _LedBoardPainter({
    required this.pitch,
    required this.cols,
    required this.rows,
    required this.lit,
    required this.bands,
    required this.edges,
  });

  final double pitch;
  final int cols;
  final int rows;
  final Set<LedCell> lit;
  final List<LedBand> bands;
  final List<({int fromY, int toY})> edges;

  @override
  void paint(Canvas canvas, Size size) {
    final dot = pitch * .68;
    for (final band in bands) {
      canvas.drawRect(
        Rect.fromLTWH(
          0,
          band.fromY * pitch,
          size.width,
          (band.toY - band.fromY) * pitch,
        ),
        Paint()..color = band.color,
      );
    }
    // 꺼진 점 전부 — 한 번의 drawPoints. 매초 다시 그려도 값싸다.
    final off = <Offset>[
      for (var y = 0; y < rows; y++)
        for (var x = 0; x < cols; x++)
          if (!lit.contains((x: x, y: y)))
            Offset(x * pitch + pitch / 2, y * pitch + pitch / 2),
    ];
    canvas.drawPoints(
      PointMode.points,
      off,
      Paint()
        ..color = LedPalette.off
        ..strokeWidth = dot
        ..strokeCap = StrokeCap.round,
    );
    // 켜진 점 — 번짐 한 겹 아래, 또렷한 점 위. LED가 종이 위 잉크와 다른 이유.
    final glow = Paint()
      ..color = LedPalette.lit.withValues(alpha: .35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, dot * .6);
    final on = Paint()..color = LedPalette.lit;
    final edgeCells = <LedCell>{
      for (final edge in edges)
        for (var y = edge.fromY; y < edge.toY; y++) (x: 0, y: y),
    };
    for (final cell in lit.followedBy(edgeCells)) {
      final center = Offset(
        cell.x * pitch + pitch / 2,
        cell.y * pitch + pitch / 2,
      );
      canvas.drawCircle(center, dot * .75, glow);
      canvas.drawCircle(center, dot / 2, on);
    }
  }

  @override
  bool shouldRepaint(_LedBoardPainter old) =>
      old.pitch != pitch ||
      old.cols != cols ||
      old.rows != rows ||
      old.lit != lit ||
      old.bands != bands ||
      old.edges != edges;
}
