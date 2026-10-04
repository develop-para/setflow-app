/// Input units only. Workout weights remain kilograms in every stored model.
enum WeightInputUnit {
  kg,
  lb;

  static const kilogramsPerPound = 0.45359237;

  String get symbol => name;

  double fromKilograms(double value) =>
      this == kg ? value : value / kilogramsPerPound;

  double toKilograms(double value) =>
      this == kg ? value : value * kilogramsPerPound;
}

/// Keep converted weights when a routine draft is serialized through a field.
String formatWeightInput(double value) =>
    value.toStringAsFixed(8).replaceFirst(RegExp(r'\.?0+$'), '');
