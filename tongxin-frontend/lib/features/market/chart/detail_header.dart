import 'package:flutter/material.dart';

import 'chart_theme.dart';

/// 详情页顶栏（扁平）：左 返回+Symbol+交易所/名称(灰) | 右 当前价(大)+涨跌/幅(正负色)+状态点
class DetailHeader extends StatelessWidget {
  const DetailHeader({
    super.key,
    required this.symbol,
    this.exchangeOrName,
    this.currentPrice,
    this.change,
    this.changePercent,
    this.statusLabel,
    this.onBack,
  });

  final String symbol;
  final String? exchangeOrName;
  final double? currentPrice;
  final double? change;
  final double? changePercent;
  /// 如 "盘中" / "已收盘"，显示在价格右侧小点旁
  final String? statusLabel;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final hasPrice = currentPrice != null || changePercent != null;
    final isUp = changePercent != null && changePercent! >= 0;
    final color = changePercent != null ? (isUp ? ChartTheme.up : ChartTheme.down) : ChartTheme.textSecondary;
    final changeStr = change != null ? '${change! >= 0 ? '+' : ''}${change!.toStringAsFixed(2)}' : '';
    final percentStr = changePercent != null ? '${changePercent! >= 0 ? '+' : ''}${changePercent!.toStringAsFixed(2)}%' : '';

    return SizedBox(
      height: ChartTheme.topBarHeight,
      child: Material(
        color: ChartTheme.background,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: ChartTheme.border, width: 1)),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: ChartTheme.pagePadding),
              child: Row(
                children: [
                  _hoverIconButton(
                    icon: Icons.arrow_back_ios_new,
                    size: 18,
                    onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        symbol,
                        style: const TextStyle(
                          color: ChartTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: ChartTheme.fontMono,
                          fontFeatures: [ChartTheme.tabularFigures],
                        ),
                      ),
                      if (exchangeOrName != null && exchangeOrName!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          exchangeOrName!,
                          style: const TextStyle(
                            color: ChartTheme.textTertiary,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                  const Spacer(),
                  if (hasPrice) ...[
                    if (currentPrice != null)
                      Text(
                        _formatPrice(currentPrice!),
                        style: const TextStyle(
                          color: ChartTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          fontFamily: ChartTheme.fontMono,
                          fontFeatures: [ChartTheme.tabularFigures],
                        ),
                      ),
                    if (change != null || changePercent != null) ...[
                      const SizedBox(width: 12),
                      Text(
                        '$changeStr $percentStr',
                        style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFamily: ChartTheme.fontMono,
                          fontFeatures: const [ChartTheme.tabularFigures],
                        ),
                      ),
                    ],
                    if (statusLabel != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: ChartTheme.surface2,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: ChartTheme.borderSubtle),
                        ),
                        child: Text(
                          statusLabel!,
                          style: const TextStyle(color: ChartTheme.textTertiary, fontSize: 10),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hoverIconButton({
    required IconData icon,
    required double size,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(ChartTheme.radiusButton),
        hoverColor: ChartTheme.surfaceHover,
        focusColor: ChartTheme.surfaceHover,
        highlightColor: ChartTheme.surfaceHover,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: Icon(icon, size: size, color: ChartTheme.textSecondary),
          ),
        ),
      ),
    );
  }

  static String _formatPrice(double v) {
    if (v >= 10000) return v.toStringAsFixed(0);
    if (v >= 1) return v.toStringAsFixed(2);
    return v.toStringAsFixed(4);
  }
}
