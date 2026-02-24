import 'package:flutter/material.dart';

import 'chart_theme.dart';

/// 悬浮在主图底部居中的周期切换条：1m/5m/15m/1h/1D（分时）或 5日/日K/周K/月K/年K（K线）
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

  static const List<String> intradayOptions = ['1m', '5m', '15m', '1h', '1D'];
  static const List<String> klineOptions = ['5day', 'day', 'week', 'month', 'year'];
  static const List<String> klineLabels = ['5日', '日K', '周K', '月K', '年K'];

  @override
  Widget build(BuildContext context) {
    if (isIntraday) {
      return _buildBar(
        options: intradayOptions,
        labels: intradayOptions,
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: ChartTheme.cardBackground.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(ChartTheme.radiusButton),
        border: Border.all(color: ChartTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(options.length, (i) {
          final id = options[i];
          final label = labels[i];
          final isSelected = selected == id;
          return Padding(
            padding: const EdgeInsets.only(left: 4, right: 4),
            child: Material(
              color: isSelected ? ChartTheme.accentGold : Colors.transparent,
              borderRadius: BorderRadius.circular(ChartTheme.radiusButton),
              child: InkWell(
                onTap: () => onTap(id),
                borderRadius: BorderRadius.circular(ChartTheme.radiusButton),
                child: Container(
                  decoration: isSelected
                      ? null
                      : BoxDecoration(
                          borderRadius: BorderRadius.circular(ChartTheme.radiusButton),
                          border: Border.all(color: ChartTheme.borderSubtle),
                        ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? ChartTheme.background : ChartTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
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
