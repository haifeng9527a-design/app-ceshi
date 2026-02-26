import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'friend_models.dart';
import 'message_models.dart';

class MessagesLocalStore {
  static const _pinsKey = 'chat_pins';
  static const _draftsKey = 'chat_drafts';
  static const _friendRemarksKey = 'friend_remarks';
  static const _friendBlacklistKey = 'friend_blacklist';
  static const _hiddenConversationsKey = 'chat_hidden';
  static const _cachedConversationsKey = 'chat_cached_conversations';
  static const _cachedFriendsKey = 'chat_cached_friends';
  static const _cachedMessagesPrefix = 'chat_cached_msgs_';
  static const _maxCachedMessagesPerConversation = 200;
  static const _cachedIncomingRequestsKey = 'chat_cached_incoming_requests';
  static const _cachedPeerPrefix = 'chat_peer_';
  static const _cachedGroupAvatarPrefix = 'chat_group_avatar_';
  static const _mutedConversationsKey = 'chat_muted';

  Future<Set<String>> loadMutedConversations() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_mutedConversationsKey)?.toSet() ?? <String>{};
  }

  Future<void> saveMutedConversations(Set<String> conversationIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_mutedConversationsKey, conversationIds.toList());
  }

  Future<bool> isConversationMuted(String conversationId) async {
    if (conversationId.isEmpty) return false;
    final muted = await loadMutedConversations();
    return muted.contains(conversationId);
  }

  Future<void> setConversationMuted(String conversationId, bool muted) async {
    if (conversationId.isEmpty) return;
    final set = await loadMutedConversations();
    if (muted) {
      set.add(conversationId);
    } else {
      set.remove(conversationId);
    }
    await saveMutedConversations(set);
  }

  Future<Set<String>> loadPinnedConversations() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_pinsKey)?.toSet() ?? <String>{};
  }

  Future<void> savePinnedConversations(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pinsKey, ids.toList());
  }

  Future<Map<String, String>> loadDrafts() async {
    return _loadStringMap(_draftsKey);
  }

  Future<void> saveDraft(String conversationId, String text) async {
    final drafts = await _loadStringMap(_draftsKey);
    if (text.trim().isEmpty) {
      drafts.remove(conversationId);
    } else {
      drafts[conversationId] = text;
    }
    await _saveStringMap(_draftsKey, drafts);
  }

  Future<Map<String, String>> loadFriendRemarks() async {
    return _loadStringMap(_friendRemarksKey);
  }

  /// 将当前全部备注写入本地，供断网时使用
  Future<void> saveFriendRemarks(Map<String, String> remarks) async {
    await _saveStringMap(_friendRemarksKey, remarks);
  }

  /// 缓存会话对方的显示名和头像，断网时顶栏可继续显示
  Future<void> saveConversationPeer({
    required String conversationId,
    required String displayName,
    String? avatarUrl,
  }) async {
    if (conversationId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = '$_cachedPeerPrefix$conversationId';
    await prefs.setString(key, jsonEncode({
      'displayName': displayName,
      'avatarUrl': avatarUrl ?? '',
    }));
  }

  Future<Map<String, String>?> loadConversationPeer(String conversationId) async {
    if (conversationId.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final key = '$_cachedPeerPrefix$conversationId';
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final name = decoded['displayName']?.toString() ?? '';
      final avatar = decoded['avatarUrl']?.toString();
      return {'displayName': name, 'avatarUrl': avatar ?? ''};
    } catch (_) {
      return null;
    }
  }

  /// 缓存群聊头像 URL（群头像 + 各成员头像 + 自己的头像），断网时聊天记录里的头像仍可显示
  Future<void> saveGroupAvatarCache({
    required String conversationId,
    String? groupAvatarUrl,
    required Map<String, String?> memberAvatarUrls,
    String? myAvatarUrl,
  }) async {
    if (conversationId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = '$_cachedGroupAvatarPrefix$conversationId';
    final membersJson = <String, String>{};
    for (final e in memberAvatarUrls.entries) {
      if (e.value != null && e.value!.trim().isNotEmpty) {
        membersJson[e.key] = e.value!.trim();
      }
    }
    await prefs.setString(key, jsonEncode({
      'groupAvatarUrl': groupAvatarUrl ?? '',
      'myAvatarUrl': myAvatarUrl ?? '',
      'members': membersJson,
    }));
  }

  /// 读取群聊头像 URL 缓存，无缓存或解析失败返回 null
  Future<Map<String, dynamic>?> loadGroupAvatarCache(String conversationId) async {
    if (conversationId.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final key = '$_cachedGroupAvatarPrefix$conversationId';
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final groupUrl = decoded['groupAvatarUrl']?.toString().trim();
      final myUrl = decoded['myAvatarUrl']?.toString().trim();
      final members = decoded['members'];
      final Map<String, String?> memberMap = {};
      if (members is Map) {
        for (final e in members.entries) {
          final v = e.value?.toString().trim();
          memberMap[e.key.toString()] = (v != null && v.isNotEmpty) ? v : null;
        }
      }
      return {
        'groupAvatarUrl': (groupUrl != null && groupUrl.isNotEmpty) ? groupUrl : null,
        'myAvatarUrl': (myUrl != null && myUrl.isNotEmpty) ? myUrl : null,
        'memberAvatarUrls': memberMap,
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> saveFriendRemark(
    String friendId,
    String? remark, {
    String? displayName,
    String? email,
  }) async {
    final remarks = await _loadStringMap(_friendRemarksKey);
    final trimmed = remark?.trim() ?? '';
    if (trimmed.isEmpty) {
      remarks.remove(_remarkKeyById(friendId));
      remarks.remove(friendId);
      if (displayName != null && displayName.isNotEmpty) {
        remarks.remove(_remarkKeyByName(displayName));
      }
      if (email != null && email.isNotEmpty) {
        remarks.remove(_remarkKeyByEmail(email));
      }
    } else {
      remarks[_remarkKeyById(friendId)] = trimmed;
      if (!remarks.containsKey(friendId)) {
        remarks[friendId] = trimmed;
      }
      if (displayName != null && displayName.isNotEmpty) {
        remarks[_remarkKeyByName(displayName)] = trimmed;
      }
      if (email != null && email.isNotEmpty) {
        remarks[_remarkKeyByEmail(email)] = trimmed;
      }
    }
    await _saveStringMap(_friendRemarksKey, remarks);
  }

  Future<Set<String>> loadBlacklist() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_friendBlacklistKey)?.toSet() ?? <String>{};
  }

  Future<Map<String, DateTime>> loadHiddenConversations() async {
    final raw = await _loadStringMap(_hiddenConversationsKey);
    final result = <String, DateTime>{};
    for (final entry in raw.entries) {
      final parsed = DateTime.tryParse(entry.value);
      if (parsed != null) {
        result[entry.key] = parsed;
      }
    }
    return result;
  }

  Future<List<Conversation>> loadCachedConversations(String userId) async {
    if (userId.isEmpty) {
      return const <Conversation>[];
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyWithUser(_cachedConversationsKey, userId));
    if (raw == null || raw.isEmpty) {
      return const <Conversation>[];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const <Conversation>[];
    }
    return decoded
        .whereType<Map>()
        .map((item) => _conversationFromJson(item))
        .whereType<Conversation>()
        .toList();
  }

  Future<void> saveCachedConversations(
    String userId,
    List<Conversation> items,
  ) async {
    if (userId.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final payload = items.map(_conversationToJson).toList();
    await prefs.setString(
      _keyWithUser(_cachedConversationsKey, userId),
      jsonEncode(payload),
    );
  }

  Future<List<FriendProfile>> loadCachedFriends(String userId) async {
    if (userId.isEmpty) {
      return const <FriendProfile>[];
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyWithUser(_cachedFriendsKey, userId));
    if (raw == null || raw.isEmpty) {
      return const <FriendProfile>[];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const <FriendProfile>[];
    }
    return decoded
        .whereType<Map>()
        .map((item) => _friendFromJson(item))
        .whereType<FriendProfile>()
        .toList();
  }

  Future<void> saveCachedFriends(
    String userId,
    List<FriendProfile> items,
  ) async {
    if (userId.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final payload = items.map(_friendToJson).toList();
    await prefs.setString(
      _keyWithUser(_cachedFriendsKey, userId),
      jsonEncode(payload),
    );
  }

  /// 本机缓存：按会话读取最近 N 条聊天记录，弱网时先显示缓存再等实时流。
  Future<List<ChatMessage>> loadCachedMessages({
    required String conversationId,
    required String currentUserId,
  }) async {
    if (conversationId.isEmpty || currentUserId.isEmpty) {
      return const [];
    }
    final prefs = await SharedPreferences.getInstance();
    final key = '${_cachedMessagesPrefix}${currentUserId}_$conversationId';
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const [];
    }
    return decoded
        .whereType<Map>()
        .map((item) => ChatMessage.fromJson(
              Map<String, dynamic>.from(item),
              currentUserId: currentUserId,
            ))
        .toList();
  }

  /// 保存该会话的聊天记录到本机（仅保留最近 [_maxCachedMessagesPerConversation] 条）。
  Future<void> saveCachedMessages({
    required String conversationId,
    required String currentUserId,
    required List<ChatMessage> messages,
  }) async {
    if (conversationId.isEmpty || currentUserId.isEmpty) {
      return;
    }
    final toSave = messages.length > _maxCachedMessagesPerConversation
        ? messages.sublist(messages.length - _maxCachedMessagesPerConversation)
        : messages;
    final prefs = await SharedPreferences.getInstance();
    final key = '${_cachedMessagesPrefix}${currentUserId}_$conversationId';
    final payload = toSave.map((m) => m.toJson()).toList();
    await prefs.setString(key, jsonEncode(payload));
  }

  /// 本机缓存：好友申请列表，弱网时先显示缓存再等实时流。
  Future<List<FriendRequestItem>> loadCachedIncomingRequests(String userId) async {
    if (userId.isEmpty) return const [];
    final prefs = await SharedPreferences.getInstance();
    final key = _keyWithUser(_cachedIncomingRequestsKey, userId);
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) => FriendRequestItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> saveCachedIncomingRequests(
    String userId,
    List<FriendRequestItem> items,
  ) async {
    if (userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = _keyWithUser(_cachedIncomingRequestsKey, userId);
    await prefs.setString(key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  Future<void> setHiddenConversation(
    String conversationId,
    DateTime? hiddenAt,
  ) async {
    final raw = await _loadStringMap(_hiddenConversationsKey);
    if (hiddenAt == null) {
      raw.remove(conversationId);
    } else {
      raw[conversationId] = hiddenAt.toIso8601String();
    }
    await _saveStringMap(_hiddenConversationsKey, raw);
  }

  Future<void> setBlacklisted(String friendId, bool blocked) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_friendBlacklistKey)?.toSet() ?? <String>{};
    if (blocked) {
      current.add(friendId);
    } else {
      current.remove(friendId);
    }
    await prefs.setStringList(_friendBlacklistKey, current.toList());
  }

  Future<Map<String, String>> _loadStringMap(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return <String, String>{};
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return <String, String>{};
    }
    return decoded.map((key, value) => MapEntry('$key', '$value'));
  }

  Future<void> _saveStringMap(String key, Map<String, String> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(value));
  }

  String _remarkKeyById(String friendId) => 'id:$friendId';

  String _remarkKeyByName(String name) => 'name:$name';

  String _remarkKeyByEmail(String email) => 'email:$email';

  String _keyWithUser(String key, String userId) => '${key}_$userId';

  Map<String, dynamic> _conversationToJson(Conversation item) {
    return {
      'id': item.id,
      'title': item.title,
      'subtitle': item.subtitle,
      'lastMessage': item.lastMessage,
      'lastTime': item.lastTime?.toIso8601String(),
      'peerId': item.peerId,
      'avatarText': item.avatarText,
      'avatarUrl': item.avatarUrl,
      'unreadCount': item.unreadCount,
      'isGroup': item.isGroup,
      'lastMessageSenderId': item.lastMessageSenderId,
    };
  }

  Conversation? _conversationFromJson(Map item) {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) {
      return null;
    }
    return Conversation(
      id: id,
      title: item['title']?.toString() ?? '',
      subtitle: item['subtitle']?.toString() ?? '',
      lastMessage: item['lastMessage']?.toString() ?? '',
      lastTime: DateTime.tryParse(item['lastTime']?.toString() ?? ''),
      peerId: item['peerId']?.toString(),
      avatarText: item['avatarText']?.toString(),
      avatarUrl: item['avatarUrl']?.toString(),
      unreadCount: int.tryParse(item['unreadCount']?.toString() ?? '') ?? 0,
      isGroup: item['isGroup'] == true,
      lastMessageSenderId: item['lastMessageSenderId']?.toString(),
    );
  }

  Map<String, dynamic> _friendToJson(FriendProfile item) {
    return {
      'userId': item.userId,
      'displayName': item.displayName,
      'email': item.email,
      'avatarUrl': item.avatarUrl,
      'status': item.status,
      'shortId': item.shortId,
      'level': item.level,
      'roleLabel': item.roleLabel,
    };
  }

  FriendProfile? _friendFromJson(Map item) {
    final userId = item['userId']?.toString() ?? '';
    if (userId.isEmpty) {
      return null;
    }
    return FriendProfile(
      userId: userId,
      displayName: item['displayName']?.toString() ?? '',
      email: item['email']?.toString() ?? '',
      avatarUrl: item['avatarUrl']?.toString(),
      status: item['status']?.toString() ?? 'offline',
      shortId: item['shortId']?.toString(),
      level: (item['level'] is int) ? item['level'] as int : int.tryParse(item['level']?.toString() ?? '') ?? 0,
      roleLabel: item['roleLabel']?.toString(),
    );
  }
}
