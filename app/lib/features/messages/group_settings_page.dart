import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:cached_network_image/cached_network_image.dart';

import '../../core/app_download.dart';
import '../../core/network_error_helper.dart';
import '../../core/supabase_bootstrap.dart';
import 'chat_media_cache.dart';
import 'friend_models.dart';
import 'friends_repository.dart';
import 'message_models.dart';
import 'messages_local_store.dart';
import 'messages_repository.dart';
import 'user_profile_page.dart';

class GroupSettingsPage extends StatefulWidget {
  const GroupSettingsPage({
    super.key,
    required this.conversation,
  });

  final Conversation conversation;

  @override
  State<GroupSettingsPage> createState() => _GroupSettingsPageState();
}

class _GroupSettingsPageState extends State<GroupSettingsPage> {
  final _messagesRepository = MessagesRepository();
  final _friendsRepository = FriendsRepository();
  final _localStore = MessagesLocalStore();
  final _picker = ImagePicker();
  GroupInfo? _info;
  bool _loading = true;
  String? _error;
  bool _muted = false;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (userId.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final muted = await _localStore.isConversationMuted(widget.conversation.id);
      final info = await _messagesRepository.fetchGroupInfo(
        conversationId: widget.conversation.id,
        currentUserId: userId,
      );
      if (!mounted) return;
      if (info != null) {
        final membersWithProfile = await _fillMemberProfiles(info.members);
        setState(() {
          _muted = muted;
          _info = GroupInfo(
            conversationId: info.conversationId,
            title: info.title,
            announcement: info.announcement,
            avatarUrl: info.avatarUrl,
            createdBy: info.createdBy,
            memberCount: info.memberCount,
            myRole: info.myRole,
            members: membersWithProfile,
          );
        });
      } else {
        setState(() => _error = '无法加载群信息');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = NetworkErrorHelper.messageForUser(e, prefix: '加载失败');
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<GroupMember>> _fillMemberProfiles(List<GroupMember> members) async {
    final list = <GroupMember>[];
    for (final m in members) {
      FriendProfile? p;
      try {
        p = await _friendsRepository.findById(m.userId);
      } catch (_) {}
      list.add(GroupMember(
        userId: m.userId,
        role: m.role,
        displayName: p?.displayName,
        avatarUrl: p?.avatarUrl,
        shortId: p?.shortId,
      ));
    }
    return list;
  }

  static const String _groupJoinScheme = 'teacherhub';
  static const String _groupJoinHost = 'group';
  static const String _groupJoinPath = 'join';

  String _groupJoinLink() {
    return '$_groupJoinScheme://$_groupJoinHost/$_groupJoinPath?id=${widget.conversation.id}';
  }

  void _showToast(String msg) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showGroupInviteOptions(BuildContext context, String groupName) {
    final link = _groupJoinLink();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1C21),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '邀请好友进群',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '好友打开链接或扫描二维码即可申请加入「$groupName」',
                style: TextStyle(
                  color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.8),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('复制邀请链接'),
                onTap: () {
                  Clipboard.setData(ClipboardData(
                    text: '点击此链接加入群：$link',
                  ));
                  Navigator.of(ctx).pop();
                  _showToast('链接已复制，好友点击链接即可加入群');
                },
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_2),
                title: const Text('二维码邀请'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showToast('扫码加入群');
                  _showQrDialog(context, link, groupName);
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('未安装 App？前往下载'),
                subtitle: const Text('好友未安装时可引导其下载'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  openAppDownloadPage(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQrDialog(BuildContext context, String link, String groupName) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1C21),
        title: Text('扫码加入「$groupName」'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: link,
                version: QrVersions.auto,
                size: 200,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '好友使用本 App 扫一扫即可进群',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  String _memberDisplayName(GroupMember m) {
    if (m.displayName != null && m.displayName!.trim().isNotEmpty) {
      return m.displayName!.trim();
    }
    if (m.shortId != null && m.shortId!.trim().isNotEmpty) {
      return 'ID ${m.shortId!.trim()}';
    }
    return m.userId;
  }

  Widget _buildOwnerAdminSection(GroupInfo info) {
    final owner = info.members.where((m) => m.isOwner).toList();
    final admins = info.members.where((m) => m.role == 'admin').toList();
    if (owner.isEmpty) return const SizedBox.shrink();
    final ownerName = owner.map(_memberDisplayName).firstOrNull ?? '群主';
    final adminNames = admins.map(_memberDisplayName).toList();
    final subtitle = adminNames.isEmpty
        ? ownerName
        : '$ownerName · ${adminNames.join('、')}';
    return ListTile(
      leading: const Icon(Icons.person_pin_outlined),
      title: const Text('群主'),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  Future<void> _inviteMembers() async {
    if (_info == null) return;
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (userId.isEmpty) return;
    final friends = await _friendsRepository.watchFriends(userId: userId).first;
    final inGroup = _info!.members.map((e) => e.userId).toSet();
    final candidates = friends.where((f) => !inGroup.contains(f.userId)).toList();
    if (candidates.isEmpty) {
      _showToast('没有可邀请的好友');
      return;
    }
    if (!mounted) return;
    final selected = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => InviteGroupMembersPage(
          conversationId: widget.conversation.id,
          candidates: candidates,
        ),
      ),
    );
    if (selected != null && selected.isNotEmpty && mounted) {
      try {
        final userIdToDisplayName = {
          for (final f in candidates)
            if (selected.contains(f.userId)) f.userId: f.displayName,
        };
        await _messagesRepository.addGroupMembers(
          conversationId: widget.conversation.id,
          userIds: selected,
          userIdToDisplayName: userIdToDisplayName,
        );
        _showToast('已邀请 ${selected.length} 人');
        _load();
      } catch (e) {
        _showToast(NetworkErrorHelper.messageForUser(e, prefix: '邀请失败'));
      }
    }
  }

  Future<void> _editGroupName() async {
    if (_info == null || !_info!.canManage) return;
    final c = TextEditingController(text: _info!.title);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改群名称'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(
            hintText: '群名称',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(c.text.trim()), child: const Text('保存')),
        ],
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    try {
      await _messagesRepository.updateGroupProfile(
        conversationId: widget.conversation.id,
        title: result,
      );
      _showToast('群名称已更新');
      _load();
    } catch (e) {
      _showToast(NetworkErrorHelper.messageForUser(e, prefix: '保存失败'));
    }
  }

  Future<void> _toggleMuted(bool muted) async {
    await _localStore.setConversationMuted(widget.conversation.id, muted);
    if (mounted) setState(() => _muted = muted);
    _showToast(muted ? '已开启消息免打扰' : '已关闭消息免打扰');
  }

  static String _guessImageContentType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _editGroupAvatar() async {
    if (_info == null || !_info!.canManage || _uploadingAvatar) return;
    if (!SupabaseBootstrap.isReady) {
      _showToast('未配置 Supabase，无法上传');
      return;
    }
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    setState(() => _uploadingAvatar = true);
    try {
      final bytes = await picked.readAsBytes();
      final name = picked.name.replaceAll(' ', '_');
      final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
      final url = await _messagesRepository.uploadGroupAvatar(
        conversationId: widget.conversation.id,
        userId: userId,
        bytes: bytes,
        contentType: _guessImageContentType(name),
      );
      await _messagesRepository.updateGroupProfile(
        conversationId: widget.conversation.id,
        avatarUrl: url,
      );
      if (!mounted) return;
      _showToast('群头像已更新');
      _load();
    } catch (e) {
      if (mounted) {
        _showToast(NetworkErrorHelper.messageForUser(e, prefix: '上传失败'));
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _editAnnouncement() async {
    if (_info == null || !_info!.canManage) return;
    final c = TextEditingController(text: _info!.announcement ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('群公告'),
        content: TextField(
          controller: c,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: '输入群公告',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(c.text.trim()), child: const Text('保存')),
        ],
      ),
    );
    if (result == null || !mounted) return;
    try {
      await _messagesRepository.updateGroupProfile(
        conversationId: widget.conversation.id,
        announcement: result.isEmpty ? null : result,
      );
      _showToast('群公告已更新');
      _load();
    } catch (e) {
      _showToast(NetworkErrorHelper.messageForUser(e, prefix: '保存失败'));
    }
  }

  Future<void> _leaveGroup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出群聊'),
        content: const Text('确定退出该群聊？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('退出')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    final userId = user?.uid ?? '';
    if (userId.isEmpty) return;
    final leaveUserName = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : user?.email?.split('@').first ?? '某用户';
    try {
      await _messagesRepository.leaveGroup(
        conversationId: widget.conversation.id,
        userId: userId,
        leaveUserName: leaveUserName,
      );
      if (!mounted) return;
      _showToast('已退出群聊');
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      _showToast(NetworkErrorHelper.messageForUser(e, prefix: '退出失败'));
    }
  }

  Future<void> _dismissGroup() async {
    if (_info == null || !_info!.isOwner) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解散群聊'),
        content: const Text('确定解散该群聊？所有成员将退出，聊天记录将无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('解散')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _messagesRepository.dismissGroup(conversationId: widget.conversation.id);
      if (!mounted) return;
      _showToast('群聊已解散');
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      _showToast(NetworkErrorHelper.messageForUser(e, prefix: '解散失败'));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('群设置')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('群设置')),
        body: Center(child: Text(_error!)),
      );
    }
    final info = _info!;
    final showAvatar =
        info.avatarUrl != null && info.avatarUrl!.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('群设置')),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: info.canManage && !_uploadingAvatar ? _editGroupAvatar : null,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: const Color(0xFF1A1C21),
                        child: showAvatar
                            ? ClipOval(
                                child: CachedNetworkImage(
                                  imageUrl: info.avatarUrl!.trim(),
                                  cacheManager: ChatMediaCache.instance,
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Center(
                                    child: Text(
                                      info.title.isNotEmpty ? info.title[0] : '群',
                                      style: const TextStyle(
                                          fontSize: 32,
                                          color: Color(0xFFD4AF37),
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  errorWidget: (_, __, ___) => Center(
                                    child: Text(
                                      info.title.isNotEmpty ? info.title[0] : '群',
                                      style: const TextStyle(
                                          fontSize: 32,
                                          color: Color(0xFFD4AF37),
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              )
                            : Text(
                                info.title.isNotEmpty ? info.title[0] : '群',
                                style: const TextStyle(
                                    fontSize: 32,
                                    color: Color(0xFFD4AF37),
                                    fontWeight: FontWeight.bold),
                              ),
                      ),
                      if (info.canManage && !_uploadingAvatar)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.black54,
                            child: _uploadingAvatar
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
                if (info.canManage && !_uploadingAvatar)
                  const SizedBox(height: 6),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('群名称'),
            subtitle: info.title.isNotEmpty ? Text(info.title) : null,
            trailing: info.canManage
                ? const Icon(Icons.chevron_right)
                : null,
            onTap: info.canManage ? _editGroupName : null,
          ),
          _buildOwnerAdminSection(info),
          if (info.announcement != null && info.announcement!.trim().isNotEmpty)
            ListTile(
              leading: const Icon(Icons.campaign_outlined),
              title: const Text('群公告'),
              subtitle: Text(
                info.announcement!.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: info.canManage ? const Icon(Icons.chevron_right) : null,
              onTap: info.canManage ? _editAnnouncement : null,
            )
          else if (info.canManage)
            ListTile(
              leading: const Icon(Icons.campaign_outlined),
              title: const Text('群公告'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _editAnnouncement,
            ),
          const Divider(),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_off_outlined),
            title: const Text('消息免打扰'),
            value: _muted,
            onChanged: _toggleMuted,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.person_add_outlined),
            title: const Text('邀请新成员'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _inviteMembers,
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('群邀请链接'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showGroupInviteOptions(context, info.title),
          ),
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: Text('群成员 (${info.memberCount})'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GroupMemberListPage(
                    conversationId: widget.conversation.id,
                    groupInfo: info,
                    onUpdated: _load,
                  ),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.exit_to_app),
            title: const Text('退出群聊'),
            onTap: _leaveGroup,
          ),
          if (info.isOwner) ...[
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('解散群聊', style: TextStyle(color: Colors.red)),
              onTap: _dismissGroup,
            ),
          ],
        ],
      ),
    );
  }
}

/// 邀请入群：从候选好友中多选
class InviteGroupMembersPage extends StatefulWidget {
  const InviteGroupMembersPage({
    super.key,
    required this.conversationId,
    required this.candidates,
  });

  final String conversationId;
  final List<FriendProfile> candidates;

  @override
  State<InviteGroupMembersPage> createState() => _InviteGroupMembersPageState();
}

class _InviteGroupMembersPageState extends State<InviteGroupMembersPage> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('邀请新成员'),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(_selected.toList()),
            child: Text('确定(${_selected.length})'),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: widget.candidates.length,
        itemBuilder: (context, index) {
          final f = widget.candidates[index];
          final name = f.displayName.trim().isEmpty ? f.email.split('@').first : f.displayName;
          final checked = _selected.contains(f.userId);
          return CheckboxListTile(
            value: checked,
            onChanged: (v) {
              setState(() {
                if (v == true) {
                  _selected.add(f.userId);
                } else {
                  _selected.remove(f.userId);
                }
              });
            },
            title: Text(name),
            subtitle: f.shortId?.trim().isNotEmpty == true ? Text('账号ID ${f.shortId!.trim()}') : null,
          );
        },
      ),
    );
  }
}

/// 群成员列表：展示角色，群主可转让群主/设管理员，群主/管理员可移除成员
class GroupMemberListPage extends StatelessWidget {
  const GroupMemberListPage({
    super.key,
    required this.conversationId,
    required this.groupInfo,
    required this.onUpdated,
  });

  final String conversationId;
  final GroupInfo groupInfo;
  final VoidCallback onUpdated;

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      appBar: AppBar(title: Text('群成员 (${groupInfo.memberCount})')),
      body: ListView.builder(
        itemCount: groupInfo.members.length,
        itemBuilder: (context, index) {
          final m = groupInfo.members[index];
          final name = (m.displayName?.trim() ?? '').isEmpty
              ? (m.shortId != null && m.shortId!.trim().isNotEmpty ? 'ID ${m.shortId!.trim()}' : m.userId)
              : (m.displayName ?? m.userId);
          final roleLabel = m.isOwner ? '群主' : (m.role == 'admin' ? '管理员' : null);
          final canShowActions = groupInfo.canManage &&
              !m.isOwner &&
              m.userId != currentUserId;
          final isOwner = groupInfo.isOwner;
          return ListTile(
            onTap: () => openUserProfile(
              context,
              userId: m.userId,
              displayName: name,
              avatarUrl: m.avatarUrl,
            ),
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF1A1C21),
              child: m.avatarUrl != null && m.avatarUrl!.trim().isNotEmpty
                  ? ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: m.avatarUrl!.trim(),
                        cacheManager: ChatMediaCache.instance,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Center(
                          child: Text(name.isEmpty ? '?' : name[0],
                              style: const TextStyle(color: Color(0xFFD4AF37))),
                        ),
                        errorWidget: (_, __, ___) => Center(
                          child: Text(name.isEmpty ? '?' : name[0],
                              style: const TextStyle(color: Color(0xFFD4AF37))),
                        ),
                      ),
                    )
                  : Text(name.isEmpty ? '?' : name[0],
                      style: const TextStyle(color: Color(0xFFD4AF37))),
            ),
            title: Row(
              children: [
                Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
                if (roleLabel != null && roleLabel.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4AF37).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFD4AF37), width: 1),
                    ),
                    child: Text(
                      roleLabel!,
                      style: const TextStyle(
                        color: Color(0xFFD4AF37),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: canShowActions
                ? Text(
                    '点击右侧 ⋮ 可移出、转让群主、设管理员',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                    ),
                  )
                : null,
            trailing: canShowActions
                ? PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white70),
                    onSelected: (value) {
                      switch (value) {
                        case 'remove':
                          _removeMember(context, m.userId, name);
                          break;
                        case 'transfer':
                          _transferOwner(context, m.userId, name);
                          break;
                        case 'set_admin':
                          _setMemberRole(context, m.userId, 'admin', name);
                          break;
                        case 'unset_admin':
                          _setMemberRole(context, m.userId, 'member', name);
                          break;
                      }
                    },
                    itemBuilder: (ctx) {
                      final items = <PopupMenuEntry<String>>[
                        const PopupMenuItem(value: 'remove', child: Text('移除（踢出群聊）')),
                      ];
                      if (isOwner) {
                        items.add(const PopupMenuItem(value: 'transfer', child: Text('转让群主')));
                        if (m.role == 'member') {
                          items.add(const PopupMenuItem(value: 'set_admin', child: Text('设为管理员')));
                        } else if (m.role == 'admin') {
                          items.add(const PopupMenuItem(value: 'unset_admin', child: Text('取消管理员')));
                        }
                      }
                      return items;
                    },
                  )
                : null,
          );
        },
      ),
    );
  }

  Future<void> _transferOwner(BuildContext context, String targetUserId, String targetName) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('转让群主'),
        content: Text('确定将群主转让给 $targetName？转让后您将变为管理员。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('转让')),
        ],
      ),
    );
    if (ok != true) return;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUserId.isEmpty) return;
    try {
      final repo = MessagesRepository();
      await repo.transferGroupOwnership(
        conversationId: conversationId,
        currentOwnerId: currentUserId,
        targetUserId: targetUserId,
      );
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('已转让群主')));
        onUpdated();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(NetworkErrorHelper.messageForUser(e, prefix: '操作失败'))),
        );
      }
    }
  }

  Future<void> _setMemberRole(BuildContext context, String userId, String role, String displayName) async {
    final label = role == 'admin' ? '设为管理员' : '取消管理员';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: Text(role == 'admin'
            ? '确定将 $displayName 设为管理员？'
            : '确定取消 $displayName 的管理员身份？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(label)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final repo = MessagesRepository();
      await repo.updateMemberRole(conversationId: conversationId, userId: userId, role: role);
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$label 成功')));
        onUpdated();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(NetworkErrorHelper.messageForUser(e, prefix: '操作失败'))),
        );
      }
    }
  }

  Future<void> _removeMember(BuildContext context, String userId, String leaveUserName) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除成员'),
        content: const Text('确定将该成员移出群聊？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('移除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final repo = MessagesRepository();
      await repo.removeGroupMember(
        conversationId: conversationId,
        userId: userId,
        leaveUserName: leaveUserName,
      );
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('已移出群聊')));
        onUpdated();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(NetworkErrorHelper.messageForUser(e, prefix: '操作失败'))),
        );
      }
    }
  }
}
