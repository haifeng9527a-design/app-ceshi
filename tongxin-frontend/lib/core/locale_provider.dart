import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _localeKey = 'app_locale';

/// 应用语言偏好管理，持久化到 SharedPreferences
class LocaleProvider extends ChangeNotifier {
  LocaleProvider._();
  static final LocaleProvider _instance = LocaleProvider._();
  static LocaleProvider get instance => _instance;

  Locale? _locale;
  Locale? get locale => _locale;

  static const Locale zh = Locale('zh');
  static const Locale en = Locale('en');
  static const List<Locale> supported = [zh, en];

  /// 初始化：从 SharedPreferences 读取已保存的语言
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_localeKey);
    if (code != null && (code == 'zh' || code == 'en')) {
      _instance._locale = Locale(code);
    }
  }

  /// 设置语言并持久化
  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, locale.languageCode);
    notifyListeners();
  }

  /// 清除语言偏好，使用系统语言
  Future<void> clearLocale() async {
    if (_locale == null) return;
    _locale = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_localeKey);
    notifyListeners();
  }
}
