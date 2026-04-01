import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/app_webview_page.dart';
import '../../../l10n/app_localizations.dart';
import '../market_repository.dart';
import 'chart_theme.dart';
import 'indicators_section.dart';
import 'order_book_section.dart';

/// 底部 Tab（一比一参考）：盘口 | 指标 | 资金 | 新闻 | 公告
class BottomDetailTabs extends StatefulWidget {
  const BottomDetailTabs({
    super.key,
    required this.currentPrice,
    this.quote,
    this.symbol,
    this.overlayIndicator = 'none',
    this.subChartIndicator = 'vol',
    this.showPrevCloseLine = true,
    this.onOverlayChanged,
    this.onSubChartChanged,
    this.onShowPrevCloseLineChanged,
    this.klineCandles = const [],
  });

  final double? currentPrice;
  final MarketQuote? quote;
  /// 股票代码，用于盘口 Tab 定时拉取买一/卖一
  final String? symbol;
  final String overlayIndicator;
  final String subChartIndicator;
  final bool showPrevCloseLine;
  final ValueChanged<String>? onOverlayChanged;
  final ValueChanged<String>? onSubChartChanged;
  final ValueChanged<bool>? onShowPrevCloseLineChanged;
  final List<ChartCandle> klineCandles;

  @override
  State<BottomDetailTabs> createState() => _BottomDetailTabsState();
}

class _BottomDetailTabsState extends State<BottomDetailTabs> {
  int _index = 0;
  Timer? _orderBookTimer;
  bool _orderBookPollingScheduled = false;
  List<(double, int)> _bids = [];
  List<(double, int)> _asks = [];
  final _market = MarketRepository();
  bool _loadingCapital = false;
  bool _loadingNews = false;
  bool _loadingAnnouncements = false;
  Map<String, dynamic>? _keyRatios;
  List<Map<String, dynamic>> _dividends = const [];
  List<Map<String, dynamic>> _splits = const [];
  List<MarketNewsItem> _news = const [];
  List<MarketNewsItem> _announcements = const [];

  @override
  void initState() {
    super.initState();
    _loadCapital();
    _loadTickerNews();
    _loadAnnouncements();
  }

  List<String> _labels(BuildContext context) => [
    AppLocalizations.of(context)!.chartTabOrderBook,
    AppLocalizations.of(context)!.chartTabIndicator,
    AppLocalizations.of(context)!.chartTabCapital,
    AppLocalizations.of(context)!.chartTabNews,
    AppLocalizations.of(context)!.chartTabAnnouncement,
  ];

  void _startOrderBookPolling() {
    _orderBookTimer?.cancel();
    _orderBookPollingScheduled = true;
    final sym = widget.symbol?.trim();
    if (sym == null || sym.isEmpty) return;
    void poll() async {
      try {
        final q = await _market.getQuote(sym, realtime: true);
        if (!mounted || _index != 0) return;
        final bids = <(double, int)>[];
        final asks = <(double, int)>[];
        if (q.bid != null && q.bid! > 0) {
          bids.add((q.bid!, q.bidSize ?? 0));
        }
        if (q.ask != null && q.ask! > 0) {
          asks.add((q.ask!, q.askSize ?? 0));
        }
        if (mounted && _index == 0) {
          setState(() {
            _bids = bids;
            _asks = asks;
          });
        }
      } catch (_) {}
    }
    poll();
    _orderBookTimer = Timer.periodic(const Duration(seconds: 1), (_) => poll());
  }

  void _stopOrderBookPolling() {
    _orderBookTimer?.cancel();
    _orderBookTimer = null;
    _orderBookPollingScheduled = false;
  }

  @override
  void didUpdateWidget(BottomDetailTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.symbol != widget.symbol) {
      _stopOrderBookPolling();
      _bids = [];
      _asks = [];
      if (_index == 0 && widget.symbol != null) _startOrderBookPolling();
      _loadCapital();
      _loadTickerNews();
      _loadAnnouncements();
    }
  }

  @override
  void dispose() {
    _stopOrderBookPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = _labels(context);
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: ChartTheme.border, width: 0.5)),
          ),
          child: Row(
            children: List.generate(labels.length, (i) {
              final selected = _index == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    final wasOrderBook = _index == 0;
                    setState(() => _index = i);
                    if (i == 0 && !wasOrderBook) {
                      _startOrderBookPolling();
                    } else if (i != 0) {
                      _stopOrderBookPolling();
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: selected ? ChartTheme.tabUnderline : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        color: selected ? ChartTheme.textPrimary : ChartTheme.textSecondary,
                        fontSize: 15,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 180),
                child: _buildContent(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    switch (_index) {
      case 0:
        if (widget.symbol != null && !_orderBookPollingScheduled && _orderBookTimer == null) {
          _orderBookPollingScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _index == 0) _startOrderBookPolling();
          });
        }
        return OrderBookSection(
          key: const ValueKey('orderbook'),
          currentPrice: widget.currentPrice,
          quote: widget.quote,
          symbol: widget.symbol,
          bids: _bids,
          asks: _asks,
        );
      case 1:
        return IndicatorsSection(
          key: const ValueKey('indicators'),
          overlayIndicator: widget.overlayIndicator,
          subChartIndicator: widget.subChartIndicator,
          showPrevCloseLine: widget.showPrevCloseLine,
          onOverlayChanged: widget.onOverlayChanged ?? (_) {},
          onSubChartChanged: widget.onSubChartChanged ?? (_) {},
          onShowPrevCloseLineChanged: widget.onShowPrevCloseLineChanged,
          candles: widget.klineCandles,
        );
      case 2:
        return _buildCapitalTab(context);
      case 3:
        return _buildNewsTab(
          context,
          loading: _loadingNews,
          items: _news,
          emptyText: widget.symbol?.trim().isNotEmpty == true
              ? '${widget.symbol} 暂无新闻'
              : '暂无新闻',
        );
      case 4:
        return _buildNewsTab(
          context,
          loading: _loadingAnnouncements,
          items: _announcements,
          emptyText: widget.symbol?.trim().isNotEmpty == true
              ? '${widget.symbol} 暂无公告'
              : '暂无公告',
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _placeholder(BuildContext context, String label) {
    final developing = AppLocalizations.of(context)!.commonFeatureDeveloping;
    return Container(
      key: ValueKey(label),
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      alignment: Alignment.center,
      child: Text(
        '$label - $developing',
        style: TextStyle(color: ChartTheme.textSecondary, fontSize: 14),
      ),
    );
  }

  Future<void> _loadCapital() async {
    final symbol = widget.symbol?.trim() ?? '';
    if (symbol.isEmpty) return;
    setState(() => _loadingCapital = true);
    final ratios = await _market.getKeyRatios(symbol);
    final dividends = await _market.getDividends(symbol);
    final splits = await _market.getSplits(symbol);
    if (!mounted) return;
    setState(() {
      _keyRatios = ratios;
      _dividends = dividends;
      _splits = splits;
      _loadingCapital = false;
    });
  }

  Future<void> _loadTickerNews() async {
    final symbol = widget.symbol?.trim() ?? '';
    if (symbol.isEmpty) return;
    setState(() => _loadingNews = true);
    final rows = await _market.getTickerNews(symbol, limit: 20);
    if (!mounted) return;
    setState(() {
      _news = rows;
      _loadingNews = false;
    });
  }

  Future<void> _loadAnnouncements() async {
    final symbol = widget.symbol?.trim() ?? '';
    if (symbol.isEmpty) return;
    setState(() => _loadingAnnouncements = true);
    final rows = await _market.getTickerAnnouncements(symbol, limit: 20);
    if (!mounted) return;
    setState(() {
      _announcements = rows;
      _loadingAnnouncements = false;
    });
  }

  Widget _buildCapitalTab(BuildContext context) {
    if (_loadingCapital) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final hasRatios = _keyRatios != null && _keyRatios!.isNotEmpty;
    final hasActions = _dividends.isNotEmpty || _splits.isNotEmpty;
    if (!hasRatios && !hasActions) {
      return _placeholder(context, AppLocalizations.of(context)!.chartTabCapital);
    }
    final pe = _numText(_keyRatios?['price_to_earnings']);
    final pb = _numText(_keyRatios?['price_to_book']);
    final dy = _percentText(_keyRatios?['dividend_yield']);
    final roe = _percentText(_keyRatios?['return_on_equity']);
    final mc = _largeNumText(_keyRatios?['market_cap']);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasRatios) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metricChip('P/E', pe),
                _metricChip('P/B', pb),
                _metricChip('Div Yield', dy),
                _metricChip('ROE', roe),
                _metricChip('Mkt Cap', mc),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (_dividends.isNotEmpty)
            Text(
              'Dividends: ${_dividends.take(3).map((d) => '${d['ex_dividend_date'] ?? '-'} \$${d['cash_amount'] ?? '-'}').join('  |  ')}',
              style: TextStyle(color: ChartTheme.textPrimary, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          if (_splits.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Splits: ${_splits.take(3).map((s) => '${s['execution_date'] ?? '-'} ${s['split_from'] ?? '-'}:${s['split_to'] ?? '-'}').join('  |  ')}',
              style: TextStyle(color: ChartTheme.textPrimary, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: ChartTheme.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ChartTheme.border),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(color: ChartTheme.textPrimary, fontSize: 12),
      ),
    );
  }

  Widget _buildNewsTab(
    BuildContext context, {
    required bool loading,
    required List<MarketNewsItem> items,
    required String emptyText,
  }) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (items.isEmpty) {
      return _placeholder(context, emptyText);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        children: items.take(12).map((item) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: ChartTheme.surface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ChartTheme.border),
            ),
            child: ListTile(
              dense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              title: Text(
                item.title,
                style: const TextStyle(
                  color: ChartTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${item.source} · ${_formatTime(item.publishedAt)}',
                  style: const TextStyle(
                    color: ChartTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              trailing: const Icon(
                Icons.open_in_new_rounded,
                size: 16,
                color: ChartTheme.textSecondary,
              ),
              onTap: () => _openNews(item),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _openNews(MarketNewsItem item) async {
    final uri = Uri.tryParse(item.url);
    if (uri == null) return;
    await openInAppWebView(
      context,
      url: item.url,
      title: item.title,
    );
  }

  static String _numText(dynamic value) {
    final v = value is num ? value.toDouble() : double.tryParse('${value ?? ''}');
    if (v == null) return '--';
    return v.toStringAsFixed(2);
  }

  static String _percentText(dynamic value) {
    final v = value is num ? value.toDouble() : double.tryParse('${value ?? ''}');
    if (v == null) return '--';
    return '${(v * 100).toStringAsFixed(2)}%';
  }

  static String _largeNumText(dynamic value) {
    final v = value is num ? value.toDouble() : double.tryParse('${value ?? ''}');
    if (v == null) return '--';
    if (v >= 1000000000) return '${(v / 1000000000).toStringAsFixed(2)}B';
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(2)}M';
    return v.toStringAsFixed(0);
  }

  static String _formatTime(DateTime? dt) {
    if (dt == null) return '--';
    final local = dt.toLocal();
    return '${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
