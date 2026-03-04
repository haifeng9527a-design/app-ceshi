import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/finance_background.dart';
import 'core/supabase_bootstrap.dart';
import 'l10n/admin_strings.dart';
import 'pages/admin_login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('dotenv load failed: $e');
  }
  await SupabaseBootstrap.init();
  runApp(const TongxinAdminApp());
}

class TongxinAdminApp extends StatelessWidget {
  const TongxinAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AdminStrings.adminTitle,
      debugShowCheckedModeBanner: false,
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
        if (child == null) return const SizedBox.shrink();
        return FinanceBackground(child: child);
      },
      home: const AdminLoginPage(),
    );
  }
}
