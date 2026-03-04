import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'chart_theme.dart';

/// 分时/1分 Tab 图标：竖条（K线柱）+ 下拉箭头，参考同花顺等行情 App
class _IntradayTabIcon extends StatelessWidget {
  const _IntradayTabIcon({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? ChartTheme.tabUnderline : ChartTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: ChartTheme.border, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 6,
            height: 14,
            decoration: BoxDecoration(
              color: color.withValues(alpha: selected ? 0.85 : 0.5),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down, size: 16, color: color),
        ],
      ),
    );
  }
}

/// 周K/月K/年K 下拉选项（需在 build 中通过 l10n 获取 label）
List<({String label, String interval})> _extendedKlineOptions(AppLocalizations l10n) => [
  (label: l10n.chartWeekK, interval: '1week'),
  (label: l10n.chartMonthK, interval: '1month'),
  (label: l10n.chartYearK, interval: '1year'),
];

/// 图表 Tab：股票详情 6 个（1分/5分/15分/30分/日K/周K），指数/外汇等 2 个（分时/日K）
/// 第一个 Tab（1分/分时）用图标替代文字；最后一个 Tab（周K）带下拉菜单，可选月K、年K
class ChartModeTabs extends StatelessWidget {
  const ChartModeTabs({
    super.key,
    required this.tabIndex,
    required this.onTabChanged,
    required this.isIntraday,
    required this.intradayPeriod,
    required this.klineTimespan,
    required this.onIntradayPeriodChanged,
    required this.onKlineTimespanChanged,
    this.labels,
    this.extendedKlineInterval = '1week',
    this.onExtendedKlineChanged,
  });

  final int tabIndex;
  final ValueChanged<int> onTabChanged;
  final bool isIntraday;
  final String intradayPeriod;
  final String klineTimespan;
  final ValueChanged<String> onIntradayPeriodChanged;
  final ValueChanged<String> onKlineTimespanChanged;
  /// 不传则用股票详情 6 个 Tab
  final List<String>? labels;
  /// 周K/月K/年K 当前选中项
  final String extendedKlineInterval;
  final ValueChanged<String>? onExtendedKlineChanged;

  static List<String> stockLabels(AppLocalizations l10n) => [
    l10n.chart1Min, l10n.chart5Min, l10n.chart15Min, l10n.chart30Min,
    l10n.chartDayK, l10n.chartWeekK,
  ];
  static List<String> genericLabels(AppLocalizations l10n) => [
    l10n.chartTimeshare, l10n.chartDayK,
  ];

  String _extendedLabel(AppLocalizations l10n) {
    final opts = _extendedKlineOptions(l10n);
    final opt = opts.firstWhere(
      (e) => e.interval == extendedKlineInterval,
      orElse: () => opts.first,
    );
    return opt.label;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tabLabels = labels ?? stockLabels(l10n);
    final hasExtendedDropdown = tabLabels.length >= 6 && onExtendedKlineChanged != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: ChartTheme.border, width: 0.5)),
      ),
      child: Row(
        children: List.generate(tabLabels.length, (i) {
          final selected = tabIndex == i;
          final useIcon = i == 0;
          final isExtendedTab = hasExtendedDropdown && i == tabLabels.length - 1;
          return Expanded(
            child: GestureDetector(
              onTap: () => onTabChanged(i),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: selected ? ChartTheme.tabUnderline : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: useIcon
                    ? Center(child: _IntradayTabIcon(selected: selected))
                    : isExtendedTab
                        ? Center(
                            child: PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              offset: const Offset(0, 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              onOpened: () => onTabChanged(i),
                              onSelected: (interval) => onExtendedKlineChanged!(interval),
                              itemBuilder: (context) => _extendedKlineOptions(l10n)
                                  .map((e) => PopupMenuItem<String>(
                                        value: e.interval,
                                        child: Text(e.label, style: const TextStyle(fontSize: 14)),
                                      ))
                                  .toList(),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _extendedLabel(l10n),
                                    style: TextStyle(
                                      color: selected ? ChartTheme.textPrimary : ChartTheme.textSecondary,
                                      fontSize: 14,
                                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                                    ),
                                  ),
                                  Icon(
                                    Icons.keyboard_arrow_down,
                                    size: 18,
                                    color: selected ? ChartTheme.textPrimary : ChartTheme.textSecondary,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Text(
                            tabLabels[i],
                            style: TextStyle(
                              color: selected ? ChartTheme.textPrimary : ChartTheme.textSecondary,
                              fontSize: 14,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
