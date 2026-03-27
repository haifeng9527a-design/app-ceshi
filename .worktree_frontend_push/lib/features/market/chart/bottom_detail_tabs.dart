import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../trading/polygon_repository.dart';
import '../market_repository.dart';
import 'chart_theme.dart';
import 'indicators_section.dart';
import 'order_book_section.dart';

/// 底部 Tab（一比一参考）：盘口 | 指标 | 资金 | 新闻 | 公告
class BottomDetailTabs extends StatefulWidget {
  const BottomDetailTabs({
    super.key,
    required this.currentPrice,
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
    _orderBookTimer = Timer.periodic(const Duration(seconds: 5), (_) => poll());
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
                    if (i == 0 && !wasOrderBook) _startOrderBookPolling();
                    else if (i != 0) _stopOrderBookPolling();
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
        return _placeholder(context, AppLocalizations.of(context)!.chartTabCapital);
      case 3:
        return _placeholder(context, AppLocalizations.of(context)!.chartTabNews);
      case 4:
        return _placeholder(context, AppLocalizations.of(context)!.chartTabAnnouncement);
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
}
