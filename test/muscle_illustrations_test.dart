import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/theme/muscle_illustrations.dart';

void main() {
  test('every exercise category maps to a distinct PNG mascot', () {
    const muscles = ['가슴', '등', '어깨', '하체', '팔', '복근', '유산소'];

    final assets = muscles.map(SetflowMuscleIllustrations.forMuscle).toSet();

    expect(assets, hasLength(muscles.length));
    expect(assets.every((asset) => asset.endsWith('.png')), isTrue);
  });
}
