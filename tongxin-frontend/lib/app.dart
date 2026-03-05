import 'package:flutter/material.dart';

import 'core/finance_background.dart';
import 'core/last_online_service.dart';
import 'core/locale_provider.dart';
import 'core/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'features/home/home_page.dart';
import 'l10n/app_localizations.dart';
import 'ui/splash/tv_orbit_splash.dart';

Widget _splashNext() => const HomePage();

class TeacherHubApp extends StatefulWidget {
  const TeacherHubApp({super.key});

  @override
  State<TeacherHubApp> createState() => _TeacherHubAppState();
}

class _TeacherHubAppState extends State<TeacherHubApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!NotificationService.isInitialized) {
        NotificationService.init();
      }
      NotificationService.ensureTokenSavedOnResume();
      NotificationService.refreshBadgeFromUnread();
      // Android CallStyle 接听/拒绝后，检查待处理的来电数据
      NotificationService.checkPendingCallAnswerAndDecline();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // 退出 APP、切到后台、关闭聊天等场景：更新最后上线时间，供好友在聊天窗口查看
      LastOnlineService.updateLastOnlineNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleProvider.instance,
      builder: (_, __) {
        // 未手动设置时返回 null，让 Flutter 按系统语言自动匹配；
        // 手动设置后使用持久化的 locale 覆盖系统语言。
        final locale = LocaleProvider.instance.locale;
        return MaterialApp(
          title: 'Tongxin',
          debugShowCheckedModeBanner: false,
          navigatorKey: NotificationService.navigatorKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          routes: const {},
          theme: AppTheme.dark(),
      builder: (context, child) {
        if (child == null) {
          return const SizedBox.shrink();
        }
        return FinanceBackground(child: child);
      },
      home: TvOrbitSplash(nextBuilder: _splashNext),
        );
      },
    );
  }
}
