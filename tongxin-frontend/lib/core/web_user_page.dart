import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app_webview_page.dart';
import 'i18n_extra.dart';

/// WebView 用户信息页地址（.env: WEBVIEW_USER_PAGE_URL）
String? get webUserPageUrl {
  final v = dotenv.env['WEBVIEW_USER_PAGE_URL'];
  return (v != null && v.trim().isNotEmpty) ? v.trim() : null;
}

Future<void> openWebUserPage(BuildContext context) async {
  final url = webUserPageUrl;
  if (url == null) {
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
        const SnackBar(content: Text('WEBVIEW_USER_PAGE_URL 无效')),
      );
    }
    return;
  }
  await openInAppWebView(
    context,
    url: parsed.toString(),
    title: I18nExtra.webViewUserPageTitle(context),
    allowedHosts: <String>[parsed.host],
  );
}
