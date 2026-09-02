import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/theme/muscle_illustrations.dart';

void main() {
  test('every exercise category maps to a distinct category fill', () {
    const muscles = ['가슴', '등', '어깨', '하체', '팔', '복근', '유산소'];

    final fills = muscles.map(SetflowMuscleIllustrations.fillForMuscle).toSet();

    expect(SetflowMuscleIllustrations.muscles, muscles);
    expect(fills, hasLength(muscles.length));
  });
}
