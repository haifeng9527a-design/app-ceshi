import 'package:flutter/material.dart';

import 'chart_theme.dart';

/// 图表页顶部栏：返回 + 代码 | 分时/K线 分段控件 | 当前价 + 涨跌（克制色）
class ChartTopBar extends StatelessWidget {
  const ChartTopBar({
    super.key,
    required this.symbol,
    this.currentPrice,
    this.change,
    this.changePercent,
    required this.tabIndex,
    required this.onTabChanged,
    this.onBack,
  });

  final String symbol;
  final double? currentPrice;
  final double? change;
  final double? changePercent;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final hasPrice = currentPrice != null || changePercent != null;
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
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                    color: ChartTheme.textSecondary,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: ChartTheme.textSecondary,
                      padding: const EdgeInsets.all(8),
                      minimumSize: const Size(36, 36),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    symbol,
                    style: const TextStyle(
                      color: ChartTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: ChartTheme.fontMono,
                    ),
                  ),
                  const Spacer(),
                  _buildSegmentedTabs(),
                  const Spacer(),
                  if (hasPrice) _buildPriceBlock(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 分时 / K线：胶囊底 + 选中态
  Widget _buildSegmentedTabs() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: ChartTheme.surface2,
        borderRadius: BorderRadius.circular(ChartTheme.radiusButton),
        border: Border.all(color: ChartTheme.borderSubtle, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segmentChip('分时', 0),
          _segmentChip('K线', 1),
        ],
      ),
    );
  }

  Widget _segmentChip(String label, int index) {
    final selected = tabIndex == index;
    return Material(
      color: selected ? ChartTheme.up.withValues(alpha: 0.15) : Colors.transparent,
      borderRadius: BorderRadius.circular(ChartTheme.radiusButton - 2),
      child: InkWell(
        onTap: () => onTabChanged(index),
        borderRadius: BorderRadius.circular(ChartTheme.radiusButton - 2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? ChartTheme.up : ChartTheme.textSecondary,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPriceBlock() {
    final changeVal = change ?? (currentPrice != null && changePercent != null
        ? currentPrice! * (changePercent! / 100)
        : null);
    final up = changePercent != null && changePercent! >= 0;
    final color = up ? ChartTheme.up : ChartTheme.down;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (currentPrice != null)
          Text(
            ChartTheme.formatPrice(currentPrice!),
            style: const TextStyle(
              color: ChartTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFamily: ChartTheme.fontMono,
            ),
          ),
        if (changeVal != null) ...[
          const SizedBox(width: 8),
          Text(
            '${changeVal >= 0 ? '+' : ''}${ChartTheme.formatPrice(changeVal)}',
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: ChartTheme.fontMono),
          ),
        ],
        if (changePercent != null) ...[
          const SizedBox(width: 4),
          Text(
            '(${changePercent! >= 0 ? '+' : ''}${changePercent!.toStringAsFixed(2)}%)',
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: ChartTheme.fontMono),
          ),
        ],
      ],
    );
  }
}
