import 'package:flutter/material.dart';

import 'chart_theme.dart';
import 'indicators_panel.dart';

/// TradingView 风格时间周期工具栏（桌面端，36px 高）
///
/// 布局: 分时 5分 15分 30分 1小时 日K | 分隔线 | 指标▼ | ... | ☰侧栏
class TvTimeframeToolbar extends StatelessWidget {
  const TvTimeframeToolbar({
    super.key,
    required this.chartTabs,
    required this.selectedIndex,
    required this.onTabChanged,
    required this.overlayIndicator,
    required this.subChartIndicator,
    required this.onOverlayChanged,
    required this.onSubChartChanged,
    required this.isSidePanelOpen,
    required this.onToggleSidePanel,
  });

  final List<(String, String)> chartTabs;
  final int selectedIndex;
  final ValueChanged<int> onTabChanged;
  final String overlayIndicator;
  final String subChartIndicator;
  final ValueChanged<String> onOverlayChanged;
  final ValueChanged<String> onSubChartChanged;
  final bool isSidePanelOpen;
  final VoidCallback onToggleSidePanel;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: ChartTheme.tvTimeframeBarHeight,
      decoration: const BoxDecoration(
        color: ChartTheme.tvTopBarBg,
        border: Border(
          bottom: BorderSide(color: ChartTheme.tvBorder, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(width: 8),
          // 时间周期按钮
          ...List.generate(chartTabs.length, (i) {
            final selected = selectedIndex == i;
            return _timeframeBtn(chartTabs[i].$1, selected, () => onTabChanged(i));
          }),
          // 分隔线
          _divider(),
          // 指标按钮
          _indicatorDropdown(context),
          const Spacer(),
          // 侧栏切换
          _iconBtn(
            isSidePanelOpen
                ? Icons.view_sidebar_rounded
                : Icons.view_sidebar_outlined,
            onToggleSidePanel,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _timeframeBtn(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: selected
            ? const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: ChartTheme.tabUnderline, width: 2),
                ),
              )
            : null,
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? ChartTheme.tvTextActive : ChartTheme.tvTextMuted,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _indicatorDropdown(BuildContext context) {
    // 当前激活的指标简要标签
    final overlayLabel = overlayIndicator == 'none' ? '' : overlayIndicator.toUpperCase();
    final subLabel = subChartIndicator.toUpperCase();
    final activeLabel = [
      if (overlayLabel.isNotEmpty) overlayLabel,
      subLabel,
    ].join('·');

    return PopupMenuButton<String>(
      offset: const Offset(0, 36),
      color: ChartTheme.tvTopBarBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: ChartTheme.tvBorder),
      ),
      onSelected: (id) {
        // 查找这个 id 是 overlay 还是 subchart
        final item = IndicatorsPanel.items.where((e) => e.id == id).firstOrNull;
        if (item == null) return;
        if (item.isOverlay) {
          onOverlayChanged(id);
        } else {
          onSubChartChanged(id);
        }
      },
      itemBuilder: (_) {
        final items = <PopupMenuEntry<String>>[];
        // Overlay 指标
        items.add(const PopupMenuItem<String>(
          enabled: false,
          height: 28,
          child: Text('主图叠加', style: TextStyle(color: ChartTheme.tvTextMuted, fontSize: 11)),
        ));
        for (final e in IndicatorsPanel.items.where((e) => e.isOverlay)) {
          final selected = overlayIndicator == e.id;
          items.add(PopupMenuItem<String>(
            value: e.id,
            height: 32,
            child: Row(
              children: [
                if (selected)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.check, size: 14, color: ChartTheme.tabUnderline),
                  ),
                Text(
                  e.label,
                  style: TextStyle(
                    color: selected ? ChartTheme.tvTextActive : ChartTheme.tvTextMuted,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ));
        }
        items.add(const PopupMenuDivider(height: 1));
        // Sub-chart 指标
        items.add(const PopupMenuItem<String>(
          enabled: false,
          height: 28,
          child: Text('副图指标', style: TextStyle(color: ChartTheme.tvTextMuted, fontSize: 11)),
        ));
        for (final e in IndicatorsPanel.items.where((e) => !e.isOverlay)) {
          final selected = subChartIndicator == e.id;
          items.add(PopupMenuItem<String>(
            value: e.id,
            height: 32,
            child: Row(
              children: [
                if (selected)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.check, size: 14, color: ChartTheme.tabUnderline),
                  ),
                Text(
                  e.label,
                  style: TextStyle(
                    color: selected ? ChartTheme.tvTextActive : ChartTheme.tvTextMuted,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ));
        }
        return items;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bar_chart_rounded, size: 14, color: ChartTheme.tvTextMuted),
            const SizedBox(width: 4),
            Text(
              activeLabel,
              style: const TextStyle(
                color: ChartTheme.tvTextMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, size: 14, color: ChartTheme.tvTextMuted),
          ],
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: ChartTheme.tvBorder,
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Icon(icon, size: 18, color: ChartTheme.tvTextMuted),
      ),
    );
  }
}
