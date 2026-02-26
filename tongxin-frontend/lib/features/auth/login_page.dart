import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/firebase_bootstrap.dart';
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

  Future<void> _run(Future<void> Function() action) async {
    if (!_firebaseReady) {
      _showMessage('请先配置 Firebase（添加配置文件）');
      return;
    }
    setState(() => _loading = true);
    try {
      await action();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      _showMessage(_friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 第三方登录后校验后台限制，受限则登出并提示
  Future<void> _runSignIn(Future<void> Function() signInAction) async {
    if (!_firebaseReady) {
      _showMessage('请先配置 Firebase（添加配置文件）');
      return;
    }
    setState(() => _loading = true);
    try {
      await signInAction();
      final restrictions = await UserRestrictions.getMyRestrictionRow();
      if (UserRestrictions.isRestrictedLogin(restrictions)) {
        await _authService.signOut();
        _showMessage(UserRestrictions.getAccountStatusMessage(restrictions));
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
      _showMessage('请先配置 Firebase（添加配置文件）');
      return;
    }
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      _showMessage('请先填写邮箱和密码');
      return;
    }
    setState(() => _loading = true);
    try {
      await _authService.signInWithEmail(email: email, password: password);
      final verified = await _authService.isEmailVerified();
      if (!verified) {
        await _authService.sendEmailVerificationIfNeeded();
        await _authService.signOut();
        _showMessage('已发送验证邮件，请验证后再登录');
        return;
      }
      // 校验后台限制：限制登录 / 封禁 / 冻结
      final restrictions = await UserRestrictions.getMyRestrictionRow();
      if (UserRestrictions.isRestrictedLogin(restrictions)) {
        await _authService.signOut();
        _showMessage(UserRestrictions.getAccountStatusMessage(restrictions));
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
      _showMessage('请先配置 Firebase（添加配置文件）');
      return;
    }
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final name = _nameController.text.trim();
    if (name.isEmpty || email.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      _showMessage('请先填写姓名、邮箱和两次密码');
      return;
    }
    if (password != confirmPassword) {
      _showMessage('两次密码不一致');
      return;
    }
    if (password.length < 6) {
      _showMessage('密码至少 6 位');
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
      _showMessage('已发送验证邮件，请验证后再登录');
      _startResendCooldown();
    } catch (error) {
      _showMessage(_friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendVerification() async {
    if (!_firebaseReady) {
      _showMessage('请先配置 Firebase（添加配置文件）');
      return;
    }
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (_resendCooldown > 0) {
      _showMessage('请稍后再试（${_resendCooldown}s）');
      return;
    }
    if (email.isEmpty || password.isEmpty) {
      _showMessage('请先填写邮箱和密码');
      return;
    }
    setState(() => _loading = true);
    try {
      await _authService.resendVerificationForEmailPassword(
        email: email,
        password: password,
      );
      _showMessage('验证邮件已发送，请检查邮箱');
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

  @override
  Widget build(BuildContext context) {
    // macOS 未配置 Sign in with Apple 签名时必现 error 1000，仅 iOS 展示 Apple 登录
    final canUseApple = defaultTargetPlatform == TargetPlatform.iOS;

    return Scaffold(
      appBar: AppBar(
        title: const Text('登录/注册'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_firebaseReady)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF111215),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD4AF37), width: 0.4),
              ),
              child: const Text(
                '尚未配置 Firebase，请先添加配置文件（google-services.json / GoogleService-Info.plist）。',
              ),
            ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF111215),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD4AF37), width: 0.4),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _AuthModeTab(
                    label: '登录',
                    selected: !_isRegister,
                    onTap: () => setState(() => _isRegister = false),
                  ),
                ),
                Expanded(
                  child: _AuthModeTab(
                    label: '注册',
                    selected: _isRegister,
                    onTap: () => setState(() => _isRegister = true),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_isRegister) ...[
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: '姓名'),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: '邮箱'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: '密码'),
          ),
          if (_isRegister) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '确认密码'),
            ),
          ],
          const SizedBox(height: 16),
          if (_isRegister)
            FilledButton(
              onPressed: _loading ? null : _handleEmailRegister,
              child: const Text('注册并发送验证邮件'),
            )
          else
            FilledButton(
              onPressed: _loading ? null : _handleEmailLogin,
              child: const Text('登录'),
            ),
          if (_isRegister)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _loading || _resendCooldown > 0
                    ? null
                    : _resendVerification,
                child: Text(
                  _resendCooldown > 0
                      ? '发送验证邮件（${_resendCooldown}s）'
                      : '发送验证邮件',
                ),
              ),
            ),
          const SizedBox(height: 8),
          _SectionDivider(label: '第三方登录'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loading ? null : () => _runSignIn(_authService.signInWithGoogle),
            icon: const Icon(Icons.login),
            label: const Text('Google 登录'),
          ),
          if (canUseApple) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed:
                  _loading ? null : () => _runSignIn(_authService.signInWithApple),
              icon: const Icon(Icons.apple),
              label: const Text('Apple 登录'),
            ),
          ],
          if (defaultTargetPlatform == TargetPlatform.macOS)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'macOS 端请使用邮箱或 Google 登录。',
                style: TextStyle(color: Color(0xFF8A6D1D), fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          if (kIsWeb)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Web 端 Apple 登录受限，请使用邮箱或 Google。'),
            ),
        ],
      ),
    );
  }
}

class _AuthModeTab extends StatelessWidget {
  const _AuthModeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFD4AF37) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.black : const Color(0xFFD4AF37),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xFF2A2D34))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF8A6D1D)),
          ),
        ),
        const Expanded(child: Divider(color: Color(0xFF2A2D34))),
      ],
    );
  }
}
