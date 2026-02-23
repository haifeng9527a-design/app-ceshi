import 'package:flutter/material.dart';

import 'generic_chart_page.dart';
import 'market_repository.dart';
import 'search_page.dart';
import 'stock_chart_page.dart';
import 'watchlist_repository.dart';

/// 自选列表：展示、移除、点击进详情，支持从搜索页添加
class WatchlistPage extends StatefulWidget {
  const WatchlistPage({super.key});

  @override
  State<WatchlistPage> createState() => _WatchlistPageState();
}

class _WatchlistPageState extends State<WatchlistPage> {
  final _watchlist = WatchlistRepository.instance;
  final _market = MarketRepository();

  List<String> _symbols = [];
  Map<String, MarketQuote?> _quotes = {};
  bool _loading = true;

  static const _bg = Color(0xFF0B0C0E);
  static const _surface = Color(0xFF111215);
  static const _accent = Color(0xFFD4AF37);
  static const _muted = Color(0xFF9CA3AF);
  static const _text = Color(0xFFE8D5A3);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _watchlist.getWatchlist();
    if (!mounted) return;
    setState(() {
      _symbols = list;
      _loading = false;
    });
    if (list.isEmpty) return;
    final quotes = await _market.getQuotes(list);
    if (!mounted) return;
    setState(() => _quotes = quotes);
  }

  bool _isUsStock(String symbol) {
    final s = symbol.trim().toUpperCase();
    if (s.isEmpty || s.length > 5) return false;
    if (s.contains('/')) return false;
    return s.runes.every((r) => r >= 0x41 && r <= 0x5A);
  }

  void _openDetail(String symbol) {
    final name = _quotes[symbol]?.name ?? symbol;
    if (_isUsStock(symbol)) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StockChartPage(symbol: symbol),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GenericChartPage(symbol: symbol, name: name),
        ),
      );
    }
  }

  Future<void> _remove(String symbol) async {
    await _watchlist.removeWatchlist(symbol);
    if (!mounted) return;
    setState(() {
      _symbols = _symbols.where((s) => s != symbol).toList();
      _quotes.remove(symbol);
    });
  }

  void _goSearch() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SearchPage(),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text(
          '自选',
          style: TextStyle(
            color: _text,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        backgroundColor: _bg,
        foregroundColor: _accent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: '添加',
            onPressed: _goSearch,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _accent),
      );
    }
    if (_symbols.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_border, size: 64, color: _muted.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              '暂无自选',
              style: TextStyle(color: _muted, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              '点击右上角 + 去搜索添加',
              style: TextStyle(color: _muted, fontSize: 13),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _goSearch,
              icon: const Icon(Icons.search, size: 20),
              label: const Text('去搜索'),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: _bg,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _accent,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _symbols.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: _muted.withValues(alpha: 0.2),
        ),
        itemBuilder: (context, index) {
          final symbol = _symbols[index];
          final quote = _quotes[symbol];
          return _buildRow(symbol, quote);
        },
      ),
    );
  }

  Widget _buildRow(String symbol, MarketQuote? quote) {
    final hasData = quote != null && !quote.hasError;
    final isUp = (quote?.changePercent ?? 0) >= 0;
    final priceColor = hasData
        ? (isUp ? const Color(0xFF22C55E) : const Color(0xFFEF4444))
        : _muted;
    return Material(
      color: _surface,
      child: InkWell(
        onTap: () => _openDetail(symbol),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      symbol,
                      style: const TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasData && quote!.price > 0
                          ? quote.price.toStringAsFixed(2)
                          : '—',
                      style: TextStyle(
                        color: priceColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      hasData && quote!.price > 0
                          ? (quote.changePercent >= 0 ? '+' : '') +
                              quote.changePercent.toStringAsFixed(2) + '%'
                          : '—',
                      style: TextStyle(color: priceColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.remove_circle_outline, color: _muted, size: 22),
                tooltip: '移除自选',
                onPressed: () => _remove(symbol),
              ),
              Icon(Icons.chevron_right, color: _muted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
