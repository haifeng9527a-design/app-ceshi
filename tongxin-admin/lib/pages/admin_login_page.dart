import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/admin_api_client.dart';
import '../l10n/admin_strings.dart';
import 'admin_home_page.dart';

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _errorText;

  static const Color _accent = Color(0xFFD4AF37);
  static const Color _surface = Color(0xFF1A1C21);

  @override
  void initState() {
    super.initState();
    _bootstrapIfNeeded();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// 首次部署：若数据库无管理员，则从 env 创建默认账号
  Future<void> _bootstrapIfNeeded() async {
    if (!AdminApiClient.instance.isAvailable) return;
    try {
      await AdminApiClient.instance.post('api/admin/auth/bootstrap');
    } catch (_) {}
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) return;

    setState(() {
      _errorText = null;
      _loading = true;
    });
    await Future.delayed(const Duration(milliseconds: 200));

    if (!AdminApiClient.instance.isAvailable) {
      if (!mounted) return;
      setState(() {
        _errorText = '未配置 API 地址或密钥，请检查 .env';
        _loading = false;
      });
      return;
    }

    try {
      final resp = await AdminApiClient.instance.post(
        'api/admin/auth/login',
        body: {'username': username, 'password': password},
      );
      if (!mounted) return;

      if (resp.statusCode == 200) {
        setState(() => _loading = false);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AdminHomePage()),
        );
        return;
      }

      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
      final err = body is Map ? body['error']?.toString() : null;
      if (resp.statusCode == 403) {
        setState(() {
          _errorText = err ?? '账户已锁定，请稍后再试';
          _loading = false;
        });
        return;
      }
      setState(() {
        _errorText = err ?? '账号或密码错误';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = '登录失败：$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.admin_panel_settings_rounded,
                    size: 56,
                    color: _accent,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '后台管理',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: _accent,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '请登录后管理后台',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                        ),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _accent.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            labelText: AdminStrings.authAccount,
                            hintText: AdminStrings.authEnterAdminAccount,
                            prefixIcon: const Icon(Icons.person_outline, color: _accent),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: _accent.withOpacity(0.5)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: _accent, width: 1.5),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return AdminStrings.authEnterAccount;
                            return null;
                          },
                          onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: AdminStrings.authPassword,
                            hintText: AdminStrings.authEnterPasswordHint,
                            prefixIcon: const Icon(Icons.lock_outline, color: _accent),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                color: _accent,
                              ),
                              onPressed: () {
                                setState(() => _obscurePassword = !_obscurePassword);
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: _accent.withOpacity(0.5)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: _accent, width: 1.5),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return '请输入密码';
                            return null;
                          },
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        if (_errorText != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _errorText!,
                            style: const TextStyle(color: Color(0xFFE57373), fontSize: 13),
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _loading
                              ? null
                              : () {
                                  if (_formKey.currentState?.validate() ?? false) {
                                    _submit();
                                  }
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: const Color(0xFF111215),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(AdminStrings.authLogin),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
