import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/design/design_tokens.dart';
import '../../core/firebase_bootstrap.dart';
import '../../core/layout_mode.dart';
import '../../core/local_debug_mode.dart';
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
        _showMessage(
            UserRestrictions.getAccountStatusMessage(restrictions, context));
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
      _showMessage(
          AppLocalizations.of(context)!.authPleaseFillEmailAndPassword);
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
        _showMessage(
            UserRestrictions.getAccountStatusMessage(restrictions, context));
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
    if (name.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
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

  void _continueLocalDebug() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    _showMessage('已启用本地开发模式，请先调试无需登录的页面');
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

  Widget _buildModeToggle(AppLocalizations l10n) {
    Widget item({
      required bool selected,
      required String label,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.32)
                    : AppColors.border.withValues(alpha: 0.6),
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: selected ? AppColors.primary : AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          item(
            selected: !_isRegister,
            label: l10n.authLogin,
            onTap: () => setState(() => _isRegister = false),
          ),
          const SizedBox(width: AppSpacing.sm),
          item(
            selected: _isRegister,
            label: l10n.authRegister,
            onTap: () => setState(() => _isRegister = true),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPanel(AppLocalizations l10n) {
    Widget highlight(String value, String label) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.48),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: AppTypography.title.copyWith(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              style: AppTypography.bodySecondary.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF18140C),
            Color(0xFF0F1013),
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.account_balance_outlined,
              color: AppColors.primary,
              size: 28,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            '登录后继续查看策略、消息与交易员资料',
            style: AppTypography.title.copyWith(
              fontSize: 34,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            _isRegister ? l10n.authRegisterHint : l10n.authLoginHint,
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
              height: 1.7,
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Row(
            children: [
              Expanded(child: highlight('实时', '消息与策略动态同步')),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: highlight('统一', '网页与 App 账号体系共用')),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Text(
              '支持邮箱登录、Google 登录，以及后续浏览器内消息提醒。',
              style: AppTypography.bodySecondary.copyWith(
                color: AppColors.textSecondary,
                height: 1.7,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthCard(AppLocalizations l10n, {required bool desktop}) {
    final canUseApple = defaultTargetPlatform == TargetPlatform.iOS;
    return Container(
      padding: EdgeInsets.all(desktop ? AppSpacing.xxl : AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.login_rounded,
                  color: AppColors.primary,
                  size: 26,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isRegister
                          ? l10n.authRegister
                          : l10n.authLoginOrRegister,
                      style: AppTypography.title.copyWith(
                        fontSize: desktop ? 30 : 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '使用邮箱或第三方账号继续',
                      style: AppTypography.bodySecondary.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.showBackButton)
                _IconBtn(
                  icon: Icons.arrow_back_ios_new,
                  onTap: () => Navigator.of(context).pop(),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          _buildModeToggle(l10n),
          if (!_firebaseReady) ...[
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              padding: AppSpacing.allMd,
              child: Text(
                kIsWeb
                    ? l10n.authFirebaseConfigHintWeb
                    : l10n.authFirebaseConfigHint,
                style: AppTypography.bodySecondary.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
          if (LocalDebugMode.isEnabled) ...[
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              padding: AppSpacing.allMd,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前 macOS 本地调试未使用开发签名，Firebase 登录会被系统钥匙串拦截。',
                    style: AppTypography.body.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '现在先继续开发无需登录的页面；以后补好签名后再恢复真实登录。',
                    style: AppTypography.bodySecondary,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    variant: AppButtonVariant.secondary,
                    label: '继续本地开发',
                    onPressed: _loading ? null : _continueLocalDebug,
                  ),
                ],
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
            textInputAction:
                _isRegister ? TextInputAction.next : TextInputAction.done,
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
            height: 54,
            child: AppButton(
              label:
                  _isRegister ? l10n.authRegisterAndSendEmail : l10n.authLogin,
              onPressed: _loading
                  ? null
                  : (_isRegister ? _handleEmailRegister : _handleEmailLogin),
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
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: Divider(
                  color: AppColors.border.withValues(alpha: 0.7),
                  height: 1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text(
                  l10n.authThirdPartyLogin,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Divider(
                  color: AppColors.border.withValues(alpha: 0.7),
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _SocialBtn(
            icon: Icons.g_mobiledata_rounded,
            label: l10n.authGoogleLogin,
            onPressed: _loading
                ? null
                : () => _runSignIn(_authService.signInWithGoogle),
          ),
          if (canUseApple) ...[
            const SizedBox(height: AppSpacing.sm),
            _SocialBtn(
              icon: Icons.apple,
              label: l10n.authAppleLogin,
              onPressed: _loading
                  ? null
                  : () => _runSignIn(_authService.signInWithApple),
            ),
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
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final useDesktopLayout = LayoutMode.useDesktopLikeLayout(context);

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: useDesktopLayout ? AppSpacing.xl : AppSpacing.lg,
              vertical: AppSpacing.xl,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: useDesktopLayout ? 1180 : 560,
              ),
              child: useDesktopLayout
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 11, child: _buildInfoPanel(l10n)),
                        const SizedBox(width: AppSpacing.xl),
                        Expanded(
                          flex: 9,
                          child: _buildAuthCard(l10n, desktop: true),
                        ),
                      ],
                    )
                  : _buildAuthCard(l10n, desktop: false),
            ),
          ),
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
