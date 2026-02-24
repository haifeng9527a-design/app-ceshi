import 'package:flutter/material.dart';

import '../market_colors.dart';
import 'chart_theme.dart';

/// 底部统计条：开/高/低/收/昨收/涨跌/涨跌幅/振幅/均价/成交量/成交额/换手率/市盈率TTM
/// 固定在页面底部，标签弱化、数值加强，涨跌红绿；不重复顶栏的「代码+现价+涨跌」
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
  final double? turnoverRate;
  final double? peTtm;
  /// 是否显示顶栏已有的「代码 现价 涨跌 涨跌幅」摘要行（默认不显示，避免重复）
  final bool showSummaryLine;

  static String _formatVol(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toString();
  }

  static String _formatTurnover(double v) {
    if (v >= 100000000) return '${(v / 100000000).toStringAsFixed(2)}亿';
    if (v >= 10000) return '${(v / 10000).toStringAsFixed(2)}万';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final displayClose = currentPrice ?? close;
    final hasAny = displayClose != null || open != null || volume != null;
    if (!hasAny) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: const BoxDecoration(
        color: ChartTheme.cardBackground,
        border: Border(
          top: BorderSide(color: ChartTheme.border, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showSummaryLine)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '$symbol ${displayClose?.toStringAsFixed(2) ?? "—"} '
                  '${change != null ? (change! >= 0 ? "+" : "") + change!.toStringAsFixed(2) : ""} '
                  '${changePercent != null ? "(${changePercent! >= 0 ? "+" : ""}${changePercent!.toStringAsFixed(2)}%)" : ""}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: ChartTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: ChartTheme.fontMono,
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      _cell('开', open, null),
                      _cell('高', high, true),
                      _cell('低', low, false),
                      _cell('收', displayClose, null),
                      _cell('昨收', prevClose, null),
                      _cell('涨跌', change, change != null ? (change! >= 0) : null),
                      _cell('涨跌幅', changePercent, changePercent != null ? (changePercent! >= 0) : null, isPercent: true),
                      _cell('振幅', amplitude, null, isPercent: true),
                    ],
                  ),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      _cell('均价', avgPrice, null),
                      _cell('成交量', volume != null ? volume!.toDouble() : null, null, format: volume != null ? _formatVol(volume!) : null),
                      _cell('成交额', turnover, null, format: turnover != null ? _formatTurnover(turnover!) : null),
                      _cell('换手率', turnoverRate, null, isPercent: true),
                      _cell('市盈率TTM', peTtm, null),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(String label, double? value, bool? isUp, {bool isPercent = false, String? format}) {
    final color = value == null
        ? ChartTheme.textSecondary
        : (isUp == true ? ChartTheme.up : isUp == false ? ChartTheme.down : ChartTheme.textPrimary);
    final text = value == null
        ? '—'
        : (format ?? (isPercent ? '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}%' : value.toStringAsFixed(2)));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: ChartTheme.textSecondary, fontSize: 10)),
        const SizedBox(height: 2),
        Text(
          text,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: ChartTheme.fontMono),
        ),
      ],
    );
  }
}
