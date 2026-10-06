import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:setflow/data/asset_gym_directory_repository.dart';
import 'package:setflow/data/gym_directory_repository.dart';
import 'package:setflow/data/hive_gym_place_repository.dart';
import 'package:setflow/data/supabase_gym_directory_request_repository.dart';
import 'package:setflow/domain/gym_directory.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _userId = '11111111-1111-4111-8111-111111111111';
const _otherUserId = '22222222-2222-4222-8222-222222222222';
const _gym = GymPlace(
  id: 'place-example',
  name: '빌드업 피트니스',
  aliases: ['빌드업 PT&골프 종각역점'],
  address: '서울특별시 종로구 청계천로 67',
  roadAddress: '서울특별시 종로구 청계천로 67',
  lotAddress: '서울특별시 종로구 관철동 155',
  region: '서울특별시',
  district: '종로구',
);

GymDirectoryRequest _request({
  String id = 'request-test-1',
  String? ownerUserId,
  DateTime? submittedAt,
}) => GymDirectoryRequest(
  id: id,
  kind: GymDirectoryRequestKind.correction,
  facilityId: _gym.id,
  gymName: _gym.name,
  address: _gym.address,
  note: '도로명 주소의 층을 확인해주세요.',
  createdAt: DateTime.utc(2026, 10, 6, 12),
  ownerUserId: ownerUserId,
  submittedAt: submittedAt,
);

Future<void> _signIn(SupabaseClient client, {String userId = _userId}) =>
    client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-access-token',
        'refresh_token': 'test-refresh-token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': userId,
          'email': 'member@example.test',
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-10-01T00:00:00Z',
        },
      }),
    );

SupabaseClient _client(MockClient httpClient) => SupabaseClient(
  'https://example.test',
  'test-key',
  authOptions: const AuthClientOptions(autoRefreshToken: false),
  httpClient: httpClient,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'search joins Korean spaces, aliases and both addresses with AND tokens',
    () {
      final catalog = GymDirectoryCatalog(
        source: const GymDirectorySource(
          label: '제공 목록',
          fileName: 'gyms.xlsx',
          sha256: 'test',
        ),
        gyms: [
          _gym,
          const GymPlace(
            id: 'other-place',
            name: '빌드업 피트니스',
            address: '부산광역시 해운대구 중동 1',
            region: '부산광역시',
          ),
        ],
      );
      expect(catalog.search('빌드업피트니스 종로').single.id, _gym.id);
      expect(catalog.search('골프 관철동').single.id, _gym.id);
      expect(catalog.search('골프 부산'), isEmpty);
      expect(catalog.search('빌드업', region: '부산광역시').single.id, 'other-place');
      expect(catalog.search('', limit: 1), hasLength(1));
      expect(catalog.search('', limit: 0), isEmpty);
    },
  );

  test(
    'the exported workbook is readable and does not invent verification',
    () async {
      final catalog = await AssetGymDirectoryRepository().loadCatalog();
      expect(catalog.gyms, hasLength(16784));
      expect(catalog.source.sourceUrl, isNull);
      expect(catalog.source.sourceDataDate, isNull);
      expect(catalog.source.verifiedAt, isNull);
      expect(catalog.source.sha256, hasLength(64));
      expect(catalog.search('빌드업 골프 종각').single.name, contains('빌드업'));
    },
  );

  test(
    'asset reader caches a successful catalog and retries a failed read',
    () async {
      final bundle = _CatalogBundle(_gym);
      final repository = AssetGymDirectoryRepository(bundle: bundle);
      await expectLater(repository.loadCatalog(), throwsStateError);
      final first = await repository.loadCatalog();
      final second = await repository.loadCatalog();
      expect(identical(first, second), isTrue);
      expect(bundle.reads, 2);
    },
  );

  test(
    'codec preserves choice, aliases and draft versus real server receipt',
    () {
      final draft = _request();
      final receipt = _request(
        id: 'request-received',
        ownerUserId: _userId,
        submittedAt: DateTime.utc(2026, 10, 6, 13),
      );
      final decoded = GymPlaceLibraryCodec.decode(
        GymPlaceLibraryCodec.encode(
          GymPlaceLibrary(
            gyms: [_gym],
            selectedId: _gym.id,
            requests: [draft, receipt],
          ),
        ),
      );
      expect(decoded.selectedGym?.id, _gym.id);
      expect(decoded.gyms.single.aliases, _gym.aliases);
      expect(decoded.requests.first.isSubmitted, isFalse);
      expect(decoded.requests.last.submittedAt, receipt.submittedAt);
      expect(decoded.requests.last.ownerUserId, _userId);
      expect(decoded.copyWith(clearSelection: true).selectedId, isNull);
      expect(() => decoded.gyms.add(_gym), throwsUnsupportedError);
      expect(() => decoded.requests.clear(), throwsUnsupportedError);
    },
  );

  test(
    'invalid replacement leaves the whole existing device library intact',
    () async {
      final repository = MemoryGymPlaceRepository(
        initialValue: GymPlaceLibrary(gyms: [_gym], selectedId: _gym.id),
      );
      await expectLater(
        repository.save(GymPlaceLibrary(gyms: [_gym], selectedId: 'missing')),
        throwsFormatException,
      );
      await expectLater(
        repository.save(GymPlaceLibrary(gyms: [_gym, _gym])),
        throwsFormatException,
      );
      await expectLater(
        repository.save(
          GymPlaceLibrary(
            requests: [_request(submittedAt: DateTime.utc(2026))],
          ),
        ),
        throwsFormatException,
      );
      expect((await repository.load()).selectedGym?.id, _gym.id);
    },
  );

  test(
    'Hive flush persists places and unsubmitted requests after reopening',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'setflow-gym-places-test-',
      );
      final boxName = 'gym_places_${DateTime.now().microsecondsSinceEpoch}';
      Hive.init(directory.path);
      addTearDown(() async {
        if (Hive.isBoxOpen(boxName)) await Hive.box<String>(boxName).close();
        await directory.delete(recursive: true);
      });
      final first = HiveGymPlaceRepository(boxName: boxName);
      await first.save(
        GymPlaceLibrary(
          gyms: [_gym],
          selectedId: _gym.id,
          requests: [_request()],
        ),
      );
      await Hive.box<String>(boxName).close();
      final reopened = await HiveGymPlaceRepository(boxName: boxName).load();
      expect(reopened.selectedGym?.address, _gym.address);
      expect(reopened.requests.single.isSubmitted, isFalse);
      expect(reopened.requests.single.id, 'request-test-1');
    },
  );

  for (final status in [404, 403, 503]) {
    test(
      'server capability returns false for HTTP $status without sending a draft',
      () async {
        final calls = <http.Request>[];
        final client = _client(
          MockClient((request) async {
            calls.add(request);
            return http.Response(
              jsonEncode({
                'code': status == 404 ? 'PGRST202' : '42501',
                'message': 'Unavailable',
              }),
              status,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        addTearDown(client.dispose);
        expect(
          await SupabaseGymDirectoryRequestRepository(client).isAvailable(),
          isFalse,
        );
        expect(
          calls.single.url.path,
          '/rest/v1/rpc/gym_directory_request_service_available',
        );
      },
    );
  }

  test(
    'an explicit retry keeps the ID and receives the original server timestamp',
    () async {
      final calls = <http.Request>[];
      final client = _client(
        MockClient((request) async {
          calls.add(request);
          if (calls.length == 1) throw const SocketException('Lost response');
          return http.Response(
            jsonEncode({
              'id': 'request-test-1',
              'owner_user_id': _userId,
              'submitted_at': '2026-10-06T13:00:00Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      await _signIn(client);
      final repository = SupabaseGymDirectoryRequestRepository(client);
      await expectLater(
        repository.submitRequest(_request()),
        throwsA(isA<SocketException>()),
      );
      final receipt = await repository.submitRequest(_request());
      expect(receipt, DateTime.utc(2026, 10, 6, 13));
      expect(calls, hasLength(2));
      expect(calls.first.body, calls.last.body);
      final payload = jsonDecode(calls.last.body) as Map;
      expect(payload['request_id'], 'request-test-1');
      expect(payload.containsKey('owner_user_id'), isFalse);
      expect(payload.containsKey('submitted_at'), isFalse);
    },
  );

  test('guest and foreign account drafts cannot be submitted', () async {
    var calls = 0;
    final client = _client(
      MockClient((request) async {
        calls++;
        return http.Response('null', 200);
      }),
    );
    addTearDown(client.dispose);
    final repository = SupabaseGymDirectoryRequestRepository(client);
    await expectLater(repository.submitRequest(_request()), throwsStateError);
    await _signIn(client);
    await expectLater(
      repository.submitRequest(_request(ownerUserId: _otherUserId)),
      throwsStateError,
    );
    expect(calls, 0);
  });

  test(
    'an account switch during RPC keeps a valid receipt for its captured owner',
    () async {
      final started = Completer<void>();
      final response = Completer<http.Response>();
      late http.Request submittedRequest;
      final client = _client(
        MockClient((request) async {
          submittedRequest = request;
          started.complete();
          return response.future;
        }),
      );
      addTearDown(client.dispose);
      await _signIn(client);
      final repository = SupabaseGymDirectoryRequestRepository(client);
      final submission = repository.submitRequest(
        _request(ownerUserId: _userId),
      );
      await started.future;
      await _signIn(client, userId: _otherUserId);
      response.complete(
        http.Response(
          jsonEncode({
            'id': 'request-test-1',
            'owner_user_id': _userId,
            'submitted_at': '2026-10-06T13:00:00Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: submittedRequest,
        ),
      );
      expect(await submission, DateTime.utc(2026, 10, 6, 13));
      expect(client.auth.currentUser?.id, _otherUserId);
      await expectLater(
        repository.submitRequest(_request(ownerUserId: _userId)),
        throwsStateError,
      );
    },
  );

  test(
    'foreign or missing server receipts never become submitted requests',
    () async {
      Object? response;
      final client = _client(
        MockClient(
          (request) async => http.Response(
            jsonEncode(response),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          ),
        ),
      );
      addTearDown(client.dispose);
      await _signIn(client);
      final repository = SupabaseGymDirectoryRequestRepository(client);
      for (final invalid in [
        null,
        {
          'id': 'request-test-1',
          'owner_user_id': _otherUserId,
          'submitted_at': '2026-10-06T13:00:00Z',
        },
        {
          'id': 'other-id',
          'owner_user_id': _userId,
          'submitted_at': '2026-10-06T13:00:00Z',
        },
        {
          'id': 'request-test-1',
          'owner_user_id': _userId,
          'submitted_at': 'invalid',
        },
      ]) {
        response = invalid;
        await expectLater(
          repository.submitRequest(_request()),
          throwsFormatException,
        );
      }
    },
  );
}

class _CatalogBundle extends CachingAssetBundle {
  _CatalogBundle(this.gym);

  final GymPlace gym;
  int reads = 0;

  @override
  Future<ByteData> load(String key) => throw UnimplementedError();

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    reads++;
    if (reads == 1) throw StateError('Transient failure');
    return jsonEncode({
      'source': {'label': '제공 목록', 'fileName': 'gyms.xlsx', 'sha256': 'test'},
      'gyms': [gym.toJson()],
    });
  }
}
