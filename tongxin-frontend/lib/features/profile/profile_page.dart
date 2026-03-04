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
import '../../core/locale_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../core/role_badge.dart';
import '../../core/supabase_bootstrap.dart';
import '../../core/notification_settings_guide.dart';
import '../../core/notification_service.dart';
import '../../core/user_restrictions.dart';
import '../home/featured_teacher_page.dart';
import '../teachers/teacher_center_page.dart';
import '../messages/customer_service_workbench_page.dart';
import '../messages/supabase_user_sync.dart';
import 'report_page.dart';

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
        SnackBar(content: Text(AppLocalizations.of(context)!.profileAvatarUploadFailedNoSupabase)),
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
      // 仅保留安全字符，避免 storage 元数据写入时 22P02 类型错误
      final rawName = picked.name.replaceAll(' ', '_');
      final cleaned = rawName.replaceAll(RegExp(r'[^\w\-.]'), '');
      final safeName = cleaned.isEmpty ? 'image.jpg' : cleaned;
      final path =
          'users/$userId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      await SupabaseBootstrap.client.storage.from('avatars').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: _guessImageContentType(picked.name),
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
        SnackBar(content: Text(AppLocalizations.of(context)!.profileAvatarUpdated)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('${AppLocalizations.of(context)!.profileAvatarUploadFailed}: $error')),
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
          title: Text(AppLocalizations.of(context)!.profileEditSignature),
          content: TextField(
            controller: controller,
            maxLines: 2,
            decoration: InputDecoration(hintText: AppLocalizations.of(context)!.profileSignatureHint),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(AppLocalizations.of(context)!.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(AppLocalizations.of(context)!.commonSave),
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
        SnackBar(content: Text(AppLocalizations.of(context)!.profileSignatureUpdated)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('${AppLocalizations.of(context)!.profileSignatureUpdateFailed}: $error')),
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

  String _formatIdentityTag(
    BuildContext context, {
    required bool verified,
    required String role,
    required String teacherStatus,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final r = role.toString().trim().toLowerCase();
    final status = teacherStatus.toString().trim().toLowerCase();
    if (r == 'admin') return l10n.profileAdmin;
    if (r == 'vip') return l10n.profileVip;
    if (r == 'teacher' || status == 'approved') return l10n.profileTeacher;
    return l10n.profileNormalUser;
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
        title: Text(AppLocalizations.of(context)!.profileMy),
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
              child: Text(
                AppLocalizations.of(context)!.profileFirebaseNotConfigured,
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
                      title: Text(AppLocalizations.of(context)!.profileStudentAccount),
                      subtitle: Text(AppLocalizations.of(context)!.profileNotLoggedIn),
                      trailing: TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const LoginPage()),
                          );
                        },
                        child: Text(AppLocalizations.of(context)!.authLoginOrRegister),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.star_border),
                        title: Text(AppLocalizations.of(context)!.profileBecomeTeacher),
                        subtitle: Text(AppLocalizations.of(context)!.profileLoginToSubmit),
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
                      final msg = UserRestrictions.getAccountStatusMessage(row, context);
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
                              AppLocalizations.of(context)!.profileNotificationNotEnabled,
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
                            child: Text(AppLocalizations.of(context)!.commonGoToEnable),
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
                                                        ? AppLocalizations.of(context)!.profileStudentAccount
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
                                                        ? AppLocalizations.of(context)!.profileAccountIdDash
                                                        : AppLocalizations.of(context)!.profileAccountIdValue(_shortId!.trim()),
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
                                                    context,
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
                                                    : AppLocalizations.of(context)!.profileLazySignature,
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
                                        ? AppLocalizations.of(context)!.profileTeacherCenter
                                        : AppLocalizations.of(context)!.profileBecomeTeacher,
                                  ),
                                  subtitle: Text(
                                    role.teacherStatus.toString().trim().toLowerCase() == 'approved'
                                        ? AppLocalizations.of(context)!.profileManageStrategyAndRecords
                                        : AppLocalizations.of(context)!.profileSubmitProfileAndPublish,
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
                              if (role.role.toString().trim().toLowerCase() == 'customer_service') ...[
                                const SizedBox(height: 16),
                                Card(
                                  child: ListTile(
                                    leading: const Icon(Icons.support_agent_outlined),
                                    title: Text(AppLocalizations.of(context)!.profileCsWorkbench),
                                    subtitle: Text(AppLocalizations.of(context)!.profileCsWorkbenchSubtitle),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => const CustomerServiceWorkbenchPage(),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
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
              leading: const Icon(Icons.people_outline),
              title: Text(AppLocalizations.of(context)!.profileTraderFriends),
              subtitle: Text(AppLocalizations.of(context)!.profileTraderFriendsSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FeaturedTeacherPage()),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.help_outline),
              title: Text(AppLocalizations.of(context)!.profileHelp),
              subtitle: Text(AppLocalizations.of(context)!.profileNotificationGuideSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showHelpSheet(context),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(AppLocalizations.of(context)!.profilePrivacyPolicy),
              subtitle: Text(AppLocalizations.of(context)!.profilePrivacyPolicySubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showPrivacyPolicy(context),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(AppLocalizations.of(context)!.profileReport),
              subtitle: Text(AppLocalizations.of(context)!.profileReportSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showReport(context),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout_outlined),
              title: Text(AppLocalizations.of(context)!.profileLogout),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final authService = AuthService();
                final currentUser = FirebaseBootstrap.isReady
                    ? FirebaseAuth.instance.currentUser
                    : null;
                if (currentUser == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(AppLocalizations.of(context)!.profileCurrentNotLoggedIn)),
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
                              currentUser.email ?? AppLocalizations.of(context)!.profileLoggedIn,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: () =>
                                  Navigator.of(context).pop(false),
                              child: Text(AppLocalizations.of(context)!.commonCancel),
                            ),
                            const SizedBox(height: 8),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.of(context).pop(true),
                              child: Text(AppLocalizations.of(context)!.profileLogout),
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
          StreamBuilder<User?>(
            stream: FirebaseBootstrap.isReady
                ? FirebaseAuth.instance.authStateChanges()
                : Stream.value(null),
            builder: (context, snapshot) {
              final user = snapshot.data;
              if (user == null) return const SizedBox.shrink();
              return Card(
                child: ListTile(
                  leading: Icon(Icons.person_off_outlined, color: Colors.red.shade300),
                  title: Text(
                    AppLocalizations.of(context)!.profileAccountDeletion,
                    style: TextStyle(color: Colors.red.shade300),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showAccountDeletion(context, user),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.language_outlined),
              title: Text(AppLocalizations.of(context)!.settingsLanguage),
              subtitle: Text(
                LocaleProvider.instance.locale?.languageCode == 'en'
                    ? AppLocalizations.of(context)!.settingsLanguageEnglish
                    : AppLocalizations.of(context)!.settingsLanguageChinese,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final l10n = AppLocalizations.of(context)!;
                final choice = await showModalBottomSheet<String>(
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
                              l10n.settingsLanguage,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            ListTile(
                              title: Text(l10n.settingsLanguageChinese),
                              onTap: () => Navigator.of(context).pop('zh'),
                            ),
                            ListTile(
                              title: Text(l10n.settingsLanguageEnglish),
                              onTap: () => Navigator.of(context).pop('en'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
                if (choice != null && context.mounted) {
                  await LocaleProvider.instance.setLocale(Locale(choice));
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showHelpSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111215),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.profileHelpTitle,
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: Text(l10n.profilePushNotificationGuide),
                  subtitle: Text(l10n.profileNotificationGuideSubtitle),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    if (!kIsWeb && Platform.isAndroid) {
                      final status = await Permission.notification.status;
                      if (!status.isGranted) {
                        await NotificationSettingsGuide.showIfPermissionDenied(context);
                        _checkNotificationPermission();
                        return;
                      }
                    }
                    if (!context.mounted) return;
                    showDialog<void>(
                      context: context,
                      builder: (dctx) => AlertDialog(
                        title: Text(l10n.profileEnsureReceiveMessages),
                        content: SingleChildScrollView(
                          child: Text(
                            l10n.profileNotificationPermissionGuide,
                            style: const TextStyle(height: 1.4),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dctx).pop(),
                            child: Text(l10n.commonKnowIt),
                          ),
                          FilledButton(
                            onPressed: () async {
                              Navigator.of(dctx).pop();
                              await NotificationSettingsGuide.requestAllPermissionsNow(context);
                            },
                            child: Text(l10n.profileReRequestPermission),
                          ),
                          FilledButton(
                            onPressed: () {
                              Navigator.of(dctx).pop();
                              openAppSettings();
                            },
                            child: Text(l10n.commonGoToSettings),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                if (!kIsWeb && Platform.isAndroid)
                  ListTile(
                    leading: const Icon(Icons.call_outlined),
                    title: Text(l10n.profileIncomingCallFullScreen),
                    subtitle: Text(l10n.profileIncomingCallFullScreenSubtitle),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      final canUse = await NotificationService.canUseFullScreenIntent();
                      if (canUse && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.profileFullScreenIntentEnabled)),
                        );
                        return;
                      }
                      await NotificationSettingsGuide.showFullScreenIntentPermissionGuide(context);
                      if (context.mounted) {
                        await NotificationSettingsGuide.showCallFullScreenPermissionGuide(context);
                      }
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPrivacyPolicy(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.profilePrivacyPolicy),
        content: SingleChildScrollView(
          child: Text(
            l10n.profilePrivacyPolicyContent,
            style: const TextStyle(height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.commonKnowIt),
          ),
        ],
      ),
    );
  }

  void _showReport(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ReportPage()),
    );
  }

  Future<void> _showAccountDeletion(BuildContext context, User user) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.profileAccountDeletion),
        content: Text(l10n.profileAccountDeletionConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.profileAccountDeletion),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await user.delete();
      if (!mounted) return;
      await AuthService().signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.profileDeletionSuccess)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.profileAccountDeletion}: $e')),
      );
    }
  }
}

