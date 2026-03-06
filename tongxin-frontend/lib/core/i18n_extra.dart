import 'package:flutter/material.dart';

class I18nExtra {
  I18nExtra._();

  static bool _isZh(BuildContext context) {
    return Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('zh');
  }

  static String webViewUserPageTitle(BuildContext context) {
    return _isZh(context) ? 'WebView 用户信息页' : 'WebView User Info';
  }

  static String webViewUserPageSubtitle(BuildContext context) {
    return _isZh(context)
        ? '通过 WebView 打开并显示当前登录用户信息'
        : 'Open with WebView and show current user info';
  }

  static String webViewUserPageUrlMissing(BuildContext context) {
    return _isZh(context)
        ? '未配置 WEBVIEW_USER_PAGE_URL'
        : 'WEBVIEW_USER_PAGE_URL is not configured';
  }
}
