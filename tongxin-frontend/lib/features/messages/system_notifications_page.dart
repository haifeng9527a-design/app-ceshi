import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../core/network_error_helper.dart';
import '../../core/pc_dashboard_theme.dart';
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
        SnackBar(content: Text(AppLocalizations.of(context)!.msgFriendRequestAccepted)),
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
          SnackBar(content: Text(AppLocalizations.of(context)!.msgOpenChatFromList)),
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
        SnackBar(content: Text(NetworkErrorHelper.messageForUser(error, prefix: AppLocalizations.of(context)!.msgAcceptFailed, l10n: AppLocalizations.of(context)))),
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
        SnackBar(content: Text(NetworkErrorHelper.messageForUser(error, prefix: AppLocalizations.of(context)!.msgRejectFailed, l10n: AppLocalizations.of(context)))),
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
      backgroundColor: PcDashboardTheme.surface,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.messagesSystemNotifications, style: PcDashboardTheme.titleMedium),
        backgroundColor: PcDashboardTheme.surfaceVariant,
        foregroundColor: PcDashboardTheme.text,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: userId.isEmpty
          ? Center(child: Text(AppLocalizations.of(context)!.teachersPleaseLoginFirst, style: PcDashboardTheme.bodyLarge))
          : StreamBuilder<List<FriendRequestItem>>(
              stream: _friendsRepository.watchAllFriendRequestRecords(userId: userId),
              builder: (context, snapshot) {
                final items = snapshot.data ?? const <FriendRequestItem>[];
                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(PcDashboardTheme.contentPadding),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.notifications_none_outlined,
                            size: 64,
                            color: PcDashboardTheme.textMuted,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            AppLocalizations.of(context)!.msgSystemNotificationsEmptyHint,
                            style: PcDashboardTheme.bodyLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            AppLocalizations.of(context)!.msgNoSystemNotifications,
                            style: PcDashboardTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(PcDashboardTheme.contentPadding),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final busy = _isBusy(item.requestId);
                    final l10n = AppLocalizations.of(context)!;
                    final idLabel = item.otherShortId?.trim().isNotEmpty == true
                        ? l10n.profileAccountIdValue(item.otherShortId!.trim())
                        : l10n.profileAccountIdDash;
                    String statusLabel;
                    if (item.isOutgoing) {
                      statusLabel = item.isPending
                          ? l10n.msgPendingOther
                          : (item.isAccepted ? l10n.msgAccepted : l10n.msgRejected);
                    } else {
                      statusLabel = item.isPending
                          ? l10n.msgRequestAddYou
                          : (item.isAccepted ? l10n.msgAccepted : l10n.msgRejected);
                    }
                    final showActions =
                        !item.isOutgoing && item.isPending;
                    final avatarUrl = item.otherAvatar?.trim() ?? '';
                    final initial = item.otherDisplayName.isEmpty
                        ? (AppLocalizations.of(context)!.commonUser.isNotEmpty ? AppLocalizations.of(context)!.commonUser[0] : '?')
                        : item.otherDisplayName[0];
                    return Container(
                      decoration: PcDashboardTheme.cardDecoration(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: PcDashboardTheme.surfaceElevated,
                            child: avatarUrl.isNotEmpty
                                ? ClipOval(
                                    child: CachedNetworkImage(
                                      imageUrl: avatarUrl,
                                      cacheManager: ChatMediaCache.instance,
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.cover,
                                      fadeInDuration: Duration.zero,
                                      fadeOutDuration: Duration.zero,
                                      placeholder: (_, __) => Center(
                                        child: Text(
                                          initial,
                                          style: PcDashboardTheme.titleSmall.copyWith(
                                            color: PcDashboardTheme.accent,
                                          ),
                                        ),
                                      ),
                                      errorWidget: (_, __, ___) => Center(
                                        child: Text(
                                          initial,
                                          style: PcDashboardTheme.titleSmall.copyWith(
                                            color: PcDashboardTheme.accent,
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                : Text(
                                    initial,
                                    style: PcDashboardTheme.titleSmall.copyWith(
                                      color: PcDashboardTheme.accent,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  item.otherDisplayName,
                                  style: PcDashboardTheme.titleSmall,
                                ),
                                const SizedBox(height: 2),
                                Text(idLabel, style: PcDashboardTheme.bodySmall),
                                if (item.isOutgoing) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    l10n.msgYouRequestAddFriend,
                                    style: PcDashboardTheme.bodySmall,
                                  ),
                                ],
                                const SizedBox(height: 2),
                                Text(
                                  statusLabel,
                                  style: PcDashboardTheme.bodySmall.copyWith(
                                    color: item.isPending
                                        ? PcDashboardTheme.accent
                                        : PcDashboardTheme.textMuted,
                                  ),
                                ),
                                if (item.createdAt != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatTime(item.createdAt),
                                    style: PcDashboardTheme.label,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (showActions)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => _rejectRequest(item),
                                  child: Text(
                                    l10n.callDecline,
                                    style: PcDashboardTheme.titleSmall.copyWith(
                                      color: PcDashboardTheme.textSecondary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: busy
                                      ? null
                                      : () => _acceptRequest(item, userId),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: PcDashboardTheme.accent,
                                    foregroundColor: PcDashboardTheme.surface,
                                  ),
                                  child: Text(
                                    l10n.msgAcceptShort,
                                    style: PcDashboardTheme.titleSmall.copyWith(
                                      color: PcDashboardTheme.surface,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            Text(
                              statusLabel,
                              style: PcDashboardTheme.bodySmall,
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
