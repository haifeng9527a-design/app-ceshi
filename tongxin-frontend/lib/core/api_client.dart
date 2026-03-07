import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'firebase_bootstrap.dart';

/// 统一 API 客户端：请求 tongxin-backend，自动附加 Firebase Token
/// 所有数据操作应通过此后端代理，避免前端直连 Supabase 暴露数据库
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();
  static const int _networkErrorStatusCode = 599;

  String? get _baseUrl {
    final url = dotenv.env['TONGXIN_API_URL']?.trim();
    if (url != null && url.isNotEmpty) return url.endsWith('/') ? url : '$url/';
    return null;
  }

  bool get isAvailable => _baseUrl != null;

  void _logRequest(String method, Uri uri, {Object? body}) {
    if (kDebugMode) {
      debugPrint('[ApiClient] $method ${uri.toString()}');
      if (uri.queryParameters.isNotEmpty) {
        debugPrint('[ApiClient] query: ${uri.queryParameters}');
      }
      if (body != null) {
        final str = body is String ? body : jsonEncode(body);
        debugPrint('[ApiClient] body: ${str.length > 500 ? '${str.substring(0, 500)}...' : str}');
      }
    }
  }

  void _logDuration(String method, String path, Duration duration, int statusCode) {
    if (kDebugMode) {
      debugPrint('[ApiClient] $method $path → ${statusCode} (${duration.inMilliseconds}ms)');
    }
  }

  /// [forceRefresh] 为 true 时强制刷新 Token，用于 401 重试
  Future<Map<String, String>> _headers({bool withAuth = true, bool forceRefresh = false}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (withAuth && FirebaseBootstrap.isReady) {
      try {
        final token = await FirebaseAuth.instance.currentUser?.getIdToken(forceRefresh);
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        } else if (kDebugMode) {
          debugPrint('[ApiClient] 未获取到 Token，currentUser=${FirebaseAuth.instance.currentUser?.uid}');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[ApiClient] getIdToken 失败: $e');
      }
    }
    return headers;
  }

  Future<http.Response> get(
    String path, {
    Map<String, String>? queryParameters,
    bool withAuth = true,
    Duration? timeout,
  }) async {
    final base = _baseUrl;
    if (base == null) {
      return http.Response('{"error":"TONGXIN_API_URL not configured"}', 503);
    }
    var uri = Uri.parse('$base$path');
    if (queryParameters != null && queryParameters.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParameters);
    }
    _logRequest('GET', uri);
    try {
      var resp = await http
          .get(uri, headers: await _headers(withAuth: withAuth))
          .timeout(timeout ?? const Duration(seconds: 15));
      // 401 时尝试强制刷新 Token 并重试一次
      if (resp.statusCode == 401 && withAuth && FirebaseBootstrap.isReady) {
        resp = await http
            .get(uri, headers: await _headers(withAuth: true, forceRefresh: true))
            .timeout(timeout ?? const Duration(seconds: 15));
      }
      return resp;
    } catch (e) {
      if (kDebugMode) debugPrint('[ApiClient GET $path] $e');
      return http.Response('{"error":"${e.toString()}"}', _networkErrorStatusCode);
    }
  }

  Future<http.Response> post(
    String path, {
    Object? body,
    bool withAuth = true,
    Duration? timeout,
  }) async {
    final base = _baseUrl;
    if (base == null) {
      return http.Response('{"error":"TONGXIN_API_URL not configured"}', 503);
    }
    final uri = Uri.parse('$base$path');
    _logRequest('POST', uri, body: body);
    try {
      final stopwatch = Stopwatch()..start();
      var resp = await http
          .post(
            uri,
            headers: await _headers(withAuth: withAuth),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeout ?? const Duration(seconds: 15));
      if (resp.statusCode == 401 && withAuth && FirebaseBootstrap.isReady) {
        resp = await http
            .post(
              uri,
              headers: await _headers(withAuth: true, forceRefresh: true),
              body: body != null ? jsonEncode(body) : null,
            )
            .timeout(timeout ?? const Duration(seconds: 15));
      }
      stopwatch.stop();
      _logDuration('POST', path, stopwatch.elapsed, resp.statusCode);
      return resp;
    } catch (e) {
      if (kDebugMode) debugPrint('[ApiClient POST $path] $e');
      return http.Response('{"error":"${e.toString()}"}', _networkErrorStatusCode);
    }
  }

  Future<http.Response> put(
    String path, {
    Object? body,
    bool withAuth = true,
    Duration? timeout,
  }) async {
    final base = _baseUrl;
    if (base == null) {
      return http.Response('{"error":"TONGXIN_API_URL not configured"}', 503);
    }
    final uri = Uri.parse('$base$path');
    _logRequest('PUT', uri, body: body);
    try {
      final stopwatch = Stopwatch()..start();
      var resp = await http
          .put(
            uri,
            headers: await _headers(withAuth: withAuth),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeout ?? const Duration(seconds: 15));
      if (resp.statusCode == 401 && withAuth && FirebaseBootstrap.isReady) {
        resp = await http
            .put(
              uri,
              headers: await _headers(withAuth: true, forceRefresh: true),
              body: body != null ? jsonEncode(body) : null,
            )
            .timeout(timeout ?? const Duration(seconds: 15));
      }
      stopwatch.stop();
      _logDuration('PUT', path, stopwatch.elapsed, resp.statusCode);
      return resp;
    } catch (e) {
      if (kDebugMode) debugPrint('[ApiClient PUT $path] $e');
      return http.Response('{"error":"${e.toString()}"}', _networkErrorStatusCode);
    }
  }

  Future<http.Response> patch(
    String path, {
    Object? body,
    bool withAuth = true,
    Duration? timeout,
  }) async {
    final base = _baseUrl;
    if (base == null) {
      return http.Response('{"error":"TONGXIN_API_URL not configured"}', 503);
    }
    final uri = Uri.parse('$base$path');
    _logRequest('PATCH', uri, body: body);
    try {
      final stopwatch = Stopwatch()..start();
      var resp = await http
          .patch(
            uri,
            headers: await _headers(withAuth: withAuth),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeout ?? const Duration(seconds: 15));
      if (resp.statusCode == 401 && withAuth && FirebaseBootstrap.isReady) {
        resp = await http
            .patch(
              uri,
              headers: await _headers(withAuth: true, forceRefresh: true),
              body: body != null ? jsonEncode(body) : null,
            )
            .timeout(timeout ?? const Duration(seconds: 15));
      }
      stopwatch.stop();
      _logDuration('PATCH', path, stopwatch.elapsed, resp.statusCode);
      return resp;
    } catch (e) {
      if (kDebugMode) debugPrint('[ApiClient PATCH $path] $e');
      return http.Response('{"error":"${e.toString()}"}', _networkErrorStatusCode);
    }
  }

  Future<http.Response> delete(
    String path, {
    bool withAuth = true,
    Duration? timeout,
  }) async {
    final base = _baseUrl;
    if (base == null) {
      return http.Response('{"error":"TONGXIN_API_URL not configured"}', 503);
    }
    final uri = Uri.parse('$base$path');
    _logRequest('DELETE', uri);
    try {
      final stopwatch = Stopwatch()..start();
      var resp = await http
          .delete(uri, headers: await _headers(withAuth: withAuth))
          .timeout(timeout ?? const Duration(seconds: 15));
      if (resp.statusCode == 401 && withAuth && FirebaseBootstrap.isReady) {
        resp = await http
            .delete(uri, headers: await _headers(withAuth: true, forceRefresh: true))
            .timeout(timeout ?? const Duration(seconds: 15));
      }
      stopwatch.stop();
      _logDuration('DELETE', path, stopwatch.elapsed, resp.statusCode);
      return resp;
    } catch (e) {
      if (kDebugMode) debugPrint('[ApiClient DELETE $path] $e');
      return http.Response('{"error":"${e.toString()}"}', _networkErrorStatusCode);
    }
  }

  /// 上传二进制文件（multipart/form-data）
  Future<http.Response> upload(
    String path, {
    required List<int> bytes,
    required String fileName,
    String fieldName = 'file',
    Map<String, String>? extraFields,
    bool withAuth = true,
    Duration? timeout,
  }) async {
    final base = _baseUrl;
    if (base == null) {
      return http.Response('{"error":"TONGXIN_API_URL not configured"}', 503);
    }
    final uri = Uri.parse('$base$path');
    _logRequest('UPLOAD', uri, body: {'file': fileName, ...?extraFields});
    try {
      final stopwatch = Stopwatch()..start();
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await _headers(withAuth: withAuth));
      request.files.add(http.MultipartFile.fromBytes(
        fieldName,
        bytes,
        filename: fileName,
      ));
      if (extraFields != null) {
        request.fields.addAll(extraFields);
      }
      final streamed = await request.send().timeout(
            timeout ?? const Duration(seconds: 30),
          );
      final resp = await http.Response.fromStream(streamed);
      stopwatch.stop();
      _logDuration('UPLOAD', path, stopwatch.elapsed, resp.statusCode);
      return resp;
    } catch (e) {
      if (kDebugMode) debugPrint('[ApiClient UPLOAD $path] $e');
      return http.Response('{"error":"${e.toString()}"}', _networkErrorStatusCode);
    }
  }
}
