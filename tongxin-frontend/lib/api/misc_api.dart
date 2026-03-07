import 'dart:convert';

import '../core/api_client.dart';

/// 杂项 API：config、call-invitations
class MiscApi {
  MiscApi._();
  static final MiscApi instance = MiscApi._();
  final _api = ApiClient.instance;

  /// GET /api/config/:key
  Future<String?> getConfig(String key) async {
    if (!_api.isAvailable || key.isEmpty) return null;
    final resp = await _api.get('api/config/$key');
    if (resp.statusCode != 200) return null;
    try {
      final json = jsonDecode(resp.body) as Map?;
      final v = json?['value']?.toString().trim();
      return v != null && v.isNotEmpty ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// PATCH /api/config/:key
  Future<void> setConfig(String key, String? value) async {
    if (!_api.isAvailable || key.isEmpty) return;
    await _api.patch('api/config/$key', body: {'value': value});
  }

  /// PATCH /api/users/:userId/role
  Future<void> setUserRole(String userId, String role) async {
    if (!_api.isAvailable) return;
    await _api.patch('api/users/$userId/role', body: {'role': role});
  }

  /// GET /api/users/:userId/is-customer-service
  Future<bool> isCustomerServiceStaff(String userId) async {
    if (!_api.isAvailable || userId.isEmpty) return false;
    final resp = await _api.get('api/users/$userId/is-customer-service');
    if (resp.statusCode != 200) return false;
    try {
      final json = jsonDecode(resp.body) as Map?;
      return json?['is_customer_service'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  /// GET /api/customer-service/online-staff
  Future<List<String>> getOnlineCustomerServiceStaff() async {
    if (!_api.isAvailable) return [];
    final resp = await _api.get('api/customer-service/online-staff');
    if (resp.statusCode != 200) return [];
    try {
      final list = jsonDecode(resp.body) as List? ?? [];
      return list.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  /// GET /api/customer-service/all-staff
  Future<List<String>> getAllCustomerServiceStaff() async {
    if (!_api.isAvailable) return [];
    final resp = await _api.get('api/customer-service/all-staff');
    if (resp.statusCode != 200) return [];
    try {
      final list = jsonDecode(resp.body) as List? ?? [];
      return list.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  /// GET /api/customer-service/assignments/:userId
  Future<String?> getAssignedStaff(String userId) async {
    if (!_api.isAvailable || userId.isEmpty) return null;
    final resp = await _api.get('api/customer-service/assignments/$userId');
    if (resp.statusCode != 200) return null;
    try {
      final json = jsonDecode(resp.body) as Map?;
      return json?['staff_id']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// PUT /api/customer-service/assignments
  Future<void> assignUserToStaff({required String userId, required String staffId}) async {
    if (!_api.isAvailable) return;
    await _api.put('api/customer-service/assignments', body: {'user_id': userId, 'staff_id': staffId});
  }

  /// GET /api/customer-service/conversations
  Future<List<Map<String, dynamic>>> getConversationsWithSystemCs() async {
    if (!_api.isAvailable) return [];
    final resp = await _api.get('api/customer-service/conversations');
    if (resp.statusCode != 200) return [];
    try {
      final list = jsonDecode(resp.body) as List? ?? [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  /// POST /api/customer-service/welcome-message
  Future<void> trySendWelcomeMessage({required String conversationId, required String peerId}) async {
    if (!_api.isAvailable) return;
    await _api.post('api/customer-service/welcome-message', body: {'conversation_id': conversationId, 'peer_id': peerId});
  }

  /// POST /api/customer-service/broadcast
  Future<Map<String, dynamic>> broadcastMessage(String message) async {
    if (!_api.isAvailable) return {'ok': false, 'error': 'API 未配置', 'count': 0};
    final resp = await _api.post('api/customer-service/broadcast', body: {'message': message});
    if (resp.statusCode != 200) return {'ok': false, 'error': resp.body, 'count': 0};
    try {
      return Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
    } catch (_) {
      return {'ok': false, 'error': 'parse error', 'count': 0};
    }
  }

  /// POST /api/customer-service/assign-or-get
  Future<String?> assignOrGetStaffForUser(String userId) async {
    if (!_api.isAvailable || userId.isEmpty) return null;
    final resp = await _api.post('api/customer-service/assign-or-get', body: {'user_id': userId});
    if (resp.statusCode != 200) return null;
    try {
      final json = jsonDecode(resp.body) as Map?;
      return json?['staff_id']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// POST /api/call-invitations
  Future<String?> createCallInvitation({
    required String toUserId,
    required String channelId,
    String? fromUserName,
    String callType = 'voice',
  }) async {
    if (!_api.isAvailable) return null;
    final resp = await _api.post('api/call-invitations', body: {
      'to_user_id': toUserId,
      'channel_id': channelId,
      if (fromUserName != null) 'from_user_name': fromUserName,
      'call_type': callType,
    });
    if (resp.statusCode != 200) return null;
    try {
      final json = jsonDecode(resp.body) as Map?;
      return json?['id']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// PATCH /api/call-invitations/:id/status
  Future<void> updateCallInvitationStatus(String id, String status) async {
    if (!_api.isAvailable) return;
    await _api.patch('api/call-invitations/$id/status', body: {'status': status});
  }

  /// GET /api/call-invitations/:id
  Future<Map<String, dynamic>?> getCallInvitation(String id) async {
    if (!_api.isAvailable || id.isEmpty) return null;
    final resp = await _api.get('api/call-invitations/$id');
    if (resp.statusCode != 200) return null;
    try {
      final json = jsonDecode(resp.body);
      if (json == null) return null;
      return Map<String, dynamic>.from(json as Map);
    } catch (_) {
      return null;
    }
  }

  /// GET /api/call-invitations/ringing — 被叫：获取发给我且 ringing 的最新一条
  Future<Map<String, dynamic>?> getLatestRingingInvitation() async {
    if (!_api.isAvailable) return null;
    final resp = await _api.get('api/call-invitations/ringing');
    if (resp.statusCode != 200) return null;
    try {
      final json = jsonDecode(resp.body);
      if (json == null) return null;
      return Map<String, dynamic>.from(json as Map);
    } catch (_) {
      return null;
    }
  }

  /// GET /api/call-invitations/records?peer_user_id=xxx
  Future<List<Map<String, dynamic>>> getCallRecords(String peerUserId, {int limit = 50}) async {
    if (!_api.isAvailable) return [];
    final resp = await _api.get('api/call-invitations/records', queryParameters: {
      'peer_user_id': peerUserId,
      'limit': limit.toString(),
    });
    if (resp.statusCode != 200) return [];
    try {
      final list = jsonDecode(resp.body) as List? ?? [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<String?> getAgoraToken(String channelId, {int? uid}) async {
    if (!_api.isAvailable || channelId.trim().isEmpty) return null;
    final resp = await _api.get(
      'api/call-invitations/agora-token',
      queryParameters: {
        'channel_id': channelId,
        if (uid != null) 'uid': '$uid',
      },
    );
    if (resp.statusCode != 200) return null;
    try {
      final json = jsonDecode(resp.body) as Map?;
      final token = json?['token']?.toString().trim();
      return token != null && token.isNotEmpty ? token : null;
    } catch (_) {
      return null;
    }
  }
}
