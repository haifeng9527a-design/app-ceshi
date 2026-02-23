import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/network_error_helper.dart';
import 'chat_detail_page.dart';
import 'chat_media_cache.dart';
import 'friend_models.dart';
import 'friends_repository.dart';
import 'message_models.dart';
import 'messages_repository.dart';

class SystemNotificationsPage extends StatefulWidget {
  const SystemNotificationsPage({super.key});

  @override
  State<SystemNotificationsPage> createState() =>
      _SystemNotificationsPageState();
}

class _SystemNotificationsPageState extends State<SystemNotificationsPage> {
  final _friendsRepository = FriendsRepository();
  final Map<String, bool> _busyRequest = {};

  bool _isBusy(String requestId) => _busyRequest[requestId] == true;

  Future<void> _acceptRequest(
    FriendRequestItem item,
    String receiverId,
  ) async {
    setState(() => _busyRequest[item.requestId] = true);
    try {
      await _friendsRepository.acceptRequest(
        requestId: item.requestId,
        requesterId: item.requesterId,
        receiverId: receiverId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已通过，已添加为好友')),
      );
      // 立即跳转到和该好友的聊天窗口
      final repo = MessagesRepository();
      final conversation = await repo.createOrGetDirectConversation(
        currentUserId: receiverId,
        friendId: item.requesterId,
        friendName: item.requesterName,
      );
      if (!mounted) return;
      if (conversation.isGroup) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('打开私聊失败，请从消息列表进入')),
        );
        return;
      }
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatDetailPage(
            conversation: conversation,
            initialMessages: const <ChatMessage>[],
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(NetworkErrorHelper.messageForUser(error, prefix: '通过失败'))),
      );
    } finally {
      if (mounted) {
        setState(() => _busyRequest[item.requestId] = false);
      }
    }
  }

  Future<void> _rejectRequest(FriendRequestItem item) async {
    setState(() => _busyRequest[item.requestId] = true);
    try {
      await _friendsRepository.rejectRequest(requestId: item.requestId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(NetworkErrorHelper.messageForUser(error, prefix: '拒绝失败'))),
      );
    } finally {
      if (mounted) {
        setState(() => _busyRequest[item.requestId] = false);
      }
    }
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final t = dt.isUtc ? dt.toLocal() : dt;
    final now = DateTime.now();
    final sameDay = now.year == t.year && now.month == t.month && now.day == t.day;
    if (sameDay) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    return '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('系统消息'),
      ),
      body: userId.isEmpty
          ? const Center(child: Text('请先登录'))
          : StreamBuilder<List<FriendRequestItem>>(
              stream: _friendsRepository.watchAllFriendRequestRecords(userId: userId),
              builder: (context, snapshot) {
                final items = snapshot.data ?? const <FriendRequestItem>[];
                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.notifications_none_outlined,
                            size: 64,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '好友申请、通过/拒绝记录会显示在这里',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '暂无系统消息',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final busy = _isBusy(item.requestId);
                    final idLabel = item.otherShortId?.trim().isNotEmpty == true
                        ? '账号ID ${item.otherShortId!.trim()}'
                        : '账号ID —';
                    String statusLabel;
                    if (item.isOutgoing) {
                      statusLabel = item.isPending
                          ? '待对方处理'
                          : (item.isAccepted ? '已通过' : '已拒绝');
                    } else {
                      statusLabel = item.isPending
                          ? '请求添加你为好友'
                          : (item.isAccepted ? '已通过' : '已拒绝');
                    }
                    final showActions =
                        !item.isOutgoing && item.isPending;
                    final avatarUrl = item.otherAvatar?.trim() ?? '';
                    final initial = item.otherDisplayName.isEmpty
                        ? '用'
                        : item.otherDisplayName[0];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF1A1C21),
                          child: avatarUrl.isNotEmpty
                              ? ClipOval(
                                  child: CachedNetworkImage(
                                    imageUrl: avatarUrl,
                                    cacheManager: ChatMediaCache.instance,
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Center(
                                      child: Text(
                                        initial,
                                        style: const TextStyle(
                                            color: Color(0xFFD4AF37)),
                                      ),
                                    ),
                                    errorWidget: (_, __, ___) => Center(
                                      child: Text(
                                        initial,
                                        style: const TextStyle(
                                            color: Color(0xFFD4AF37)),
                                      ),
                                    ),
                                  ),
                                )
                              : Text(
                                  initial,
                                  style: const TextStyle(
                                      color: Color(0xFFD4AF37)),
                                ),
                        ),
                        title: Text(item.otherDisplayName),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              idLabel,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6C6F77),
                              ),
                            ),
                            if (item.isOutgoing) ...[
                              const SizedBox(height: 2),
                              Text(
                                '你请求添加 Ta 为好友',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF6C6F77),
                                ),
                              ),
                            ],
                            const SizedBox(height: 2),
                            Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 12,
                                color: item.isPending
                                    ? const Color(0xFFD4AF37)
                                    : const Color(0xFF6C6F77),
                              ),
                            ),
                            if (item.createdAt != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                _formatTime(item.createdAt),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF6C6F77),
                                ),
                              ),
                            ],
                          ],
                        ),
                        trailing: showActions
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => _rejectRequest(item),
                                    child: const Text('拒绝'),
                                  ),
                                  const SizedBox(width: 6),
                                  FilledButton(
                                    onPressed: busy
                                        ? null
                                        : () => _acceptRequest(item, userId),
                                    child: const Text('通过'),
                                  ),
                                ],
                              )
                            : Text(
                                statusLabel,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF6C6F77),
                                ),
                              ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
