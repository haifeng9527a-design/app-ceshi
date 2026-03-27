import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/network_error_helper.dart';
import '../../l10n/app_localizations.dart';
import 'chat_media_cache.dart';
import 'chat_detail_page.dart';
import 'friends_repository.dart';
import 'messages_repository.dart';
import '../teachers/teacher_public_page.dart';
import '../teachers/teacher_repository.dart';

/// 打开用户资料：交易员走 TeacherPublicPage（申请关注），否则走 UserProfilePage（加好友）
Future<void> openUserProfile(
  BuildContext context, {
  required String userId,
  required String displayName,
  String? avatarUrl,
  String? roleLabel,
  bool forceUserProfile = false,
}) async {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  if (userId.isEmpty || userId == currentUserId) return;
  final normalizedRole = (roleLabel ?? '').trim().toLowerCase();
  final roleSuggestsTeacher = normalizedRole == 'teacher' ||
      normalizedRole == 'trader' ||
      normalizedRole == '交易员';

  void openNormalProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfilePage(
          userId: userId,
          displayName:
              displayName.isEmpty ? AppLocalizations.of(context)!.msgNoNicknameSet : displayName,
          avatarUrl: avatarUrl,
        ),
      ),
    );
  }

  // 客服/普通用户强制走用户资料页；只有明确交易员角色才尝试进入交易员资料页。
  if (forceUserProfile || !roleSuggestsTeacher) {
    if (!context.mounted) return;
    openNormalProfile();
    return;
  }

  final teacherRepo = TeacherRepository();
  final profile = await teacherRepo.fetchProfile(userId);
  final friendsRepo = FriendsRepository();
  final isFriend = await friendsRepo.isFriend(userId: currentUserId, friendId: userId);
  if (!context.mounted) return;
  if (profile != null) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeacherPublicPage(
          teacherId: userId,
          isAlreadyFriend: isFriend,
        ),
      ),
    );
  } else {
    openNormalProfile();
  }
}

/// 非交易员用户资料页：加好友、发消息
class UserProfilePage extends StatelessWidget {
  const UserProfilePage({
    super.key,
    required this.userId,
    required this.displayName,
    this.avatarUrl,
  });

  final String userId;
  final String displayName;
  final String? avatarUrl;

  static const Color _accent = Color(0xFFD4AF37);
  static const Color _muted = Color(0xFF6C6F77);

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isSelf = currentUserId == userId;
    final friendsRepo = FriendsRepository();
    final messagesRepo = MessagesRepository();

    return Scaffold(
      backgroundColor: const Color(0xFF111215),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _accent, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          AppLocalizations.of(context)!.profilePersonalInfo,
          style: const TextStyle(color: _accent, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 24),
            CircleAvatar(
              radius: 48,
              backgroundColor: const Color(0xFF1A1C21),
              child: avatarUrl != null && avatarUrl!.trim().isNotEmpty
                  ? ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: avatarUrl!.trim(),
                        cacheManager: ChatMediaCache.instance,
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        placeholder: (_, __) => Center(
                          child: Text(
                            displayName.isEmpty ? '?' : displayName[0],
                            style: const TextStyle(
                              fontSize: 36,
                              color: _accent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Center(
                          child: Text(
                            displayName.isEmpty ? '?' : displayName[0],
                            style: const TextStyle(
                              fontSize: 36,
                              color: _accent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    )
                  : Text(
                      displayName.isEmpty ? '?' : displayName[0],
                      style: const TextStyle(
                        fontSize: 36,
                        color: _accent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Text(
              displayName.isEmpty ? AppLocalizations.of(context)!.msgNoNicknameSet : displayName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            if (isSelf) ...[
              const SizedBox(height: 24),
              Text(AppLocalizations.of(context)!.profileItsYou, style: const TextStyle(color: _muted)),
            ] else ...[
              const SizedBox(height: 32),
              FutureBuilder<bool>(
                future: friendsRepo.isFriend(userId: currentUserId, friendId: userId),
                builder: (context, snapshot) {
                  final isFriend = snapshot.data ?? false;
                  // 已是好友：只显示「发消息」；非好友：只显示「加好友」，不两个一起展示
                  return SizedBox(
                    width: double.infinity,
                    child: isFriend
                        ? FilledButton(
                            onPressed: () => _openChat(context, messagesRepo),
                            style: FilledButton.styleFrom(
                              backgroundColor: _accent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              AppLocalizations.of(context)!.msgSendMessage,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          )
                        : FilledButton(
                            onPressed: () => _sendFriendRequest(context, friendsRepo),
                            style: FilledButton.styleFrom(
                              backgroundColor: _accent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              AppLocalizations.of(context)!.msgAddFriend,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _sendFriendRequest(BuildContext context, FriendsRepository repo) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUserId.isEmpty) return;
    try {
      await repo.sendFriendRequest(requesterId: currentUserId, receiverId: userId);
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.msgFriendRequestSent)));
      }
    } catch (e) {
      if (context.mounted) {
        final msg = e.toString();
        String displayMsg;
        if (msg.contains('already_friends')) {
          displayMsg = AppLocalizations.of(context)!.msgAlreadyFriends;
        } else if (msg.contains('already_pending')) {
          displayMsg = AppLocalizations.of(context)!.msgAlreadyPending;
        } else {
          debugPrint('${AppLocalizations.of(context)!.msgAddFriendFailed}: $e');
          displayMsg = NetworkErrorHelper.messageForUser(e, prefix: AppLocalizations.of(context)!.msgOperationFailed, l10n: AppLocalizations.of(context));
        }
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(displayMsg)));
      }
    }
  }

  Future<void> _openChat(BuildContext context, MessagesRepository repo) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUserId.isEmpty) return;
    final navigator = Navigator.of(context);
    try {
      final conv = await repo.createOrGetDirectConversation(
        currentUserId: currentUserId,
        friendId: userId,
        friendName: displayName,
      );
      if (!context.mounted) return;
      // 先关掉当前资料页，再清掉下层可能是的群聊，只保留根路由后压入私聊，避免点发消息后仍停在群聊
      navigator.pop();
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => ChatDetailPage(
            conversation: conv,
            initialMessages: const [],
          ),
        ),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(NetworkErrorHelper.messageForUser(e, prefix: AppLocalizations.of(context)!.msgOpenChatFailedPrefix, l10n: AppLocalizations.of(context)))),
        );
      }
    }
  }
}
