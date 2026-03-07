import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
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
  String _sortColumn = 'pct'; // code, pct, price
  bool _sortAscending = false;

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
    final list = await _watchlist.getWatchlist(forceSync: true);
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

  void _openDetail(String symbol) {
    final name = _quotes[symbol]?.name ?? symbol;
    if (SymbolResolver.isUsStock(symbol)) {
      final sorted = _sortedSymbols;
      final idx = sorted.indexOf(symbol);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StockChartPage(
            symbol: symbol,
            name: name != symbol ? name : null,
            symbolList: sorted,
            symbolIndex: idx >= 0 ? idx : null,
          ),
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

  List<String> get _sortedSymbols {
    if (_symbols.isEmpty) return _symbols;
    final sorted = List<String>.from(_symbols);
    final q = _quotes;
    final asc = _sortAscending ? 1 : -1;
    sorted.sort((a, b) {
      int cmp = 0;
      switch (_sortColumn) {
        case 'code':
          cmp = a.compareTo(b);
          break;
        case 'pct':
          cmp = ((q[a]?.changePercent ?? 0) - (q[b]?.changePercent ?? 0))
              .sign
              .toInt();
          if (cmp == 0) cmp = a.compareTo(b);
          break;
        case 'price':
          cmp = ((q[a]?.price ?? 0) - (q[b]?.price ?? 0)).sign.toInt();
          if (cmp == 0) cmp = a.compareTo(b);
          break;
        default:
          cmp = ((q[a]?.changePercent ?? 0) - (q[b]?.changePercent ?? 0))
              .sign
              .toInt();
      }
      return cmp * asc;
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.watchlistTitle,
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: '排序',
            onSelected: (value) {
              setState(() {
                if (_sortColumn == value) {
                  _sortAscending = !_sortAscending;
                } else {
                  _sortColumn = value;
                  _sortAscending = value == 'code';
                }
              });
            },
            itemBuilder: (context) {
              final l10n = AppLocalizations.of(context)!;
              return [
                PopupMenuItem(
                    value: 'code',
                    child: Row(children: [
                      Text(l10n.marketCode),
                      if (_sortColumn == 'code')
                        Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Icon(
                                _sortAscending
                                    ? Icons.arrow_drop_up
                                    : Icons.arrow_drop_down,
                                size: 18,
                                color: _accent))
                    ])),
                PopupMenuItem(
                    value: 'pct',
                    child: Row(children: [
                      Text(l10n.marketChangePct),
                      if (_sortColumn == 'pct')
                        Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Icon(
                                _sortAscending
                                    ? Icons.arrow_drop_up
                                    : Icons.arrow_drop_down,
                                size: 18,
                                color: _accent))
                    ])),
                PopupMenuItem(
                    value: 'price',
                    child: Row(children: [
                      Text(l10n.marketLatestPrice),
                      if (_sortColumn == 'price')
                        Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Icon(
                                _sortAscending
                                    ? Icons.arrow_drop_up
                                    : Icons.arrow_drop_down,
                                size: 18,
                                color: _accent))
                    ])),
              ];
            },
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: AppLocalizations.of(context)!.watchlistAdd,
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
            Icon(Icons.star_border,
                size: 64, color: _muted.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.marketNoWatchlist,
              style: TextStyle(color: _muted, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.marketAddWatchlistHint,
              style: TextStyle(color: _muted, fontSize: 13),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _goSearch,
              icon: const Icon(Icons.search, size: 20),
              label: Text(AppLocalizations.of(context)!.marketGoSearch),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: _bg,
              ),
            ),
          ],
        ),
      );
    }
    final sorted = _sortedSymbols;
    return RefreshIndicator(
      onRefresh: _load,
      color: _accent,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: sorted.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: _muted.withValues(alpha: 0.2),
        ),
        itemBuilder: (context, index) {
          final symbol = sorted[index];
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
                              quote.changePercent.toStringAsFixed(2) +
                              '%'
                          : '—',
                      style: TextStyle(color: priceColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon:
                    Icon(Icons.remove_circle_outline, color: _muted, size: 22),
                tooltip: AppLocalizations.of(context)!.watchlistRemove,
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
