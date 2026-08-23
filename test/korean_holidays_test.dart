import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/korean_holidays.dart';

/// A calendar that paints the wrong day red is worse than one that paints none,
/// so the dates are pinned here rather than trusted.
void main() {
  String? nameOf(DateTime date) => holidayOf(date)?.name;

  test('fixed holidays are marked', () {
    expect(nameOf(DateTime(2026, 1, 1)), '신정');
    expect(nameOf(DateTime(2026, 3, 1)), '삼일절');
    expect(nameOf(DateTime(2026, 5, 5)), '어린이날');
    expect(nameOf(DateTime(2026, 6, 6)), '현충일');
    expect(nameOf(DateTime(2026, 8, 15)), '광복절');
    expect(nameOf(DateTime(2026, 10, 3)), '개천절');
    expect(nameOf(DateTime(2026, 10, 9)), '한글날');
    expect(nameOf(DateTime(2026, 12, 25)), '성탄절');
  });

  test('an ordinary day is not a holiday', () {
    expect(holidayOf(DateTime(2026, 8, 23)), isNull);
    expect(holidayOf(DateTime(2026, 4, 14)), isNull);
  });

  test('설날 and 추석 carry the day either side', () {
    // 2026 설날 = 2/17.
    expect(nameOf(DateTime(2026, 2, 16)), '설날 연휴');
    expect(nameOf(DateTime(2026, 2, 17)), '설날');
    expect(nameOf(DateTime(2026, 2, 18)), '설날 연휴');
    expect(holidayOf(DateTime(2026, 2, 19)), isNull);

    // 2026 추석 = 9/25.
    expect(nameOf(DateTime(2026, 9, 24)), '추석 연휴');
    expect(nameOf(DateTime(2026, 9, 25)), '추석');
    expect(nameOf(DateTime(2026, 9, 26)), '추석 연휴');
  });

  test('부처님오신날 follows the lunar table', () {
    expect(nameOf(DateTime(2025, 5, 5)), isNotNull); // 어린이날과 겹치는 해
    expect(nameOf(DateTime(2026, 5, 24)), '부처님오신날');
    expect(nameOf(DateTime(2027, 5, 13)), '부처님오신날');
  });

  test('a holiday on a weekend moves to the next working day', () {
    // 2026-08-15 광복절은 토요일 -> 8/17(월)이 대체공휴일.
    expect(DateTime(2026, 8, 15).weekday, DateTime.saturday);
    final substitute = holidayOf(DateTime(2026, 8, 17));
    expect(substitute?.name, '광복절');
    expect(substitute?.substitute, isTrue);

    // 2026-10-03 개천절도 토요일 -> 10/5(월).
    expect(DateTime(2026, 10, 3).weekday, DateTime.saturday);
    expect(holidayOf(DateTime(2026, 10, 5))?.substitute, isTrue);
  });

  test('현충일 and 신정 never get a substitute', () {
    // 2026-06-06 현충일은 토요일이지만 대체가 붙지 않는다.
    expect(DateTime(2026, 6, 6).weekday, DateTime.saturday);
    expect(holidayOf(DateTime(2026, 6, 8)), isNull);
  });

  test('a year outside the lunar table claims no lunar holiday', () {
    // 표를 넘어선 해는 조용히 비운다 — 틀린 날을 빨갛게 칠하지 않기 위해서다.
    expect(holidayOf(DateTime(2040, 2, 17)), isNull);
    // 양력 고정일은 표와 무관하게 계속 답한다.
    expect(nameOf(DateTime(2040, 3, 1)), '삼일절');
  });

  test('일요일과 공휴일이 쉬는 날, 토요일은 아니다', () {
    expect(isRestDay(DateTime(2026, 8, 23)), isTrue); // 일요일
    expect(isRestDay(DateTime(2026, 8, 22)), isFalse); // 토요일
    expect(isRestDay(DateTime(2026, 8, 15)), isTrue); // 광복절(토)
    expect(isRestDay(DateTime(2026, 8, 20)), isFalse); // 평일
  });
}
