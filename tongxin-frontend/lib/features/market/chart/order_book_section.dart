import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../market_repository.dart';
import 'chart_theme.dart';

typedef _DepthRow = ({double? askPrice, int? askQty, double? bidPrice, int? bidQty});

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
  final List<(double, int)> bids;
  final List<(double, int)> asks;

  @override
  Widget build(BuildContext context) {
    final realRows = <_DepthRow>[];
    final maxDepth = [asks.length, bids.length].fold<int>(0, (a, b) => a > b ? a : b);
    for (var i = 0; i < maxDepth && i < 5; i++) {
      realRows.add((
        askPrice: i < asks.length ? asks[i].$1 : null,
        askQty: i < asks.length ? asks[i].$2 : null,
        bidPrice: i < bids.length ? bids[i].$1 : null,
        bidQty: i < bids.length ? bids[i].$2 : null,
      ));
    }

    final simulatedRows = realRows.isEmpty ? _buildSimulatedRows() : const <_DepthRow>[];
    final displayRows = realRows.isNotEmpty ? realRows : simulatedRows;
    final topAsk = asks.isNotEmpty
        ? asks.first
        : (displayRows.isNotEmpty && displayRows.first.askPrice != null
            ? (displayRows.first.askPrice!, displayRows.first.askQty ?? 0)
            : (quote?.ask != null ? (quote!.ask!, quote?.askSize ?? 0) : null));
    final topBid = bids.isNotEmpty
        ? bids.first
        : (displayRows.isNotEmpty && displayRows.first.bidPrice != null
            ? (displayRows.first.bidPrice!, displayRows.first.bidQty ?? 0)
            : (quote?.bid != null ? (quote!.bid!, quote?.bidSize ?? 0) : null));
    final spread =
        topAsk != null && topBid != null ? topAsk.$1 - topBid.$1 : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          Row(
            children: [
              Expanded(
                child: _summaryTile(
                  label: 'Ask',
                  price: topAsk?.$1,
                  qty: topAsk?.$2,
                  color: ChartTheme.down,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _summaryTile(
                  label: 'Bid',
                  price: topBid?.$1,
                  qty: topBid?.$2,
                  color: ChartTheme.up,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _summaryTile(
                  label: 'Spread',
                  price: spread,
                  qty: null,
                  color: ChartTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _headerRow(context),
          const SizedBox(height: 8),
          if (displayRows.isEmpty)
            _fallbackSnapshotCard()
          else
            ...displayRows.map(_depthRow),
        ],
      );
  }

  List<_DepthRow> _buildSimulatedRows() {
    final base = currentPrice ?? quote?.price ?? quote?.prevClose;
    if (base == null || base <= 0) return const <_DepthRow>[];

    final spreadStep = (base * 0.00012) > 0.2 ? (base * 0.00012) : 0.2;
    final ladderStep = (base * 0.00045) > 0.4 ? (base * 0.00045) : 0.4;
    final seed = ((base * 100).round().abs() % 17) + 7;
    final bias = (quote?.changePercent ?? 0) >= 0 ? 1 : -1;
    final rows = <_DepthRow>[];

    for (var i = 0; i < 5; i++) {
      final askPrice = _roundDepthPrice(base + spreadStep + ladderStep * i);
      final bidPrice = _roundDepthPrice(base - spreadStep - ladderStep * i);
      final askQty = (seed + i * 3 + (bias > 0 ? 1 : 4)) * 9;
      final bidQty = (seed + (4 - i) * 3 + (bias > 0 ? 4 : 1)) * 9;
      rows.add((
        askPrice: askPrice,
        askQty: askQty,
        bidPrice: bidPrice > 0 ? bidPrice : 0.0,
        bidQty: bidQty,
      ));
    }

    return rows;
  }

  double _roundDepthPrice(double value) {
    final decimals = value >= 1000 ? 2 : value >= 1 ? 4 : 6;
    return double.parse(value.toStringAsFixed(decimals));
  }

  Widget _fallbackSnapshotCard() {
    final q = quote;
    final prevClose = q?.prevClose ??
        ((q != null && q.change != 0) ? (q.price - q.change) : null);
    final turnover = (q != null && q.volume != null && q.volume! > 0 && q.price > 0)
        ? q.volume! * q.price
        : null;
    final items = <(String, String, Color?)>[
      ('最新价', currentPrice != null ? ChartTheme.formatPrice(currentPrice!) : '--', ChartTheme.textPrimary),
      ('今开', q?.open != null ? ChartTheme.formatPrice(q!.open!) : '--', null),
      ('昨收', prevClose != null ? ChartTheme.formatPrice(prevClose) : '--', null),
      ('最高', q?.high != null ? ChartTheme.formatPrice(q!.high!) : '--', ChartTheme.up),
      ('最低', q?.low != null ? ChartTheme.formatPrice(q!.low!) : '--', ChartTheme.down),
      ('成交量', _formatCompactVolume(q?.volume), null),
      ('成交额', _formatCompactTurnover(turnover), null),
      ('代码', (symbol == null || symbol!.trim().isEmpty) ? '--' : symbol!.trim().toUpperCase(), null),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ChartTheme.surface2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '实时行情摘要',
            style: const TextStyle(
              color: ChartTheme.textSecondary,
              fontSize: 13,
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
                    border: Border.all(color: ChartTheme.borderSubtle),
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

  Widget _summaryTile({
    required String label,
    required double? price,
    required int? qty,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: ChartTheme.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ChartTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: ChartTheme.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            price != null ? ChartTheme.formatPrice(price) : '--',
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFamily: ChartTheme.fontMono,
              fontFeatures: const [ChartTheme.tabularFigures],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            qty != null
                ? 'Qty $qty'
                : 'Realtime top level',
            style: const TextStyle(
              color: ChartTheme.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
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
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: ChartTheme.textTertiary,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _depthRow(_DepthRow row) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: ChartTheme.surface2.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(child: _priceCell(row.askPrice, ChartTheme.down)),
          Expanded(child: _qtyCell(row.askQty)),
          Expanded(child: _priceCell(row.bidPrice, ChartTheme.up)),
          Expanded(child: _qtyCell(row.bidQty)),
        ],
      ),
    );
  }

  Widget _priceCell(double? value, Color color) {
    return Text(
      value != null ? ChartTheme.formatPrice(value) : '--',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: value != null ? color : ChartTheme.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        fontFamily: ChartTheme.fontMono,
        fontFeatures: const [ChartTheme.tabularFigures],
      ),
    );
  }

  Widget _qtyCell(int? value) {
    return Text(
      value?.toString() ?? '--',
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: ChartTheme.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  String _formatCompactVolume(int? volume) {
    if (volume == null || volume <= 0) return '--';
    if (volume >= 100000000) return '${(volume / 100000000).toStringAsFixed(2)}亿';
    if (volume >= 10000) return '${(volume / 10000).toStringAsFixed(2)}万';
    return volume.toString();
  }

  String _formatCompactTurnover(double? turnover) {
    if (turnover == null || turnover <= 0) return '--';
    if (turnover >= 100000000) return '${(turnover / 100000000).toStringAsFixed(2)}亿';
    if (turnover >= 10000) return '${(turnover / 10000).toStringAsFixed(2)}万';
    return turnover.toStringAsFixed(0);
  }
}
