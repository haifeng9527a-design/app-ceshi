import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../trading/trading_cache.dart';
import 'chart/chart_theme.dart';
import 'chart/indicators_panel.dart';
import 'chart/intraday_chart.dart';
import 'chart/stats_bar.dart';
import 'chart/timeframe_bar.dart';
import 'chart/top_bar.dart';
import 'chart_viewport.dart';
import 'chart_viewport_controller.dart';
import 'market_colors.dart';
import 'market_repository.dart';

/// 股票详情：实时价、历史走势、成交量、成交额、开高低收（对齐 MOMO 等看盘 App）
///
/// 数据来源（见注释）：
/// - 实时价：WebSocket trade（Polygon 成交流）
/// - 当日 OHLC + volume：优先 Polygon 单标的 Snapshot（/v2/snapshot/.../tickers/{ticker}），否则 Polygon aggregates(1, day, today)
/// - 昨收：Polygon getPreviousClose（/v2/aggs/ticker/prev）或 Snapshot prevDay
/// - 若某字段拿不到，显示 "—" 不显示 0
class StockChartPage extends StatefulWidget {
  const StockChartPage({
    super.key,
    required this.symbol,
    this.initialSnapshot,
    this.isMockData = false,
  });

  final String symbol;
  /// 从行情列表点进时传入，用于立即展示今开/最高/最低/昨收，不等图表
  final PolygonGainer? initialSnapshot;
  /// 是否为模拟数据（列表无 API 时传入，详情页顶部显示「模拟数据」提示）
  final bool isMockData;

  @override
  State<StockChartPage> createState() => _StockChartPageState();
}

class _StockChartPageState extends State<StockChartPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _market = MarketRepository();

  List<ChartCandle> _candlesIntraday = [];
  List<ChartCandle> _candlesKLine = [];
  late final ChartViewportController _klineController;
  bool _klineLoadingMore = false;
  int? _lastLoadedEarliestTs;
  bool _chartLoading = true;
  /// 实时价，来源：WebSocket trade
  double? _currentPrice;
  double? _changePercent;
  /// 昨收，来源：getPreviousClose / Snapshot prevDay
  double? _prevClose;
  /// 当日开/高/低/量，来源：Polygon Snapshot day 或 aggregates(1, day, today)
  double? _dayOpen;
  double? _dayHigh;
  double? _dayLow;
  int? _dayVolume;
  /// 当日累计成交量（WebSocket 成交累加），与 _dayVolume 二选一或叠加展示
  int _realtimeVolume = 0;
  PolygonRealtime? _realtime;
  StreamSubscription<PolygonTradeUpdate>? _realtimeSub;
  /// 时间周期：1m, 5m, 15m, 1h, 1D（分时/K 统一入口）
  String _chartPeriod = '5m';
  /// K线周期（仅 K 线 Tab）：5day, day, week, month, year
  String _klineTimespan = 'day';
  /// 主图叠加：ma / ema
  String _overlayIndicator = 'ma';
  /// 副图：vol / macd / rsi
  String _subChartIndicator = 'vol';
  Timer? _quoteTimer;
  Timer? _chartTimer;
  Timer? _autoRetryTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _klineController = ChartViewportController(initialVisibleCount: 80, minVisibleCount: 30, maxVisibleCount: 200);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {});
    });
    final snap = widget.initialSnapshot;
    if (snap != null) {
      _currentPrice = snap.price;
      _prevClose = snap.prevClose;
      _changePercent = snap.todaysChangePerc;
      _dayOpen = snap.dayOpen;
      _dayHigh = snap.dayHigh;
      _dayLow = snap.dayLow;
      _dayVolume = snap.dayVolume;
      setState(() {});
    }
    // 先出价、再出图：报价优先展示，图表并行加载，任一方完成即更新 UI，避免「点进去半天看不了」
    _loadQuote().then((_) {
      if (mounted) setState(() {});
    });
    _loadTodayOHLC();
    _loadIntraday().then((_) {
      if (mounted) setState(() => _chartLoading = false);
    });
    _loadKLine().then((_) {
      if (mounted) setState(() => _chartLoading = false);
    });
    _connectRealtime();
    _startRealtimeTimers();
  }

  void _startRealtimeTimers() {
    _quoteTimer?.cancel();
    _chartTimer?.cancel();
    _autoRetryTimer?.cancel();
    _quoteTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _loadQuote();
    });
    _chartTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      _loadTodayOHLC();
      _loadIntraday();
      _loadKLine();
    });
    _autoRetryTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      if (_candlesIntraday.isEmpty) _loadIntraday();
      if (_candlesKLine.isEmpty) _loadKLine();
    });
  }

  static String _formatVol(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toString();
  }

  void _connectRealtime() {
    if (!_market.polygonAvailable) return;
    _realtime = _market.openRealtime(widget.symbol);
    _realtime?.connect();
    _realtimeSub = _realtime?.stream.listen((u) {
      if (!mounted) return;
      setState(() {
        _currentPrice = u.price;
        _realtimeVolume += u.size;
      });
    });
  }

  @override
  void dispose() {
    _quoteTimer?.cancel();
    _chartTimer?.cancel();
    _autoRetryTimer?.cancel();
    _realtimeSub?.cancel();
    _realtime?.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadQuote() async {
    final quote = await _market.getQuote(widget.symbol);
    final prev = _market.polygonAvailable ? await _market.getPreviousClose(widget.symbol) : null;
    if (!mounted) return;
    setState(() {
      if (!quote.hasError) {
        _currentPrice = quote.price > 0 ? quote.price : _currentPrice;
        _changePercent = quote.changePercent;
      }
      _prevClose = prev ?? _prevClose;
    });
  }

  /// 当日 OHLC + volume：优先 Polygon Snapshot（单标的 /v2/snapshot/.../tickers/{ticker}），
  /// 否则 Polygon aggregates(1, day, today) 取最后一根作为当日 bar
  Future<void> _loadTodayOHLC() async {
    if (!_market.polygonAvailable) return;
    final snap = await _market.getDaySnapshot(widget.symbol);
    if (!mounted) return;
    if (snap != null) {
      setState(() {
        _dayOpen = snap.dayOpen;
        _dayHigh = snap.dayHigh;
        _dayLow = snap.dayLow;
        _dayVolume = snap.dayVolume;
        if (_prevClose == null && snap.prevClose != null) _prevClose = snap.prevClose;
      });
      return;
    }
    final toMs = DateTime.now().millisecondsSinceEpoch;
    final now = DateTime.now();
    final todayStart = DateTime.utc(now.year, now.month, now.day);
    final fromMs = todayStart.millisecondsSinceEpoch;
    final list = await _market.getAggregates(
      widget.symbol,
      multiplier: 1,
      timespan: 'day',
      fromMs: fromMs,
      toMs: toMs,
    );
    if (!mounted || list.isEmpty) return;
    final bar = list.last;
    setState(() {
      _dayOpen = bar.open;
      _dayHigh = bar.high;
      _dayLow = bar.low;
      _dayVolume = bar.volume != null && bar.volume! > 0 ? bar.volume : _dayVolume;
    });
  }

  Future<void> _loadIntraday() async {
    final sym = widget.symbol.trim().toUpperCase();
    final toMs = DateTime.now().millisecondsSinceEpoch;
    int fromMs;
    int multiplier;
    String timespan;
    if (_chartPeriod == '1D') {
      fromMs = toMs - 60 * 24 * 3600 * 1000;
      multiplier = 1;
      timespan = 'day';
    } else if (_chartPeriod == '1h') {
      fromMs = toMs - 72 * 3600 * 1000;
      multiplier = 1;
      timespan = 'hour';
    } else {
      final min = _chartPeriod == '1m' ? 1 : _chartPeriod == '5m' ? 5 : 15;
      fromMs = toMs - (min <= 1 ? 6 : min <= 15 ? 24 : 72) * 3600 * 1000;
      multiplier = min;
      timespan = 'minute';
    }
    List<ChartCandle> list = [];
    final cache = TradingCache.instance;
    final cacheKey = 'polygon_aggs_${sym}_${multiplier}_${timespan}_${fromMs}_$toMs';
    final cached = await cache.getList(cacheKey, maxAge: const Duration(hours: 24));
    if (cached != null && cached.isNotEmpty) {
      for (final r in cached) {
        if (r is Map<String, dynamic>) {
          final bar = PolygonBar.fromJson(r);
          if (bar != null) list.add(ChartCandle.fromBar(bar));
        }
      }
    }
    if (_market.polygonAvailable) {
      list = await _market.getAggregates(sym, multiplier: multiplier, timespan: timespan, fromMs: fromMs, toMs: toMs);
    }
    if (list.isEmpty && _market.twelveDataAvailable) {
      final interval = _chartPeriod == '1D' ? '1day' : _chartPeriod == '1h' ? '1h' : '${multiplier}min';
      list = await _market.getCandles(sym, interval);
    }
    if (mounted) setState(() => _candlesIntraday = list);
  }

  Future<void> _loadKLine() async {
    final sym = widget.symbol.trim().toUpperCase();
    final toMs = DateTime.now().millisecondsSinceEpoch;
    int fromMs;
    String polygonTimespan = _klineTimespan;
    if (_klineTimespan == '5day') {
      fromMs = toMs - 5 * 24 * 3600 * 1000;
      polygonTimespan = 'day';
    } else if (_klineTimespan == 'year') {
      fromMs = toMs - 10 * 365 * 24 * 3600 * 1000;
      polygonTimespan = 'month';
    } else if (_klineTimespan == 'week') {
      fromMs = toMs - 52 * 7 * 24 * 3600 * 1000;
    } else if (_klineTimespan == 'month') {
      fromMs = toMs - 24 * 30 * 24 * 3600 * 1000;
    } else {
      fromMs = toMs - 60 * 24 * 3600 * 1000;
    }
    List<ChartCandle> list = [];
    final cache = TradingCache.instance;
    final cacheKey = 'polygon_aggs_${sym}_1_${polygonTimespan}_${fromMs}_$toMs';
    final cached = await cache.getList(cacheKey, maxAge: const Duration(hours: 24));
    if (cached != null && cached.isNotEmpty) {
      for (final r in cached) {
        if (r is Map<String, dynamic>) {
          final bar = PolygonBar.fromJson(r);
          if (bar != null) list.add(ChartCandle.fromBar(bar));
        }
      }
    }
    if (_market.polygonAvailable) {
      list = await _market.getAggregates(sym, multiplier: 1, timespan: polygonTimespan, fromMs: fromMs, toMs: toMs);
    }
    if (list.isEmpty && _market.twelveDataAvailable) {
      final interval = polygonTimespan == 'week' ? '1week' : polygonTimespan == 'month' ? '1month' : '1day';
      list = await _market.getCandles(sym, interval);
    }
    if (list.isEmpty) {
      debugPrint('StockChartPage: K线无数据 symbol=$sym timespan=$_klineTimespan (Polygon/Twelve Data 均未返回)');
    }
    if (mounted) {
      setState(() {
        _candlesKLine = list;
        _klineController.initFromCandlesLength(list.length);
      });
    }
  }

  String _klineIntervalForLoadMore() {
    if (_klineTimespan == 'day' || _klineTimespan == '5day') return '1day';
    if (_klineTimespan == 'week') return '1week';
    if (_klineTimespan == 'month' || _klineTimespan == 'year') return '1month';
    return '1day';
  }

  String _klinePolygonTimespan() {
    if (_klineTimespan == '5day' || _klineTimespan == 'day') return 'day';
    if (_klineTimespan == 'year') return 'month';
    if (_klineTimespan == 'week') return 'week';
    if (_klineTimespan == 'month') return 'month';
    return 'day';
  }

  Future<void> _loadKLineHistory(int earliestTimestampMs) async {
    if (_klineLoadingMore) return;
    if (_lastLoadedEarliestTs != null && earliestTimestampMs >= _lastLoadedEarliestTs!) return;
    setState(() => _klineLoadingMore = true);
    try {
      final beforeLen = _candlesKLine.length;
      final earliestTsBefore = beforeLen > 0 ? (_candlesKLine.first.time * 1000).round() : null;
      final list = await _market.getCandlesOlderThan(
        widget.symbol,
        _klineIntervalForLoadMore(),
        olderThanMs: earliestTimestampMs,
        limit: 300,
      );
      if (!mounted) return;
      if (list.isNotEmpty) {
        final merged = MarketRepository.mergeAndDedupeCandles(list, _candlesKLine);
        final afterLen = merged.length;
        final newCandlesLen = afterLen - beforeLen;
        final earliestTsAfter = afterLen > 0 ? (merged.first.time * 1000).round() : null;
        if (kDebugMode) {
          debugPrint('[KLine loadMore] beforeLen=$beforeLen afterLen=$afterLen earliestTsBefore=$earliestTsBefore earliestTsAfter=$earliestTsAfter newCandlesLen=$newCandlesLen');
        }
        setState(() {
          _candlesKLine = merged;
          _klineController.addStartOffset(newCandlesLen);
          _lastLoadedEarliestTs = earliestTimestampMs;
        });
      }
    } finally {
      if (mounted) setState(() => _klineLoadingMore = false);
    }
  }

  static const double _chartMinHeight = 320.0;
  static const double _intradayChartPaddingV = 20.0;
  /// 周期条占位：底部 padding 12 + 按钮条约 40
  static const double _timeframeBarBlockHeight = 52.0;
  static const double _ratioChart = 220 / 298;
  static const double _ratioVolume = 56 / 298;
  static const double _ratioTimeAxis = 22 / 298;
  static const double _ratioIntradayVolume = 0.18;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChartTheme.background,
      body: Column(
        children: [
          ChartTopBar(
            symbol: widget.symbol,
            currentPrice: _currentPrice,
            change: _currentPrice != null && _prevClose != null && _prevClose! > 0
                ? _currentPrice! - _prevClose!
                : null,
            changePercent: _changePercent,
            tabIndex: _tabController.index,
            onTabChanged: (i) => _tabController.animateTo(i),
            onBack: () => Navigator.of(context).maybePop(),
          ),
          if (widget.isMockData) _buildMockBanner(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableHeight = constraints.maxHeight.clamp(_chartMinHeight, double.infinity);
                final contentHeight = (availableHeight - _intradayChartPaddingV - _timeframeBarBlockHeight).clamp(200.0, double.infinity);
                final chartHeight = contentHeight * _ratioChart;
                final volumeHeight = contentHeight * _ratioVolume;
                final timeAxisHeight = contentHeight * _ratioTimeAxis;
                final intradayVolumeHeight = contentHeight * _ratioIntradayVolume;

                return Column(
                  children: [
                    Expanded(
                      child: _chartLoading
                          ? Center(child: Text('加载中…', style: TextStyle(color: ChartTheme.textSecondary)))
                          : _candlesIntraday.isEmpty && _candlesKLine.isEmpty
                              ? _buildNoDataHint(null)
                              : TabBarView(
                                  controller: _tabController,
                                  children: [
                                    _candlesIntraday.isEmpty
                                        ? _buildNoDataHint(true)
                                        : IntradayChart(
                                            candles: _candlesIntraday,
                                            prevClose: _prevClose,
                                            currentPrice: _currentPrice,
                                            chartHeight: chartHeight,
                                            timeAxisHeight: timeAxisHeight,
                                            volumeHeight: intradayVolumeHeight,
                                            periodLabel: _chartPeriod,
                                          ),
                                    _candlesKLine.isEmpty
                                        ? _buildNoDataHint(false)
                                        : Stack(
                                            children: [
                                              ChartViewport(
                                                controller: _klineController,
                                                candles: _candlesKLine,
                                                onLoadMoreHistory: _loadKLineHistory,
                                                isLoadingMore: _klineLoadingMore,
                                                chartHeight: chartHeight,
                                                volumeHeight: volumeHeight,
                                                timeAxisHeight: timeAxisHeight,
                                                overlayIndicator: _overlayIndicator,
                                                subChartIndicator: _subChartIndicator,
                                              ),
                                              ListenableBuilder(
                                                listenable: _klineController,
                                                builder: (_, __) {
                                                  final atRealtime = _klineController.isAtRealtime(_candlesKLine.length);
                                                  if (atRealtime) return const SizedBox.shrink();
                                                  return Positioned(
                                                    right: 12,
                                                    bottom: 12,
                                                    child: Material(
                                                      color: ChartTheme.cardBackground,
                                                      borderRadius: BorderRadius.circular(ChartTheme.radiusButton),
                                                      child: InkWell(
                                                        onTap: () => _klineController.goToRealtime(_candlesKLine.length),
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
                                ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Center(
                        child: TimeframeBar(
                          isIntraday: _tabController.index == 0,
                          intradayPeriod: _chartPeriod,
                          klineTimespan: _klineTimespan,
                          onIntradayPeriodChanged: (p) async {
                            if (_chartPeriod == p) return;
                            setState(() => _chartPeriod = p);
                            setState(() => _chartLoading = true);
                            await _loadIntraday();
                            if (mounted) setState(() => _chartLoading = false);
                          },
                          onKlineTimespanChanged: (t) async {
                            if (_klineTimespan == t) return;
                            setState(() => _klineTimespan = t);
                            setState(() => _chartLoading = true);
                            await _loadKLine();
                            if (mounted) setState(() => _chartLoading = false);
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (_tabController.index == 1)
            IndicatorsPanel(
              overlayIndicator: _overlayIndicator,
              subChartIndicator: _subChartIndicator,
              onOverlayChanged: (v) => setState(() => _overlayIndicator = v),
              onSubChartChanged: (v) => setState(() => _subChartIndicator = v),
            ),
          _buildStatsBar(),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    double? open;
    double? high;
    double? low;
    double? close;
    if (_candlesIntraday.isNotEmpty) {
      open = _candlesIntraday.first.open;
      high = _candlesIntraday.map((c) => c.high).reduce((a, b) => a > b ? a : b);
      low = _candlesIntraday.map((c) => c.low).reduce((a, b) => a < b ? a : b);
      close = _candlesIntraday.last.close;
    } else if (_candlesKLine.isNotEmpty) {
      final last = _candlesKLine.last;
      open = last.open;
      high = last.high;
      low = last.low;
      close = last.close;
    }
    open ??= _dayOpen;
    high ??= _dayHigh;
    low ??= _dayLow;
    final displayClose = _currentPrice ?? close;
    final change = (displayClose != null && _prevClose != null && _prevClose! > 0)
        ? displayClose - _prevClose!
        : null;
    int? vol;
    if (_realtimeVolume > 0) vol = _realtimeVolume;
    else if (_candlesIntraday.isNotEmpty && _candlesIntraday.any((c) => (c.volume ?? 0) > 0)) {
      vol = _candlesIntraday.fold<int>(0, (s, c) => s + (c.volume ?? 0));
    } else if (_candlesKLine.isNotEmpty && _candlesKLine.last.volume != null && _candlesKLine.last.volume! > 0) {
      vol = _candlesKLine.last.volume;
    }
    if (vol == null || vol <= 0) vol = _dayVolume;
    if (vol != null && vol <= 0) vol = null;
    final priceForTurnover = (displayClose != null && displayClose > 0) ? displayClose : (open != null && open! > 0 ? open : _prevClose);
    final turnover = (vol != null && vol > 0 && priceForTurnover != null && priceForTurnover > 0)
        ? vol * priceForTurnover
        : null;
    final prev = (_prevClose != null && _prevClose! > 0) ? _prevClose! : 0.0;
    final amplitude = (high != null && low != null && prev > 0)
        ? (high! - low!) / prev * 100
        : null;
    final avgPrice = (high != null && low != null && displayClose != null)
        ? (high! + low! + displayClose) / 3
        : null;
    return ChartStatsBar(
      symbol: widget.symbol,
      currentPrice: displayClose,
      change: change,
      changePercent: _changePercent,
      open: open,
      high: high,
      low: low,
      close: displayClose,
      prevClose: _prevClose,
      amplitude: amplitude,
      avgPrice: avgPrice,
      volume: vol,
      turnover: turnover,
      turnoverRate: null,
      peTtm: null,
    );
  }

  Widget _buildMockBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ChartTheme.accentGold.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ChartTheme.accentGold.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: ChartTheme.accentGold),
          const SizedBox(width: 8),
          Text('模拟数据，仅作展示', style: TextStyle(color: ChartTheme.textPrimary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildNoDataHint(bool? isIntraday) {
    final label = isIntraday == false ? 'K线' : isIntraday == true ? '分时' : '图表';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2, color: ChartTheme.accentGold)),
            const SizedBox(height: 12),
            Text('正在拉取${label}实时数据…', style: TextStyle(color: ChartTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('每秒更新报价，图表每10秒刷新', style: TextStyle(color: ChartTheme.textSecondary, fontSize: 11), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  static List<double?> _ma(List<ChartCandle> candles, int period) {
    if (candles.isEmpty) return [];
    final closes = candles.map((c) => c.close).toList();
    final out = <double?>[];
    for (var i = 0; i < closes.length; i++) {
      if (i + 1 < period) {
        out.add(null);
        continue;
      }
      double sum = 0;
      for (var j = i - period + 1; j <= i; j++) sum += closes[j];
      out.add(sum / period);
    }
    return out;
  }

  static const double _candleWidth = 8.0;
  static const double _chartHeight = 220.0;
  static const double _volumeHeight = 56.0;
  static const double _timeAxisHeight = 22.0;

  String _formatChartTime(double timeSec) {
    final d = DateTime.fromMillisecondsSinceEpoch((timeSec * 1000).toInt());
    if (_klineTimespan == 'month' || _klineTimespan == 'week' || _klineTimespan == 'year') {
      return '${d.year}/${d.month.toString().padLeft(2, '0')}';
    }
    if (_klineTimespan == 'day' || _klineTimespan == '5day') {
      return '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    }
    return '${d.month.toString().padLeft(2, '0')}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildKLineWithMaAndVolume(List<ChartCandle> candles) {
    if (candles.isEmpty) return Center(child: Text('暂无图表数据', style: TextStyle(color: ChartTheme.textSecondary)));
    double minY = candles.first.low;
    double maxY = candles.first.high;
    for (final c in candles) {
      if (c.low < minY) minY = c.low;
      if (c.high > maxY) maxY = c.high;
    }
    final ma5 = _ma(candles, 5);
    final ma10 = _ma(candles, 10);
    final ma20 = _ma(candles, 20);
    for (var i = 0; i < candles.length; i++) {
      for (final v in [ma5[i], ma10[i], ma20[i]]) {
        if (v != null) {
          if (v < minY) minY = v;
          if (v > maxY) maxY = v;
        }
      }
    }
    final range = (maxY - minY).clamp(0.01, double.infinity);
    minY = minY - range * 0.02;
    maxY = maxY + range * 0.02;
    final hasVolume = candles.any((c) => (c.volume ?? 0) > 0);
    final basePrice = _prevClose ?? candles.first.open;
    final contentWidth = (candles.length * _candleWidth).clamp(200.0, double.infinity);
    final axisStyle = TextStyle(color: ChartTheme.textSecondary, fontSize: 10);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MA5/MA10/MA20', style: TextStyle(color: ChartTheme.textSecondary, fontSize: 10)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 48,
                height: _chartHeight + (hasVolume ? _volumeHeight : 0) + _timeAxisHeight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(5, (i) {
                    final v = maxY - (maxY - minY) * i / 4;
                    return Text(v.toStringAsFixed(2), style: axisStyle);
                  }),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: SizedBox(
                    width: contentWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: _chartHeight,
                          child: CustomPaint(
                            size: Size(contentWidth, _chartHeight),
                            painter: _CandlestickPainter(
                              candles: candles,
                              minY: minY,
                              maxY: maxY,
                              ma5: ma5,
                              ma10: ma10,
                              ma20: ma20,
                            ),
                          ),
                        ),
                        if (hasVolume)
                          SizedBox(
                            height: _volumeHeight,
                            child: CustomPaint(
                              size: Size(contentWidth, _volumeHeight),
                              painter: _VolumeBarPainter(candles: candles),
                            ),
                          ),
                        SizedBox(
                          height: _timeAxisHeight,
                          width: contentWidth,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(5, (i) {
                              final idx = i == 0 ? 0 : (i * (candles.length - 1) / 4).floor().clamp(0, candles.length - 1);
                              if (idx >= candles.length) return const SizedBox.shrink();
                              return Text(_formatChartTime(candles[idx].time), style: axisStyle);
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 44,
                height: _chartHeight + (hasVolume ? _volumeHeight : 0) + _timeAxisHeight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(5, (i) {
                    final v = maxY - (maxY - minY) * i / 4;
                    final pct = basePrice > 0 ? (v - basePrice) / basePrice * 100 : 0.0;
                    final pctStr = '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%';
                    return Text(pctStr, style: axisStyle);
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CandlestickPainter extends CustomPainter {
  _CandlestickPainter({
    required this.candles,
    required this.minY,
    required this.maxY,
    this.ma5,
    this.ma10,
    this.ma20,
  });

  final List<ChartCandle> candles;
  final double minY;
  final double maxY;
  final List<double?>? ma5;
  final List<double?>? ma10;
  final List<double?>? ma20;

  void _drawMaLine(Canvas canvas, Size size, List<double?>? values, Color color) {
    if (values == null || values.length != candles.length) return;
    const pad = 4.0;
    final chartW = size.width - pad * 2;
    final chartH = size.height - pad * 2;
    final rangeY = (maxY - minY).clamp(0.01, double.infinity);
    final n = candles.length;
    final candleW = (chartW / n).clamp(2.0, 20.0);
    final gap = (chartW - candleW * n) / (n + 1);
    final path = Path();
    var started = false;
    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v == null) continue;
      final x = pad + gap + (gap + candleW) * i + candleW / 2;
      final y = pad + chartH - (v - minY) / rangeY * chartH;
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    if (started) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    final n = candles.length;
    const pad = 4.0;
    final chartW = size.width - pad * 2;
    final chartH = size.height - pad * 2;
    final rangeY = (maxY - minY).clamp(0.01, double.infinity);
    final candleW = (chartW / n).clamp(2.0, 20.0);
    final gap = (chartW - candleW * n) / (n + 1);

    if (ma5 != null) _drawMaLine(canvas, size, ma5, const Color(0xFFF59E0B));
    if (ma10 != null) _drawMaLine(canvas, size, ma10, const Color(0xFF3B82F6));
    if (ma20 != null) _drawMaLine(canvas, size, ma20, const Color(0xFF8B5CF6));

    final gridPaint = Paint()
      ..color = const Color(0x14FFFFFF) // rgba(255,255,255,0.08)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    for (var g = 0; g <= 4; g++) {
      final y = pad + chartH * g / 4;
      canvas.drawLine(Offset(pad, y), Offset(size.width - pad, y), gridPaint);
    }

    for (var i = 0; i < n; i++) {
      final c = candles[i];
      final isUp = c.close >= c.open;
      final color = MarketColors.forUp(isUp);
      final x = pad + gap + (gap + candleW) * i + candleW / 2;
      final yHigh = pad + chartH - (c.high - minY) / rangeY * chartH;
      final yLow = pad + chartH - (c.low - minY) / rangeY * chartH;
      final yOpen = pad + chartH - (c.open - minY) / rangeY * chartH;
      final yClose = pad + chartH - (c.close - minY) / rangeY * chartH;
      final bodyTop = yOpen < yClose ? yOpen : yClose;
      final bodyBottom = yOpen < yClose ? yClose : yOpen;
      final bodyH = (bodyBottom - bodyTop).clamp(1.0, double.infinity);
      const wickW = 1.0;
      final bodyW = (candleW * 0.7).clamp(3.0, 14.0);

      final paint = Paint()
        ..color = color
        ..strokeWidth = wickW
        ..style = PaintingStyle.stroke;

      canvas.drawLine(Offset(x, yHigh), Offset(x, yLow), paint);

      paint.style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(x, (bodyTop + bodyBottom) / 2),
          width: bodyW,
          height: bodyH,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CandlestickPainter old) {
    return old.candles != candles || old.minY != minY || old.maxY != maxY ||
        old.ma5 != ma5 || old.ma10 != ma10 || old.ma20 != ma20;
  }
}

class _VolumeBarPainter extends CustomPainter {
  _VolumeBarPainter({required this.candles});
  final List<ChartCandle> candles;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    final vols = candles.map((c) => (c.volume ?? 0).toDouble()).toList();
    final maxV = vols.reduce((a, b) => a > b ? a : b);
    if (maxV <= 0) return;
    final n = candles.length;
    const pad = 4.0;
    final chartW = size.width - pad * 2;
    final chartH = size.height - pad * 2;
    final barW = (chartW / n).clamp(1.0, 12.0);
    final gap = (chartW - barW * n) / (n + 1);
    for (var i = 0; i < n; i++) {
      final v = vols[i];
      if (v <= 0) continue;
      final isUp = candles[i].close >= candles[i].open;
      final color = MarketColors.forUp(isUp).withValues(alpha: 0.7);
      final x = pad + gap + (gap + barW) * i;
      final h = (v / maxV * chartH).clamp(2.0, chartH);
      final y = pad + chartH - h;
      canvas.drawRect(
        Rect.fromLTWH(x, y, barW, h),
        Paint()..color = color..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VolumeBarPainter old) => old.candles != candles;
}
