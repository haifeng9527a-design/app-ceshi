import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  }

  /// 立即请求全部权限（不检查是否已展示过），用于「收不到推送」等页面的「重新请求」按钮。
  static Future<void> requestAllPermissionsNow(BuildContext context) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await _requestAllPermissions(context);
  }

  /// 来电全屏接听：若未授予「显示在其他应用上层」，弹窗说明并引导去设置。
  /// 后台或锁屏时能否直接弹出接听界面（像微信来电）依赖此权限，华为/小米等需手动开启。
  static Future<void> showCallFullScreenPermissionGuide(BuildContext context) async {
    if (kIsWeb || !Platform.isAndroid) return;
    final status = await Permission.systemAlertWindow.status;
    if (status.isGranted) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('来电全屏接听'),
        content: const Text(
          '为了在后台或锁屏时直接弹出接听界面（像微信来电一样），需要允许本应用「显示在其他应用上层」。\n\n'
          '请点击「去设置」，在设置页中找到「显示在其他应用上层」或「悬浮窗」等选项，并开启 teacher_hub。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await Permission.systemAlertWindow.request();
              if (ctx.mounted) await openAppSettings();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
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
        title: const Text('通知未开启'),
        content: const Text(
          '您已拒绝通知权限，将无法收到新消息提醒。可点击「去授权」再次请求，或到系统设置中开启。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _requestAllPermissions(context);
            },
            child: const Text('去授权'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await openAppSettings();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }
}
