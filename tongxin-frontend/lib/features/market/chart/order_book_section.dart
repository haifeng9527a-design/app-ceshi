import 'package:flutter/material.dart';

import 'chart_theme.dart';

/// 盘口/委托簿（与特斯拉图完全一致）：卖价/数量/买价/数量，卖档红底渐变、买档绿底渐变
class OrderBookSection extends StatelessWidget {
  const OrderBookSection({
    super.key,
    required this.currentPrice,
    this.bids = const [],
    this.asks = const [],
  });

  final double? currentPrice;
  /// 买盘 [(price, qty), ...] 从高到低
  final List<(double, int)> bids;
  /// 卖盘 [(price, qty), ...] 从低到高
  final List<(double, int)> asks;

  @override
  Widget build(BuildContext context) {
    final price = currentPrice ?? 0.0;
    // 卖档：从高到低（最接近现价在上）；买档：从高到低
    final mockAsks = asks.isEmpty
        ? List.generate(5, (i) => (price + 0.05 + i * 0.05, 80 + i * 100))
        : asks.take(5).toList();
    final mockBids = bids.isEmpty
        ? List.generate(5, (i) => (price - 0.06 - i * 0.05, 100 + i * 120))
        : bids.take(5).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      decoration: const BoxDecoration(
        color: ChartTheme.cardBackground,
        border: Border(top: BorderSide(color: ChartTheme.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _headerRow(),
          const SizedBox(height: 8),
          for (var i = 0; i < 5; i++) _orderRow(
            sellPrice: i < mockAsks.length ? mockAsks[i].$1 : null,
            sellQty: i < mockAsks.length ? mockAsks[i].$2 : null,
            buyPrice: i < mockBids.length ? mockBids[i].$1 : null,
            buyQty: i < mockBids.length ? mockBids[i].$2 : null,
            rowIndex: i,
          ),
        ],
      ),
    );
  }

  Widget _headerRow() {
    return Row(
      children: [
        Expanded(child: _headerCell('卖一')),
        Expanded(child: _headerCell('数量')),
        Expanded(child: _headerCell('买一')),
        Expanded(child: _headerCell('数量')),
      ],
    );
  }

  Widget _headerCell(String text) {
    return Text(
      text,
      style: const TextStyle(color: ChartTheme.textTertiary, fontSize: 11),
      textAlign: TextAlign.center,
    );
  }

  Widget _orderRow({
    double? sellPrice,
    int? sellQty,
    double? buyPrice,
    int? buyQty,
    required int rowIndex,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    ChartTheme.down.withValues(alpha: 0.15),
                    ChartTheme.down.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                sellPrice != null ? sellPrice.toStringAsFixed(2) : '—',
                style: TextStyle(color: ChartTheme.down, fontSize: 12, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Expanded(
            child: Text(
              sellQty != null ? sellQty.toString() : '—',
              style: TextStyle(color: ChartTheme.textPrimary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    ChartTheme.up.withValues(alpha: 0.05),
                    ChartTheme.up.withValues(alpha: 0.15),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                buyPrice != null ? buyPrice.toStringAsFixed(2) : '—',
                style: TextStyle(color: ChartTheme.up, fontSize: 12, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Expanded(
            child: Text(
              buyQty != null ? buyQty.toString() : '—',
              style: TextStyle(color: ChartTheme.textPrimary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
