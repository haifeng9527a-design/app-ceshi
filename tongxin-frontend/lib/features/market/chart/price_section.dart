import 'package:flutter/material.dart';

import 'chart_theme.dart';

/// 价格区（与特斯拉图完全一致）：价格+涨跌同行，指标 今开/最高/最低/昨收 | 成交额/换手率/振幅
class PriceSection extends StatelessWidget {
  const PriceSection({
    super.key,
    required this.currentPrice,
    this.change,
    this.changePercent,
    this.prevClose,
    this.open,
    this.high,
    this.low,
    this.turnover,
    this.marketCap,
    this.turnoverRate,
    this.amplitude,
  });

  final double? currentPrice;
  final double? change;
  final double? changePercent;
  final double? prevClose;
  final double? open;
  final double? high;
  final double? low;
  final double? turnover;
  final double? marketCap;
  final double? turnoverRate;
  final double? amplitude;

  static String _formatLarge(double v) {
    if (v >= 1000000000) return '${(v / 1000000000).toStringAsFixed(1)}B';
    if (v >= 100000000) return '${(v / 100000000).toStringAsFixed(2)}亿';
    if (v >= 10000) return '${(v / 10000).toStringAsFixed(2)}万';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final isUp = change != null && change! >= 0;
    final color = change != null ? (isUp ? ChartTheme.up : ChartTheme.down) : ChartTheme.textPrimary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                currentPrice != null ? currentPrice!.toStringAsFixed(2) : '—',
                style: TextStyle(
                  color: color,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  fontFamily: ChartTheme.fontMono,
                  fontFeatures: const [ChartTheme.tabularFigures],
                ),
              ),
              if (change != null || changePercent != null) ...[
                const SizedBox(width: 10),
                Icon(
                  change != null && change! < 0 ? Icons.arrow_drop_down : Icons.arrow_drop_up,
                  color: color,
                  size: 20,
                ),
                Text(
                  '${change != null ? (change! >= 0 ? '+' : '') + change!.toStringAsFixed(2) : ''} '
                  '${changePercent != null ? '(${(changePercent! >= 0 ? '+' : '') + changePercent!.toStringAsFixed(2)}%)' : ''}',
                  style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFamily: ChartTheme.fontMono,
                    fontFeatures: const [ChartTheme.tabularFigures],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _metric('今开', open),
              _metric('最高', high, isUp: true),
              _metric('最低', low, isUp: false),
              _metric('昨收', prevClose),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _metric('总成交', turnover != null ? _formatLarge(turnover!) : (marketCap != null ? _formatLarge(marketCap!) : null)),
              _metric('换手率', turnoverRate != null ? '${turnoverRate!.toStringAsFixed(1)}%' : null),
              _metric('振幅', amplitude != null ? '${amplitude!.toStringAsFixed(1)}%' : null),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, dynamic value, {bool? isUp}) {
    final str = value is double ? value.toStringAsFixed(2) : (value is String ? value : '—');
    final valueColor = value == null || value == '—'
        ? ChartTheme.textSecondary
        : (isUp == true ? ChartTheme.up : isUp == false ? ChartTheme.down : ChartTheme.textPrimary);
    return Expanded(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: ChartTheme.textTertiary, fontSize: 13)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              str,
              style: TextStyle(
                color: valueColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                fontFamily: ChartTheme.fontMono,
                fontFeatures: const [ChartTheme.tabularFigures],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
