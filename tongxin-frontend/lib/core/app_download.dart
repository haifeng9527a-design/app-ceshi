import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';

/// 应用下载页地址（.env 中 APP_DOWNLOAD_URL，未配置时为空，后续上线后填写）。
String? get appDownloadUrl {
  final v = dotenv.env['APP_DOWNLOAD_URL'];
  return (v != null && v.trim().isNotEmpty) ? v.trim() : null;
}

/// 打开应用下载页；若未配置则提示「下载地址敬请期待」。
Future<void> openAppDownloadPage(BuildContext context) async {
  final url = appDownloadUrl;
  if (url == null) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('下载地址敬请期待')),
      );
    }
    return;
  }
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('无法打开下载页')),
    );
  }
}
