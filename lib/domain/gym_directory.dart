/// A public workout place. This identity never grants business workspace access.
class GymPlace {
  const GymPlace({
    required this.id,
    required this.name,
    required this.address,
    required this.region,
    this.aliases = const [],
    this.roadAddress,
    this.lotAddress,
    this.district,
  });

  final String id;
  final String name;
  final List<String> aliases;
  final String address;
  final String? roadAddress;
  final String? lotAddress;
  final String region;
  final String? district;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'aliases': aliases,
    'address': address,
    'roadAddress': roadAddress,
    'lotAddress': lotAddress,
    'region': region,
    'district': district,
  };

  factory GymPlace.fromJson(Map<String, dynamic> json) {
    final aliases = json['aliases'] ?? const <String>[];
    if (aliases is! List || aliases.any((alias) => alias is! String)) {
      throw const FormatException('헬스장 검색 이름을 확인해주세요.');
    }
    return GymPlace(
      id: _field(json, 'id', 80),
      name: _field(json, 'name', 150),
      address: _field(json, 'address', 500),
      region: _field(json, 'region', 100),
      aliases: List.unmodifiable(
        aliases.map((alias) => _text(alias, 'alias', 150)),
      ),
      roadAddress: _optionalField(json, 'roadAddress', 500),
      lotAddress: _optionalField(json, 'lotAddress', 500),
      district: _optionalField(json, 'district', 100),
    );
  }
}

class GymDirectorySource {
  const GymDirectorySource({
    required this.label,
    required this.fileName,
    required this.sha256,
    this.sourceUrl,
    this.sourceDataDate,
    this.verifiedAt,
  });

  final String label;
  final String fileName;
  final String sha256;
  final String? sourceUrl;
  final String? sourceDataDate;
  final DateTime? verifiedAt;

  factory GymDirectorySource.fromJson(Map<String, dynamic> json) =>
      GymDirectorySource(
        label: _field(json, 'label', 200),
        fileName: _field(json, 'fileName', 200),
        sha256: _field(json, 'sha256', 64),
        sourceUrl: _optionalField(json, 'sourceUrl', 2000),
        sourceDataDate: _optionalField(json, 'sourceDataDate', 100),
        verifiedAt: _optionalDate(json, 'verifiedAt'),
      );
}

class GymDirectoryCatalog {
  GymDirectoryCatalog({required this.source, required List<GymPlace> gyms})
    : gyms = List.unmodifiable(gyms),
      _searchText = List.unmodifiable(gyms.map(_gymSearchText));

  final GymDirectorySource source;
  final List<GymPlace> gyms;
  final List<String> _searchText;

  factory GymDirectoryCatalog.fromJson(Map<String, dynamic> json) {
    final source = json['source'];
    final rows = json['gyms'];
    if (source is! Map || rows is! List) {
      throw const FormatException('헬스장 목록 형식을 확인해주세요.');
    }
    final gyms = rows
        .map((row) {
          if (row is! Map) {
            throw const FormatException('헬스장 정보를 읽을 수 없어요.');
          }
          return GymPlace.fromJson(Map<String, dynamic>.from(row));
        })
        .toList(growable: false);
    if (gyms.map((gym) => gym.id).toSet().length != gyms.length) {
      throw const FormatException('헬스장 ID가 중복됐어요.');
    }
    return GymDirectoryCatalog(
      source: GymDirectorySource.fromJson(Map<String, dynamic>.from(source)),
      gyms: gyms,
    );
  }

  /// Every query token must occur in the name, aliases or address. Spaces
  /// inside those fields do not prevent matching a joined Korean place name.
  List<GymPlace> search(String query, {String? region, int limit = 60}) {
    if (limit <= 0) return const [];
    final tokens = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    final regionKey = region == null ? null : _compact(region);
    final matches = <GymPlace>[];
    for (var i = 0; i < gyms.length; i++) {
      final gym = gyms[i];
      if (regionKey != null &&
          regionKey.isNotEmpty &&
          _compact(gym.region) != regionKey) {
        continue;
      }
      if (tokens.every((token) => _searchText[i].contains(_compact(token)))) {
        matches.add(gym);
        if (matches.length == limit) break;
      }
    }
    return List.unmodifiable(matches);
  }
}

enum GymDirectoryRequestKind { add, correction, claim }

/// A device draft becomes submitted only after the server returns its receipt.
class GymDirectoryRequest {
  const GymDirectoryRequest({
    required this.id,
    required this.kind,
    required this.gymName,
    required this.address,
    required this.note,
    required this.createdAt,
    this.facilityId,
    this.submittedAt,
    this.ownerUserId,
  });

  final String id;
  final GymDirectoryRequestKind kind;
  final String? facilityId;
  final String gymName;
  final String address;
  final String note;
  final DateTime createdAt;
  final DateTime? submittedAt;
  final String? ownerUserId;

  bool get isSubmitted => submittedAt != null;

  GymDirectoryRequest copyWith({DateTime? submittedAt, String? ownerUserId}) =>
      GymDirectoryRequest(
        id: id,
        kind: kind,
        facilityId: facilityId,
        gymName: gymName,
        address: address,
        note: note,
        createdAt: createdAt,
        submittedAt: submittedAt ?? this.submittedAt,
        ownerUserId: ownerUserId ?? this.ownerUserId,
      );

  void validate() {
    if (!RegExp(r'^[a-zA-Z0-9_:-]{1,80}$').hasMatch(id)) {
      throw const FormatException('제안 ID를 확인해주세요.');
    }
    _text(gymName, 'gymName', 150);
    _text(address, 'address', 500);
    _text(note, 'note', 2000, allowEmpty: true);
    if (kind == GymDirectoryRequestKind.add && facilityId != null) {
      throw const FormatException('새 헬스장 제안에는 기존 장소 ID를 넣을 수 없어요.');
    }
    if (kind != GymDirectoryRequestKind.add) {
      _text(facilityId, 'facilityId', 80);
    }
    if (ownerUserId != null) _text(ownerUserId, 'ownerUserId', 80);
    if (submittedAt != null && ownerUserId == null) {
      throw const FormatException('접수한 계정 정보를 확인해주세요.');
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'facilityId': facilityId,
    'gymName': gymName,
    'address': address,
    'note': note,
    'createdAt': createdAt.toIso8601String(),
    'submittedAt': submittedAt?.toIso8601String(),
    'ownerUserId': ownerUserId,
  };

  factory GymDirectoryRequest.fromJson(Map<String, dynamic> json) {
    final kind = GymDirectoryRequestKind.values
        .where((kind) => kind.name == json['kind'])
        .firstOrNull;
    final createdAt = _optionalDate(json, 'createdAt');
    if (kind == null || createdAt == null) {
      throw const FormatException('제안 종류 또는 보관 시각을 확인해주세요.');
    }
    final request = GymDirectoryRequest(
      id: _field(json, 'id', 80),
      kind: kind,
      facilityId: _optionalField(json, 'facilityId', 80),
      gymName: _field(json, 'gymName', 150),
      address: _field(json, 'address', 500),
      note: _field(json, 'note', 2000, allowEmpty: true),
      createdAt: createdAt,
      submittedAt: _optionalDate(json, 'submittedAt'),
      ownerUserId: _optionalField(json, 'ownerUserId', 80),
    );
    request.validate();
    return request;
  }
}

/// Personal choices belong to this device, including while signed out.
class GymPlaceLibrary {
  GymPlaceLibrary({
    List<GymPlace> gyms = const [],
    this.selectedId,
    List<GymDirectoryRequest> requests = const [],
  }) : gyms = List.unmodifiable(gyms),
       requests = List.unmodifiable(requests);

  final List<GymPlace> gyms;
  final String? selectedId;
  final List<GymDirectoryRequest> requests;

  GymPlace? get selectedGym =>
      gyms.where((gym) => gym.id == selectedId).firstOrNull;

  GymPlaceLibrary copyWith({
    List<GymPlace>? gyms,
    String? selectedId,
    bool clearSelection = false,
    List<GymDirectoryRequest>? requests,
  }) => GymPlaceLibrary(
    gyms: gyms ?? this.gyms,
    selectedId: clearSelection ? null : selectedId ?? this.selectedId,
    requests: requests ?? this.requests,
  );
}

String _gymSearchText(GymPlace gym) => [
  gym.name,
  ...gym.aliases,
  gym.address,
  gym.roadAddress ?? '',
  gym.lotAddress ?? '',
  gym.region,
  gym.district ?? '',
].map(_compact).join('\n');

String _compact(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'\s+'), '');

String _field(
  Map<String, dynamic> json,
  String key,
  int maxLength, {
  bool allowEmpty = false,
}) => _text(json[key], key, maxLength, allowEmpty: allowEmpty);

String? _optionalField(Map<String, dynamic> json, String key, int maxLength) =>
    json[key] == null ? null : _text(json[key], key, maxLength);

String _text(
  Object? value,
  String key,
  int maxLength, {
  bool allowEmpty = false,
}) {
  if (value is! String) {
    throw FormatException('$key 정보가 올바르지 않아요.');
  }
  final text = value.trim();
  if (text.length > maxLength || (!allowEmpty && text.isEmpty)) {
    throw FormatException('$key 정보의 길이를 확인해주세요.');
  }
  return text;
}

DateTime? _optionalDate(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  final date = value is String ? DateTime.tryParse(value) : null;
  if (date == null) throw FormatException('$key 시각을 확인해주세요.');
  return date;
}
