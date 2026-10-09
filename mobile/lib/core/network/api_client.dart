import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../constants/api_config.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';

class ApiClient {
  ApiClient({required TokenStorage tokenStorage, http.Client? httpClient})
      : _tokenStorage = tokenStorage,
        _http = httpClient ?? http.Client();

  final TokenStorage _tokenStorage;
  final http.Client _http;

  /// Called when an authenticated request returns 401.
  /// Login failures do not trigger this.
  Future<void> Function()? onUnauthorized;

  Future<dynamic> get(String path) => _send('GET', path);

  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) {
    return _send('POST', path, body: body, authenticated: authenticated);
  }

  Future<dynamic> put(String path, {Map<String, dynamic>? body}) {
    return _send('PUT', path, body: body);
  }

  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };

    if (authenticated) {
      final token = await _tokenStorage.readToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    late http.Response response;
    try {
      final encodedBody = body == null ? null : jsonEncode(body);
      switch (method) {
        case 'GET':
          response = await _http
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 20));
        case 'POST':
          response = await _http
              .post(uri, headers: headers, body: encodedBody)
              .timeout(const Duration(seconds: 20));
        case 'PUT':
          response = await _http
              .put(uri, headers: headers, body: encodedBody)
              .timeout(const Duration(seconds: 20));
        case 'DELETE':
          response = await _http
              .delete(uri, headers: headers)
              .timeout(const Duration(seconds: 20));
        default:
          throw ApiException(0, 'Unsupported request');
      }
    } on SocketException {
      throw ApiException(
        0,
        'Cannot reach the server. Check that the API is running and the base URL is correct.',
      );
    } on TimeoutException {
      throw ApiException(0, 'The server took too long to respond.');
    }

    return _decode(response, authenticated: authenticated);
  }

  Future<dynamic> _decode(
    http.Response response, {
    required bool authenticated,
  }) async {
    Map<String, dynamic>? body;
    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          body = decoded;
        }
      } catch (_) {
        throw ApiException(response.statusCode, 'Unexpected server response');
      }
    }

    final message = body?['message'] is String
        ? body!['message'] as String
        : 'Request failed';

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (body != null && body['success'] == false) {
        throw ApiException(response.statusCode, message);
      }
      return body?['data'];
    }

    if (response.statusCode == 401 && authenticated) {
      await onUnauthorized?.call();
    }

    throw ApiException(response.statusCode, message);
  }
}
