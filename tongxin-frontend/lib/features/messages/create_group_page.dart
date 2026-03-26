import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../core/network_error_helper.dart';
import '../../core/pc_dashboard_theme.dart';
import '../../core/user_restrictions.dart';
import 'chat_media_cache.dart';
import 'friend_models.dart';
import 'friends_repository.dart';
import 'messages_repository.dart';

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key});

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final _nameController = TextEditingController();
  final _friendsRepository = FriendsRepository();
  final _messagesRepository = MessagesRepository();
  final Set<String> _selectedIds = {};
  bool _creating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final userName = FirebaseAuth.instance.currentUser?.displayName?.trim() ?? 
        FirebaseAuth.instance.currentUser?.email?.split('@').first ?? '我';
    if (userId.isEmpty) {
      _showToast(AppLocalizations.of(context)!.teachersPleaseLoginFirst);
      return;
    }
    final restrictions = await UserRestrictions.getMyRestrictionRow();
    if (!UserRestrictions.canCreateGroup(restrictions)) {
      UserRestrictions.clearCache();
      _showToast(UserRestrictions.getAccountStatusMessage(restrictions, context));
      return;
    }
    if (_selectedIds.isEmpty) {
      _showToast(AppLocalizations.of(context)!.groupSelectAtLeastOne);
      return;
    }
    setState(() => _creating = true);
    try {
      final name = _nameController.text.trim();
      final conversation = await _messagesRepository.createGroupConversation(
        currentUserId: userId,
        currentUserName: userName,
        title: name,
        memberUserIds: _selectedIds.toList(),
        defaultTitleWhenEmpty: name.isEmpty
            ? AppLocalizations.of(context)!.msgGroupChatN(_selectedIds.length + 1)
            : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop(conversation);
    } catch (e) {
      if (!mounted) return;
      _showToast(NetworkErrorHelper.messageForUser(e, prefix: AppLocalizations.of(context)!.groupCreateFailed, l10n: AppLocalizations.of(context)));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _showToast(String msg) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));
  }

  static Widget _avatarPlaceholder(String name) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: PcDashboardTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(22),
        ),
        alignment: Alignment.center,
        child: Text(
          name.isEmpty ? '?' : name[0],
          style: PcDashboardTheme.titleMedium.copyWith(color: PcDashboardTheme.accent),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PcDashboardTheme.surface,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.groupCreateGroup, style: PcDashboardTheme.titleMedium),
        backgroundColor: PcDashboardTheme.surfaceVariant,
        foregroundColor: PcDashboardTheme.text,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(PcDashboardTheme.contentPadding),
            child: TextField(
              controller: _nameController,
              style: PcDashboardTheme.bodyLarge,
              decoration: PcDashboardTheme.inputDecoration(
                hintText: AppLocalizations.of(context)!.groupCreateGroupHint,
              ).copyWith(labelText: AppLocalizations.of(context)!.groupGroupNameLabel, labelStyle: PcDashboardTheme.bodyMedium),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PcDashboardTheme.contentPadding),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(AppLocalizations.of(context)!.groupSelectFriends, style: PcDashboardTheme.label),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<List<FriendProfile>>(
              stream: _friendsRepository.watchFriends(
                userId: FirebaseAuth.instance.currentUser?.uid ?? '',
              ),
              builder: (context, snapshot) {
                final friends = snapshot.data ?? [];
                final list = friends.where((f) => f.userId != FirebaseAuth.instance.currentUser?.uid).toList();
                if (list.isEmpty) {
                  return Center(
                    child: Text(
                      AppLocalizations.of(context)!.groupNoFriendsHint,
                      style: PcDashboardTheme.bodyMedium,
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: PcDashboardTheme.contentPadding),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final friend = list[index];
                    final name = friend.displayName.trim().isEmpty
                        ? friend.email.split('@').first
                        : friend.displayName;
                    final checked = _selectedIds.contains(friend.userId);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        decoration: PcDashboardTheme.cardDecoration(),
                        child: CheckboxListTile(
                          value: checked,
                          activeColor: PcDashboardTheme.accent,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selectedIds.add(friend.userId);
                              } else {
                                _selectedIds.remove(friend.userId);
                              }
                            });
                          },
                          title: Text(name, style: PcDashboardTheme.titleSmall),
                          subtitle: friend.shortId?.trim().isNotEmpty == true
                              ? Text(AppLocalizations.of(context)!.profileAccountIdValue(friend.shortId!.trim()), style: PcDashboardTheme.bodySmall)
                              : null,
                          secondary: friend.avatarUrl != null && friend.avatarUrl!.trim().isNotEmpty
                              ? ClipOval(
                                  child: CachedNetworkImage(
                                    imageUrl: friend.avatarUrl!.trim(),
                                    cacheManager: ChatMediaCache.instance,
                                    width: 44,
                                    height: 44,
                                    fit: BoxFit.cover,
                                    fadeInDuration: Duration.zero,
                                    fadeOutDuration: Duration.zero,
                                    placeholder: (_, __) => _avatarPlaceholder(name),
                                    errorWidget: (_, __, ___) => _avatarPlaceholder(name),
                                  ),
                                )
                              : _avatarPlaceholder(name),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(PcDashboardTheme.contentPadding),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _creating || _selectedIds.isEmpty
                      ? null
                      : _createGroup,
                  style: FilledButton.styleFrom(
                    backgroundColor: PcDashboardTheme.accent,
                    foregroundColor: PcDashboardTheme.surface,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(PcDashboardTheme.radiusMd),
                    ),
                  ),
                  child: _creating
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _selectedIds.isEmpty
                              ? AppLocalizations.of(context)!.groupCreateGroupButton
                              : AppLocalizations.of(context)!.groupCreateGroupButtonN(_selectedIds.length),
                          style: PcDashboardTheme.titleSmall.copyWith(color: PcDashboardTheme.surface),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
