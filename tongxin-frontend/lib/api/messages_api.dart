import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../features/messages/message_models.dart';


/// 消息/会话相关 API
class MessagesApi {
  MessagesApi._();
  static final MessagesApi instance = MessagesApi._();
  final _api = ApiClient.instance;

  /// GET /api/conversations
  Future<List<Map<String, dynamic>>> getConversations() async {
    if (!_api.isAvailable) return [];
    final resp = await _api.get('api/conversations');
    if (resp.statusCode != 200) {
      if (kDebugMode) debugPrint('[MessagesApi] GET /api/conversations => ${resp.statusCode} ${resp.body}');
      if (resp.statusCode == 401) throw Exception('鉴权失败，请重新登录');
      if (resp.statusCode == 503) throw Exception('后端鉴权服务未配置');
      return [];
    }
    try {
      final list = jsonDecode(resp.body) as List? ?? [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  /// 轮询会话列表
  Stream<List<Conversation>> watchConversations({required String userId, Duration interval = const Duration(seconds: 5)}) async* {
    while (true) {
      final list = await getConversations();
      yield list.map((c) => Conversation.fromSupabase(
        row: c,
        unreadCount: c['unread_count'] as int? ?? 0,
        peerId: c['peer_id'] as String?,
      )).toList();
      await Future<void>.delayed(interval);
    }
  }

  /// GET /api/conversations/unread-count
  Future<int> getTotalUnreadCount(String userId) async {
    if (!_api.isAvailable) return 0;
    final resp = await _api.get('api/conversations/unread-count');
    if (resp.statusCode != 200) return 0;
    try {
      final json = jsonDecode(resp.body) as Map?;
      return json?['count'] as int? ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// GET /api/conversations/:id
  Future<Conversation?> getConversationById(String conversationId, String currentUserId) async {
    if (!_api.isAvailable) return null;
    final resp = await _api.get('api/conversations/$conversationId');
    if (resp.statusCode != 200) return null;
    try {
      final c = jsonDecode(resp.body);
      if (c == null) return null;
      final map = Map<String, dynamic>.from(c as Map);
      return Conversation.fromSupabase(row: map, unreadCount: map['unread_count'] as int? ?? 0, peerId: map['peer_id'] as String?);
    } catch (_) {
      return null;
    }
  }

  /// GET /api/chat-members/:conversationId
  Future<String?> getPeerId(String conversationId, String currentUserId) async {
    if (!_api.isAvailable) return null;
    final resp = await _api.get('api/chat-members/$conversationId');
    if (resp.statusCode != 200) return null;
    try {
      final json = jsonDecode(resp.body) as Map?;
      return json?['peer_id'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// GET /api/conversations/:id/messages
  Future<List<ChatMessage>> getMessages(String conversationId, String currentUserId, {String? before}) async {
    if (!_api.isAvailable) return [];
    final params = before != null ? {'before': before} : null;
    final resp = await _api.get('api/conversations/$conversationId/messages', queryParameters: params);
    if (resp.statusCode != 200) {
      if (kDebugMode) debugPrint('[MessagesApi] GET /api/conversations/$conversationId/messages => ${resp.statusCode} ${resp.body}');
      return [];
    }
    try {
      final list = jsonDecode(resp.body) as List? ?? [];
      return list.map((e) => ChatMessage.fromSupabase(row: Map<String, dynamic>.from(e as Map), currentUserId: currentUserId)).toList();
    } catch (_) {
      return [];
    }
  }

  /// POST /api/messages
  /// 失败时抛出异常，便于 UI 显示发送失败（红感叹号）
  Future<String?> sendMessage({
    required String conversationId,
    required String senderId,
    required String senderName,
    required String content,
    String messageType = 'text',
    String? mediaUrl,
    int? durationMs,
    String? receiverId,
    String? replyToMessageId,
    String? replyToSenderName,
    String? replyToContent,
  }) async {
    if (!_api.isAvailable) throw StateError('API 未配置');
    final body = <String, dynamic>{
      'conversation_id': conversationId,
      'content': content,
      'message_type': messageType,
    };
    if (mediaUrl != null) body['media_url'] = mediaUrl;
    if (durationMs != null) body['duration_ms'] = durationMs;
    if (replyToMessageId != null) body['reply_to_message_id'] = replyToMessageId;
    if (replyToSenderName != null) body['reply_to_sender_name'] = replyToSenderName;
    if (replyToContent != null) body['reply_to_content'] = replyToContent;
    final resp = await _api.post('api/messages', body: body);
    if (resp.statusCode != 200) {
      if (kDebugMode) debugPrint('[MessagesApi] POST /api/messages => ${resp.statusCode} ${resp.body}');
      String msg = '发送失败';
      try {
        final json = jsonDecode(resp.body) as Map?;
        msg = json?['error']?.toString() ?? msg;
      } catch (_) {}
      if (resp.statusCode == 401) throw Exception('鉴权失败，请重新登录');
      if (resp.statusCode == 403) throw Exception(msg);
      if (resp.statusCode == 502 || resp.statusCode == 503) throw Exception('$msg (${resp.statusCode})');
      throw Exception('$msg (${resp.statusCode})');
    }
    try {
      final json = jsonDecode(resp.body) as Map?;
      return json?['id'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// PATCH /api/conversations/:id/read
  Future<void> markConversationRead(String conversationId, String userId) async {
    if (!_api.isAvailable) return;
    await _api.patch('api/conversations/$conversationId/read');
  }

  /// GET /api/conversations/direct?peer_id=xxx
  Future<List<String>> findDirectConversationIds(String currentUserId, String friendId) async {
    if (!_api.isAvailable) return [];
    final resp = await _api.get('api/conversations/direct', queryParameters: {'peer_id': friendId});
    if (resp.statusCode != 200) return [];
    try {
      final list = jsonDecode(resp.body) as List? ?? [];
      return list.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  /// POST /api/conversations/direct
  Future<Conversation?> createOrGetDirectConversation(String currentUserId, String friendId) async {
    if (!_api.isAvailable) return null;
    final resp = await _api.post('api/conversations/direct', body: {'peer_id': friendId});
    if (resp.statusCode != 200) return null;
    try {
      final json = jsonDecode(resp.body) as Map?;
      final id = json?['id'] as String?;
      if (id == null) return null;
      return getConversationById(id, currentUserId);
    } catch (_) {
      return null;
    }
  }

  /// POST /api/conversations/group
  Future<Conversation?> createGroupConversation({
    required String currentUserId,
    required String title,
    required List<String> memberUserIds,
  }) async {
    if (!_api.isAvailable) return null;
    final resp = await _api.post('api/conversations/group', body: {'title': title, 'member_user_ids': memberUserIds});
    if (resp.statusCode != 200) return null;
    try {
      final json = jsonDecode(resp.body) as Map?;
      final id = json?['id'] as String?;
      if (id == null) return null;
      return getConversationById(id, currentUserId);
    } catch (_) {
      return null;
    }
  }

  /// GET /api/conversations/:id/group-info
  Future<GroupInfo?> getGroupInfo(String conversationId, String currentUserId) async {
    if (!_api.isAvailable) return null;
    final resp = await _api.get('api/conversations/$conversationId/group-info');
    if (resp.statusCode != 200) return null;
    try {
      final json = jsonDecode(resp.body);
      if (json == null) return null;
      final m = Map<String, dynamic>.from(json as Map);
      final members = (m['members'] as List? ?? []).map((e) {
        final r = Map<String, dynamic>.from(e as Map);
        return GroupMember(
          userId: r['user_id'] as String? ?? '',
          role: r['role'] as String? ?? 'member',
          displayName: r['display_name'] as String?,
          avatarUrl: r['avatar_url'] as String?,
          shortId: r['short_id'] as String?,
        );
      }).toList();
      return GroupInfo(
        conversationId: m['conversation_id'] as String? ?? conversationId,
        title: m['title'] as String? ?? '未命名群聊',
        announcement: m['announcement'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        createdBy: m['created_by'] as String?,
        memberCount: m['member_count'] as int? ?? members.length,
        myRole: m['my_role'] as String? ?? 'member',
        members: members,
      );
    } catch (_) {
      return null;
    }
  }

  /// DELETE /api/messages/:id
  Future<void> deleteMessage(String messageId) async {
    if (!_api.isAvailable) return;
    await _api.delete('api/messages/$messageId');
  }

  /// DELETE /api/conversations/:id/members/me — 退出会话（群聊时可传 leave_user_name 插入退群系统消息）
  Future<void> removeConversationForUser(String conversationId, {String? leaveUserName}) async {
    if (!_api.isAvailable) return;
    var url = 'api/conversations/$conversationId/members/me';
    if (leaveUserName != null && leaveUserName.isNotEmpty) {
      url += '?leave_user_name=${Uri.encodeComponent(leaveUserName)}';
    }
    await _api.delete(url);
  }

  /// DELETE /api/conversations/:id/messages — 清空会话消息
  Future<void> deleteMessagesByConversation(String conversationId) async {
    if (!_api.isAvailable) return;
    await _api.delete('api/conversations/$conversationId/messages');
  }

  /// POST /api/upload/group-avatar — 上传群头像
  Future<String?> uploadGroupAvatar({
    required String conversationId,
    required List<int> bytes,
    required String contentType,
  }) async {
    if (!_api.isAvailable) return null;
    final resp = await _api.post('api/upload/group-avatar', body: {
      'conversation_id': conversationId,
      'content_base64': base64Encode(bytes),
      'content_type': contentType,
    });
    if (resp.statusCode != 200) return null;
    try {
      final json = jsonDecode(resp.body) as Map?;
      return json?['url'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// POST /api/conversations/:id/members — 邀请入群
  Future<void> addGroupMembers({
    required String conversationId,
    required List<String> userIds,
    Map<String, String>? userIdToDisplayName,
  }) async {
    if (!_api.isAvailable || conversationId.isEmpty || userIds.isEmpty) return;
    await _api.post('api/conversations/$conversationId/members', body: {
      'user_ids': userIds,
      if (userIdToDisplayName != null) 'user_id_to_display_name': userIdToDisplayName,
    });
  }

  /// DELETE /api/conversations/:id/members/:userId — 移除群成员
  Future<void> removeGroupMember({
    required String conversationId,
    required String userId,
    String? leaveUserName,
  }) async {
    if (!_api.isAvailable || conversationId.isEmpty || userId.isEmpty) return;
    var url = 'api/conversations/$conversationId/members/$userId';
    if (leaveUserName != null && leaveUserName.isNotEmpty) {
      url += '?leave_user_name=${Uri.encodeComponent(leaveUserName)}';
    }
    await _api.delete(url);
  }

  /// PATCH /api/conversations/:id/members/:userId/role
  Future<void> updateMemberRole({
    required String conversationId,
    required String userId,
    required String role,
  }) async {
    if (!_api.isAvailable) return;
    await _api.patch('api/conversations/$conversationId/members/$userId/role', body: {'role': role});
  }

  /// POST /api/conversations/:id/transfer-ownership
  Future<void> transferGroupOwnership({
    required String conversationId,
    required String targetUserId,
  }) async {
    if (!_api.isAvailable) return;
    await _api.post('api/conversations/$conversationId/transfer-ownership', body: {'target_user_id': targetUserId});
  }

  /// DELETE /api/conversations/:id — 解散群聊
  Future<void> dismissGroup(String conversationId) async {
    if (!_api.isAvailable || conversationId.isEmpty) return;
    await _api.delete('api/conversations/$conversationId');
  }

  /// PATCH /api/conversations/:id — 更新群资料
  Future<void> updateGroupProfile({
    required String conversationId,
    String? title,
    String? announcement,
    String? avatarUrl,
  }) async {
    if (!_api.isAvailable || conversationId.isEmpty) return;
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (announcement != null) body['announcement'] = announcement;
    if (avatarUrl != null) body['avatar_url'] = avatarUrl;
    if (body.isEmpty) return;
    await _api.patch('api/conversations/$conversationId', body: body);
  }

  /// 上传聊天媒体，走 /api/upload/chat-media
  Future<String?> uploadChatMedia({
    required String conversationId,
    required String userId,
    required String fileName,
    required List<int> bytes,
    required String contentType,
  }) async {
    if (!_api.isAvailable) return null;
    final base64Str = base64Encode(bytes);
    final resp = await _api.post('api/upload/chat-media', body: {
      'conversation_id': conversationId,
      'content_base64': base64Str,
      'content_type': contentType,
      'file_name': fileName,
    });
    if (resp.statusCode != 200) return null;
    try {
      final json = jsonDecode(resp.body) as Map?;
      return json?['url'] as String?;
    } catch (_) {
      return null;
    }
  }
}
