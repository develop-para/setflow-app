import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/data/supabase_business_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _memberId = '11111111-1111-4111-8111-111111111111';
const _trainerUserId = '22222222-2222-4222-8222-222222222222';
const _consultationId = '33333333-3333-4333-8333-333333333333';
const _requestId = '44444444-4444-4444-8444-444444444444';

void main() {
  for (final viewer in [_memberId, _trainerUserId]) {
    test(
      'chat sends persisted text without client-chosen sender for $viewer',
      () async {
        final backend = await _ChatBackend.start(viewerId: viewer);
        addTearDown(backend.close);
        final consultation = await backend.repository.sendConsultationMessage(
          const SendConsultationMessageInput(
            consultationId: _consultationId,
            requestId: _requestId,
            text: '  다음 질문이에요  ',
          ),
        );
        expect(backend.sent.single, {
          'consultation_id': _consultationId,
          'request_id': _requestId,
          'text': '다음 질문이에요',
        });
        expect(consultation.messages.single.requestId, _requestId);
        expect(consultation.messages.single.senderId, viewer);
        expect(consultation.messages.single.text, '다음 질문이에요');
        expect(
          consultation.messages.single.sender,
          viewer == _memberId
              ? BusinessMessageSender.member
              : BusinessMessageSender.trainer,
        );
      },
    );
  }

  test(
    'canonical chat read pages message history with tied timestamps',
    () async {
      final backend = await _ChatBackend.start();
      addTearDown(backend.close);
      backend.messages.addAll(List.generate(205, backend.message));
      final consultation = await backend.repository.loadConsultation(
        _consultationId,
      );
      expect(consultation.messages, hasLength(205));
      expect(consultation.latestMessage?.text, '메시지 204');
      expect(backend.messageReads, hasLength(2));
      expect(
        backend.messageReads.first.queryParameters['order'],
        'created_at.asc.nullslast,id.asc.nullslast',
      );
      expect(
        backend.messageReads.last.queryParameters['or'],
        contains('id.gt.'),
      );
      expect(
        backend.messageReads.last.queryParameters['or'],
        contains('created_at.eq.'),
      );
    },
  );

  test(
    'a same-text message without this request cannot acknowledge a send',
    () async {
      final backend = await _ChatBackend.start();
      addTearDown(backend.close);
      backend.persistRequestId = false;
      await expectLater(
        backend.repository.sendConsultationMessage(
          const SendConsultationMessageInput(
            consultationId: _consultationId,
            requestId: _requestId,
            text: '질문',
          ),
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'RLS-hidden conversation and server authorization map to domain denial',
    () async {
      final backend = await _ChatBackend.start();
      addTearDown(backend.close);
      backend.hidden = true;
      await expectLater(
        backend.repository.loadConsultation(_consultationId),
        throwsA(isA<BusinessAccessDenied>()),
      );
      backend.hidden = false;
      backend.sendDenied = true;
      await expectLater(
        backend.repository.sendConsultationMessage(
          const SendConsultationMessageInput(
            consultationId: _consultationId,
            requestId: _requestId,
            text: '질문',
          ),
        ),
        throwsA(isA<BusinessAccessDenied>()),
      );
    },
  );

  test(
    'in-flight canonical read cannot return the previous account conversation',
    () async {
      final backend = await _ChatBackend.start();
      addTearDown(backend.close);
      backend.readGate = Completer<void>();
      final loading = backend.repository.loadConsultation(_consultationId);
      final outcome = expectLater(
        loading,
        throwsA(isA<BusinessAccessDenied>()),
      );
      await backend.readStarted.future;
      await backend.signIn(_trainerUserId);
      backend.readGate!.complete();
      await outcome;
    },
  );

  test(
    'watch receives an initial state and refreshes when the socket is unavailable',
    () async {
      final backend = await _ChatBackend.start();
      addTearDown(backend.close);
      final received = <BusinessConsultation>[];
      final refreshed = Completer<void>();
      final subscription = backend.repository
          .watchConsultation(_consultationId)
          .listen((value) {
            received.add(value);
            if (received.length == 1) {
              backend.messages.add(backend.message(0));
            }
            if (value.messages.isNotEmpty && !refreshed.isCompleted) {
              refreshed.complete();
            }
          });
      addTearDown(subscription.cancel);
      await refreshed.future.timeout(const Duration(seconds: 6));
      expect(received.first.messages, isEmpty);
      expect(received.last.messages.single.text, '메시지 0');
      await subscription.cancel();
      expect(backend.client.getChannels(), isEmpty);
    },
  );

  test(
    'chat validates empty/oversized messages before calling the server',
    () async {
      final backend = await _ChatBackend.start();
      addTearDown(backend.close);
      for (final text in [' ', '가' * 5001]) {
        await expectLater(
          backend.repository.sendConsultationMessage(
            SendConsultationMessageInput(
              consultationId: _consultationId,
              requestId: _requestId,
              text: text,
            ),
          ),
          throwsArgumentError,
        );
      }
      expect(backend.sent, isEmpty);
    },
  );
}

class _ChatBackend {
  _ChatBackend(this.server, this.client, this.viewerId);

  final HttpServer server;
  final SupabaseClient client;
  String viewerId;
  final messages = <Map<String, Object?>>[];
  final sent = <Map<String, Object?>>[];
  final messageReads = <Uri>[];
  bool hidden = false;
  bool sendDenied = false;
  bool persistRequestId = true;
  Completer<void>? readGate;
  final readStarted = Completer<void>();
  SupabaseBusinessRepository get repository =>
      SupabaseBusinessRepository(client);

  static Future<_ChatBackend> start({String viewerId = _memberId}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = SupabaseClient(
      'http://${server.address.host}:${server.port}',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final backend = _ChatBackend(server, client, viewerId);
    server.listen(backend.handle);
    await backend.signIn(viewerId);
    return backend;
  }

  Future<void> signIn(String userId) async {
    viewerId = userId;
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-access-token',
        'refresh_token': 'test-refresh-token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': userId,
          'email': 'viewer@example.test',
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-10-01T00:00:00Z',
        },
      }),
    );
  }

  Map<String, Object?> message(int index) => {
    'id': '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
    'consultation_id': _consultationId,
    'sender_type': 'user',
    'sender_id': _memberId,
    'request_id': null,
    'text': '메시지 $index',
    'created_at': '2026-10-01T01:00:00.000Z',
  };

  Future<void> handle(HttpRequest request) async {
    if (request.uri.path == '/rest/v1/rpc/send_consultation_message') {
      final body = Map<String, Object?>.from(
        jsonDecode(await utf8.decoder.bind(request).join()) as Map,
      );
      sent.add(body);
      if (sendDenied) {
        await write(request, {
          'code': '42501',
          'message': 'Participant access required',
        }, status: 403);
        return;
      }
      messages.add({
        ...message(messages.length),
        'request_id': persistRequestId ? body['request_id'] : null,
        'sender_type': viewerId == _memberId ? 'user' : 'trainer',
        'sender_id': viewerId,
        'text': body['text'],
      });
      await write(request, {
        'consultation_id': _consultationId,
        'message_id': messages.last['id'],
      });
    } else if (request.uri.path == '/rest/v1/consultations') {
      await request.drain<void>();
      if (!readStarted.isCompleted) readStarted.complete();
      await readGate?.future;
      await write(
        request,
        hidden
            ? <Object?>[]
            : {
                'id': _consultationId,
                'user_id': _memberId,
                'status': 'pending',
                'is_read': false,
                'question': '첫 질문',
                'created_at': '2026-10-01T00:00:00Z',
              },
      );
    } else if (request.uri.path == '/rest/v1/consultation_messages') {
      await request.drain<void>();
      messageReads.add(request.uri);
      final filter = request.uri.queryParameters['or'];
      final cursor = filter == null
          ? null
          : RegExp(r'id\.gt\.([0-9a-f-]+)').firstMatch(filter)?.group(1);
      final page = messages
          .where(
            (row) =>
                cursor == null || (row['id']! as String).compareTo(cursor) > 0,
          )
          .take(int.parse(request.uri.queryParameters['limit'] ?? '200'))
          .toList();
      await write(request, page);
    } else {
      await request.drain<void>();
      await write(request, {
        'code': 'PGRST404',
        'message': 'Unknown route',
      }, status: 404);
    }
  }

  Future<void> write(
    HttpRequest request,
    Object? body, {
    int status = 200,
  }) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> close() async {
    await client.dispose();
    await server.close(force: true);
  }
}
