import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'chat_media_cache.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/last_online_service.dart';
import '../../core/network_error_helper.dart';
import '../../core/notification_service.dart';
import '../../core/role_badge.dart';
import '../../core/supabase_bootstrap.dart';
import '../../core/user_restrictions.dart';
import 'friend_models.dart';
import 'message_models.dart';
import 'messages_local_store.dart';
import 'messages_repository.dart';
import 'friends_repository.dart';
import 'group_join_link_handler.dart';
import 'group_settings_page.dart';
import 'user_profile_page.dart';
import '../call/agora_call_page.dart';
import '../call/agora_config.dart';
import '../call/call_invitation_repository.dart';
import '../teachers/teacher_public_page.dart';

class ChatDetailPage extends StatefulWidget {
  const ChatDetailPage({
    super.key,
    required this.conversation,
    required this.initialMessages,
    this.onCloseForEmbed,
  });

  final Conversation conversation;
  final List<ChatMessage> initialMessages;
  /// PC 端内嵌时传入，点击返回会调用此回调而非 Navigator.pop
  final VoidCallback? onCloseForEmbed;

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> with TickerProviderStateMixin {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _repository = MessagesRepository();
  final _friendsRepository = FriendsRepository();
  final _picker = ImagePicker();
  final _recorder = AudioRecorder();
  final _localStore = MessagesLocalStore();
  late final String _userId;
  late final String _userName;
  String? _peerId;
  final List<ChatMessage> _pendingMessages = [];
  /// 发送失败的本条消息 localId，用于在气泡旁显示感叹号（不弹 toast）
  final Set<String> _failedLocalIds = {};
  Map<String, String> _friendRemarks = {};
  FriendProfile? _peerProfile;
  String? _cachedPeerDisplayName;
  String? _cachedPeerAvatarUrl;
  String? _groupAvatarUrl;
  String? _groupTitle;
  String? _groupAnnouncement;
  String _myGroupRole = 'member';
  /// 群成员 userId -> avatarUrl，用于聊天气泡头像
  final Map<String, String?> _memberAvatarUrls = {};
  /// 群成员列表（含 displayName），用于 @ 提及 选择
  List<GroupMember> _groupMembersWithNames = [];
  /// @ 提及：输入框内从 @ 到光标的内容，用于过滤成员列表；非 null 时显示成员选择
  String? _mentionQuery;
  /// @ 在输入框中的起始偏移，选择成员后替换该段
  int _mentionStartOffset = 0;
  String? _myAvatarUrl;
  bool _groupAnnouncementVisible = true;
  bool _groupAnnouncementCollapsing = false;
  AnimationController? _groupAnnouncementAnimationController;
  Animation<double>? _groupAnnouncementSizeFactor;
  StreamSubscription<Map<String, String>>? _remarkSubscription;
  bool _isRecording = false;
  bool _isUploading = false;
  final ValueNotifier<bool> _isSendingNotifier = ValueNotifier<bool>(false);
  bool _useVoiceInput = false;
  final ValueNotifier<bool> _hasTextNotifier = ValueNotifier<bool>(false);
  bool _emojiOpen = false;
  DateTime? _recordStart;
  final Set<String> _prefetchedMediaIds = {};
  final Map<String, String> _localMediaByUrl = {};
  int _lastMessageCount = 0;
  final ValueNotifier<bool> _shouldAutoScrollNotifier = ValueNotifier<bool>(true);
  Timer? _draftSaveTimer;
  Timer? _markReadTimer;
  List<ChatMessage>? _cachedMessages;
  bool _cacheLoadComplete = false;
  late final Stream<List<ChatMessage>> _messageStream;
  ChatMessage? _replyingToMessage;
  /// 与当前单聊对象的通话记录（仅单聊时加载，用于在聊天时间线中展示呼叫记录）
  List<CallRecord>? _callRecords;
  /// 文件上传进度：localId -> null=进行中(无具体进度)，0.0~1.0=进度值，上传完成后移除
  final Map<String, double?> _fileUploadProgress = {};

  void _doMarkConversationRead() {
    if (_userId.isEmpty) return;
    _repository.markConversationRead(
      conversationId: widget.conversation.id,
      userId: _userId,
    );
  }

  @override
  void initState() {
    super.initState();
    NotificationService.setCurrentConversationId(widget.conversation.id);
    final user = FirebaseAuth.instance.currentUser;
    _userId = user?.uid ?? '';
    _userName = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : (user?.email?.split('@').first ?? '我');
    _peerId = widget.conversation.peerId;
    _ensurePeerId();
    _textController.addListener(_handleTextChanged);
    _loadCachedRemarksAndPeer();
    _subscribeRemarks();
    _loadDraft();
    _scrollController.addListener(_handleScroll);
    if (_userId.isNotEmpty) {
      _doMarkConversationRead();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _doMarkConversationRead();
        _markReadTimer?.cancel();
        _markReadTimer = Timer.periodic(const Duration(seconds: 2), (_) {
          if (!mounted) return;
          _doMarkConversationRead();
        });
      });
    }
    if (widget.conversation.isGroup) {
      _groupAvatarUrl = widget.conversation.avatarUrl;
      _groupTitle = widget.conversation.title;
      Future.microtask(() async {
        final url = await _resolveMyAvatarUrl();
        if (mounted) setState(() => _myAvatarUrl = url);
      });
      _groupAnnouncementAnimationController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 280),
      );
      _groupAnnouncementSizeFactor = Tween<double>(begin: 1, end: 0).animate(
        CurvedAnimation(
          parent: _groupAnnouncementAnimationController!,
          curve: Curves.easeIn,
        ),
      );
      _groupAnnouncementAnimationController!.addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() {
            _groupAnnouncementVisible = false;
            _groupAnnouncementCollapsing = false;
          });
          _groupAnnouncementAnimationController?.reset();
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshGroupInfo());
    }
    if (!widget.conversation.isGroup && (_peerId != null && _peerId!.isNotEmpty)) {
      _loadPeerProfile(_peerId!);
      _loadCallRecords();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final pid = await _ensurePeerId();
        if (pid != null && pid.isNotEmpty && mounted) {
          _loadPeerProfile(pid);
          if (!widget.conversation.isGroup) _loadCallRecords();
        }
      });
    }
    _loadCachedMessages();
    _messageStream = _debounceMessageStream(const Duration(milliseconds: 280));
    // 打开聊天窗口时自动聚焦输入框，可直接输入
    _requestInputFocus();
  }

  /// 下一帧请求输入框聚焦（打开或切换会话时调用，避免每次都要用鼠标点一下）
  void _requestInputFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant ChatDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversation.id != widget.conversation.id) {
      // 切换到另一个会话时，同样自动聚焦输入框
      _requestInputFocus();
    }
  }

  Future<void> _loadCallRecords() async {
    final peerId = _peerId ?? widget.conversation.peerId;
    if (peerId == null || peerId.isEmpty || widget.conversation.isGroup) return;
    try {
      final list = await CallInvitationRepository().listForConversation(
        myUserId: _userId,
        peerUserId: peerId,
        limit: 50,
      );
      if (mounted) setState(() => _callRecords = list);
    } catch (_) {
      if (mounted) setState(() => _callRecords = []);
    }
  }

  /// 对消息流防抖：首条立即发出，后续短时间内的多次推送合并为一次，减轻“闪两下”
  Stream<List<ChatMessage>> _debounceMessageStream(Duration duration) {
    late StreamSubscription<List<ChatMessage>> sub;
    List<ChatMessage>? latest;
    Timer? timer;
    var isFirst = true;
    final controller = StreamController<List<ChatMessage>>.broadcast(sync: true);
    void emitLatest() {
      if (latest != null) {
        controller.add(latest!);
        latest = null;
      }
      timer = null;
    }
    sub = _repository
        .watchMessages(
          conversationId: widget.conversation.id,
          currentUserId: _userId,
        )
        .listen(
          (data) {
            if (isFirst) {
              isFirst = false;
              controller.add(data);
              return;
            }
            latest = data;
            timer?.cancel();
            timer = Timer(duration, emitLatest);
          },
          onError: controller.addError,
          onDone: () {
            timer?.cancel();
            emitLatest();
            controller.close();
          },
        );
    controller.onCancel = () {
      timer?.cancel();
      sub.cancel();
    };
    return controller.stream;
  }

  Future<void> _loadCachedRemarksAndPeer() async {
    final prefsRemarks = await _localStore.loadFriendRemarks();
    final cid = widget.conversation.id;
    final peer = await _localStore.loadConversationPeer(cid);
    if (!mounted) return;
    setState(() {
      _friendRemarks = prefsRemarks;
      _cachedPeerDisplayName = peer?['displayName']?.trim();
      _cachedPeerAvatarUrl = peer?['avatarUrl']?.trim();
      if (_cachedPeerAvatarUrl != null && _cachedPeerAvatarUrl!.isEmpty) {
        _cachedPeerAvatarUrl = null;
      }
    });
  }

  Future<void> _loadCachedMessages() async {
    if (_userId.isEmpty) return;
    final list = await _localStore.loadCachedMessages(
      conversationId: widget.conversation.id,
      currentUserId: _userId,
    );
    final peer = await _localStore.loadConversationPeer(widget.conversation.id);
    Map<String, dynamic>? groupAvatarCache;
    if (widget.conversation.isGroup) {
      groupAvatarCache = await _localStore.loadGroupAvatarCache(widget.conversation.id);
    }
    if (!mounted) return;
    setState(() {
      _cachedMessages = list.isEmpty ? null : list;
      _cacheLoadComplete = true;
      _cachedPeerDisplayName ??= peer?['displayName']?.trim();
      _cachedPeerAvatarUrl ??= peer?['avatarUrl']?.trim();
      if (_cachedPeerAvatarUrl != null && _cachedPeerAvatarUrl!.isEmpty) {
        _cachedPeerAvatarUrl = null;
      }
      if (widget.conversation.isGroup && groupAvatarCache != null) {
        final gUrl = groupAvatarCache['groupAvatarUrl'];
        final mUrl = groupAvatarCache['myAvatarUrl'];
        final members = groupAvatarCache['memberAvatarUrls'];
        if (gUrl != null) _groupAvatarUrl = gUrl as String?;
        if (mUrl != null) _myAvatarUrl = mUrl as String?;
        if (members is Map<String, String?>) {
          _memberAvatarUrls.addAll(members);
        }
      }
    });
  }

  Future<void> _loadPeerProfile(String peerId) async {
    try {
      final profile = await _friendsRepository.findById(peerId);
      if (!mounted) return;
      setState(() {
        _peerProfile = profile;
      });
      final name = profile?.displayName.trim() ?? '';
      if (name.isNotEmpty) {
        await _localStore.saveConversationPeer(
          conversationId: widget.conversation.id,
          displayName: name,
          avatarUrl: profile?.avatarUrl,
        );
      }
    } catch (_) {
      // 忽略加载失败，顶栏用本地缓存或会话标题
    }
  }

  @override
  void dispose() {
    NotificationService.setCurrentConversationId(null);
    LastOnlineService.updateLastOnlineNow();
    _markReadTimer?.cancel();
    _markReadTimer = null;
    if (_userId.isNotEmpty) {
      final cid = widget.conversation.id;
      final uid = _userId;
      Future.microtask(() {
        _repository.markConversationRead(
          conversationId: cid,
          userId: uid,
        );
      });
    }
    _textController.removeListener(_handleTextChanged);
    _textController.dispose();
    _focusNode.dispose();
    _hasTextNotifier.dispose();
    _shouldAutoScrollNotifier.dispose();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _draftSaveTimer?.cancel();
    _recorder.dispose();
    _groupAnnouncementAnimationController?.dispose();
    _remarkSubscription?.cancel();
    super.dispose();
  }

  void _hideGroupAnnouncement() {
    if (!_groupAnnouncementVisible || _groupAnnouncementCollapsing) return;
    final controller = _groupAnnouncementAnimationController;
    if (controller == null) {
      setState(() => _groupAnnouncementVisible = false);
      return;
    }
    setState(() => _groupAnnouncementCollapsing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _groupAnnouncementCollapsing) controller.forward();
    });
  }

  Future<void> _loadDraft() async {
    final drafts = await _localStore.loadDrafts();
    final draft = drafts[widget.conversation.id];
    if (!mounted || draft == null || draft.isEmpty) {
      return;
    }
    _textController.text = draft;
    _textController.selection = TextSelection.fromPosition(
      TextPosition(offset: _textController.text.length),
    );
    _hasTextNotifier.value = _textController.text.trim().isNotEmpty;
  }

  Future<String?> _ensurePeerId() async {
    if (_peerId != null && _peerId!.isNotEmpty) {
      return _peerId;
    }
    if (_userId.isEmpty || widget.conversation.isGroup) {
      return _peerId;
    }
    try {
      final members = await SupabaseBootstrap.client
          .from('chat_members')
          .select('user_id')
          .eq('conversation_id', widget.conversation.id);
      final resolved = members
          .map((row) => row['user_id'] as String?)
          .whereType<String>()
          .firstWhere((id) => id != _userId, orElse: () => '');
      if (resolved.isNotEmpty) {
        if (!mounted) {
          _peerId = resolved;
        } else {
          setState(() {
            _peerId = resolved;
          });
        }
      }
    } catch (_) {
      // Ignore peer resolve errors, push will be skipped.
    }
    return _peerId;
  }

  void _subscribeRemarks() {
    if (_userId.isEmpty) {
      return;
    }
    _remarkSubscription?.cancel();
    _remarkSubscription = _friendsRepository
        .watchRemarks(userId: _userId)
        .listen((remarks) {
      if (!mounted) return;
      setState(() {
        _friendRemarks = remarks;
      });
      _localStore.saveFriendRemarks(remarks);
    });
  }

  void _onSelectMentionMember(GroupMember member) {
    final name = member.displayName?.trim().isNotEmpty == true
        ? member.displayName!
        : member.userId;
    final insert = '@$name ';
    final text = _textController.text;
    final cursor = _textController.selection.baseOffset.clamp(0, text.length);
    final start = _mentionStartOffset.clamp(0, text.length);
    final end = cursor;
    final before = start > 0 ? text.substring(0, start) : '';
    final after = end < text.length ? text.substring(end) : '';
    _textController.text = before + insert + after;
    _textController.selection = TextSelection.fromPosition(
      TextPosition(offset: (before + insert).length),
    );
    setState(() {
      _mentionQuery = null;
      _mentionStartOffset = 0;
    });
    _hasTextNotifier.value = true;
  }

  Widget _buildMentionOverlay() {
    final query = (_mentionQuery ?? '').trim().toLowerCase();
    final list = query.isEmpty
        ? _groupMembersWithNames
        : _groupMembersWithNames.where((m) {
            final name = (m.displayName ?? m.userId).toLowerCase();
            return name.contains(query) || m.userId.toLowerCase().contains(query);
          }).toList();
    if (list.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1C21),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2A2D34)),
        ),
        child: const Text(
          '暂无匹配成员',
          style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1C21),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2A2D34)),
        ),
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final m = list[i];
            final displayName = m.displayName?.trim().isNotEmpty == true
                ? m.displayName!
                : m.userId;
            final avatarUrl = _memberAvatarUrls[m.userId];
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _onSelectMentionMember(m),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: const Color(0xFF2A2D34),
                        backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                            ? NetworkImage(avatarUrl)
                            : null,
                        child: avatarUrl == null || avatarUrl.isEmpty
                            ? Text(
                                displayName.isNotEmpty ? displayName[0] : '?',
                                style: const TextStyle(
                                  color: Color(0xFFD4AF37),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          displayName,
                          style: const TextStyle(
                            color: Color(0xFFE5E7EB),
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _handleTextChanged() {
    final hasText = _textController.text.trim().isNotEmpty;
    if (hasText != _hasTextNotifier.value) {
      _hasTextNotifier.value = hasText;
    }
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 350), () {
      _localStore.saveDraft(widget.conversation.id, _textController.text);
    });
    // 群聊 @ 提及：检测光标前是否有 @，有则展示可选成员
    if (widget.conversation.isGroup && _groupMembersWithNames.isNotEmpty) {
      final text = _textController.text;
      final cursor = _textController.selection.baseOffset.clamp(0, text.length);
      final beforeCursor = cursor > 0 ? text.substring(0, cursor) : '';
      final lastAt = beforeCursor.lastIndexOf('@');
      if (lastAt >= 0) {
        final afterAt = beforeCursor.substring(lastAt + 1);
        if (!afterAt.contains(' ') && !afterAt.contains('\n')) {
          if (mounted) {
            setState(() {
              _mentionQuery = afterAt;
              _mentionStartOffset = lastAt;
            });
          }
          return;
        }
      }
      if (mounted && _mentionQuery != null) {
        setState(() {
          _mentionQuery = null;
          _mentionStartOffset = 0;
        });
      }
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    if (_groupAnnouncementVisible && mounted) {
      _hideGroupAnnouncement();
    }
    final position = _scrollController.position;
    final threshold = 48.0;
    // reverse 列表下，最新消息在顶部（pixels 接近 0），故在底部 = pixels <= threshold
    final atBottom = position.pixels <= threshold;
    if (atBottom != _shouldAutoScrollNotifier.value) {
      _shouldAutoScrollNotifier.value = atBottom;
    }
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) {
      return;
    }
    // reverse 列表底部对应 offset 0
    const target = 0.0;
    if (animated) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  /// 发送文本：先落本地缓存并立即在列表显示（不依赖网络，不卡），再后台上传；仅在上传失败时 toast 提示。
  void _sendMessage() {
    if (_isSendingNotifier.value) return;
    final text = _textController.text.trim();
    if (text.isEmpty || _userId.isEmpty) return;

    final localId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    final replying = _replyingToMessage;
    final pending = ChatMessage(
      id: localId,
      senderId: _userId,
      senderName: _userName,
      content: text,
      messageType: 'text',
      time: DateTime.now(),
      isMine: true,
      isLocal: true,
      replyToMessageId: replying?.id,
      replyToSenderName: replying?.senderName,
      replyToContent: replying?.content,
    );

    _isSendingNotifier.value = true;
    setState(() {
      if (_emojiOpen) _emojiOpen = false;
      _replyingToMessage = null;
      _pendingMessages.add(pending);
      _textController.clear();
      _hasTextNotifier.value = false;
    });
    _localStore.saveDraft(widget.conversation.id, '');
    _shouldAutoScrollNotifier.value = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(animated: true);
      // 发送后保持输入框聚焦，可继续输入
      if (mounted) _focusNode.requestFocus();
    });

    // 先写本地缓存（纯本地，无网络不卡），再后台上传
    _appendSentMessageToCache(pending);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _uploadTextMessageToServer(
        text: text,
        localId: localId,
        replyToMessageId: replying?.id,
        replyToSenderName: replying?.senderName,
        replyToContent: replying?.content,
      );
    });
  }

  /// 将刚发送的消息追加到本地缓存（不阻塞 UI）
  void _appendSentMessageToCache(ChatMessage pending) {
    final cid = widget.conversation.id;
    final uid = _userId;
    if (cid.isEmpty || uid.isEmpty) return;
    _localStore.loadCachedMessages(conversationId: cid, currentUserId: uid).then((list) {
      final next = [...list, pending];
      _localStore.saveCachedMessages(
        conversationId: cid,
        currentUserId: uid,
        messages: next,
      );
    }).catchError((_) {});
  }

  /// 后台上传文本消息。先校验权限/好友，再发服务器；仅业务失败（非好友/封禁）才移除并恢复输入框，网络失败只 toast，消息保留在本地。
  Future<void> _uploadTextMessageToServer({
    required String text,
    required String localId,
    String? replyToMessageId,
    String? replyToSenderName,
    String? replyToContent,
  }) async {
    try {
      // 后台校验：禁止发消息/封禁时移除本条并恢复输入框
      final restrictions = await UserRestrictions.getMyRestrictionRow();
      if (!UserRestrictions.canSendMessage(restrictions)) {
        if (mounted) {
          UserRestrictions.clearCache();
          setState(() {
            _pendingMessages.removeWhere((item) => item.id == localId);
            _failedLocalIds.remove(localId);
          });
          _textController.text = text;
          _textController.selection = TextSelection.fromPosition(TextPosition(offset: text.length));
          _localStore.saveDraft(widget.conversation.id, text);
          _showToast(UserRestrictions.getAccountStatusMessage(restrictions));
        }
        return;
      }
      if (!widget.conversation.isGroup) {
        final receiverId = await _ensurePeerId();
        final isFriend = await _friendsRepository.isFriend(
          userId: _userId,
          friendId: receiverId ?? '',
        );
        if (!isFriend) {
          if (mounted) {
            setState(() {
              _pendingMessages.removeWhere((item) => item.id == localId);
              _failedLocalIds.remove(localId);
            });
            _textController.text = text;
            _textController.selection = TextSelection.fromPosition(
              TextPosition(offset: text.length),
            );
            _localStore.saveDraft(widget.conversation.id, text);
            _showToast('已不是好友，无法发送');
          }
          return;
        }
        await _repository.sendMessage(
          conversationId: widget.conversation.id,
          senderId: _userId,
          senderName: _userName,
          content: text,
          messageType: 'text',
          receiverId: receiverId,
          replyToMessageId: replyToMessageId,
          replyToSenderName: replyToSenderName,
          replyToContent: replyToContent,
        );
      } else {
        final members = await _repository.fetchGroupMembers(widget.conversation.id);
        final receiverIds = members
            .map((m) => m.userId)
            .where((id) => id.isNotEmpty && id != _userId)
            .toList();
        await _repository.sendMessage(
          conversationId: widget.conversation.id,
          senderId: _userId,
          senderName: _userName,
          content: text,
          messageType: 'text',
          receiverIds: receiverIds,
          replyToMessageId: replyToMessageId,
          replyToSenderName: replyToSenderName,
          replyToContent: replyToContent,
        );
      }
      if (mounted) {
        setState(() {
          _replyingToMessage = null;
          _failedLocalIds.remove(localId);
        });
      }
    } catch (error) {
      // 网络/服务器失败：不弹 toast，只标记该条为发送失败（气泡旁显示感叹号）
      if (mounted) {
        setState(() => _failedLocalIds.add(localId));
      }
    } finally {
      if (mounted) {
        _isSendingNotifier.value = false;
      }
    }
  }

  /// 重试发送失败的那条消息（点感叹号时调用）
  void _retrySendMessage(ChatMessage message) {
    if (!message.isLocal || message.id.isEmpty) return;
    setState(() => _failedLocalIds.remove(message.id));
    _uploadTextMessageToServer(
      text: message.content,
      localId: message.id,
      replyToMessageId: message.replyToMessageId,
      replyToSenderName: message.replyToSenderName,
      replyToContent: message.replyToContent,
    );
  }

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null) {
      return;
    }
    await _sendCompressedImage(file);
  }

  Future<void> _pickVideo() async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null) {
      return;
    }
    final prepared = await _prepareVideo(file);
    await _sendMedia(
      file: prepared,
      type: 'video',
      contentType: prepared.mimeType ?? 'video/mp4',
    );
  }

  Future<void> _pickImageFromCamera() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (file == null) {
      return;
    }
    await _sendCompressedImage(file);
  }

  Future<void> _pickVideoFromCamera() async {
    final file = await _picker.pickVideo(source: ImageSource.camera);
    if (file == null) {
      return;
    }
    final prepared = await _prepareVideo(file);
    await _sendMedia(
      file: prepared,
      type: 'video',
      contentType: prepared.mimeType ?? 'video/mp4',
    );
  }

  Future<void> _toggleRecord() async {
    if (_isUploading) {
      return;
    }
    if (kIsWeb) {
      _showToast('Web 暂不支持录音');
      return;
    }
    if (_isRecording) {
      final path = await _recorder.stop();
      setState(() {
        _isRecording = false;
      });
      if (path == null || path.isEmpty) {
        return;
      }
      int? durationMs;
      if (_recordStart != null) {
        durationMs =
            DateTime.now().difference(_recordStart!).inMilliseconds;
        if (durationMs < 900) {
          _showToast('录音时间太短');
          return;
        }
      }
      final bytes = await File(path).readAsBytes();
      await _sendMediaBytes(
        fileName: path.split(Platform.pathSeparator).last,
        bytes: Uint8List.fromList(bytes),
        type: 'audio',
        contentType: 'audio/m4a',
        localPath: path,
        durationMs: durationMs,
      );
      return;
    }

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _showToast('请授予麦克风权限');
      return;
    }
    final tempDir = await getTemporaryDirectory();
    final path =
        '${tempDir.path}${Platform.pathSeparator}voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: path,
    );
    setState(() {
      _isRecording = true;
      _recordStart = DateTime.now();
    });
  }

  Future<void> _startRecord() async {
    if (_isRecording) {
      return;
    }
    await _toggleRecord();
  }

  Future<void> _stopRecord() async {
    if (!_isRecording) {
      return;
    }
    await _toggleRecord();
  }

  Future<void> _sendMedia({
    required XFile file,
    required String type,
    required String contentType,
  }) async {
    if (_userId.isEmpty) {
      return;
    }
    if (_isUploading) {
      return;
    }
    setState(() {
      _isUploading = true;
    });
    try {
      final bytes = await file.readAsBytes();
      String? localPath = kIsWeb ? null : file.path;
      if (!kIsWeb) {
        final localFile = localPath == null ? null : File(localPath);
        if (localFile == null || !localFile.existsSync()) {
          final ext = _guessExtension(type, file.name);
          localPath = await _writeTempFile(bytes, ext);
        }
      }
      await _sendMediaBytes(
        fileName: file.name,
        bytes: Uint8List.fromList(bytes),
        type: type,
        contentType: contentType,
        localPath: localPath,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _sendCompressedImage(XFile file) async {
    if (_userId.isEmpty) {
      return;
    }
    if (_isUploading) {
      return;
    }
    setState(() {
      _isUploading = true;
    });
    try {
      final bytes = await file.readAsBytes();
      Uint8List outputBytes = Uint8List.fromList(bytes);
      if (!kIsWeb) {
        final compressed = await FlutterImageCompress.compressWithList(
          bytes,
          quality: 72,
          minWidth: 1080,
          minHeight: 1080,
          keepExif: false,
        );
        if (compressed.isNotEmpty) {
          outputBytes = Uint8List.fromList(compressed);
        }
      }
      String? localPath = kIsWeb ? null : file.path;
      if (!kIsWeb) {
        final localFile = localPath == null ? null : File(localPath);
        if (localFile == null || !localFile.existsSync()) {
          localPath = await _writeTempFile(outputBytes, 'jpg');
        }
      }
      await _sendMediaBytes(
        fileName: 'img_${DateTime.now().millisecondsSinceEpoch}.jpg',
        bytes: outputBytes,
        type: 'image',
        contentType: 'image/jpeg',
        localPath: localPath,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<XFile> _prepareVideo(XFile file) async {
    if (kIsWeb) {
      return file;
    }
    try {
      final info = await VideoCompress.compressVideo(
        file.path,
        quality: VideoQuality.Res640x480Quality,
        includeAudio: true,
        deleteOrigin: false,
      );
      final compressed = info?.file;
      if (compressed != null && compressed.existsSync()) {
        return XFile(compressed.path);
      }
      return file;
    } catch (error) {
      debugPrint('video compress failed: $error');
      return file;
    }
  }

  Future<void> _sendMediaBytes({
    required String fileName,
    required Uint8List bytes,
    required String type,
    required String contentType,
    String? localPath,
    int? durationMs,
  }) async {
    if (!SupabaseBootstrap.isReady) {
      _showToast('未配置 Supabase，无法发送媒体');
      return;
    }
    // 与文本发送一致：后台限制发消息时禁止发送图片/语音/视频
    final restrictions = await UserRestrictions.getMyRestrictionRow();
    if (!UserRestrictions.canSendMessage(restrictions)) {
      UserRestrictions.clearCache();
      _showToast(UserRestrictions.getAccountStatusMessage(restrictions));
      return;
    }
    if (bytes.isEmpty) {
      _showToast('文件为空，无法发送');
      return;
    }
    try {
      String? receiverId;
      List<String>? receiverIds;
      if (!widget.conversation.isGroup) {
        receiverId = _peerId ?? await _ensurePeerId();
        final isFriend = await _friendsRepository.isFriend(
          userId: _userId,
          friendId: receiverId ?? '',
        );
        if (!isFriend) {
          _showToast('已不是好友，无法发送');
          return;
        }
      } else {
        final members = await _repository.fetchGroupMembers(widget.conversation.id);
        receiverIds = members
            .map((m) => m.userId)
            .where((id) => id.isNotEmpty && id != _userId)
            .toList();
      }
      final url = await _repository.uploadChatMedia(
        conversationId: widget.conversation.id,
        userId: _userId,
        fileName: fileName,
        bytes: bytes,
        contentType: contentType,
      );
      await _repository.sendMessage(
        conversationId: widget.conversation.id,
        senderId: _userId,
        senderName: _userName,
        content: type == 'file' ? fileName : _typeLabel(type),
        messageType: type,
        mediaUrl: url,
        localPath: localPath,
        receiverId: receiverId,
        receiverIds: receiverIds,
        durationMs: durationMs,
      );
      if (localPath != null && localPath.isNotEmpty && mounted) {
        setState(() {
          _localMediaByUrl[url] = localPath;
        });
      }
    } catch (error) {
      debugPrint('send media failed: $error');
      _showToast(NetworkErrorHelper.messageForUser(error, prefix: '发送失败'));
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'image':
        return '[图片]';
      case 'video':
        return '[视频]';
      case 'audio':
        return '[语音]';
      case 'file':
        return '[文件]';
      default:
        return '';
    }
  }

  String _guessExtension(String type, String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.contains('.')) {
      return lower.split('.').last;
    }
    switch (type) {
      case 'video':
        return 'mp4';
      case 'image':
        return 'jpg';
      case 'audio':
        return 'm4a';
      case 'file':
        return 'bin';
      default:
        return 'bin';
    }
  }

  static String _mimeFromExtension(String path) {
    final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
    const map = {
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'txt': 'text/plain',
      'zip': 'application/zip',
      'apk': 'application/vnd.android.package-archive',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  Future<String> _writeTempFile(Uint8List bytes, String ext) async {
    final tempDir = await getTemporaryDirectory();
    final path =
        '${tempDir.path}${Platform.pathSeparator}chat_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  void _toggleInputMode() {
    setState(() {
      _useVoiceInput = !_useVoiceInput;
      if (_useVoiceInput) {
        _emojiOpen = false;
      }
    });
  }

  void _openEmojiPanel() {
    FocusScope.of(context).unfocus();
    setState(() {
      _emojiOpen = !_emojiOpen;
    });
    if (_shouldAutoScrollNotifier.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom(animated: true);
      });
    }
  }

  void _openMoreActions() {
    if (_isUploading) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0E0F14),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ActionTile(
                  icon: Icons.photo_library_outlined,
                  label: '相册',
                  onTap: () {
                    Navigator.of(context).pop();
                    _showAlbumSourcePicker();
                  },
                ),
                _ActionTile(
                  icon: Icons.camera_alt_outlined,
                  label: '拍摄',
                  onTap: () {
                    Navigator.of(context).pop();
                    _showCameraSourcePicker();
                  },
                ),
                _ActionTile(
                  icon: Icons.insert_drive_file_outlined,
                  label: '文件',
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickFile();
                  },
                ),
                if (!widget.conversation.isGroup && _peerId != null && _peerId!.isNotEmpty)
                  _ActionTile(
                    icon: Icons.call_outlined,
                    label: '通话',
                    onTap: () {
                      Navigator.of(context).pop();
                      _showCallTypePicker();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 相册：选择图片或视频（均来自相册）
  void _showAlbumSourcePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0E0F14),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: const Text('图片'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickImage();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.videocam_outlined),
                  title: const Text('视频'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickVideo();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 拍摄：拍照或拍视频（均使用相机）
  void _showCameraSourcePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0E0F14),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('拍照'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickImageFromCamera();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.videocam_outlined),
                  title: const Text('拍视频'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickVideoFromCamera();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickFile() async {
    if (kIsWeb) {
      _showToast('Web 暂不支持发送文件');
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final platformFile = result.files.single;
      Uint8List? bytes;
      if (platformFile.bytes != null && platformFile.bytes!.isNotEmpty) {
        bytes = Uint8List.fromList(platformFile.bytes!);
      } else if (platformFile.path != null && platformFile.path!.isNotEmpty) {
        final file = File(platformFile.path!);
        if (file.existsSync()) {
          bytes = Uint8List.fromList(await file.readAsBytes());
        }
      }
      if (bytes == null || bytes.isEmpty) {
        _showToast('无法读取该文件');
        return;
      }
      final fileName = platformFile.name;
      final contentType = _mimeFromExtension(fileName);
      final localId = 'local-file-${DateTime.now().microsecondsSinceEpoch}';
      final pending = ChatMessage(
        id: localId,
        senderId: _userId,
        senderName: _userName,
        content: fileName,
        messageType: 'file',
        time: DateTime.now(),
        isMine: true,
        isLocal: true,
      );
      setState(() {
        _pendingMessages.add(pending);
        _fileUploadProgress[localId] = 0.0;
      });
      _appendSentMessageToCache(pending);
      _shouldAutoScrollNotifier.value = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(0.0, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
        }
      });
      _uploadFileInBackground(
        localId: localId,
        fileName: fileName,
        bytes: bytes,
        contentType: contentType,
      );
    } catch (e) {
      _showToast('选择文件失败');
    }
  }

  /// 后台上传文件：更新进度，成功后由 stream 替换为服务端消息，失败则移除 pending 并提示
  Future<void> _uploadFileInBackground({
    required String localId,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) async {
    try {
      final restrictions = await UserRestrictions.getMyRestrictionRow();
      if (!UserRestrictions.canSendMessage(restrictions)) {
        if (mounted) {
          UserRestrictions.clearCache();
          setState(() {
            _pendingMessages.removeWhere((m) => m.id == localId);
            _fileUploadProgress.remove(localId);
          });
          _showToast(UserRestrictions.getAccountStatusMessage(restrictions));
        }
        return;
      }
      String? receiverId;
      List<String>? receiverIds;
      if (!widget.conversation.isGroup) {
        receiverId = _peerId ?? await _ensurePeerId();
        final isFriend = await _friendsRepository.isFriend(
          userId: _userId,
          friendId: receiverId ?? '',
        );
        if (!isFriend && mounted) {
          setState(() {
            _pendingMessages.removeWhere((m) => m.id == localId);
            _fileUploadProgress.remove(localId);
          });
          _showToast('已不是好友，无法发送');
          return;
        }
      } else {
        final members = await _repository.fetchGroupMembers(widget.conversation.id);
        receiverIds = members
            .map((m) => m.userId)
            .where((id) => id.isNotEmpty && id != _userId)
            .toList();
      }
      if (mounted) setState(() => _fileUploadProgress[localId] = null);
      final url = await _repository.uploadChatMedia(
        conversationId: widget.conversation.id,
        userId: _userId,
        fileName: fileName,
        bytes: bytes,
        contentType: contentType,
      );
      if (mounted) setState(() => _fileUploadProgress[localId] = 1.0);
      await _repository.sendMessage(
        conversationId: widget.conversation.id,
        senderId: _userId,
        senderName: _userName,
        content: fileName,
        messageType: 'file',
        mediaUrl: url,
        receiverId: receiverId,
        receiverIds: receiverIds,
      );
      if (mounted) {
        setState(() => _fileUploadProgress.remove(localId));
      }
    } catch (e) {
      debugPrint('file upload failed: $e');
      if (mounted) {
        setState(() {
          _pendingMessages.removeWhere((m) => m.id == localId);
          _fileUploadProgress.remove(localId);
        });
        _showToast(NetworkErrorHelper.messageForUser(e, prefix: '文件发送失败'));
      }
    }
  }

  void _showToast(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showMessageActions(ChatMessage message) {
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
                leading: const Icon(Icons.reply_outlined),
                title: const Text('回复'),
                onTap: () {
                  Navigator.of(context).pop();
                  setState(() => _replyingToMessage = message);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_all_outlined),
                title: const Text('复制'),
                onTap: () {
                  Navigator.of(context).pop();
                  Clipboard.setData(ClipboardData(text: message.content));
                  _showToast('已复制');
                },
              ),
              ListTile(
                leading: const Icon(Icons.forward_to_inbox_outlined),
                title: const Text('转发'),
                onTap: () {
                  Navigator.of(context).pop();
                  _showToast('转发功能正在开发中');
                },
              ),
              if (message.isMine && !message.isLocal)
                ListTile(
                  leading: const Icon(Icons.undo, color: Colors.redAccent),
                  title: const Text('撤回'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _confirmRecall(message);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmRecall(ChatMessage message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('撤回消息'),
          content: const Text('确定撤回这条消息吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('撤回'),
            ),
          ],
        );
      },
    );
    if (result != true) return;
    try {
      await _repository.deleteMessage(messageId: message.id);
      if (!mounted) return;
      _showToast('已撤回');
    } catch (error) {
      if (!mounted) return;
      _showToast(NetworkErrorHelper.messageForUser(error, prefix: '撤回失败'));
    }
  }

  void _prefetchRemoteMedia(List<ChatMessage> messages) {
    for (final message in messages) {
      if (message.isMine) {
        continue;
      }
      final url = message.mediaUrl;
      if (url == null || url.isEmpty) {
        continue;
      }
      if (_prefetchedMediaIds.contains(message.id)) {
        continue;
      }
      _prefetchedMediaIds.add(message.id);
      ChatMediaCache.instance.downloadFile(url).then(_noop).catchError(_noop);
    }
  }

  /// 返回 (剩余待发列表, 服务端消息 id -> 对应原 pending 的 id，用于稳定 key 防闪)
  /// 匹配条件：发送者一致、内容一致、且（服务端消息时间与 pending 时间相近，或服务端消息为“刚收到”的我方消息），避免同一条显示两次。
  (List<ChatMessage>, Map<String, String>) _reconcilePendingWithKeys(List<ChatMessage> messages) {
    if (_pendingMessages.isEmpty) {
      return (_pendingMessages, const {});
    }
    const timeWindow = Duration(seconds: 300); // 5 分钟，兼容时钟偏差与网络延迟
    final now = DateTime.now();
    final remaining = <ChatMessage>[];
    final usedServerIds = <String>{};
    final serverIdToPendingId = <String, String>{};
    for (final pending in _pendingMessages) {
      ChatMessage? matchedMessage;
      final pendingTime = pending.time;
      for (final message in messages) {
        if (message.isLocal) continue;
        if (message.senderId != pending.senderId) continue;
        if (message.content != pending.content) continue;
        if (message.replyToMessageId != pending.replyToMessageId) continue;
        if (message.messageType != pending.messageType) continue;
        if (usedServerIds.contains(message.id)) continue;
        final diff = message.time.difference(pendingTime).abs();
        final isRecentFromMe = message.isMine && now.difference(message.time).abs() < timeWindow;
        if (diff > timeWindow && !isRecentFromMe) continue;
        matchedMessage = message;
        usedServerIds.add(message.id);
        serverIdToPendingId[message.id] = pending.id;
        break;
      }
      if (matchedMessage == null) {
        remaining.add(pending);
      }
    }
    return (remaining, serverIdToPendingId);
  }

  List<ChatMessage> _reconcilePending(List<ChatMessage> messages) {
    return _reconcilePendingWithKeys(messages).$1;
  }

  bool _pendingEquals(List<ChatMessage> other) {
    if (other.length != _pendingMessages.length) return false;
    for (var i = 0; i < other.length; i += 1) {
      if (other[i].id != _pendingMessages[i].id) {
        return false;
      }
    }
    return true;
  }

  String _resolveSenderName(ChatMessage message) {
    if (message.senderId == _userId) {
      return _userName;
    }
    final remark = _friendRemarks['id:${message.senderId}'] ??
        _friendRemarks[message.senderId];
    if (remark != null && remark.trim().isNotEmpty) {
      return remark.trim();
    }
    return message.senderName;
  }

  void _openUserProfile(BuildContext context, String userId, String displayName, String? avatarUrl) {
    openUserProfile(context, userId: userId, displayName: displayName, avatarUrl: avatarUrl);
  }

  String _resolveConversationTitle() {
    if (widget.conversation.isGroup && _groupTitle != null && _groupTitle!.trim().isNotEmpty) {
      return _groupTitle!.trim();
    }
    final title = widget.conversation.title;
    final peerId = _peerId ?? widget.conversation.peerId;
    final remark = (peerId == null ? null : _friendRemarks['id:$peerId']) ??
        (peerId == null ? null : _friendRemarks[peerId]) ??
        _friendRemarks['name:$title'] ??
        _friendRemarks['email:$title'] ??
        _friendRemarks[title];
    if (remark != null && remark.trim().isNotEmpty) {
      return remark.trim();
    }
    if (peerId != null && _peerProfile != null) {
      final name = _peerProfile!.displayName.trim();
      if (name.isNotEmpty) return name;
    }
    if (peerId != null && _cachedPeerDisplayName != null && _cachedPeerDisplayName!.trim().isNotEmpty) {
      return _cachedPeerDisplayName!.trim();
    }
    if (peerId != null && title.trim() == _userName.trim()) {
      return '好友';
    }
    return title;
  }

  void _showAvatarFullScreen({String? avatarUrl, required String name}) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: GestureDetector(
            onTap: () => Navigator.of(ctx).pop(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 280,
                    height: 280,
                    child: avatarUrl != null && avatarUrl.trim().isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: avatarUrl.trim(),
                            cacheManager: ChatMediaCache.instance,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => const Center(
                                child: CircularProgressIndicator()),
                            errorWidget: (_, __, ___) => _avatarPlaceholder(name),
                          )
                        : _avatarPlaceholder(name),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _avatarPlaceholder(String name) {
    return Container(
      height: 200,
      width: 200,
      color: const Color(0xFF1A1C21),
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name[0],
        style: const TextStyle(
          color: Color(0xFFD4AF37),
          fontSize: 72,
        ),
      ),
    );
  }

  void _showCallTypePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0E0F14),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.call, color: Color(0xFFD4AF37)),
                title: const Text('语音通话'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _startCall(isVideo: false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam, color: Color(0xFFD4AF37)),
                title: const Text('视频通话'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _startCall(isVideo: true);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _startCall({required bool isVideo}) async {
    final toUserId = _peerId ?? widget.conversation.peerId;
    if (toUserId == null || toUserId.isEmpty) return;
    if (!AgoraConfig.isAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未配置 Agora，无法发起通话')),
        );
      }
      return;
    }
    final fromUserId = _userId;
    final fromUserName = _userName;
    final toUserName = _cachedPeerDisplayName ?? widget.conversation.title;
    final channelId = (AgoraConfig.token != null && AgoraConfig.token!.isNotEmpty)
        ? 'haifeng'
        : 'c_${DateTime.now().millisecondsSinceEpoch}_${fromUserId.hashCode.abs().toRadixString(16)}_${toUserId.hashCode.abs().toRadixString(16)}';
    // 先弹出等待接听画面，邀请在通话页内创建，避免等待 createInvitation 网络导致 2～3 秒延迟
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AgoraCallPage(
          channelId: channelId,
          remoteUserName: toUserName,
          isVideo: isVideo,
          token: AgoraConfig.token,
          invitationId: null,
          isCallee: false,
          callerCreateInvitation: CallerCreateInvitationParams(
            fromUserId: fromUserId,
            fromUserName: fromUserName,
            toUserId: toUserId,
            callType: isVideo ? 'video' : 'voice',
          ),
        ),
      ),
    ).then((_) {
      if (mounted) _loadCallRecords();
    });
  }

  void _showChatOptionsMenu() {
    final peerId = _peerId ?? widget.conversation.peerId;
    final canSetRemark = peerId != null && peerId.isNotEmpty && !widget.conversation.isGroup;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0E0F14),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.conversation.isGroup)
                ListTile(
                  leading: const Icon(Icons.groups),
                  title: const Text('群设置'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GroupSettingsPage(conversation: widget.conversation),
                      ),
                    ).then((_) async {
                      if (!mounted) return;
                      await _refreshGroupInfo();
                    });
                  },
                ),
              if (canSetRemark)
                ListTile(
                  leading: const Icon(Icons.edit_note),
                  title: const Text('设置备注'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showSetRemarkDialog();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.pin_outlined),
                title: const Text('置顶会话'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _togglePinConversation();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: const Text('清空聊天记录'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _confirmClearChat();
                },
              ),
              if (peerId != null && peerId.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('查看个人资料'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TeacherPublicPage(
                          teacherId: peerId,
                          isAlreadyFriend: true,
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showSetRemarkDialog() async {
    final peerId = _peerId ?? widget.conversation.peerId;
    if (peerId == null || peerId.isEmpty) return;
    final current = _resolveConversationTitle();
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('设置备注'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: '输入备注名',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
            onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    if (result == null || !mounted) return;
    try {
      await _friendsRepository.saveRemark(
        userId: _userId,
        friendId: peerId,
        remark: result,
      );
      final key = 'id:$peerId';
      setState(() {
        _friendRemarks = Map.from(_friendRemarks)
          ..[key] = result
          ..[peerId] = result;
      });
      _showToast('备注已保存');
      await _localStore.saveFriendRemark(
        peerId,
        result,
        displayName: _peerProfile?.displayName,
        email: _peerProfile?.email,
      );
    } catch (e) {
      if (mounted) _showToast(NetworkErrorHelper.messageForUser(e, prefix: '保存失败'));
    }
  }

  Future<void> _togglePinConversation() async {
    final pins = await _localStore.loadPinnedConversations();
    final next = Set<String>.from(pins);
    if (next.contains(widget.conversation.id)) {
      next.remove(widget.conversation.id);
      _showToast('已取消置顶');
    } else {
      next.add(widget.conversation.id);
      _showToast('已置顶会话');
    }
    await _localStore.savePinnedConversations(next);
  }

  Future<void> _confirmClearChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('清空聊天记录'),
          content: const Text('确定清空本会话的所有聊天记录吗？此操作不可恢复。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('清空'),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;
    try {
      await _repository.deleteMessagesByConversation(widget.conversation.id);
      await _localStore.saveCachedMessages(
        conversationId: widget.conversation.id,
        currentUserId: _userId,
        messages: [],
      );
      if (mounted) _showToast('已清空聊天记录');
    } catch (e) {
      if (mounted) _showToast(NetworkErrorHelper.messageForUser(e, prefix: '清空失败'));
    }
  }

  Future<void> _refreshGroupInfo() async {
    if (!widget.conversation.isGroup || _userId.isEmpty) return;
    try {
      final info = await _repository.fetchGroupInfo(
        conversationId: widget.conversation.id,
        currentUserId: _userId,
      );
      if (info == null || !mounted) return;
      final membersWithProfile = await _fillMemberAvatarUrls(info.members);
      final myUrl = await _resolveMyAvatarUrl();
      if (!mounted) return;
      final membersWithNames = await _fillMemberDisplayNames(info.members);
      if (!mounted) return;
      setState(() {
        _groupAvatarUrl = info.avatarUrl;
        _groupTitle = info.title;
        _groupAnnouncement = info.announcement;
        _myGroupRole = info.myRole;
        _memberAvatarUrls
          ..clear()
          ..addAll(membersWithProfile);
        _groupMembersWithNames = membersWithNames;
        _myAvatarUrl = myUrl;
      });
      await _localStore.saveGroupAvatarCache(
        conversationId: widget.conversation.id,
        groupAvatarUrl: info.avatarUrl,
        memberAvatarUrls: membersWithProfile,
        myAvatarUrl: myUrl,
      );
    } catch (_) {}
  }

  Future<Map<String, String?>> _fillMemberAvatarUrls(List<GroupMember> members) async {
    final out = <String, String?>{};
    for (final m in members) {
      try {
        final p = await _friendsRepository.findById(m.userId);
        out[m.userId] = p?.avatarUrl?.trim().isNotEmpty == true ? p!.avatarUrl : null;
      } catch (_) {
        out[m.userId] = null;
      }
    }
    return out;
  }

  /// 为群成员补全 displayName，供 @ 提及 列表展示
  Future<List<GroupMember>> _fillMemberDisplayNames(List<GroupMember> members) async {
    final list = <GroupMember>[];
    for (final m in members) {
      String? displayName;
      try {
        final p = await _friendsRepository.findById(m.userId);
        displayName = p?.displayName?.trim().isNotEmpty == true
            ? p!.displayName
            : (p?.email?.split('@').first);
        if (displayName == null || displayName.isEmpty) displayName = m.userId;
      } catch (_) {
        displayName = m.userId;
      }
      list.add(GroupMember(
        userId: m.userId,
        role: m.role,
        displayName: displayName,
        avatarUrl: m.avatarUrl,
        shortId: m.shortId,
      ));
    }
    return list;
  }

  Future<String?> _resolveMyAvatarUrl() async {
    final photo = FirebaseAuth.instance.currentUser?.photoURL?.trim();
    if (photo != null && photo.isNotEmpty) return photo;
    try {
      final p = await _friendsRepository.findById(_userId);
      return p?.avatarUrl?.trim().isNotEmpty == true ? p!.avatarUrl : null;
    } catch (_) {
      return null;
    }
  }

  Widget _buildReplyPreviewBar() {
    final msg = _replyingToMessage;
    if (msg == null) return const SizedBox.shrink();
    final quote = (msg.replyToContent ?? msg.content).trim();
    final preview = quote.length > 40 ? '${quote.substring(0, 40)}…' : quote;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C21),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply, size: 18, color: Color(0xFFD4AF37)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(msg.senderName, style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 12)),
                Text(preview, style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => setState(() => _replyingToMessage = null),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupAnnouncementBanner() {
    final text = _groupAnnouncement?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    final content = GestureDetector(
      onTap: _hideGroupAnnouncement,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        decoration: BoxDecoration(
          color: const Color(0xFFD4AF37).withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.5), width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.campaign_outlined, size: 18, color: Color(0xFFD4AF37)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('群公告', style: TextStyle(color: Color(0xFFD4AF37), fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13), maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    final sizeFactor = _groupAnnouncementSizeFactor;
    if (_groupAnnouncementCollapsing && sizeFactor != null) {
      return SizeTransition(
        sizeFactor: sizeFactor,
        axisAlignment: -1,
        child: content,
      );
    }
    return content;
  }

  static String _formatLastOnline(DateTime lastOnline) {
    final local = lastOnline.isUtc ? lastOnline.toLocal() : lastOnline;
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    final today = DateTime(now.year, now.month, now.day);
    final lastDay = DateTime(local.year, local.month, local.day);
    final days = today.difference(lastDay).inDays;
    final hm = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (days == 0) return '今天 $hm';
    if (days == 1) return '昨天 $hm';
    if (days < 7) return '${days}天前';
    if (local.year == now.year) return '${local.month}月${local.day}日 $hm';
    return '${local.year}年${local.month}月${local.day}日';
  }

  Widget _buildAppBarTitle() {
    final name = _resolveConversationTitle();
    final hasProfile = _peerProfile != null;
    final avatarUrl = widget.conversation.isGroup
        ? (_groupAvatarUrl ?? widget.conversation.avatarUrl ?? _cachedPeerAvatarUrl)
        : (_peerProfile?.avatarUrl ?? _cachedPeerAvatarUrl);
    final showAvatar = avatarUrl?.trim().isNotEmpty == true;
    final levelLabel = hasProfile ? 'Lv ${_peerProfile!.level}' : null;
    final roleLabel = _peerProfile?.roleLabel;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => _showAvatarFullScreen(
            avatarUrl: avatarUrl,
            name: name.isEmpty ? '未知' : name,
          ),
          child: CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFF1A1C21),
            child: showAvatar
                ? ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: avatarUrl!.trim(),
                      cacheManager: ChatMediaCache.instance,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Center(
                        child: Text(
                          name.isEmpty ? '?' : name[0],
                          style: const TextStyle(
                            color: Color(0xFFD4AF37),
                            fontSize: 16,
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Center(
                        child: Text(
                          name.isEmpty ? '?' : name[0],
                          style: const TextStyle(
                            color: Color(0xFFD4AF37),
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  )
                : Text(
                    name.isEmpty ? '?' : name[0],
                    style: const TextStyle(
                      color: Color(0xFFD4AF37),
                      fontSize: 16,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 第一行：名字 = 认证信息（角色、等级同一行）
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      name.isEmpty ? '未知' : name,
                      style: const TextStyle(fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (levelLabel != null || (roleLabel != null && roleLabel.isNotEmpty)) ...[
                    Text(
                      ' · ',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                    if (roleLabel != null && roleLabel.isNotEmpty)
                      RoleBadge(roleLabel: roleLabel, compact: true),
                    if (levelLabel != null) ...[
                      if (roleLabel != null && roleLabel.isNotEmpty) const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0x1AD4AF37),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          levelLabel,
                          style: const TextStyle(
                            color: Color(0xFFD4AF37),
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
              // 第二行：最后上线时间
              if (!widget.conversation.isGroup && _peerProfile?.lastOnlineAt != null) ...[
                const SizedBox(height: 2),
                Text(
                  '最后上线：${_formatLastOnline(_peerProfile!.lastOnlineAt!)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8A8A8A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        leading: widget.onCloseForEmbed != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onCloseForEmbed,
              )
            : null,
        title: _buildAppBarTitle(),
        actions: [
          IconButton(
            onPressed: _showChatOptionsMenu,
            icon: const Icon(Icons.more_horiz),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.conversation.isGroup &&
              _groupAnnouncement != null &&
              _groupAnnouncement!.trim().isNotEmpty &&
              (_groupAnnouncementVisible || _groupAnnouncementCollapsing))
            _buildGroupAnnouncementBanner(),
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              key: ValueKey(widget.conversation.id),
              stream: _messageStream,
              initialData: _cachedMessages,
              builder: (context, snapshot) {
          final hasValidStream = snapshot.connectionState == ConnectionState.active && !snapshot.hasError;
          final messages = (hasValidStream && snapshot.data != null)
              ? snapshot.data!
              : (_cachedMessages ?? widget.initialMessages);
          // 服务端列表按 id 去重，避免 realtime 或缓存导致同一条出现两次
          final messagesById = <String, ChatMessage>{};
          for (final m in messages) {
            if (!m.isLocal) messagesById[m.id] = m;
            else messagesById['local:${m.id}'] = m;
          }
          final dedupedMessages = messagesById.values.toList();
          if (hasValidStream && dedupedMessages.isNotEmpty && _userId.isNotEmpty) {
            _localStore.saveCachedMessages(
              conversationId: widget.conversation.id,
              currentUserId: _userId,
              messages: dedupedMessages,
            );
          }
          dedupedMessages.sort((a, b) => a.time.compareTo(b.time));

          final (reconciledPending, serverIdToPendingId) = _reconcilePendingWithKeys(dedupedMessages);
          // 仅同步内存中的待发列表，不触发 setState，避免服务端消息到达后整页再闪一次
          if (!_pendingEquals(reconciledPending)) {
            _pendingMessages
              ..clear()
              ..addAll(reconciledPending);
          }
          // 展示前再过滤：若服务端已有“同一条”（同人、同内容、同类型且 5 分钟内），不再展示对应 pending，避免发一条出现两条
          const recentWindow = Duration(minutes: 5);
          final now = DateTime.now();
          final pendingToShow = reconciledPending.where((p) {
            final hasSame = dedupedMessages.any((m) =>
                !m.isLocal &&
                m.senderId == p.senderId &&
                m.content == p.content &&
                m.messageType == p.messageType &&
                now.difference(m.time).abs() < recentWindow);
            return !hasSame;
          }).toList();
          final combined = [...dedupedMessages, ...pendingToShow];
          combined.sort((a, b) => a.time.compareTo(b.time));
          final displayMessages = combined.where((m) {
            if (!m.isSystemLeave) return true;
            return _myGroupRole == 'owner' || _myGroupRole == 'admin';
          }).toList();
          // 单聊：把通话记录并入时间线，按时间排序
          final callRecords = widget.conversation.isGroup ? <CallRecord>[] : (_callRecords ?? []);
          final timelineEntries = <_TimelineEntry>[];
          for (final m in displayMessages) {
            timelineEntries.add(_TimelineEntry(time: m.time, message: m, call: null));
          }
          for (final c in callRecords) {
            timelineEntries.add(_TimelineEntry(time: c.createdAt, message: null, call: c));
          }
          timelineEntries.sort((a, b) => a.time.compareTo(b.time));
          final displayEntries = timelineEntries;
          _prefetchRemoteMedia(dedupedMessages);
          if (dedupedMessages.length != _lastMessageCount) {
            _lastMessageCount = dedupedMessages.length;
            if (_userId.isNotEmpty) {
              _repository.markConversationRead(
                conversationId: widget.conversation.id,
                userId: _userId,
              );
            }
            if (_shouldAutoScrollNotifier.value) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scrollController.hasClients) {
                  _scrollController.animateTo(
                    0.0,
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                  );
                }
              });
            }
          }
          if (displayEntries.isEmpty) {
            final noStreamYet = !hasValidStream && !_cacheLoadComplete;
            if (noStreamYet) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
            }
            final offlineEmpty = !hasValidStream && _cacheLoadComplete;
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.chat_bubble_outline,
                    color: Color(0xFF2A2D34),
                    size: 56,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    offlineEmpty ? '无网络，暂无本地缓存' : '还没有聊天记录',
                    style: const TextStyle(color: Color(0xFF6C6F77)),
                  ),
                ],
              ),
            );
          }
          final listView = RepaintBoundary(
            child: ListView.builder(
              key: ValueKey(widget.conversation.id),
              reverse: true,
              controller: _scrollController,
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, _emojiOpen ? 300 : 84, 16, 12),
              itemCount: displayEntries.length,
            itemBuilder: (context, index) {
              final entry = displayEntries[displayEntries.length - 1 - index];
              if (entry.call != null) {
                final record = entry.call!;
                final isMyAction = record.isActionByMe(_userId);
                return Padding(
                  key: ValueKey('call_${record.id}'),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Align(
                    alignment: isMyAction ? Alignment.centerRight : Alignment.centerLeft,
                    child: _CallRecordTile(
                      record: record,
                      currentUserId: _userId,
                      isRightAligned: isMyAction,
                    ),
                  ),
                );
              }
              final message = entry.message!;
              if (message.isSystem) {
                return Padding(
                  key: ValueKey(message.id),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: Text(
                      message.content,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ),
                );
              }
              final resolvedLocalPath = message.localPath ??
                  (message.mediaUrl == null
                      ? null
                      : _localMediaByUrl[message.mediaUrl!]);
              final displaySender = _resolveSenderName(message);
              final stableKey = serverIdToPendingId[message.id] ?? message.id;
              final isGroup = widget.conversation.isGroup;
              final senderAvatarUrl = isGroup
                  ? (message.isMine ? _myAvatarUrl : _memberAvatarUrls[message.senderId])
                  : null;
              final sendFailed = message.isMine && message.isLocal && _failedLocalIds.contains(message.id);
              final showFileProgress = message.isLocal &&
                  message.isFile &&
                  _fileUploadProgress.containsKey(message.id);
              final fileUploadProgress = showFileProgress ? _fileUploadProgress[message.id] : null;
              final bubble = _ChatBubble(
                key: ValueKey(stableKey),
                message: message,
                localPathOverride: resolvedLocalPath,
                displaySenderName: displaySender,
                onLongPress: () => _showMessageActions(message),
                isGroup: isGroup,
                onAvatarTap: isGroup
                    ? (message.isMine
                        ? () => _openUserProfile(context, _userId, _userName, _myAvatarUrl)
                        : () => _openUserProfile(context, message.senderId, message.senderName, senderAvatarUrl))
                    : null,
                senderAvatarUrl: senderAvatarUrl,
                sendFailed: sendFailed,
                onRetry: sendFailed ? () => _retrySendMessage(message) : null,
              );
              if (!showFileProgress) {
                return bubble;
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: message.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  bubble,
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 240),
                      child: LinearProgressIndicator(
                        value: fileUploadProgress,
                        backgroundColor: const Color(0xFF2A2D34),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)),
                      ),
                    ),
                  ),
                ],
              );
            },
            ),
          );
          return listView;
        },
            ),
          ),
        ],
      ),
      bottomNavigationBar: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          top: 8,
          bottom: 10 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_emojiOpen)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _EmojiPanel(
                    onSelect: (emoji) {
                      final text = _textController.text;
                      _textController.text = text + emoji;
                      _textController.selection = TextSelection.fromPosition(
                        TextPosition(offset: _textController.text.length),
                      );
                      if (_shouldAutoScrollNotifier.value) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _scrollToBottom(animated: true);
                        });
                      }
                    },
                  ),
                ),
              if (_isRecording)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text(
                    '录音中…松开发送',
                    style: TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              if (_replyingToMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _buildReplyPreviewBar(),
                ),
              if (_mentionQuery != null && widget.conversation.isGroup)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildMentionOverlay(),
                ),
              Row(
                children: [
                  IconButton(
                    tooltip: _useVoiceInput ? '键盘' : '语音',
                    onPressed: _toggleInputMode,
                    icon: Icon(
                      _useVoiceInput ? Icons.keyboard : Icons.mic_none,
                    ),
                  ),
                  Expanded(
                    child: _useVoiceInput
                        ? GestureDetector(
                            onLongPressStart: (_) => _startRecord(),
                            onLongPressEnd: (_) => _stopRecord(),
                            child: Container(
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFF171B22),
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: const Color(0xFF2A2D34)),
                              ),
                              child: Text(
                                _isRecording ? '松开发送' : '按住 说话',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                          )
                        : TextField(
                            controller: _textController,
                            focusNode: _focusNode,
                            minLines: 1,
                            maxLines: 3,
                            textInputAction: TextInputAction.send,
                            onTap: () {
                              setState(() {
                                if (_emojiOpen) _emojiOpen = false;
                              });
                              if (_groupAnnouncementVisible) _hideGroupAnnouncement();
                            },
                            onSubmitted: (_) {
                              if (!_isSendingNotifier.value) {
                                _sendMessage();
                              }
                            },
                            decoration: InputDecoration(
                              hintText: '输入消息',
                              isDense: true,
                              filled: true,
                              fillColor: const Color(0xFF171B22),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Color(0xFF2A2D34)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Color(0xFF2A2D34)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            style: const TextStyle(color: Color(0xFFE5E7EB), fontSize: 15),
                          ),
                  ),
                  IconButton(
                    onPressed: _openEmojiPanel,
                    icon: const Icon(Icons.emoji_emotions_outlined),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: _hasTextNotifier,
                    builder: (_, hasText, __) {
                      return ValueListenableBuilder<bool>(
                        valueListenable: _isSendingNotifier,
                        builder: (_, isSending, __) {
                          final hasContent = hasText || _textController.text.trim().isNotEmpty;
                          final sendingOrUploading = _isUploading || _isRecording || isSending;
                          if (hasContent)
                            return Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: FilledButton(
                                onPressed: sendingOrUploading ? null : _sendMessage,
                                child: const Text('发送'),
                              ),
                            );
                          return IconButton(
                            onPressed: _openMoreActions,
                            icon: const Icon(Icons.add_circle_outline),
                          );
                        },
                      );
                    },
                  ),
                  if (_isUploading)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _noop(Object _) {}

/// 单条消息旁的头像（群聊显示真实头像，可点击）
class _MessageAvatar extends StatelessWidget {
  const _MessageAvatar({
    this.avatarUrl,
    required this.displayName,
  });

  final String? avatarUrl;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    final initial = displayName.isEmpty ? '?' : displayName[0];
    final showImage = avatarUrl != null && avatarUrl!.trim().isNotEmpty;
    return CircleAvatar(
      radius: 18,
      backgroundColor: const Color(0xFF1A1C21),
      child: showImage
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl: avatarUrl!.trim(),
                cacheManager: ChatMediaCache.instance,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                placeholder: (_, __) => _avatarInitial(initial),
                errorWidget: (_, __, ___) => _avatarInitial(initial),
              ),
            )
          : _avatarInitial(initial),
    );
  }

  static Widget _avatarInitial(String initial) {
    return Center(
      child: Text(
        initial,
        style: const TextStyle(
          color: Color(0xFFD4AF37),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    super.key,
    required this.message,
    this.localPathOverride,
    this.onLongPress,
    required this.displaySenderName,
    this.isGroup = false,
    this.onAvatarTap,
    this.senderAvatarUrl,
    this.sendFailed = false,
    this.onRetry,
  });

  final ChatMessage message;
  final String? localPathOverride;
  final VoidCallback? onLongPress;
  final String displaySenderName;
  final bool isGroup;
  final VoidCallback? onAvatarTap;
  final String? senderAvatarUrl;
  final bool sendFailed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;
    final alignment = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final bubbleColor =
        isMine ? const Color(0xFFD4AF37) : const Color(0xFF111215);
    final hasReply = message.replyToMessageId != null ||
        (message.replyToContent != null && message.replyToContent!.trim().isNotEmpty);
    // 我的消息正文一律黑色（含回复），对方消息白色；引用块单独样式
    final textColor = isMine ? Colors.black : Colors.white;
    final screenWidth = MediaQuery.of(context).size.width;
    final showAvatar = isGroup;
    final maxBubbleWidth = showAvatar
        ? (screenWidth - 16 * 2 - 36 - 8 - 8)
        : (screenWidth * 0.82);
    final initial = displaySenderName.isEmpty ? '?' : displaySenderName[0];

    Widget content = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxBubbleWidth.clamp(0.0, double.infinity)),
      child: Column(
      crossAxisAlignment:
          isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
            displaySenderName,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF8A6D1D),
              ),
            ),
            const SizedBox(height: 4),
            if (hasReply)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Container(
                  constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (bubbleColor == const Color(0xFFD4AF37))
                          ? Colors.black.withOpacity(0.18)
                          : Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(6),
                      border: Border(
                        left: BorderSide(
                          color: isMine ? const Color(0xFFD4AF37) : const Color(0xFF6C6F77),
                          width: 2,
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: RichText(
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                              ),
                              children: [
                                TextSpan(
                                  text: '${message.replyToSenderName ?? '未知'}：',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFD4AF37),
                                  ),
                                ),
                                TextSpan(
                                  text: (message.replyToContent ?? message.content).trim(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            _MessageBody(
              message: message,
              bubbleColor: bubbleColor,
              textColor: textColor,
              localPathOverride: localPathOverride,
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                Text(
                  message.timeLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6C6F77),
                  ),
                ),
                if (sendFailed && onRetry != null) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: onRetry,
                    child: const Icon(
                      Icons.error_outline,
                      size: 18,
                      color: Colors.redAccent,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
    );

    if (showAvatar) {
      content = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: screenWidth - 32),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
          if (!isMine)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: onAvatarTap,
                child: _MessageAvatar(
                  avatarUrl: senderAvatarUrl,
                  displayName: displaySenderName,
                ),
              ),
            ),
          Expanded(
            child: content,
          ),
          if (isMine)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: GestureDetector(
                onTap: onAvatarTap,
                child: _MessageAvatar(
                  avatarUrl: senderAvatarUrl,
                  displayName: displaySenderName,
                ),
            ),
          ),
        ],
        ),
      );
    }

    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        alignment: alignment,
        child: content,
      ),
    );
  }
}

/// 时间线条目：消息或通话记录（用于单聊中合并展示）
class _TimelineEntry {
  _TimelineEntry({required this.time, this.message, this.call});
  final DateTime time;
  final ChatMessage? message;
  final CallRecord? call;
}

/// 聊天内一条通话记录展示（谁操作的显示在谁那边：我操作的右侧，对方操作的左侧）
class _CallRecordTile extends StatelessWidget {
  const _CallRecordTile({
    required this.record,
    required this.currentUserId,
    this.isRightAligned = false,
  });

  final CallRecord record;
  final String currentUserId;
  final bool isRightAligned;

  static String _statusLabel(String status) {
    switch (status) {
      case 'accepted':
        return '已接听';
      case 'rejected':
        return '已拒绝';
      case 'cancelled':
        return '已取消';
      case 'ringing':
      default:
        return '未接听';
    }
  }

  /// 按状态返回图标与文字颜色（已接听偏绿，未接听/已拒绝偏红，已取消灰色）
  static Color _statusColor(String status) {
    switch (status) {
      case 'accepted':
        return const Color(0xFF34C759); // 绿
      case 'rejected':
      case 'ringing':
        return const Color(0xFFFF3B30); // 红
      case 'cancelled':
      default:
        return const Color(0xFF8E8E93); // 灰
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVoice = record.isVoice;
    final label = isVoice ? '语音通话' : '视频通话';
    final statusText = _statusLabel(record.status);
    final statusColor = _statusColor(record.status);
    final isMine = record.isMine(currentUserId);

    final row = Row(
      mainAxisSize: isRightAligned ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: isRightAligned ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (isRightAligned) ...[
          Text(
            record.timeLabel(),
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF8E8E93),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            isVoice ? Icons.call_rounded : Icons.videocam_rounded,
            size: 20,
            color: statusColor,
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: isRightAligned ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFFE5E5EA),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              isMine ? '我 · $statusText' : '对方 · $statusText',
              style: TextStyle(
                fontSize: 13,
                color: statusColor,
              ),
            ),
          ],
        ),
        if (!isRightAligned) ...[
          const SizedBox(width: 12),
          Text(
            record.timeLabel(),
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF8E8E93),
            ),
          ),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: row,
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF171B22),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2A2D34)),
              ),
              child: Icon(icon, color: Colors.white70),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmojiPanel extends StatelessWidget {
  const _EmojiPanel({required this.onSelect});

  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    const emojis = [
      '😀',
      '😂',
      '😍',
      '👍',
      '🙏',
      '🔥',
      '💯',
      '🎉',
      '😅',
      '😭',
      '😡',
      '🤔',
      '😎',
      '🥳',
      '💔',
      '😴',
      '🤝',
      '👏',
      '⭐',
      '✅',
    ];
    return Container(
      height: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0F14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2D34)),
      ),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: emojis.map((emoji) {
            return InkWell(
              onTap: () => onSelect(emoji),
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF171B22),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF2A2D34)),
                ),
                child: Text(
                  emoji,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _MessageBody extends StatelessWidget {
  const _MessageBody({
    required this.message,
    required this.bubbleColor,
    required this.textColor,
    this.localPathOverride,
  });

  final ChatMessage message;
  final Color bubbleColor;
  final Color textColor;
  final String? localPathOverride;

  @override
  Widget build(BuildContext context) {
    if (message.isImage && message.mediaUrl != null) {
      return _MediaContainer(
        color: bubbleColor,
        child: _ImageMessageCard(
          url: message.mediaUrl!,
          localPath: localPathOverride ?? message.localPath,
        ),
      );
    }
    if (message.isVideo && message.mediaUrl != null) {
      final videoUrl = message.mediaUrlTranscoded ?? message.mediaUrl!;
      return _MediaContainer(
        color: bubbleColor,
        child: _VideoMessageCard(
          url: videoUrl,
          localPath: localPathOverride ?? message.localPath,
        ),
      );
    }
    if (message.isAudio) {
      return _MediaContainer(
        color: bubbleColor,
        child: _AudioMessageCard(
          messageId: message.id,
          url: message.mediaUrl,
          localPath: localPathOverride ?? message.localPath,
          durationMs: message.durationMs,
          isMine: message.isMine,
        ),
      );
    }
    if (message.isFile && message.mediaUrl != null) {
      return _MediaContainer(
        color: bubbleColor,
        child: _FileMessageCard(
          url: message.mediaUrl!,
          content: message.content,
        ),
      );
    }
    return _MediaContainer(
      color: bubbleColor,
      child: _LinkifiedMessageText(
        content: message.content,
        textColor: textColor,
      ),
    );
  }
}

/// 解析并展示可点击的链接与电话号码。
class _LinkifiedMessageText extends StatelessWidget {
  const _LinkifiedMessageText({
    required this.content,
    required this.textColor,
  });

  final String content;
  final Color textColor;

  static final RegExp _urlPattern = RegExp(
    r'(teacherhub://\S+|https?://[^\s]+)',
    caseSensitive: false,
  );
  static final RegExp _phonePattern = RegExp(r'1[3-9]\d{9}');

  static List<_ContentSegment> _parse(String text) {
    if (text.isEmpty) return [];
    final segments = <_ContentSegment>[];
    int pos = 0;
    while (pos < text.length) {
      _MatchResult? earliest;
      final urlMatch = _urlPattern.firstMatch(text.substring(pos));
      if (urlMatch != null) {
        earliest = _MatchResult(pos + urlMatch.start, pos + urlMatch.end, urlMatch.group(0)!, true, false);
      }
      final phoneMatch = _phonePattern.firstMatch(text.substring(pos));
      if (phoneMatch != null) {
        final start = pos + phoneMatch.start;
        final end = pos + phoneMatch.end;
        final value = phoneMatch.group(0)!;
        if (earliest == null || start < earliest.start) {
          earliest = _MatchResult(start, end, value, false, true);
        }
      }
      if (earliest == null) {
        segments.add(_ContentSegment(text.substring(pos), false, false));
        break;
      }
      if (earliest.start > pos) {
        segments.add(_ContentSegment(text.substring(pos, earliest.start), false, false));
      }
      segments.add(_ContentSegment(earliest.value, earliest.isLink, earliest.isPhone));
      pos = earliest.end;
    }
    return segments;
  }

  @override
  Widget build(BuildContext context) {
    final segments = _parse(content);
    if (segments.isEmpty) return Text(content, style: TextStyle(color: textColor));
    if (segments.length == 1 && !segments.first.isLink && !segments.first.isPhone) {
      return Text(content, style: TextStyle(color: textColor));
    }
    return RichText(
      text: TextSpan(
        style: TextStyle(color: textColor, fontSize: 16),
        children: segments.map<InlineSpan>((s) {
          if (s.isLink || s.isPhone) {
            const linkColor = Color(0xFF2196F3); // 蓝色，明确表示可点击
            return TextSpan(
              text: s.text,
              style: const TextStyle(
                color: linkColor,
                decoration: TextDecoration.underline,
                decorationColor: linkColor,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => _onTap(context, s.text, isPhone: s.isPhone),
            );
          }
          return TextSpan(text: s.text);
        }).toList(),
      ),
    );
  }

  static Future<void> _onTap(BuildContext context, String value, {required bool isPhone}) async {
    if (isPhone) {
      final uri = Uri.parse('tel:$value');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }
    final uri = Uri.tryParse(value);
    if (uri == null) return;
    // 应用内直接处理群邀请链接，弹出加入确认并加入群
    if (uri.scheme == 'teacherhub' && uri.host == 'group' && uri.path.startsWith('/join')) {
      await handleGroupJoinUri(uri);
      return;
    }
    // 聊天文件/媒体链接：先下载到本地再用系统应用打开，不跳浏览器
    if (uri.host.contains('supabase.co') && uri.path.contains('/storage/')) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('正在打开…'), duration: Duration(seconds: 1)),
      );
      try {
        final file = await ChatMediaCache.instance.getSingleFile(value);
        if (!context.mounted) return;
        final result = await OpenFilex.open(file.path);
        if (!context.mounted) return;
        if (result.type != ResultType.done) {
          messenger.showSnackBar(
            SnackBar(content: Text(result.message ?? '无法打开该文件')),
          );
        }
      } catch (_) {
        if (!context.mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('文件已过期或不存在，请让对方重新发送')),
        );
      }
      return;
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _MatchResult {
  _MatchResult(this.start, this.end, this.value, this.isLink, this.isPhone);
  final int start;
  final int end;
  final String value;
  final bool isLink;
  final bool isPhone;
}

class _ContentSegment {
  _ContentSegment(this.text, this.isLink, this.isPhone);
  final String text;
  final bool isLink;
  final bool isPhone;
}

class _MediaContainer extends StatelessWidget {
  const _MediaContainer({
    required this.child,
    required this.color,
  });

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2D34)),
      ),
      child: child,
    );
  }
}

class _VideoMessageCard extends StatelessWidget {
  const _VideoMessageCard({required this.url, this.localPath});

  final String url;
  final String? localPath;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth * 0.62;
    return InkWell(
      onTap: () {
        final source = localPath != null && File(localPath!).existsSync()
            ? localPath!
            : url;
        showDialog(
          context: context,
          builder: (context) => _MediaKitVideoDialog(
            source: source,
          ),
        );
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: 200,
          maxWidth: cardWidth.clamp(200, 280),
        ),
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0D0F14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child:
                  Icon(Icons.play_circle_fill, size: 42, color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoPreviewDialog extends StatefulWidget {
  const _VideoPreviewDialog({required this.url, this.localPath});

  final String url;
  final String? localPath;

  @override
  State<_VideoPreviewDialog> createState() => _VideoPreviewDialogState();
}

class _VideoPreviewDialogState extends State<_VideoPreviewDialog> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _loading = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _resetPlayer() async {
    await _controller?.dispose();
    _controller = null;
  }

  Future<void> _initPlayer() async {
    try {
      final localPath = widget.localPath;
      if (localPath != null && File(localPath).existsSync()) {
        await _resetPlayer();
        _controller = VideoPlayerController.file(File(localPath));
      } else {
        await _resetPlayer();
        final file = await ChatMediaCache.instance.getSingleFile(widget.url);
        _controller = VideoPlayerController.file(file);
      }
      await _controller!.initialize();
      if (_controller!.value.hasError) {
        throw Exception(_controller!.value.errorDescription ?? 'unknown error');
      }
      if (mounted) {
        setState(() {
          _ready = true;
          _loading = false;
          _errorText = null;
        });
      }
    } catch (_) {
      try {
        await _resetPlayer();
        _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
        await _controller!.initialize();
        if (_controller!.value.hasError) {
          throw Exception(_controller!.value.errorDescription ?? 'unknown error');
        }
        if (mounted) {
          setState(() {
            _ready = true;
            _loading = false;
            _errorText = null;
          });
        }
      } catch (error) {
        if (mounted) {
          setState(() {
            _loading = false;
            _errorText = NetworkErrorHelper.messageForUser(error, prefix: '视频加载失败');
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      contentPadding: const EdgeInsets.all(12),
      content: SizedBox(
        width: 300,
        child: _ready && _controller != null
            ? AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(_controller!),
                    IconButton(
                      onPressed: () {
                        if (_controller!.value.isPlaying) {
                          _controller!.pause();
                        } else {
                          _controller!.play();
                        }
                        setState(() {});
                      },
                      icon: Icon(
                        _controller!.value.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill,
                        size: 48,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: Center(
                  child: _loading
                      ? const CircularProgressIndicator()
                      : SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.broken_image),
                              const SizedBox(height: 8),
                              if (_errorText != null)
                                Text(
                                  _errorText!,
                                  style: const TextStyle(color: Colors.white70),
                                  textAlign: TextAlign.center,
                                ),
                              TextButton(
                                onPressed: () {
                                  final source = widget.localPath != null &&
                                          File(widget.localPath!).existsSync()
                                      ? widget.localPath!
                                      : widget.url;
                                  showDialog(
                                    context: context,
                                    builder: (context) => _MediaKitVideoDialog(
                                      source: source,
                                    ),
                                  );
                                },
                                child: const Text('使用兼容播放器'),
                              ),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _loading = true;
                                    _ready = false;
                                  });
                                  _initPlayer();
                                },
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
      ),
    );
  }
}

class _ImageMessageCard extends StatelessWidget {
  const _ImageMessageCard({required this.url, this.localPath});

  final String url;
  final String? localPath;

  @override
  Widget build(BuildContext context) {
    final localFile = localPath == null ? null : File(localPath!);
    return InkWell(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => _ImagePreviewDialog(
            url: url,
            localPath: localPath,
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: (localFile != null && localFile.existsSync())
            ? Image.file(
                localFile,
                width: 220,
                height: 160,
                fit: BoxFit.cover,
              )
            : CachedNetworkImage(
                imageUrl: url,
                cacheManager: ChatMediaCache.instance,
                width: 220,
                height: 160,
                fit: BoxFit.cover,
                memCacheWidth: 480,
                placeholder: (context, _) => const SizedBox(
                  width: 220,
                  height: 160,
                  child:
                      Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                errorWidget: (context, _, __) => const SizedBox(
                  width: 220,
                  height: 160,
                  child: Center(child: Icon(Icons.broken_image)),
                ),
              ),
      ),
    );
  }
}

class _ImagePreviewDialog extends StatefulWidget {
  const _ImagePreviewDialog({required this.url, this.localPath});

  final String url;
  final String? localPath;

  @override
  State<_ImagePreviewDialog> createState() => _ImagePreviewDialogState();
}

class _ImagePreviewDialogState extends State<_ImagePreviewDialog> {
  Future<File?>? _fileFuture;

  @override
  void initState() {
    super.initState();
    _fileFuture = _loadFile();
  }

  Future<File?> _loadFile() async {
    final localPath = widget.localPath;
    if (localPath != null) {
      final localFile = File(localPath);
      if (localFile.existsSync()) {
        return localFile;
      }
    }
    try {
      return await ChatMediaCache.instance.getSingleFile(widget.url);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FutureBuilder<File?>(
          future: _fileFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 240,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            final file = snapshot.data;
            if (file == null) {
              return SizedBox(
                height: 240,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.broken_image, color: Colors.white70),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _fileFuture = _loadFile();
                          });
                        },
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              );
            }
            return InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Image.file(file, fit: BoxFit.contain),
            );
          },
        ),
      ),
    );
  }
}

/// 文件消息：图标 + 文案，点击先下载/取缓存再用系统应用打开（不跳浏览器）
class _FileMessageCard extends StatelessWidget {
  const _FileMessageCard({
    required this.url,
    required this.content,
  });

  final String url;
  final String content;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        if (url.isEmpty) return;
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          const SnackBar(content: Text('正在打开…'), duration: Duration(seconds: 1)),
        );
        try {
          final file = await ChatMediaCache.instance.getSingleFile(url);
          if (!context.mounted) return;
          final result = await OpenFilex.open(file.path);
          if (!context.mounted) return;
          if (result.type != ResultType.done) {
            messenger.showSnackBar(
              SnackBar(content: Text(result.message ?? '无法打开该文件')),
            );
          }
        } catch (_) {
          if (!context.mounted) return;
          messenger.showSnackBar(
            const SnackBar(
              content: Text('文件已过期或不存在，请让对方重新发送'),
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file_outlined, size: 28, color: Colors.white70),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                content.isNotEmpty ? content : '文件',
                style: const TextStyle(color: Colors.white, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.open_in_new, size: 16, color: Colors.white54),
          ],
        ),
      ),
    );
  }
}

class _AudioMessageCard extends StatefulWidget {
  const _AudioMessageCard({
    required this.messageId,
    required this.isMine,
    this.url,
    this.localPath,
    this.durationMs,
  });

  final String messageId;
  final bool isMine;
  final String? url;
  final String? localPath;
  final int? durationMs;

  @override
  State<_AudioMessageCard> createState() => _AudioMessageCardState();
}

class _AudioMessageCardState extends State<_AudioMessageCard> {
  final AudioPlayer _player = AudioPlayer();
  bool _ready = false;
  bool _playing = false;
  Duration? _loadedDuration;

  @override
  void initState() {
    super.initState();
    if (widget.url != null || widget.localPath != null) {
      _initPlayer();
    } else {
      _ready = false;
    }
    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _playing = state.playing;
      });
    });
    _player.durationStream.listen((d) {
      if (!mounted) return;
      setState(() {
        _loadedDuration = d;
      });
    });
  }

  Future<void> _initPlayer() async {
    try {
      final localPath = widget.localPath;
      if (localPath != null && File(localPath).existsSync()) {
        await _player.setFilePath(localPath);
      } else if (widget.url != null && widget.url!.isNotEmpty) {
        final file = await ChatMediaCache.instance.getSingleFile(widget.url!);
        await _player.setFilePath(file.path);
      }
      if (mounted) {
        setState(() {
          _ready = true;
          _loadedDuration = _player.duration;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _ready = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  int? get _displayDurationMs {
    if (_loadedDuration != null && _loadedDuration!.inMilliseconds > 0) {
      return _loadedDuration!.inMilliseconds;
    }
    return widget.durationMs;
  }

  static String _formatDuration(int? ms) {
    if (ms == null || ms <= 0) return '0:00';
    final sec = ms ~/ 1000;
    final m = sec ~/ 60;
    final s = sec % 60;
    if (m > 0) {
      return '$m:${s.toString().padLeft(2, '0')}';
    }
    return '0:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isMine = widget.isMine;
    final playBg = isMine ? const Color(0xFF2C2C2C) : const Color(0xFFE8E8E8);
    final playIconColor = isMine ? Colors.white : const Color(0xFF333333);
    final waveColor = isMine ? Colors.white70 : const Color(0xFF555555);
    final durationColor = isMine ? const Color(0xFF1a1a1a) : const Color(0xFF333333);
    final durationMs = _displayDurationMs;
    final durationText = _formatDuration(durationMs);

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _ready
                  ? () {
                      if (_playing) {
                        _player.pause();
                      } else {
                        _player.play();
                      }
                    }
                  : null,
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: playBg,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: playIconColor,
                  size: 28,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _VoiceWaveform(
                  messageId: widget.messageId,
                  durationMs: durationMs ?? 0,
                  barColor: waveColor,
                ),
                const SizedBox(height: 6),
                Text(
                  durationText,
                  style: TextStyle(
                    color: durationColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
          ),
        ],
      ),
    );
  }
}

class _VoiceWaveform extends StatelessWidget {
  const _VoiceWaveform({
    required this.messageId,
    required this.durationMs,
    required this.barColor,
  });

  final String messageId;
  final int durationMs;
  final Color barColor;

  static const int _barCount = 28;
  static const double _barWidth = 2.5;
  static const double _barGap = 2.0;
  static const double _maxBarHeight = 16.0;
  static const double _minBarHeight = 4.0;

  List<double> _heights() {
    final seed = messageId.hashCode.abs();
    final heights = <double>[];
    for (var i = 0; i < _barCount; i++) {
      final t = (seed + i * 31) % 1000 / 1000.0;
      final wave = 0.5 + 0.5 * _sinApprox((i / _barCount) * 3.14 * 4 + t * 6.28);
      final h = _minBarHeight + wave * (_maxBarHeight - _minBarHeight);
      heights.add(h);
    }
    return heights;
  }

  double _sinApprox(double x) {
    x = x % 6.28318;
    if (x > 3.14159) x -= 6.28318;
    return x - x * x.abs() / 3.14159 * 0.5;
  }

  @override
  Widget build(BuildContext context) {
    final heights = _heights();
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(_barCount, (i) {
        return Container(
          width: _barWidth,
          height: heights[i],
          margin: EdgeInsets.only(
            left: i == 0 ? 0 : _barGap / 2,
            right: i == _barCount - 1 ? 0 : _barGap / 2,
          ),
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: BorderRadius.circular(_barWidth / 2),
          ),
        );
      }),
    );
  }
}

class _MediaKitVideoDialog extends StatefulWidget {
  const _MediaKitVideoDialog({required this.source});

  final String source;

  @override
  State<_MediaKitVideoDialog> createState() => _MediaKitVideoDialogState();
}

class _MediaKitVideoDialogState extends State<_MediaKitVideoDialog> {
  late final Player _player;
  late final VideoController _controller;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _player.open(Media(widget.source), play: true);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: Colors.black,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Video(controller: _controller),
      ),
    );
  }
}
