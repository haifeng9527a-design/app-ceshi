import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/supabase_bootstrap.dart';

class SupabaseUserSync {
  Future<void> upsertFromFirebase(User user) async {
    final name = user.displayName?.trim();
    final email = user.email?.trim();
    final data = <String, dynamic>{
      'user_id': user.uid,
      'display_name': name?.isEmpty == true ? null : name,
      'email': email?.isEmpty == true ? null : email,
      'updated_at': DateTime.now().toIso8601String(),
    };
    final photo = user.photoURL?.trim();
    if (photo != null && photo.isNotEmpty) {
      data['avatar_url'] = photo;
    }
    await SupabaseBootstrap.client.from('user_profiles').upsert(data);
    await ensureShortId(user.uid);
  }

  Future<void> ensureShortId(String userId) async {
    if (!SupabaseBootstrap.isReady) {
      return;
    }
    final existing = await SupabaseBootstrap.client
        .from('user_profiles')
        .select('short_id')
        .eq('user_id', userId)
        .maybeSingle();
    final shortId = existing?['short_id'] as String?;
    if (shortId != null && shortId.trim().isNotEmpty) {
      return;
    }
    for (var i = 0; i < 10; i += 1) {
      final candidate = _generateShortId();
      try {
        await SupabaseBootstrap.client.from('user_profiles').update({
          'short_id': candidate,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('user_id', userId).isFilter('short_id', null);
        final confirmed = await SupabaseBootstrap.client
            .from('user_profiles')
            .select('short_id')
            .eq('user_id', userId)
            .maybeSingle();
        final updated = confirmed?['short_id'] as String?;
        if (updated != null && updated.trim().isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('profile.shortId.$userId', updated.trim());
          return;
        }
      } catch (_) {
        // Likely unique conflict, retry.
      }
    }
  }

  String _generateShortId() {
    final random = Random();
    final length = 6 + random.nextInt(4); // 6-9
    final buffer = StringBuffer();
    for (var i = 0; i < length; i += 1) {
      final digit = i == 0 ? 1 + random.nextInt(9) : random.nextInt(10);
      buffer.write(digit);
    }
    return buffer.toString();
  }
}
