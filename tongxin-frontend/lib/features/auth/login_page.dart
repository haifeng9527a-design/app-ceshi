import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/firebase_bootstrap.dart';
import '../../l10n/app_localizations.dart';
import '../../core/user_restrictions.dart';
import 'auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();
  final _authService = AuthService();
  bool _loading = false;
  bool _isRegister = false;
  Timer? _cooldownTimer;
  int _resendCooldown = 0;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    _cooldownTimer?.cancel();
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
      if (mounted) Navigator.of(context).pop();
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
      if (mounted) Navigator.of(context).pop();
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
      _startResendCooldown();
    } catch (error) {
      _showMessage(_friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendVerification() async {
    if (!_firebaseReady) {
      _showMessage(AppLocalizations.of(context)!.authPleaseConfigureFirebase);
      return;
    }
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (_resendCooldown > 0) {
      _showMessage(AppLocalizations.of(context)!.authResendCooldown(_resendCooldown));
      return;
    }
    if (email.isEmpty || password.isEmpty) {
      _showMessage(AppLocalizations.of(context)!.authPleaseFillEmailAndPassword);
      return;
    }
    setState(() => _loading = true);
    try {
      await _authService.resendVerificationForEmailPassword(
        email: email,
        password: password,
      );
      _showMessage(AppLocalizations.of(context)!.authVerificationEmailSent);
      _startResendCooldown();
    } catch (error) {
      _showMessage('操作失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF5C5F68),
        margin: const EdgeInsets.all(16),
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

  void _startResendCooldown([int seconds = 60]) {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldown = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldown <= 1) {
        timer.cancel();
        setState(() => _resendCooldown = 0);
      } else {
        setState(() => _resendCooldown -= 1);
      }
    });
  }

  // 与 App 统一：金色主色、深色背景（market_page / profile_page 风格）
  static const _accent = Color(0xFFD4AF37);
  static const _bg = Color(0xFF0B0C0E);
  static const _text = Color(0xFFE8D5A3);
  static const _textMuted = Color(0xFF9CA3AF);

  @override
  Widget build(BuildContext context) {
    final canUseApple = defaultTargetPlatform == TargetPlatform.iOS;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _IconBtn(
                        icon: Icons.arrow_back_ios_new,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(height: 40),
                    Row(
                      children: [
                        Icon(Icons.public_rounded, color: _accent, size: 28),
                        const SizedBox(width: 10),
                        Text(
                          l10n.authLoginOrRegister,
                          style: const TextStyle(
                            color: _text,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isRegister ? l10n.authRegisterHint : l10n.authLoginHint,
                      style: const TextStyle(color: _textMuted, fontSize: 15),
                    ),
                    const SizedBox(height: 40),
                    // Tab
                    Row(
                      children: [
                        Expanded(
                          child: _TabChip(
                            label: l10n.authLogin,
                            selected: !_isRegister,
                            onTap: () => setState(() => _isRegister = false),
                            accent: _accent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TabChip(
                            label: l10n.authRegister,
                            selected: _isRegister,
                            onTap: () => setState(() => _isRegister = true),
                            accent: _accent,
                          ),
                        ),
                      ],
                    ),
                    if (!_firebaseReady) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _accent.withValues(alpha: 0.3)),
                        ),
                        child: Text(l10n.authFirebaseConfigHint, style: const TextStyle(color: _accent, fontSize: 13)),
                      ),
                    ],
                    const SizedBox(height: 32),
                    if (_isRegister) ...[
                      _Input(controller: _nameController, label: l10n.authName, icon: Icons.person_outline, textInputAction: TextInputAction.next, accent: _accent),
                      const SizedBox(height: 16),
                    ],
                    _Input(controller: _emailController, label: l10n.authEmail, icon: Icons.mail_outline, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next, accent: _accent),
                    const SizedBox(height: 16),
                    _Input(controller: _passwordController, label: l10n.authPassword, icon: Icons.lock_outline, obscureText: true, textInputAction: _isRegister ? TextInputAction.next : TextInputAction.done, accent: _accent),
                    if (_isRegister) ...[
                      const SizedBox(height: 16),
                      _Input(controller: _confirmPasswordController, label: l10n.authConfirmPassword, icon: Icons.lock_outline, obscureText: true, accent: _accent),
                    ],
                    const SizedBox(height: 32),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _loading ? null : (_isRegister ? _handleEmailRegister : _handleEmailLogin),
                        style: FilledButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: const Color(0xFF111215),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _loading
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF111215)))
                            : Text(_isRegister ? l10n.authRegisterAndSendEmail : l10n.authLogin, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    if (_isRegister) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _loading || _resendCooldown > 0 ? null : _resendVerification,
                          child: Text(
                            _resendCooldown > 0 ? l10n.authSendVerificationEmailCooldown(_resendCooldown) : l10n.authSendVerificationEmail,
                            style: const TextStyle(color: _accent, fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(l10n.authThirdPartyLogin, textAlign: TextAlign.center, style: const TextStyle(color: _textMuted, fontSize: 13)),
                    const SizedBox(height: 16),
                    _SocialBtn(icon: Icons.g_mobiledata_rounded, label: l10n.authGoogleLogin, onPressed: _loading ? null : () => _runSignIn(_authService.signInWithGoogle)),
                    if (canUseApple) ...[
                      const SizedBox(height: 10),
                      _SocialBtn(icon: Icons.apple, label: l10n.authAppleLogin, onPressed: _loading ? null : () => _runSignIn(_authService.signInWithApple)),
                    ],
                    if (defaultTargetPlatform == TargetPlatform.macOS)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(l10n.authMacosUseEmailOrGoogle, style: const TextStyle(color: _textMuted, fontSize: 12), textAlign: TextAlign.center),
                      ),
                    if (kIsWeb)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(l10n.authWebAppleLimited, style: const TextStyle(color: _textMuted, fontSize: 12), textAlign: TextAlign.center),
                      ),
                    const SizedBox(height: 24),
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
      color: const Color(0xFF111215),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, size: 20, color: const Color(0xFF9CA3AF)),
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({required this.label, required this.selected, required this.onTap, required this.accent});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? accent : const Color(0xFF111215),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? const Color(0xFF111215) : const Color(0xFF9CA3AF),
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Input extends StatelessWidget {
  const _Input({
    required this.controller,
    required this.label,
    required this.icon,
    required this.accent,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final Color accent;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      style: const TextStyle(color: Color(0xFFE5E5E7), fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: const Color(0xFF9CA3AF)),
        labelStyle: const TextStyle(color: Color(0xFF9CA3AF)),
        floatingLabelStyle: TextStyle(color: accent),
        filled: true,
        fillColor: const Color(0xFF0B0C0E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A2D34), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
      height: 50,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFE5E5E7),
          side: const BorderSide(color: Color(0xFFD4AF37), width: 0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: const Color(0xFFD4AF37)),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
