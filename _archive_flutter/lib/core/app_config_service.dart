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
  String? _rankingsIntroTitle;
  String? _rankingsIntroSummary;
  String? _rankingsIntroDetail;
  String? _rankingsSignupTitle;
  String? _rankingsSignupSummary;
  String? _rankingsSignupDetail;
  String? _rankingsSignupEntryUrl;
  String? _rankingsActivityTitle;
  String? _rankingsActivitySummary;
  String? _rankingsActivityDetail;

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

  String get rankingsIntroTitle =>
      (_rankingsIntroTitle != null && _rankingsIntroTitle!.trim().isNotEmpty) ? _rankingsIntroTitle!.trim() : '排行榜简介';
  String get rankingsIntroSummary =>
      (_rankingsIntroSummary != null && _rankingsIntroSummary!.trim().isNotEmpty) ? _rankingsIntroSummary!.trim() : '榜单基于导师收益与稳定性综合展示，帮助学员快速发现值得长期跟踪的导师。';
  String get rankingsIntroDetail =>
      (_rankingsIntroDetail != null && _rankingsIntroDetail!.trim().isNotEmpty) ? _rankingsIntroDetail!.trim() : '排行榜按不同周期展示导师表现。你可以查看周榜、月榜、季度榜、年度榜和总榜，结合胜率与盈亏趋势，评估导师风格是否与你匹配。';

  String get rankingsSignupTitle =>
      (_rankingsSignupTitle != null && _rankingsSignupTitle!.trim().isNotEmpty) ? _rankingsSignupTitle!.trim() : '报名须知与入口';
  String get rankingsSignupSummary =>
      (_rankingsSignupSummary != null && _rankingsSignupSummary!.trim().isNotEmpty) ? _rankingsSignupSummary!.trim() : '参与导师评选或活动报名前，请先阅读规则说明与资格要求。';
  String get rankingsSignupDetail =>
      (_rankingsSignupDetail != null && _rankingsSignupDetail!.trim().isNotEmpty) ? _rankingsSignupDetail!.trim() : '报名须知：\n1. 需完成实名认证；\n2. 近30天有有效交易记录；\n3. 严禁刷单或虚假收益展示。\n\n通过入口链接提交报名信息，审核结果将在1-3个工作日内反馈。';
  String get rankingsSignupEntryUrl =>
      (_rankingsSignupEntryUrl != null && _rankingsSignupEntryUrl!.trim().isNotEmpty) ? _rankingsSignupEntryUrl!.trim() : 'https://example.com/rankings-signup';

  String get rankingsActivityTitle =>
      (_rankingsActivityTitle != null && _rankingsActivityTitle!.trim().isNotEmpty) ? _rankingsActivityTitle!.trim() : '最新活动介绍';
  String get rankingsActivitySummary =>
      (_rankingsActivitySummary != null && _rankingsActivitySummary!.trim().isNotEmpty) ? _rankingsActivitySummary!.trim() : '本月导师挑战赛进行中，完成阶段目标可获得曝光位与奖励。';
  String get rankingsActivityDetail =>
      (_rankingsActivityDetail != null && _rankingsActivityDetail!.trim().isNotEmpty) ? _rankingsActivityDetail!.trim() : '活动时间：每月1日-25日\n活动内容：按收益稳定性、回撤控制和互动质量综合评定。\n奖励说明：Top 榜单导师将获得首页推荐位和官方流量支持。';

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
      final rankingsIntroTitle = map['rankings_intro_title'];
      final rankingsIntroSummary = map['rankings_intro_summary'];
      final rankingsIntroDetail = map['rankings_intro_detail'];
      final rankingsSignupTitle = map['rankings_signup_title'];
      final rankingsSignupSummary = map['rankings_signup_summary'];
      final rankingsSignupDetail = map['rankings_signup_detail'];
      final rankingsSignupEntryUrl = map['rankings_signup_entry_url'];
      final rankingsActivityTitle = map['rankings_activity_title'];
      final rankingsActivitySummary = map['rankings_activity_summary'];
      final rankingsActivityDetail = map['rankings_activity_detail'];
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
      _rankingsIntroTitle = rankingsIntroTitle != null ? rankingsIntroTitle.toString().trim() : null;
      if (_rankingsIntroTitle != null && _rankingsIntroTitle!.isEmpty) _rankingsIntroTitle = null;
      _rankingsIntroSummary = rankingsIntroSummary != null ? rankingsIntroSummary.toString().trim() : null;
      if (_rankingsIntroSummary != null && _rankingsIntroSummary!.isEmpty) _rankingsIntroSummary = null;
      _rankingsIntroDetail = rankingsIntroDetail != null ? rankingsIntroDetail.toString().trim() : null;
      if (_rankingsIntroDetail != null && _rankingsIntroDetail!.isEmpty) _rankingsIntroDetail = null;
      _rankingsSignupTitle = rankingsSignupTitle != null ? rankingsSignupTitle.toString().trim() : null;
      if (_rankingsSignupTitle != null && _rankingsSignupTitle!.isEmpty) _rankingsSignupTitle = null;
      _rankingsSignupSummary = rankingsSignupSummary != null ? rankingsSignupSummary.toString().trim() : null;
      if (_rankingsSignupSummary != null && _rankingsSignupSummary!.isEmpty) _rankingsSignupSummary = null;
      _rankingsSignupDetail = rankingsSignupDetail != null ? rankingsSignupDetail.toString().trim() : null;
      if (_rankingsSignupDetail != null && _rankingsSignupDetail!.isEmpty) _rankingsSignupDetail = null;
      _rankingsSignupEntryUrl = rankingsSignupEntryUrl != null ? rankingsSignupEntryUrl.toString().trim() : null;
      if (_rankingsSignupEntryUrl != null && _rankingsSignupEntryUrl!.isEmpty) _rankingsSignupEntryUrl = null;
      _rankingsActivityTitle = rankingsActivityTitle != null ? rankingsActivityTitle.toString().trim() : null;
      if (_rankingsActivityTitle != null && _rankingsActivityTitle!.isEmpty) _rankingsActivityTitle = null;
      _rankingsActivitySummary = rankingsActivitySummary != null ? rankingsActivitySummary.toString().trim() : null;
      if (_rankingsActivitySummary != null && _rankingsActivitySummary!.isEmpty) _rankingsActivitySummary = null;
      _rankingsActivityDetail = rankingsActivityDetail != null ? rankingsActivityDetail.toString().trim() : null;
      if (_rankingsActivityDetail != null && _rankingsActivityDetail!.isEmpty) _rankingsActivityDetail = null;
    } catch (_) {
      _hiddenVersions = [];
      _webviewUrl = null;
      _menuTitle = null;
      _menuSubtitle = null;
      _hiddenMenuTitle = null;
      _hiddenMenuSubtitle = null;
      _rankingsIntroTitle = null;
      _rankingsIntroSummary = null;
      _rankingsIntroDetail = null;
      _rankingsSignupTitle = null;
      _rankingsSignupSummary = null;
      _rankingsSignupDetail = null;
      _rankingsSignupEntryUrl = null;
      _rankingsActivityTitle = null;
      _rankingsActivitySummary = null;
      _rankingsActivityDetail = null;
    }
  }
}
