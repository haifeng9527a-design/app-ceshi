import 'package:flutter/material.dart';

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
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;
  final int unreadCount;
  final String? userAvatarUrl;

  static const List<String> _pageTitles = [
    '首页',
    '行情',
    '自选',
    '消息',
    '排行榜',
    '我的',
  ];

  @override
  Widget build(BuildContext context) {
    final title = currentIndex >= 0 && currentIndex < _pageTitles.length
        ? _pageTitles[currentIndex]
        : '首页';
    return ColoredBox(
      color: PcDashboardTheme.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PcSidebar(
            currentIndex: currentIndex,
            onDestinationSelected: onDestinationSelected,
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
                    padding: const EdgeInsets.all(PcDashboardTheme.contentPadding),
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
