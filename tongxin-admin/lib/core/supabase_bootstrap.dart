import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 管理后台 Supabase 初始化（不使用 Firebase，仅 anon key）
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
      debugPrint('[Admin Supabase] init skipped: missing SUPABASE_URL / SUPABASE_ANON_KEY');
      isReady = false;
      return;
    }
    debugPrint('[Admin Supabase] initializing...');
    try {
      await Supabase.initialize(url: url, anonKey: anonKey);
      isReady = true;
      debugPrint('[Admin Supabase] init OK');
    } catch (error, stack) {
      isReady = false;
      debugPrint('[Admin Supabase] init failed: $error');
      debugPrint('[Admin Supabase] stack: $stack');
    }
  }

  static SupabaseClient get client => Supabase.instance.client;
}
