import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'generic_chart_page.dart';
import 'market_repository.dart';
import 'stock_chart_page.dart';
import 'watchlist_repository.dart';

/// 行情搜索：输入股票或加密货币名称，展示 symbol / name / market，点击进入详情
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _market = MarketRepository();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  List<MarketSearchResult> _results = [];
  bool _loading = false;
  String _query = '';
  Timer? _debounce;

  static const _bg = Color(0xFF0B0C0E);
  static const _surface = Color(0xFF111215);
  static const _accent = Color(0xFFD4AF37);
  static const _muted = Color(0xFF9CA3AF);
  static const _text = Color(0xFFE8D5A3);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
  }

  void _onQueryChanged() {
    final q = _controller.text.trim();
    _debounce?.cancel();
    if (q.isEmpty) {
      setState(() {
        _query = '';
        _results = [];
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (_query == q) return;
      _search(q);
    });
  }

  Future<void> _search(String query) async {
    setState(() {
      _query = query;
      _loading = true;
      _results = [];
    });
    final list = await _market.searchSymbols(query);
    if (!mounted) return;
    setState(() {
      _results = list;
      _loading = false;
    });
  }

  /// 是否美股代码（与 MarketRepository 一致：无斜杠、1～5 位字母）
  bool _isUsStock(String symbol) {
    final s = symbol.trim().toUpperCase();
    if (s.isEmpty || s.length > 5) return false;
    if (s.contains('/')) return false;
    return s.runes.every((r) => r >= 0x41 && r <= 0x5A);
  }

  void _openDetail(MarketSearchResult item) {
    if (_isUsStock(item.symbol)) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StockChartPage(symbol: item.symbol, name: item.name),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GenericChartPage(
            symbol: item.symbol,
            name: item.name,
          ),
        ),
      );
    }
  }

  String _marketLabel(BuildContext context, String? market) {
    if (market == null || market.isEmpty) return '—';
    final l10n = AppLocalizations.of(context)!;
    switch (market.toLowerCase()) {
      case 'stocks':
        return l10n.searchUsStock;
      case 'crypto':
        return l10n.searchCrypto;
      case 'fx':
      case 'forex':
        return l10n.searchForex;
      case 'indices':
        return l10n.searchIndex;
      default:
        return market;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.commonSearch,
          style: TextStyle(
            color: _text,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        backgroundColor: _bg,
        foregroundColor: _accent,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.searchHint,
                hintStyle: TextStyle(color: _muted, fontSize: 14),
                prefixIcon: Icon(Icons.search, color: _muted, size: 22),
                filled: true,
                fillColor: _surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _accent.withValues(alpha: 0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _accent.withValues(alpha: 0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _accent, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
        ),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _accent),
      );
    }
    if (_query.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context)!.searchInputHint,
          style: TextStyle(color: _muted, fontSize: 14),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: _muted.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context)!.searchNotFound(_query),
              style: const TextStyle(color: _muted, fontSize: 14),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _results.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: _muted.withValues(alpha: 0.2),
      ),
      itemBuilder: (context, index) {
        final item = _results[index];
        return Material(
          color: _surface,
          child: InkWell(
            onTap: () => _openDetail(item),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.symbol,
                          style: const TextStyle(
                            color: _text,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.name,
                          style: TextStyle(
                            color: _muted,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _marketLabel(context, item.market),
                      style: const TextStyle(
                        color: _accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 22),
                    color: _accent,
                    tooltip: AppLocalizations.of(context)!.searchAddWatchlist,
                    onPressed: () async {
                      await WatchlistRepository.instance.addWatchlist(item.symbol);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(AppLocalizations.of(context)!.searchAddedToWatchlist(item.symbol)),
                          backgroundColor: _surface,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                  Icon(Icons.chevron_right, color: _muted, size: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
