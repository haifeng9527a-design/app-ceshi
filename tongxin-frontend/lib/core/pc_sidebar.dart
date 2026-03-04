import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'pc_dashboard_theme.dart';

/// 极简侧栏：仅图标，细选中条，无装饰
class PcSidebar extends StatefulWidget {
  const PcSidebar({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    this.messageUnreadCount = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  /// 消息未读数，在「消息」入口显示红点/数字角标（与顶栏通知一致）
  final int messageUnreadCount;

  static const double width = 72;

  static List<_NavItem> _items(BuildContext context) => [
    _NavItem(icon: Icons.dashboard_outlined, tooltip: AppLocalizations.of(context)!.navHome),
    _NavItem(icon: Icons.candlestick_chart_outlined, tooltip: AppLocalizations.of(context)!.navMarket),
    _NavItem(icon: Icons.star_outline, tooltip: AppLocalizations.of(context)!.navWatchlist),
    _NavItem(icon: Icons.chat_bubble_outline, tooltip: AppLocalizations.of(context)!.navMessages),
    _NavItem(icon: Icons.leaderboard_outlined, tooltip: AppLocalizations.of(context)!.navRankings),
    _NavItem(icon: Icons.person_outline, tooltip: AppLocalizations.of(context)!.navProfile),
  ];

  @override
  State<PcSidebar> createState() => _PcSidebarState();
}

class _PcSidebarState extends State<PcSidebar> {
  int _hovered = -1;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: PcDashboardTheme.surfaceVariant,
      child: SizedBox(
        width: PcSidebar.width,
        child: Column(
          children: [
            const SizedBox(height: 20),
            _AppMark(),
            const SizedBox(height: 28),
            ...List.generate(PcSidebar._items(context).length, (i) {
              final item = PcSidebar._items(context)[i];
              final selected = widget.currentIndex == i;
              final hover = _hovered == i;
              final badgeCount = (i == 3) ? widget.messageUnreadCount : 0;
              return _NavItemTile(
                icon: item.icon,
                tooltip: item.tooltip,
                selected: selected,
                hover: hover,
                badgeCount: badgeCount,
                onTap: () => widget.onDestinationSelected(i),
                onHover: (v) => setState(() => _hovered = v ? i : -1),
              );
            }),
            const Spacer(),
            _NavItemTile(
              icon: Icons.settings_outlined,
              tooltip: AppLocalizations.of(context)!.navSettings,
              selected: false,
              hover: _hovered == -2,
              onTap: () {},
              onHover: (v) => setState(() => _hovered = v ? -2 : -1),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _AppMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: PcDashboardTheme.accent.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(PcDashboardTheme.radiusSm),
      ),
      child: const Icon(Icons.insights_rounded, color: PcDashboardTheme.accent, size: 22),
    );
  }
}

class _NavItemTile extends StatelessWidget {
  const _NavItemTile({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.hover,
    this.badgeCount = 0,
    required this.onTap,
    required this.onHover,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final bool hover;
  final int badgeCount;
  final VoidCallback onTap;
  final void Function(bool) onHover;

  @override
  Widget build(BuildContext context) {
    Widget iconChild = Icon(
      icon,
      size: 22,
      color: selected
          ? PcDashboardTheme.accent
          : (hover ? PcDashboardTheme.text : PcDashboardTheme.textMuted),
    );
    if (badgeCount > 0) {
      iconChild = Badge(
        label: Text(
          badgeCount > 99 ? '99+' : '$badgeCount',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        backgroundColor: PcDashboardTheme.danger,
        child: iconChild,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: tooltip,
        preferBelow: false,
        child: MouseRegion(
          onEnter: (_) => onHover(true),
          onExit: (_) => onHover(false),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              mouseCursor: SystemMouseCursors.click,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  if (selected)
                    Positioned(
                      left: 0,
                      child: Container(
                        width: 3,
                        height: 28,
                        decoration: BoxDecoration(
                          color: PcDashboardTheme.accent,
                          borderRadius: BorderRadius.horizontal(right: Radius.circular(2)),
                        ),
                      ),
                    ),
                  Container(
                    width: 48,
                    height: 44,
                    margin: const EdgeInsets.only(left: 12),
                    decoration: BoxDecoration(
                      color: (selected || hover)
                          ? (selected
                              ? PcDashboardTheme.accentSubtle
                              : PcDashboardTheme.surfaceHover.withValues(alpha: 0.5))
                          : null,
                      borderRadius: BorderRadius.circular(PcDashboardTheme.radiusSm),
                    ),
                    alignment: Alignment.center,
                    child: iconChild,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({required this.icon, required this.tooltip});
  final IconData icon;
  final String tooltip;
}
