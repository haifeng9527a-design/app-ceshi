import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../features/messages/friend_models.dart';

/// 好友相关 API
class FriendsApi {
  FriendsApi._();
  static final FriendsApi instance = FriendsApi._();
  final _api = ApiClient.instance;

  static DateTime? _parseDateTime(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  static FriendProfile _profileFromRow(Map<String, dynamic> row, {String? teacherStatus}) {
    final ts = teacherStatus ?? row['teacher_status'] as String? ?? 'pending';
    String roleLabel = '普通用户';
    final r = (row['role'] as String? ?? '').toLowerCase();
    final status = ts.toString().toLowerCase();
    if (r == 'admin') roleLabel = '管理员';
    else if (r == 'vip') roleLabel = '会员';
    else if (r == 'teacher' || status == 'approved') roleLabel = '交易员';
    else if (r == 'customer_service') roleLabel = '客服';
    return FriendProfile(
      userId: row['user_id'] as String,
      displayName: (row['display_name'] as String?) ?? (row['email'] as String?)?.split('@').first ?? '用户',
      email: row['email'] as String? ?? '',
      avatarUrl: row['avatar_url'] as String?,
      status: row['status'] as String? ?? 'offline',
      shortId: row['short_id'] as String?,
      level: (row['level'] as int?) ?? 0,
      roleLabel: roleLabel,
      lastOnlineAt: _parseDateTime(row['last_online_at']),
    );
  }

  /// GET /api/friends
  Future<List<FriendProfile>> getFriends() async {
    if (!_api.isAvailable) return [];
    final resp = await _api.get('api/friends');
    if (resp.statusCode != 200) {
      if (kDebugMode) debugPrint('[FriendsApi] GET /api/friends => ${resp.statusCode} ${resp.body}');
      if (resp.statusCode == 401) throw Exception('鉴权失败，请重新登录');
      if (resp.statusCode == 503) throw Exception('后端鉴权服务未配置');
      return [];
    }
    try {
      final list = jsonDecode(resp.body) as List? ?? [];
      return list.map((e) => _profileFromRow(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  /// 轮询好友列表流
  Stream<List<FriendProfile>> watchFriends({required String userId, Duration interval = const Duration(seconds: 5)}) async* {
    while (true) {
      yield await getFriends();
      await Future<void>.delayed(interval);
    }
  }

  /// GET /api/friends/remarks
  Future<Map<String, String>> getRemarks() async {
    if (!_api.isAvailable) return {};
    final resp = await _api.get('api/friends/remarks');
    if (resp.statusCode != 200) return {};
    try {
      final json = jsonDecode(resp.body) as Map? ?? {};
      return json.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  Stream<Map<String, String>> watchRemarks({required String userId, Duration interval = const Duration(seconds: 5)}) async* {
    while (true) {
      yield await getRemarks();
      await Future<void>.delayed(interval);
    }
  }

  /// PUT /api/friends/remarks
  Future<void> saveRemark({required String userId, required String friendId, required String remark}) async {
    if (!_api.isAvailable) return;
    await _api.put('api/friends/remarks', body: {'friend_id': friendId, 'remark': remark.trim()});
  }

  /// GET /api/friends/requests/incoming
  Future<List<FriendRequestItem>> getIncomingRequests() async {
    if (!_api.isAvailable) return [];
    final resp = await _api.get('api/friends/requests/incoming');
    if (resp.statusCode != 200) return [];
    try {
      final list = jsonDecode(resp.body) as List? ?? [];
      return list.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return FriendRequestItem(
          requestId: m['request_id'] as String? ?? '',
          requesterId: m['requester_id'] as String? ?? '',
          requesterName: m['requester_name'] as String? ?? '用户',
          requesterEmail: m['requester_email'] as String? ?? '',
          requesterAvatar: m['requester_avatar'] as String?,
          requesterShortId: m['requester_short_id'] as String?,
          status: m['status'] as String? ?? 'pending',
          createdAt: _parseDateTime(m['created_at']),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// GET /api/friends/requests/all — 收到+发出的所有好友申请
  Future<List<FriendRequestItem>> getAllRequestRecords() async {
    if (!_api.isAvailable) return [];
    final resp = await _api.get('api/friends/requests/all');
    if (resp.statusCode != 200) return [];
    try {
      final list = jsonDecode(resp.body) as List? ?? [];
      return list.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        final isOutgoing = m['is_outgoing'] as bool? ?? false;
        return FriendRequestItem(
          requestId: m['request_id'] as String? ?? '',
          requesterId: m['requester_id'] as String? ?? '',
          requesterName: m['requester_name'] as String? ?? '用户',
          requesterEmail: m['requester_email'] as String? ?? '',
          requesterAvatar: m['requester_avatar'] as String?,
          requesterShortId: m['requester_short_id'] as String?,
          status: m['status'] as String? ?? 'pending',
          createdAt: _parseDateTime(m['created_at']),
          isOutgoing: isOutgoing,
          receiverId: m['receiver_id'] as String?,
          receiverName: m['receiver_name'] as String? ?? '用户',
          receiverAvatar: m['receiver_avatar'] as String?,
          receiverShortId: m['receiver_short_id'] as String?,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// GET /api/friends/requests/incoming/count
  Future<int> getIncomingRequestCount(String userId) async {
    if (!_api.isAvailable) return 0;
    final resp = await _api.get('api/friends/requests/incoming/count');
    if (resp.statusCode != 200) return 0;
    try {
      final json = jsonDecode(resp.body) as Map?;
      return json?['count'] as int? ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// POST /api/friends/requests
  Future<void> sendFriendRequest({required String requesterId, required String receiverId}) async {
    if (!_api.isAvailable) return;
    final resp = await _api.post('api/friends/requests', body: {'receiver_id': receiverId});
    if (resp.statusCode == 400) {
      final json = jsonDecode(resp.body) as Map?;
      final err = json?['error'] as String?;
      if (err == 'already_friends') throw Exception('already_friends');
      if (err == 'already_pending') throw Exception('already_pending');
    }
    if (resp.statusCode != 200) throw Exception(resp.body);
  }

  /// POST /api/friends/requests/:id/accept
  Future<void> acceptRequest({required String requestId, required String requesterId, required String receiverId}) async {
    if (!_api.isAvailable) return;
    await _api.post('api/friends/requests/$requestId/accept', body: {'requester_id': requesterId, 'receiver_id': receiverId});
  }

  /// POST /api/friends/requests/:id/reject
  Future<void> rejectRequest({required String requestId}) async {
    if (!_api.isAvailable) return;
    await _api.post('api/friends/requests/$requestId/reject');
  }

  /// DELETE /api/friends/:friendId
  Future<void> deleteFriend({required String userId, required String friendId}) async {
    if (!_api.isAvailable) return;
    await _api.delete('api/friends/$friendId');
  }

  /// GET /api/friends/search?by=email|short_id&value=xxx
  Future<FriendProfile?> searchByEmail(String email) async {
    if (!_api.isAvailable) return null;
    final resp = await _api.get('api/friends/search', queryParameters: {'by': 'email', 'value': email});
    if (resp.statusCode != 200) return null;
    try {
      final json = jsonDecode(resp.body);
      if (json == null) return null;
      return _profileFromRow(Map<String, dynamic>.from(json as Map));
    } catch (_) {
      return null;
    }
  }

  Future<FriendProfile?> searchByShortId(String shortId) async {
    if (!_api.isAvailable) return null;
    final resp = await _api.get('api/friends/search', queryParameters: {'by': 'short_id', 'value': shortId});
    if (resp.statusCode != 200) return null;
    try {
      final json = jsonDecode(resp.body);
      if (json == null) return null;
      return _profileFromRow(Map<String, dynamic>.from(json as Map));
    } catch (_) {
      return null;
    }
  }

  /// GET /api/friends/check/:friendId
  Future<bool> isFriend({required String userId, required String friendId}) async {
    if (!_api.isAvailable) return false;
    final resp = await _api.get('api/friends/check/$friendId');
    if (resp.statusCode != 200) return false;
    try {
      final json = jsonDecode(resp.body) as Map?;
      return json?['is_friend'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  /// POST /api/friends/ensure-customer-service
  Future<void> ensureCustomerServiceFriend({required String userId, required String customerServiceId}) async {
    if (!_api.isAvailable) return;
    await _api.post('api/friends/ensure-customer-service');
  }
}
