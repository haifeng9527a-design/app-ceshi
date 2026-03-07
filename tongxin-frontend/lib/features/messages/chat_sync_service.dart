import 'dart:async';

import '../../api/messages_api.dart';
import '../../core/api_client.dart';
import '../../core/chat_web_socket_service.dart';
import 'chat_db.dart';
import 'message_models.dart';

/// 聊天数据同步：启动时从服务端拉取一次与本地合并，收到新消息时更新本地
class ChatSyncService {
  ChatSyncService._();
  static final ChatSyncService instance = ChatSyncService._();

  bool get _useApi => ApiClient.instance.isAvailable;

  /// 同步会话列表：拉取服务端数据，与本地合并（不存在则插入，已存在则更新）
  /// 同时订阅 WebSocket，收到新消息时实时推送
  Future<void> syncConversations(String userId) async {
    if (userId.isEmpty || !_useApi) return;
    try {
      final list = await MessagesApi.instance.getConversations();
      if (list.isEmpty) return;
      final conversations = list.map((c) => Conversation.fromSupabase(
        row: c,
        unreadCount: c['unread_count'] as int? ?? 0,
        peerId: c['peer_id'] as String?,
      )).toList();
      await ChatDb.instance.upsertConversations(userId, conversations);
      final currentIds = ChatWebSocketService.instance.subscribedConversationIds;
      final missingIds = conversations
          .map((c) => c.id)
          .where((id) => id.isNotEmpty && !currentIds.contains(id))
          .toList();
      if (missingIds.isNotEmpty) {
        ChatWebSocketService.instance.subscribe(missingIds);
      }
    } catch (_) {
      // 静默失败，本地数据仍可用
    }
  }

  /// 同步某会话的消息：拉取服务端数据，与本地合并
  Future<void> syncMessages({
    required String conversationId,
    required String currentUserId,
  }) async {
    if (conversationId.isEmpty || currentUserId.isEmpty || !_useApi) return;
    try {
      final list = await MessagesApi.instance.getMessages(conversationId, currentUserId);
      if (list.isEmpty) return;
      await ChatDb.instance.upsertMessages(
        conversationId: conversationId,
        currentUserId: currentUserId,
        list: list,
      );
    } catch (_) {
      // 静默失败
    }
  }
}
