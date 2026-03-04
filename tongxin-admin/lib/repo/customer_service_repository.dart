import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_bootstrap.dart';

class CustomerServiceRepository {
  CustomerServiceRepository({SupabaseClient? client})
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  Future<String?> getSystemCustomerServiceUserId() async {
    try {
      final row = await _client
          .from('app_config')
          .select('value')
          .eq('key', 'customer_service_user_id')
          .maybeSingle();
      final v = row?['value']?.toString()?.trim();
      return v != null && v.isNotEmpty ? v : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> getCustomerServiceWelcomeMessage() async {
    try {
      final row = await _client
          .from('app_config')
          .select('value')
          .eq('key', 'customer_service_welcome_message')
          .maybeSingle();
      final v = row?['value']?.toString()?.trim();
      return v != null && v.isNotEmpty ? v : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> setCustomerServiceWelcomeMessage(String? message) async {
    final value = message?.trim().isEmpty == true ? null : message?.trim();
    await _client.from('app_config').upsert({
      'key': 'customer_service_welcome_message',
      'value': value,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'key');
  }

  Future<String?> getCustomerServiceAvatarUrl() async {
    try {
      final row = await _client
          .from('app_config')
          .select('value')
          .eq('key', 'customer_service_avatar_url')
          .maybeSingle();
      return row?['value']?.toString()?.trim();
    } catch (_) {
      return null;
    }
  }

  Future<void> setSystemCustomerServiceUserId(String userId) async {
    await _client.from('app_config').upsert({
      'key': 'customer_service_user_id',
      'value': userId.trim().isEmpty ? null : userId.trim(),
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'key');
  }

  Future<void> setCustomerServiceAvatarUrl(String? url) async {
    final value = url?.trim().isEmpty == true ? null : url?.trim();
    await _client.from('app_config').upsert({
      'key': 'customer_service_avatar_url',
      'value': value,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'key');
    final csId = await getSystemCustomerServiceUserId();
    if (csId != null && csId.isNotEmpty && value != null && value.isNotEmpty) {
      await _client.from('user_profiles').update({
        'avatar_url': value,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('user_id', csId);
    }
  }

  Future<void> setUserRole(String userId, String role) async {
    await _client.from('user_profiles').update({
      'role': role,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('user_id', userId);
  }

  Future<Map<String, dynamic>> broadcastMessage(String message) async {
    try {
      final res = await _client.rpc(
        'broadcast_customer_service_message',
        params: {'msg': message.trim()},
      );
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      return {'ok': false, 'error': e.toString(), 'count': 0};
    }
  }
}
