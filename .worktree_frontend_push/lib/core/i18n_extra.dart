import 'package:flutter/material.dart';

class I18nExtra {
  I18nExtra._();

  static bool _isZh(BuildContext context) {
    return Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('zh');
  }

  static String webViewUserPageUrlMissing(BuildContext context) {
    return _isZh(context)
        ? '未配置 WEBVIEW_USER_PAGE_URL'
        : 'WEBVIEW_USER_PAGE_URL is not configured';
  }
}
