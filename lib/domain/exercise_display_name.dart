/// Exercise labels omit the manufacturer while keeping the machine line and
/// movement. This also covers names stored before labels became brand-free.
String exerciseDisplayName(String name) {
  final trimmed = name.trimLeft();
  final match = _manufacturerPrefix.firstMatch(trimmed);
  if (match == null) return name;
  final movement = trimmed.substring(match.end).trimLeft();
  return movement.isEmpty ? name : movement;
}

final _manufacturerPrefix = RegExp(
  r'^(?:테크노짐|Technogym|파나타|파나따|Panatta|뉴텍|New\s*tech|'
  r'해머스트렝스|해머스트랭스|해머스랭스|Hammer\s+Strength)'
  r'(?:\s*[-:·|]\s*|\s+)',
  caseSensitive: false,
);
