import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import 'notification_service.dart';

/// 安装/首次启动时一次性请求应用所需全部权限（通知、后台运行、相机、麦克风、相册、悬浮窗等）。
class NotificationSettingsGuide {
  static const String _keyShown = 'notification_settings_guide_shown';

  /// 若为 Android 且尚未请求过，直接依次触发系统权限弹窗（如「是否允许 teacher_hub 发送通知？」），用户逐项点「允许」即可，无需先点应用内弹窗。
  static Future<void> showIfNeeded(BuildContext context) async {
    if (kIsWeb || !Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_keyShown) == true) return;
    await prefs.setBool(_keyShown, true);
    if (!context.mounted) return;
    await _requestAllPermissions(context);
  }

  /// 依次请求全部所需权限，每项间隔约 0.5 秒，避免系统弹窗重叠。
  static Future<void> _requestAllPermissions(BuildContext context) async {
    if (kIsWeb || !Platform.isAndroid) return;

    final permissions = <Permission>[
      Permission.notification,
      Permission.ignoreBatteryOptimizations,
      Permission.camera,
      Permission.microphone,
      Permission.photos,
      Permission.systemAlertWindow,
    ];

    for (final p in permissions) {
      if (!context.mounted) return;
      try {
        final status = await p.status;
        if (status.isDenied || status.isPermanentlyDenied) {
          await p.request();
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      } catch (_) {
        // 部分机型某项权限不可用时跳过
      }
    }
    // Android 14+ 来电全屏：若未授予「全屏意图」，引导去设置
    if (context.mounted) {
      await showFullScreenIntentPermissionGuide(context);
    }
  }

  /// 立即请求全部权限（不检查是否已展示过），用于「收不到推送」等页面的「重新请求」按钮。
  static Future<void> requestAllPermissionsNow(BuildContext context) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await _requestAllPermissions(context);
  }

  /// Android 14+ 来电全屏接听：若未授予「全屏意图」，直接跳转设置页让用户点允许。
  static Future<void> showFullScreenIntentPermissionGuide(BuildContext context) async {
    if (kIsWeb || !Platform.isAndroid) return;
    final canUse = await NotificationService.canUseFullScreenIntent();
    if (canUse) return;
    await NotificationService.openFullScreenIntentSettings();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.notifFullScreenIntentHint)),
      );
    }
  }

  /// 来电全屏接听：若未授予「显示在其他应用上层」，直接跳转设置页让用户点允许（华为/小米等需此项）。
  static Future<void> showCallFullScreenPermissionGuide(BuildContext context) async {
    if (kIsWeb || !Platform.isAndroid) return;
    final status = await Permission.systemAlertWindow.status;
    if (status.isGranted) return;
    await Permission.systemAlertWindow.request();
  }

  /// 若通知未授予，可再次触发系统请求或引导去设置。
  static Future<void> showIfPermissionDenied(BuildContext context) async {
    if (kIsWeb || !Platform.isAndroid) return;
    final status = await Permission.notification.status;
    if (status.isGranted) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.notifNotEnabled),
        content: Text(AppLocalizations.of(context)!.notifPermissionDenied),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(context)!.commonCancel),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _requestAllPermissions(context);
            },
            child: Text(AppLocalizations.of(context)!.notifGoAuthorize),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await openAppSettings();
            },
            child: Text(AppLocalizations.of(context)!.notifGoSettings),
          ),
        ],
      ),
    );
  }
}
