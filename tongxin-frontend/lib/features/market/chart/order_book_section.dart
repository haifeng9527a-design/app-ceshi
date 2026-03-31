import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../market_repository.dart';
import 'chart_theme.dart';

/// 盘口/委托簿（与特斯拉图完全一致）：卖价/数量/买价/数量，卖档红底渐变、买档绿底渐变
class OrderBookSection extends StatelessWidget {
  const OrderBookSection({
    super.key,
    required this.currentPrice,
    this.quote,
    this.symbol,
    this.bids = const [],
    this.asks = const [],
  });

  final double? currentPrice;
  final MarketQuote? quote;
  final String? symbol;
  /// 买盘 [(price, qty), ...] 从高到低
  final List<(double, int)> bids;
  /// 卖盘 [(price, qty), ...] 从低到高
  final List<(double, int)> asks;

  @override
  Widget build(BuildContext context) {
    final topAsk = asks.isNotEmpty
        ? asks.first
        : (quote?.ask != null ? (quote!.ask!, quote?.askSize ?? 0) : null);
    final topBid = bids.isNotEmpty
        ? bids.first
        : (quote?.bid != null ? (quote!.bid!, quote?.bidSize ?? 0) : null);
    final spread = (topAsk != null && topBid != null)
        ? topAsk.$1 - topBid.$1
        : null;
    final rows = <({double? sellPrice, int? sellQty, double? buyPrice, int? buyQty})>[];
    final maxDepth = [asks.length, bids.length].reduce((a, b) => a > b ? a : b);
    for (var i = 0; i < maxDepth && i < 5; i++) {
      rows.add((
        sellPrice: i < asks.length ? asks[i].$1 : null,
        sellQty: i < asks.length ? asks[i].$2 : null,
        buyPrice: i < bids.length ? bids[i].$1 : null,
        buyQty: i < bids.length ? bids[i].$2 : null,
      ));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      decoration: const BoxDecoration(
        color: ChartTheme.cardBackground,
        border: Border(top: BorderSide(color: ChartTheme.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _headerRow(context),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _summaryCard(
                  label: '卖一',
                  price: topAsk?.$1,
                  qty: topAsk?.$2,
                  valueColor: ChartTheme.down,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _summaryCard(
                  label: '买一',
                  price: topBid?.$1,
                  qty: topBid?.$2,
                  valueColor: ChartTheme.up,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _spreadCard(spread),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            _fallbackSnapshotCard()
          else
            ...rows.asMap().entries.map((entry) => _orderRow(
                  sellPrice: entry.value.sellPrice,
                  sellQty: entry.value.sellQty,
                  buyPrice: entry.value.buyPrice,
                  buyQty: entry.value.buyQty,
                  rowIndex: entry.key,
                )),
        ],
      ),
    );
  }

  Widget _fallbackSnapshotCard() {
    final q = quote;
    final prevClose = q?.prevClose ??
        ((q != null && q.change != 0) ? (q.price - q.change) : null);
    final turnover = (q != null &&
            q.volume != null &&
            q.volume! > 0 &&
            q.price > 0)
        ? q.volume! * q.price
        : null;
    final items = <(String, String, Color?)>[
      ('最新价', currentPrice != null ? ChartTheme.formatPrice(currentPrice!) : '—', ChartTheme.textPrimary),
      ('今开', q?.open != null ? ChartTheme.formatPrice(q!.open!) : '—', null),
      ('昨收', prevClose != null ? ChartTheme.formatPrice(prevClose) : '—', null),
      ('最高', q?.high != null ? ChartTheme.formatPrice(q!.high!) : '—', ChartTheme.up),
      ('最低', q?.low != null ? ChartTheme.formatPrice(q!.low!) : '—', ChartTheme.down),
      ('成交量', _formatCompactVolume(q?.volume), null),
      ('成交额', _formatCompactTurnover(turnover), null),
      ('代码', (symbol == null || symbol!.trim().isEmpty) ? '—' : symbol!.trim().toUpperCase(), null),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: ChartTheme.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ChartTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '当前数据源暂无盘口深度，已回退显示可获取的实时快照。',
            style: TextStyle(
              color: ChartTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: items.map((item) {
              return SizedBox(
                width: 148,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: ChartTheme.cardBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ChartTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.$1,
                        style: const TextStyle(
                          color: ChartTheme.textTertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.$2,
                        style: TextStyle(
                          color: item.$3 ?? ChartTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard({
    required String label,
    required double? price,
    required int? qty,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: ChartTheme.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ChartTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: ChartTheme.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            price != null ? ChartTheme.formatPrice(price) : '—',
            style: TextStyle(
              color: valueColor,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            qty != null ? '数量 $qty' : '数量 —',
            style: const TextStyle(
              color: ChartTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _spreadCard(double? spread) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: ChartTheme.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ChartTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '价差',
            style: TextStyle(
              color: ChartTheme.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            spread != null ? ChartTheme.formatPrice(spread) : '—',
            style: const TextStyle(
              color: ChartTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '实时买一卖一',
            style: TextStyle(
              color: ChartTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  String _formatCompactVolume(int? volume) {
    if (volume == null || volume <= 0) return '—';
    if (volume >= 100000000) return '${(volume / 100000000).toStringAsFixed(2)}亿';
    if (volume >= 10000) return '${(volume / 10000).toStringAsFixed(2)}万';
    return volume.toString();
  }

  String _formatCompactTurnover(double? turnover) {
    if (turnover == null || turnover <= 0) return '—';
    if (turnover >= 100000000) return '${(turnover / 100000000).toStringAsFixed(2)}亿';
    if (turnover >= 10000) return '${(turnover / 10000).toStringAsFixed(2)}万';
    return turnover.toStringAsFixed(0);
  }

  Widget _headerRow(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(child: _headerCell(l10n.chartOrderBookSell)),
        Expanded(child: _headerCell(l10n.chartOrderBookQty)),
        Expanded(child: _headerCell(l10n.chartOrderBookBuy)),
        Expanded(child: _headerCell(l10n.chartOrderBookQty)),
      ],
    );
  }

  Widget _headerCell(String text) {
    return Text(
      text,
      style: const TextStyle(color: ChartTheme.textTertiary, fontSize: 12, fontWeight: FontWeight.w600),
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
              padding: const EdgeInsets.symmetric(vertical: 6),
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
                sellPrice != null ? ChartTheme.formatPrice(sellPrice) : '—',
                style: TextStyle(color: ChartTheme.down, fontSize: 14, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Expanded(
            child: Text(
              sellQty != null ? sellQty.toString() : '—',
              style: TextStyle(color: ChartTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
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
                buyPrice != null ? ChartTheme.formatPrice(buyPrice) : '—',
                style: TextStyle(color: ChartTheme.up, fontSize: 14, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Expanded(
            child: Text(
              buyQty != null ? buyQty.toString() : '—',
              style: TextStyle(color: ChartTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
