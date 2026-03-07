import 'dart:async';
import 'dart:typed_data';

import '../../api/messages_api.dart';
import '../../core/api_client.dart';
import 'chat_db.dart';
import 'chat_sync_service.dart';
import 'message_models.dart';

class MessagesRepository {
  MessagesRepository();

  bool get _useApi => ApiClient.instance.isAvailable;

  Stream<List<Conversation>> watchConversations({required String userId}) async* {
    if (userId.isEmpty) {
      yield [];
      return;
    }
    if (!_useApi) {
      yield [];
      return;
    }
    // 启动时拉取一次与本地合并
    await ChatSyncService.instance.syncConversations(userId);
    // 每 5 秒同步一次
    final syncTimer = Stream.periodic(const Duration(seconds: 5), (_) {});
    final syncSub = syncTimer.listen((_) {
      ChatSyncService.instance.syncConversations(userId);
    });
    try {
      await for (final list in ChatDb.instance.watchConversations(userId)) {
        yield list;
      }
    } finally {
      await syncSub.cancel();
    }
  }

  Future<int> getTotalUnreadCount(String userId) async {
    if (userId.isEmpty || !_useApi) return 0;
    return MessagesApi.instance.getTotalUnreadCount(userId);
  }

  Future<Conversation?> fetchConversationById({
    required String conversationId,
    required String currentUserId,
  }) async {
    if (conversationId.isEmpty || currentUserId.isEmpty || !_useApi) return null;
    return MessagesApi.instance.getConversationById(conversationId, currentUserId);
  }

  Future<List<String>> findDirectConversationIds({
    required String currentUserId,
    required String friendId,
  }) async {
    if (currentUserId.isEmpty || friendId.isEmpty || !_useApi) return const <String>[];
    return MessagesApi.instance.findDirectConversationIds(currentUserId, friendId);
  }

  Future<void> removeConversationForUser({
    required String conversationId,
    required String userId,
    String? leaveUserName,
  }) async {
    if (conversationId.isEmpty || userId.isEmpty || !_useApi) return;
    await MessagesApi.instance.removeConversationForUser(conversationId, leaveUserName: leaveUserName);
  }

  Stream<List<ChatMessage>> watchMessages({
    required String conversationId,
    required String currentUserId,
  }) async* {
    if (conversationId.isEmpty || currentUserId.isEmpty) {
      yield [];
      return;
    }
    if (!_useApi) {
      yield [];
      return;
    }
    // 启动时拉取一次与本地合并
    await ChatSyncService.instance.syncMessages(
      conversationId: conversationId,
      currentUserId: currentUserId,
    );
    // 每 2 秒同步一次（减少收消息延迟，部署到远端服务器时体验更好）
    final syncTimer = Stream.periodic(const Duration(seconds: 2), (_) {});
    final syncSub = syncTimer.listen((_) {
      ChatSyncService.instance.syncMessages(
        conversationId: conversationId,
        currentUserId: currentUserId,
      );
    });
    try {
      await for (final list in ChatDb.instance.watchMessages(
        conversationId: conversationId,
        currentUserId: currentUserId,
      )) {
        yield list;
      }
    } finally {
      await syncSub.cancel();
    }
  }

  Future<void> deleteMessage({required String messageId}) async {
    if (messageId.isEmpty || !_useApi) return;
    await MessagesApi.instance.deleteMessage(messageId);
  }

  Future<void> deleteMessagesByConversation(String conversationId) async {
    if (conversationId.isEmpty || !_useApi) return;
    await MessagesApi.instance.deleteMessagesByConversation(conversationId);
  }

  Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String senderName,
    required String content,
    String messageType = 'text',
    String? mediaUrl,
    int? durationMs,
    String? localPath,
    String? receiverId,
    List<String>? receiverIds,
    String? replyToMessageId,
    String? replyToSenderName,
    String? replyToContent,
  }) async {
    if (!_useApi) return;
    await MessagesApi.instance.sendMessage(
      conversationId: conversationId,
      senderId: senderId,
      senderName: senderName,
      content: content,
      messageType: messageType,
      mediaUrl: mediaUrl,
      durationMs: durationMs,
      receiverId: receiverId,
      replyToMessageId: replyToMessageId,
      replyToSenderName: replyToSenderName,
      replyToContent: replyToContent,
    );
    // 发送成功后立即同步，减少对方收到消息的延迟
    ChatSyncService.instance.syncMessages(conversationId: conversationId, currentUserId: senderId);
  }

  Future<String> uploadChatMedia({
    required String conversationId,
    required String userId,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (!_useApi) throw StateError('API 未配置');
    final url = await MessagesApi.instance.uploadChatMedia(
      conversationId: conversationId,
      userId: userId,
      fileName: fileName,
      bytes: bytes.toList(),
      contentType: contentType,
    );
    if (url != null) return url;
    throw StateError('上传失败');
  }

  Future<String> uploadGroupAvatar({
    required String conversationId,
    required String userId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (!_useApi) throw StateError('API 未配置');
    final url = await MessagesApi.instance.uploadGroupAvatar(
      conversationId: conversationId,
      bytes: bytes.toList(),
      contentType: contentType,
    );
    if (url != null) return url;
    throw StateError('上传失败');
  }

  Future<void> markConversationRead({
    required String conversationId,
    required String userId,
  }) async {
    if (!_useApi) return;
    await MessagesApi.instance.markConversationRead(conversationId, userId);
  }

  Future<Conversation> createGroupConversation({
    required String currentUserId,
    required String currentUserName,
    required String title,
    required List<String> memberUserIds,
    String? defaultTitleWhenEmpty,
  }) async {
    if (memberUserIds.isEmpty) throw ArgumentError('群聊至少需要除自己外一名成员');
    if (!_useApi) throw StateError('API 未配置');
    final conv = await MessagesApi.instance.createGroupConversation(
      currentUserId: currentUserId,
      title: title.trim().isEmpty ? (defaultTitleWhenEmpty ?? 'Group(${memberUserIds.length + 1})') : title.trim(),
      memberUserIds: memberUserIds,
    );
    if (conv != null) return conv;
    throw StateError('创建群聊失败');
  }

  Future<GroupInfo?> fetchGroupInfo({
    required String conversationId,
    required String currentUserId,
  }) async {
    if (conversationId.isEmpty || !_useApi) return null;
    return MessagesApi.instance.getGroupInfo(conversationId, currentUserId);
  }

  Future<List<GroupMember>> fetchGroupMembers(String conversationId) async {
    if (conversationId.isEmpty || !_useApi) return [];
    final info = await MessagesApi.instance.getGroupInfo(conversationId, '');
    return info?.members ?? [];
  }

  Future<void> insertSystemMessage({
    required String conversationId,
    required String messageType,
    required String content,
    required String senderId,
    required String senderName,
  }) async {
    if (!_useApi) return;
    await MessagesApi.instance.sendMessage(
      conversationId: conversationId,
      senderId: senderId,
      senderName: senderName,
      content: content,
      messageType: messageType,
    );
  }

  Future<void> addGroupMembers({
    required String conversationId,
    required List<String> userIds,
    Map<String, String>? userIdToDisplayName,
  }) async {
    if (!_useApi || conversationId.isEmpty || userIds.isEmpty) return;
    await MessagesApi.instance.addGroupMembers(
      conversationId: conversationId,
      userIds: userIds,
      userIdToDisplayName: userIdToDisplayName,
    );
  }

  Future<void> removeGroupMember({
    required String conversationId,
    required String userId,
    String? leaveUserName,
  }) async {
    if (!_useApi || conversationId.isEmpty || userId.isEmpty) return;
    await MessagesApi.instance.removeGroupMember(
      conversationId: conversationId,
      userId: userId,
      leaveUserName: leaveUserName,
    );
  }

  Future<void> updateMemberRole({
    required String conversationId,
    required String userId,
    required String role,
  }) async {
    if (!_useApi || conversationId.isEmpty || userId.isEmpty) return;
    if (!['owner', 'admin', 'member'].contains(role)) return;
    await MessagesApi.instance.updateMemberRole(
      conversationId: conversationId,
      userId: userId,
      role: role,
    );
  }

  Future<void> transferGroupOwnership({
    required String conversationId,
    required String currentOwnerId,
    required String targetUserId,
  }) async {
    if (!_useApi || conversationId.isEmpty || targetUserId.isEmpty) return;
    await MessagesApi.instance.transferGroupOwnership(
      conversationId: conversationId,
      targetUserId: targetUserId,
    );
  }

  Future<void> leaveGroup({
    required String conversationId,
    required String userId,
    String? leaveUserName,
  }) async {
    if (!_useApi || conversationId.isEmpty || userId.isEmpty) return;
    await MessagesApi.instance.removeConversationForUser(conversationId, leaveUserName: leaveUserName);
  }

  Future<void> dismissGroup({required String conversationId}) async {
    if (!_useApi || conversationId.isEmpty) return;
    await MessagesApi.instance.dismissGroup(conversationId);
  }

  Future<void> updateGroupProfile({
    required String conversationId,
    String? title,
    String? announcement,
    String? avatarUrl,
  }) async {
    if (!_useApi || conversationId.isEmpty) return;
    await MessagesApi.instance.updateGroupProfile(
      conversationId: conversationId,
      title: title,
      announcement: announcement,
      avatarUrl: avatarUrl,
    );
  }

  Future<Conversation> createOrGetDirectConversation({
    required String currentUserId,
    required String friendId,
    required String friendName,
  }) async {
    if (!_useApi) throw StateError('API 未配置');
    final conv = await MessagesApi.instance.createOrGetDirectConversation(currentUserId, friendId);
    if (conv != null) return conv;
    throw StateError('创建会话失败');
  }

  Future<void> deleteConversationForUser({
    required String conversationId,
    required String userId,
  }) async {
    if (conversationId.isEmpty || userId.isEmpty || !_useApi) return;
    await MessagesApi.instance.removeConversationForUser(conversationId);
  }
}
