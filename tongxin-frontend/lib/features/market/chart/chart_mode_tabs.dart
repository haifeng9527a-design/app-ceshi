import 'package:flutter/material.dart';

import 'chart_theme.dart';
import 'timeframe_bar.dart';

/// 图表工具条：分时/K线 Segmented + 周期 pills + 指标/更多占位；按钮高 28~30，间距 8，hover 轻亮
class ChartModeTabs extends StatefulWidget {
  const ChartModeTabs({
    super.key,
    required this.tabIndex,
    required this.onTabChanged,
    required this.isIntraday,
    required this.intradayPeriod,
    required this.klineTimespan,
    required this.onIntradayPeriodChanged,
    required this.onKlineTimespanChanged,
  });

  final int tabIndex;
  final ValueChanged<int> onTabChanged;
  final bool isIntraday;
  final String intradayPeriod;
  final String klineTimespan;
  final ValueChanged<String> onIntradayPeriodChanged;
  final ValueChanged<String> onKlineTimespanChanged;

  @override
  State<ChartModeTabs> createState() => _ChartModeTabsState();
}

class _ChartModeTabsState extends State<ChartModeTabs> {
  static const _duration = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ChartTheme.pagePadding,
        vertical: ChartTheme.toolbarSpacing,
      ),
      child: Row(
        children: [
          _segmentRow(),
          const SizedBox(width: ChartTheme.toolbarSpacing),
          TimeframeBar(
            isIntraday: widget.isIntraday,
            intradayPeriod: widget.intradayPeriod,
            klineTimespan: widget.klineTimespan,
            onIntradayPeriodChanged: widget.onIntradayPeriodChanged,
            onKlineTimespanChanged: widget.onKlineTimespanChanged,
          ),
          const Spacer(),
          _pillButton('指标', onTap: () {}),
          const SizedBox(width: ChartTheme.toolbarSpacing),
          _pillButton('更多', onTap: () {}),
        ],
      ),
    );
  }

  /// 分时 / K线：与右侧周期按钮同一风格，独立圆角胶囊，选中为绿色底+绿字
  Widget _segmentRow() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: ChartTheme.surface2,
        borderRadius: BorderRadius.circular(ChartTheme.radiusButton),
        border: Border.all(color: ChartTheme.borderSubtle, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, right: 2),
            child: _segmentChip('分时', 0),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 2, right: 2),
            child: _segmentChip('K线', 1),
          ),
        ],
      ),
    );
  }

  Widget _segmentChip(String label, int index) {
    final selected = widget.tabIndex == index;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(ChartTheme.radiusButton - 2),
      child: InkWell(
        onTap: () => widget.onTabChanged(index),
        borderRadius: BorderRadius.circular(ChartTheme.radiusButton - 2),
        hoverColor: ChartTheme.surfaceHover,
        child: AnimatedContainer(
          duration: _duration,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? ChartTheme.up.withValues(alpha: 0.15) : null,
            borderRadius: BorderRadius.circular(ChartTheme.radiusButton - 2),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? ChartTheme.up : ChartTheme.textSecondary,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
            overflow: TextOverflow.visible,
          ),
        ),
      ),
    );
  }

  Widget _pillButton(String label, {required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        hoverColor: ChartTheme.surfaceHover,
        child: Container(
          height: ChartTheme.toolbarButtonHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              color: ChartTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
