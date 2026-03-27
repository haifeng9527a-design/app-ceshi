import 'dart:async';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'message_models.dart';

/// SQLite 本地存储：会话列表与聊天记录
/// 启动时从服务端拉取一次，与本地合并（不存在则插入，已存在则更新）
/// 收到新消息时更新本地并通知 UI
class ChatDb {
  ChatDb._();
  static final ChatDb instance = ChatDb._();

  Database? _db;
  static const int _version = 2;
  static const String _dbName = 'chat_local.db';

  final Map<String, StreamController<Object?>> _conversationControllers = {};
  final Map<String, StreamController<Object?>> _messageControllers = {};

  Future<Database> _getDb() async {
    if (_db != null && _db!.isOpen) return _db!;
    final dbDir = await getDatabasesPath();
    final dbPath = join(dbDir, _dbName);
    _db = await openDatabase(
      dbPath,
      version: _version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE conversations (
        id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        title TEXT,
        subtitle TEXT,
        last_message TEXT,
        last_time TEXT,
        peer_id TEXT,
        avatar_text TEXT,
        avatar_url TEXT,
        unread_count INTEGER DEFAULT 0,
        is_group INTEGER DEFAULT 0,
        last_message_sender_id TEXT,
        type TEXT,
        raw_json TEXT,
        updated_at INTEGER,
        PRIMARY KEY (id, user_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        current_user_id TEXT NOT NULL,
        sender_id TEXT,
        sender_name TEXT,
        content TEXT,
        message_type TEXT,
        created_at TEXT,
        media_url TEXT,
        media_url_transcoded TEXT,
        duration_ms INTEGER,
        local_path TEXT,
        reply_to_message_id TEXT,
        reply_to_sender_name TEXT,
        reply_to_content TEXT,
        updated_at INTEGER,
        local_display_time TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_conv_user ON conversations(user_id)');
    await db.execute('CREATE INDEX idx_conv_updated ON conversations(user_id, updated_at)');
    await db.execute('CREATE INDEX idx_msg_conv ON messages(conversation_id, current_user_id)');
    await db.execute('CREATE INDEX idx_msg_created ON messages(conversation_id, created_at)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE messages ADD COLUMN local_display_time TEXT');
      } catch (_) {}
    }
  }

  /// 合并会话：以服务端为准，先清空该用户会话再插入（已删除的会移除）
  Future<void> upsertConversations(String userId, List<Conversation> list) async {
    if (userId.isEmpty) return;
    final db = await _getDb();
    await db.delete('conversations', where: 'user_id = ?', whereArgs: [userId]);
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final c in list) {
      batch.insert(
        'conversations',
        {
          'id': c.id,
          'user_id': userId,
          'title': c.title,
          'subtitle': c.subtitle,
          'last_message': c.lastMessage,
          'last_time': c.lastTime?.toIso8601String(),
          'peer_id': c.peerId,
          'avatar_text': null,
          'avatar_url': c.avatarUrl,
          'unread_count': c.unreadCount,
          'is_group': c.isGroup ? 1 : 0,
          'last_message_sender_id': c.lastMessageSenderId,
          'type': c.isGroup ? 'group' : 'direct',
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    _notifyConversations(userId);
  }

  /// 合并消息：不存在则插入，已存在则更新。显示时间以本地为准（首次收到/发送时的本地时间）
  Future<void> upsertMessages({
    required String conversationId,
    required String currentUserId,
    required List<ChatMessage> list,
  }) async {
    if (conversationId.isEmpty || currentUserId.isEmpty) return;
    final db = await _getDb();
    final now = DateTime.now();
    final nowStr = now.toIso8601String();
    final ids = list.map((m) => m.id).toList();
    final existingRows = ids.isEmpty
        ? <Map<String, dynamic>>[]
        : await db.query(
            'messages',
            columns: ['id', 'local_display_time'],
            where: 'conversation_id = ? AND current_user_id = ? AND id IN (${List.filled(ids.length, '?').join(',')})',
            whereArgs: [conversationId, currentUserId, ...ids],
          );
    final existingMap = {for (final r in existingRows) r['id'] as String: r['local_display_time'] as String?};
    for (final m in list) {
      final keepTime = existingMap[m.id];
      await db.insert(
        'messages',
        {
          'id': m.id,
          'conversation_id': conversationId,
          'current_user_id': currentUserId,
          'sender_id': m.senderId,
          'sender_name': m.senderName,
          'content': m.content,
          'message_type': m.messageType,
          'created_at': m.time.toIso8601String(),
          'media_url': m.mediaUrl,
          'media_url_transcoded': m.mediaUrlTranscoded,
          'duration_ms': m.durationMs,
          'local_path': m.localPath,
          'reply_to_message_id': m.replyToMessageId,
          'reply_to_sender_name': m.replyToSenderName,
          'reply_to_content': m.replyToContent,
          'updated_at': now.millisecondsSinceEpoch,
          'local_display_time': keepTime ?? nowStr,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    _notifyMessages(conversationId, currentUserId);
  }

  /// 插入单条消息（收到新消息时调用）
  Future<void> insertMessage({
    required String conversationId,
    required String currentUserId,
    required ChatMessage message,
  }) async {
    await upsertMessages(
      conversationId: conversationId,
      currentUserId: currentUserId,
      list: [message],
    );
  }

  /// 删除本地临时消息（id 以 local- 开头）中与给定内容匹配的，用于收到服务端 new_message 时替换
  Future<void> deleteLocalMessageMatch({
    required String conversationId,
    required String currentUserId,
    required String senderId,
    required String content,
    required String messageType,
    String? mediaUrl,
  }) async {
    if (conversationId.isEmpty || currentUserId.isEmpty) return;
    final db = await _getDb();
    final args = <dynamic>[conversationId, currentUserId, 'local-%', senderId, content, messageType];
    String where = 'conversation_id = ? AND current_user_id = ? AND id LIKE ? AND sender_id = ? AND content = ? AND message_type = ?';
    if (mediaUrl != null && mediaUrl.isNotEmpty) {
      where += ' AND media_url = ?';
      args.add(mediaUrl);
    } else {
      where += ' AND (media_url IS NULL OR media_url = \'\')';
    }
    await db.delete('messages', where: where, whereArgs: args);
    _notifyMessages(conversationId, currentUserId);
  }

  /// 更新会话（如最后一条消息、未读数变化）
  Future<void> updateConversation(String userId, Conversation c) async {
    await upsertConversations(userId, [c]);
  }

  Future<List<Conversation>> getConversations(String userId) async {
    if (userId.isEmpty) return [];
    final db = await _getDb();
    final rows = await db.query(
      'conversations',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'updated_at DESC',
    );
    return rows.map(_rowToConversation).toList();
  }

  Future<List<ChatMessage>> getMessages({
    required String conversationId,
    required String currentUserId,
    int limit = 200,
  }) async {
    if (conversationId.isEmpty || currentUserId.isEmpty) return [];
    final db = await _getDb();
    final rows = await db.query(
      'messages',
      where: 'conversation_id = ? AND current_user_id = ?',
      whereArgs: [conversationId, currentUserId],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map((r) => _rowToMessage(r, currentUserId)).toList();
  }

  Conversation _rowToConversation(Map<String, dynamic> r) {
    return Conversation(
      id: r['id'] as String,
      title: (r['title'] as String?) ?? '未命名会话',
      subtitle: (r['subtitle'] as String?) ?? '',
      lastMessage: (r['last_message'] as String?) ?? '',
      lastTime: r['last_time'] != null ? DateTime.tryParse(r['last_time'] as String) : null,
      peerId: r['peer_id'] as String?,
      avatarUrl: r['avatar_url'] as String?,
      unreadCount: r['unread_count'] as int? ?? 0,
      isGroup: (r['is_group'] as int? ?? 0) == 1,
      lastMessageSenderId: r['last_message_sender_id'] as String?,
    );
  }

  ChatMessage _rowToMessage(Map<String, dynamic> r, String currentUserId) {
    final senderId = r['sender_id'] as String? ?? '';
    final localDisplay = r['local_display_time'] as String?;
    final displayTime = localDisplay != null && localDisplay.isNotEmpty
        ? DateTime.tryParse(localDisplay)
        : null;
    final fallback = DateTime.tryParse(r['created_at'] as String? ?? '') ?? DateTime.now();
    return ChatMessage(
      id: r['id'] as String,
      senderId: senderId,
      senderName: r['sender_name'] as String? ?? '用户',
      content: r['content'] as String? ?? '',
      messageType: r['message_type'] as String? ?? 'text',
      mediaUrl: r['media_url'] as String?,
      mediaUrlTranscoded: r['media_url_transcoded'] as String?,
      durationMs: r['duration_ms'] as int?,
      localPath: r['local_path'] as String?,
      time: displayTime ?? fallback,
      isMine: senderId == currentUserId,
      replyToMessageId: r['reply_to_message_id'] as String?,
      replyToSenderName: r['reply_to_sender_name'] as String?,
      replyToContent: r['reply_to_content'] as String?,
    );
  }

  void _notifyConversations(String userId) {
    _conversationControllers[userId]?.add(null);
  }

  void _notifyMessages(String conversationId, String currentUserId) {
    final key = '${conversationId}_$currentUserId';
    _messageControllers[key]?.add(null);
  }

  /// 监听会话列表变化，本地有更新时自动重新拉取并推送
  Stream<List<Conversation>> watchConversations(String userId) async* {
    if (userId.isEmpty) {
      yield [];
      return;
    }
    final key = userId;
    _conversationControllers[key] ??= StreamController<Object?>.broadcast();
    yield await getConversations(userId);
    await for (final _ in _conversationControllers[key]!.stream) {
      yield await getConversations(userId);
    }
  }

  /// 监听消息列表变化
  Stream<List<ChatMessage>> watchMessages({
    required String conversationId,
    required String currentUserId,
  }) async* {
    if (conversationId.isEmpty || currentUserId.isEmpty) {
      yield [];
      return;
    }
    final key = '${conversationId}_$currentUserId';
    _messageControllers[key] ??= StreamController<Object?>.broadcast();
    yield await getMessages(conversationId: conversationId, currentUserId: currentUserId);
    await for (final _ in _messageControllers[key]!.stream) {
      yield await getMessages(conversationId: conversationId, currentUserId: currentUserId);
    }
  }

  /// 删除会话（用户主动删除时）
  Future<void> deleteConversation(String userId, String conversationId) async {
    final db = await _getDb();
    await db.delete(
      'conversations',
      where: 'user_id = ? AND id = ?',
      whereArgs: [userId, conversationId],
    );
    await db.delete(
      'messages',
      where: 'conversation_id = ? AND current_user_id = ?',
      whereArgs: [conversationId, userId],
    );
    _notifyConversations(userId);
  }

  Future<void> close() async {
    for (final c in _conversationControllers.values) {
      await c.close();
    }
    for (final c in _messageControllers.values) {
      await c.close();
    }
    _conversationControllers.clear();
    _messageControllers.clear();
    await _db?.close();
    _db = null;
  }
}
