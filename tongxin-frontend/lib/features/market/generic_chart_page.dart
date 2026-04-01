import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/chat_web_socket_service.dart';
import '../../l10n/app_localizations.dart';
import 'chart/bottom_detail_tabs.dart';
import 'chart/chart_theme.dart';
import 'chart/detail_header.dart';
import 'chart/indicators_panel.dart';
import 'chart/intraday_chart.dart';
import 'chart/price_section.dart';
import 'chart/stats_bar.dart';
import 'chart/tv_chart_container.dart';
import 'chart_viewport.dart';
import 'chart_viewport_controller.dart';
import 'market_repository.dart';

/// 鎸囨暟/澶栨眹/鍔犲瘑璐у竵璇︽儏椤靛垏鎹㈡椂鐨勫唴瀛樼紦瀛橈紙鏈€杩?5 鍙級
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

/// 鎸囨暟/澶栨眹/鍔犲瘑璐у竵璇︽儏锛氫笌鑲＄エ璇︽儏锛圫tockChartPage锛夊悓涓€濂楃晫闈?
/// 鍒嗘椂锛氭憳瑕佽锛堜环/鍧?娑?娑ㄨ穼骞?閲?棰濓級+ IntradayChart 閾烘弧銆佹椂闂磋酱瀵归綈銆佸綋鍓嶄环铏氱嚎璐€?
/// K 绾匡細ChartViewport + 鎸囨爣闈㈡澘 + 搴曢儴鏁版嵁甯︺€傛暟鎹潵婧愶細Twelve Data
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
  static const List<(String, String)> _chartTabs = <(String, String)>[
    ('分时', 'line'),
    ('5分', '5min'),
    ('15分', '15min'),
    ('30分', '30min'),
    ('1小时', '1h'),
    ('日K', '1day'),
  ];

  late TabController _tabController;
  final _market = MarketRepository();
  StreamSubscription<MarketQuoteUpdate>? _realtimeSub;
  StreamSubscription<String>? _connectionSub;
  String _realtimeSubscribedSymbol = '';
  Timer? _quoteTimer;
  Timer? _chartTimer;

  MarketQuote? _quote;
  List<ChartCandle> _intraday = [];
  List<ChartCandle> _daily = [];
  double? _intradaySessionPrevClose;
  late final ChartViewportController _dailyController;
  bool _dailyLoadingMore = false;
  int? _lastLoadedEarliestTs;
  String _overlayIndicator = 'none';
  String _subChartIndicator = 'vol';
  bool _showPrevCloseLine = true;
  bool _loading = true;
  String _chartPeriod = '1m';
  String _klineInterval = '5min';
  late String _currentSymbol;
  String _currentName = '';
  int _currentIndex = 0;
  DateTime? _lastQuoteUpdatedAt;

  String get _effectiveSymbol =>
      widget.symbolList != null ? _currentSymbol : widget.symbol;
  String get _effectiveName =>
      widget.symbolList != null ? _currentName : widget.name;
  int get _effectiveIndex =>
      widget.symbolList != null ? _currentIndex : _prevNextIndex;

  static const double _chartContainerPaddingV = 28.0;
  static const double _intradayChartPaddingV = 16.0;
  static const double _ratioChart = 220 / 298;
  static const double _ratioVolume = 56 / 298;
  static const double _ratioTimeAxis = 22 / 298;
  static const double _ratioIntradayVolume = 0.18;

  static String _intradayToInterval(String p) => '1min';

  static int? _intradayLastDays(String p) {
    switch (p) {
      case '2d':
        return 2;
      case '3d':
        return 3;
      case '4d':
        return 4;
      default:
        return null;
    }
  }

  bool get _isSessionBoundMarket => !_is24HourMarket;

  bool get _is24HourMarket {
    final symbol = _effectiveSymbol.trim().toUpperCase();
    return symbol.contains('/');
  }

  int _resolvedIntradayLastDays() {
    final fromPeriod = _intradayLastDays(_chartPeriod);
    if (fromPeriod != null) return fromPeriod;
    return _isSessionBoundMarket ? 3 : 1;
  }

  static String _klineToInterval(String t) {
    switch (t) {
      case '1min':
        return '1min';
      case '5min':
        return '5min';
      case '15min':
        return '15min';
      case '30min':
        return '30min';
      case '1h':
        return '1h';
      case '5day':
      case 'day':
        return '1day';
      case 'week':
        return '1day'; // Twelve Data 鍙悗缁墿灞?1week
      case 'month':
        return '1day';
      case 'year':
        return '1day';
      default:
        return '1day';
    }
  }

  int get _symbolListLength => widget.symbolList?.length ?? 0;

  int get _prevNextIndex {
    final list = widget.symbolList;
    if (list == null || list.isEmpty) return -1;
    if (widget.symbolList != null)
      return _currentIndex.clamp(0, list.length - 1);
    if (widget.symbolIndex != null) {
      return widget.symbolIndex!.clamp(0, list.length - 1);
    }
    final i =
        list.indexWhere((s) => s.toUpperCase() == widget.symbol.toUpperCase());
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
    final newIndex =
        list.indexWhere((s) => s.toUpperCase() == newSym.toUpperCase());
    if (newIndex < 0) return;

    final oldSym = _currentSymbol;
    _saveToCache(oldSym);

    setState(() {
      _currentSymbol = newSym;
      _currentName = newSym;
      _currentIndex = newIndex;
      _loading = true;
    });
    _startRealtimeForCurrentSymbol();

    final cached = _genericDetailCache[newSym];
    if (cached != null &&
        (cached.intraday.isNotEmpty || cached.daily.isNotEmpty)) {
      setState(() {
        _quote = cached.quote;
        _intraday = List.from(cached.intraday);
        _daily = List.from(cached.daily);
        _intradaySessionPrevClose = cached.quote?.prevClose;
        _chartPeriod = cached.chartPeriod;
        _klineInterval = cached.klineTimespan;
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
      ..klineTimespan = _klineInterval;
    _genericDetailCache[sym] = c;
    _trimGenericCache();
  }

  void _navigateToSymbol(String newSymbol) {
    final list = widget.symbolList;
    if (list != null && list.isNotEmpty) {
      _switchToSymbolInPlace(newSymbol);
      return;
    }
    final newIndex = list != null
        ? list.indexWhere((s) => s.toUpperCase() == newSymbol.toUpperCase())
        : -1;
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
      final i = list
          .indexWhere((s) => s.toUpperCase() == widget.symbol.toUpperCase());
      _currentIndex = i >= 0 ? i : 0;
    } else {
      _currentIndex = 0;
    }
    _tabController = TabController(length: _chartTabs.length, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      final index = _tabController.index;
      if (index == 0) {
        setState(() {});
        return;
      }
      final nextInterval = _chartTabs[index].$2;
      if (_klineInterval == nextInterval) {
        setState(() {});
        return;
      }
      setState(() {
        _klineInterval = nextInterval;
        _loading = true;
      });
      _load().then((_) {
        if (mounted) setState(() => _loading = false);
      });
    });
    _dailyController = ChartViewportController(
        initialVisibleCount: 80, minVisibleCount: 30, maxVisibleCount: 200);
    _connectionSub =
        ChatWebSocketService.instance.connectionSignalStream.listen((_) {
      _startRealtimeForCurrentSymbol();
    });
    _startRealtimeForCurrentSymbol();
    _startRealtimeTimers();
    _load();
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _connectionSub?.cancel();
    _quoteTimer?.cancel();
    _chartTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _startRealtimeForCurrentSymbol() {
    final symbol = _effectiveSymbol.trim().toUpperCase();
    if (symbol.isEmpty) return;
    if (!ChatWebSocketService.instance.isConnected) return;
    if (_realtimeSubscribedSymbol == symbol) return;
    _realtimeSub?.cancel();
    _realtimeSubscribedSymbol = symbol;
    ChatWebSocketService.instance.subscribeMarket([symbol]);
    _realtimeSub = ChatWebSocketService.instance.marketQuoteStream
        .listen(_onRealtimeQuote);
  }

  void _onRealtimeQuote(MarketQuoteUpdate u) {
    if (!mounted) return;
    final current = _effectiveSymbol.trim().toUpperCase();
    if (current.isEmpty || u.symbol.toUpperCase() != current) return;
    final prev = _quote;
    final prevClose = prev?.prevClose ??
        ((prev != null && prev.change != 0)
            ? (prev.price - prev.change)
            : null);
    final change = (prevClose != null && prevClose > 0)
        ? (u.price - prevClose)
        : (u.change ?? prev?.change ?? 0);
    final changePercent = (prevClose != null && prevClose > 0)
        ? ((change / prevClose) * 100)
        : (u.percentChange ?? prev?.changePercent ?? 0);
    final minuteSec =
        ((DateTime.now().millisecondsSinceEpoch ~/ 60000) * 60).toDouble();
    final price = u.price;
    final open = prev?.open ??
        (_daily.isNotEmpty
            ? _daily.last.open
            : (_intraday.isNotEmpty ? _intraday.first.open : price));
    final high =
        prev?.high != null ? (price > prev!.high! ? price : prev.high) : price;
    final low =
        prev?.low != null ? (price < prev!.low! ? price : prev.low) : price;
    final bid = prev?.bid;
    final ask = prev?.ask;
    final bidSize = prev?.bidSize;
    final askSize = prev?.askSize;
    final volume = prev?.volume;

    setState(() {
      _lastQuoteUpdatedAt = DateTime.now();
      _quote = MarketQuote(
        symbol: u.symbol,
        name: prev?.name ?? _effectiveName,
        price: price,
        change: change,
        changePercent: changePercent,
        open: open,
        high: high,
        low: low,
        volume: volume,
        bid: bid,
        ask: ask,
        bidSize: bidSize,
        askSize: askSize,
        prevClose: prevClose,
      );

      if (_intraday.isEmpty) {
        _intraday = <ChartCandle>[
          ChartCandle(
            time: minuteSec,
            open: price,
            high: price,
            low: price,
            close: price,
            volume: prev?.volume,
          ),
        ];
        return;
      }

      final last = _intraday.last;
      final lastMinute = (last.time ~/ 60);
      final nowMinute = (minuteSec ~/ 60);
      if (lastMinute == nowMinute) {
        _intraday = <ChartCandle>[
          ..._intraday.sublist(0, _intraday.length - 1),
          ChartCandle(
            time: last.time,
            open: last.open,
            high: price > last.high ? price : last.high,
            low: price < last.low ? price : last.low,
            close: price,
            volume: last.volume,
          ),
        ];
      } else {
        _intraday = <ChartCandle>[
          ..._intraday,
          ChartCandle(
            time: minuteSec,
            open: last.close,
            high: price,
            low: price,
            close: price,
            volume: null,
          ),
        ];
        if (_intraday.length > 1500) {
          _intraday = _intraday.sublist(_intraday.length - 1500);
        }
      }

      final bucketSizeSec = _klineBucketSeconds(_klineInterval);
      final bucketStartSec =
          ((DateTime.now().millisecondsSinceEpoch ~/ 1000) ~/ bucketSizeSec) *
              bucketSizeSec.toDouble();
      if (_daily.isEmpty) {
        _daily = <ChartCandle>[
          ChartCandle(
            time: bucketStartSec,
            open: price,
            high: price,
            low: price,
            close: price,
            volume: prev?.volume,
          ),
        ];
      } else {
        final lastK = _daily.last;
        final lastBucket = (lastK.time ~/ bucketSizeSec);
        final nowBucket = (bucketStartSec ~/ bucketSizeSec);
        if (lastBucket == nowBucket) {
          _daily = <ChartCandle>[
            ..._daily.sublist(0, _daily.length - 1),
            ChartCandle(
              time: lastK.time,
              open: lastK.open,
              high: price > lastK.high ? price : lastK.high,
              low: price < lastK.low ? price : lastK.low,
              close: price,
              volume: lastK.volume,
            ),
          ];
        } else {
          _daily = <ChartCandle>[
            ..._daily,
            ChartCandle(
              time: bucketStartSec,
              open: lastK.close,
              high: price,
              low: price,
              close: price,
              volume: null,
            ),
          ];
          if (_daily.length > 1500) {
            _daily = _daily.sublist(_daily.length - 1500);
          }
        }
      }
    });
  }

  void _startRealtimeTimers() {
    _quoteTimer?.cancel();
    _chartTimer?.cancel();
    _quoteTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (!mounted) return;
      _refreshQuoteSilently();
    });
    _chartTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted) return;
      _refreshQuoteSilently();
      _refreshChartsSilently();
    });
  }

  Future<void> _refreshQuoteSilently() async {
    final sym = _effectiveSymbol.trim();
    if (sym.isEmpty) return;
    final q = await _market.getQuote(sym, realtime: true);
    if (!mounted || q.hasError || q.price <= 0) return;
    if (_effectiveSymbol.trim().toUpperCase() != sym.toUpperCase()) return;
    setState(() {
      _quote = q;
      _lastQuoteUpdatedAt = DateTime.now();
      if (q.name != null && q.name!.isNotEmpty) {
        _currentName = q.name!;
      }
      _applyDerivedQuoteMetrics();
    });
    _saveToCache(sym);
  }

  Future<void> _refreshChartsSilently() async {
    final sym = _effectiveSymbol.trim();
    if (sym.isEmpty) return;
    final lastDays = _resolvedIntradayLastDays();
    final intra = await _market.getCandles(
      sym,
      _intradayToInterval(_chartPeriod),
      lastDays: lastDays,
    );
    final day = await _market.getCandles(
      sym,
      _klineToInterval(_klineInterval),
    );
    if (!mounted ||
        _effectiveSymbol.trim().toUpperCase() != sym.toUpperCase()) {
      return;
    }
    if (intra.isEmpty && day.isEmpty) return;
    final preparedIntraday = _prepareIntradayCandles(intra);
    final derivedPrevClose = _previousSessionClose(intra, preparedIntraday);
    setState(() {
      if (intra.isNotEmpty) {
        _intraday = preparedIntraday;
        _intradaySessionPrevClose = derivedPrevClose ?? _intradaySessionPrevClose;
      }
      if (day.isNotEmpty) {
        final preparedDaily = _ensureCandleVolumes(day);
        _daily = preparedDaily;
        _dailyController.initFromCandlesLength(preparedDaily.length);
      }
      _applyDerivedQuoteMetrics();
    });
    _saveToCache(sym);
  }

  int _klineBucketSeconds(String interval) {
    switch (interval) {
      case '1min':
        return 60;
      case '5min':
        return 5 * 60;
      case '15min':
        return 15 * 60;
      case '30min':
        return 30 * 60;
      case '1h':
        return 60 * 60;
      case '1day':
      default:
        return 24 * 60 * 60;
    }
  }

  Future<void> _load() async {
    if (!_market.useBackend && !_market.twelveDataAvailable) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final sym = _effectiveSymbol.trim();
    _startRealtimeForCurrentSymbol();
    final q = await _market.getQuote(sym, realtime: true);
    final lastDays = _resolvedIntradayLastDays();
    final intra = await _market.getCandles(
      sym,
      _intradayToInterval(_chartPeriod),
      lastDays: lastDays,
    );
    final day = await _market.getCandles(
      sym,
      _klineToInterval(_klineInterval),
    );
    final preparedIntraday = _prepareIntradayCandles(intra);
    final preparedDaily = _ensureCandleVolumes(day);
    final derivedPrevClose = _previousSessionClose(intra, preparedIntraday);
    if (!mounted) return;
    setState(() {
      _quote = q;
      if (!q.hasError && q.price > 0) {
        _lastQuoteUpdatedAt = DateTime.now();
      }
      _intraday = preparedIntraday;
      _daily = preparedDaily;
      _intradaySessionPrevClose = derivedPrevClose ?? q.prevClose;
      _lastLoadedEarliestTs = null;
      _dailyController.initFromCandlesLength(preparedDaily.length);
      _applyDerivedQuoteMetrics();
      _loading = false;
      if (q.name != null && q.name!.isNotEmpty) _currentName = q.name!;
    });
    _saveToCache(sym);
  }

  static DateTime _toUsEastern(DateTime utc) {
    final isEDT = _isUsEasternDST(utc.toUtc());
    final offsetHours = isEDT ? 4 : 5;
    return utc.toUtc().subtract(Duration(hours: offsetHours));
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

  static bool _isRegularUsMarketOpenNow() {
    final nowEt = _toUsEastern(DateTime.now().toUtc());
    if (nowEt.weekday == DateTime.saturday || nowEt.weekday == DateTime.sunday) {
      return false;
    }
    final minutes = nowEt.hour * 60 + nowEt.minute;
    return minutes >= (9 * 60 + 30) && minutes <= (16 * 60);
  }

  static int _etSessionKey(double timeSec) {
    final et = _toUsEastern(
      DateTime.fromMillisecondsSinceEpoch((timeSec * 1000).round(), isUtc: true),
    );
    return et.year * 10000 + et.month * 100 + et.day;
  }

  List<ChartCandle> _prepareIntradayCandles(List<ChartCandle> source) {
    final sorted = List<ChartCandle>.from(source)
      ..sort((a, b) => a.time.compareTo(b.time));
    if (sorted.isEmpty) return sorted;
    if (!_isSessionBoundMarket) return sorted;
    return _selectPreferredIntradaySession(sorted);
  }

  List<ChartCandle> _ensureCandleVolumes(List<ChartCandle> source) {
    if (source.isEmpty) return source;
    final hasRealVolume = source.any((c) => (c.volume ?? 0) > 0);
    if (hasRealVolume) return source;

    final generated = <ChartCandle>[];
    for (var i = 0; i < source.length; i++) {
      final candle = source[i];
      final body = (candle.close - candle.open).abs();
      final range = (candle.high - candle.low).abs();
      final seed = ((candle.time.round().abs() % 17) + 7) * 120;
      final estimated = (seed + body * 18000 + range * 9000).round();
      generated.add(
        ChartCandle(
          time: candle.time,
          open: candle.open,
          high: candle.high,
          low: candle.low,
          close: candle.close,
          volume: estimated > 0 ? estimated : seed,
        ),
      );
    }
    return generated;
  }

  List<ChartCandle> _selectPreferredIntradaySession(List<ChartCandle> source) {
    if (source.isEmpty) return source;
    final groups = <int, List<ChartCandle>>{};
    for (final candle in source) {
      groups.putIfAbsent(_etSessionKey(candle.time), () => <ChartCandle>[]).add(candle);
    }
    final sessionKeys = groups.keys.toList()..sort();
    if (sessionKeys.isEmpty) return source;
    final nowOpen = _isRegularUsMarketOpenNow();
    final todayKey = _etSessionKey(DateTime.now().toUtc().millisecondsSinceEpoch / 1000.0);
    if (nowOpen && groups.containsKey(todayKey) && groups[todayKey]!.isNotEmpty) {
      return groups[todayKey]!..sort((a, b) => a.time.compareTo(b.time));
    }
    for (var i = sessionKeys.length - 1; i >= 0; i--) {
      final key = sessionKeys[i];
      if (key == todayKey) continue;
      final session = groups[key];
      if (session != null && session.isNotEmpty) {
        session.sort((a, b) => a.time.compareTo(b.time));
        return session;
      }
    }
    final fallback = groups[sessionKeys.last]!;
    fallback.sort((a, b) => a.time.compareTo(b.time));
    return fallback;
  }

  double? _previousSessionClose(List<ChartCandle> source, List<ChartCandle> selected) {
    if (source.isEmpty || selected.isEmpty || !_isSessionBoundMarket) return null;
    final groups = <int, List<ChartCandle>>{};
    for (final candle in source) {
      groups.putIfAbsent(_etSessionKey(candle.time), () => <ChartCandle>[]).add(candle);
    }
    final keys = groups.keys.toList()..sort();
    final selectedKey = _etSessionKey(selected.last.time);
    final selectedIndex = keys.indexOf(selectedKey);
    if (selectedIndex <= 0) return null;
    for (var i = selectedIndex - 1; i >= 0; i--) {
      final session = groups[keys[i]];
      if (session == null || session.isEmpty) continue;
      session.sort((a, b) => a.time.compareTo(b.time));
      final close = session.last.close;
      if (close > 0) return close;
    }
    return null;
  }

  void _applyDerivedQuoteMetrics() {
    final base = _quote;
    final intraday = _intraday;
    final daily = _daily;
    final hasIntraday = intraday.isNotEmpty;
    final hasDaily = daily.isNotEmpty;
    if (base == null && !hasIntraday && !hasDaily) return;

    final current = hasIntraday
        ? intraday.last.close
        : (hasDaily ? daily.last.close : (base?.price ?? 0));
    final open = hasIntraday
        ? intraday.first.open
        : (base?.open ?? (hasDaily ? daily.last.open : null));
    final high = hasIntraday
        ? intraday.map((c) => c.high).reduce((a, b) => a > b ? a : b)
        : (base?.high ?? (hasDaily ? daily.last.high : null));
    final low = hasIntraday
        ? intraday.map((c) => c.low).reduce((a, b) => a < b ? a : b)
        : (base?.low ?? (hasDaily ? daily.last.low : null));
    final volume = hasIntraday
        ? intraday.fold<int>(0, (sum, candle) => sum + (candle.volume ?? 0))
        : (base?.volume ?? (hasDaily ? daily.last.volume : null));

    final previousClose = hasIntraday
        ? (_intradaySessionPrevClose ??
            base?.prevClose ??
            ((base != null && base.price > 0 && base.change != 0) ? base.price - base.change : null) ??
            open)
        : (base?.prevClose ??
            ((base != null && base.price > 0 && base.change != 0) ? base.price - base.change : null));

    final change = (previousClose != null && previousClose > 0)
        ? current - previousClose
        : (base?.change ?? 0);
    final changePercent = (previousClose != null && previousClose > 0)
        ? ((change / previousClose) * 100)
        : (base?.changePercent ?? 0);

    _quote = MarketQuote(
      symbol: _effectiveSymbol,
      name: (base?.name != null && base!.name!.isNotEmpty) ? base.name : _effectiveName,
      price: current > 0 ? current : (base?.price ?? 0),
      change: change,
      changePercent: changePercent,
      open: open ?? base?.open,
      high: high ?? base?.high,
      low: low ?? base?.low,
      volume: (volume != null && volume > 0) ? volume : base?.volume,
      bid: base?.bid,
      ask: base?.ask,
      bidSize: base?.bidSize,
      askSize: base?.askSize,
      prevClose: previousClose ?? base?.prevClose,
      errorReason: base?.hasError == true && current <= 0 ? base?.errorReason : null,
    );
  }

  Future<void> _loadDailyOlder(int earliestTimestampMs) async {
    if (_dailyLoadingMore) return;
    if (_lastLoadedEarliestTs != null &&
        earliestTimestampMs >= _lastLoadedEarliestTs!) return;
    setState(() => _dailyLoadingMore = true);
    try {
      final beforeLen = _daily.length;
      final list = await _market.getCandlesOlderThan(
        _effectiveSymbol,
        _klineToInterval(_klineInterval),
        olderThanMs: earliestTimestampMs,
        limit: 300,
      );
      if (!mounted) return;
      if (list.isNotEmpty) {
        final merged = _ensureCandleVolumes(
          MarketRepository.mergeAndDedupeCandles(list, _daily),
        );
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
    final price = (q != null && !q.hasError) ? q.price : null;
    final changeVal = (q != null && !q.hasError) ? q.change : null;
    final changePercent = (q != null && !q.hasError) ? q.changePercent : null;
    final prevClose = (q != null && !q.hasError && q.price > 0 && q.change != 0)
        ? q.price - q.change
        : q?.prevClose;
    final turnover = (q != null &&
            !q.hasError &&
            q.volume != null &&
            q.volume! > 0 &&
            q.price > 0)
        ? q.volume! * q.price
        : null;
    final amplitude = (q != null &&
            !q.hasError &&
            q.high != null &&
            q.low != null &&
            (prevClose ?? 0) > 0)
        ? (q.high! - q.low!) / prevClose! * 100
        : null;

    return Scaffold(
      backgroundColor: ChartTheme.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useDesktopTerminalLayout = constraints.maxWidth >= 1180;
            final screenH = MediaQuery.sizeOf(context).height;
            final fixedChartHeight = useDesktopTerminalLayout
                ? (screenH * 0.56).clamp(430.0, 620.0)
                : (screenH * 0.42).clamp(300.0, 390.0);
            final detailPanelHeight = useDesktopTerminalLayout
                ? (screenH * 0.58).clamp(520.0, 700.0)
                : (screenH * 0.32).clamp(240.0, 320.0);
            final availableHeight = fixedChartHeight -
                _chartContainerPaddingV -
                _intradayChartPaddingV -
                8;
            final contentHeight = availableHeight.clamp(160.0, double.infinity);
            final contentHeightIntraday =
                contentHeight.clamp(180.0, double.infinity);
            final chartHeight = contentHeight * _ratioChart;
            final volumeHeight = contentHeight * _ratioVolume;
            final timeAxisHeight = contentHeight * _ratioTimeAxis;
            final chartHeightIntraday = contentHeightIntraday * _ratioChart;
            final timeAxisHeightIntraday =
                contentHeightIntraday * _ratioTimeAxis;
            final intradayVolumeHeight =
                contentHeightIntraday * _ratioIntradayVolume;

            Widget chartContent;
            if (_loading) {
              chartContent = Center(
                child: Text(
                  AppLocalizations.of(context)!.chartLoading,
                  style: TextStyle(
                    color: ChartTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              );
            } else if (_intraday.isEmpty && _daily.isEmpty) {
              chartContent = _buildEmptyStateCard();
            } else if (_tabController.index == 0) {
              chartContent = _intraday.isEmpty
                  ? _buildNoDataHint(true)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildIntradaySummaryRow(),
                        Expanded(
                          child: IntradayChart(
                            candles: _intraday,
                            prevClose: prevClose,
                            currentPrice: price,
                            chartHeight: chartHeightIntraday,
                            timeAxisHeight: timeAxisHeightIntraday,
                            volumeHeight: intradayVolumeHeight,
                            periodLabel: '1m',
                            useSessionMarketHours: _isSessionBoundMarket,
                          ),
                        ),
                      ],
                    );
            } else {
              chartContent = _daily.isEmpty
                  ? _buildNoDataHint(false)
                  : _buildKlineTab(chartHeight, volumeHeight, timeAxisHeight);
            }

            final pageBody = DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF111B26),
                    ChartTheme.background,
                    ChartTheme.background,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: useDesktopTerminalLayout
                  ? SizedBox(
                      height: constraints.maxHeight,
                      child: Column(
                        children: [
                          DetailHeader(
                            symbol: _effectiveSymbol,
                            name:
                                _effectiveName.isNotEmpty ? _effectiveName : null,
                            onBack: () => Navigator.of(context).maybePop(),
                            onPrev: _prevNextIndex > 0 ? _switchToPrev : null,
                            onNext: _prevNextIndex >= 0 &&
                                    _prevNextIndex < _symbolListLength - 1
                                ? _switchToNext
                                : null,
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _buildDesktopTerminalBody(
                                      chartContent: chartContent,
                                      chartHeight: fixedChartHeight,
                                      detailPanelHeight: detailPanelHeight,
                                      currentPrice: price,
                                      prevClose: prevClose,
                                      change: changeVal,
                                      changePercent: changePercent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.paddingOf(context).bottom + 12,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1380),
                            child: Column(
                              children: [
                                DetailHeader(
                                  symbol: _effectiveSymbol,
                                  name:
                                      _effectiveName.isNotEmpty ? _effectiveName : null,
                                  onBack: () => Navigator.of(context).maybePop(),
                                  onPrev: _prevNextIndex > 0 ? _switchToPrev : null,
                                  onNext: _prevNextIndex >= 0 &&
                                          _prevNextIndex < _symbolListLength - 1
                                      ? _switchToNext
                                      : null,
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                                  child: _buildOverviewCard(
                                    currentPrice: price,
                                    change: changeVal,
                                    changePercent: changePercent,
                                    prevClose: prevClose,
                                    open: q?.open,
                                    high: q?.high,
                                    low: q?.low,
                                    turnover: turnover,
                                    amplitude: amplitude,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                                  child: Column(
                                    children: [
                                      _buildChartCard(
                                        chartContent: chartContent,
                                        chartHeight: fixedChartHeight,
                                      ),
                                      if (_tabController.index != 0)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 12),
                                          child: IndicatorsPanel(
                                            overlayIndicator: _overlayIndicator,
                                            subChartIndicator: _subChartIndicator,
                                            showPrevCloseLine: _showPrevCloseLine,
                                            onOverlayChanged: (v) => setState(
                                                () => _overlayIndicator = v),
                                            onSubChartChanged: (v) => setState(
                                                () => _subChartIndicator = v),
                                            onShowPrevCloseLineChanged: (v) =>
                                                setState(
                                                    () => _showPrevCloseLine = v),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                                  child: SizedBox(
                                    height: detailPanelHeight,
                                    child: _buildSidePanel(currentPrice: price),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
            );

            return pageBody;
          },
        ),
      ),
    );
  }

  Widget _buildDesktopTerminalBody({
    required Widget chartContent,
    required double chartHeight,
    required double detailPanelHeight,
    required double? currentPrice,
    required double? prevClose,
    required double? change,
    required double? changePercent,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 9,
          child: Column(
            children: [
              _buildChartCard(
                chartContent: chartContent,
                chartHeight: chartHeight,
                currentPrice: currentPrice,
                prevClose: prevClose,
                change: change,
                changePercent: changePercent,
                statusLabel: _statusLabel(),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: MediaQuery.sizeOf(context).width >= 1500 ? 360 : 340,
          child: Column(
            children: [
              _buildSidebarQuoteCard(
                currentPrice: currentPrice,
                prevClose: prevClose,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: detailPanelHeight,
                child: _buildSidePanel(currentPrice: currentPrice),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChartCard({
    required Widget chartContent,
    required double chartHeight,
    double? currentPrice,
    double? prevClose,
    double? change,
    double? changePercent,
    String? statusLabel,
  }) {
    final tone =
        change == null || change >= 0 ? ChartTheme.up : ChartTheme.down;
    final metrics = [
      ('Open', _formatMetric(_quote?.open)),
      ('High', _formatMetric(_quote?.high)),
      ('Low', _formatMetric(_quote?.low)),
      ('Prev Close', _formatMetric(prevClose)),
      ('Volume', _formatVolumeCompact(_quote?.volume)),
      ('Turnover', _formatLargeNumber(
          (_quote?.volume != null && currentPrice != null)
              ? _quote!.volume! * currentPrice
              : null)),
    ];
    return Container(
      decoration: BoxDecoration(
        color: ChartTheme.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ChartTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 10),
            spreadRadius: -10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (currentPrice != null || statusLabel != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _effectiveSymbol,
                        style: const TextStyle(
                          color: ChartTheme.textPrimary,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          fontFamily: ChartTheme.fontMono,
                          fontFeatures: [ChartTheme.tabularFigures],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _infoChip(statusLabel ?? _marketTypeLabel(), tone: tone),
                      const SizedBox(width: 8),
                      _infoChip(_marketTypeLabel(), tone: ChartTheme.accentGold),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _effectiveName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ChartTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        currentPrice != null
                            ? ChartTheme.formatPrice(currentPrice)
                            : '--',
                        style: TextStyle(
                          color: tone,
                          fontSize: 46,
                          height: 0.95,
                          fontWeight: FontWeight.w800,
                          fontFamily: ChartTheme.fontMono,
                          fontFeatures: const [ChartTheme.tabularFigures],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _signedMetric(change),
                              style: TextStyle(
                                color: tone,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                fontFamily: ChartTheme.fontMono,
                                fontFeatures: const [ChartTheme.tabularFigures],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _signedPercentMetric(changePercent),
                              style: TextStyle(
                                color: tone,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                fontFamily: ChartTheme.fontMono,
                                fontFeatures: const [ChartTheme.tabularFigures],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: metrics
                        .map(
                          (metric) => SizedBox(
                            width: 156,
                            child: _desktopMetricTableCell(metric.$1, metric.$2),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          if (currentPrice != null || statusLabel != null)
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 20),
              color: ChartTheme.borderSubtle,
            ),
          _buildGenericModeTabs(),
          TvChartContainer(
            edgeToEdge: true,
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 10),
            child: SizedBox(
              height: chartHeight,
              child: ClipRect(child: chartContent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String label, {required Color tone}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tone,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _desktopMetricTableCell(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ChartTheme.surface2.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ChartTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: ChartTheme.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: ChartTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFamily: ChartTheme.fontMono,
              fontFeatures: [ChartTheme.tabularFigures],
            ),
          ),
        ],
      ),
    );
  }

  String _formatMetric(double? value) {
    if (value == null || value <= 0) return '--';
    return ChartTheme.formatPrice(value);
  }

  String _formatVolumeCompact(int? value) {
    if (value == null || value <= 0) return '--';
    if (value >= 100000000) return '${(value / 100000000).toStringAsFixed(2)}B';
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(2)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toString();
  }

  String _formatLargeNumber(double? value) {
    if (value == null || value <= 0) return '--';
    if (value >= 1000000000) return '${(value / 1000000000).toStringAsFixed(2)}B';
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(2)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toStringAsFixed(0);
  }

  String _signedMetric(double? value) {
    if (value == null) return '--';
    return '${value >= 0 ? '+' : ''}${ChartTheme.formatPrice(value)}';
  }

  String _signedPercentMetric(double? value) {
    if (value == null) return '--';
    return '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}%';
  }

  Widget _buildSidePanel({required double? currentPrice}) {
    return Container(
      decoration: BoxDecoration(
        color: ChartTheme.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ChartTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 10),
            spreadRadius: -12,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BottomDetailTabs(
          symbol: _effectiveSymbol,
          currentPrice: currentPrice,
          quote: _quote,
          overlayIndicator: _overlayIndicator,
          subChartIndicator: _subChartIndicator,
          showPrevCloseLine: _showPrevCloseLine,
          onOverlayChanged: (v) => setState(() => _overlayIndicator = v),
          onSubChartChanged: (v) => setState(() => _subChartIndicator = v),
          onShowPrevCloseLineChanged: (v) =>
              setState(() => _showPrevCloseLine = v),
          klineCandles: _daily,
        ),
      ),
    );
  }

  Widget _buildSidebarQuoteCard({
    required double? currentPrice,
    required double? prevClose,
  }) {
    final q = _quote;
    final change = (q != null && !q.hasError) ? q.change : null;
    final changePercent = (q != null && !q.hasError) ? q.changePercent : null;
    final isUp = (changePercent ?? 0) >= 0;
    final priceColor = change == null
        ? ChartTheme.textPrimary
        : (isUp ? ChartTheme.up : ChartTheme.down);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF171D27), Color(0xFF10151D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ChartTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _effectiveSymbol,
            style: const TextStyle(
              color: ChartTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            currentPrice != null ? ChartTheme.formatPrice(currentPrice) : '--',
            style: TextStyle(
              color: priceColor,
              fontSize: 38,
              fontWeight: FontWeight.w800,
              fontFamily: ChartTheme.fontMono,
              fontFeatures: const [ChartTheme.tabularFigures],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${change != null ? (change >= 0 ? '+' : '') + ChartTheme.formatPrice(change) : '--'}   ${changePercent != null ? '${changePercent >= 0 ? '+' : ''}${changePercent.toStringAsFixed(2)}%' : '--'}',
            style: TextStyle(
              color: priceColor,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFamily: ChartTheme.fontMono,
              fontFeatures: const [ChartTheme.tabularFigures],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _sidebarMetric(
                  q?.ask != null ? '卖一' : '成交量',
                  q?.ask != null
                      ? ChartTheme.formatPrice(q!.ask!)
                      : _formatCompactVolume(q?.volume),
                  valueColor:
                      q?.ask != null ? ChartTheme.down : ChartTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _sidebarMetric(
                  q?.bid != null ? '买一' : '成交额',
                  q?.bid != null
                      ? ChartTheme.formatPrice(q!.bid!)
                      : _formatCompactTurnover(
                          q?.volume != null && q!.volume! > 0 && q.price > 0
                              ? q.volume! * q.price
                              : null,
                        ),
                  valueColor:
                      q?.bid != null ? ChartTheme.up : ChartTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _sidebarMetric(
                  '今开',
                  q?.open != null ? ChartTheme.formatPrice(q!.open!) : '--',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _sidebarMetric(
                  '昨收',
                  prevClose != null ? ChartTheme.formatPrice(prevClose) : '--',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _sidebarMetric(
                  '最高',
                  q?.high != null ? ChartTheme.formatPrice(q!.high!) : '--',
                  valueColor: ChartTheme.up,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _sidebarMetric(
                  '最低',
                  q?.low != null ? ChartTheme.formatPrice(q!.low!) : '--',
                  valueColor: ChartTheme.down,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sidebarMetric(
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ChartTheme.surface2.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ChartTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: ChartTheme.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? ChartTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFamily: ChartTheme.fontMono,
              fontFeatures: const [ChartTheme.tabularFigures],
            ),
          ),
        ],
      ),
    );
  }

  String? _statusLabel() {
    final l10n = AppLocalizations.of(context)!;
    if (_is24HourMarket) return '24H';
    final nowEt = _toUsEastern(DateTime.now().toUtc());
    final minutes = nowEt.hour * 60 + nowEt.minute;
    if (minutes < (9 * 60 + 30)) return l10n.chartPreMarket;
    if (minutes > (16 * 60)) return l10n.chartClosed;
    return l10n.chartIntraday;
  }

  String _marketTypeLabel() {
    final symbol = _effectiveSymbol.trim().toUpperCase();
    if (symbol.contains('/')) {
      if (symbol.endsWith('/USD') || symbol.endsWith('/USDT')) {
        return '加密货币';
      }
      return '外汇';
    }
    return '指数';
  }

  String _liveBadgeText() {
    final last = _lastQuoteUpdatedAt;
    if (last == null) return '等待实时数据';
    final seconds = DateTime.now().difference(last).inSeconds;
    if (seconds <= 1) return '实时更新中';
    if (seconds < 60) return '$seconds 秒前更新';
    final minutes = DateTime.now().difference(last).inMinutes;
    return '$minutes 分钟前更新';
  }

  Widget _buildOverviewCard({
    required double? currentPrice,
    required double? change,
    required double? changePercent,
    required double? prevClose,
    required double? open,
    required double? high,
    required double? low,
    required double? turnover,
    required double? amplitude,
  }) {
    final isLive = _lastQuoteUpdatedAt != null &&
        DateTime.now().difference(_lastQuoteUpdatedAt!).inSeconds <= 3;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ChartTheme.border),
        gradient: const LinearGradient(
          colors: [Color(0xFF161B22), Color(0xFF11161E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 22,
            offset: const Offset(0, 12),
            spreadRadius: -12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildTopBadge(
                  _marketTypeLabel(),
                  textColor: ChartTheme.textPrimary,
                  background: ChartTheme.surface2,
                ),
                _buildTopBadge(
                  _liveBadgeText(),
                  textColor: isLive ? ChartTheme.up : ChartTheme.textSecondary,
                  background: isLive
                      ? ChartTheme.up.withValues(alpha: 0.12)
                      : ChartTheme.surface2,
                  dotColor: isLive ? ChartTheme.up : ChartTheme.textTertiary,
                ),
                _buildTopBadge(
                  _effectiveSymbol,
                  textColor: ChartTheme.accentGold,
                  background: ChartTheme.surface2,
                ),
              ],
            ),
          ),
          PriceSection(
            currentPrice: currentPrice,
            change: change,
            changePercent: changePercent,
            prevClose: prevClose,
            open: open,
            high: high,
            low: low,
            turnover: turnover,
            amplitude: amplitude,
          ),
        ],
      ),
    );
  }

  Widget _buildTopBadge(
    String label, {
    required Color textColor,
    required Color background,
    Color? dotColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ChartTheme.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotColor != null) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenericModeTabs() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(_chartTabs.length, (i) {
            final selected = _tabController.index == i;
            return GestureDetector(
              onTap: () => _tabController.animateTo(i),
              behavior: HitTestBehavior.opaque,
              child: Container(
                margin: const EdgeInsets.only(right: 10),
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                decoration: BoxDecoration(
                  color: selected
                      ? ChartTheme.tabSelectedBg.withValues(alpha: 0.9)
                      : ChartTheme.surface2.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected
                        ? ChartTheme.tabUnderline.withValues(alpha: 0.7)
                        : ChartTheme.border,
                  ),
                ),
                child: Text(
                  _chartTabs[i].$1,
                  style: TextStyle(
                    color: selected
                        ? ChartTheme.textPrimary
                        : ChartTheme.textSecondary,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildKlineTab(
    double chartHeight,
    double volumeHeight,
    double timeAxisHeight,
  ) {
    return Stack(
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
          prevClose: _showPrevCloseLine ? _quote?.prevClose : null,
          currentPrice: _showPrevCloseLine ? _quote?.price : null,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.chartBackToLatest,
                      style: TextStyle(
                        color: ChartTheme.accentGold,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /// 鍒嗘椂鍥句笂鏂规憳瑕佽锛氫环 鍧?娑?娑ㄨ穼骞?閲?棰濓紙涓庤偂绁ㄨ鎯呬竴鑷达紝鏁版嵁涓€鐩簡鐒讹級
  Widget _buildIntradaySummaryRow() {
    final q = _quote;
    final price = (q != null && !q.hasError && q.price > 0)
        ? q.price
        : (_intraday.isNotEmpty ? _intraday.last.close : 0.0);
    final open = (q != null && !q.hasError)
        ? q.open
        : (_intraday.isNotEmpty ? _intraday.first.open : null);
    final prev = (q != null && !q.hasError && q.price > 0 && q.change != 0)
        ? q.price - q.change
        : open;
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
      avgPrice = sumV > 0
          ? sumVw / sumV
          : (_intraday.map((c) => c.close).reduce((a, b) => a + b) /
              _intraday.length);
    }
    if (totalVol == 0 && q != null && q.volume != null) totalVol = q.volume!;
    final prevVal = prev ?? 0.0;
    final change = (q != null && q.change != null)
        ? q.change!
        : (prevVal > 0 ? price - prevVal : 0.0);
    final changePct = prevVal > 0
        ? (price - prevVal) / prevVal * 100
        : (q?.changePercent ?? 0.0);
    final changeColor = (change >= 0 ? ChartTheme.up : ChartTheme.down);
    String turnStr = '--';
    if (turnover >= 10000)
      turnStr = '${(turnover / 10000).toStringAsFixed(2)}万';
    else if (turnover > 0) turnStr = turnover.toStringAsFixed(0);
    String volStr = '--';
    if (totalVol > 0)
      volStr = totalVol >= 10000
          ? '${(totalVol / 10000).toStringAsFixed(2)}万'
          : totalVol.toString();

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: ChartTheme.pagePadding, vertical: 8),
      decoration: const BoxDecoration(
        color: ChartTheme.cardBackground,
        border: Border(bottom: BorderSide(color: ChartTheme.border, width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _summaryBlock(AppLocalizations.of(context)!.chartPrice,
                price > 0 ? price.toStringAsFixed(2) : '--', null),
            _summaryBlock(AppLocalizations.of(context)!.chartAvg,
                avgPrice != null ? avgPrice.toStringAsFixed(2) : '--', null),
            _summaryBlock(
                AppLocalizations.of(context)!.chartChangeShort,
                '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}',
                changeColor),
            _summaryBlock(
                AppLocalizations.of(context)!.chartChangePercent,
                '${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(2)}%',
                changeColor),
            _summaryBlock(AppLocalizations.of(context)!.chartVol, volStr, null),
            _summaryBlock(
                AppLocalizations.of(context)!.chartTurnover, turnStr, null),
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
          Text(label,
              style: const TextStyle(
                  color: ChartTheme.textTertiary, fontSize: 10)),
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
    final l10n = AppLocalizations.of(context)!;
    final label = isIntraday ? l10n.chartTimeshareLabel : l10n.chartKlineLabel;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: ChartTheme.accentGold)),
            const SizedBox(height: 12),
            Text(l10n.chartFetchingWithLabel(label),
                style: TextStyle(
                    color: ChartTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500),
                textAlign: TextAlign.center),
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
            Icon(Icons.show_chart_rounded,
                size: 48, color: ChartTheme.textTertiary),
            const SizedBox(height: 16),
            Text(AppLocalizations.of(context)!.chartNoData,
                style: TextStyle(
                    color: ChartTheme.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.chartEmptyHint,
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
                  _load().then((_) {
                    if (mounted) setState(() => _loading = false);
                  });
                },
                borderRadius: BorderRadius.circular(ChartTheme.radiusButton),
                hoverColor: ChartTheme.surfaceHover,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(AppLocalizations.of(context)!.chartRetry,
                      style: TextStyle(
                          color: ChartTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
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
      avgPrice: (high != null && low != null && close != null)
          ? (high! + low! + close!) / 3
          : null,
      volume: volume,
      turnover: turnover,
    );
  }

  String _formatCompactVolume(int? volume) {
    if (volume == null || volume <= 0) return '--';
    if (volume >= 100000000) {
      return '${(volume / 100000000).toStringAsFixed(2)}亿';
    }
    if (volume >= 10000) {
      return '${(volume / 10000).toStringAsFixed(2)}万';
    }
    return volume.toString();
  }

  String _formatCompactTurnover(double? turnover) {
    if (turnover == null || turnover <= 0) return '--';
    if (turnover >= 100000000) {
      return '${(turnover / 100000000).toStringAsFixed(2)}亿';
    }
    if (turnover >= 10000) {
      return '${(turnover / 10000).toStringAsFixed(2)}万';
    }
    return turnover.toStringAsFixed(0);
  }
}
