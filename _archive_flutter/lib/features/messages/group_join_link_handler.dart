import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../core/network_error_helper.dart';
import '../../core/notification_service.dart';
import '../../core/user_restrictions.dart';
import 'messages_repository.dart';

/// 群邀请链接格式: teacherhub://group/join?id=conversationId
/// 在 main 中调用 [initGroupJoinLinkHandler] 监听冷启动与热启动的链接。
void initGroupJoinLinkHandler() {
  final appLinks = AppLinks();
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final uri = await appLinks.getInitialLink();
    if (uri != null) {
      handleGroupJoinUri(uri);
    }
    appLinks.uriLinkStream.listen(handleGroupJoinUri);
  });
}

/// 处理群邀请链接（可从聊天内点击链接时直接调用）。
Future<void> handleGroupJoinUri(Uri uri) async {
  if (uri.scheme != 'teacherhub' ||
      uri.host != 'group' ||
      !uri.path.startsWith('/join')) {
    return;
  }
  final conversationId = uri.queryParameters['id']?.trim();
  if (conversationId == null || conversationId.isEmpty) return;

  final userId = FirebaseAuth.instance.currentUser?.uid;
  if (userId == null || userId.isEmpty) {
    final ctx = NotificationService.navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      _showSnackBar(AppLocalizations.of(ctx)!.groupJoinLoginFirst);
    }
    return;
  }
  final ctx = NotificationService.navigatorKey.currentContext;
  if (ctx == null || !ctx.mounted) return;

  final restrictions = await UserRestrictions.getMyRestrictionRow();
  if (!UserRestrictions.canJoinGroup(restrictions)) {
    UserRestrictions.clearCache();
    _showSnackBar(UserRestrictions.getAccountStatusMessage(restrictions, ctx));
    return;
  }
  final context = ctx;

  final l10n = AppLocalizations.of(context)!;
  final join = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.groupJoinTitle),
      content: Text(l10n.groupJoinConfirm),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.commonConfirm),
        ),
      ],
    ),
  );
  if (join != true) return;

  try {
    final displayName = FirebaseAuth.instance.currentUser?.displayName?.trim() ??
        FirebaseAuth.instance.currentUser?.email?.split('@').first ??
        l10n.groupNewMember;
    final repo = MessagesRepository();
    await repo.addGroupMembers(
      conversationId: conversationId,
      userIds: [userId],
      userIdToDisplayName: {userId: displayName},
    );
    if (context.mounted) {
      _showSnackBar(l10n.groupJoinSuccess);
    }
  } catch (e) {
    if (context.mounted) {
      final msg = NetworkErrorHelper.messageForUser(e, prefix: AppLocalizations.of(context)!.groupJoinFailed, l10n: AppLocalizations.of(context));
      _showSnackBar(msg);
    }
  }
}

void _showSnackBar(String msg) {
  final context = NotificationService.navigatorKey.currentContext;
  if (context != null && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));
  }
}
