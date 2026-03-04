import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app.dart';
import 'core/locale_provider.dart';
import 'features/messages/group_join_link_handler.dart';
import 'core/firebase_bootstrap.dart';
import 'core/notification_service.dart';
import 'core/supabase_bootstrap.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
    if (kDebugMode) {
      final polygonKey = dotenv.env['POLYGON_API_KEY']?.trim();
      final backendUrl = dotenv.env['TONGXIN_API_URL']?.trim() ?? dotenv.env['BACKEND_URL']?.trim();
      debugPrint('dotenv: POLYGON_API_KEY ${polygonKey != null && polygonKey.isNotEmpty ? "loaded" : "empty/missing"}');
      debugPrint('dotenv: TONGXIN_API_URL ${backendUrl != null && backendUrl.isNotEmpty ? "loaded (K线走后端)" : "empty (K线直连 Polygon/Twelve)"}');
    }
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('dotenv load failed: $e');
      debugPrint('$st');
    }
    // 未打包 .env 或路径错误时继续运行，仅部分功能不可用
  }
  await FirebaseBootstrap.init();
  await SupabaseBootstrap.init();
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    try {
      await NotificationService.init();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[main] NotificationService.init 失败，继续启动: $e');
        debugPrint('$st');
      }
    }
  }
  await LocaleProvider.init();
  runApp(const TeacherHubApp());
  if (!kIsWeb) {
    initGroupJoinLinkHandler();
  }
}
