import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class AdminApiClient {
  AdminApiClient._();
  static final AdminApiClient instance = AdminApiClient._();
  String? _sessionToken;

  String? get _baseUrl {
    final v = dotenv.env['TONGXIN_API_URL']?.trim();
    if (v == null || v.isEmpty) return null;
    return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
  }

  String? get _adminApiKey {
    final v = dotenv.env['ADMIN_API_KEY']?.trim();
    if (v == null || v.isEmpty) return null;
    return v;
  }

  bool get isAvailable => _baseUrl != null;
  bool get hasBootstrapKey => _adminApiKey != null;
  bool get hasSession => _sessionToken != null && _sessionToken!.trim().isNotEmpty;

  void setSessionToken(String token) {
    final trimmed = token.trim();
    _sessionToken = trimmed.isEmpty ? null : trimmed;
  }

  void clearSessionToken() {
    _sessionToken = null;
  }

  Uri _uri(String path) {
    final base = _baseUrl;
    if (base == null) {
      throw StateError('缺少 TONGXIN_API_URL');
    }
    final safePath = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$base/$safePath');
  }

  Map<String, String> _headers({bool includeAdminKey = false}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (hasSession) {
      headers['x-admin-session'] = _sessionToken!;
    }
    if (includeAdminKey) {
      final key = _adminApiKey;
      if (key == null) {
        throw StateError('缺少 ADMIN_API_KEY');
      }
      headers['x-admin-key'] = key;
    }
    return headers;
  }

  Future<http.Response> get(String path) {
    return http.get(_uri(path), headers: _headers());
  }

  Future<http.Response> post(String path, {Object? body}) {
    return http.post(_uri(path), headers: _headers(), body: jsonEncode(body ?? const {}));
  }

  Future<http.Response> postWithAdminKey(String path, {Object? body}) {
    return http.post(
      _uri(path),
      headers: _headers(includeAdminKey: true),
      body: jsonEncode(body ?? const {}),
    );
  }

  Future<http.Response> patch(String path, {Object? body}) {
    return http.patch(_uri(path), headers: _headers(), body: jsonEncode(body ?? const {}));
  }

  Future<http.Response> put(String path, {Object? body}) {
    return http.put(_uri(path), headers: _headers(), body: jsonEncode(body ?? const {}));
  }

  Future<http.Response> delete(String path) {
    return http.delete(_uri(path), headers: _headers());
  }
}
