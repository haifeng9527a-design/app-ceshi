import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_bootstrap.dart';
import 'message_models.dart';

class MessagesRepository {
  MessagesRepository({SupabaseClient? client})
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  Stream<List<Conversation>> watchConversations({
    required String userId,
  }) {
    return _client
        .from('chat_members')
        .stream(primaryKey: ['conversation_id', 'user_id'])
        .eq('user_id', userId)
        .asyncMap((rows) async {
      if (rows.isEmpty) {
        return <Conversation>[];
      }
      final unreadMap = <String, int>{};
      for (final row in rows) {
        final id = row['conversation_id'] as String?;
        if (id == null) {
          continue;
        }
        unreadMap[id] = row['unread_count'] as int? ?? 0;
      }
      if (unreadMap.isEmpty) {
        return <Conversation>[];
      }
      final memberRows = await _client
          .from('chat_members')
          .select('conversation_id, user_id')
          .inFilter('conversation_id', unreadMap.keys.toList());
      final peerMap = <String, String>{};
      for (final row in memberRows) {
        final conversationId = row['conversation_id'] as String?;
        final memberId = row['user_id'] as String?;
        if (conversationId == null || memberId == null) {
          continue;
        }
        if (memberId == userId) {
          continue;
        }
        peerMap[conversationId] = memberId;
      }
      final conversations = await _client
          .from('chat_conversations')
          .select()
          .inFilter('id', unreadMap.keys.toList())
          .order('last_time', ascending: false);
      final results = <Conversation>[];
      for (final row in conversations) {
        final id = row['id'] as String? ?? '';
        final type = row['type'] as String?;
        if (type == 'direct') {
          final peerId = peerMap[id];
          if (peerId == null || peerId.isEmpty) {
            // Orphaned direct conversation, skip it.
            continue;
          }
        }
        results.add(Conversation.fromSupabase(
          row: row,
          unreadCount: unreadMap[id] ?? 0,
          peerId: type == 'direct' ? peerMap[id] : null,
        ));
      }
      return results;
    });
  }

  /// 获取当前用户总未读消息数（用于角标等）
  Future<int> getTotalUnreadCount(String userId) async {
    if (userId.isEmpty) return 0;
    try {
      final rows = await _client
          .from('chat_members')
          .select('unread_count')
          .eq('user_id', userId);
      int total = 0;
      for (final row in rows) {
        total += row['unread_count'] as int? ?? 0;
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<Conversation?> fetchConversationById({
    required String conversationId,
    required String currentUserId,
  }) async {
    if (conversationId.isEmpty || currentUserId.isEmpty) {
      return null;
    }
    final convo = await _client
        .from('chat_conversations')
        .select()
        .eq('id', conversationId)
        .maybeSingle();
    if (convo == null) {
      return null;
    }
    final members = await _client
        .from('chat_members')
        .select('user_id, unread_count')
        .eq('conversation_id', conversationId);
    int unreadCount = 0;
    String? peerId;
    for (final row in members) {
      final memberId = row['user_id'] as String?;
      if (memberId == null) {
        continue;
      }
      if (memberId == currentUserId) {
        unreadCount = row['unread_count'] as int? ?? 0;
      } else {
        peerId = memberId;
      }
    }
    final type = convo['type'] as String?;
    return Conversation.fromSupabase(
      row: convo,
      unreadCount: unreadCount,
      peerId: type == 'direct' ? peerId : null,
    );
  }

  Future<List<String>> findDirectConversationIds({
    required String currentUserId,
    required String friendId,
  }) async {
    if (currentUserId.isEmpty || friendId.isEmpty) {
      return const <String>[];
    }
    final myRows = await _client
        .from('chat_members')
        .select('conversation_id')
        .eq('user_id', currentUserId);
    final friendRows = await _client
        .from('chat_members')
        .select('conversation_id')
        .eq('user_id', friendId);
    final myIds = myRows
        .map((row) => row['conversation_id'] as String?)
        .whereType<String>()
        .toSet();
    final friendIds = friendRows
        .map((row) => row['conversation_id'] as String?)
        .whereType<String>()
        .toSet();
    final common = myIds.intersection(friendIds).toList();
    if (common.isEmpty) {
      return const <String>[];
    }
    final directRows = await _client
        .from('chat_conversations')
        .select('id,type')
        .inFilter('id', common);
    return directRows
        .where((row) => row['type'] == 'direct')
        .map((row) => row['id'] as String)
        .toList();
  }

  Future<void> removeConversationForUser({
    required String conversationId,
    required String userId,
  }) async {
    if (conversationId.isEmpty || userId.isEmpty) {
      return;
    }
    await _client
        .from('chat_members')
        .delete()
        .eq('conversation_id', conversationId)
        .eq('user_id', userId);
  }

  Stream<List<ChatMessage>> watchMessages({
    required String conversationId,
    required String currentUserId,
  }) {
    return _client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .map((rows) {
          final messages = rows
              .map((row) => ChatMessage.fromSupabase(
                    row: row,
                    currentUserId: currentUserId,
                  ))
              .toList();
          messages.sort((a, b) => a.time.compareTo(b.time));
          return messages;
        });
  }

  Future<void> deleteMessage({required String messageId}) async {
    if (messageId.isEmpty) {
      return;
    }
    await _client.from('chat_messages').delete().eq('id', messageId);
  }

  /// 清空会话内所有消息（仅删除服务端记录）
  Future<void> deleteMessagesByConversation(String conversationId) async {
    if (conversationId.isEmpty) return;
    await _client
        .from('chat_messages')
        .delete()
        .eq('conversation_id', conversationId);
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
    /// 群聊时推送给除发送者外的所有成员；与 receiverId 二选一
    List<String>? receiverIds,
    String? replyToMessageId,
    String? replyToSenderName,
    String? replyToContent,
  }) async {
    final map = <String, dynamic>{
      'conversation_id': conversationId,
      'sender_id': senderId,
      'sender_name': senderName,
      'content': content,
      'message_type': messageType,
      'media_url': mediaUrl,
      'duration_ms': durationMs,
      'local_path': localPath,
    };
    if (replyToMessageId != null && replyToMessageId.isNotEmpty) {
      map['reply_to_message_id'] = replyToMessageId;
      if (replyToSenderName != null) map['reply_to_sender_name'] = replyToSenderName;
      if (replyToContent != null) map['reply_to_content'] = replyToContent;
    }
    await _client.from('chat_messages').insert(map);
    // 推送由 Database Webhook（chat_messages INSERT → notify_new_message → send_push）统一触发，不再在客户端调用 send_push，避免每条消息推两次。
  }

  Future<String> uploadChatMedia({
    required String conversationId,
    required String userId,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final bucket = 'chat-media';
    final safeName = fileName.replaceAll(' ', '_');
    final path =
        'chat/$conversationId/$userId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
          ),
        );
    return _client.storage.from(bucket).getPublicUrl(path);
  }

  /// 上传群头像，返回公开 URL
  Future<String> uploadGroupAvatar({
    required String conversationId,
    required String userId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final bucket = 'chat-media';
    final path =
        'chat/$conversationId/group_avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
          ),
        );
    return _client.storage.from(bucket).getPublicUrl(path);
  }

  Future<void> markConversationRead({
    required String conversationId,
    required String userId,
  }) async {
    await _client
        .from('chat_members')
        .update({
          'unread_count': 0,
          'last_read_at': DateTime.now().toIso8601String(),
        })
        .eq('conversation_id', conversationId)
        .eq('user_id', userId);
  }

  /// 创建群聊：当前用户为群主(owner)，其余为 member
  Future<Conversation> createGroupConversation({
    required String currentUserId,
    required String currentUserName,
    required String title,
    required List<String> memberUserIds,
  }) async {
    if (memberUserIds.isEmpty) {
      throw ArgumentError('群聊至少需要除自己外一名成员');
    }
    final allIds = {currentUserId, ...memberUserIds};
    final groupTitle = title.trim().isEmpty ? '群聊(${allIds.length}人)' : title.trim();
    final created = await _client
        .from('chat_conversations')
        .insert({
          'type': 'group',
          'title': groupTitle,
        })
        .select()
        .single();
    final conversationId = created['id'] as String;
    final memberRows = allIds.map((uid) => {
      'conversation_id': conversationId,
      'user_id': uid,
      'role': uid == currentUserId ? 'owner' : 'member',
    }).toList();
    await _client.from('chat_members').insert(memberRows);
    return Conversation.fromSupabase(
      row: created,
      unreadCount: 0,
      peerId: null,
    );
  }

  /// 群资料与成员（含角色）
  Future<GroupInfo?> fetchGroupInfo({
    required String conversationId,
    required String currentUserId,
  }) async {
    if (conversationId.isEmpty) return null;
    final convo = await _client
        .from('chat_conversations')
        .select()
        .eq('id', conversationId)
        .maybeSingle();
    if (convo == null || (convo['type'] as String?) != 'group') return null;
    final memberRows = await _client
        .from('chat_members')
        .select('user_id, role')
        .eq('conversation_id', conversationId);
    String myRole = 'member';
    final members = <GroupMember>[];
    for (final row in memberRows) {
      final uid = row['user_id'] as String? ?? '';
      final role = row['role'] as String? ?? 'member';
      if (uid == currentUserId) myRole = role;
      members.add(GroupMember(userId: uid, role: role));
    }
    final title = convo['title'] as String? ?? '未命名群聊';
    return GroupInfo(
      conversationId: conversationId,
      title: title,
      announcement: convo['announcement'] as String?,
      avatarUrl: convo['avatar_url'] as String?,
      createdBy: convo['created_by'] as String?,
      memberCount: members.length,
      myRole: myRole,
      members: members,
    );
  }

  /// 拉取成员资料（displayName, avatarUrl 等）需结合 user_profiles，此处仅返回 id+role，由上层补全
  Future<List<GroupMember>> fetchGroupMembers(String conversationId) async {
    if (conversationId.isEmpty) return [];
    final rows = await _client
        .from('chat_members')
        .select('user_id, role')
        .eq('conversation_id', conversationId);
    return rows
        .map((row) => GroupMember(
              userId: row['user_id'] as String? ?? '',
              role: row['role'] as String? ?? 'member',
            ))
        .toList();
  }

  /// 插入群系统消息（加入/退群提示），不推送。
  Future<void> insertSystemMessage({
    required String conversationId,
    required String messageType,
    required String content,
    required String senderId,
    required String senderName,
  }) async {
    await _client.from('chat_messages').insert({
      'conversation_id': conversationId,
      'sender_id': senderId,
      'sender_name': senderName,
      'content': content,
      'message_type': messageType,
    });
  }

  /// 邀请入群：批量加入成员，并插入「xxx 加入了群聊」系统消息
  Future<void> addGroupMembers({
    required String conversationId,
    required List<String> userIds,
    Map<String, String>? userIdToDisplayName,
  }) async {
    if (conversationId.isEmpty || userIds.isEmpty) return;
    final existing = await _client
        .from('chat_members')
        .select('user_id')
        .eq('conversation_id', conversationId);
    final existingIds = existing.map((r) => r['user_id'] as String?).whereType<String>().toSet();
    final toAdd = userIds.where((id) => !existingIds.contains(id)).toList();
    if (toAdd.isEmpty) return;
    await _client.from('chat_members').insert(
      toAdd.map((uid) => {
        'conversation_id': conversationId,
        'user_id': uid,
        'role': 'member',
      }).toList(),
    );
    for (final uid in toAdd) {
      final name = userIdToDisplayName?[uid]?.trim() ?? '新成员';
      await insertSystemMessage(
        conversationId: conversationId,
        messageType: 'system_join',
        content: '$name 加入了群聊',
        senderId: uid,
        senderName: name,
      );
    }
  }

  /// 移除群成员（群主可移任何人，管理员可移普通成员），并插入退群系统消息（仅群主/管理员可见）
  Future<void> removeGroupMember({
    required String conversationId,
    required String userId,
    String? leaveUserName,
  }) async {
    if (conversationId.isEmpty || userId.isEmpty) return;
    await _client
        .from('chat_members')
        .delete()
        .eq('conversation_id', conversationId)
        .eq('user_id', userId);
    final name = leaveUserName?.trim() ?? '某用户';
    await insertSystemMessage(
      conversationId: conversationId,
      messageType: 'system_leave',
      content: '$name 退出了群聊',
      senderId: userId,
      senderName: name,
    );
  }

  /// 更新成员角色（owner/admin/member）。用于转让群主、设置/取消管理员。
  Future<void> updateMemberRole({
    required String conversationId,
    required String userId,
    required String role,
  }) async {
    if (conversationId.isEmpty || userId.isEmpty) return;
    if (!['owner', 'admin', 'member'].contains(role)) return;
    await _client
        .from('chat_members')
        .update({'role': role})
        .eq('conversation_id', conversationId)
        .eq('user_id', userId);
  }

  /// 转让群主：将 targetUserId 设为 owner，将 currentOwnerId 设为 admin。
  Future<void> transferGroupOwnership({
    required String conversationId,
    required String currentOwnerId,
    required String targetUserId,
  }) async {
    if (conversationId.isEmpty ||
        currentOwnerId.isEmpty ||
        targetUserId.isEmpty) return;
    await _client.from('chat_members').update({'role': 'admin'}).eq(
        'conversation_id', conversationId).eq('user_id', currentOwnerId);
    await _client.from('chat_members').update({'role': 'owner'}).eq(
        'conversation_id', conversationId).eq('user_id', targetUserId);
  }

  /// 退出群聊，并插入退群系统消息（仅群主/管理员可见）
  Future<void> leaveGroup({
    required String conversationId,
    required String userId,
    String? leaveUserName,
  }) async {
    final name = leaveUserName?.trim() ?? '某用户';
    await insertSystemMessage(
      conversationId: conversationId,
      messageType: 'system_leave',
      content: '$name 退出了群聊',
      senderId: userId,
      senderName: name,
    );
    await _client
        .from('chat_members')
        .delete()
        .eq('conversation_id', conversationId)
        .eq('user_id', userId);
  }

  /// 解散群聊（删除会话，cascade 会删成员与消息）
  Future<void> dismissGroup({
    required String conversationId,
  }) async {
    if (conversationId.isEmpty) return;
    await _client.from('chat_conversations').delete().eq('id', conversationId);
  }

  /// 更新群资料（名称、公告等）
  Future<void> updateGroupProfile({
    required String conversationId,
    String? title,
    String? announcement,
    String? avatarUrl,
  }) async {
    if (conversationId.isEmpty) return;
    final map = <String, dynamic>{};
    if (title != null) map['title'] = title;
    if (announcement != null) map['announcement'] = announcement;
    if (avatarUrl != null) map['avatar_url'] = avatarUrl;
    if (map.isEmpty) return;
    await _client
        .from('chat_conversations')
        .update(map)
        .eq('id', conversationId);
  }

  Future<Conversation> createOrGetDirectConversation({
    required String currentUserId,
    required String friendId,
    required String friendName,
  }) async {
    final myRows = await _client
        .from('chat_members')
        .select('conversation_id, chat_conversations(type, title)')
        .eq('user_id', currentUserId);
    final friendRows = await _client
        .from('chat_members')
        .select('conversation_id')
        .eq('user_id', friendId);
    final myIds = myRows
        .map((row) => row['conversation_id'] as String?)
        .whereType<String>()
        .toSet();
    final friendIds = friendRows
        .map((row) => row['conversation_id'] as String?)
        .whereType<String>()
        .toSet();
    final common = myIds.intersection(friendIds).toList();
    if (common.isNotEmpty) {
      final convoRows = await _client
          .from('chat_conversations')
          .select()
          .inFilter('id', common)
          .eq('type', 'direct')
          .order('last_time', ascending: false);
      if (convoRows.isNotEmpty) {
        final primary = convoRows.first;
        final primaryId = primary['id'] as String? ?? '';
        if (primaryId.isNotEmpty && convoRows.length > 1) {
          final extraIds = convoRows
              .skip(1)
              .map((row) => row['id'] as String?)
              .whereType<String>()
              .toList();
          if (extraIds.isNotEmpty) {
            await _client
                .from('chat_members')
                .delete()
                .eq('user_id', currentUserId)
                .inFilter('conversation_id', extraIds);
          }
        }
        return Conversation.fromSupabase(
          row: primary,
          unreadCount: 0,
          peerId: friendId,
        );
      }
    }

    final created = await _client
        .from('chat_conversations')
        .insert({
          'type': 'direct',
          'title': friendName,
        })
        .select()
        .single();
    final conversationId = created['id'] as String;
    await _client.from('chat_members').insert([
      {'conversation_id': conversationId, 'user_id': currentUserId, 'role': 'member'},
      {'conversation_id': conversationId, 'user_id': friendId, 'role': 'member'},
    ]);
    return Conversation.fromSupabase(
      row: created,
      unreadCount: 0,
      peerId: friendId,
    );
  }

  Future<void> deleteConversationForUser({
    required String conversationId,
    required String userId,
  }) async {
    if (conversationId.isEmpty || userId.isEmpty) {
      return;
    }
    await _client
        .from('chat_members')
        .delete()
        .eq('conversation_id', conversationId)
        .eq('user_id', userId);
    final remaining = await _client
        .from('chat_members')
        .select('user_id')
        .eq('conversation_id', conversationId);
    if (remaining.isEmpty) {
      await _client.from('chat_conversations').delete().eq('id', conversationId);
    }
  }
}
