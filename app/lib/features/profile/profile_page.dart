import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:permission_handler/permission_handler.dart';

import '../auth/auth_service.dart';
import '../auth/login_page.dart';
import '../../core/firebase_bootstrap.dart';
import '../../core/role_badge.dart';
import '../../core/supabase_bootstrap.dart';
import '../../core/notification_settings_guide.dart';
import '../../core/user_restrictions.dart';
import '../teachers/teacher_center_page.dart';
import '../messages/supabase_user_sync.dart';

class UserRoleInfo {
  const UserRoleInfo({
    required this.role,
    required this.level,
    required this.teacherStatus,
  });

  final String role;
  final int level;
  final String teacherStatus;
}

Future<UserRoleInfo?> _fetchRoleInfo(String userId) async {
  if (userId.isEmpty) {
    return null;
  }
  if (!SupabaseBootstrap.isReady) {
    return const UserRoleInfo(role: 'user', level: 0, teacherStatus: 'pending');
  }
  final up = await SupabaseBootstrap.client
      .from('user_profiles')
      .select('role, level, teacher_status')
      .eq('user_id', userId)
      .maybeSingle();
  String teacherStatus = up?['teacher_status'] as String? ?? 'pending';
  final tp = await SupabaseBootstrap.client
      .from('teacher_profiles')
      .select('status')
      .eq('user_id', userId)
      .maybeSingle();
  if (tp != null && tp['status'] != null) {
    teacherStatus = tp['status'] as String;
  }
  return UserRoleInfo(
    role: up?['role'] as String? ?? 'user',
    level: (up?['level'] as int?) ?? 0,
    teacherStatus: teacherStatus,
  );
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with WidgetsBindingObserver {
  final _picker = ImagePicker();
  String? _avatarUrl;
  String? _signature;
  String? _shortId;
  String? _loadedUserId;
  bool _uploadingAvatar = false;
  bool _savingSignature = false;
  bool _requestingShortId = false;
  /// 通知权限未开启时为 true（仅 Android 检测）
  bool _notificationDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb && Platform.isAndroid) {
      _checkNotificationPermission();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !kIsWeb && Platform.isAndroid) {
      _checkNotificationPermission();
    }
  }

  Future<void> _checkNotificationPermission() async {
    final status = await Permission.notification.status;
    if (mounted) {
      setState(() => _notificationDenied = !status.isGranted);
    }
  }

  Future<void> _loadAvatar(String userId) async {
    if (userId.isEmpty) {
      return;
    }
    final alreadyLoaded = userId == _loadedUserId;
    if (alreadyLoaded &&
        _avatarUrl != null &&
        _shortId != null &&
        _signature != null) {
      return;
    }
    _loadedUserId = userId;
    await _loadCachedProfile(userId);
    if (!SupabaseBootstrap.isReady) {
      return;
    }
    try {
      final row = await SupabaseBootstrap.client
          .from('user_profiles')
          .select('avatar_url, signature, short_id')
          .eq('user_id', userId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _avatarUrl = row?['avatar_url'] as String?;
        _signature = row?['signature'] as String?;
        _shortId = row?['short_id'] as String?;
      });
      await _saveCachedProfile(
        userId: userId,
        avatarUrl: _avatarUrl,
        signature: _signature,
        shortId: _shortId,
      );
      if (_shortId == null || _shortId!.trim().isEmpty) {
        await _requestShortId(userId);
      }
    } catch (_) {
      await _loadCachedProfile(userId);
    }
  }

  Future<void> _loadCachedProfile(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final avatar = prefs.getString('profile.avatar.$userId');
    final signature = prefs.getString('profile.signature.$userId');
    final shortId = prefs.getString('profile.shortId.$userId');
    final firebaseAvatar = FirebaseBootstrap.isReady
        ? FirebaseAuth.instance.currentUser?.photoURL?.trim()
        : null;
    if (!mounted) return;
    setState(() {
      if (avatar != null && avatar.trim().isNotEmpty) {
        _avatarUrl = avatar;
      } else if (firebaseAvatar != null && firebaseAvatar.isNotEmpty) {
        _avatarUrl = firebaseAvatar;
      }
      if (signature != null && signature.trim().isNotEmpty) {
        _signature = signature;
      }
      if (shortId != null && shortId.trim().isNotEmpty) {
        _shortId = shortId;
      }
    });
    if ((avatar == null || avatar.trim().isEmpty) &&
        firebaseAvatar != null &&
        firebaseAvatar.isNotEmpty) {
      await _saveCachedProfile(userId: userId, avatarUrl: firebaseAvatar);
    }
  }

  Future<void> _saveCachedProfile({
    required String userId,
    String? avatarUrl,
    String? signature,
    String? shortId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (avatarUrl != null && avatarUrl.trim().isNotEmpty) {
      await prefs.setString('profile.avatar.$userId', avatarUrl);
    }
    if (signature != null && signature.trim().isNotEmpty) {
      await prefs.setString('profile.signature.$userId', signature);
    }
    if (shortId != null && shortId.trim().isNotEmpty) {
      await prefs.setString('profile.shortId.$userId', shortId);
    }
  }

  Future<void> _requestShortId(String userId) async {
    if (_requestingShortId || !SupabaseBootstrap.isReady) {
      return;
    }
    _requestingShortId = true;
    try {
      await SupabaseUserSync().ensureShortId(userId);
      final row = await SupabaseBootstrap.client
          .from('user_profiles')
          .select('short_id')
          .eq('user_id', userId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _shortId = row?['short_id'] as String?;
      });
      await _saveCachedProfile(userId: userId, shortId: _shortId);
    } finally {
      _requestingShortId = false;
    }
  }

  Future<void> _uploadAvatar(String userId) async {
    if (_uploadingAvatar || userId.isEmpty) {
      return;
    }
    if (!SupabaseBootstrap.isReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('头像上传失败：未配置 Supabase')),
      );
      return;
    }
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) {
      return;
    }
    setState(() => _uploadingAvatar = true);
    try {
      final bytes = await picked.readAsBytes();
      final name = picked.name.replaceAll(' ', '_');
      final path =
          'users/$userId/${DateTime.now().millisecondsSinceEpoch}_$name';
      await SupabaseBootstrap.client.storage.from('avatars').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: _guessImageContentType(name),
              upsert: true,
            ),
          );
      final url =
          SupabaseBootstrap.client.storage.from('avatars').getPublicUrl(path);
      await SupabaseBootstrap.client.from('user_profiles').upsert({
        'user_id': userId,
        'avatar_url': url,
        'updated_at': DateTime.now().toIso8601String(),
      });
      if (FirebaseBootstrap.isReady) {
        await FirebaseAuth.instance.currentUser?.updatePhotoURL(url);
        await FirebaseAuth.instance.currentUser?.reload();
      }
      if (!mounted) return;
      setState(() => _avatarUrl = url);
      await _saveCachedProfile(userId: userId, avatarUrl: url);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('头像已更新')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('头像上传失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _editSignature(String userId) async {
    if (_savingSignature || userId.isEmpty) {
      return;
    }
    final controller = TextEditingController(text: _signature ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('编辑个性签名'),
          content: TextField(
            controller: controller,
            maxLines: 2,
            decoration: const InputDecoration(hintText: '写点什么吧…'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      controller.dispose();
      return;
    }
    setState(() => _savingSignature = true);
    try {
      final value = controller.text.trim();
      await SupabaseBootstrap.client.from('user_profiles').upsert({
        'user_id': userId,
        'signature': value,
        'updated_at': DateTime.now().toIso8601String(),
      });
      if (!mounted) return;
      setState(() => _signature = value);
      await _saveCachedProfile(userId: userId, signature: value);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('签名已更新')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('签名更新失败：$error')),
      );
    } finally {
      controller.dispose();
      if (mounted) setState(() => _savingSignature = false);
    }
  }

  String _guessImageContentType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  String _formatIdentityTag({
    required bool verified,
    required String role,
    required String teacherStatus,
  }) {
    final r = role.toString().trim().toLowerCase();
    final status = teacherStatus.toString().trim().toLowerCase();
    if (r == 'admin') return '管理员';
    if (r == 'vip') return '会员';
    if (r == 'teacher' || status == 'approved') return '交易员';
    return '普通用户';
  }

  Widget _buildLevelTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0x1AD4AF37),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!FirebaseBootstrap.isReady)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF111215),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD4AF37), width: 0.4),
              ),
              child: const Text(
                '尚未配置 Firebase，登录与消息功能暂不可用。',
              ),
            ),
          StreamBuilder<User?>(
            stream: FirebaseBootstrap.isReady
                ? FirebaseAuth.instance.authStateChanges()
                : Stream.value(null),
            builder: (context, snapshot) {
              final user = snapshot.data;
              if (user == null) {
                _loadedUserId = null;
                _avatarUrl = null;
                _shortId = null;
                _signature = null;
                return Column(
                  children: [
                    ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: const Text('学员账号'),
                      subtitle: const Text('未登录'),
                      trailing: TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const LoginPage()),
                          );
                        },
                        child: const Text('登录/注册'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.star_border),
                        title: const Text('成为交易员'),
                        subtitle: const Text('登录后可提交资料'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const LoginPage()),
                          );
                        },
                      ),
                    ),
                  ],
                );
              }
              final verified = user.emailVerified;
              final name = user.displayName?.trim();
              _loadAvatar(user.uid);
              final roleFuture = _fetchRoleInfo(user.uid);
              return Column(
                children: [
                  FutureBuilder<Map<String, dynamic>?>(
                    future: UserRestrictions.getMyRestrictionRow(),
                    builder: (context, restrictionSnap) {
                      final row = restrictionSnap.data;
                      if (row == null || !UserRestrictions.hasAnyRestriction(row)) {
                        return const SizedBox.shrink();
                      }
                      final msg = UserRestrictions.getAccountStatusMessage(row);
                      final isBanned = UserRestrictions.isBannedOrFrozen(row);
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isBanned ? Colors.red.shade900.withOpacity(0.3) : Colors.orange.shade900.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isBanned ? Colors.red.shade700 : Colors.orange.shade700,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isBanned ? Icons.block : Icons.info_outline,
                              color: isBanned ? Colors.red.shade200 : Colors.orange.shade200,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                msg,
                                style: TextStyle(
                                  color: isBanned ? Colors.red.shade100 : Colors.orange.shade100,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  if (!kIsWeb && Platform.isAndroid && _notificationDenied)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade900.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange.shade700,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.notifications_off_outlined,
                            color: Colors.orange.shade200,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '通知未开启，可能收不到新消息提醒',
                              style: TextStyle(
                                color: Colors.orange.shade100,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              await NotificationSettingsGuide.showIfPermissionDenied(context);
                              _checkNotificationPermission();
                            },
                            child: const Text('去开启'),
                          ),
                        ],
                      ),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: FutureBuilder<UserRoleInfo?>(
                        future: roleFuture,
                        builder: (context, roleSnapshot) {
                          final role = roleSnapshot.data ??
                              const UserRoleInfo(
                                role: 'user',
                                level: 0,
                                teacherStatus: 'pending',
                              );
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: _uploadingAvatar
                                          ? null
                                          : () => _uploadAvatar(user.uid),
                                      borderRadius: BorderRadius.circular(40),
                                      child: Stack(
                                        children: [
                                          _avatarUrl?.trim().isNotEmpty == true
                                              ? ClipOval(
                                                  child: CachedNetworkImage(
                                                    imageUrl: _avatarUrl!.trim(),
                                                    width: 72,
                                                    height: 72,
                                                    fit: BoxFit.cover,
                                                    placeholder: (_, __) =>
                                                        const SizedBox(
                                                      width: 72,
                                                      height: 72,
                                                      child: Center(
                                                        child: Icon(
                                                          Icons.person,
                                                          color: Color(0xFF111215),
                                                          size: 32,
                                                        ),
                                                      ),
                                                    ),
                                                    errorWidget: (_, __, ___) =>
                                                        const SizedBox(
                                                      width: 72,
                                                      height: 72,
                                                      child: Center(
                                                        child: Icon(
                                                          Icons.person,
                                                          color: Color(0xFF111215),
                                                          size: 32,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                )
                                              : CircleAvatar(
                                                  radius: 36,
                                                  backgroundColor:
                                                      const Color(0xFFD4AF37),
                                                  child: const Icon(
                                                    Icons.person,
                                                    color: Color(0xFF111215),
                                                    size: 32,
                                                  ),
                                                ),
                                          Positioned(
                                            right: 0,
                                            bottom: 0,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF111215),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color:
                                                      const Color(0xFFD4AF37),
                                                  width: 0.6,
                                                ),
                                              ),
                                              padding: const EdgeInsets.all(3),
                                              child: const Icon(
                                                Icons.camera_alt_outlined,
                                                size: 14,
                                                color: Color(0xFFD4AF37),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    name == null ||
                                                            name.isEmpty
                                                        ? '学员账号'
                                                        : name,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleMedium,
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    _shortId == null ||
                                                            _shortId!
                                                                .trim()
                                                                .isEmpty
                                                        ? '账号ID --'
                                                        : '账号ID ${_shortId!.trim()}',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Color(0xFF6C6F77),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                RoleBadge(
                                                  roleLabel: _formatIdentityTag(
                                                    verified: verified,
                                                    role: role.role,
                                                    teacherStatus: role.teacherStatus,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                _buildLevelTag('Lv ${role.level}'),
                                              ],
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _signature?.trim().isNotEmpty ==
                                                        true
                                                    ? _signature!.trim()
                                                    : '这个人很懒，什么都没写',
                                                style: const TextStyle(
                                                  color: Color(0xFF6C6F77),
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: _savingSignature
                                                  ? null
                                                  : () => _editSignature(
                                                        user.uid,
                                                      ),
                                              icon: const Icon(
                                                Icons.edit_outlined,
                                                size: 18,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const SizedBox(height: 16),
                              Card(
                                child: ListTile(
                                  leading: Icon(
                                    role.teacherStatus.toString().trim().toLowerCase() == 'approved'
                                        ? Icons.school
                                        : Icons.star_border,
                                  ),
                                  title: Text(
                                    role.teacherStatus.toString().trim().toLowerCase() == 'approved'
                                        ? '交易员中心'
                                        : '成为交易员',
                                  ),
                                  subtitle: Text(
                                    role.teacherStatus.toString().trim().toLowerCase() == 'approved'
                                        ? '管理策略与交易记录'
                                        : '提交资料，发布策略与交易记录',
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const TeacherCenterPage(),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.bookmark_border),
              title: const Text('我的关注'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
          ),
          if (_showAdminEntry)
            Column(
              children: [
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.admin_panel_settings_outlined),
                    title: const Text('后台管理（PC）'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).pushNamed('/admin');
                    },
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('收不到推送？'),
              subtitle: const Text('查看通知与自启动设置说明'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                if (!kIsWeb && Platform.isAndroid) {
                  final status = await Permission.notification.status;
                  if (!status.isGranted) {
                    await NotificationSettingsGuide.showIfPermissionDenied(context);
                    _checkNotificationPermission();
                    return;
                  }
                }
                if (!mounted) return;
                showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('确保收到新消息'),
                    content: const SingleChildScrollView(
                      child: Text(
                        '1. 请允许本应用的「通知」和「后台运行」权限。\n\n'
                        '2. 华为/荣耀用户：若后台收不到消息，请到\n'
                        '   设置 → 应用 → teacher_hub\n'
                        '   开启「自启动」，并在「手动管理」中允许后台活动。\n\n'
                        '3. 华为/荣耀用户：若来电时没有弹出接听界面（只在通知栏看到），请到\n'
                        '   设置 → 应用 → teacher_hub → 权限\n'
                        '   开启「后台弹窗」或「悬浮窗」，以便在桌面/其他 App 时也能弹出通话窗口。\n\n'
                        '4. 若需要桌面图标显示未读数字，请到\n'
                        '   设置 → 应用 → teacher_hub → 通知管理\n'
                        '   开启「桌面角标」。',
                        style: TextStyle(height: 1.4),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('知道了'),
                      ),
                      FilledButton(
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          await NotificationSettingsGuide.requestAllPermissionsNow(context);
                        },
                        child: const Text('重新请求权限'),
                      ),
                      FilledButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          openAppSettings();
                        },
                        child: const Text('去设置'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (!kIsWeb && Platform.isAndroid)
            Card(
              child: ListTile(
                leading: const Icon(Icons.call_outlined),
                title: const Text('来电全屏接听'),
                subtitle: const Text('后台或锁屏时直接弹出接听界面'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await NotificationSettingsGuide.showCallFullScreenPermissionGuide(context);
                },
              ),
            ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('设置'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final authService = AuthService();
                final currentUser = FirebaseBootstrap.isReady
                    ? FirebaseAuth.instance.currentUser
                    : null;
                if (currentUser == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('当前未登录')),
                  );
                  return;
                }
                final confirmed = await showModalBottomSheet<bool>(
                  context: context,
                  backgroundColor: const Color(0xFF111215),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  builder: (context) {
                    return SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              currentUser.email ?? '已登录',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: () =>
                                  Navigator.of(context).pop(false),
                              child: const Text('取消'),
                            ),
                            const SizedBox(height: 8),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.of(context).pop(true),
                              child: const Text('退出登录'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
                if (confirmed == true) {
                  await authService.signOut();
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

bool get _showAdminEntry {
  if (kIsWeb) {
    return true;
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
      return true;
    default:
      return false;
  }
}
