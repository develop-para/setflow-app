import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/data/exercise_catalog_crosswalk.dart';

void main() {
  test('the public catalog has one unique Korean name for all 876 rows', () {
    final names = <String, String>{};
    for (final suffix in ['a', 'b', 'c']) {
      final file = File(
        'tool/data/free_exercise_db_names_ko_part_$suffix.json',
      );
      final decoded = jsonDecode(file.readAsStringSync());
      expect(decoded, isA<Map<String, dynamic>>());
      final part = decoded as Map<String, dynamic>;
      expect(part, hasLength(292));
      for (final entry in part.entries) {
        expect(names.containsKey(entry.key), isFalse);
        names[entry.key] = entry.value.toString().trim();
      }
    }

    expect(names, hasLength(876));
    expect(names.values.toSet(), hasLength(876));
    const correctedNames = <String, String>{
      'Dumbbell_Lying_Pronation': '엎드린 덤벨 어깨 외회전',
      'Dumbbell_Lying_Supination': '사이드 라잉 덤벨 어깨 외회전',
      'Hyperextensions_With_No_Hyperextension_Bench': '플랫 벤치 파트너 보조 하이퍼익스텐션',
      'Incline_Push-Up_Depth_Jump': '발 올린 뎁스 점프 푸시업',
      'Isometric_Wipers': '좌우 이동 와이퍼 푸시업',
      'Keg_Load': '케그 운반·플랫폼 적재',
      'Leg_Lift': '스탠딩 리어 레그 리프트',
      'Lower_Back_Curl': '엎드린 백 익스텐션',
      'One_Arm_Floor_Press': '원 암 바벨 플로어 프레스',
      'Overhead_Lat': '파트너 오버헤드 광배근 수축·이완 스트레칭',
      'Overhead_Triceps': '파트너 오버헤드 삼두근 수축·이완 스트레칭',
      'Platform_Hamstring_Slides': '수건 햄스트링 힐 슬라이드',
      'Power_Stairs': '중량물 계단 올리기',
      'Rocky_Pull-Ups_Pulldowns': '로키 프런트·비하인드 넥 풀업',
      'Skating': '롤러스케이팅',
      'Split_Squats': '점핑 얼터네이팅 스플릿 스쿼트',
      'Standing_Low-Pulley_One-Arm_Triceps_Extension':
          '스탠딩 로우 풀리 원암 오버헤드 트라이셉스 익스텐션',
    };
    for (final entry in correctedNames.entries) {
      expect(names, containsPair(entry.key, entry.value));
    }
    for (final entry in names.entries) {
      expect(entry.key.trim(), isNotEmpty);
      expect(entry.value, isNotEmpty);
      expect(entry.value.length, lessThanOrEqualTo(160));
      expect(
        RegExp(r'[가-힣]').hasMatch(entry.value),
        isTrue,
        reason: '${entry.key}에 한글 운동명이 없습니다: ${entry.value}',
      );
      expect(
        RegExp(r'[A-Za-z]').hasMatch(entry.value),
        isFalse,
        reason: '${entry.key}의 표시명에 영문이 남았습니다: ${entry.value}',
      );
    }

    expect(exerciseCatalog, hasLength(80));
    expect(freeExerciseDbBuiltInIds, hasLength(56));
    expect(
      exerciseCatalog.length + names.length - freeExerciseDbBuiltInIds.length,
      900,
      reason: '검수 번들과 DB 운동의 중복을 제거한 선택 목록 수',
    );
  });
}
