import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'chart_theme.dart';

/// 底部数据带：固定高度单行，横向滚动，不随窗口变化溢出；每项 label(Meta 灰) + value(Body/Title)，右对齐、等宽数字
class ChartStatsBar extends StatelessWidget {
  const ChartStatsBar({
    super.key,
    required this.symbol,
    this.currentPrice,
    this.change,
    this.changePercent,
    this.open,
    this.high,
    this.low,
    this.close,
    this.prevClose,
    this.amplitude,
    this.avgPrice,
    this.volume,
    this.turnover,
    this.turnoverRate,
    this.dividendYieldPercent,
    this.peTtm,
    this.showSummaryLine = false,
  });

  final String symbol;
  final double? currentPrice;
  final double? change;
  final double? changePercent;
  final double? open;
  final double? high;
  final double? low;
  final double? close;
  final double? prevClose;
  final double? amplitude;
  final double? avgPrice;
  final int? volume;
  final double? turnover;
  /// 换手率（%），若为 null 且 [dividendYieldPercent] 非空则显示股息率
  final double? turnoverRate;
  /// 股息率（%），有值时在换手率位置显示「股息率」
  final double? dividendYieldPercent;
  final double? peTtm;
  final bool showSummaryLine;

  static String _formatVol(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toString();
  }

  String _formatTurnover(BuildContext context, double v) {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    if (v >= 100000000) return isZh ? '${(v / 100000000).toStringAsFixed(2)}亿' : '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 10000) return isZh ? '${(v / 10000).toStringAsFixed(2)}万' : '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final displayClose = currentPrice ?? close;
    final hasAny = displayClose != null || open != null || volume != null;
    if (!hasAny) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final items = <_StatItem>[
      _StatItem(l10n.chartStatsOpen, _v(open), null),
      _StatItem(l10n.chartStatsHigh, _v(high), true),
      _StatItem(l10n.chartStatsLow, _v(low), false),
      _StatItem(l10n.chartStatsClose, _v(displayClose), null, highlight: true),
      _StatItem(l10n.chartStatsPrevClose, _v(prevClose), null),
      _StatItem(l10n.chartStatsChange, _v(change, isChange: true), change != null ? (change! >= 0) : null),
      _StatItem(l10n.chartStatsChangePct, _v(changePercent, isPercent: true), changePercent != null ? (changePercent! >= 0) : null, highlight: true),
      _StatItem(l10n.chartStatsAmplitude, _v(amplitude, isPercent: true), null),
      _StatItem(l10n.chartStatsAvgPrice, _v(avgPrice), null),
      _StatItem(l10n.chartStatsVolume, volume != null ? _formatVol(volume!) : '—', null),
      _StatItem(l10n.chartStatsTurnover, turnover != null ? _formatTurnover(context, turnover!) : '—', null),
      _StatItem(
        dividendYieldPercent != null ? l10n.chartStatsDividendYield : l10n.chartStatsTurnoverRate,
        turnoverRate != null ? '${turnoverRate!.toStringAsFixed(2)}%' : (dividendYieldPercent != null ? '${dividendYieldPercent!.toStringAsFixed(2)}%' : '—'),
        null,
      ),
      _StatItem(l10n.chartStatsPeTtm, peTtm != null ? peTtm!.toStringAsFixed(2) : '—', null),
    ];

    return Container(
      width: double.infinity,
      height: 64,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: ChartTheme.pagePadding),
      decoration: const BoxDecoration(
        color: ChartTheme.cardBackground,
        border: Border(top: BorderSide(color: ChartTheme.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showSummaryLine)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '$symbol ${displayClose?.toStringAsFixed(2) ?? "—"} '
                  '${change != null ? (change! >= 0 ? "+" : "") + change!.toStringAsFixed(2) : ""} '
                  '${changePercent != null ? "(${changePercent! >= 0 ? "+" : ""}${changePercent!.toStringAsFixed(2)}%)" : ""}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: ChartTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: ChartTheme.fontMono,
                    fontFeatures: [ChartTheme.tabularFigures],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: items.map((e) => Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _statChip(e),
                  )).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(_StatItem item) {
    final color = item.value == '—'
        ? ChartTheme.textTertiary
        : (item.isUp == true ? ChartTheme.up : item.isUp == false ? ChartTheme.down : ChartTheme.textPrimary);
    return SizedBox(
      width: 68,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            item.label,
            style: const TextStyle(color: ChartTheme.textTertiary, fontSize: ChartTheme.fontSizeLabel),
          ),
          const SizedBox(height: 3),
          Text(
            item.value,
            style: TextStyle(
              color: color,
              fontSize: item.highlight ? ChartTheme.fontSizeKey : 12,
              fontWeight: FontWeight.w600,
              fontFamily: ChartTheme.fontMono,
              fontFeatures: const [ChartTheme.tabularFigures],
            ),
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _v(double? value, {bool isPercent = false, bool isChange = false}) {
    if (value == null) return '—';
    if (isPercent) return '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}%';
    if (isChange) return '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}';
    return value.toStringAsFixed(2);
  }
}

class _StatItem {
  _StatItem(this.label, this.value, this.isUp, {this.highlight = false});
  final String label;
  final String value;
  final bool? isUp;
  final bool highlight;
}
