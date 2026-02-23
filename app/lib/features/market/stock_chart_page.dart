import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../trading/trading_cache.dart';
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

  /// TradingView 风格：图表优先，顶部仅 symbol + price + change%
  static const double _headerHeight = 52.0;
  static const double _tabBarHeight = 46.0;
  static const double _chartScreenRatio = 0.70;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final chartBlockHeight = screenHeight * _chartScreenRatio;
    final chartContentHeight = (chartBlockHeight - _tabBarHeight).clamp(120.0, double.infinity);
    final chartHeight = chartContentHeight * (220 / 298);
    final volumeHeight = chartContentHeight * (56 / 298);
    final timeAxisHeight = chartContentHeight * (22 / 298);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0C0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0C0E),
        foregroundColor: const Color(0xFFD4AF37),
        elevation: 0,
        titleSpacing: 0,
        title: _buildTradingViewHeader(),
      ),
      body: Column(
        children: [
          if (widget.isMockData) _buildMockBanner(),
          SizedBox(
            height: chartBlockHeight,
            child: Column(
              children: [
                TabBar(
                  controller: _tabController,
                  labelColor: const Color(0xFFD4AF37),
                  unselectedLabelColor: const Color(0xFF9CA3AF),
                  indicatorColor: const Color(0xFFD4AF37),
                  tabAlignment: TabAlignment.center,
                  tabs: const [
                    Tab(text: '分时'),
                    Tab(text: 'K线'),
                  ],
                ),
                Expanded(
                  child: _chartLoading
                      ? const Center(child: Text('Loading...', style: TextStyle(color: Color(0xFF9CA3AF))))
                      : _candlesIntraday.isEmpty && _candlesKLine.isEmpty
                          ? _buildNoDataHint(null)
                          : TabBarView(
                              controller: _tabController,
                              children: [
                                _candlesIntraday.isEmpty ? _buildNoDataHint(true) : _buildLineChart(_candlesIntraday, chartHeight, timeAxisHeight),
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
                                                  color: const Color(0xFF1A1C21),
                                                  borderRadius: BorderRadius.circular(8),
                                                  child: InkWell(
                                                    onTap: () {
                                                      _klineController.goToRealtime(_candlesKLine.length);
                                                    },
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: Padding(
                                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                      child: Text(
                                                        'Go to realtime',
                                                        style: TextStyle(color: const Color(0xFFD4AF37), fontSize: 12, fontWeight: FontWeight.w600),
                                                      ),
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
              ],
            ),
          ),
          _buildPeriodSelector(),
          if (_tabController.index == 1) _buildIndicatorSelector(),
          Expanded(
            child: _buildStatsExpansion(),
          ),
        ],
      ),
    );
  }

  /// 顶部仅：symbol（+ 可选 name）、price + change + changePercent
  Widget _buildTradingViewHeader() {
    final hasPrice = _currentPrice != null || _changePercent != null;
    return Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.symbol,
                style: const TextStyle(color: Color(0xFFE8D5A3), fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        if (hasPrice)
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (_currentPrice != null)
                Text(
                  _currentPrice!.toStringAsFixed(2),
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                ),
              if (_changePercent != null) ...[
                const SizedBox(width: 8),
                Text(
                  (_changePercent! >= 0 ? '+' : '') + _changePercent!.toStringAsFixed(2) + '%',
                  style: TextStyle(
                    color: MarketColors.forChangePercent(_changePercent!),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }

  /// 可折叠 Stats 区域（默认折叠），内容为 OHLC/成交量卡片
  bool _statsExpanded = false;

  Widget _buildStatsExpansion() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _statsExpanded = !_statsExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Text(
                    'Stats',
                    style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _statsExpanded ? Icons.expand_less : Icons.expand_more,
                    color: const Color(0xFF9CA3AF),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_statsExpanded) _buildQuoteSummaryCard(),
        ],
      ),
    );
  }

  Widget _buildMockBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.4)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: Color(0xFFD4AF37)),
          SizedBox(width: 8),
          Text('模拟数据，仅作展示', style: TextStyle(color: Color(0xFFE8D5A3), fontSize: 12)),
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
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD4AF37)),
            ),
            const SizedBox(height: 12),
            Text(
              '正在拉取${label}实时数据…',
              style: const TextStyle(color: Color(0xFFE8D5A3), fontSize: 15, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '每秒更新报价，图表每10秒刷新',
              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIndicatorSelector() {
    // [label, id, isOverlay]
    const items = [
      ['MA', 'ma', true],
      ['EMA', 'ema', true],
      ['VOL', 'vol', false],
      ['MACD', 'macd', false],
      ['RSI', 'rsi', false],
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: items.map((e) {
            final label = e[0] as String;
            final id = e[1] as String;
            final isOverlay = e[2] as bool;
            final selected = isOverlay
                ? _overlayIndicator == id
                : _subChartIndicator == id;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(label),
                selected: selected,
                onSelected: (_) {
                  setState(() {
                    if (isOverlay) {
                      _overlayIndicator = id;
                    } else {
                      _subChartIndicator = id;
                    }
                  });
                },
                selectedColor: const Color(0xFFD4AF37).withValues(alpha: 0.3),
                checkmarkColor: const Color(0xFFD4AF37),
                labelStyle: TextStyle(
                  color: selected ? const Color(0xFFD4AF37) : const Color(0xFF9CA3AF),
                  fontSize: 12,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  static const List<String> _periodOptions = ['1m', '5m', '15m', '1h', '1D'];

  Widget _buildPeriodSelector() {
    final isIntraday = _tabController.index == 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: isIntraday
              ? _periodOptions.map((p) {
                  final selected = _chartPeriod == p;
                  final label = p == '1D' ? '1D' : p;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(label),
                      selected: selected,
                      onSelected: (_) async {
                        if (_chartPeriod == p) return;
                        setState(() => _chartPeriod = p);
                        setState(() => _chartLoading = true);
                        await _loadIntraday();
                        if (mounted) setState(() => _chartLoading = false);
                      },
                      selectedColor: const Color(0xFFD4AF37).withValues(alpha: 0.3),
                      checkmarkColor: const Color(0xFFD4AF37),
                      labelStyle: TextStyle(
                        color: selected ? const Color(0xFFD4AF37) : const Color(0xFF9CA3AF),
                        fontSize: 12,
                      ),
                    ),
                  );
                }).toList()
              : ['5day', 'day', 'week', 'month', 'year'].map((t) {
                  final label = t == '5day' ? '5日' : t == 'day' ? '日K' : t == 'week' ? '周K' : t == 'month' ? '月K' : '年K';
                  final selected = _klineTimespan == t;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(label),
                      selected: selected,
                      onSelected: (_) async {
                        if (_klineTimespan == t) return;
                        setState(() => _klineTimespan = t);
                        setState(() => _chartLoading = true);
                        await _loadKLine();
                        if (mounted) setState(() => _chartLoading = false);
                      },
                      selectedColor: const Color(0xFFD4AF37).withValues(alpha: 0.3),
                      checkmarkColor: const Color(0xFFD4AF37),
                      labelStyle: TextStyle(
                        color: selected ? const Color(0xFFD4AF37) : const Color(0xFF9CA3AF),
                        fontSize: 12,
                      ),
                    ),
                  );
                }).toList(),
        ),
      ),
    );
  }

  /// OHLC 摘要卡片。数据优先级：收=实时价(WebSocket) > 分时/K线最后一根；开/高/低=分时区间或 K 线最后一根 或 当日 Snapshot/aggregates；昨收=getPreviousClose/Snapshot；量=WebSocket 累加 或 分时/K 线 或 当日 Snapshot。拿不到的字段显示 "—"（不显示 0）。
  Widget _buildQuoteSummaryCard() {
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
    final change = (displayClose != null && displayClose > 0 && _prevClose != null && _prevClose! > 0)
        ? displayClose - _prevClose!
        : null;
    int? vol;
    if (_realtimeVolume > 0) vol = _realtimeVolume;
    else if (_candlesIntraday.isNotEmpty && _candlesIntraday.any((c) => c.volume != null && (c.volume ?? 0) > 0)) {
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
    final amplitude = (high != null && high! > 0 && low != null && prev > 0)
        ? (high! - low!) / prev * 100
        : null;
    final avgPrice = (high != null && low != null && displayClose != null && (high! + low! + displayClose!) > 0)
        ? (high! + low! + displayClose!) / 3
        : null;
    // 拿不到时显示 "—"：价格/量 为 null 或 0 视为拿不到
    double? displayOpen = (open != null && open! > 0) ? open : null;
    double? displayHigh = (high != null && high! > 0) ? high : null;
    double? displayLow = (low != null && low! > 0) ? low : null;
    double? displayCloseVal = (displayClose != null && displayClose > 0) ? displayClose : null;
    double? displayPrev = (_prevClose != null && _prevClose! > 0) ? _prevClose : null;
    final hasAny = displayCloseVal != null || displayPrev != null || displayOpen != null || vol != null;
    if (!hasAny) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111215),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('OHLC', style: _summaryLabelStyle()),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _summaryItem('开', displayOpen, null),
              _summaryItem('高', displayHigh, true),
              _summaryItem('低', displayLow, false),
              _summaryItem('收', displayCloseVal, null),
              _summaryItem('昨收', displayPrev, null),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _summaryItem('涨', change, change != null ? (change! >= 0) : null, treatZeroAsMissing: false),
              _summaryItem('涨跌幅', _changePercent != null ? _changePercent! : null, _changePercent != null ? (_changePercent! >= 0) : null, isPercent: true, treatZeroAsMissing: false),
              _summaryItem('振幅', amplitude, null, isPercent: true),
              _summaryItem('均价', avgPrice, null),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('市盈率TTM', style: _summaryLabelStyle()),
                  const SizedBox(height: 2),
                  const Text('—', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('总市值', style: _summaryLabelStyle()),
                  const SizedBox(height: 2),
                  const Text('—', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              if (vol != null && vol > 0)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('成交量', style: _summaryLabelStyle()),
                    const SizedBox(height: 2),
                    Text(_formatVol(vol), style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11)),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('成交量', style: _summaryLabelStyle()),
                    const SizedBox(height: 2),
                    const Text('—', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11)),
                  ],
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('成交额', style: _summaryLabelStyle()),
                  const SizedBox(height: 2),
                  Text((turnover != null && turnover > 0) ? _formatTurnover(turnover) : '—', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('换手率', style: _summaryLabelStyle()),
                  const SizedBox(height: 2),
                  const Text('—', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatTurnover(double v) {
    if (v >= 100000000) return '${(v / 100000000).toStringAsFixed(2)}亿';
    if (v >= 10000) return '${(v / 10000).toStringAsFixed(2)}万';
    return v.toStringAsFixed(0);
  }

  TextStyle _summaryLabelStyle() => const TextStyle(color: Color(0xFF6B6B70), fontSize: 10);
  /// 拿不到或 treatZeroAsMissing 且为 0 时显示 "—"
  Widget _summaryItem(String label, double? value, bool? isUp, {bool isPercent = false, bool treatZeroAsMissing = true}) {
    final effective = (value == null || (treatZeroAsMissing && value == 0)) ? null : value;
    final color = effective == null ? MarketColors.neutral : (isUp == true ? MarketColors.up : isUp == false ? MarketColors.down : MarketColors.neutral);
    String text = effective != null
        ? (isPercent ? '${effective >= 0 ? '+' : ''}${effective.toStringAsFixed(2)}%' : effective.toStringAsFixed(2))
        : '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: _summaryLabelStyle()),
        const SizedBox(height: 2),
        Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }

  String _formatIntradayTime(double timeSec) {
    final d = DateTime.fromMillisecondsSinceEpoch((timeSec * 1000).toInt());
    if (_chartPeriod == '1D') {
      return '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    }
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildLineChart(List<ChartCandle> candles, double chartHeight, double timeAxisHeight) {
    if (candles.isEmpty) return const Center(child: Text('No chart data', style: TextStyle(color: Color(0xFF9CA3AF))));
    final closes = candles.map((c) => c.close).toList();
    double minY = closes.reduce((a, b) => a < b ? a : b);
    double maxY = closes.reduce((a, b) => a > b ? a : b);
    if (_currentPrice != null) {
      if (_currentPrice! < minY) minY = _currentPrice!;
      if (_currentPrice! > maxY) maxY = _currentPrice!;
    }
    final range = (maxY - minY).clamp(0.01, double.infinity);
    final minYPlot = minY - range * 0.05;
    final maxYPlot = maxY + range * 0.05;
    final spots = <FlSpot>[];
    for (var i = 0; i < candles.length; i++) {
      spots.add(FlSpot(i.toDouble(), candles[i].close));
    }
    if (_currentPrice != null) {
      spots.add(FlSpot(
          candles.isEmpty ? 0.0 : (candles.length - 1).toDouble() + 1,
          _currentPrice!));
    }
    if (spots.isEmpty) return const SizedBox.shrink();
    final lastClose =
        candles.isNotEmpty ? candles.last.close : _currentPrice;
    final firstOpen =
        candles.isNotEmpty ? candles.first.open : _currentPrice;
    final lineColor = (lastClose ?? firstOpen ?? 0) >= (firstOpen ?? lastClose ?? 0)
        ? MarketColors.up
        : MarketColors.down;
    final maxX = spots.length <= 1 ? 1.0 : (spots.length - 1).toDouble();
    final contentWidth = (candles.length * _candleWidth).clamp(200.0, double.infinity);
    const axisStyle = TextStyle(color: Color(0xFF6B6B70), fontSize: 10);
    final basePrice = _prevClose ?? candles.first.open;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 48,
            height: chartHeight + timeAxisHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(5, (i) {
                final v = maxYPlot - (maxYPlot - minYPlot) * i / 4;
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
                      height: chartHeight,
                      child: LineChart(
                        LineChartData(
                          minX: 0,
                          maxX: maxX,
                          minY: minYPlot,
                          maxY: maxYPlot,
                          lineBarsData: [
                            LineChartBarData(
                              spots: spots,
                              isCurved: true,
                              color: lineColor,
                              barWidth: 2,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                color: lineColor.withValues(alpha: 0.15),
                              ),
                            ),
                          ],
                          gridData: const FlGridData(show: true, drawVerticalLine: false),
                          titlesData: const FlTitlesData(
                            show: false,
                            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          borderData: FlBorderData(show: false),
                        ),
                        duration: const Duration(milliseconds: 150),
                      ),
                    ),
                    SizedBox(
                      height: timeAxisHeight,
                      width: contentWidth,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(5, (i) {
                          final idx = i == 0 ? 0 : (i * (candles.length - 1) / 4).floor().clamp(0, candles.length - 1);
                          if (idx >= candles.length) return const SizedBox.shrink();
                          return Text(_formatIntradayTime(candles[idx].time), style: axisStyle);
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
            height: chartHeight + timeAxisHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(5, (i) {
                final v = maxYPlot - (maxYPlot - minYPlot) * i / 4;
                final pct = basePrice > 0 ? (v - basePrice) / basePrice * 100 : 0.0;
                final pctStr = '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%';
                return Text(pctStr, style: axisStyle);
              }),
            ),
          ),
        ],
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
    if (candles.isEmpty) return const Center(child: Text('No chart data', style: TextStyle(color: Color(0xFF9CA3AF))));
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
    const axisStyle = TextStyle(color: Color(0xFF6B6B70), fontSize: 10);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MA5/MA10/MA20', style: _summaryLabelStyle()),
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
      ..color = const Color(0xFF2A2D34)
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
