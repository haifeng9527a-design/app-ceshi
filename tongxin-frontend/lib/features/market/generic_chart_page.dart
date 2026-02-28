import 'package:flutter/material.dart';

import 'chart/chart_mode_tabs.dart';
import 'chart/chart_theme.dart';
import 'chart/detail_header.dart';
import 'chart/indicators_panel.dart';
import 'chart/intraday_chart.dart';
import 'chart/stats_bar.dart';
import 'chart/tv_chart_container.dart';
import 'chart_viewport.dart';
import 'chart_viewport_controller.dart';
import 'market_repository.dart';

/// 指数/外汇/加密货币详情页切换时的内存缓存（最近 5 只）
class _GenericDetailCache {
  MarketQuote? quote;
  List<ChartCandle> intraday = [];
  List<ChartCandle> daily = [];
  String chartPeriod = '1m';
  String klineTimespan = 'day';
}

const int _genericCacheMaxSize = 5;
final Map<String, _GenericDetailCache> _genericDetailCache = {};

void _trimGenericCache() {
  if (_genericDetailCache.length > _genericCacheMaxSize) {
    final keys = _genericDetailCache.keys.toList();
    for (var i = 0; i < keys.length - _genericCacheMaxSize; i++) {
      _genericDetailCache.remove(keys[i]);
    }
  }
}

/// 指数/外汇/加密货币详情：与股票详情（StockChartPage）同一套界面
/// 分时：摘要行（价/均/涨/涨跌幅/量/额）+ IntradayChart 铺满、时间轴对齐、当前价虚线贯通
/// K 线：ChartViewport + 指标面板 + 底部数据带。数据来源：Twelve Data
class GenericChartPage extends StatefulWidget {
  const GenericChartPage({
    super.key,
    required this.symbol,
    required this.name,
    this.symbolList,
    this.symbolIndex,
  });

  final String symbol;
  final String name;
  final List<String>? symbolList;
  final int? symbolIndex;

  @override
  State<GenericChartPage> createState() => _GenericChartPageState();
}

class _GenericChartPageState extends State<GenericChartPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _market = MarketRepository();

  MarketQuote? _quote;
  List<ChartCandle> _intraday = [];
  List<ChartCandle> _daily = [];
  late final ChartViewportController _dailyController;
  bool _dailyLoadingMore = false;
  int? _lastLoadedEarliestTs;
  String _overlayIndicator = 'none';
  String _subChartIndicator = 'vol';
  bool _showPrevCloseLine = true;
  bool _loading = true;
  String _chartPeriod = '1m';
  String _klineTimespan = 'day';
  late String _currentSymbol;
  String _currentName = '';
  int _currentIndex = 0;

  String get _effectiveSymbol => widget.symbolList != null ? _currentSymbol : widget.symbol;
  String get _effectiveName => widget.symbolList != null ? _currentName : widget.name;
  int get _effectiveIndex => widget.symbolList != null ? _currentIndex : _prevNextIndex;

  static const double _chartMinHeight = 320.0;
  static const double _chartContainerPaddingV = 28.0;
  static const double _intradayChartPaddingV = 16.0;
  static const double _intradaySummaryRowHeight = 56.0;
  static const double _ratioChart = 220 / 298;
  static const double _ratioVolume = 56 / 298;
  static const double _ratioTimeAxis = 22 / 298;
  static const double _ratioIntradayVolume = 0.18;

  static String _intradayToInterval(String p) => '1min';

  static int? _intradayLastDays(String p) {
    switch (p) {
      case '2d': return 2;
      case '3d': return 3;
      case '4d': return 4;
      default: return null;
    }
  }

  static String _klineToInterval(String t) {
    switch (t) {
      case '5day':
      case 'day': return '1day';
      case 'week': return '1day'; // Twelve Data 可后续扩展 1week
      case 'month': return '1day';
      case 'year': return '1day';
      default: return '1day';
    }
  }

  int get _symbolListLength => widget.symbolList?.length ?? 0;

  int get _prevNextIndex {
    final list = widget.symbolList;
    if (list == null || list.isEmpty) return -1;
    if (widget.symbolList != null) return _currentIndex.clamp(0, list.length - 1);
    if (widget.symbolIndex != null) {
      return widget.symbolIndex!.clamp(0, list.length - 1);
    }
    final i = list.indexWhere((s) => s.toUpperCase() == widget.symbol.toUpperCase());
    return i >= 0 ? i : 0;
  }

  void _switchToPrev() {
    final list = widget.symbolList;
    if (list == null || list.isEmpty) return;
    final i = _effectiveIndex;
    if (i <= 0) return;
    _switchToSymbolInPlace(list[i - 1]);
  }

  void _switchToNext() {
    final list = widget.symbolList;
    if (list == null || list.isEmpty) return;
    final i = _effectiveIndex;
    if (i >= list.length - 1) return;
    _switchToSymbolInPlace(list[i + 1]);
  }

  void _switchToSymbolInPlace(String newSymbol) {
    final list = widget.symbolList;
    if (list == null || list.isEmpty) return;
    final newSym = newSymbol.trim();
    final newIndex = list.indexWhere((s) => s.toUpperCase() == newSym.toUpperCase());
    if (newIndex < 0) return;

    final oldSym = _currentSymbol;
    _saveToCache(oldSym);

    setState(() {
      _currentSymbol = newSym;
      _currentName = newSym;
      _currentIndex = newIndex;
      _loading = true;
    });

    final cached = _genericDetailCache[newSym];
    if (cached != null && (cached.intraday.isNotEmpty || cached.daily.isNotEmpty)) {
      setState(() {
        _quote = cached.quote;
        _intraday = List.from(cached.intraday);
        _daily = List.from(cached.daily);
        _chartPeriod = cached.chartPeriod;
        _klineTimespan = cached.klineTimespan;
        _loading = false;
      });
      _dailyController.initFromCandlesLength(_daily.length);
    }

    _load().then((_) {
      if (mounted) {
        setState(() {});
        _saveToCache(newSym);
      }
    });
  }

  void _saveToCache(String sym) {
    if (_intraday.isEmpty && _daily.isEmpty) return;
    final c = _GenericDetailCache()
      ..quote = _quote
      ..intraday = List.from(_intraday)
      ..daily = List.from(_daily)
      ..chartPeriod = _chartPeriod
      ..klineTimespan = _klineTimespan;
    _genericDetailCache[sym] = c;
    _trimGenericCache();
  }

  void _navigateToSymbol(String newSymbol) {
    final list = widget.symbolList;
    if (list != null && list.isNotEmpty) {
      _switchToSymbolInPlace(newSymbol);
      return;
    }
    final newIndex = list != null ? list.indexWhere((s) => s.toUpperCase() == newSymbol.toUpperCase()) : -1;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GenericChartPage(
          symbol: newSymbol,
          name: newSymbol,
          symbolList: list,
          symbolIndex: newIndex >= 0 ? newIndex : null,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _currentSymbol = widget.symbol.trim();
    _currentName = widget.name;
    final list = widget.symbolList;
    if (list != null && list.isNotEmpty && widget.symbolIndex != null) {
      _currentIndex = widget.symbolIndex!.clamp(0, list.length - 1);
    } else if (list != null && list.isNotEmpty) {
      final i = list.indexWhere((s) => s.toUpperCase() == widget.symbol.toUpperCase());
      _currentIndex = i >= 0 ? i : 0;
    } else {
      _currentIndex = 0;
    }
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {});
    });
    _dailyController = ChartViewportController(initialVisibleCount: 80, minVisibleCount: 30, maxVisibleCount: 200);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_market.twelveDataAvailable) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final sym = _effectiveSymbol.trim();
    final q = await _market.getQuote(sym);
    final lastDays = _intradayLastDays(_chartPeriod);
    final intra = await _market.getCandles(sym, _intradayToInterval(_chartPeriod), lastDays: lastDays);
    final day = await _market.getCandles(sym, _klineToInterval(_klineTimespan));
    if (!mounted) return;
    setState(() {
      _quote = q;
      _intraday = intra;
      _daily = day;
      _lastLoadedEarliestTs = null;
      _dailyController.initFromCandlesLength(day.length);
      _loading = false;
      if (q.name != null && q.name!.isNotEmpty) _currentName = q.name!;
    });
    _saveToCache(sym);
  }

  Future<void> _loadDailyOlder(int earliestTimestampMs) async {
    if (_dailyLoadingMore) return;
    if (_lastLoadedEarliestTs != null && earliestTimestampMs >= _lastLoadedEarliestTs!) return;
    setState(() => _dailyLoadingMore = true);
    try {
      final beforeLen = _daily.length;
      final list = await _market.getCandlesOlderThan(
        _effectiveSymbol,
        _klineToInterval(_klineTimespan),
        olderThanMs: earliestTimestampMs,
        limit: 300,
      );
      if (!mounted) return;
      if (list.isNotEmpty) {
        final merged = MarketRepository.mergeAndDedupeCandles(list, _daily);
        final newCandlesLen = merged.length - beforeLen;
        setState(() {
          _daily = merged;
          _dailyController.addStartOffset(newCandlesLen);
          _lastLoadedEarliestTs = earliestTimestampMs;
        });
      }
    } finally {
      if (mounted) setState(() => _dailyLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _quote;
    final changeVal = (q != null && !q.hasError) ? q.change : null;
    final changePercent = (q != null && !q.hasError) ? q.changePercent : null;

    return Scaffold(
      backgroundColor: ChartTheme.background,
      body: Column(
        children: [
          DetailHeader(
            symbol: _effectiveSymbol,
            name: _effectiveName.isNotEmpty ? _effectiveName : null,
            onBack: () => Navigator.of(context).maybePop(),
            onPrev: _prevNextIndex > 0 ? _switchToPrev : null,
            onNext: _prevNextIndex >= 0 && _prevNextIndex < _symbolListLength - 1 ? _switchToNext : null,
          ),
          ChartModeTabs(
            labels: ChartModeTabs.genericLabels,
            tabIndex: _tabController.index,
            onTabChanged: (i) => _tabController.animateTo(i),
            isIntraday: _tabController.index == 0,
            intradayPeriod: _chartPeriod,
            klineTimespan: _klineTimespan,
            onIntradayPeriodChanged: (p) async {
              if (_chartPeriod == p) return;
              setState(() => _chartPeriod = p);
              setState(() => _loading = true);
              await _load();
              if (mounted) setState(() => _loading = false);
            },
            onKlineTimespanChanged: (t) async {
              if (_klineTimespan == t) return;
              setState(() => _klineTimespan = t);
              setState(() => _loading = true);
              await _load();
              if (mounted) setState(() => _loading = false);
            },
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableHeight = constraints.maxHeight.clamp(_chartMinHeight, double.infinity);
                final contentHeight = (availableHeight - _chartContainerPaddingV - _intradayChartPaddingV).clamp(200.0, double.infinity);
                final contentHeightIntraday = (contentHeight - _intradaySummaryRowHeight).clamp(200.0, double.infinity);
                final chartHeight = contentHeight * _ratioChart;
                final volumeHeight = contentHeight * _ratioVolume;
                final timeAxisHeight = contentHeight * _ratioTimeAxis;
                final chartHeightIntraday = contentHeightIntraday * _ratioChart;
                final timeAxisHeightIntraday = contentHeightIntraday * _ratioTimeAxis;
                final intradayVolumeHeight = contentHeightIntraday * _ratioIntradayVolume;

                Widget chartContent;
                if (_loading) {
                  chartContent = Center(
                    child: Text('加载中…', style: TextStyle(color: ChartTheme.textSecondary, fontSize: 13)),
                  );
                } else if (_intraday.isEmpty && _daily.isEmpty) {
                  chartContent = _buildEmptyStateCard();
                } else {
                  chartContent = TabBarView(
                    controller: _tabController,
                    children: [
                      _intraday.isEmpty
                          ? _buildNoDataHint(true)
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildIntradaySummaryRow(),
                                Expanded(
                                  child: IntradayChart(
                                    candles: _intraday,
                                    prevClose: (q != null && !q.hasError && q.price > 0 && q.change != 0) ? q.price - q.change : null,
                                    currentPrice: (q != null && !q.hasError) ? q.price : null,
                                    chartHeight: chartHeightIntraday,
                                    timeAxisHeight: timeAxisHeightIntraday,
                                    volumeHeight: intradayVolumeHeight,
                                    periodLabel: _chartPeriod,
                                  ),
                                ),
                              ],
                            ),
                      _daily.isEmpty
                          ? _buildNoDataHint(false)
                          : Stack(
                              children: [
                                ChartViewport(
                                  controller: _dailyController,
                                  candles: _daily,
                                  onLoadMoreHistory: _loadDailyOlder,
                                  isLoadingMore: _dailyLoadingMore,
                                  chartHeight: chartHeight,
                                  volumeHeight: volumeHeight,
                                  timeAxisHeight: timeAxisHeight,
                                  overlayIndicator: _overlayIndicator,
                                  subChartIndicator: _subChartIndicator,
                                  showPrevCloseLine: _showPrevCloseLine,
                                ),
                                ListenableBuilder(
                                  listenable: _dailyController,
                                  builder: (_, __) {
                                    final atRealtime = _dailyController.isAtRealtime(_daily.length);
                                    if (atRealtime) return const SizedBox.shrink();
                                    return Positioned(
                                      right: 12,
                                      bottom: 12,
                                      child: Material(
                                        color: ChartTheme.cardBackground,
                                        borderRadius: BorderRadius.circular(ChartTheme.radiusButton),
                                        child: InkWell(
                                          onTap: () => _dailyController.goToRealtime(_daily.length),
                                          borderRadius: BorderRadius.circular(ChartTheme.radiusButton),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            child: Text('回最新', style: TextStyle(color: ChartTheme.accentGold, fontSize: 12, fontWeight: FontWeight.w600)),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                    ],
                  );
                }

                return TvChartContainer(
                  padding: const EdgeInsets.fromLTRB(ChartTheme.innerPadding, 16, ChartTheme.innerPadding, ChartTheme.innerPadding),
                  child: SizedBox(height: double.infinity, child: chartContent),
                );
              },
            ),
          ),
          if (_tabController.index == 1)
            IndicatorsPanel(
              overlayIndicator: _overlayIndicator,
              subChartIndicator: _subChartIndicator,
              showPrevCloseLine: _showPrevCloseLine,
              onOverlayChanged: (v) => setState(() => _overlayIndicator = v),
              onSubChartChanged: (v) => setState(() => _subChartIndicator = v),
              onShowPrevCloseLineChanged: (v) => setState(() => _showPrevCloseLine = v),
            ),
          _buildStatsBar(),
        ],
      ),
    );
  }

  String? _statusLabel() {
    final now = DateTime.now();
    final hour = now.hour;
    final minute = now.minute;
    if (hour < 9 || (hour == 9 && minute < 30)) return '未开市';
    if (hour > 16 || (hour == 16 && minute > 0)) return '已收盘';
    return '盘中';
  }

  /// 分时图上方摘要行：价 均 涨 涨跌幅 量 额（与股票详情一致，数据一目了然）
  Widget _buildIntradaySummaryRow() {
    final q = _quote;
    final price = (q != null && !q.hasError && q.price > 0) ? q.price : (_intraday.isNotEmpty ? _intraday.last.close : 0.0);
    final open = (q != null && !q.hasError) ? q.open : (_intraday.isNotEmpty ? _intraday.first.open : null);
    final prev = (q != null && !q.hasError && q.price > 0 && q.change != 0) ? q.price - q.change : open;
    double? avgPrice;
    int totalVol = 0;
    double turnover = 0;
    if (_intraday.isNotEmpty) {
      var sumV = 0.0;
      var sumVw = 0.0;
      for (final c in _intraday) {
        final v = (c.volume ?? 0).toDouble();
        totalVol += c.volume ?? 0;
        turnover += c.close * v;
        sumV += v;
        sumVw += c.close * v;
      }
      avgPrice = sumV > 0 ? sumVw / sumV : (_intraday.map((c) => c.close).reduce((a, b) => a + b) / _intraday.length);
    }
    if (totalVol == 0 && q != null && q.volume != null) totalVol = q.volume!;
    final prevVal = prev ?? 0.0;
    final change = (q != null && q.change != null) ? q.change! : (prevVal > 0 ? price - prevVal : 0.0);
    final changePct = prevVal > 0 ? (price - prevVal) / prevVal * 100 : (q?.changePercent ?? 0.0);
    final changeColor = (change >= 0 ? ChartTheme.up : ChartTheme.down);
    String turnStr = '—';
    if (turnover >= 10000) turnStr = '${(turnover / 10000).toStringAsFixed(2)}万';
    else if (turnover > 0) turnStr = turnover.toStringAsFixed(0);
    String volStr = '—';
    if (totalVol > 0) volStr = totalVol >= 10000 ? '${(totalVol / 10000).toStringAsFixed(2)}万' : totalVol.toString();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ChartTheme.pagePadding, vertical: 8),
      decoration: const BoxDecoration(
        color: ChartTheme.cardBackground,
        border: Border(bottom: BorderSide(color: ChartTheme.border, width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _summaryBlock('价', price > 0 ? price.toStringAsFixed(2) : '—', null),
            _summaryBlock('均', avgPrice != null ? avgPrice.toStringAsFixed(2) : '—', null),
            _summaryBlock('涨', '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}', changeColor),
            _summaryBlock('涨跌幅', '${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(2)}%', changeColor),
            _summaryBlock('量', volStr, null),
            _summaryBlock('额', turnStr, null),
          ],
        ),
      ),
    );
  }

  Widget _summaryBlock(String label, String value, Color? valueColor) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: ChartTheme.textTertiary, fontSize: 10)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? ChartTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: ChartTheme.fontMono,
              fontFeatures: const [ChartTheme.tabularFigures],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildNoDataHint(bool isIntraday) {
    final label = isIntraday ? '分时' : 'K线';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2, color: ChartTheme.accentGold)),
            const SizedBox(height: 12),
            Text('正在拉取${label}数据…', style: TextStyle(color: ChartTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyStateCard() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(ChartTheme.sectionGap),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          color: ChartTheme.cardBackground,
          borderRadius: BorderRadius.circular(ChartTheme.radiusCard),
          border: Border.all(color: ChartTheme.border, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.show_chart_rounded, size: 48, color: ChartTheme.textTertiary),
            const SizedBox(height: 16),
            Text('暂无数据', style: TextStyle(color: ChartTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              '分时与 K 线数据暂时无法加载，请稍后重试或检查数据源配置',
              style: TextStyle(color: ChartTheme.textTertiary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Material(
              color: ChartTheme.surface2,
              borderRadius: BorderRadius.circular(ChartTheme.radiusButton),
              child: InkWell(
                onTap: () {
                  setState(() => _loading = true);
                  _load().then((_) { if (mounted) setState(() => _loading = false); });
                },
                borderRadius: BorderRadius.circular(ChartTheme.radiusButton),
                hoverColor: ChartTheme.surfaceHover,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text('重试', style: TextStyle(color: ChartTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsBar() {
    final q = _quote;
    double? open;
    double? high;
    double? low;
    double? close;
    double? prevClose;
    double? change;
    double? changePercent;
    double? amplitude;
    int? volume;
    double? turnover;
    if (q != null && !q.hasError) {
      open = q.open;
      high = q.high;
      low = q.low;
      close = q.price;
      prevClose = (q.price > 0 && q.change != 0) ? q.price - q.change : null;
      change = q.change;
      changePercent = q.changePercent;
      if (high != null && low != null && (prevClose ?? 0) > 0) {
        amplitude = (high! - low!) / prevClose! * 100;
      }
      volume = q.volume;
      if (volume != null && volume > 0 && close != null && close! > 0) {
        turnover = volume * close!;
      }
    }
    if (open == null && _intraday.isNotEmpty) {
      open = _intraday.first.open;
      high = _intraday.map((c) => c.high).reduce((a, b) => a > b ? a : b);
      low = _intraday.map((c) => c.low).reduce((a, b) => a < b ? a : b);
      close ??= _intraday.last.close;
    }
    if (open == null && _daily.isNotEmpty) {
      final last = _daily.last;
      open = last.open;
      high = last.high;
      low = last.low;
      close = last.close;
    }
    return ChartStatsBar(
      symbol: widget.symbol,
      currentPrice: close,
      change: change,
      changePercent: changePercent,
      open: open,
      high: high,
      low: low,
      close: close,
      prevClose: prevClose,
      amplitude: amplitude,
      avgPrice: (high != null && low != null && close != null) ? (high! + low! + close!) / 3 : null,
      volume: volume,
      turnover: turnover,
    );
  }
}
