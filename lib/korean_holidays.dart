/// 대한민국 공휴일. 캘린더가 날짜를 빨갛게 칠할지 정하는 유일한 근거다.
///
/// 양력 고정일은 계산되지만 **설날·추석·부처님오신날은 음력이라 계산할 수 없다** —
/// 음력 변환기를 앱에 넣는 대신 연도별 표로 박아둔다. 표에 없는 해는 "공휴일 아님"으로
/// 답한다(틀린 날을 빨갛게 칠하느니 안 칠하는 쪽이 낫다). 표를 늘릴 때는 관보 기준으로
/// 확인할 것 — 음력 환산은 해마다 하루씩 어긋나기 쉽다.
library;

class KoreanHoliday {
  const KoreanHoliday(this.name, {this.substitute = false});

  final String name;

  /// 대체공휴일이면 true. 원래 공휴일이 주말과 겹쳐 뒤로 밀린 날이다.
  final bool substitute;
}

/// 음력에서 온 공휴일. 연휴는 앞뒤 하루씩 함께 쉰다.
///
/// key = 연도, value = (설날 당일, 추석 당일, 부처님오신날).
const _lunarAnchors =
    <int, ({(int, int) seollal, (int, int) chuseok, (int, int) buddha})>{
      2024: (seollal: (2, 10), chuseok: (9, 17), buddha: (5, 15)),
      2025: (seollal: (1, 29), chuseok: (10, 6), buddha: (5, 5)),
      2026: (seollal: (2, 17), chuseok: (9, 25), buddha: (5, 24)),
      2027: (seollal: (2, 7), chuseok: (9, 15), buddha: (5, 13)),
      2028: (seollal: (1, 27), chuseok: (10, 3), buddha: (5, 2)),
    };

/// 양력으로 날짜가 고정된 공휴일.
const _fixed = <(int, int), String>{
  (1, 1): '신정',
  (3, 1): '삼일절',
  (5, 5): '어린이날',
  (6, 6): '현충일',
  (8, 15): '광복절',
  (10, 3): '개천절',
  (10, 9): '한글날',
  (12, 25): '성탄절',
};

/// 대체공휴일이 붙는 공휴일. 현충일과 신정은 붙지 않는다.
const _substituted = {
  '삼일절',
  '어린이날',
  '광복절',
  '개천절',
  '한글날',
  '성탄절',
  '부처님오신날',
  '설날',
  '설날 연휴',
  '추석',
  '추석 연휴',
};

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// 대체공휴일을 뺀, 달력에 원래 찍혀 있는 공휴일.
String? _baseHolidayName(DateTime date) {
  final fixed = _fixed[(date.month, date.day)];
  if (fixed != null) return fixed;

  final anchors = _lunarAnchors[date.year];
  if (anchors == null) return null;

  final seollal = DateTime(date.year, anchors.seollal.$1, anchors.seollal.$2);
  final chuseok = DateTime(date.year, anchors.chuseok.$1, anchors.chuseok.$2);
  final buddha = DateTime(date.year, anchors.buddha.$1, anchors.buddha.$2);
  final day = _dateOnly(date);

  if (day == buddha) return '부처님오신날';
  for (final (anchor, label) in [(seollal, '설날'), (chuseok, '추석')]) {
    if (day == anchor) return label;
    if (day == anchor.subtract(const Duration(days: 1)) ||
        day == anchor.add(const Duration(days: 1))) {
      return '$label 연휴';
    }
  }
  return null;
}

/// [date]가 공휴일이면 그 이름, 아니면 null.
///
/// 대체공휴일도 함께 답한다. 규칙: 설날·추석 연휴는 일요일과 겹칠 때만, 나머지는
/// 토·일 어느 쪽과 겹쳐도 **다음 평일**로 밀린다. 이미 다른 공휴일인 날은 건너뛴다.
KoreanHoliday? holidayOf(DateTime date) {
  final day = _dateOnly(date);
  final own = _baseHolidayName(day);
  if (own != null) return KoreanHoliday(own);

  // 앞선 최대 열흘을 되짚어, 주말에 걸려 이 날짜까지 밀려온 공휴일이 있는지 본다.
  for (var back = 1; back <= 10; back++) {
    final origin = day.subtract(Duration(days: back));
    final name = _baseHolidayName(origin);
    if (name == null || !_substituted.contains(name)) continue;

    final lunarPack = name.startsWith('설날') || name.startsWith('추석');
    final weekendHit = lunarPack
        ? origin.weekday == DateTime.sunday
        : origin.weekday == DateTime.saturday ||
              origin.weekday == DateTime.sunday;
    if (!weekendHit) continue;

    // 그 공휴일 다음의 첫 평일이 이 날짜인가.
    var cursor = origin.add(const Duration(days: 1));
    while (cursor.weekday == DateTime.saturday ||
        cursor.weekday == DateTime.sunday ||
        _baseHolidayName(cursor) != null) {
      cursor = cursor.add(const Duration(days: 1));
    }
    if (cursor == day) return KoreanHoliday(name, substitute: true);
  }
  return null;
}

/// 날짜를 빨갛게 칠할지. 일요일과 공휴일이 빨강, 토요일은 파랑이라 여기엔 없다.
bool isRestDay(DateTime date) =>
    date.weekday == DateTime.sunday || holidayOf(date) != null;
