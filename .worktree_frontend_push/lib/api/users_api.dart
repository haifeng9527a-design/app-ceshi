import 'dart:convert';

import '../core/api_client.dart';

/// 用户相关 API（profile、restrictions、last-online、device-tokens）
class UsersApi {
  UsersApi._();
  static final UsersApi instance = UsersApi._();
  final _api = ApiClient.instance;

  /// GET /api/users/:userId/profile
  Future<Map<String, dynamic>?> getProfile(String userId) async {
    if (!_api.isAvailable) return null;
    final resp = await _api.get('api/users/$userId/profile');
    if (resp.statusCode != 200) return null;
    try {
      final json = jsonDecode(resp.body);
      if (json == null) return null;
      return Map<String, dynamic>.from(json as Map);
    } catch (_) {
      return null;
    }
  }

  /// PATCH /api/users/me — 更新当前用户
  Future<bool> updateMe(Map<String, dynamic> updates) async {
    if (!_api.isAvailable) return false;
    final resp = await _api.patch('api/users/me', body: updates);
    return resp.statusCode == 200;
  }

  /// GET /api/users/me/restrictions
  Future<Map<String, dynamic>?> getMyRestrictions() async {
    if (!_api.isAvailable) return null;
    final resp = await _api.get('api/users/me/restrictions');
    if (resp.statusCode != 200) return null;
    try {
      final json = jsonDecode(resp.body);
      return json != null ? Map<String, dynamic>.from(json as Map) : null;
    } catch (_) {
      return null;
    }
  }

  /// PATCH /api/users/me/last-online
  Future<void> updateLastOnline() async {
    if (!_api.isAvailable) return;
    await _api.patch('api/users/me/last-online');
  }

  /// POST /api/device-tokens
  Future<void> saveDeviceToken({required String token, required String platform}) async {
    if (!_api.isAvailable) return;
    await _api.post('api/device-tokens', body: {'token': token, 'platform': platform});
  }

  /// GET /api/user-profiles/batch
  Future<Map<String, Map<String, String?>>> getProfilesBatch(List<String> userIds) async {
    if (!_api.isAvailable || userIds.isEmpty) return {};
    final ids = userIds.join(',');
    final resp = await _api.get('api/user-profiles/batch', queryParameters: {'ids': ids});
    if (resp.statusCode != 200) return {};
    try {
      final json = jsonDecode(resp.body) as Map? ?? {};
      return json.map((k, v) => MapEntry(k.toString(), Map<String, String?>.from((v as Map).map((kk, vv) => MapEntry(kk.toString(), vv?.toString())))));
    } catch (_) {
      return {};
    }
  }

  /// POST /api/upload/avatar — 上传头像，返回新 URL
  Future<String?> uploadAvatar({
    required String contentBase64,
    String? contentType,
    String? fileName,
  }) async {
    if (!_api.isAvailable) return null;
    final body = <String, dynamic>{
      'content_base64': contentBase64,
      if (contentType != null) 'content_type': contentType,
      if (fileName != null) 'file_name': fileName,
    };
    final resp = await _api.post('api/upload/avatar', body: body);
    if (resp.statusCode != 200) return null;
    try {
      final json = jsonDecode(resp.body) as Map?;
      return json?['url'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// GET /api/user-profiles/:userId/display-name
  Future<String> getDisplayName(String userId) async {
    if (!_api.isAvailable) return '用户';
    final resp = await _api.get('api/user-profiles/$userId/display-name');
    if (resp.statusCode != 200) return '用户';
    try {
      final json = jsonDecode(resp.body) as Map?;
      return json?['display_name'] as String? ?? '用户';
    } catch (_) {
      return '用户';
    }
  }
}
