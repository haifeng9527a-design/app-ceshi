import 'dart:convert';

import '../core/api_client.dart';

/// 用户/鉴权相关 API，通过后端代理，避免前端直连 Supabase
class AuthApi {
  AuthApi._();
  static final AuthApi instance = AuthApi._();
  final _api = ApiClient.instance;

  /// 登录后同步 Firebase 用户到 user_profiles（uid 由后端从 Token 解析）
  Future<bool> syncProfile({
    String? displayName,
    String? email,
    String? avatarUrl,
  }) async {
    if (!_api.isAvailable) return false;
    final resp = await _api.post('api/auth/profile/sync', body: {
      'display_name': displayName,
      'email': email,
      'avatar_url': avatarUrl,
    });
    return resp.statusCode == 200;
  }

  /// 确保 short_id，由后端生成
  Future<String?> ensureShortId() async {
    if (!_api.isAvailable) return null;
    final resp = await _api.post('api/auth/profile/short-id');
    if (resp.statusCode != 200) return null;
    try {
      final json = jsonDecode(resp.body) as Map<String, dynamic>?;
      return json?['short_id'] as String?;
    } catch (_) {
      return null;
    }
  }
}
