import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_bootstrap.dart';
import 'supabase_bootstrap.dart';

/// 最后上线时间：在用户退出 APP（后台、关闭应用、关闭聊天窗口）时更新，
/// 供所有好友在聊天窗口查看。
class LastOnlineService {
  /// 将当前用户的「最后上线时间」设为当前时间。
  /// 在 App 进入后台、非活跃、关闭，或用户离开聊天页时调用。
  static Future<void> updateLastOnlineNow() async {
    if (!SupabaseBootstrap.isReady || !FirebaseBootstrap.isReady) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    try {
      await SupabaseBootstrap.client.from('user_profiles').update({
        'last_online_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', uid);
    } catch (_) {
      // 静默失败，不打扰用户
    }
  }
}
