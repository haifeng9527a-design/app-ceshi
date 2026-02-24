import 'package:flutter/material.dart';

import '../market_colors.dart'; // same feature
import 'chart_theme.dart';

/// 图表页顶部栏：返回 + 代码 | 分时/K线 Tab | 当前价 + 涨跌额 + 涨跌幅
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
            border: Border(
              bottom: BorderSide(color: ChartTheme.border, width: 1),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    color: ChartTheme.textSecondary,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: ChartTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    symbol,
                    style: const TextStyle(
                      color: ChartTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      fontFamily: ChartTheme.fontMono,
                    ),
                  ),
                  const Spacer(),
                  _buildTabs(context),
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

  Widget _buildTabs(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _tabChip('分时', 0),
        _tabChip('K线', 1),
      ],
    );
  }

  Widget _tabChip(String label, int index) {
    final selected = tabIndex == index;
    return GestureDetector(
      onTap: () => onTabChanged(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? ChartTheme.textPrimary : ChartTheme.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              height: 2,
              width: 32,
              decoration: BoxDecoration(
                color: selected ? ChartTheme.accentGold : Colors.transparent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceBlock() {
    final changeVal = change ?? (currentPrice != null && changePercent != null
        ? currentPrice! * (changePercent! / 100)
        : null);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (currentPrice != null)
          Text(
            currentPrice!.toStringAsFixed(2),
            style: const TextStyle(
              color: ChartTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFamily: ChartTheme.fontMono,
            ),
          ),
        if (changeVal != null) ...[
          const SizedBox(width: 8),
          Text(
            '${changeVal >= 0 ? '+' : ''}${changeVal.toStringAsFixed(2)}',
            style: TextStyle(
              color: MarketColors.forChangePercent(changeVal),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFamily: ChartTheme.fontMono,
            ),
          ),
        ],
        if (changePercent != null) ...[
          const SizedBox(width: 4),
          Text(
            '(${changePercent! >= 0 ? '+' : ''}${changePercent!.toStringAsFixed(2)}%)',
            style: TextStyle(
              color: MarketColors.forChangePercent(changePercent!),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFamily: ChartTheme.fontMono,
            ),
          ),
        ],
      ],
    );
  }
}
