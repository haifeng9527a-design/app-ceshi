import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/auth_api.dart';
import '../../core/api_client.dart';
import 'customer_service_repository.dart';
import 'friends_repository.dart';

class SupabaseUserSync {
  Future<void> upsertFromFirebase(User user) async {
    final name = user.displayName?.trim();
    final email = user.email?.trim();
    final photo = user.photoURL?.trim();

    if (ApiClient.instance.isAvailable) {
      try {
        final ok = await AuthApi.instance.syncProfile(
          displayName: name?.isEmpty == true ? null : name,
          email: email?.isEmpty == true ? null : email,
          avatarUrl: photo?.isEmpty == true ? null : photo,
        );
        if (ok) {
          final shortId = await AuthApi.instance.ensureShortId();
          if (shortId != null && shortId.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('profile.shortId.${user.uid}', shortId.trim());
          }
          await _ensureCustomerServiceFriend(user.uid);
        }
      } catch (_) {}
      return;
    }
  }

  /// 确保用户已添加系统客服为好友（注册用户均有）
  Future<void> _ensureCustomerServiceFriend(String userId) async {
    if (userId.isEmpty) return;
    try {
      final csId = await CustomerServiceRepository().getSystemCustomerServiceUserId();
      if (csId == null || csId.isEmpty || csId == userId) return;
      await FriendsRepository().ensureCustomerServiceFriend(
        userId: userId,
        customerServiceId: csId,
      );
    } catch (_) {
      // 静默失败，不阻塞登录
    }
  }

  Future<void> ensureShortId(String userId) async {
    if (!ApiClient.instance.isAvailable) return;
    final shortId = await AuthApi.instance.ensureShortId();
    if (shortId != null && shortId.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profile.shortId.$userId', shortId.trim());
    }
  }
}
