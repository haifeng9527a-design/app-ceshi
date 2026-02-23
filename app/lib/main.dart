import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app.dart';
import 'features/admin/admin_login_page.dart';
import 'features/messages/group_join_link_handler.dart';
import 'core/finance_background.dart';
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
      debugPrint('dotenv: POLYGON_API_KEY ${polygonKey != null && polygonKey.isNotEmpty ? "loaded" : "empty/missing"}');
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
  if (kIsWeb && !FirebaseBootstrap.isReady) {
    runApp(const AdminWebApp());
    return;
  }
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await NotificationService.init();
  }
  runApp(const TeacherHubApp());
  if (!kIsWeb) {
    initGroupJoinLinkHandler();
  }
}

class AdminWebApp extends StatelessWidget {
  const AdminWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '后台管理',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFD4AF37),
          secondary: Color(0xFF8A6D1D),
          surface: Color(0xFF111215),
        ),
        scaffoldBackgroundColor: const Color(0xFF0B0C0E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0B0C0E),
          foregroundColor: Color(0xFFD4AF37),
          elevation: 0,
        ),
        useMaterial3: true,
      ),
      builder: (context, child) {
        if (child == null) {
          return const SizedBox.shrink();
        }
        return FinanceBackground(child: child);
      },
      home: const AdminLoginPage(),
    );
  }
}
