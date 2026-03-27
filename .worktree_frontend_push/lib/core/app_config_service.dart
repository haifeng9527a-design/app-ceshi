import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App 配置服务：启动时从后端拉取 app_config，本地缓存
/// 用于用户交易中心菜单的版本控制等
class AppConfigService {
  AppConfigService._();
  static final AppConfigService instance = AppConfigService._();

  static const _prefsKey = 'app_config_cache';
  static const _prefsKeyFetchedAt = 'app_config_fetched_at';
  static const _cacheMaxAgeMs = 24 * 60 * 60 * 1000; // 24 小时

  String? _baseUrl;
  List<String>? _hiddenVersions;
  String? _webviewUrl;
  String? _menuTitle;
  String? _menuSubtitle;
  String? _hiddenMenuTitle;
  String? _hiddenMenuSubtitle;

  String? get _apiBaseUrl {
    _baseUrl ??= dotenv.env['TONGXIN_API_URL']?.trim();
    if (_baseUrl != null && _baseUrl!.endsWith('/')) {
      _baseUrl = _baseUrl!.substring(0, _baseUrl!.length - 1);
    }
    return _baseUrl;
  }

  /// 用户交易中心菜单标题（配置为空时用默认值）
  String get userTradingCenterMenuTitle =>
      (_menuTitle != null && _menuTitle!.trim().isNotEmpty) ? _menuTitle!.trim() : '用户交易中心';

  /// 用户交易中心菜单备注/副标题（配置为空时用默认值）
  String get userTradingCenterMenuSubtitle =>
      (_menuSubtitle != null && _menuSubtitle!.trim().isNotEmpty) ? _menuSubtitle!.trim() : '通过 WebView 打开用户交易中心';

  /// 隐藏时显示的名称（版本在隐藏列表中时）
  String get userTradingCenterHiddenMenuTitle =>
      (_hiddenMenuTitle != null && _hiddenMenuTitle!.trim().isNotEmpty) ? _hiddenMenuTitle!.trim() : '用户交易中心';

  /// 隐藏时显示的备注（版本在隐藏列表中时）
  String get userTradingCenterHiddenMenuSubtitle =>
      (_hiddenMenuSubtitle != null && _hiddenMenuSubtitle!.trim().isNotEmpty) ? _hiddenMenuSubtitle!.trim() : '当前版本暂不支持，请访问下方链接';

  /// WebView 用户交易中心页面 URL（优先用配置，否则 .env）
  String? get webviewUserPageUrl {
    if (_webviewUrl != null && _webviewUrl!.trim().isNotEmpty) {
      return _webviewUrl!.trim();
    }
    return dotenv.env['WEBVIEW_USER_PAGE_URL']?.trim();
  }

  /// 是否应显示用户交易中心菜单（在隐藏列表中的版本不显示，否则显示）
  Future<bool> isUserTradingCenterMenuEnabled() async {
    await ensureLoaded();
    final hidden = _hiddenVersions;
    if (hidden == null || hidden.isEmpty) return true;
    final info = await PackageInfo.fromPlatform();
    final appVersion = info.version.trim();
    return !hidden.any((v) => _versionEquals(appVersion, v.trim()));
  }

  bool _versionEquals(String a, String b) {
    if (a == b) return true;
    final pa = _parseVersion(a);
    final pb = _parseVersion(b);
    return pa[0] == pb[0] && pa[1] == pb[1] && pa[2] == pb[2];
  }

  List<int> _parseVersion(String v) {
    final parts = v.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
    return [
      parts.isNotEmpty ? parts[0] : 0,
      parts.length > 1 ? parts[1] : 0,
      parts.length > 2 ? parts[2] : 0,
    ];
  }

  Future<void> ensureLoaded() async {
    if (_hiddenVersions != null) return;
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefsKey);
    final fetchedAt = prefs.getInt(_prefsKeyFetchedAt) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (cached != null && (now - fetchedAt) < _cacheMaxAgeMs) {
      _applyFromJson(cached);
      return;
    }
    await fetchAndCache();
  }

  Future<void> fetchAndCache() async {
    final base = _apiBaseUrl;
    if (base == null || base.isEmpty) {
      _hiddenVersions = null;
      _webviewUrl = null;
      return;
    }
    try {
      final uri = Uri.parse('$base/api/config/app');
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, resp.body);
        await prefs.setInt(_prefsKeyFetchedAt, DateTime.now().millisecondsSinceEpoch);
        _applyFromJson(resp.body);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AppConfigService] fetch failed: $e');
      }
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_prefsKey);
      if (cached != null) {
        _applyFromJson(cached);
      } else {
        _hiddenVersions = [];
      }
    }
  }

  void _applyFromJson(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final hidden = map['user_trading_center_hidden_versions'];
      final url = map['webview_user_page_url'];
      final title = map['user_trading_center_menu_title'];
      final subtitle = map['user_trading_center_menu_subtitle'];
      final hiddenTitle = map['user_trading_center_hidden_menu_title'];
      final hiddenSubtitle = map['user_trading_center_hidden_menu_subtitle'];
      if (hidden != null) {
        final s = hidden.toString().trim();
        _hiddenVersions = s.isEmpty
            ? <String>[]
            : s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      } else {
        _hiddenVersions = [];
      }
      _webviewUrl = url != null ? url.toString().trim() : null;
      if (_webviewUrl != null && _webviewUrl!.isEmpty) _webviewUrl = null;
      _menuTitle = title != null ? title.toString().trim() : null;
      if (_menuTitle != null && _menuTitle!.isEmpty) _menuTitle = null;
      _menuSubtitle = subtitle != null ? subtitle.toString().trim() : null;
      if (_menuSubtitle != null && _menuSubtitle!.isEmpty) _menuSubtitle = null;
      _hiddenMenuTitle = hiddenTitle != null ? hiddenTitle.toString().trim() : null;
      if (_hiddenMenuTitle != null && _hiddenMenuTitle!.isEmpty) _hiddenMenuTitle = null;
      _hiddenMenuSubtitle = hiddenSubtitle != null ? hiddenSubtitle.toString().trim() : null;
      if (_hiddenMenuSubtitle != null && _hiddenMenuSubtitle!.isEmpty) _hiddenMenuSubtitle = null;
    } catch (_) {
      _hiddenVersions = [];
      _webviewUrl = null;
      _menuTitle = null;
      _menuSubtitle = null;
      _hiddenMenuTitle = null;
      _hiddenMenuSubtitle = null;
    }
  }
}
