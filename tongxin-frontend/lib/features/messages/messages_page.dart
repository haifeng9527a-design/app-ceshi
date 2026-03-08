import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/api_client.dart';
import '../../core/design/design_tokens.dart';
import '../../core/firebase_bootstrap.dart';
import '../../core/layout_mode.dart';
import '../../l10n/app_localizations.dart';
import '../../core/network_error_helper.dart';
import '../../core/role_badge.dart';
import '../../ui/components/components.dart';
import '../auth/login_page.dart';
import 'chat_detail_page.dart';
import 'add_friend_page.dart';
import 'customer_service_repository.dart';
import 'chat_media_cache.dart';
import 'create_group_page.dart';
import 'friend_models.dart';
import 'friends_repository.dart';
import 'message_models.dart';
import 'messages_local_store.dart';
import 'messages_repository.dart';
import 'system_notifications_page.dart';

Widget _messagesAvatarPlaceholder(String initial, [bool isGroup = false]) {
  if (isGroup) {
    return const CircleAvatar(
      radius: 26,
      backgroundColor: AppColors.borderFocus,
      child: Icon(Icons.people, color: AppColors.success, size: 26),
    );
  }
  return Container(
    width: 40,
    height: 40,
    color: AppColors.surfaceElevated,
    alignment: Alignment.center,
    child: Text(
      initial.isEmpty ? '?' : initial,
      style: const TextStyle(color: AppColors.primary, fontSize: 16),
    ),
  );
}

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
  final Set<String> _customerServiceIds = <String>{};
  Timer? _cleanupTimer;
  bool _localStateLoaded = false;
  Stream<List<Conversation>>? _conversationStream;
  String? _conversationStreamUserId;
  Key _conversationStreamKey = UniqueKey();
  Key _friendsStreamKey = UniqueKey();

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
      if (mounted)
        setState(() => _conversationSearchQuery =
            _conversationSearchController.text.trim());
    });
    _loadLocalState();
    _subscribeRemarks();
    _subscribeFriends();
    _subscribeIncomingRequests();
    _ensureCustomerServiceFriend();
    _refreshCustomerServiceIds();
    if (FirebaseBootstrap.isReady) {
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((_) {
        _subscribeFriends();
        _subscribeRemarks();
        _subscribeIncomingRequests();
        _ensureCustomerServiceFriend();
        _refreshCustomerServiceIds();
      });
    }
  }

  /// 确保已添加系统客服为好友（配置后进入消息页会自动补充）
  Future<void> _ensureCustomerServiceFriend() async {
    final userId = _currentUser?.uid ?? '';
    if (userId.isEmpty) return;
    try {
      final csId =
          await CustomerServiceRepository().getSystemCustomerServiceUserId();
      if (csId == null || csId.isEmpty) return;
      await _friendsRepository.ensureCustomerServiceFriend(
        userId: userId,
        customerServiceId: csId,
      );
    } catch (_) {
      // 静默失败
    }
  }

  Future<void> _refreshCustomerServiceIds() async {
    try {
      final repo = CustomerServiceRepository();
      final ids = <String>{};
      final systemId = await repo.getSystemCustomerServiceUserId();
      if (systemId != null && systemId.trim().isNotEmpty) {
        ids.add(systemId.trim());
      }
      final staffs = await repo.getAllCustomerServiceStaff();
      for (final id in staffs) {
        if (id.trim().isNotEmpty) {
          ids.add(id.trim());
        }
      }
      if (!mounted) return;
      setState(() {
        _customerServiceIds
          ..clear()
          ..addAll(ids);
      });
    } catch (_) {
      // 静默失败，不影响主流程
    }
  }

  void _ensureConversationStream(String userId, {bool forceRefresh = false}) {
    if (!forceRefresh &&
        _conversationStream != null &&
        _conversationStreamUserId == userId) {
      return;
    }
    _conversationStreamUserId = userId;
    _conversationStream = _repository
        .watchConversations(userId: userId)
        .asBroadcastStream();
    _conversationStreamKey = UniqueKey();
  }

  bool _isCustomerServiceFriend(FriendProfile friend) {
    final role = (friend.roleLabel ?? '').trim();
    return role == '客服' ||
        role.toLowerCase() == 'customer_service' ||
        _customerServiceIds.contains(friend.userId);
  }

  String _customerServiceDisplayName(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    return code.startsWith('en') ? 'Customer Service' : '客服';
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
      if (countIncreased && requests.isNotEmpty && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                requests.length == 1
                    ? AppLocalizations.of(context)!.msgNewFriendRequest
                    : AppLocalizations.of(context)!
                        .msgNewFriendRequests(requests.length),
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
    _friendsSubscription =
        _friendsRepository.watchFriends(userId: userId).listen((friends) {
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
    _remarkSubscription =
        _friendsRepository.watchRemarks(userId: userId).listen((remarks) {
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
      final hasNewerMessage = lastTime != null && lastTime.isAfter(hiddenAt);
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
    if (_isCustomerServiceFriend(friend)) {
      // 用户端固定显示客服身份，不暴露客服内部用户名。
      return _customerServiceDisplayName(context);
    }
    final remark =
        _friendRemarks['id:${friend.userId}'] ?? _friendRemarks[friend.userId];
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
          if (_isCustomerServiceFriend(f)) {
            return _customerServiceDisplayName(context);
          }
          final name = _resolveFriendName(f);
          if (name.trim().isNotEmpty && name.trim() != myName) return name;
          return AppLocalizations.of(context)!.msgNoNicknameSet;
        }
      }
      // 没有好友资料或后端 title 存错了：若是自己的名字则显示占位
      final fallback = conversation.title.trim();
      if (fallback.isEmpty || fallback == myName)
        return AppLocalizations.of(context)!.msgNoNicknameSet;
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
        label: Text(_showBlacklist
            ? AppLocalizations.of(context)!.msgHideBlacklist
            : AppLocalizations.of(context)!.msgShowBlacklist),
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
            _SectionTitle(title: AppLocalizations.of(context)!.msgBlacklist),
            const SizedBox(height: 8),
            ...blacklisted.map((friend) {
              final isCustomerService = _isCustomerServiceFriend(friend);
              return Padding(
                padding: const EdgeInsets.only(bottom: 0),
                child: _FriendCard(
                  name: _resolveFriendName(friend),
                  subtitle: isCustomerService
                      ? ''
                      : (friend.shortId?.trim().isNotEmpty == true
                          ? AppLocalizations.of(context)!
                              .profileAccountIdValue(friend.shortId!.trim())
                          : AppLocalizations.of(context)!.profileAccountIdDash),
                  avatarText: friend.displayName.isEmpty
                      ? AppLocalizations.of(context)!.commonUserInitial
                      : friend.displayName[0],
                  avatarUrl: friend.avatarUrl,
                  levelLabel: isCustomerService ? null : 'Lv ${friend.level}',
                  roleLabel:
                      isCustomerService ? 'customer_service' : friend.roleLabel,
                  onTap: () {},
                  onMore: () => _showFriendActions(context, friend),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  void _showFriendActions(BuildContext context, FriendProfile friend) {
    final isBlocked = _blacklist.contains(friend.userId);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.scaffold,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_note_rounded),
                title: Text(AppLocalizations.of(context)!.msgSetRemark),
                onTap: () {
                  Navigator.of(context).pop();
                  _editRemark(context, friend);
                },
              ),
              ListTile(
                leading: Icon(
                    isBlocked ? Icons.lock_open_rounded : Icons.block_rounded),
                title: Text(isBlocked
                    ? AppLocalizations.of(context)!.msgRemoveFromBlacklist
                    : AppLocalizations.of(context)!.msgAddToBlacklist),
                onTap: () {
                  Navigator.of(context).pop();
                  _toggleBlacklist(friend);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: Colors.redAccent),
                title: Text(AppLocalizations.of(context)!.msgDeleteFriend),
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
          title: Text(AppLocalizations.of(context)!.msgSetRemark),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.msgRemarkHint),
          ),
          actions: [
            AppButton(
              variant: AppButtonVariant.secondary,
              label: AppLocalizations.of(context)!.commonCancel,
              onPressed: () => Navigator.of(dialogContext).pop(null),
            ),
            AppButton(
              label: AppLocalizations.of(context)!.commonSave,
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
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

  bool get _isPcLayout => LayoutMode.useDesktopLikeLayout(context);

  bool get _apiReady => ApiClient.instance.isAvailable;

  @override
  Widget build(BuildContext context) {
    final firebaseReady = FirebaseBootstrap.isReady;
    final apiReady = _apiReady;
    final user = _currentUser;
    final userId = user?.uid ?? '';
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: firebaseReady && apiReady && _currentUser != null && _isPcLayout
            ? _buildPcTwoPaneLayout(context, userId)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildChatStyleHeader(context, firebaseReady, apiReady),
                  if (firebaseReady && apiReady && _currentUser != null) ...[
                    _buildSearchBar(context),
                    _buildWeChatTabs(context),
                    Expanded(
                      child: _buildBodyContent(
                          context, userId, firebaseReady, apiReady),
                    ),
                  ] else
                    Expanded(
                      child: _buildLoginOrConfigPrompt(
                          context, firebaseReady, apiReady),
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
          decoration: const BoxDecoration(
            color: AppColors.scaffold,
            border:
                Border(right: BorderSide(color: Color(0xFF2A2D34), width: 1)),
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
            color: AppColors.surface,
            child: _selectedConversation == null
                ? const _ChatWindowPlaceholder()
                : ChatDetailPage(
                    key: ValueKey(_selectedConversation!.id),
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
    bool apiReady,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      decoration: const BoxDecoration(
        color: AppColors.scaffold,
        border:
            Border(bottom: BorderSide(color: Color(0xFF2A2D34), width: 0.6)),
      ),
      child: Row(
        children: [
          Text(
            AppLocalizations.of(context)!.navMessages,
            style: AppTypography.subtitle,
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(AppIcons.addFriend, size: 22),
            color: AppColors.textSecondary,
            onPressed: () => _openAddFriend(context),
            tooltip: AppLocalizations.of(context)!.messagesAddFriend,
          ),
          IconButton(
            icon: const Icon(AppIcons.createGroup, size: 22),
            color: AppColors.textSecondary,
            onPressed: () => _openCreateGroup(context),
            tooltip: AppLocalizations.of(context)!.messagesCreateGroup,
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(AppIcons.notifications, size: 22),
                color: AppColors.textSecondary,
                onPressed: () => _openSystemNotifications(context),
                tooltip:
                    AppLocalizations.of(context)!.messagesSystemNotifications,
              ),
              if (_pendingFriendRequestCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    constraints:
                        const BoxConstraints(minWidth: 16, minHeight: 16),
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _pendingFriendRequestCount > 99
                          ? '99+'
                          : '$_pendingFriendRequestCount',
                      style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w600),
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
      child: AppInput(
        controller: _tabIndex == 0
            ? _conversationSearchController
            : _friendSearchController,
        onChanged: (_) {
          setState(() {
            if (_tabIndex == 0)
              _conversationSearchQuery =
                  _conversationSearchController.text.trim();
          });
        },
        hintText: _tabIndex == 0
            ? AppLocalizations.of(context)!.messagesSearchConversations
            : AppLocalizations.of(context)!.messagesSearchFriends,
        prefixIcon: const Icon(Icons.search, size: 20),
      ),
    );
  }

  Widget _buildWeChatTabs(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          _WeChatTab(
            label: AppLocalizations.of(context)!.messagesRecentChats,
            selected: _tabIndex == 0,
            onTap: () => setState(() => _tabIndex = 0),
          ),
          const SizedBox(width: 24),
          _WeChatTab(
            label: AppLocalizations.of(context)!.messagesFriendList,
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
    bool apiReady,
  ) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (!firebaseReady)
          _ConfigCard(
            icon: Icons.warning_amber_outlined,
            title: AppLocalizations.of(context)!.messagesFirebaseNotConfigured,
            subtitle: AppLocalizations.of(context)!.messagesAddConfigFirst,
            onTap: () {},
          )
        else if (!apiReady)
          _ConfigCard(
            icon: Icons.cloud_off_outlined,
            title: AppLocalizations.of(context)!.messagesApiNotConfigured,
            subtitle: AppLocalizations.of(context)!.messagesConfigureApi,
            onTap: () {},
          )
        else if (_currentUser == null)
          _ConfigCard(
            icon: Icons.lock_outline,
            title: AppLocalizations.of(context)!.messagesLoginToUseChat,
            subtitle: AppLocalizations.of(context)!.messagesLoginMethods,
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
    bool apiReady,
  ) {
    if (_tabIndex == 0) {
      _ensureConversationStream(userId);
      return StreamBuilder<List<Conversation>>(
        key: _conversationStreamKey,
        stream: _conversationStream,
        initialData: _cachedConversations,
        builder: (context, snapshot) {
          final hasValidStream =
              snapshot.connectionState == ConnectionState.active &&
                  !snapshot.hasError;
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
              child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF07C160))),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off,
                        size: 48, color: Colors.orange.shade300),
                    const SizedBox(height: 12),
                    Text(
                      NetworkErrorHelper.messageForUser(
                        snapshot.error,
                        l10n: AppLocalizations.of(context),
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Color(0xFF6C6F77), fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () => setState(
                        () => _ensureConversationStream(
                          userId,
                          forceRefresh: true,
                        ),
                      ),
                      icon: const Icon(AppIcons.retry, size: 18),
                      label: Text(AppLocalizations.of(context)!.commonRetry),
                    ),
                  ],
                ),
              ),
            );
          }
          final sourceItems =
              hasValidStream && items != null ? items : _cachedConversations;
          final friendIds = _cachedFriends.map((f) => f.userId).toSet();
          final onlyFriends =
              _filterConversationsByFriends(sourceItems, friendIds);
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
                _conversationSearchQuery.isEmpty
                    ? AppLocalizations.of(context)!.msgNoConversations
                    : AppLocalizations.of(context)!.msgNoMatchingConversations,
                style: const TextStyle(color: Color(0xFF6C6F77), fontSize: 14),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => Divider(
                height: 1,
                indent: 72,
                color: const Color(0xFF2A2D34).withValues(alpha: 0.6)),
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
            if (snapshot.hasData &&
                snapshot.data != null &&
                userId.isNotEmpty) {
              _cachedIncomingRequests = snapshot.data!;
              _localStore.saveCachedIncomingRequests(
                  userId, _cachedIncomingRequests);
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
                    AppLocalizations.of(context)!.msgFriendRequest,
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
          key: _friendsStreamKey,
          stream: _friendsRepository.watchFriends(userId: userId),
          initialData: _cachedFriends,
          builder: (context, snapshot) {
            final hasValidStream =
                snapshot.connectionState == ConnectionState.active &&
                    !snapshot.hasError;
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
                child: Center(
                    child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2))),
              );
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off,
                          size: 40, color: Colors.orange.shade300),
                      const SizedBox(height: 8),
                      Text(
                        NetworkErrorHelper.messageForUser(
                          snapshot.error,
                          l10n: AppLocalizations.of(context),
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Color(0xFF6C6F77), fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: () =>
                            setState(() => _friendsStreamKey = UniqueKey()),
                        icon: const Icon(AppIcons.retry, size: 16),
                        label: Text(AppLocalizations.of(context)!.commonRetry),
                      ),
                    ],
                  ),
                ),
              );
            }
            final sourceFriends =
                hasValidStream && friends != null ? friends : _cachedFriends;
            final filtered = _filterFriends(sourceFriends);
            final blacklisted = _filterBlacklisted(sourceFriends);
            if (filtered.isEmpty && (!_showBlacklist || blacklisted.isEmpty)) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    AppLocalizations.of(context)!.msgNoFriends,
                    style: const TextStyle(color: Color(0xFF6C6F77)),
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
                        subtitle: _isCustomerServiceFriend(friend)
                            ? ''
                            : (friend.shortId?.trim().isNotEmpty == true
                                ? AppLocalizations.of(context)!
                                    .profileAccountIdValue(
                                        friend.shortId!.trim())
                                : AppLocalizations.of(context)!
                                    .profileAccountIdDash),
                        avatarText: friend.displayName.isEmpty
                            ? AppLocalizations.of(context)!.commonUserInitial
                            : friend.displayName[0],
                        avatarUrl: friend.avatarUrl,
                        levelLabel: _isCustomerServiceFriend(friend)
                            ? null
                            : 'Lv ${friend.level}',
                        roleLabel: _isCustomerServiceFriend(friend)
                            ? 'customer_service'
                            : friend.roleLabel,
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
      if (!context.mounted) return;
      if (conversation != null) {
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
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => ChatDetailPage(
          conversation: conversation,
          initialMessages: const <ChatMessage>[],
        ),
      ),
    )
        .then((_) {
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
    final avatarUrl =
        conversation.isGroup ? conversation.avatarUrl : peerProfile?.avatarUrl;
    final isCustomerService =
        peerProfile != null && _isCustomerServiceFriend(peerProfile);
    final displayTitleForCard =
        isCustomerService ? _resolveFriendName(peerProfile) : displayTitle;
    final levelLabel = (peerProfile != null && !isCustomerService)
        ? 'Lv ${peerProfile.level}'
        : null;
    final roleLabel =
        isCustomerService ? 'customer_service' : peerProfile?.roleLabel;
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
          displayTitle: displayTitleForCard,
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
      backgroundColor: AppColors.scaffold,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(isPinned
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined),
                title: Text(isPinned
                    ? AppLocalizations.of(context)!.msgUnpin
                    : AppLocalizations.of(context)!.msgPin),
                onTap: () {
                  Navigator.of(context).pop();
                  _togglePin(conversation.id);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title:
                    Text(AppLocalizations.of(context)!.msgDeleteConversation),
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
        SnackBar(
            content:
                Text(AppLocalizations.of(context)!.msgAcceptFriendSuccess)),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(NetworkErrorHelper.messageForUser(error,
                prefix: AppLocalizations.of(context)!.msgOperationFailed,
                l10n: AppLocalizations.of(context)))),
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
        SnackBar(
            content:
                Text(AppLocalizations.of(context)!.msgRejectFriendSuccess)),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(NetworkErrorHelper.messageForUser(error,
                prefix: AppLocalizations.of(context)!.msgOperationFailed,
                l10n: AppLocalizations.of(context)))),
      );
    }
  }

  Conversation? _findCachedDirectConversation(String friendId) {
    if (friendId.isEmpty) return null;
    for (final conversation in _cachedConversations) {
      if (!conversation.isGroup && conversation.peerId == friendId) {
        return conversation;
      }
    }
    return null;
  }

  Future<Conversation> _ensureDirectConversation(
    String currentUserId,
    FriendProfile friend,
  ) async {
    if (_isCustomerServiceFriend(friend)) {
      // 不阻塞 UI；仅确保客服分配关系存在。
      await CustomerServiceRepository().assignOrGetStaffForUser(currentUserId);
    }
    return _repository.createOrGetDirectConversation(
      currentUserId: currentUserId,
      friendId: friend.userId,
      friendName: _resolveFriendName(friend),
    );
  }

  Future<void> _warmUpDirectConversation(
    String currentUserId,
    FriendProfile friend,
  ) async {
    try {
      await _ensureDirectConversation(currentUserId, friend);
    } catch (_) {
      // 已有会话时仅做后台预热，失败不打断当前聊天页。
    }
  }

  /// 从好友列表点击：始终创建/获取与该好友的单聊并打开；清掉栈上已有聊天页再压入私聊，避免误进群聊。
  Future<void> _openDirectChat(
    BuildContext context,
    FriendProfile friend,
  ) async {
    final current = _currentUser;
    if (current == null) return;

    final cached = _findCachedDirectConversation(friend.userId);
    if (cached != null) {
      _openConversation(context, cached);
      unawaited(_warmUpDirectConversation(current.uid, friend));
      return;
    }

    if (_startingChat) return;
    setState(() => _startingChat = true);
    try {
      final conversation = await _ensureDirectConversation(current.uid, friend);
      if (!context.mounted) return;
      if (conversation.isGroup) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(AppLocalizations.of(context)!.msgOpenChatFailed)),
          );
        }
        return;
      }
      _openConversation(context, conversation);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(NetworkErrorHelper.messageForUser(error,
              prefix: AppLocalizations.of(context)!.msgOpenChatFailedPrefix,
              l10n: AppLocalizations.of(context))),
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
          title: Text(AppLocalizations.of(context)!.msgDeleteFriend),
          content: Text(AppLocalizations.of(context)!
              .msgDeleteFriendConfirm(friend.displayName)),
          actions: [
            AppButton(
              variant: AppButtonVariant.secondary,
              label: AppLocalizations.of(context)!.commonCancel,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            AppButton(
              label: AppLocalizations.of(context)!.msgDelete,
              onPressed: () => Navigator.of(dialogContext).pop(true),
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
      SnackBar(content: Text(AppLocalizations.of(context)!.msgFriendDeleted)),
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
            child: const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 40,
              color: Color(0xFF6C6F77),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            AppLocalizations.of(context)!.msgSelectConversation,
            style: TextStyle(
              color: const Color(0xFF9CA3AF).withValues(alpha: 0.9),
              fontSize: 15,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)!.msgClickLeftToOpen,
            style: const TextStyle(
              color: Color(0xFF6C6F77),
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
                color: selected ? AppColors.success : AppColors.textTertiary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              height: 2,
              width: 24,
              decoration: BoxDecoration(
                color: selected ? AppColors.success : Colors.transparent,
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
    return AppCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title:
            Text(title, style: const TextStyle(color: AppColors.textPrimary)),
        subtitle: Text(subtitle,
            style:
                const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
        trailing:
            const Icon(Icons.chevron_right, color: AppColors.textTertiary),
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
        color: AppColors.primary,
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
    );
  }
}

class _FriendCard extends StatelessWidget {
  const _FriendCard({
    required this.name,
    required this.subtitle,
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
        color: AppColors.primarySubtle(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(color: AppColors.primary, fontSize: 11),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            placeholder: (_, __) =>
                                _messagesAvatarPlaceholder(avatarText),
                            errorWidget: (_, __, ___) =>
                                _messagesAvatarPlaceholder(avatarText),
                          ),
                        )
                      : CircleAvatar(
                          radius: 24,
                          backgroundColor: AppColors.surface2,
                          child: Text(
                            avatarText,
                            style: const TextStyle(color: AppColors.success),
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
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (subtitle.trim().isNotEmpty)
                          Expanded(
                            child: Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.textTertiary),
                            ),
                          ),
                        if (roleLabel != null && roleLabel!.isNotEmpty)
                          RoleBadge(roleLabel: roleLabel!),
                        if (levelLabel != null && levelLabel!.isNotEmpty)
                          _levelTag(levelLabel!),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: AppLocalizations.of(context)!.msgMore,
                onPressed: onMore,
                icon: const Icon(Icons.more_vert,
                    size: 20, color: AppColors.textTertiary),
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
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.surfaceElevated,
                  child: Text(
                    item.requesterName.isEmpty
                        ? AppLocalizations.of(context)!.commonUserInitial
                        : item.requesterName[0],
                    style: const TextStyle(color: AppColors.primary),
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
                          color: AppColors.textTertiary,
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
                  child: AppButton(
                    variant: AppButtonVariant.secondary,
                    label: AppLocalizations.of(context)!.msgDecline,
                    onPressed: onReject,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    label: AppLocalizations.of(context)!.msgAccept,
                    onPressed: onAccept,
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
  static const _green = AppColors.success;

  @override
  Widget build(BuildContext context) {
    final avatarText = _initial(conversation.avatarText ?? displayTitle);
    final showAvatar = avatarUrl?.trim().isNotEmpty == true;
    final hasDraft = draft != null && draft!.trim().isNotEmpty;
    final String subtitleText;
    if (hasDraft) {
      subtitleText =
          '${AppLocalizations.of(context)!.msgDraft}${draft!.trim()}';
    } else if (conversation.lastMessage.trim().isNotEmpty &&
        conversation.lastMessageSenderId != null &&
        conversation.lastMessageSenderId == currentUserId) {
      subtitleText =
          '${AppLocalizations.of(context)!.msgMePrefix}${conversation.lastMessage}';
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
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            placeholder: (_, __) => _messagesAvatarPlaceholder(
                                avatarText, conversation.isGroup),
                            errorWidget: (_, __, ___) =>
                                _messagesAvatarPlaceholder(
                                    avatarText, conversation.isGroup),
                          ),
                        )
                      : conversation.isGroup
                          ? const CircleAvatar(
                              radius: _avatarSize / 2,
                              backgroundColor: AppColors.borderFocus,
                              child: Icon(Icons.people,
                                  color: AppColors.success, size: 26),
                            )
                          : CircleAvatar(
                              radius: _avatarSize / 2,
                              backgroundColor: AppColors.surface2,
                              child: Text(
                                avatarText,
                                style: const TextStyle(
                                    color: AppColors.success, fontSize: 20),
                              ),
                            ),
                  if (conversation.isGroup)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: AppColors.scaffold,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: AppColors.surface2, width: 1),
                        ),
                        child: const Icon(Icons.people,
                            size: 12, color: AppColors.success),
                      ),
                    ),
                  if (pinned)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: AppColors.scaffold,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.push_pin,
                            size: 12, color: AppColors.success),
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
                        if (conversation.isGroup)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.success.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                    color: AppColors.success
                                        .withValues(alpha: 0.4),
                                    width: 0.8),
                              ),
                              child: Text(
                                AppLocalizations.of(context)!.msgGroupChat,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.success,
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            displayTitle,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
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
                              style: const TextStyle(
                                  fontSize: 10, color: AppColors.textTertiary),
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
                        color: hasDraft
                            ? AppColors.warning
                            : AppColors.textTertiary,
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
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textTertiary),
                  ),
                  if (conversation.unreadCount > 0) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _green,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        conversation.unreadCount > 99
                            ? '99+'
                            : '${conversation.unreadCount}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500),
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
