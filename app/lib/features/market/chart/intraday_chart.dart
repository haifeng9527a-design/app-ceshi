import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../market_colors.dart';
import '../../trading/polygon_repository.dart';
import 'chart_theme.dart';

/// 分时图：绿色折线 + 半透明面积填充，左侧价格、右侧百分比，底部时间轴 + 成交量柱（15-20% 高度）
class IntradayChart extends StatelessWidget {
  const IntradayChart({
    super.key,
    required this.candles,
    this.prevClose,
    this.currentPrice,
    required this.chartHeight,
    this.timeAxisHeight = 22,
    this.volumeHeight = 0,
    this.periodLabel = '5m',
  });

  final List<ChartCandle> candles;
  final double? prevClose;
  final double? currentPrice;
  final double chartHeight;
  final double timeAxisHeight;
  /// 若 >0 则底部绘制成交量柱
  final double volumeHeight;
  final String periodLabel;

  static const double _candleWidth = 8.0;

  String _formatTime(double timeSec) {
    final d = DateTime.fromMillisecondsSinceEpoch((timeSec * 1000).toInt());
    if (periodLabel == '1D') {
      return '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    }
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (candles.isEmpty) {
      return Center(child: Text('暂无图表数据', style: TextStyle(color: ChartTheme.textSecondary)));
    }
    final closes = candles.map((c) => c.close).toList();
    double minY = closes.reduce((a, b) => a < b ? a : b);
    double maxY = closes.reduce((a, b) => a > b ? a : b);
    if (currentPrice != null) {
      if (currentPrice! < minY) minY = currentPrice!;
      if (currentPrice! > maxY) maxY = currentPrice!;
    }
    final range = (maxY - minY).clamp(0.01, double.infinity);
    final minYPlot = minY - range * 0.05;
    final maxYPlot = maxY + range * 0.05;
    final spots = <FlSpot>[];
    for (var i = 0; i < candles.length; i++) {
      spots.add(FlSpot(i.toDouble(), candles[i].close));
    }
    if (currentPrice != null) {
      spots.add(FlSpot(
          candles.isEmpty ? 0.0 : (candles.length - 1).toDouble() + 1,
          currentPrice!));
    }
    if (spots.isEmpty) return const SizedBox.shrink();

    final lastClose = candles.isNotEmpty ? candles.last.close : currentPrice;
    final firstOpen = candles.isNotEmpty ? candles.first.open : currentPrice;
    final lineColor = (lastClose ?? firstOpen ?? 0) >= (firstOpen ?? lastClose ?? 0)
        ? MarketColors.up
        : MarketColors.down;
    final maxX = spots.length <= 1 ? 1.0 : (spots.length - 1).toDouble();
    final contentWidth = (candles.length * _candleWidth).clamp(200.0, double.infinity);
    final axisStyle = TextStyle(color: ChartTheme.textSecondary, fontSize: 10, fontFamily: ChartTheme.fontMono);
    final basePrice = prevClose ?? candles.first.open;
    final totalBottom = timeAxisHeight + (volumeHeight > 0 ? volumeHeight : 0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 48,
            height: chartHeight + totalBottom,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(5, (i) {
                final v = maxYPlot - (maxYPlot - minYPlot) * i / 4;
                return Text(v.toStringAsFixed(2), style: axisStyle);
              }),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: SizedBox(
                width: contentWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: chartHeight,
                      child: LineChart(
                        LineChartData(
                          minX: 0,
                          maxX: maxX,
                          minY: minYPlot,
                          maxY: maxYPlot,
                          lineBarsData: [
                            LineChartBarData(
                              spots: spots,
                              isCurved: true,
                              color: lineColor,
                              barWidth: 2,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                color: lineColor.withValues(alpha: 0.25),
                              ),
                            ),
                          ],
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            getDrawingHorizontalLine: (_) => const FlLine(color: ChartTheme.gridLine, strokeWidth: 0.8),
                          ),
                          titlesData: const FlTitlesData(show: false),
                          borderData: FlBorderData(show: false),
                        ),
                        duration: const Duration(milliseconds: 150),
                      ),
                    ),
                    if (volumeHeight > 0 && candles.any((c) => (c.volume ?? 0) > 0))
                      SizedBox(
                        height: volumeHeight,
                        width: contentWidth,
                        child: CustomPaint(
                          size: Size(contentWidth, volumeHeight),
                          painter: _VolumeBarPainter(candles: candles),
                        ),
                      ),
                    SizedBox(
                      height: timeAxisHeight,
                      width: contentWidth,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(5, (i) {
                          final idx = i == 0 ? 0 : (i * (candles.length - 1) / 4).floor().clamp(0, candles.length - 1);
                          if (idx >= candles.length) return const SizedBox.shrink();
                          return Text(_formatTime(candles[idx].time), style: axisStyle);
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 44,
            height: chartHeight + totalBottom,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(5, (i) {
                final v = maxYPlot - (maxYPlot - minYPlot) * i / 4;
                final pct = basePrice > 0 ? (v - basePrice) / basePrice * 100 : 0.0;
                final pctStr = '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%';
                return Text(pctStr, style: axisStyle);
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _VolumeBarPainter extends CustomPainter {
  _VolumeBarPainter({required this.candles});
  final List<ChartCandle> candles;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    final vols = candles.map((c) => (c.volume ?? 0).toDouble()).toList();
    final maxV = vols.reduce((a, b) => a > b ? a : b);
    if (maxV <= 0) return;
    final n = candles.length;
    const pad = 2.0;
    final chartW = size.width - pad * 2;
    final chartH = size.height - pad * 2;
    final barW = (chartW / n).clamp(1.0, 8.0);
    final gap = (chartW - barW * n) / (n + 1);
    for (var i = 0; i < n; i++) {
      final v = vols[i];
      if (v <= 0) continue;
      final isUp = candles[i].close >= candles[i].open;
      final color = (isUp ? ChartTheme.up : ChartTheme.down).withValues(alpha: 0.5);
      final x = pad + gap + (gap + barW) * i;
      final h = (v / maxV * chartH).clamp(2.0, chartH);
      final y = pad + chartH - h;
      canvas.drawRect(
        Rect.fromLTWH(x, y, barW, h),
        Paint()..color = color..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VolumeBarPainter old) => old.candles != candles;
}
