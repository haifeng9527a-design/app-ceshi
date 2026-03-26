class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.lastMessage,
    required this.lastTime,
    this.peerId,
    this.avatarText,
    this.avatarUrl,
    this.unreadCount = 0,
    this.isGroup = false,
    this.lastMessageSenderId,
  });

  final String id;
  final String title;
  final String subtitle;
  final String lastMessage;
  final DateTime? lastTime;
  final String? peerId;
  final String? avatarText;
  final String? avatarUrl;
  final int unreadCount;
  final bool isGroup;
  /// 最后一条消息的发送者 user_id，用于会话列表显示「我: xxx」
  final String? lastMessageSenderId;

  /// 会话最后一条消息时间，显示为当前手机本地时间
  String get lastTimeLabel {
    if (lastTime == null) {
      return '';
    }
    final t = lastTime!.isUtc ? lastTime!.toLocal() : lastTime!;
    final now = DateTime.now();
    final sameDay =
        now.year == t.year && now.month == t.month && now.day == t.day;
    if (sameDay) {
      final hour = t.hour.toString().padLeft(2, '0');
      final minute = t.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }
    return '${t.month}/${t.day}';
  }

  factory Conversation.fromSupabase({
    required Map<String, dynamic> row,
    required int unreadCount,
    String? peerId,
  }) {
    final lastTime = row['last_time'] as String?;
    return Conversation(
      id: row['id'] as String,
      title: (row['title'] as String?) ?? '未命名会话',
      subtitle: (row['type'] as String?) == 'group' ? '群聊' : '私聊',
      lastMessage: (row['last_message'] as String?) ?? '',
      lastTime: lastTime == null ? null : DateTime.tryParse(lastTime),
      peerId: peerId,
      avatarUrl: row['avatar_url'] as String?,
      unreadCount: unreadCount,
      isGroup: (row['type'] as String?) == 'group',
      lastMessageSenderId: row['last_sender_id'] as String?,
    );
  }
}

/// 群成员（用于成员列表）
class GroupMember {
  const GroupMember({
    required this.userId,
    required this.role,
    this.displayName,
    this.avatarUrl,
    this.shortId,
  });

  final String userId;
  final String role; // owner | admin | member
  final String? displayName;
  final String? avatarUrl;
  final String? shortId;

  bool get isOwner => role == 'owner';
  bool get isAdmin => role == 'admin' || role == 'owner';
}

/// 群资料（群设置页）
class GroupInfo {
  const GroupInfo({
    required this.conversationId,
    required this.title,
    required this.memberCount,
    required this.myRole,
    required this.members,
    this.announcement,
    this.avatarUrl,
    this.createdBy,
  });

  final String conversationId;
  final String title;
  final String? announcement;
  final String? avatarUrl;
  final String? createdBy;
  final int memberCount;
  final String myRole;
  final List<GroupMember> members;

  bool get isOwner => myRole == 'owner';
  bool get canManage => myRole == 'owner' || myRole == 'admin';
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.messageType,
    required this.time,
    required this.isMine,
    this.mediaUrl,
    this.mediaUrlTranscoded,
    this.durationMs,
    this.localPath,
    this.isLocal = false,
    this.replyToMessageId,
    this.replyToSenderName,
    this.replyToContent,
  });

  final String id;
  final String senderId;
  final String senderName;
  final String content;
  final String messageType;
  final DateTime time;
  final bool isMine;
  final String? mediaUrl;
  final String? mediaUrlTranscoded;
  final int? durationMs;
  final String? localPath;
  final bool isLocal;
  final String? replyToMessageId;
  final String? replyToSenderName;
  final String? replyToContent;

  bool get isText => messageType == 'text';
  bool get isImage => messageType == 'image';
  bool get isVideo => messageType == 'video';
  bool get isAudio => messageType == 'audio';
  bool get isFile => messageType == 'file';
  bool get isTeacherShare => messageType == 'teacher_share';
  bool get isSystemJoin => messageType == 'system_join';
  bool get isSystemLeave => messageType == 'system_leave';
  bool get isSystem => isSystemJoin || isSystemLeave;

  /// 显示为当前手机本地时间（服务端若是 UTC 会先转成本地再格式化为 HH:mm）
  String get timeLabel {
    final t = time.isUtc ? time.toLocal() : time;
    final hour = t.hour.toString().padLeft(2, '0');
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  factory ChatMessage.fromSupabase({
    required Map<String, dynamic> row,
    required String currentUserId,
  }) {
    final senderId = row['sender_id'] as String? ?? '';
    final replyToId = row['reply_to_message_id'];
    return ChatMessage(
      id: row['id'] as String,
      senderId: senderId,
      senderName: row['sender_name'] as String? ?? '用户',
      content: row['content'] as String? ?? '',
      messageType: row['message_type'] as String? ?? 'text',
      mediaUrl: row['media_url'] as String?,
      mediaUrlTranscoded: row['media_url_transcoded'] as String?,
      durationMs: row['duration_ms'] as int?,
      localPath: row['local_path'] as String?,
      time: DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
      isMine: senderId == currentUserId,
      replyToMessageId: replyToId != null ? replyToId.toString() : null,
      replyToSenderName: row['reply_to_sender_name'] as String?,
      replyToContent: row['reply_to_content'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'sender_name': senderName,
      'content': content,
      'message_type': messageType,
      'created_at': time.toIso8601String(),
      'media_url': mediaUrl,
      'media_url_transcoded': mediaUrlTranscoded,
      'duration_ms': durationMs,
      'local_path': localPath,
      'is_mine': isMine,
      'reply_to_message_id': replyToMessageId,
      'reply_to_sender_name': replyToSenderName,
      'reply_to_content': replyToContent,
    };
  }

  factory ChatMessage.fromJson(
    Map<String, dynamic> json, {
    required String currentUserId,
  }) {
    final senderId = json['sender_id'] as String? ?? '';
    return ChatMessage(
      id: json['id'] as String? ?? '',
      senderId: senderId,
      senderName: json['sender_name'] as String? ?? '用户',
      content: json['content'] as String? ?? '',
      messageType: json['message_type'] as String? ?? 'text',
      mediaUrl: json['media_url'] as String?,
      mediaUrlTranscoded: json['media_url_transcoded'] as String?,
      durationMs: json['duration_ms'] as int?,
      localPath: json['local_path'] as String?,
      time: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      isMine: json['is_mine'] as bool? ?? (senderId == currentUserId),
      replyToMessageId: json['reply_to_message_id'] as String?,
      replyToSenderName: json['reply_to_sender_name'] as String?,
      replyToContent: json['reply_to_content'] as String?,
    );
  }
}
