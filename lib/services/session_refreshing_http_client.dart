import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'auth_service.dart';

class SessionRefreshingHttpClient extends http.BaseClient {
  SessionRefreshingHttpClient(this._inner, this._authService);

  final http.Client _inner;
  final AuthService _authService;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bodyBytes = await request.finalize().toBytes();
    final originalToken = _authorizationToken(request.headers);
    final firstRequest = _copyRequest(request, bodyBytes: bodyBytes);
    final firstResponse = _attachRequest(
      await _inner.send(firstRequest),
      firstRequest,
    );
    if (firstResponse.statusCode != 401 || originalToken == null) {
      return firstResponse;
    }

    final responseBytes = await firstResponse.stream.toBytes();
    if (!_requiresTrustedSessionRefresh(responseBytes)) {
      return _restoreResponse(firstResponse, responseBytes);
    }

    var currentToken = await _authService.token();
    if (currentToken == null ||
        AuthService.identicalSessionToken(currentToken, originalToken)) {
      final refreshed = await _authService.refreshTrustedDeviceSession();
      if (!refreshed) {
        return _restoreResponse(firstResponse, responseBytes);
      }
      currentToken = await _authService.token();
    }
    if (currentToken == null || currentToken.trim().isEmpty) {
      return _restoreResponse(firstResponse, responseBytes);
    }

    final retryRequest = _copyRequest(
      request,
      bodyBytes: bodyBytes,
      authorizationToken: currentToken,
    );
    return _attachRequest(await _inner.send(retryRequest), retryRequest);
  }

  http.Request _copyRequest(
    http.BaseRequest source, {
    required Uint8List bodyBytes,
    String? authorizationToken,
  }) {
    final copy = http.Request(source.method, source.url)
      ..followRedirects = source.followRedirects
      ..maxRedirects = source.maxRedirects
      ..persistentConnection = source.persistentConnection
      ..headers.addAll(source.headers)
      ..bodyBytes = bodyBytes;
    if (authorizationToken != null) {
      copy.headers['Authorization'] = 'Bearer ${authorizationToken.trim()}';
    }
    return copy;
  }

  http.StreamedResponse _restoreResponse(
    http.StreamedResponse source,
    Uint8List bytes,
  ) {
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      source.statusCode,
      contentLength: bytes.length,
      request: source.request,
      headers: source.headers,
      isRedirect: source.isRedirect,
      persistentConnection: source.persistentConnection,
      reasonPhrase: source.reasonPhrase,
    );
  }

  http.StreamedResponse _attachRequest(
    http.StreamedResponse source,
    http.BaseRequest request,
  ) {
    return http.StreamedResponse(
      source.stream,
      source.statusCode,
      contentLength: source.contentLength,
      request: source.request ?? request,
      headers: source.headers,
      isRedirect: source.isRedirect,
      persistentConnection: source.persistentConnection,
      reasonPhrase: source.reasonPhrase,
    );
  }

  bool _requiresTrustedSessionRefresh(Uint8List bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      return decoded is Map && decoded['deviceSessionRefreshRequired'] == true;
    } catch (_) {
      return false;
    }
  }

  String? _authorizationToken(Map<String, String> headers) {
    String authorization = '';
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'authorization') {
        authorization = entry.value.trim();
        break;
      }
    }
    const prefix = 'Bearer ';
    return authorization.startsWith(prefix)
        ? authorization.substring(prefix.length).trim()
        : null;
  }
}
