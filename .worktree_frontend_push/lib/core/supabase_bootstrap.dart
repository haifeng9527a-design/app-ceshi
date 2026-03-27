import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_bootstrap.dart';

class SupabaseBootstrap {
  static bool isReady = false;

  static Future<void> init() async {
    final envUrl = dotenv.env['SUPABASE_URL'];
    final envAnonKey = dotenv.env['SUPABASE_ANON_KEY'];
    final url = (envUrl != null && envUrl.isNotEmpty)
        ? envUrl
        : const String.fromEnvironment('SUPABASE_URL');
    final anonKey = (envAnonKey != null && envAnonKey.isNotEmpty)
        ? envAnonKey
        : const String.fromEnvironment('SUPABASE_ANON_KEY');
    if (url.isEmpty || anonKey.isEmpty) {
      debugPrint('[Supabase] init skipped: missing SUPABASE_URL / SUPABASE_ANON_KEY');
      isReady = false;
      return;
    }
    debugPrint('[Supabase] URL present, anonKey present, initializing...');
    try {
      // 使用 Firebase ID Token 作为 Supabase 请求鉴权，使 RLS 中 auth.uid() 与 Firebase UID 一致。
      // 需在 Supabase 控制台配置 Firebase 第三方登录，并为 Firebase 用户设置 role: authenticated。
      // macOS 等平台可能未配置 Firebase，accessToken 仅在 Firebase 就绪时调用，否则返回 null 避免 [core/no-app] 崩溃。
      await Supabase.initialize(
        url: url,
        anonKey: anonKey,
        accessToken: () async {
          if (!FirebaseBootstrap.isReady) return null;
          try {
            return await FirebaseAuth.instance.currentUser?.getIdToken() ?? null;
          } catch (_) {
            // 后台等未登录 Firebase 时返回 null，请求以 anon 发送，避免 FirebaseException 导致 Web 端 TypeError
            return null;
          }
        },
      );
      isReady = true;
      debugPrint('[Supabase] init OK');
    } catch (error, stack) {
      isReady = false;
      debugPrint('[Supabase] init failed: $error');
      debugPrint('[Supabase] stack: $stack');
    }
  }

  static SupabaseClient get client {
    if (!isReady) {
      throw StateError(
        'Supabase 未配置：已迁移至后端代理，请配置 TONGXIN_API_URL 并确保后端运行',
      );
    }
    return Supabase.instance.client;
  }

  /// 未配置时返回 null，供 Repository 安全降级（返回空数据）
  static SupabaseClient? get clientOrNull =>
      isReady ? Supabase.instance.client : null;
}
