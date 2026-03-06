import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../l10n/app_localizations.dart';
import '../trading/backend_realtime_client.dart';
import '../trading/trading_cache.dart';
import 'chart/bottom_detail_tabs.dart';
import 'chart/chart_theme.dart';
import 'chart/chart_mode_tabs.dart';
import 'chart/detail_header.dart';
import 'chart/price_section.dart';
import 'chart/intraday_chart.dart';
import 'chart/stats_bar.dart';
import 'chart/tv_chart_container.dart';
import 'chart_viewport.dart';
import 'chart_viewport_controller.dart';
import 'market_colors.dart';
import 'market_repository.dart';

/// 股票详情页切换时的内存缓存（最近 5 只），切换时先展示缓存再后台刷新
class _StockDetailCache {
  double? currentPrice;
  double? changePercent;
  double? prevClose;
  double? dayOpen;
  double? dayHigh;
  double? dayLow;
  int? dayVolume;
  String? stockName;
  List<ChartCandle> candlesIntraday = [];
  List<ChartCandle> candlesKLine = [];
  String klineInterval = '5min';
}

const int _detailCacheMaxSize = 5;
final Map<String, _StockDetailCache> _stockDetailCache = {};

void _trimDetailCache() {
  if (_stockDetailCache.length > _detailCacheMaxSize) {
    final keys = _stockDetailCache.keys.toList();
    for (var i = 0; i < keys.length - _detailCacheMaxSize; i++) {
      _stockDetailCache.remove(keys[i]);
    }
  }
}

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
    this.name,
    this.initialSnapshot,
    this.isMockData = false,
    this.symbolList,
    this.symbolIndex,
  });

  final String symbol;
  /// 股票名称（如「特斯拉」），无则用 symbol
  final String? name;
  /// 从行情列表点进时传入，用于立即展示今开/最高/最低/昨收，不等图表
  final PolygonGainer? initialSnapshot;
  /// 是否为模拟数据（列表无 API 时传入，详情页顶部显示「模拟数据」提示）
  final bool isMockData;
  /// 股票列表，传入后顶栏显示左右箭头可切换股票
  final List<String>? symbolList;
  /// 当前在 symbolList 中的索引，不传则按 symbol 查找
  final int? symbolIndex;

  @override
  State<StockChartPage> createState() => _StockChartPageState();
}

class _StockChartPageState extends State<StockChartPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _market = MarketRepository();

  List<ChartCandle> _candlesIntraday = [];
  List<ChartCandle> _candlesKLine = [];
  /// K 线请求失败时的错误信息（便于界面上直接看到原因）
  String? _klineLoadError;
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
  BackendRealtimeClient? _backendRealtime;
  StreamSubscription<PolygonTradeUpdate>? _realtimeSub;
  /// 分时周期：仅 Tab 0（1分）用折线图，固定 1min
  static const String _intradayInterval = '1min';
  /// K线周期（Tab 1-5）：5min/15min/30min/1day/1week|1month|1year
  String _klineInterval = '5min';
  /// 周K Tab 下拉选中：1week | 1month | 1year
  String _extendedKlineInterval = '1week';
  /// 主图叠加：ma / ema
  String _overlayIndicator = 'none';
  /// 副图：vol / macd / rsi
  String _subChartIndicator = 'vol';
  /// 是否显示昨收价虚线（Prev Close）
  bool _showPrevCloseLine = true;
  Timer? _quoteTimer;
  Timer? _chartTimer;
  Timer? _autoRetryTimer;
  Map<String, dynamic>? _keyRatios;
  List<Map<String, dynamic>> _dividends = [];
  List<Map<String, dynamic>> _splits = [];
  String? _stockName;
  /// 有 symbolList 时用于原地切换，避免 pushReplacement 重建页面
  late String _currentSymbol;
  int _currentIndex = 0;

  String get _effectiveSymbol => widget.symbolList != null ? _currentSymbol : widget.symbol;
  int get _effectiveIndex => widget.symbolList != null ? _currentIndex : _prevNextIndex;

  @override
  void initState() {
    super.initState();
    _currentSymbol = widget.symbol.trim().toUpperCase();
    _currentIndex = _prevNextIndex;
    _tabController = TabController(length: 6, vsync: this);
    _klineController = ChartViewportController(initialVisibleCount: 80, minVisibleCount: 30, maxVisibleCount: 400);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      final i = _tabController.index;
      if (i == 0) {
        setState(() {});
        return;
      }
      // Tab 1-5: 5分/15分/30分/日K/周K(或月K/年K) 均为 K 线图
      final interval = i == 5 ? _extendedKlineInterval : ['5min', '15min', '30min', '1day'][i - 1];
      if (_klineInterval != interval) {
        setState(() {
          _klineInterval = interval;
          _chartLoading = true;
        });
        _loadKLine().then((_) {
          if (mounted) setState(() => _chartLoading = false);
        });
      } else {
        setState(() {});
      }
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
      if (mounted) {
        setState(() => _chartLoading = false);
        _saveToCache(_effectiveSymbol);
      }
    });
    _loadKLine().then((_) {
      if (mounted) {
        setState(() => _chartLoading = false);
        _saveToCache(_effectiveSymbol);
      }
    });
    _connectRealtime();
    _startRealtimeTimers();
    _loadKeyRatios();
    _loadCompanyActions();
    if (widget.name == null) _loadStockName();
  }

  /// 无名称时通过搜索获取股票名称（如从领涨榜进入详情页）
  Future<void> _loadStockName() async {
    final sym = _effectiveSymbol.trim().toUpperCase();
    if (sym.isEmpty) return;
    final results = await _market.searchSymbols(sym);
    if (!mounted || results.isEmpty) return;
    MarketSearchResult? match;
    for (final r in results) {
      if (r.symbol.toUpperCase() == sym) {
        match = r;
        break;
      }
    }
    final m = match ?? results.first;
    if (m.name.isNotEmpty && m.name != sym) {
      setState(() => _stockName = m.name);
    }
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

  /// 原地切换：不 pushReplacement，先展示缓存再后台刷新，切换更丝滑
  void _switchToSymbolInPlace(String newSymbol) {
    final list = widget.symbolList;
    if (list == null || list.isEmpty) return;
    final newSym = newSymbol.trim().toUpperCase();
    final newIndex = list.indexWhere((s) => s.toUpperCase() == newSym);
    if (newIndex < 0) return;

    final oldSym = _currentSymbol;
    _saveToCache(oldSym);

    setState(() {
      _currentSymbol = newSym;
      _currentIndex = newIndex;
      _chartLoading = true;
      _realtimeVolume = 0;
    });

    final cached = _stockDetailCache[newSym];
    if (cached != null) {
      setState(() {
        _currentPrice = cached.currentPrice;
        _changePercent = cached.changePercent;
        _prevClose = cached.prevClose;
        _dayOpen = cached.dayOpen;
        _dayHigh = cached.dayHigh;
        _dayLow = cached.dayLow;
        _dayVolume = cached.dayVolume;
        _stockName = cached.stockName;
        _candlesIntraday = List.from(cached.candlesIntraday);
        _candlesKLine = List.from(cached.candlesKLine);
        _klineInterval = cached.klineInterval;
        _chartLoading = false;
      });
      _klineController.initFromCandlesLength(_candlesKLine.length);
    }

    _realtimeSub?.cancel();
    _realtime?.dispose();
    _backendRealtime?.dispose();
    _realtime = null;
    _backendRealtime = null;
    _realtimeSub = null;
    _connectRealtime();
    _loadQuote().then((_) {
      if (mounted) setState(() {});
    });
    _loadTodayOHLC();
    _loadIntraday().then((_) {
      if (mounted) {
        setState(() => _chartLoading = false);
        _saveToCache(newSym);
      }
    });
    _loadKLine().then((_) {
      if (mounted) {
        setState(() => _chartLoading = false);
        _saveToCache(newSym);
      }
    });
  }

  void _saveToCache(String sym) {
    if (_candlesIntraday.isEmpty && _candlesKLine.isEmpty) return;
    final c = _StockDetailCache()
      ..currentPrice = _currentPrice
      ..changePercent = _changePercent
      ..prevClose = _prevClose
      ..dayOpen = _dayOpen
      ..dayHigh = _dayHigh
      ..dayLow = _dayLow
      ..dayVolume = _dayVolume
      ..stockName = _stockName
      ..candlesIntraday = List.from(_candlesIntraday)
      ..candlesKLine = List.from(_candlesKLine)
      ..klineInterval = _klineInterval;
    _stockDetailCache[sym] = c;
    _trimDetailCache();
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
        builder: (_) => StockChartPage(
          symbol: newSymbol,
          symbolList: list,
          symbolIndex: newIndex >= 0 ? newIndex : null,
          isMockData: widget.isMockData,
        ),
      ),
    );
  }

  double? _marketCapForPriceSection() {
    final cap = _keyRatios != null && _keyRatios!['market_cap'] != null
        ? (_keyRatios!['market_cap'] as num).toDouble()
        : null;
    if (cap != null && cap > 0) return cap;
    return null;
  }

  double? _turnoverForPriceSection() {
    int? vol;
    if (_realtimeVolume > 0) vol = _realtimeVolume;
    else if (_candlesIntraday.isNotEmpty && _candlesIntraday.any((c) => (c.volume ?? 0) > 0)) {
      vol = _candlesIntraday.fold<int>(0, (s, c) => s + (c.volume ?? 0));
    } else if (_candlesKLine.isNotEmpty && _candlesKLine.last.volume != null && _candlesKLine.last.volume! > 0) {
      vol = _candlesKLine.last.volume;
    }
    if (vol == null || vol <= 0) vol = _dayVolume;
    if (vol == null || vol <= 0) return null;
    final price = _currentPrice ?? _dayOpen ?? _prevClose;
    if (price == null || price <= 0) return null;
    return vol * price;
  }

  static String _formatVol(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toString();
  }

  void _connectRealtime() {
    if (!_market.polygonAvailable) return;
    final apiKey = dotenv.env['POLYGON_API_KEY']?.trim();
    final backendUrl = dotenv.env['TONGXIN_API_URL']?.trim() ?? dotenv.env['BACKEND_URL']?.trim();
    if (apiKey != null && apiKey.isNotEmpty) {
      _backendRealtime?.dispose();
      _realtimeSub?.cancel();
      _realtime = _market.openRealtime(_effectiveSymbol);
      _realtime?.connect();
      _realtimeSub = _realtime?.stream.listen((u) {
        if (!mounted) return;
        setState(() {
          _currentPrice = u.price;
          _realtimeVolume += u.size;
        });
      });
    } else if (backendUrl != null && backendUrl.isNotEmpty) {
      _realtime?.dispose();
      _realtimeSub?.cancel();
      _backendRealtime = BackendRealtimeClient(baseUrl: backendUrl);
      _backendRealtime!.connect(symbols: [_effectiveSymbol]);
      _realtimeSub = _backendRealtime!.stream.listen((u) {
        if (!mounted) return;
        setState(() {
          _currentPrice = u.price;
          _realtimeVolume += u.size;
        });
      });
    }
  }

  @override
  void dispose() {
    _quoteTimer?.cancel();
    _chartTimer?.cancel();
    _autoRetryTimer?.cancel();
    _realtimeSub?.cancel();
    _realtime?.dispose();
    _backendRealtime?.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadQuote() async {
    final quote = await _market.getQuote(_effectiveSymbol, realtime: true);
    final prev = _market.polygonAvailable ? await _market.getPreviousClose(_effectiveSymbol) : null;
    if (!mounted) return;
    setState(() {
      if (!quote.hasError) {
        _currentPrice = quote.price > 0 ? quote.price : _currentPrice;
        _changePercent = quote.changePercent;
        if (quote.open != null && quote.open! > 0) _dayOpen = quote.open;
        if (quote.high != null && quote.high! > 0) _dayHigh = quote.high;
        if (quote.low != null && quote.low! > 0) _dayLow = quote.low;
        if (quote.volume != null && quote.volume! > 0) _dayVolume = quote.volume;
        if (quote.price > 0 && quote.change != 0) _prevClose = quote.price - quote.change;
        if (quote.name != null && quote.name!.isNotEmpty) _stockName = quote.name;
      }
      if (_prevClose == null) _prevClose = prev;
    });
  }

  /// 当日 OHLC + volume：优先 Polygon Snapshot（单标的 /v2/snapshot/.../tickers/{ticker}），
  /// 否则 Polygon aggregates(1, day, today) 取最后一根作为当日 bar
  Future<void> _loadKeyRatios() async {
    final data = await _market.getKeyRatios(_effectiveSymbol);
    if (mounted) setState(() => _keyRatios = data);
  }

  Future<void> _loadCompanyActions() async {
    final div = await _market.getDividends(_effectiveSymbol);
    final spl = await _market.getSplits(_effectiveSymbol);
    if (mounted) setState(() {
      _dividends = div;
      _splits = spl;
    });
  }

  Future<void> _loadTodayOHLC() async {
    if (!_market.polygonAvailable) return;
    final snap = await _market.getDaySnapshot(_effectiveSymbol);
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
      _effectiveSymbol,
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

  /// 分时图（仅 1 分）：折线图，当日数据
  Future<void> _loadIntraday() async {
    final sym = _effectiveSymbol.trim().toUpperCase();
    const lastDays = 1;
    const interval = '1min';
    List<ChartCandle> list = [];
    if (_market.useBackend) {
      list = await _market.getCandles(sym, interval, lastDays: lastDays);
    }
    if (list.isEmpty) {
      final toMs = DateTime.now().millisecondsSinceEpoch;
      final fromMs = toMs - lastDays * 24 * 3600 * 1000;
      final cache = TradingCache.instance;
      final cacheKey = 'polygon_aggs_${sym}_1_minute_${fromMs}_$toMs';
      final cached = await cache.getList(cacheKey, maxAge: const Duration(hours: 24));
      if (cached != null && cached.isNotEmpty) {
        for (final r in cached) {
          if (r is Map<String, dynamic>) {
            final bar = PolygonBar.fromJson(r);
            if (bar != null) list.add(ChartCandle.fromBar(bar));
          }
        }
      }
      if (_market.polygonAvailable && list.isEmpty) {
        list = await _market.getAggregates(sym, multiplier: 1, timespan: 'minute', fromMs: fromMs, toMs: toMs);
      }
      if (list.isEmpty && _market.twelveDataAvailable) {
        list = await _market.getCandles(sym, interval, lastDays: lastDays);
      }
    }
    list.sort((a, b) => a.time.compareTo(b.time));
    if (mounted) setState(() => _candlesIntraday = list);
  }

  /// Tab 0：1 分分时折线图
  Widget _buildIntradayTab(double chartHeight, double timeAxisHeight, double volumeHeight) {
    if (_candlesIntraday.isEmpty) {
      return _buildNoDataHint(true, stillLoading: _chartLoading);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: IntradayChart(
            candles: _candlesIntraday,
            prevClose: _prevClose,
            currentPrice: _currentPrice,
            chartHeight: chartHeight,
            timeAxisHeight: timeAxisHeight,
            volumeHeight: volumeHeight,
            periodLabel: '1m',
          ),
        ),
      ],
    );
  }

  /// K 线图：5分/15分/30分/日K/周K，均用蜡烛图
  Future<void> _loadKLine() async {
    final sym = _effectiveSymbol.trim().toUpperCase();
    final interval = _klineInterval;
    int? lastDays;
    if (interval == '5min') lastDays = 5;
    else if (interval == '15min') lastDays = 10;
    else if (interval == '30min') lastDays = 15;
    List<ChartCandle> list = [];
    if (mounted) setState(() => _klineLoadError = null);

    if (kDebugMode) debugPrint('StockChartPage _loadKLine: symbol=$sym interval=$interval useBackend=${_market.useBackend}');
    if (_market.useBackend) {
      list = await _market.getCandles(
        sym,
        interval,
        lastDays: lastDays,
        onError: (msg) {
          if (mounted) setState(() => _klineLoadError = msg);
        },
      );
    }
    if (list.isEmpty) {
      final toMs = DateTime.now().millisecondsSinceEpoch;
      int fromMs;
      int multiplier = 1;
      String timespan = 'minute';
      if (interval == '5min') {
        fromMs = toMs - 5 * 24 * 3600 * 1000;
        multiplier = 5;
      } else if (interval == '15min') {
        fromMs = toMs - 10 * 24 * 3600 * 1000;
        multiplier = 15;
      } else if (interval == '30min') {
        fromMs = toMs - 15 * 24 * 3600 * 1000;
        multiplier = 30;
      } else if (interval == '1week') {
        fromMs = toMs - 52 * 7 * 24 * 3600 * 1000;
        timespan = 'week';
      } else if (interval == '1month') {
        fromMs = toMs - 24 * 30 * 24 * 3600 * 1000;
        timespan = 'month';
      } else if (interval == '1year') {
        fromMs = toMs - 20 * 365 * 24 * 3600 * 1000;
        timespan = 'year';
      } else {
        fromMs = toMs - 60 * 24 * 3600 * 1000;
        timespan = 'day';
      }
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
      if (list.isEmpty && _market.polygonAvailable) {
        list = await _market.getAggregates(sym, multiplier: multiplier, timespan: timespan, fromMs: fromMs, toMs: toMs);
      }
      if (list.isEmpty && _market.twelveDataAvailable) {
        list = await _market.getCandles(sym, interval, lastDays: lastDays);
      }
    }
    if (list.isEmpty) {
      debugPrint('StockChartPage: K线无数据 symbol=$sym interval=$interval');
      if (_market.useBackend && kDebugMode) {
        debugPrint('  → 已配置后端优先，请确认：1) 后端已启动  2) TONGXIN_API_URL 可访问');
      }
    }
    if (mounted) {
      setState(() {
        _candlesKLine = list;
        _klineController.initFromCandlesLength(list.length);
      });
      if (_isKlineIntervalDayOrWeek()) _scheduleBackfillKLineTo20Years();
    }
  }

  bool _isKlineIntervalDayOrWeek() =>
      _klineInterval == '1day' || _klineInterval == '1week' || _klineInterval == '1month' || _klineInterval == '1year';

  /// 近 20 年 K 线目标：首屏显示后持续在后台补全更早数据，直到约 20 年或接口无更多数据
  static final int _kline20YearsMs = (20 * 365.25 * 24 * 3600 * 1000).round();

  void _scheduleBackfillKLineTo20Years() {
    if (!_isKlineIntervalDayOrWeek()) return;
    if (_candlesKLine.isEmpty || _klineLoadingMore) return;
    final oldestMs = (_candlesKLine.first.time * 1000).round();
    final twentyYearsAgo = DateTime.now().millisecondsSinceEpoch - _kline20YearsMs;
    if (oldestMs <= twentyYearsAgo) return;
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted || _klineLoadingMore) return;
      if (_candlesKLine.isEmpty) return;
      final earliest = (_candlesKLine.first.time * 1000).round();
      _loadKLineHistory(earliest).then((_) {
        if (mounted && _candlesKLine.isNotEmpty) _scheduleBackfillKLineTo20Years();
      });
    });
  }

  String _klineIntervalForLoadMore() => _klineInterval;

  /// 传给图表的 K 线列表：在「最新」视口且有实时价时，最后一根用实时价更新 high/low/close，使最后一根随行情波动
  List<ChartCandle> get _kLineDisplayCandles {
    if (_candlesKLine.isEmpty) return _candlesKLine;
    final price = _currentPrice;
    if (price == null || price <= 0) return _candlesKLine;
    if (!_klineController.isAtRealtime(_candlesKLine.length)) return _candlesKLine;
    final last = _candlesKLine.last;
    final high = (last.high > price ? last.high : price).toDouble();
    final low = (last.low < price ? last.low : price).toDouble();
    final merged = ChartCandle(
      time: last.time,
      open: last.open,
      high: high,
      low: low,
      close: price,
      volume: _dayVolume ?? (_realtimeVolume > 0 ? _realtimeVolume : last.volume),
    );
    return [..._candlesKLine.sublist(0, _candlesKLine.length - 1), merged];
  }

  Future<void> _loadKLineHistory(int earliestTimestampMs) async {
    if (_klineLoadingMore) return;
    if (_lastLoadedEarliestTs != null && earliestTimestampMs >= _lastLoadedEarliestTs!) return;
    setState(() => _klineLoadingMore = true);
    try {
      final beforeLen = _candlesKLine.length;
      final earliestTsBefore = beforeLen > 0 ? (_candlesKLine.first.time * 1000).round() : null;
      final list = await _market.getCandlesOlderThan(
        _effectiveSymbol,
        _klineIntervalForLoadMore(),
        olderThanMs: earliestTimestampMs,
        limit: 500,
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
        _scheduleBackfillKLineTo20Years();
      }
    } finally {
      if (mounted) setState(() => _klineLoadingMore = false);
    }
  }

  static const double _chartMinHeight = 320.0;
  /// TvChartContainer 上下内边距（缩小以增大图表可视区域）
  static const double _chartContainerPaddingV = 12.0;
  /// 分时图内部 Padding 占用的垂直空间
  static const double _intradayChartPaddingV = 10.0;
  /// 分时图上方摘要行占用的高度
  static const double _intradaySummaryRowHeight = 44.0;
  /// K 线视口额外占用（缩小以让主图+成交量占满可用高度）
  static const double _klineViewportExtraV = 24.0;
  /// 分时：主图占比提高，放大主图便于看清
  static const double _ratioChart = 250 / 320;
  static const double _ratioVolume = 48 / 320;
  static const double _ratioTimeAxis = 22 / 320;
  /// K 线：主图 92%、成交量 8%，时间轴至少 28px 确保底部日期完整显示
  static const double _ratioTimeAxisK = 28 / 376;
  static const double _ratioChartK = 0.92 * (1 - _ratioTimeAxisK);
  static const double _ratioVolumeK = 0.08 * (1 - _ratioTimeAxisK);
  static const double _ratioIntradayVolume = 48 / 320;

  @override
  Widget build(BuildContext context) {
    final changeVal = _currentPrice != null && _prevClose != null && _prevClose! > 0
        ? _currentPrice! - _prevClose!
        : null;
    return Scaffold(
      backgroundColor: ChartTheme.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenH = MediaQuery.sizeOf(context).height;
            final fixedChartHeight = (screenH * 0.45).clamp(320.0, 420.0);
            final detailPanelHeight = (screenH * 0.34).clamp(240.0, 360.0);
            final availableHeight = fixedChartHeight - _chartContainerPaddingV - _intradayChartPaddingV - 8;
            final contentHeight = availableHeight.clamp(160.0, double.infinity);
            final contentHeightIntraday = contentHeight.clamp(180.0, double.infinity);
            final contentHeightKline = (availableHeight - _klineViewportExtraV).clamp(200.0, double.infinity);
            final chartHeight = contentHeightKline * _ratioChartK;
            final volumeHeight = contentHeightKline * _ratioVolumeK;
            final timeAxisHeight = contentHeightKline * _ratioTimeAxisK;
            final chartHeightIntraday = contentHeightIntraday * _ratioChart;
            final timeAxisHeightIntraday = contentHeightIntraday * _ratioTimeAxis;
            final intradayVolumeHeight = contentHeightIntraday * _ratioIntradayVolume;

            Widget chartContent;
            if (_chartLoading) {
              chartContent = Center(
                child: Text(AppLocalizations.of(context)!.chartLoading, style: TextStyle(color: ChartTheme.textSecondary, fontSize: 13)),
              );
            } else if (_candlesIntraday.isEmpty && _candlesKLine.isEmpty) {
              chartContent = _buildEmptyStateCard();
            } else {
              chartContent = TabBarView(
                controller: _tabController,
                children: [
                  _buildIntradayTab(chartHeightIntraday, timeAxisHeightIntraday, intradayVolumeHeight),
                  _buildKlineTab(chartHeight, volumeHeight, timeAxisHeight),
                  _buildKlineTab(chartHeight, volumeHeight, timeAxisHeight),
                  _buildKlineTab(chartHeight, volumeHeight, timeAxisHeight),
                  _buildKlineTab(chartHeight, volumeHeight, timeAxisHeight),
                  _buildKlineTab(chartHeight, volumeHeight, timeAxisHeight),
                ],
              );
            }

            return SingleChildScrollView(
              padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 12),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  children: [
                    DetailHeader(
                      symbol: _effectiveSymbol,
                      name: widget.name ?? _stockName,
                      onBack: () => Navigator.of(context).maybePop(),
                      onPrev: _prevNextIndex > 0 ? _switchToPrev : null,
                      onNext: _prevNextIndex >= 0 && _prevNextIndex < _symbolListLength - 1 ? _switchToNext : null,
                    ),
                    PriceSection(
                      currentPrice: _currentPrice,
                      change: changeVal,
                      changePercent: _changePercent,
                      prevClose: _prevClose,
                      open: _dayOpen ?? (_candlesIntraday.isNotEmpty ? _candlesIntraday.first.open : null),
                      high: _dayHigh ?? (_candlesIntraday.isNotEmpty ? _candlesIntraday.map((c) => c.high).reduce((a, b) => a > b ? a : b) : null),
                      low: _dayLow ?? (_candlesIntraday.isNotEmpty ? _candlesIntraday.map((c) => c.low).reduce((a, b) => a < b ? a : b) : null),
                      turnover: _turnoverForPriceSection(),
                      marketCap: _marketCapForPriceSection(),
                      turnoverRate: _keyRatios != null && _keyRatios!['volume_turnover'] != null
                          ? (_keyRatios!['volume_turnover'] as num).toDouble() * 100
                          : null,
                      amplitude: _prevClose != null && _prevClose! > 0 && _dayHigh != null && _dayLow != null
                          ? (_dayHigh! - _dayLow!) / _prevClose! * 100
                          : null,
                    ),
                    ChartModeTabs(
                      tabIndex: _tabController.index,
                      onTabChanged: (i) => _tabController.animateTo(i),
                      isIntraday: _tabController.index == 0,
                      intradayPeriod: _intradayInterval,
                      klineTimespan: _klineInterval == '1day' ? 'day' : _klineInterval == '1week' ? 'week' : _klineInterval == '1month' ? 'month' : _klineInterval == '1year' ? 'year' : _klineInterval,
                      onIntradayPeriodChanged: (_) {},
                      onKlineTimespanChanged: (_) {},
                      extendedKlineInterval: _extendedKlineInterval,
                      onExtendedKlineChanged: (v) {
                        if (_extendedKlineInterval != v) {
                          setState(() {
                            _extendedKlineInterval = v;
                            _klineInterval = v;
                            _chartLoading = true;
                          });
                          _loadKLine().then((_) {
                            if (mounted) setState(() => _chartLoading = false);
                          });
                        }
                      },
                    ),
                    if (widget.isMockData) _buildMockBanner(),
                    TvChartContainer(
                      edgeToEdge: true,
                      padding: const EdgeInsets.fromLTRB(0, 6, 0, 16),
                      child: SizedBox(
                        height: fixedChartHeight,
                        child: ClipRect(
                          child: chartContent,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: detailPanelHeight,
                      child: BottomDetailTabs(
                        symbol: widget.symbol,
                        currentPrice: _currentPrice,
                        overlayIndicator: _overlayIndicator,
                        subChartIndicator: _subChartIndicator,
                        showPrevCloseLine: _showPrevCloseLine,
                        onOverlayChanged: (v) => setState(() => _overlayIndicator = v),
                        onSubChartChanged: (v) => setState(() => _subChartIndicator = v),
                        onShowPrevCloseLineChanged: (v) => setState(() => _showPrevCloseLine = v),
                        klineCandles: _candlesKLine,
                      ),
                    ),
                    if (_dividends.isNotEmpty || _splits.isNotEmpty) _buildCompanyActionsSection(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCompanyActionsSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(ChartTheme.pagePadding, 12, ChartTheme.pagePadding, 18),
      decoration: const BoxDecoration(
        color: ChartTheme.cardBackground,
        border: Border(top: BorderSide(color: ChartTheme.border, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppLocalizations.of(context)!.chartCompanyActions, style: TextStyle(color: ChartTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (_dividends.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${AppLocalizations.of(context)!.chartDividends}: ${_dividends.take(3).map((d) => '${d['ex_dividend_date'] ?? d['pay_date']} \$${d['cash_amount']}').join(' · ')}${_dividends.length > 3 ? ' …' : ''}',
                  style: TextStyle(color: ChartTheme.textPrimary, fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (_splits.isNotEmpty)
              Text(
                '${AppLocalizations.of(context)!.chartSplits}: ${_splits.take(3).map((s) => '${s['execution_date']} ${s['split_from']}:${s['split_to']}').join(' · ')}${_splits.length > 3 ? ' …' : ''}',
                style: TextStyle(color: ChartTheme.textPrimary, fontSize: 14),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }

  /// 美股交易时段按美东时间：9:30–16:00（EST/EDT）
  String? _statusLabel(BuildContext context) {
    final (hour, minute) = _usEasternHourMinute();
    final l10n = AppLocalizations.of(context)!;
    if (hour < 9 || (hour == 9 && minute < 30)) return l10n.chartPreMarket;
    if (hour > 16 || (hour == 16 && minute > 0)) return l10n.chartClosed;
    return l10n.chartIntraday;
  }

  /// 当前美东时间（小时、分），近似 EST/EDT（3 月第 2 个周日–11 月第 1 个周日为 EDT）
  static (int hour, int minute) _usEasternHourMinute() {
    final utc = DateTime.now().toUtc();
    final isEDT = _isUsEasternDST(utc);
    final offsetHours = isEDT ? 4 : 5;
    final eastern = utc.subtract(Duration(hours: offsetHours));
    return (eastern.hour, eastern.minute);
  }

  static bool _isUsEasternDST(DateTime utc) {
    final y = utc.year;
    final marchSecondSun = _nthSundayOfMonth(y, 3, 2);
    final novFirstSun = _nthSundayOfMonth(y, 11, 1);
    final at = DateTime.utc(y, utc.month, utc.day);
    return !at.isBefore(marchSecondSun) && at.isBefore(novFirstSun);
  }

  static DateTime _nthSundayOfMonth(int year, int month, int n) {
    var d = DateTime.utc(year, month, 1);
    var count = 0;
    while (d.month == month) {
      if (d.weekday == DateTime.sunday) {
        count++;
        if (count == n) return d;
      }
      d = d.add(const Duration(days: 1));
    }
    return DateTime.utc(year, month, 1);
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
      symbol: _effectiveSymbol,
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
      dividendYieldPercent: _keyRatios != null && _keyRatios!['dividend_yield'] != null
          ? (_keyRatios!['dividend_yield'] as num).toDouble() * 100
          : null,
      peTtm: _keyRatios != null && _keyRatios!['price_to_earnings'] != null
          ? (_keyRatios!['price_to_earnings'] as num).toDouble()
          : null,
    );
  }

  Widget _buildKlineTab(double chartHeight, double volumeHeight, double timeAxisHeight) {
    if (_candlesKLine.isEmpty) {
      return _buildNoDataHint(false, stillLoading: _chartLoading, klineError: _klineLoadError, onRetry: () {
        setState(() => _chartLoading = true);
        _loadKLine().then((_) { if (mounted) setState(() => _chartLoading = false); });
      });
    }
    return Stack(
      children: [
        ChartViewport(
          controller: _klineController,
          candles: _kLineDisplayCandles,
          onLoadMoreHistory: _loadKLineHistory,
          isLoadingMore: _klineLoadingMore,
          chartHeight: chartHeight,
          volumeHeight: volumeHeight,
          timeAxisHeight: timeAxisHeight,
          overlayIndicator: _overlayIndicator,
          subChartIndicator: _subChartIndicator,
          prevClose: _prevClose,
          currentPrice: _currentPrice,
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
                    child: Text(AppLocalizations.of(context)!.chartBackToLatest, style: TextStyle(color: ChartTheme.accentGold, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            );
          },
        ),
      ],
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
          Text(AppLocalizations.of(context)!.chartMockDataHint, style: TextStyle(color: ChartTheme.textPrimary, fontSize: 12)),
        ],
      ),
    );
  }

  /// 分时图上方摘要行：价 均 涨 涨跌幅 量 额（对齐同花顺/东方财富，数据一目了然）
  Widget _buildIntradaySummaryRow() {
    final price = _currentPrice ?? (_candlesIntraday.isNotEmpty ? _candlesIntraday.last.close : 0.0);
    final open = _dayOpen ?? (_candlesIntraday.isNotEmpty ? _candlesIntraday.first.open : null);
    final prev = _prevClose ?? open;
    double? avgPrice;
    int totalVol = 0;
    double turnover = 0;
    if (_candlesIntraday.isNotEmpty) {
      var sumV = 0.0;
      var sumVw = 0.0;
      for (final c in _candlesIntraday) {
        final v = (c.volume ?? 0).toDouble();
        totalVol += c.volume ?? 0;
        turnover += (c.close * v);
        sumV += v;
        sumVw += c.close * v;
      }
      avgPrice = sumV > 0 ? sumVw / sumV : (_candlesIntraday.map((c) => c.close).reduce((a, b) => a + b) / _candlesIntraday.length);
    }
    if (totalVol == 0) totalVol = _dayVolume ?? 0;
    final prevVal = prev ?? 0.0;
    final change = (open != null && open > 0) ? price - open : (prevVal > 0 ? price - prevVal : 0.0);
    final changePct = prevVal > 0 ? (price - prevVal) / prevVal * 100 : 0.0;
    final changeColor = (change >= 0 ? ChartTheme.up : ChartTheme.down);
    String turnStr = '—';
    if (turnover >= 10000) turnStr = '${(turnover / 10000).toStringAsFixed(2)}万';
    else if (turnover > 0) turnStr = turnover.toStringAsFixed(0);
    String volStr = '—';
    if (totalVol > 0) volStr = totalVol >= 10000 ? '${(totalVol / 10000).toStringAsFixed(2)}万' : totalVol.toString();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ChartTheme.pagePadding, vertical: 6),
      decoration: const BoxDecoration(
        color: ChartTheme.cardBackground,
        border: Border(bottom: BorderSide(color: ChartTheme.border, width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _summaryBlock(AppLocalizations.of(context)!.chartPrice, price > 0 ? ChartTheme.formatPrice(price) : '—', null),
            _summaryBlock(AppLocalizations.of(context)!.chartAvg, avgPrice != null ? ChartTheme.formatPrice(avgPrice!) : '—', null),
            _summaryBlock(AppLocalizations.of(context)!.chartChangeShort, open != null ? '${change >= 0 ? '+' : ''}${ChartTheme.formatPrice(change)}' : '—', changeColor),
            _summaryBlock(AppLocalizations.of(context)!.chartChangePercent, '${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(2)}%', changeColor),
            _summaryBlock(AppLocalizations.of(context)!.chartVol, volStr, null),
            _summaryBlock(AppLocalizations.of(context)!.chartTurnover, turnStr, null),
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

  /// 分时/K线单一为空时：加载中或暂无数据+重试
  Widget _buildNoDataHint(bool? isIntraday, {bool stillLoading = true, String? klineError, VoidCallback? onRetry}) {
    final l10n = AppLocalizations.of(context)!;
    final label = isIntraday == false ? l10n.chartKlineLabel : isIntraday == true ? l10n.chartTimeshareLabel : l10n.chartTimeshareLabel;
    final isIntradayEmpty = isIntraday == true && !stillLoading;
    final isKlineEmpty = isIntraday == false && !stillLoading;
    final content = Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (stillLoading) SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2, color: ChartTheme.accentGold)),
            if (stillLoading) const SizedBox(height: 12),
            Text(
              isIntradayEmpty ? l10n.chartNoIntradayData : (isKlineEmpty ? l10n.chartNoKlineData : l10n.chartFetchingWithLabel(label)),
              style: TextStyle(color: ChartTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            if (stillLoading) const SizedBox(height: 4),
            if (stillLoading) Text(l10n.chartQuoteRefreshHint, style: TextStyle(color: ChartTheme.textSecondary, fontSize: 11), textAlign: TextAlign.center),
            if (isIntradayEmpty) const SizedBox(height: 6),
            if (isIntradayEmpty) Text(l10n.chartOhlcHint, style: TextStyle(color: ChartTheme.textSecondary, fontSize: 12), textAlign: TextAlign.center),
            if (isKlineEmpty && klineError != null && klineError.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(l10n.chartRequestFailed(klineError), style: TextStyle(color: ChartTheme.down, fontSize: 12), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            if (isKlineEmpty) const SizedBox(height: 8),
            if (isKlineEmpty) Text(l10n.chartClickRetry, style: TextStyle(color: ChartTheme.accentGold, fontSize: 13), textAlign: TextAlign.center),
            if (isKlineEmpty) const SizedBox(height: 4),
            if (isKlineEmpty) Text(l10n.chartNoDataTroubleshoot, style: TextStyle(color: ChartTheme.textTertiary, fontSize: 11), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
    if (isKlineEmpty && onRetry != null) {
      return GestureDetector(onTap: onRetry, behavior: HitTestBehavior.opaque, child: content);
    }
    return content;
  }

  /// 分时与 K 线数据皆空时：居中空态卡片（仅 UI，不改数据逻辑）
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
            Text(
              AppLocalizations.of(context)!.chartNoData,
              style: TextStyle(color: ChartTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.chartEmptyHint,
              style: TextStyle(color: ChartTheme.textTertiary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _emptyStateButton(AppLocalizations.of(context)!.chartRetry, onPressed: () {
                  setState(() => _chartLoading = true);
                  _loadIntraday().then((_) => _loadKLine()).then((_) {
                    if (mounted) setState(() => _chartLoading = false);
                  });
                }),
                const SizedBox(width: 12),
                _emptyStateButton(AppLocalizations.of(context)!.chartSwitchDataSource, onPressed: () {}),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyStateButton(String label, {required VoidCallback onPressed}) {
    return Material(
      color: ChartTheme.surface2,
      borderRadius: BorderRadius.circular(ChartTheme.radiusButton),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(ChartTheme.radiusButton),
        hoverColor: ChartTheme.surfaceHover,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(label, style: TextStyle(color: ChartTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
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
    if (_klineInterval == '1week') {
      return '${d.year}/${d.month.toString().padLeft(2, '0')}';
    }
    if (_klineInterval == '1day') {
      return '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    }
    return '${d.month.toString().padLeft(2, '0')}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildKLineWithMaAndVolume(List<ChartCandle> candles) {
    if (candles.isEmpty) return Center(child: Text(AppLocalizations.of(context)!.chartNoChartData, style: TextStyle(color: ChartTheme.textSecondary)));
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
