import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'pc_dashboard_theme.dart';
import 'pc_sidebar.dart';
import 'pc_topbar.dart';

/// 桌面壳：侧栏 + 顶栏 + 内容区，宽度 >= 1100 时使用
class PcShell extends StatelessWidget {
  const PcShell({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.child,
    this.unreadCount = 0,
    this.userAvatarUrl,
    this.contentPadding,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;
  final int unreadCount;
  final String? userAvatarUrl;
  /// 内容区内边距；null 时使用 contentPadding。行情等页传 EdgeInsets.zero 可铺满全屏
  final EdgeInsets? contentPadding;

  static List<String> _pageTitles(BuildContext context) => [
    AppLocalizations.of(context)!.navRankings,
    AppLocalizations.of(context)!.navMarket,
    AppLocalizations.of(context)!.navWatchlist,
    AppLocalizations.of(context)!.navMessages,
    AppLocalizations.of(context)!.navFollow,
    AppLocalizations.of(context)!.navProfile,
  ];

  @override
  Widget build(BuildContext context) {
    final titles = _pageTitles(context);
    final title = currentIndex >= 0 && currentIndex < titles.length
        ? titles[currentIndex]
        : AppLocalizations.of(context)!.navRankings;
    return ColoredBox(
      color: PcDashboardTheme.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PcSidebar(
            currentIndex: currentIndex,
            onDestinationSelected: onDestinationSelected,
            messageUnreadCount: unreadCount,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PcTopbar(
                  pageTitle: title,
                  unreadCount: unreadCount,
                  userAvatarUrl: userAvatarUrl,
                ),
                Expanded(
                  child: Padding(
                    padding: contentPadding ?? const EdgeInsets.all(PcDashboardTheme.contentPadding),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
