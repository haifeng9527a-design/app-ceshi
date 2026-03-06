import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/design/design_tokens.dart';
import '../../core/firebase_bootstrap.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/components.dart';
import '../../core/user_restrictions.dart';
import 'auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    /// 登录成功后是否 pop 关闭页面；为 false 时（如作为「我的」Tab 主内容）不 pop，由父级根据 auth 状态刷新
    this.popOnSuccess = true,
    /// 是否显示返回按钮；为 false 时（如作为「我的」Tab 主内容）不显示
    this.showBackButton = true,
  });

  final bool popOnSuccess;
  final bool showBackButton;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const String _rememberEmailKey = 'auth.remembered_email';
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();
  final _authService = AuthService();
  bool _loading = false;
  bool _isRegister = false;

  String _registerEmailTip(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode.toLowerCase();
    if (lang.startsWith('zh')) {
      return '点击注册后会自动发送验证邮件，请前往邮箱确认后再登录';
    }
    return 'After registration, a verification email will be sent automatically. Please confirm it before signing in.';
  }

  @override
  void initState() {
    super.initState();
    _restoreRememberedCredentials();
  }

  Future<void> _restoreRememberedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedEmail = prefs.getString(_rememberEmailKey)?.trim() ?? '';
      if (!mounted) return;
      if (savedEmail.isEmpty) return;
      setState(() {
        _emailController.text = savedEmail;
      });
    } catch (_) {
      // 忽略本地读取异常，不影响登录主流程
    }
  }

  Future<void> _saveRememberedCredentials({required String email}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_rememberEmailKey, email);
    } catch (_) {
      // 忽略本地写入异常，不影响登录主流程
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  bool get _firebaseReady => FirebaseBootstrap.isReady;

  /// 第三方登录后校验后台限制，受限则登出并提示
  Future<void> _runSignIn(Future<void> Function() signInAction) async {
    if (!_firebaseReady) {
      _showMessage(AppLocalizations.of(context)!.authPleaseConfigureFirebase);
      return;
    }
    setState(() => _loading = true);
    try {
      await signInAction();
      final restrictions = await UserRestrictions.getMyRestrictionRow();
      if (UserRestrictions.isRestrictedLogin(restrictions)) {
        await _authService.signOut();
        _showMessage(UserRestrictions.getAccountStatusMessage(restrictions, context));
        return;
      }
      if (mounted && widget.popOnSuccess) Navigator.of(context).pop();
    } catch (error) {
      _showMessage(_friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleEmailLogin() async {
    if (!_firebaseReady) {
      _showMessage(AppLocalizations.of(context)!.authPleaseConfigureFirebase);
      return;
    }
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      _showMessage(AppLocalizations.of(context)!.authPleaseFillEmailAndPassword);
      return;
    }
    setState(() => _loading = true);
    try {
      await _authService.signInWithEmail(email: email, password: password);
      final verified = await _authService.isEmailVerified();
      if (!verified) {
        await _authService.sendEmailVerificationIfNeeded();
        await _authService.signOut();
        _showMessage(AppLocalizations.of(context)!.authVerificationSent);
        return;
      }
      // 校验后台限制：限制登录 / 封禁 / 冻结
      final restrictions = await UserRestrictions.getMyRestrictionRow();
      if (UserRestrictions.isRestrictedLogin(restrictions)) {
        await _authService.signOut();
        _showMessage(UserRestrictions.getAccountStatusMessage(restrictions, context));
        return;
      }
      await _saveRememberedCredentials(email: email);
      if (mounted && widget.popOnSuccess) Navigator.of(context).pop();
    } catch (error) {
      _showMessage(_friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleEmailRegister() async {
    if (!_firebaseReady) {
      _showMessage(AppLocalizations.of(context)!.authPleaseConfigureFirebase);
      return;
    }
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final name = _nameController.text.trim();
    if (name.isEmpty || email.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      _showMessage(AppLocalizations.of(context)!.authFillNameEmailPassword);
      return;
    }
    if (password != confirmPassword) {
      _showMessage(AppLocalizations.of(context)!.authPasswordMismatch);
      return;
    }
    if (password.length < 6) {
      _showMessage(AppLocalizations.of(context)!.authPasswordMinLength);
      return;
    }
    setState(() => _loading = true);
    try {
      await _authService.registerWithEmail(
        email: email,
        password: password,
        displayName: name,
      );
      await _authService.signOut();
      _showMessage(AppLocalizations.of(context)!.authVerificationSent);
    } catch (error) {
      _showMessage(_friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _friendlyErrorMessage(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'network-request-failed':
          return '无法连接服务器（可能是网络、防火墙或本机限制），请检查后重试或改用邮箱登录';
        case 'email-already-in-use':
          return '该邮箱已注册，请直接登录或更换邮箱';
        case 'invalid-email':
          return '邮箱格式不正确';
        case 'weak-password':
          return '密码强度太弱，请设置至少 6 位';
        case 'user-not-found':
          return '账号不存在，请先注册';
        case 'wrong-password':
          return '密码错误，请重试';
        case 'too-many-requests':
          return '操作过于频繁，请稍后再试';
        case 'user-disabled':
          return '账号已被禁用，请联系管理员';
        case 'operation-not-allowed':
          return '该登录方式未启用，请联系管理员';
        case 'invalid-credential':
          return '账号或凭据无效，请重新登录';
        default:
          return '操作失败：${error.message ?? error.code}';
      }
    }
    final message = error.toString();
    if (message.contains('GoogleSignInException') ||
        message.contains('google_sign_in')) {
      return 'Google 登录失败（可能为网络、防火墙或权限），请重试或改用邮箱登录';
    }
    if (message.contains('keychain')) {
      return '登录需要钥匙串权限，请用 Xcode 配置开发签名后重试，或改用邮箱登录';
    }
    if (message.contains('connection') ||
        message.contains('Connection') ||
        message.contains('network') ||
        message.contains('Network') ||
        message.contains('socket')) {
      return '连接失败（可能为网络或防火墙），请检查后重试或改用邮箱登录';
    }
    return '操作失败：$message';
  }

  @override
  Widget build(BuildContext context) {
    final canUseApple = defaultTargetPlatform == TargetPlatform.iOS;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: AppSpacing.symmetric(horizontal: AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.md),
                    if (widget.showBackButton)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _IconBtn(
                          icon: Icons.arrow_back_ios_new,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      )
                    else
                      const SizedBox(height: AppSpacing.xl),
                    const SizedBox(height: AppSpacing.xl),
                    Row(
                      children: [
                        const Icon(Icons.public_rounded, color: AppColors.primary, size: 32),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          l10n.authLoginOrRegister,
                          style: AppTypography.title.copyWith(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _isRegister ? l10n.authRegisterHint : l10n.authLoginHint,
                      style: AppTypography.bodySecondary.copyWith(
                        fontSize: 15,
                        color: AppColors.textPrimary.withValues(alpha: 0.88),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    // Tab
                    Row(
                      children: [
                        Expanded(
                          child: AppChip(
                            label: l10n.authLogin,
                            selected: !_isRegister,
                            onTap: () => setState(() => _isRegister = false),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: AppChip(
                            label: l10n.authRegister,
                            selected: _isRegister,
                            onTap: () => setState(() => _isRegister = true),
                          ),
                        ),
                      ],
                    ),
                    if (!_firebaseReady) ...[
                      const SizedBox(height: AppSpacing.lg),
                      AppCard(
                        padding: AppSpacing.allMd,
                        child: Text(
                          l10n.authFirebaseConfigHint,
                          style: AppTypography.bodySecondary.copyWith(color: AppColors.primary),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    if (_isRegister) ...[
                      AppInput(
                        controller: _nameController,
                        label: l10n.authName,
                        hintText: l10n.authName,
                        prefixIcon: const Icon(Icons.person_outline),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    AppInput(
                      controller: _emailController,
                      label: l10n.authEmail,
                      hintText: l10n.authEmail,
                      prefixIcon: const Icon(Icons.mail_outline),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppInput(
                      controller: _passwordController,
                      label: l10n.authPassword,
                      hintText: l10n.authPassword,
                      prefixIcon: const Icon(Icons.lock_outline),
                      obscureText: true,
                      textInputAction: _isRegister ? TextInputAction.next : TextInputAction.done,
                    ),
                    if (_isRegister) ...[
                      const SizedBox(height: AppSpacing.md),
                      AppInput(
                        controller: _confirmPasswordController,
                        label: l10n.authConfirmPassword,
                        hintText: l10n.authConfirmPassword,
                        prefixIcon: const Icon(Icons.lock_outline),
                        obscureText: true,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    SizedBox(
                      height: AppSpacing.xxl + AppSpacing.sm,
                      child: AppButton(
                        label: _isRegister ? l10n.authRegisterAndSendEmail : l10n.authLogin,
                        onPressed: _loading ? null : (_isRegister ? _handleEmailRegister : _handleEmailLogin),
                        loading: _loading,
                        variant: AppButtonVariant.primary,
                      ),
                    ),
                    if (_isRegister) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        _registerEmailTip(context),
                        textAlign: TextAlign.center,
                        style: AppTypography.bodySecondary.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      l10n.authThirdPartyLogin,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySecondary.copyWith(
                        color: AppColors.textPrimary.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _SocialBtn(icon: Icons.g_mobiledata_rounded, label: l10n.authGoogleLogin, onPressed: _loading ? null : () => _runSignIn(_authService.signInWithGoogle)),
                    if (canUseApple) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _SocialBtn(icon: Icons.apple, label: l10n.authAppleLogin, onPressed: _loading ? null : () => _runSignIn(_authService.signInWithApple)),
                    ],
                    if (defaultTargetPlatform == TargetPlatform.macOS)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: Text(
                          l10n.authMacosUseEmailOrGoogle,
                          style: AppTypography.caption,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (kIsWeb)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: Text(
                          l10n.authWebAppleLimited,
                          style: AppTypography.caption,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadius.mdAll,
      child: InkWell(
        borderRadius: AppRadius.mdAll,
        onTap: onTap,
        child: Padding(
          padding: AppSpacing.allMd,
          child: Icon(icon, size: 20, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _SocialBtn extends StatelessWidget {
  const _SocialBtn({required this.icon, required this.label, this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSpacing.xxl + AppSpacing.xs,
      child: AppButton(
        variant: AppButtonVariant.secondary,
        icon: Icon(icon, size: 22, color: AppColors.primary),
        label: label,
        onPressed: onPressed,
      ),
    );
  }
}
