import 'package:flutter/material.dart';

import 'chart_theme.dart';

/// OHLC 信息叠加层（叠加在图表左上角内部）
///
/// 用 [IgnorePointer] 包裹，不拦截图表的手势。
/// 仿 TradingView 效果：半透明背景 + 单行/双行简洁数据。
class TvOhlcOverlay extends StatelessWidget {
  const TvOhlcOverlay({
    super.key,
    required this.symbol,
    required this.periodLabel,
    this.open,
    this.high,
    this.low,
    this.close,
    this.change,
    this.changePercent,
  });

  final String symbol;
  final String periodLabel;
  final double? open;
  final double? high;
  final double? low;
  final double? close;
  final double? change;
  final double? changePercent;

  @override
  Widget build(BuildContext context) {
    final tone = (change ?? 0) >= 0 ? ChartTheme.up : ChartTheme.down;
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xCC131722),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 第一行: 符号 · 周期 · 最新价格
            Text(
              '$symbol · $periodLabel · 最新价格',
              style: const TextStyle(
                color: ChartTheme.tvTextMuted,
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 2),
            // 第二行: 开=xx  高=xx  低=xx  收=xx  涨跌额(涨跌幅%)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ohlcItem('开', open, tone),
                _ohlcItem('高', high, tone),
                _ohlcItem('低', low, tone),
                _ohlcItem('收', close, tone),
                if (change != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '${change! >= 0 ? '+' : ''}${ChartTheme.formatPrice(change!)}',
                    style: TextStyle(
                      color: tone,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: ChartTheme.fontMono,
                      fontFeatures: const [ChartTheme.tabularFigures],
                    ),
                  ),
                ],
                if (changePercent != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    '(${changePercent! >= 0 ? '+' : ''}${changePercent!.toStringAsFixed(2)}%)',
                    style: TextStyle(
                      color: tone,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: ChartTheme.fontMono,
                      fontFeatures: const [ChartTheme.tabularFigures],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ohlcItem(String label, double? value, Color tone) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label=',
            style: const TextStyle(
              color: ChartTheme.tvTextMuted,
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
          Text(
            value != null && value > 0 ? ChartTheme.formatPrice(value) : '--',
            style: TextStyle(
              color: tone,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFamily: ChartTheme.fontMono,
              fontFeatures: const [ChartTheme.tabularFigures],
            ),
          ),
        ],
      ),
    );
  }
}
