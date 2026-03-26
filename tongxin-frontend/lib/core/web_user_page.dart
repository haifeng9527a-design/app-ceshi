import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app_config_service.dart';
import 'app_webview_page.dart';
import 'i18n_extra.dart';

/// WebView 用户交易中心地址（app_config 或 .env: WEBVIEW_USER_PAGE_URL）
String get webUserPageUrl {
  return AppConfigService.instance.webviewUserPageUrl?.trim() ?? '';
}

Future<void> openWebUserPage(BuildContext context) async {
  await AppConfigService.instance.ensureLoaded();
  final url = webUserPageUrl;
  if (url.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(I18nExtra.webViewUserPageUrlMissing(context))),
      );
    }
    return;
  }
  final parsed = Uri.tryParse(url);
  final valid = parsed != null &&
      (parsed.scheme == 'https' || parsed.scheme == 'http') &&
      parsed.host.isNotEmpty;
  if (!valid) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(I18nExtra.webViewUserPageUrlInvalid(context))),
      );
    }
    return;
  }
  final apiBaseUrl = dotenv.env['TONGXIN_API_URL']?.trim();
  final authToken = await FirebaseAuth.instance.currentUser?.getIdToken();
  await openInAppWebView(
    context,
    url: parsed.toString(),
    title: AppConfigService.instance.userTradingCenterMenuTitle,
    allowedHosts: <String>[parsed.host],
    apiBaseUrl: apiBaseUrl != null && apiBaseUrl.isNotEmpty ? apiBaseUrl.replaceFirst(RegExp(r'/$'), '') : null,
    authToken: authToken,
  );
}
