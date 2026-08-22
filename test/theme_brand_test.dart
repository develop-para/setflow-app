import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/theme.dart';

double _contrastRatio(Color a, Color b) {
  final aLuminance = a.computeLuminance();
  final bLuminance = b.computeLuminance();
  final lighter = aLuminance > bLuminance ? aLuminance : bLuminance;
  final darker = aLuminance > bLuminance ? bLuminance : aLuminance;
  return (lighter + .05) / (darker + .05);
}

void main() {
  test('light and dark themes keep the Setflow yellow brand accent', () {
    expect(SetflowColors.primary, const Color(0xFFFFCA10));
    expect(SetflowTheme.light.colorScheme.primary, SetflowColors.primary);
    expect(SetflowTheme.dark.colorScheme.primary, SetflowColors.primary);
  });

  test('brand-yellow controls use a readable dark foreground', () {
    for (final theme in [SetflowTheme.light, SetflowTheme.dark]) {
      expect(
        _contrastRatio(theme.colorScheme.primary, theme.colorScheme.onPrimary),
        greaterThanOrEqualTo(4.5),
      );
      expect(theme.colorScheme.onPrimary, isNot(Colors.white));
    }
  });

  test('semantic accents retain distinct Setflow state colours', () {
    final colors = SetflowTheme.light.extension<SetflowSemanticColors>()!;
    expect(colors.success, SetflowColors.green);
    expect(colors.warning, SetflowColors.warning);
    expect(colors.info, SetflowColors.info);
    expect(colors.teal, SetflowColors.teal);
    expect(colors.blue, SetflowColors.blue);
    expect(colors.purple, SetflowColors.purple);
    expect(colors.orange, SetflowColors.orange);
  });

  test('selected checkboxes stay readable on the teal fill', () {
    for (final theme in [SetflowTheme.light, SetflowTheme.dark]) {
      final selected = {WidgetState.selected};
      final fill = theme.checkboxTheme.fillColor!.resolve(selected)!;
      final check = theme.checkboxTheme.checkColor!.resolve(selected)!;
      expect(_contrastRatio(fill, check), greaterThanOrEqualTo(3));
    }
  });
}
