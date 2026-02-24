import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/firebase_bootstrap.dart';
import '../../core/network_error_helper.dart';
import '../../core/role_badge.dart';
import '../../core/supabase_bootstrap.dart';
import '../auth/login_page.dart';
import 'chat_detail_page.dart';
import 'add_friend_page.dart';
import 'chat_media_cache.dart';
import 'create_group_page.dart';
import 'friend_models.dart';
import 'friends_repository.dart';
import 'message_models.dart';
import 'messages_local_store.dart';
import 'messages_repository.dart';
import 'system_notifications_page.dart';

Widget _messagesAvatarPlaceholder(String initial) => Container(
      width: 40,
      height: 40,
      color: const Color(0xFF1A1C21),
      alignment: Alignment.center,
      child: Text(
        initial.isEmpty ? '?' : initial,
        style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 16),
      ),
    );

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  int _tabIndex = 0;
  final _repository = MessagesRepository();
  final _friendsRepository = FriendsRepository();
  final _localStore = MessagesLocalStore();
  int _lastRequestCount = 0;
  bool _startingChat = false;
  final _friendSearchController = TextEditingController();
  Set<String> _pinnedConversations = {};
  Map<String, String> _drafts = {};
  Map<String, String> _friendRemarks = {};
  Set<String> _blacklist = {};
  bool _showBlacklist = false;
  String _friendQuery = '';
  StreamSubscription<Map<String, String>>? _remarkSubscription;
  StreamSubscription<List<FriendProfile>>? _friendsSubscription;
  StreamSubscription<List<FriendRequestItem>>? _incomingRequestsSubscription;
  StreamSubscription<User?>? _authSubscription;
  int _pendingFriendRequestCount = 0;
  Map<String, DateTime> _hiddenConversations = {};
  final Set<String> _locallyRemoved = {};
  final Set<String> _cleanedConversationIds = {};
  List<Conversation> _cachedConversations = [];
  List<FriendProfile> _cachedFriends = [];
  List<FriendRequestItem> _cachedIncomingRequests = [];
  Timer? _cleanupTimer;
  bool _localStateLoaded = false;
  /// PC 双栏下在右侧内嵌展示的会话（不 push 全屏）
  Conversation? _selectedConversation;

  /// 仅当 Firebase 已初始化时返回当前用户，避免 macOS 等平台 [core/no-app] 崩溃
  User? get _currentUser =>
      FirebaseBootstrap.isReady ? FirebaseAuth.instance.currentUser : null;

  @override
  void initState() {
    super.initState();
    _friendSearchController.addListener(_handleFriendQuery);
    _conversationSearchController.addListener(() {
      if (mounted) setState(() => _conversationSearchQuery = _conversationSearchController.text.trim());
    });
    _loadLocalState();
    _subscribeRemarks();
    _subscribeFriends();
    _subscribeIncomingRequests();
    if (FirebaseBootstrap.isReady) {
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((_) {
        _subscribeIncomingRequests();
      });
    }
  }

  @override
  void dispose() {
    _friendSearchController.removeListener(_handleFriendQuery);
    _friendSearchController.dispose();
    _conversationSearchController.dispose();
    _remarkSubscription?.cancel();
    _friendsSubscription?.cancel();
    _incomingRequestsSubscription?.cancel();
    _authSubscription?.cancel();
    _cleanupTimer?.cancel();
    super.dispose();
  }

  void _subscribeIncomingRequests() {
    if (!FirebaseBootstrap.isReady) return;
    final userId = _currentUser?.uid ?? '';
    if (userId.isEmpty) return;
    _incomingRequestsSubscription?.cancel();
    _incomingRequestsSubscription = _friendsRepository
        .watchIncomingRequests(userId: userId)
        .listen((requests) {
      if (!mounted) return;
      final countIncreased = requests.length > _lastRequestCount;
      setState(() {
        _pendingFriendRequestCount = requests.length;
        if (countIncreased) _lastRequestCount = requests.length;
      });
      if (countIncreased && requests.length > 0 && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                requests.length == 1
                    ? '你有一条新的好友申请'
                    : '你有 ${requests.length} 条新的好友申请',
              ),
            ),
          );
        });
      }
    });
  }

  void _subscribeFriends() {
    final userId = _currentUser?.uid ?? '';
    if (userId.isEmpty) return;
    _friendsSubscription?.cancel();
    _friendsSubscription = _friendsRepository.watchFriends(userId: userId).listen((friends) {
      if (!mounted) return;
      setState(() {
        _cachedFriends = friends;
      });
      if (userId.isNotEmpty) {
        _localStore.saveCachedFriends(userId, friends);
      }
    });
  }

  void _handleFriendQuery() {
    final query = _friendSearchController.text.trim();
    if (query == _friendQuery) {
      return;
    }
    setState(() {
      _friendQuery = query;
    });
  }

  Future<void> _loadLocalState() async {
    final userId = _currentUser?.uid ?? '';
    final pins = await _localStore.loadPinnedConversations();
    final drafts = await _localStore.loadDrafts();
    final remarks = await _localStore.loadFriendRemarks();
    final blacklist = await _localStore.loadBlacklist();
    final hidden = await _localStore.loadHiddenConversations();
    final cachedConversations =
        await _localStore.loadCachedConversations(userId);
    final cachedFriends = await _localStore.loadCachedFriends(userId);
    final cachedRequests = await _localStore.loadCachedIncomingRequests(userId);
    if (!mounted) return;
    setState(() {
      _pinnedConversations = pins;
      _drafts = drafts;
      _friendRemarks = remarks;
      _blacklist = blacklist;
      _hiddenConversations = hidden;
      _cachedConversations = cachedConversations;
      _cachedFriends = cachedFriends;
      _cachedIncomingRequests = cachedRequests;
      _pendingFriendRequestCount = cachedRequests.length;
      _localStateLoaded = true;
    });
  }

  void _subscribeRemarks() {
    final userId = _currentUser?.uid;
    if (userId == null || userId.isEmpty) {
      return;
    }
    _remarkSubscription?.cancel();
    _remarkSubscription = _friendsRepository
        .watchRemarks(userId: userId)
        .listen((remarks) {
      if (!mounted) return;
      setState(() {
        _friendRemarks = remarks;
      });
    });
  }

  List<Conversation> _sortConversations(List<Conversation> items) {
    final sorted = [...items];
    sorted.sort((a, b) {
      final ap = _pinnedConversations.contains(a.id);
      final bp = _pinnedConversations.contains(b.id);
      if (ap != bp) {
        return ap ? -1 : 1;
      }
      final at = a.lastTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.lastTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });
    return sorted;
  }

  List<Conversation> _applyHiddenConversations(List<Conversation> items) {
    if (_hiddenConversations.isEmpty) {
      return items.where((item) => !_locallyRemoved.contains(item.id)).toList();
    }
    final nextHidden = {..._hiddenConversations};
    final removedLocal = {..._locallyRemoved};
    final visible = <Conversation>[];
    for (final convo in items) {
      if (removedLocal.contains(convo.id)) {
        continue;
      }
      final hiddenAt = nextHidden[convo.id];
      if (hiddenAt == null) {
        visible.add(convo);
        continue;
      }
      final lastTime = convo.lastTime;
      final hasNewerMessage =
          lastTime != null && lastTime.isAfter(hiddenAt);
      final hasUnread = convo.unreadCount > 0;
      if (hasNewerMessage || hasUnread) {
        nextHidden.remove(convo.id);
        // 仅「删除会话」的会话会因新消息再次显示；在 removedLocal 的是删好友导致的，上面已 continue
        visible.add(convo);
      }
    }
    if (!mapEquals(nextHidden, _hiddenConversations) ||
        !setEquals(removedLocal, _locallyRemoved)) {
      final removed = _hiddenConversations.keys
          .where((key) => !nextHidden.containsKey(key))
          .toList();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _hiddenConversations = nextHidden;
          _locallyRemoved
            ..clear()
            ..addAll(removedLocal);
        });
        for (final entry in _hiddenConversations.entries) {
          _localStore.setHiddenConversation(entry.key, entry.value);
        }
        for (final key in removed) {
          _localStore.setHiddenConversation(key, null);
        }
      });
    }
    return visible;
  }

  /// 仅保留与当前好友的私聊会话；群聊全部保留。
  List<Conversation> _filterConversationsByFriends(
    List<Conversation> items,
    Set<String> friendIds,
  ) {
    if (friendIds.isEmpty) {
      return items.where((c) => c.isGroup).toList();
    }
    return items.where((c) {
      if (c.isGroup) return true;
      final peerId = c.peerId;
      if (peerId == null || peerId.isEmpty) return false;
      return friendIds.contains(peerId);
    }).toList();
  }

  List<Conversation> _dedupeDirectConversations(List<Conversation> items) {
    final kept = <Conversation>[];
    final byPeer = <String, Conversation>{};
    for (final convo in items) {
      if (convo.isGroup) {
        kept.add(convo);
        continue;
      }
      final key = (convo.peerId != null && convo.peerId!.isNotEmpty)
          ? convo.peerId!
          : convo.title;
      if (key.isEmpty) {
        kept.add(convo);
        continue;
      }
      final existing = byPeer[key];
      if (existing == null) {
        byPeer[key] = convo;
        continue;
      }
      final existingTime =
          existing.lastTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final currentTime =
          convo.lastTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (currentTime.isAfter(existingTime)) {
        byPeer[key] = convo;
      }
    }
    kept.addAll(byPeer.values);
    return kept;
  }

  void _cleanupDuplicateDirectConversations(List<Conversation> items) {
    final currentUserId = _currentUser?.uid ?? '';
    if (currentUserId.isEmpty) {
      return;
    }
    final byPeer = <String, List<Conversation>>{};
    for (final convo in items) {
      if (convo.isGroup) {
        continue;
      }
      final key = (convo.peerId != null && convo.peerId!.isNotEmpty)
          ? convo.peerId!
          : convo.title;
      if (key.isEmpty) {
        continue;
      }
      byPeer.putIfAbsent(key, () => <Conversation>[]).add(convo);
    }
    for (final entry in byPeer.entries) {
      final list = entry.value;
      if (list.length <= 1) {
        continue;
      }
      list.sort((a, b) {
        final at = a.lastTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.lastTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      final keep = list.first.id;
      final extras = list.skip(1).map((item) => item.id).toList();
      for (final id in extras) {
        if (_cleanedConversationIds.contains(id)) {
          continue;
        }
        _cleanedConversationIds.add(id);
        _repository.removeConversationForUser(
          conversationId: id,
          userId: currentUserId,
        );
      }
      _cleanedConversationIds.add(keep);
    }
  }

  void _scheduleConversationCleanup(List<Conversation> items) {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer(const Duration(milliseconds: 300), () {
      _cleanupDuplicateDirectConversations(items);
    });
  }

  void _togglePin(String conversationId) {
    final next = {..._pinnedConversations};
    if (next.contains(conversationId)) {
      next.remove(conversationId);
    } else {
      next.add(conversationId);
    }
    setState(() {
      _pinnedConversations = next;
    });
    _localStore.savePinnedConversations(next);
  }

  String _resolveFriendName(FriendProfile friend) {
    final remark = _friendRemarks['id:${friend.userId}'] ??
        _friendRemarks[friend.userId];
    if (remark != null && remark.trim().isNotEmpty) {
      return remark.trim();
    }
    return friend.displayName;
  }

  String _resolveConversationTitle(Conversation conversation) {
    final peerId = conversation.peerId;
    final me = _currentUser;
    final myName = (me?.displayName?.trim().isNotEmpty == true
            ? me!.displayName!.trim()
            : me?.email?.split('@').first ?? '')
        .trim();

    // 私聊：优先用备注，再用手好友资料里的名字；绝不在会话列表显示自己的名字
    if (peerId != null && peerId.isNotEmpty) {
      final remark = _friendRemarks['id:$peerId'] ??
          _friendRemarks[peerId] ??
          _friendRemarks['name:${conversation.title}'] ??
          _friendRemarks['email:${conversation.title}'] ??
          _friendRemarks[conversation.title];
      if (remark != null && remark.trim().isNotEmpty) {
        return remark.trim();
      }
      for (final f in _cachedFriends) {
        if (f.userId == peerId) {
          final name = _resolveFriendName(f);
          if (name.trim().isNotEmpty && name.trim() != myName) return name;
          return '未设置昵称';
        }
      }
      // 没有好友资料或后端 title 存错了：若是自己的名字则显示占位
      final fallback = conversation.title.trim();
      if (fallback.isEmpty || fallback == myName) return '未设置昵称';
      return fallback;
    }
    return conversation.title;
  }

  List<FriendProfile> _filterFriends(List<FriendProfile> friends) {
    final query = _friendQuery.toLowerCase();
    return friends.where((friend) {
      if (_blacklist.contains(friend.userId)) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      final name = _resolveFriendName(friend).toLowerCase();
      final email = friend.email.toLowerCase();
      final shortId = (friend.shortId ?? '').toLowerCase();
      return name.contains(query) ||
          email.contains(query) ||
          shortId.contains(query);
    }).toList();
  }

  List<FriendProfile> _filterBlacklisted(List<FriendProfile> friends) {
    final query = _friendQuery.toLowerCase();
    return friends.where((friend) {
      if (!_blacklist.contains(friend.userId)) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      final name = _resolveFriendName(friend).toLowerCase();
      final email = friend.email.toLowerCase();
      final shortId = (friend.shortId ?? '').toLowerCase();
      return name.contains(query) ||
          email.contains(query) ||
          shortId.contains(query);
    }).toList();
  }

  Widget _buildFriendSearchBar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          TextField(
            controller: _friendSearchController,
            decoration: const InputDecoration(
              hintText: '搜索好友/备注/账号ID',
              isDense: true,
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlacklistToggle() {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: () {
          setState(() {
            _showBlacklist = !_showBlacklist;
          });
        },
        icon: Icon(
          _showBlacklist ? Icons.visibility_off : Icons.visibility,
          size: 18,
        ),
        label: Text(_showBlacklist ? '隐藏黑名单' : '显示黑名单'),
      ),
    );
  }

  Widget _buildBlacklistSection() {
    return StreamBuilder<List<FriendProfile>>(
      stream: _friendsRepository.watchFriends(
        userId: _currentUser?.uid ?? '',
      ),
      builder: (context, snapshot) {
        final friends = snapshot.data ?? const <FriendProfile>[];
        final blacklisted = _filterBlacklisted(friends);
        if (blacklisted.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const _SectionTitle(title: '黑名单'),
            const SizedBox(height: 8),
            ...blacklisted.map((friend) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 0),
                child: _FriendCard(
                  name: _resolveFriendName(friend),
                  subtitle: friend.shortId?.trim().isNotEmpty == true
                      ? '账号ID ${friend.shortId!.trim()}'
                      : '账号ID —',
                  status: '已拉黑',
                  avatarText:
                      friend.displayName.isEmpty ? '用' : friend.displayName[0],
                  avatarUrl: friend.avatarUrl,
                  levelLabel: 'Lv ${friend.level}',
                  roleLabel: friend.roleLabel,
                  onTap: () {},
                  onMore: () => _showFriendActions(context, friend),
                ),
              );
            }).toList(),
          ],
        );
      },
    );
  }

  void _showFriendActions(BuildContext context, FriendProfile friend) {
    final isBlocked = _blacklist.contains(friend.userId);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0E0F14),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('设置备注名'),
                onTap: () {
                  Navigator.of(context).pop();
                  _editRemark(context, friend);
                },
              ),
              ListTile(
                leading:
                    Icon(isBlocked ? Icons.lock_open : Icons.block_outlined),
                title: Text(isBlocked ? '移出黑名单' : '加入黑名单'),
                onTap: () {
                  Navigator.of(context).pop();
                  _toggleBlacklist(friend);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('删除好友'),
                onTap: () {
                  Navigator.of(context).pop();
                  _confirmDeleteFriend(context, friend);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editRemark(BuildContext context, FriendProfile friend) async {
    final controller = TextEditingController(
      text: _friendRemarks['id:${friend.userId}'] ??
          _friendRemarks[friend.userId] ??
          '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('设置备注名'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: '输入备注名'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    if (result == null) return;
    final current = _currentUser;
    if (current == null) return;
    await _friendsRepository.saveRemark(
      userId: current.uid,
      friendId: friend.userId,
      remark: result,
    );
  }

  Future<void> _toggleBlacklist(FriendProfile friend) async {
    final isBlocked = _blacklist.contains(friend.userId);
    await _localStore.setBlacklisted(friend.userId, !isBlocked);
    if (!mounted) return;
    final next = {..._blacklist};
    if (isBlocked) {
      next.remove(friend.userId);
    } else {
      next.add(friend.userId);
    }
    setState(() {
      _blacklist = next;
    });
  }

  final _conversationSearchController = TextEditingController();
  String _conversationSearchQuery = '';

  bool get _isPcLayout =>
      MediaQuery.sizeOf(context).width >= 1100;

  @override
  Widget build(BuildContext context) {
    final firebaseReady = FirebaseBootstrap.isReady;
    final supabaseReady = SupabaseBootstrap.isReady;
    final user = _currentUser;
    final userId = user?.uid ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0F),
      body: SafeArea(
        child: firebaseReady && supabaseReady && _currentUser != null && _isPcLayout
            ? _buildPcTwoPaneLayout(context, userId)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildChatStyleHeader(context, firebaseReady, supabaseReady),
                  if (firebaseReady && supabaseReady && _currentUser != null) ...[
                    _buildSearchBar(context),
                    _buildWeChatTabs(context),
                    Expanded(
                      child: _buildBodyContent(context, userId, firebaseReady, supabaseReady),
                    ),
                  ] else
                    Expanded(
                      child: _buildLoginOrConfigPrompt(context, firebaseReady, supabaseReady),
                    ),
                ],
              ),
      ),
    );
  }

  /// PC 端双栏：左侧会话列表，右侧聊天窗口（空状态或占位）
  Widget _buildPcTwoPaneLayout(BuildContext context, String userId) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 380,
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D0F),
            border: Border(right: BorderSide(color: const Color(0xFF2A2D34), width: 1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildChatStyleHeader(context, true, true),
              _buildSearchBar(context),
              _buildWeChatTabs(context),
              Expanded(
                child: _buildBodyContent(context, userId, true, true),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: const Color(0xFF111318),
            child: _selectedConversation == null
                ? const _ChatWindowPlaceholder()
                : ChatDetailPage(
                    conversation: _selectedConversation!,
                    initialMessages: const <ChatMessage>[],
                    onCloseForEmbed: () {
                      if (mounted) setState(() => _selectedConversation = null);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildChatStyleHeader(
    BuildContext context,
    bool firebaseReady,
    bool supabaseReady,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0F),
        border: Border(bottom: BorderSide(color: const Color(0xFF2A2D34), width: 0.6)),
      ),
      child: Row(
        children: [
          Text(
            '消息',
            style: const TextStyle(
              color: Color(0xFFE8D5A3),
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 22),
            color: const Color(0xFF9CA3AF),
            onPressed: () => _openAddFriend(context),
            tooltip: '添加好友',
          ),
          IconButton(
            icon: const Icon(Icons.group_add_outlined, size: 22),
            color: const Color(0xFF9CA3AF),
            onPressed: () => _openCreateGroup(context),
            tooltip: '创建群聊',
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined, size: 22),
                color: const Color(0xFF9CA3AF),
                onPressed: () => _openSystemNotifications(context),
                tooltip: '系统消息',
              ),
              if (_pendingFriendRequestCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF07C160),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _pendingFriendRequestCount > 99 ? '99+' : '$_pendingFriendRequestCount',
                      style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        controller: _tabIndex == 0 ? _conversationSearchController : _friendSearchController,
        onChanged: (_) {
          setState(() {
            if (_tabIndex == 0) _conversationSearchQuery = _conversationSearchController.text.trim();
          });
        },
        decoration: InputDecoration(
          hintText: _tabIndex == 0 ? '搜索会话' : '搜索好友',
          hintStyle: const TextStyle(color: Color(0xFF6C6F77), fontSize: 14),
          prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF6C6F77)),
          filled: true,
          fillColor: const Color(0xFF1A1C21),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          isDense: true,
        ),
        style: const TextStyle(color: Color(0xFFE8D5A3), fontSize: 14),
      ),
    );
  }

  Widget _buildWeChatTabs(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          _WeChatTab(
            label: '最近会话',
            selected: _tabIndex == 0,
            onTap: () => setState(() => _tabIndex = 0),
          ),
          const SizedBox(width: 24),
          _WeChatTab(
            label: '好友列表',
            selected: _tabIndex == 1,
            onTap: () => setState(() => _tabIndex = 1),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginOrConfigPrompt(
    BuildContext context,
    bool firebaseReady,
    bool supabaseReady,
  ) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (!firebaseReady)
          _ConfigCard(
            icon: Icons.warning_amber_outlined,
            title: '未配置 Firebase',
            subtitle: '请先添加配置文件后再使用消息功能',
            onTap: () {},
          )
        else if (!supabaseReady)
          _ConfigCard(
            icon: Icons.cloud_off_outlined,
            title: '未配置 Supabase',
            subtitle: '请配置 SUPABASE_URL / SUPABASE_ANON_KEY',
            onTap: () {},
          )
        else if (_currentUser == null)
          _ConfigCard(
            icon: Icons.lock_outline,
            title: '登录后使用聊天功能',
            subtitle: '支持邮箱、Google、Apple 登录',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LoginPage()),
              );
            },
          ),
      ],
    );
  }

  Widget _buildBodyContent(
    BuildContext context,
    String userId,
    bool firebaseReady,
    bool supabaseReady,
  ) {
    if (_tabIndex == 0) {
      return StreamBuilder<List<Conversation>>(
        stream: _repository.watchConversations(userId: userId),
        initialData: _cachedConversations,
        builder: (context, snapshot) {
          final hasValidStream = snapshot.connectionState == ConnectionState.active && !snapshot.hasError;
          final items = snapshot.data;
          if (hasValidStream && items != null) {
            _cachedConversations = items;
            if (userId.isNotEmpty) {
              _localStore.saveCachedConversations(userId, items);
            }
            _scheduleConversationCleanup(items);
          }
          if (!_localStateLoaded) {
            return const Center(
              child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF07C160))),
            );
          }
          final sourceItems = hasValidStream && items != null ? items : _cachedConversations;
          final friendIds = _cachedFriends.map((f) => f.userId).toSet();
          final onlyFriends = _filterConversationsByFriends(sourceItems, friendIds);
          final visible = _applyHiddenConversations(onlyFriends);
          final deduped = _dedupeDirectConversations(visible);
          final sorted = _sortConversations(deduped);
          final filtered = _conversationSearchQuery.isEmpty
              ? sorted
              : sorted.where((c) {
                  final title = _resolveConversationTitle(c).toLowerCase();
                  final msg = c.lastMessage.toLowerCase();
                  final q = _conversationSearchQuery.toLowerCase();
                  return title.contains(q) || msg.contains(q);
                }).toList();
          if (filtered.isEmpty) {
            return Center(
              child: Text(
                _conversationSearchQuery.isEmpty ? '暂无会话' : '未找到匹配的会话',
                style: const TextStyle(color: Color(0xFF6C6F77), fontSize: 14),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => Divider(height: 1, indent: 72, color: const Color(0xFF2A2D34).withValues(alpha: 0.6)),
            itemBuilder: (_, i) => _buildConversationItem(context, filtered[i]),
          );
        },
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        StreamBuilder<List<FriendRequestItem>>(
              stream: _friendsRepository.watchIncomingRequests(userId: userId),
              initialData: _cachedIncomingRequests,
              builder: (context, snapshot) {
                final requests = snapshot.data ?? _cachedIncomingRequests;
                if (snapshot.hasData && snapshot.data != null && userId.isNotEmpty) {
                  _cachedIncomingRequests = snapshot.data!;
                  _localStore.saveCachedIncomingRequests(userId, _cachedIncomingRequests);
                }
                if (requests.isNotEmpty && requests.length != _lastRequestCount) {
                  _lastRequestCount = requests.length;
                }
                if (requests.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        '好友申请',
                        style: const TextStyle(
                          color: Color(0xFF6C6F77),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    ...requests.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 0),
                        child: _FriendRequestCard(
                          item: item,
                          onAccept: () => _acceptRequest(context, item),
                          onReject: () => _rejectRequest(context, item),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                );
              },
            ),
            StreamBuilder<List<FriendProfile>>(
              stream: _friendsRepository.watchFriends(userId: userId),
              initialData: _cachedFriends,
              builder: (context, snapshot) {
                final hasValidStream = snapshot.connectionState == ConnectionState.active && !snapshot.hasError;
                final friends = snapshot.data;
                if (hasValidStream && friends != null) {
                  _cachedFriends = friends;
                  if (userId.isNotEmpty) {
                    _localStore.saveCachedFriends(userId, friends);
                  }
                }
                if (!_localStateLoaded) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                  );
                }
                final sourceFriends = hasValidStream && friends != null ? friends : _cachedFriends;
                final filtered = _filterFriends(sourceFriends);
                final blacklisted = _filterBlacklisted(sourceFriends);
                if (filtered.isEmpty && (!_showBlacklist || blacklisted.isEmpty)) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        '暂无好友',
                        style: TextStyle(color: Color(0xFF6C6F77)),
                      ),
                    ),
                  );
                }
                return Column(
                  children: sourceFriends
                      .where((friend) => filtered.contains(friend))
                      .map(
                        (friend) => Padding(
                          padding: const EdgeInsets.only(bottom: 0),
                          child: _FriendCard(
                            name: _resolveFriendName(friend),
                            subtitle: friend.shortId?.trim().isNotEmpty == true
                                ? '账号ID ${friend.shortId!.trim()}'
                                : '账号ID —',
                            status: friend.status == 'online' ? '在线' : '离线',
                            avatarText:
                                friend.displayName.isEmpty ? '用' : friend.displayName[0],
                            avatarUrl: friend.avatarUrl,
                            levelLabel: 'Lv ${friend.level}',
                            roleLabel: friend.roleLabel,
                            onTap: () => _openDirectChat(context, friend),
                            onLongPress: () =>
                                _confirmDeleteFriend(context, friend),
                            onMore: () => _showFriendActions(context, friend),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            if (_showBlacklist) _buildBlacklistSection(),
            const SizedBox(height: 8),
            _buildBlacklistToggle(),
          ],
        );
  }

  void _guardAuth(BuildContext context) {
    if (_currentUser == null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('功能正在开发中')),
    );
  }

  void _openCreateGroup(BuildContext context) {
    if (_currentUser == null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      return;
    }
    Navigator.of(context)
        .push<Conversation>(
          MaterialPageRoute(builder: (_) => const CreateGroupPage()),
        )
        .then((conversation) {
      if (conversation != null && mounted) {
        _openConversation(context, conversation);
      }
    });
  }

  void _openSystemNotifications(BuildContext context) {
    if (_currentUser == null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SystemNotificationsPage()),
    );
  }

  void _openConversation(BuildContext context, Conversation conversation) {
    if (_currentUser == null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      return;
    }
    if (_isPcLayout) {
      setState(() => _selectedConversation = conversation);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatDetailPage(
          conversation: conversation,
          initialMessages: const <ChatMessage>[],
        ),
      ),
    ).then((_) {
      if (mounted) _loadLocalState();
    });
  }

  Widget _buildConversationItem(
    BuildContext context,
    Conversation conversation,
  ) {
    final draft = _drafts[conversation.id];
    final displayTitle = _resolveConversationTitle(conversation);
    final peerId = conversation.peerId;
    FriendProfile? peerProfile;
    if (peerId != null && peerId.isNotEmpty) {
      for (final f in _cachedFriends) {
        if (f.userId == peerId) {
          peerProfile = f;
          break;
        }
      }
    }
    final avatarUrl = conversation.isGroup
        ? conversation.avatarUrl
        : peerProfile?.avatarUrl;
    final levelLabel = peerProfile != null ? 'Lv ${peerProfile.level}' : null;
    final roleLabel = peerProfile?.roleLabel;
    return Padding(
      padding: const EdgeInsets.only(bottom: 0),
        child: Dismissible(
        key: ValueKey('conversation-${conversation.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: Colors.red.shade700,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        confirmDismiss: (_) async {
          _hideConversation(conversation);
          return true;
        },
        child: _ConversationCard(
          conversation: conversation,
          displayTitle: displayTitle,
          avatarUrl: avatarUrl,
          levelLabel: levelLabel,
          roleLabel: roleLabel,
          draft: draft,
          pinned: _pinnedConversations.contains(conversation.id),
          currentUserId: _currentUser?.uid ?? '',
          onTap: () => _openConversation(context, conversation),
          onLongPress: () => _showConversationActions(context, conversation),
        ),
      ),
    );
  }

  /// 仅删除会话（不删好友）：从列表隐藏并清空草稿；有新消息时会再次显示。
  void _hideConversation(Conversation conversation) {
    final hiddenAt = DateTime.now();
    final nextHidden = {..._hiddenConversations, conversation.id: hiddenAt};
    setState(() {
      _hiddenConversations = nextHidden;
      // 不加入 _locallyRemoved，这样有新消息时会再次显示
    });
    _localStore.setHiddenConversation(conversation.id, hiddenAt);
    _localStore.saveDraft(conversation.id, '');
    final nextPins = {..._pinnedConversations}..remove(conversation.id);
    setState(() => _pinnedConversations = nextPins);
    _localStore.savePinnedConversations(nextPins);
  }

  void _showConversationActions(
    BuildContext context,
    Conversation conversation,
  ) {
    final isPinned = _pinnedConversations.contains(conversation.id);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0E0F14),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined),
                title: Text(isPinned ? '取消置顶' : '置顶'),
                onTap: () {
                  Navigator.of(context).pop();
                  _togglePin(conversation.id);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('删除会话'),
                onTap: () {
                  Navigator.of(context).pop();
                  _hideConversation(conversation);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _openAddFriend(BuildContext context) {
    if (_currentUser == null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddFriendPage()),
    );
  }

  Future<void> _acceptRequest(
    BuildContext context,
    FriendRequestItem item,
  ) async {
    final current = _currentUser;
    if (current == null) {
      return;
    }
    try {
      await _friendsRepository.acceptRequest(
        requestId: item.requestId,
        requesterId: item.requesterId,
        receiverId: current.uid,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已同意好友申请')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(NetworkErrorHelper.messageForUser(error, prefix: '操作失败'))),
      );
    }
  }

  Future<void> _rejectRequest(
    BuildContext context,
    FriendRequestItem item,
  ) async {
    try {
      await _friendsRepository.rejectRequest(requestId: item.requestId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已拒绝好友申请')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(NetworkErrorHelper.messageForUser(error, prefix: '操作失败'))),
      );
    }
  }

  /// 从好友列表点击：始终创建/获取与该好友的单聊并打开；清掉栈上已有聊天页再压入私聊，避免误进群聊。
  Future<void> _openDirectChat(
    BuildContext context,
    FriendProfile friend,
  ) async {
    final current = _currentUser;
    if (current == null) return;
    if (_startingChat) return;
    setState(() => _startingChat = true);
    try {
      final conversation = await _repository.createOrGetDirectConversation(
        currentUserId: current.uid,
        friendId: friend.userId,
        friendName: friend.displayName,
      );
      if (!context.mounted) return;
      if (conversation.isGroup) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('打开私聊失败，请重试')),
          );
        }
        return;
      }
      if (_isPcLayout) {
        if (mounted) setState(() => _selectedConversation = conversation);
        return;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => ChatDetailPage(
            conversation: conversation,
            initialMessages: const <ChatMessage>[],
          ),
        ),
        (route) => route.isFirst,
      ).then((_) {
        if (mounted) _loadLocalState();
      });
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(NetworkErrorHelper.messageForUser(error, prefix: '打开私聊失败')),
        ),
      );
    } finally {
      if (mounted) setState(() => _startingChat = false);
    }
  }

  Future<void> _confirmDeleteFriend(
    BuildContext context,
    FriendProfile friend,
  ) async {
    final current = _currentUser;
    if (current == null) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('删除好友'),
          content: Text('确定删除 ${friend.displayName} 吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (result != true) return;
    await _friendsRepository.deleteFriend(
      userId: current.uid,
      friendId: friend.userId,
    );
    await _hideConversationsForFriend(
      currentUserId: current.uid,
      friendId: friend.userId,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('好友已删除')),
    );
  }

  Future<void> _hideConversationsForFriend({
    required String currentUserId,
    required String friendId,
  }) async {
    try {
      final ids = await _repository.findDirectConversationIds(
        currentUserId: currentUserId,
        friendId: friendId,
      );
      if (ids.isEmpty) {
        return;
      }
      final hiddenAt = DateTime.now();
      final nextHidden = {..._hiddenConversations};
      for (final id in ids) {
        nextHidden[id] = hiddenAt;
        _locallyRemoved.add(id);
        _localStore.setHiddenConversation(id, hiddenAt);
      }
      if (!mounted) return;
      setState(() {
        _hiddenConversations = nextHidden;
      });
    } catch (_) {
      // Ignore local hide failures.
    }
  }
}

/// PC 端右侧聊天区空状态：深色背景 + 图标与文案
class _ChatWindowPlaceholder extends StatelessWidget {
  const _ChatWindowPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1C21),
              borderRadius: BorderRadius.circular(40),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 40,
              color: const Color(0xFF6C6F77),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '选择会话开始聊天',
            style: TextStyle(
              color: const Color(0xFF9CA3AF).withValues(alpha: 0.9),
              fontSize: 15,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '在左侧点击任一会话即可打开',
            style: TextStyle(
              color: const Color(0xFF6C6F77),
              fontSize: 13,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeChatTab extends StatelessWidget {
  const _WeChatTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? const Color(0xFF07C160) : const Color(0xFF6C6F77),
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              height: 2,
              width: 24,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF07C160) : Colors.transparent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfigCard extends StatelessWidget {
  const _ConfigCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1A1C21),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFFD4AF37)),
        title: Text(title, style: const TextStyle(color: Color(0xFFE8D5A3))),
        subtitle: Text(subtitle, style: const TextStyle(color: Color(0xFF6C6F77), fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: Color(0xFF6C6F77)),
        onTap: onTap,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFFD4AF37),
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.title,
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final showBadge = badgeCount > 0;
    const iconColor = Color(0xFFD4AF37);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 28, color: iconColor),
                  if (showBadge)
                    Positioned(
                      right: -6,
                      top: -4,
                      child: Container(
                        padding: badgeCount > 9
                            ? const EdgeInsets.symmetric(horizontal: 4, vertical: 1)
                            : const EdgeInsets.all(3),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.error,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentTabs extends StatelessWidget {
  const _SegmentTabs({
    required this.leftLabel,
    required this.rightLabel,
    required this.index,
    required this.onChanged,
  });

  final String leftLabel;
  final String rightLabel;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF111215),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2D34)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentTab(
              label: leftLabel,
              selected: index == 0,
              onTap: () => onChanged(0),
            ),
          ),
          Expanded(
            child: _SegmentTab(
              label: rightLabel,
              selected: index == 1,
              onTap: () => onChanged(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentTab extends StatelessWidget {
  const _SegmentTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFD4AF37) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.black : const Color(0xFFD4AF37),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.dense = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(dense ? 12 : 14),
          child: Row(
            children: [
              Container(
                width: dense ? 34 : 40,
                height: dense ? 34 : 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF111215),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2A2D34)),
                ),
                child: Icon(icon, color: const Color(0xFFD4AF37)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6C6F77),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _FriendCard extends StatelessWidget {
  const _FriendCard({
    required this.name,
    required this.subtitle,
    required this.status,
    required this.avatarText,
    this.avatarUrl,
    this.levelLabel,
    this.roleLabel,
    this.onTap,
    this.onLongPress,
    this.onMore,
  });

  final String name;
  final String subtitle;
  final String status;
  final String avatarText;
  final String? avatarUrl;
  final String? levelLabel;
  final String? roleLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMore;

  static Widget _levelTag(String text) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0x1AD4AF37),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 11),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = status == '在线';
    final showAvatar = avatarUrl?.trim().isNotEmpty == true;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Stack(
                children: [
                  showAvatar
                      ? ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: avatarUrl!.trim(),
                            cacheManager: ChatMediaCache.instance,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => _messagesAvatarPlaceholder(avatarText),
                            errorWidget: (_, __, ___) => _messagesAvatarPlaceholder(avatarText),
                          ),
                        )
                      : CircleAvatar(
                          radius: 24,
                          backgroundColor: const Color(0xFF2A2D34),
                          child: Text(
                            avatarText,
                            style: const TextStyle(color: Color(0xFF07C160)),
                          ),
                        ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isOnline ? const Color(0xFF07C160) : const Color(0xFF6C6F77),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF0D0D0F), width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Color(0xFFE8D5A3),
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF6C6F77)),
                          ),
                        ),
                        if (roleLabel != null && roleLabel!.isNotEmpty) RoleBadge(roleLabel: roleLabel!),
                        if (levelLabel != null && levelLabel!.isNotEmpty) _levelTag(levelLabel!),
                        const SizedBox(width: 6),
                        Text(
                          status,
                          style: TextStyle(
                            color: isOnline ? const Color(0xFF07C160) : const Color(0xFF6C6F77),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '更多',
                onPressed: onMore,
                icon: const Icon(Icons.more_vert, size: 20, color: Color(0xFF6C6F77)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FriendRequestCard extends StatelessWidget {
  const _FriendRequestCard({
    required this.item,
    required this.onAccept,
    required this.onReject,
  });

  final FriendRequestItem item;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF1A1C21),
                  child: Text(
                    item.requesterName.isEmpty ? '用' : item.requesterName[0],
                    style: const TextStyle(color: Color(0xFFD4AF37)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.requesterName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.requesterEmail,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6C6F77),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    child: const Text('拒绝'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: onAccept,
                    child: const Text('同意'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({
    required this.conversation,
    required this.onTap,
    this.onLongPress,
    this.draft,
    this.pinned = false,
    required this.displayTitle,
    this.avatarUrl,
    this.levelLabel,
    this.roleLabel,
    this.currentUserId = '',
  });

  final Conversation conversation;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? draft;
  final bool pinned;
  final String displayTitle;
  final String? avatarUrl;
  final String? levelLabel;
  final String? roleLabel;
  final String currentUserId;

  static const _avatarSize = 52.0;
  static const _green = Color(0xFF07C160);

  @override
  Widget build(BuildContext context) {
    final avatarText = _initial(conversation.avatarText ?? displayTitle);
    final showAvatar = avatarUrl?.trim().isNotEmpty == true;
    final hasDraft = draft != null && draft!.trim().isNotEmpty;
    final String subtitleText;
    if (hasDraft) {
      subtitleText = '草稿：${draft!.trim()}';
    } else if (conversation.lastMessage.trim().isNotEmpty &&
        conversation.lastMessageSenderId != null &&
        conversation.lastMessageSenderId == currentUserId) {
      subtitleText = '我: ${conversation.lastMessage}';
    } else {
      subtitleText = conversation.lastMessage;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                children: [
                  showAvatar
                      ? ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: avatarUrl!.trim(),
                            cacheManager: ChatMediaCache.instance,
                            width: _avatarSize,
                            height: _avatarSize,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => _messagesAvatarPlaceholder(avatarText),
                            errorWidget: (_, __, ___) => _messagesAvatarPlaceholder(avatarText),
                          ),
                        )
                      : CircleAvatar(
                          radius: _avatarSize / 2,
                          backgroundColor: const Color(0xFF2A2D34),
                          child: Text(
                            avatarText,
                            style: const TextStyle(color: Color(0xFF07C160), fontSize: 20),
                          ),
                        ),
                  if (pinned)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Color(0xFF0D0D0F),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.push_pin, size: 12, color: Color(0xFF07C160)),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayTitle,
                            style: const TextStyle(
                              color: Color(0xFFE8D5A3),
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (roleLabel != null && roleLabel!.isNotEmpty)
                          RoleBadge(roleLabel: roleLabel!, compact: true),
                        if (levelLabel != null && levelLabel!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Text(
                              levelLabel!,
                              style: const TextStyle(fontSize: 10, color: Color(0xFF6C6F77)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: hasDraft ? Colors.orange.shade300 : const Color(0xFF6C6F77),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    conversation.lastTimeLabel,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6C6F77)),
                  ),
                  if (conversation.unreadCount > 0) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _green,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        conversation.unreadCount > 99 ? '99+' : '${conversation.unreadCount}',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _initial(String text) {
    if (text.isEmpty) return '';
    return text[0];
  }
}
