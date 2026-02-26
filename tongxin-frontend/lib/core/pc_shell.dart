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
    this.contentPadding,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;
  final int unreadCount;
  final String? userAvatarUrl;
  /// 内容区内边距；null 时使用 contentPadding。行情等页传 EdgeInsets.zero 可铺满全屏
  final EdgeInsets? contentPadding;

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
