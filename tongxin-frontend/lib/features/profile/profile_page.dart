import 'dart:convert';
import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:permission_handler/permission_handler.dart';

import '../../api/users_api.dart';
import '../../core/design/design_tokens.dart';
import '../auth/auth_service.dart';
import '../auth/login_page.dart';
import '../../core/api_client.dart';
import '../../core/firebase_bootstrap.dart';
import '../../core/locale_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/components.dart';
import '../../core/role_badge.dart';
import '../../core/notification_settings_guide.dart';
import '../../core/notification_service.dart';
import '../../core/i18n_extra.dart';
import '../../core/user_restrictions.dart';
import '../../core/web_user_page.dart';
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
  if (userId.isEmpty) return null;
  if (!ApiClient.instance.isAvailable)
    return const UserRoleInfo(role: 'user', level: 0, teacherStatus: 'pending');
  final p = await UsersApi.instance.getProfile(userId);
  if (p == null)
    return const UserRoleInfo(role: 'user', level: 0, teacherStatus: 'pending');
  return UserRoleInfo(
    role: p['role'] as String? ?? 'user',
    level: (p['level'] as int?) ?? 0,
    teacherStatus: p['teacher_status'] as String? ?? 'pending',
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
    if (!ApiClient.instance.isAvailable) return;
    try {
      final p = await UsersApi.instance.getProfile(userId);
      if (!mounted) return;
      setState(() {
        _avatarUrl = p?['avatar_url'] as String?;
        _signature = p?['signature'] as String?;
        _shortId = p?['short_id'] as String?;
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
    if (_requestingShortId || !ApiClient.instance.isAvailable) return;
    _requestingShortId = true;
    try {
      await SupabaseUserSync().ensureShortId(userId);
      final p = await UsersApi.instance.getProfile(userId);
      if (!mounted) return;
      setState(() => _shortId = p?['short_id'] as String?);
      await _saveCachedProfile(userId: userId, shortId: _shortId);
    } finally {
      _requestingShortId = false;
    }
  }

  Future<void> _uploadAvatar(String userId) async {
    if (_uploadingAvatar || userId.isEmpty) return;
    if (!ApiClient.instance.isAvailable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!
                .profileAvatarUploadFailedNoSupabase)),
      );
      return;
    }
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _uploadingAvatar = true);
    try {
      final bytes = await picked.readAsBytes();
      final base64 = base64Encode(bytes);
      final contentType = _guessImageContentType(picked.name);
      final url = await UsersApi.instance.uploadAvatar(
        contentBase64: base64,
        contentType: contentType,
        fileName: picked.name,
      );
      if (url == null || url.isEmpty) throw StateError('上传失败');
      if (FirebaseBootstrap.isReady) {
        await FirebaseAuth.instance.currentUser?.updatePhotoURL(url);
        await FirebaseAuth.instance.currentUser?.reload();
      }
      if (!mounted) return;
      setState(() => _avatarUrl = url);
      await _saveCachedProfile(userId: userId, avatarUrl: url);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!.profileAvatarUpdated)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
            content: Text(
                '${AppLocalizations.of(context)!.profileAvatarUploadFailed}: $error')),
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
          content: AppInput(
            controller: controller,
            maxLines: 2,
            hintText: AppLocalizations.of(context)!.profileSignatureHint,
          ),
          actions: [
            AppButton(
              variant: AppButtonVariant.secondary,
              label: AppLocalizations.of(context)!.commonCancel,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            AppButton(
              label: AppLocalizations.of(context)!.commonSave,
              onPressed: () => Navigator.of(context).pop(true),
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
      if (!ApiClient.instance.isAvailable) {
        if (mounted) {
          setState(() => _savingSignature = false);
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
                content: Text(AppLocalizations.of(context)!
                    .profileSignatureUpdateFailed)),
          );
        }
        return;
      }
      final ok = await UsersApi.instance.updateMe({'signature': value});
      if (!ok) throw StateError('更新失败');
      if (!mounted) return;
      setState(() => _signature = value);
      await _saveCachedProfile(userId: userId, signature: value);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
            content:
                Text(AppLocalizations.of(context)!.profileSignatureUpdated)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
            content: Text(
                '${AppLocalizations.of(context)!.profileSignatureUpdateFailed}: $error')),
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
      padding: AppSpacing.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.primarySubtle(0.12),
        borderRadius: AppRadius.mdAll,
      ),
      child: Text(
        text,
        style: AppTypography.caption.copyWith(color: AppColors.primary),
      ),
    );
  }

  Widget _buildMenuItemCard({
    required Widget leading,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    Color? titleColor,
  }) {
    return AppCard(
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      onTap: onTap,
      child: ListTile(
        leading: leading,
        title: Text(
          title,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: titleColor ?? AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
        trailing:
            const Icon(Icons.chevron_right, color: AppColors.textTertiary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
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
          return Scaffold(
            appBar: AppBar(
              title: Text(AppLocalizations.of(context)!.profileMy),
            ),
            body: const LoginPage(
              popOnSuccess: false,
              showBackButton: false,
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(AppLocalizations.of(context)!.profileMy),
          ),
          body: ListView(
            padding: AppSpacing.allMd,
            children: [
              if (!FirebaseBootstrap.isReady)
                AppCard(
                  padding: AppSpacing.allMd,
                  child: Text(
                    AppLocalizations.of(context)!.profileFirebaseNotConfigured,
                    style: AppTypography.bodySecondary
                        .copyWith(color: AppColors.primary),
                  ),
                ),
              _buildLoggedInContent(user),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLoggedInContent(User user) {
    final verified = user.emailVerified;
    final name = user.displayName?.trim();
    if (_loadedUserId != user.uid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadAvatar(user.uid);
      });
    }
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
            return AppCard(
              padding: AppSpacing.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm + AppSpacing.xs),
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Icon(
                    isBanned ? Icons.block : Icons.info_outline,
                    color: isBanned ? AppColors.negative : AppColors.warning,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      msg,
                      style: AppTypography.body.copyWith(
                        color:
                            isBanned ? AppColors.negative : AppColors.warning,
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
          AppCard(
            padding: AppSpacing.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + AppSpacing.xs),
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                const Icon(
                  Icons.notifications_off_outlined,
                  color: AppColors.warning,
                  size: 22,
                ),
                const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.profileNotificationNotEnabled,
                    style: AppTypography.body.copyWith(
                      color: AppColors.warning,
                      fontSize: 13,
                    ),
                  ),
                ),
                AppButton(
                  variant: AppButtonVariant.text,
                  label: AppLocalizations.of(context)!.commonGoToEnable,
                  onPressed: () async {
                    await NotificationSettingsGuide.showIfPermissionDenied(
                        context);
                    _checkNotificationPermission();
                  },
                ),
              ],
            ),
          ),
        AppCard(
          padding: AppSpacing.allMd,
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Padding(
            padding: EdgeInsets.zero,
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
                                          fadeInDuration: Duration.zero,
                                          fadeOutDuration: Duration.zero,
                                          placeholder: (_, __) =>
                                              const SizedBox(
                                            width: 72,
                                            height: 72,
                                            child: Center(
                                              child: Icon(
                                                Icons.person,
                                                color: AppColors.surface,
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
                                                color: AppColors.surface,
                                                size: 32,
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                    : const CircleAvatar(
                                        radius: 36,
                                        backgroundColor: AppColors.primary,
                                        child: Icon(
                                          Icons.person,
                                          color: AppColors.surface,
                                          size: 32,
                                        ),
                                      ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius:
                                          BorderRadius.circular(AppRadius.md),
                                      border: Border.all(
                                        color: AppColors.primary,
                                        width: 0.6,
                                      ),
                                    ),
                                    padding:
                                        const EdgeInsets.all(AppSpacing.xs),
                                    child: const Icon(
                                      Icons.camera_alt_outlined,
                                      size: 14,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name == null || name.isEmpty
                                              ? AppLocalizations.of(context)!
                                                  .profileStudentAccount
                                              : name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                        const SizedBox(height: AppSpacing.xs),
                                        Text(
                                          _shortId == null ||
                                                  _shortId!.trim().isEmpty
                                              ? AppLocalizations.of(context)!
                                                  .profileAccountIdDash
                                              : AppLocalizations.of(context)!
                                                  .profileAccountIdValue(
                                                      _shortId!.trim()),
                                          style: AppTypography.caption.copyWith(
                                            color: AppColors.textTertiary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      RoleBadge(
                                        roleLabel: _formatIdentityTag(
                                          context,
                                          verified: verified,
                                          role: role.role,
                                          teacherStatus: role.teacherStatus,
                                        ),
                                      ),
                                      const SizedBox(height: AppSpacing.sm),
                                      _buildLevelTag('Lv ${role.level}'),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(
                                  height: AppSpacing.md - AppSpacing.xs),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _signature?.trim().isNotEmpty == true
                                          ? _signature!.trim()
                                          : AppLocalizations.of(context)!
                                              .profileLazySignature,
                                      style:
                                          AppTypography.bodySecondary.copyWith(
                                        color: AppColors.textTertiary,
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
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const SizedBox(height: AppSpacing.md),
                    AppCard(
                      padding: EdgeInsets.zero,
                      child: ListTile(
                        leading: Icon(
                          role.teacherStatus.toString().trim().toLowerCase() ==
                                  'approved'
                              ? Icons.school
                              : Icons.star_border,
                        ),
                        title: Text(
                          role.teacherStatus.toString().trim().toLowerCase() ==
                                  'approved'
                              ? AppLocalizations.of(context)!
                                  .profileTeacherCenter
                              : AppLocalizations.of(context)!
                                  .profileBecomeTeacher,
                        ),
                        subtitle: Text(
                          role.teacherStatus.toString().trim().toLowerCase() ==
                                  'approved'
                              ? AppLocalizations.of(context)!
                                  .profileManageStrategyAndRecords
                              : AppLocalizations.of(context)!
                                  .profileSubmitProfileAndPublish,
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
                    if (role.role.toString().trim().toLowerCase() ==
                        'customer_service') ...[
                      const SizedBox(height: AppSpacing.md),
                      AppCard(
                        padding: EdgeInsets.zero,
                        child: ListTile(
                          leading: const Icon(Icons.support_agent_outlined),
                          title: Text(
                              AppLocalizations.of(context)!.profileCsWorkbench),
                          subtitle: Text(AppLocalizations.of(context)!
                              .profileCsWorkbenchSubtitle),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const CustomerServiceWorkbenchPage(),
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
        const SizedBox(height: AppSpacing.md),
        _buildMenuItemCard(
          leading: const Icon(Icons.people_outline),
          title: AppLocalizations.of(context)!.profileTraderFriends,
          subtitle: AppLocalizations.of(context)!.profileTraderFriendsSubtitle,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FeaturedTeacherPage()),
            );
          },
        ),
        _buildMenuItemCard(
          leading: const Icon(Icons.help_outline),
          title: AppLocalizations.of(context)!.profileHelp,
          subtitle:
              AppLocalizations.of(context)!.profileNotificationGuideSubtitle,
          onTap: () => _showHelpSheet(context),
        ),
        _buildMenuItemCard(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: AppLocalizations.of(context)!.profilePrivacyPolicy,
          subtitle: AppLocalizations.of(context)!.profilePrivacyPolicySubtitle,
          onTap: () => _showPrivacyPolicy(context),
        ),
        _buildMenuItemCard(
          leading: const Icon(Icons.web),
          title: I18nExtra.webViewUserPageTitle(context),
          subtitle: I18nExtra.webViewUserPageSubtitle(context),
          onTap: () => openWebUserPage(context),
        ),
        _buildMenuItemCard(
          leading: const Icon(Icons.flag_outlined),
          title: AppLocalizations.of(context)!.profileReport,
          subtitle: AppLocalizations.of(context)!.profileReportSubtitle,
          onTap: () => _showReport(context),
        ),
        _buildMenuItemCard(
          leading: const Icon(Icons.logout_outlined),
          title: AppLocalizations.of(context)!.profileLogout,
          onTap: () async {
            final authService = AuthService();
            final currentUser = FirebaseBootstrap.isReady
                ? FirebaseAuth.instance.currentUser
                : null;
            if (currentUser == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(AppLocalizations.of(context)!
                        .profileCurrentNotLoggedIn)),
              );
              return;
            }
            final confirmed = await showModalBottomSheet<bool>(
              context: context,
              backgroundColor: AppColors.surface,
              shape: const RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
              ),
              builder: (context) {
                return SafeArea(
                  child: Padding(
                    padding: AppSpacing.allMd,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          currentUser.email ??
                              AppLocalizations.of(context)!.profileLoggedIn,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        AppButton(
                          label: AppLocalizations.of(context)!.commonCancel,
                          variant: AppButtonVariant.secondary,
                          onPressed: () => Navigator.of(context).pop(false),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        AppButton(
                          label: AppLocalizations.of(context)!.profileLogout,
                          onPressed: () => Navigator.of(context).pop(true),
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
        StreamBuilder<User?>(
          stream: FirebaseBootstrap.isReady
              ? FirebaseAuth.instance.authStateChanges()
              : Stream.value(null),
          builder: (context, snapshot) {
            final user = snapshot.data;
            if (user == null) return const SizedBox.shrink();
            return _buildMenuItemCard(
              leading: const Icon(Icons.person_off_outlined,
                  color: AppColors.negative),
              title: AppLocalizations.of(context)!.profileAccountDeletion,
              titleColor: AppColors.negative,
              onTap: () => _showAccountDeletion(context, user),
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        _buildMenuItemCard(
          leading: const Icon(Icons.language_outlined),
          title: AppLocalizations.of(context)!.settingsLanguage,
          subtitle: LocaleProvider.instance.locale?.languageCode == 'en'
              ? AppLocalizations.of(context)!.settingsLanguageEnglish
              : AppLocalizations.of(context)!.settingsLanguageChinese,
          onTap: () async {
            final l10n = AppLocalizations.of(context)!;
            final choice = await showModalBottomSheet<String>(
              context: context,
              backgroundColor: AppColors.surface,
              shape: const RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
              ),
              builder: (context) {
                return SafeArea(
                  child: Padding(
                    padding: AppSpacing.allMd,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.settingsLanguage,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        AppCard(
                          padding: EdgeInsets.zero,
                          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                          onTap: () => Navigator.of(context).pop('zh'),
                          child: ListTile(
                            leading: const Icon(Icons.translate,
                                color: AppColors.primary),
                            title: Text(l10n.settingsLanguageChinese),
                            trailing: const Icon(Icons.chevron_right,
                                color: AppColors.textTertiary),
                          ),
                        ),
                        AppCard(
                          padding: EdgeInsets.zero,
                          onTap: () => Navigator.of(context).pop('en'),
                          child: ListTile(
                            leading: const Icon(Icons.language,
                                color: AppColors.primary),
                            title: Text(l10n.settingsLanguageEnglish),
                            trailing: const Icon(Icons.chevron_right,
                                color: AppColors.textTertiary),
                          ),
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
      ],
    );
  }

  void _showHelpSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: AppSpacing.allMd,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.profileHelpTitle,
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  padding: EdgeInsets.zero,
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    if (!kIsWeb && Platform.isAndroid) {
                      final status = await Permission.notification.status;
                      if (!status.isGranted) {
                        if (!context.mounted) return;
                        await NotificationSettingsGuide.showIfPermissionDenied(
                            context);
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
                            style: AppTypography.body.copyWith(height: 1.4),
                          ),
                        ),
                        actions: [
                          AppButton(
                            variant: AppButtonVariant.secondary,
                            label: l10n.commonKnowIt,
                            onPressed: () => Navigator.of(dctx).pop(),
                          ),
                          AppButton(
                            label: l10n.profileReRequestPermission,
                            onPressed: () async {
                              Navigator.of(dctx).pop();
                              await NotificationSettingsGuide
                                  .requestAllPermissionsNow(context);
                            },
                          ),
                          AppButton(
                            variant: AppButtonVariant.secondary,
                            label: l10n.commonGoToSettings,
                            onPressed: () {
                              Navigator.of(dctx).pop();
                              openAppSettings();
                            },
                          ),
                        ],
                      ),
                    );
                  },
                  child: ListTile(
                    leading: const Icon(Icons.notifications_active_outlined,
                        color: AppColors.primary),
                    title: Text(l10n.profilePushNotificationGuide),
                    subtitle: Text(l10n.profileNotificationGuideSubtitle),
                    trailing: const Icon(Icons.chevron_right,
                        color: AppColors.textTertiary),
                  ),
                ),
                if (!kIsWeb && Platform.isAndroid)
                  AppCard(
                    padding: EdgeInsets.zero,
                    margin: const EdgeInsets.only(top: AppSpacing.sm),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      final canUse =
                          await NotificationService.canUseFullScreenIntent();
                      if (canUse && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                                  Text(l10n.profileFullScreenIntentEnabled)),
                        );
                        return;
                      }
                      if (!context.mounted) return;
                      await NotificationSettingsGuide
                          .showFullScreenIntentPermissionGuide(context);
                      if (context.mounted) {
                        await NotificationSettingsGuide
                            .showCallFullScreenPermissionGuide(context);
                      }
                    },
                    child: ListTile(
                      leading: const Icon(Icons.call_outlined,
                          color: AppColors.primary),
                      title: Text(l10n.profileIncomingCallFullScreen),
                      subtitle:
                          Text(l10n.profileIncomingCallFullScreenSubtitle),
                      trailing: const Icon(Icons.chevron_right,
                          color: AppColors.textTertiary),
                    ),
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
            style: AppTypography.body.copyWith(height: 1.5),
          ),
        ),
        actions: [
          AppButton(
            variant: AppButtonVariant.secondary,
            label: l10n.commonKnowIt,
            onPressed: () => Navigator.of(ctx).pop(),
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
          AppButton(
            variant: AppButtonVariant.secondary,
            label: l10n.commonCancel,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          AppButton(
            variant: AppButtonVariant.primary,
            label: l10n.profileAccountDeletion,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await user.delete();
      if (!context.mounted) return;
      await AuthService().signOut();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.profileDeletionSuccess)),
      );
    } on FirebaseAuthException catch (e) {
      if (!context.mounted) return;
      if (e.code == 'requires-recent-login') {
        await AuthService().signOut();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.networkAuthExpired)),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${l10n.profileAccountDeletion}: ${e.message ?? e.code}',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.profileAccountDeletion}: $e')),
      );
    }
  }
}
