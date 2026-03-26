import 'package:flutter/material.dart';

import '../tv_theme.dart';
import '../../features/market/market_colors.dart';

/// 指数卡片：surface2 + 低对比 border，左侧名称/价格/涨跌，右侧迷你折线
class TvIndexCard extends StatelessWidget {
  const TvIndexCard({
    super.key,
    required this.label,
    required this.symbol,
    this.price,
    this.change,
    this.changePercent,
    this.hasError = false,
    this.isLoading = false,
    this.sparklinePoints,
    required this.onTap,
  });

  final String label;
  final String symbol;
  final double? price;
  final double? change;
  final double? changePercent;
  final bool hasError;
  final bool isLoading;
  /// 迷你图 Y 值（0~1 归一化），若为 null 则用 changePercent 生成简单趋势
  final List<double>? sparklinePoints;
  final VoidCallback onTap;

  static String formatPrice(double v) {
    if (v >= 10000) return v.toStringAsFixed(0);
    if (v >= 1) return v.toStringAsFixed(2);
    return v.toStringAsFixed(4);
  }

  @override
  Widget build(BuildContext context) {
    final isUp = (changePercent ?? 0) >= 0;
    final color = MarketColors.forUp(isUp);
    final points = sparklinePoints ?? _defaultSparkline(isUp);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TvTheme.radius),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: TvTheme.cardDecoration(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$label ($symbol)',
                      style: TvTheme.meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    if (isLoading)
                      const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: TvTheme.positive),
                      )
                    else
                      Text(
                        hasError || price == null || price! <= 0
                            ? '—'
                            : formatPrice(price!),
                        style: TvTheme.dataSmall.copyWith(
                          color: hasError ? TvTheme.textTertiary : TvTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    Text(
                      hasError
                          ? '—'
                          : '${change != null && change! >= 0 ? '+' : ''}${change?.toStringAsFixed(2) ?? '—'} '
                            '(${changePercent != null ? (changePercent! >= 0 ? '+' : '') + changePercent!.toStringAsFixed(2) : '—'}%)',
                      style: TvTheme.bodySecondary.copyWith(
                        color: hasError ? TvTheme.textTertiary : color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 64,
                height: 36,
                child: CustomPaint(
                  size: const Size(64, 36),
                  painter: _SparklinePainter(points: points, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<double> _defaultSparkline(bool isUp) {
    const n = 8;
    return List.generate(n, (i) {
      final t = i / (n - 1);
      return 0.2 + 0.6 * (isUp ? t : (1 - t)) + (i % 2 == 0 ? 0.03 : -0.03);
    });
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.points, required this.color});
  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    const bottomPad = 4.0;
    final h = size.height - bottomPad;
    final w = size.width;
    final min = points.reduce((a, b) => a < b ? a : b);
    final max = points.reduce((a, b) => a > b ? a : b);
    final range = (max - min).clamp(0.01, double.infinity);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = w * i / (points.length - 1);
      final y = bottomPad + h * (1 - (points[i] - min) / range);
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
