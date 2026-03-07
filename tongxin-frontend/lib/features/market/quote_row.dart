import 'package:flutter/material.dart';

import 'market_colors.dart';

/// 统一行情行：美股热门/自选、外汇、加密、首页自选预览
/// 左：symbol（粗）+ name（灰小字可选） 右：price（粗）+ change/changePercent（红绿） 可选：mini sparkline
class QuoteRow extends StatelessWidget {
  const QuoteRow({
    super.key,
    required this.symbol,
    required this.price,
    required this.change,
    required this.changePercent,
    required this.onTap,
    this.name,
    this.showSparkline = false,
    this.hasError = false,
    this.isLoading = false,
  });

  final String symbol;
  final String? name;
  final double price;
  final double change;
  final double changePercent;
  final VoidCallback onTap;
  final bool showSparkline;
  final bool hasError;

  /// true = 报价尚未拉取（显示骨架占位），false = 已有结果（有值或失败）
  final bool isLoading;

  static const double _rowPaddingVertical = 12;
  static const double _rowPaddingHorizontal = 12;
  static const Color _bgColor = Color(0xFF111215);
  static const Color _dividerColor = Color(0xFF1F1F23);
  static const double _dividerWidth = 0.6;

  @override
  Widget build(BuildContext context) {
    final color = MarketColors.forChangePercent(changePercent);
    final changeStr = (change >= 0 ? '+' : '') + change.toStringAsFixed(2);
    final pctStr = (changePercent >= 0 ? '+' : '') +
        changePercent.toStringAsFixed(2) +
        '%';
    return Material(
      color: _bgColor,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              vertical: _rowPaddingVertical, horizontal: _rowPaddingHorizontal),
          decoration: const BoxDecoration(
            border: Border(
                bottom: BorderSide(color: _dividerColor, width: _dividerWidth)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      symbol,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (name != null && name!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        name!,
                        style: const TextStyle(
                            color: Color(0xFF9CA3AF), fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isLoading)
                const Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _PriceSkeleton(),
                  ),
                )
              else if (hasError)
                const Expanded(
                  child: Text(
                    '—',
                    style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                    textAlign: TextAlign.end,
                  ),
                )
              else ...[
                Text(
                  price > 0 ? _formatPrice(price) : '—',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 56,
                  child: Text(
                    changeStr,
                    style: TextStyle(color: color, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 52,
                  child: Text(
                    pctStr,
                    style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (showSparkline) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 48,
                    height: 24,
                    child: _MiniSparkline(percentChange: changePercent),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _formatPrice(double v) {
    if (v >= 10000) return v.toStringAsFixed(0);
    if (v >= 100) return v.toStringAsFixed(2);
    return v.toStringAsFixed(4);
  }
}

/// 报价尚未加载时的骨架占位（灰色矩形）
class _PriceSkeleton extends StatelessWidget {
  const _PriceSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: 60,
          height: 13,
          decoration: BoxDecoration(
            color: const Color(0xFF2A2C32),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 5),
        Container(
          width: 44,
          height: 11,
          decoration: BoxDecoration(
            color: const Color(0xFF2A2C32),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }
}

class _MiniSparkline extends StatelessWidget {
  const _MiniSparkline({required this.percentChange});
  final double percentChange;

  @override
  Widget build(BuildContext context) {
    final isUp = percentChange >= 0;
    final color = MarketColors.forChangePercent(percentChange);
    const pointCount = 8;
    final points = List<double>.generate(pointCount, (i) {
      final t = i / (pointCount - 1);
      final trend = isUp ? t : (1 - t);
      return 0.2 + 0.6 * trend + (i % 2 == 0 ? 0.05 : -0.05);
    });
    return CustomPaint(
      size: const Size(double.infinity, 28),
      painter: _SparklinePainter(points: points, color: color),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.points, required this.color});
  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final min = points.reduce((a, b) => a < b ? a : b);
    final max = points.reduce((a, b) => a > b ? a : b);
    final range = (max - min).clamp(0.01, double.infinity);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = size.width * i / (points.length - 1);
      final y = size.height * (1 - (points[i] - min) / range);
      if (i == 0)
        path.moveTo(x, y);
      else
        path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
