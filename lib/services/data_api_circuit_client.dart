import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Stops a Data API outage from becoming a request storm.
///
/// Supabase's client retries GET/HEAD requests by default. Setflow disables
/// those retries and uses this shared circuit instead: the first 503/520 opens
/// a short cooldown, and every following `/rest/v1` operation fails locally.
/// Auth, Storage and Realtime use different paths and remain unaffected.
class DataApiCircuitClient extends http.BaseClient {
  DataApiCircuitClient({
    http.Client? inner,
    DateTime Function()? now,
    this.initialCooldown = const Duration(seconds: 15),
    this.maximumCooldown = const Duration(minutes: 5),
    this.requestTimeout = const Duration(seconds: 8),
  }) : _inner = inner ?? http.Client(),
       _now = now ?? DateTime.now;

  final http.Client _inner;
  final DateTime Function() _now;
  final Duration initialCooldown;
  final Duration maximumCooldown;
  final Duration requestTimeout;

  DateTime? _blockedUntil;
  int _consecutiveFailures = 0;

  bool get isOpen {
    final blockedUntil = _blockedUntil;
    return blockedUntil != null && _now().isBefore(blockedUntil);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!_isDataApiRequest(request.url)) return _inner.send(request);
    if (isOpen) return _unavailableResponse(request);

    try {
      final response = await _inner.send(request).timeout(requestTimeout);
      if (response.statusCode == 503 || response.statusCode == 520) {
        _open();
      } else if (response.statusCode < 500) {
        _reset();
      }
      return response;
    } on TimeoutException {
      _open();
      rethrow;
    } on http.ClientException {
      _open();
      rethrow;
    }
  }

  bool _isDataApiRequest(Uri uri) =>
      uri.path == '/rest/v1' || uri.path.startsWith('/rest/v1/');

  void _open() {
    _consecutiveFailures++;
    final multiplier = 1 << (_consecutiveFailures - 1).clamp(0, 5);
    final proposed = Duration(
      milliseconds: initialCooldown.inMilliseconds * multiplier,
    );
    final cooldown = proposed > maximumCooldown ? maximumCooldown : proposed;
    _blockedUntil = _now().add(cooldown);
  }

  void _reset() {
    _consecutiveFailures = 0;
    _blockedUntil = null;
  }

  http.StreamedResponse _unavailableResponse(http.BaseRequest request) {
    final body = utf8.encode(
      jsonEncode({
        'code': 'PGRST002',
        'details': null,
        'hint': null,
        'message': 'Data API is temporarily unavailable. Using cached data.',
      }),
    );
    return http.StreamedResponse(
      Stream<List<int>>.value(body),
      503,
      contentLength: body.length,
      headers: const {'content-type': 'application/json; charset=utf-8'},
      reasonPhrase: 'Service Unavailable',
      request: request,
    );
  }

  @override
  void close() => _inner.close();
}
