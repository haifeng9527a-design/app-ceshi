import 'package:flutter/material.dart';

import 'chart_theme.dart';

/// 悬浮在主图底部居中的周期切换条：1分钟/两天/三天/四天（分时）或 5日/日K/周K/月K/年K（K线）
class TimeframeBar extends StatelessWidget {
  const TimeframeBar({
    super.key,
    required this.isIntraday,
    required this.intradayPeriod,
    required this.klineTimespan,
    required this.onIntradayPeriodChanged,
    required this.onKlineTimespanChanged,
  });

  final bool isIntraday;
  final String intradayPeriod;
  final String klineTimespan;
  final ValueChanged<String> onIntradayPeriodChanged;
  final ValueChanged<String> onKlineTimespanChanged;

  static const List<String> intradayOptions = ['1m', '2d', '3d', '4d'];
  static const List<String> intradayLabels = ['1天', '2天', '3天', '4天'];
  static const List<String> klineOptions = ['5day', 'day', 'week', 'month', 'year'];
  static const List<String> klineLabels = ['5日', '日K', '周K', '月K', '年K'];

  @override
  Widget build(BuildContext context) {
    if (isIntraday) {
      return _buildBar(
        options: intradayOptions,
        labels: intradayLabels,
        selected: intradayPeriod,
        onTap: onIntradayPeriodChanged,
      );
    }
    final selected = klineTimespan;
    return _buildBar(
      options: klineOptions,
      labels: klineLabels,
      selected: selected,
      onTap: onKlineTimespanChanged,
    );
  }

  Widget _buildBar({
    required List<String> options,
    required List<String> labels,
    required String selected,
    required ValueChanged<String> onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: ChartTheme.surface2,
        borderRadius: BorderRadius.circular(ChartTheme.radiusButton),
        border: Border.all(color: ChartTheme.borderSubtle, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(options.length, (i) {
          final id = options[i];
          final label = labels[i];
          final isSelected = selected == id;
          return Padding(
            padding: const EdgeInsets.only(left: 2, right: 2),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(ChartTheme.radiusButton - 2),
              child: InkWell(
                onTap: () => onTap(id),
                borderRadius: BorderRadius.circular(ChartTheme.radiusButton - 2),
                hoverColor: ChartTheme.surfaceHover,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? ChartTheme.up.withValues(alpha: 0.15) : null,
                    borderRadius: BorderRadius.circular(ChartTheme.radiusButton - 2),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? ChartTheme.up : ChartTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
