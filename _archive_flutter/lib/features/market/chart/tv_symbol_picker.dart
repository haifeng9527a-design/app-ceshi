import 'dart:async';

import 'package:flutter/material.dart';

import '../market_repository.dart';
import '../watchlist_repository.dart';
import 'chart_theme.dart';

/// 币种选择器弹窗（仿币安/TradingView 风格）
///
/// 搜索 + 自选 + 市场分类 + 币种列表
class TvSymbolPicker extends StatefulWidget {
  const TvSymbolPicker({
    super.key,
    required this.currentSymbol,
    required this.onSymbolSelected,
  });

  final String currentSymbol;
  final ValueChanged<MarketSearchResult> onSymbolSelected;

  /// 以 OverlayEntry / showDialog 方式弹出
  static Future<MarketSearchResult?> show(
    BuildContext context, {
    required String currentSymbol,
  }) {
    return showDialog<MarketSearchResult>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 40),
        child: _PickerBody(currentSymbol: currentSymbol),
      ),
    );
  }

  @override
  State<TvSymbolPicker> createState() => _TvSymbolPickerState();
}

class _TvSymbolPickerState extends State<TvSymbolPicker> {
  @override
  Widget build(BuildContext context) {
    return _PickerBody(
      currentSymbol: widget.currentSymbol,
      onSelected: widget.onSymbolSelected,
    );
  }
}

/// 选择器核心面板
class _PickerBody extends StatefulWidget {
  const _PickerBody({
    required this.currentSymbol,
    this.onSelected,
  });

  final String currentSymbol;
  final ValueChanged<MarketSearchResult>? onSelected;

  @override
  State<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends State<_PickerBody> {
  final _market = MarketRepository();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  List<MarketSearchResult> _results = [];
  List<String> _watchlist = [];
  bool _loading = false;
  String _query = '';
  Timer? _debounce;

  // Tab：0=自选，1=全部，2=加密，3=外汇，4=美股
  int _tabIndex = 1;
  static const _tabLabels = ['自选', '全部', '加密货币', '外汇', '美股', '指数'];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
    _loadWatchlist();
    // 默认加载热门
    _searchDefault();
  }

  Future<void> _loadWatchlist() async {
    final list = await WatchlistRepository.instance.getWatchlist();
    if (mounted) setState(() => _watchlist = list);
  }

  void _onQueryChanged() {
    final q = _controller.text.trim();
    _debounce?.cancel();
    if (q.isEmpty) {
      setState(() {
        _query = '';
      });
      _searchDefault();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (_query == q) return;
      _search(q);
    });
  }

  Future<void> _searchDefault() async {
    // 加载一些默认的热门币种
    setState(() => _loading = true);
    final list = await _market.searchSymbols('BTC');
    if (!mounted) return;
    setState(() {
      _results = list;
      _loading = false;
    });
  }

  Future<void> _search(String query) async {
    setState(() {
      _query = query;
      _loading = true;
    });
    final list = await _market.searchSymbols(query);
    if (!mounted) return;
    setState(() {
      _results = list;
      _loading = false;
    });
  }

  List<MarketSearchResult> get _filteredResults {
    if (_tabIndex == 0) {
      // 自选：从搜索结果中过滤出自选列表
      return _results
          .where((r) => _watchlist.contains(r.symbol.trim()))
          .toList();
    }
    if (_tabIndex == 2) {
      return _results
          .where(
              (r) => MarketRepository.isCryptoMarket(r.market))
          .toList();
    }
    if (_tabIndex == 3) {
      return _results
          .where((r) => MarketRepository.isForexMarket(r.market))
          .toList();
    }
    if (_tabIndex == 4) {
      return _results
          .where(
              (r) => r.market == 'stocks')
          .toList();
    }
    if (_tabIndex == 5) {
      return _results
          .where(
              (r) => r.market == 'indices')
          .toList();
    }
    return _results; // 全部
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
    final filtered = _filteredResults;
    return Container(
      width: 420,
      constraints: const BoxConstraints(maxHeight: 560),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ChartTheme.tvBorder),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 搜索框
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF131722),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: ChartTheme.tvBorder),
              ),
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(Icons.search, size: 16, color: ChartTheme.tvTextMuted),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      autofocus: true,
                      style: const TextStyle(
                        color: ChartTheme.tvTextActive,
                        fontSize: 13,
                      ),
                      decoration: const InputDecoration(
                        hintText: '搜索',
                        hintStyle: TextStyle(color: ChartTheme.tvTextMuted, fontSize: 13),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.only(bottom: 10),
                        isDense: true,
                      ),
                    ),
                  ),
                  if (_controller.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _controller.clear();
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.close, size: 14, color: ChartTheme.tvTextMuted),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Tab 栏
          SizedBox(
            height: 32,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _tabLabels.length,
              itemBuilder: (_, i) {
                final selected = _tabIndex == i;
                return GestureDetector(
                  onTap: () => setState(() => _tabIndex = i),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      border: selected
                          ? const Border(
                              bottom: BorderSide(
                                  color: ChartTheme.tabUnderline, width: 2),
                            )
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _tabLabels[i],
                      style: TextStyle(
                        color: selected
                            ? ChartTheme.tvTextActive
                            : ChartTheme.tvTextMuted,
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(height: 1, color: ChartTheme.tvBorder),
          // 列表头
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                const SizedBox(width: 28), // star 列
                const Expanded(
                  child: Text('交易对',
                      style: TextStyle(
                          color: ChartTheme.tvTextMuted, fontSize: 11)),
                ),
                const SizedBox(
                  width: 90,
                  child: Text('最新价',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: ChartTheme.tvTextMuted, fontSize: 11)),
                ),
                const SizedBox(
                  width: 70,
                  child: Text('类型',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: ChartTheme.tvTextMuted, fontSize: 11)),
                ),
              ],
            ),
          ),
          Container(height: 1, color: ChartTheme.tvBorder),
          // 币种列表
          Expanded(
            child: _loading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: ChartTheme.tvTextMuted),
                      ),
                    ),
                  )
                : filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _query.isEmpty ? '输入关键字搜索' : '未找到结果',
                            style: const TextStyle(
                              color: ChartTheme.tvTextMuted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: filtered.length,
                        itemExtent: 44,
                        itemBuilder: (_, i) => _buildRow(filtered[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(MarketSearchResult item) {
    final isSelected =
        item.symbol.toUpperCase() == widget.currentSymbol.toUpperCase();
    final inWl = _watchlist.contains(item.symbol.trim());
    return InkWell(
      onTap: () {
        if (widget.onSelected != null) {
          widget.onSelected!(item);
        } else {
          Navigator.of(context).pop(item);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: isSelected
            ? ChartTheme.tvBorder.withValues(alpha: 0.4)
            : null,
        child: Row(
          children: [
            // 自选星标
            GestureDetector(
              onTap: () async {
                final s = item.symbol.trim();
                if (inWl) {
                  await WatchlistRepository.instance.removeWatchlist(s);
                } else {
                  await WatchlistRepository.instance.addWatchlist(s);
                }
                _loadWatchlist();
              },
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 28,
                child: Icon(
                  inWl ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 16,
                  color: inWl ? ChartTheme.accentGold : ChartTheme.tvTextMuted,
                ),
              ),
            ),
            // 符号 + 名称
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.symbol,
                    style: TextStyle(
                      color: isSelected
                          ? ChartTheme.tabUnderline
                          : ChartTheme.tvTextActive,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: ChartTheme.fontMono,
                    ),
                  ),
                  if (item.name.isNotEmpty &&
                      item.name.toUpperCase() != item.symbol.toUpperCase())
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ChartTheme.tvTextMuted,
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            ),
            // 市场类型
            SizedBox(
              width: 70,
              child: Align(
                alignment: Alignment.centerRight,
                child: _marketBadge(item.market),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _marketBadge(String? market) {
    if (market == null || market.isEmpty) return const SizedBox.shrink();
    String label;
    Color color;
    switch (market.toLowerCase()) {
      case 'crypto':
        label = '加密';
        color = ChartTheme.accentGold;
      case 'fx':
      case 'forex':
        label = '外汇';
        color = ChartTheme.tabUnderline;
      case 'stocks':
        label = '美股';
        color = ChartTheme.up;
      case 'indices':
        label = '指数';
        color = const Color(0xFF9B59B6);
      default:
        label = market;
        color = ChartTheme.tvTextMuted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}
