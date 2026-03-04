import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'polygon_realtime.dart';
import 'trading_cache.dart';

/// Polygon.io 行情 API 封装，带本地缓存
/// 需在 .env 中配置 POLYGON_API_KEY
/// 可选 onFresh* / fallback*：开市时把数据存远端，休市时从远端读，新用户也能看到最近一次数据
class PolygonRepository {
  PolygonRepository({
    void Function(List<Map<String, dynamic>>)? onFreshGainers,
    void Function(List<Map<String, dynamic>>)? onFreshLosers,
    Future<List<PolygonGainer>> Function()? fallbackGainers,
    Future<List<PolygonGainer>> Function()? fallbackLosers,
  })  : _apiKey = dotenv.env['POLYGON_API_KEY']?.trim(),
        _onFreshGainers = onFreshGainers,
        _onFreshLosers = onFreshLosers,
        _fallbackGainers = fallbackGainers,
        _fallbackLosers = fallbackLosers;

  final String? _apiKey;
  static const _base = 'https://api.polygon.io';
  final _cache = TradingCache.instance;
  final void Function(List<Map<String, dynamic>>)? _onFreshGainers;
  final void Function(List<Map<String, dynamic>>)? _onFreshLosers;
  final Future<List<PolygonGainer>> Function()? _fallbackGainers;
  final Future<List<PolygonGainer>> Function()? _fallbackLosers;

  bool get isAvailable => _apiKey != null && _apiKey!.isNotEmpty;

  /// 最后成交（当前价、成交量、时间），缓存 1 秒
  Future<PolygonLastTrade?> getLastTrade(String symbol) async {
    if (!isAvailable) return null;
    final sym = symbol.trim().toUpperCase();
    if (sym.isEmpty) return null;
    final cacheKey = 'polygon_last_$sym';
    final cached = await _cache.get(cacheKey, maxAge: const Duration(seconds: 1));
    if (cached != null) return PolygonLastTrade.fromJson(cached, symbol: sym);
    try {
      final uri = Uri.parse('$_base/v2/last/trade/$sym').replace(
        queryParameters: {'apiKey': _apiKey!},
      );
      final resp = await http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('请求超时'),
      );
      if (resp.statusCode != 200) {
        if (kDebugMode) {
          final body = resp.body.length > 200 ? '${resp.body.substring(0, 200)}…' : resp.body;
          debugPrint('[Polygon getLastTrade $sym] HTTP ${resp.statusCode} body=$body');
        }
        return null;
      }
      final map = jsonDecode(resp.body) as Map<String, dynamic>?;
      if (map == null) {
        if (kDebugMode) {
          final body = resp.body.length > 200 ? '${resp.body.substring(0, 200)}…' : resp.body;
          debugPrint('[Polygon getLastTrade $sym] parse failed body=$body');
        }
        return null;
      }
      final results = map['results'] as Map<String, dynamic>?;
      if (results == null) return null;
      await _cache.set(cacheKey, results);
      return PolygonLastTrade.fromJson(results, symbol: sym);
    } catch (e) {
      if (kDebugMode) debugPrint('[Polygon getLastTrade $sym] exception: $e');
      return null;
    }
  }

  /// 批量获取多标的最后成交
  Future<Map<String, PolygonLastTrade?>> getLastTrades(List<String> symbols) async {
    final out = <String, PolygonLastTrade?>{};
    for (final s in symbols) {
      out[s] = await getLastTrade(s);
    }
    return out;
  }

  /// 仅从本地缓存读取最后成交，用于首屏秒出（不发起网络请求）
  Future<Map<String, PolygonLastTrade?>> getCachedLastTrades(
    List<String> symbols, {
    Duration maxAge = const Duration(seconds: 5),
  }) async {
    final out = <String, PolygonLastTrade?>{};
    for (final sym in symbols) {
      final cached = await _cache.get('polygon_last_$sym', maxAge: maxAge);
      if (cached != null) {
        final t = PolygonLastTrade.fromJson(cached, symbol: sym);
        out[sym] = t;
      }
    }
    return out;
  }

  /// 仅从本地缓存读取涨幅榜，用于首屏秒出
  Future<List<PolygonGainer>?> getCachedGainers({
    int limit = 10,
    Duration maxAge = const Duration(seconds: 60),
  }) async {
    final list = await _cache.getList('polygon_gainers_10', maxAge: maxAge);
    if (list == null || list.isEmpty) return null;
    final result = <PolygonGainer>[];
    for (var i = 0; i < list.length && result.length < limit; i++) {
      final t = list[i];
      if (t is Map<String, dynamic>) {
        final g = PolygonGainer.fromJson(t);
        if (g != null) result.add(g);
      }
    }
    return result.isEmpty ? null : result;
  }

  /// 仅从本地缓存读取领涨/领跌（不请求 API），用于进入行情页立即展示
  Future<List<PolygonGainer>?> getCachedGainersOnly({Duration maxAge = const Duration(hours: 48)}) async {
    final list = await _cache.getList('polygon_gainers_20', maxAge: maxAge);
    if (list == null || list.isEmpty) return null;
    return _parseGainersFromCached(list, 20);
  }

  Future<List<PolygonGainer>?> getCachedLosersOnly({Duration maxAge = const Duration(hours: 48)}) async {
    final list = await _cache.getList('polygon_losers_20', maxAge: maxAge);
    if (list == null || list.isEmpty) return null;
    return _parseGainersFromCached(list, 20);
  }

  /// 前一交易日收盘价（用于计算涨跌幅），缓存 24 小时
  Future<double?> getPreviousClose(String symbol) async {
    if (!isAvailable) return null;
    final sym = symbol.trim().toUpperCase();
    if (sym.isEmpty) return null;
    final cacheKey = 'polygon_prev_$sym';
    final cached = await _cache.getDouble(cacheKey, maxAge: const Duration(hours: 24));
    if (cached != null && cached > 0) return cached;
    try {
      final uri = Uri.parse('$_base/v2/aggs/ticker/$sym/prev').replace(
        queryParameters: {'apiKey': _apiKey!, 'adjusted': 'true'},
      );
      final resp = await http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('请求超时'),
      );
      if (resp.statusCode != 200) {
        if (kDebugMode) {
          final body = resp.body.length > 200 ? '${resp.body.substring(0, 200)}…' : resp.body;
          debugPrint('[Polygon getPreviousClose $sym] HTTP ${resp.statusCode} body=$body');
        }
        return null;
      }
      final map = jsonDecode(resp.body) as Map<String, dynamic>?;
      if (map == null) {
        if (kDebugMode) {
          final body = resp.body.length > 200 ? '${resp.body.substring(0, 200)}…' : resp.body;
          debugPrint('[Polygon getPreviousClose $sym] parse failed body=$body');
        }
        return null;
      }
      final results = map['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;
      final r = results.first as Map<String, dynamic>?;
      if (r == null) return null;
      final c = (r['c'] as num?)?.toDouble();
      if (c != null && c > 0) await _cache.setDouble(cacheKey, c);
      return c;
    } catch (e) {
      if (kDebugMode) debugPrint('[Polygon getPreviousClose $sym] exception: $e');
      return null;
    }
  }

  /// 批量获取前收（用于涨跌幅）
  Future<Map<String, double>> getPreviousCloses(List<String> symbols) async {
    final out = <String, double>{};
    for (final s in symbols) {
      final pc = await getPreviousClose(s);
      if (pc != null && pc > 0) out[s] = pc;
    }
    return out;
  }

  /// 单标的 Snapshot：当日 day bar（OHLCV）+ prevDay（昨收），数据来源 Polygon /v2/snapshot/.../tickers/{ticker}
  /// 用于详情页当日开/高/低/量、昨收；缓存 1 分钟
  Future<PolygonGainer?> getTickerSnapshot(String symbol) async {
    if (!isAvailable) return null;
    final sym = symbol.trim().toUpperCase();
    if (sym.isEmpty) return null;
    final cacheKey = 'polygon_snapshot_$sym';
    final cached = await _cache.get(cacheKey, maxAge: const Duration(minutes: 1));
    if (cached != null && cached is Map<String, dynamic>) {
      final g = PolygonGainer.fromJson(cached);
      if (g != null) return g;
    }
    try {
      final uri = Uri.parse('$_base/v2/snapshot/locale/us/markets/stocks/tickers/$sym').replace(
        queryParameters: {'apiKey': _apiKey!},
      );
      final resp = await http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('请求超时'),
      );
      if (resp.statusCode != 200) return null;
      final map = jsonDecode(resp.body) as Map<String, dynamic>?;
      if (map == null) return null;
      final tickerData = map['ticker'] as Map<String, dynamic>?;
      if (tickerData == null) return null;
      final g = PolygonGainer.fromJson(tickerData);
      if (g != null) await _cache.set(cacheKey, tickerData);
      return g;
    } catch (e) {
      if (kDebugMode) debugPrint('[Polygon getTickerSnapshot $sym] $e');
      return null;
    }
  }

  /// 涨幅前 N。开市时用实时数据；休市时接口常返回空，则用最近一次缓存（最多 24 小时）当昨日数据展示
  Future<List<PolygonGainer>> getTopGainers({int limit = 20}) async {
    if (!isAvailable) return [];
    const cacheKey = 'polygon_gainers_20';
    final cached = await _cache.getList(cacheKey, maxAge: const Duration(minutes: 5));
    if (cached != null && cached.isNotEmpty) {
      final list = _parseGainersFromCached(cached, limit);
      if (list.isNotEmpty) return list;
    }
    try {
      final uri = Uri.parse('$_base/v2/snapshot/locale/us/markets/stocks/gainers').replace(
        queryParameters: {'apiKey': _apiKey!},
      );
      final resp = await http.get(uri).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('请求超时'),
      );
      if (resp.statusCode != 200) {
        final msg = resp.body.isNotEmpty ? resp.body : 'HTTP ${resp.statusCode}';
        debugPrint('Polygon gainers: $msg');
        throw Exception('API ${resp.statusCode}: ${msg.length > 120 ? msg.substring(0, 120) + "…" : msg}');
      }
      final map = jsonDecode(resp.body) as Map<String, dynamic>?;
      if (map == null) return [];
      final tickers = map['tickers'] as List<dynamic>?;
      if (tickers == null) return [];
      final list = <PolygonGainer>[];
      final toCache = <Map<String, dynamic>>[];
      for (var i = 0; i < tickers.length && list.length < limit; i++) {
        final t = tickers[i];
        if (t is! Map<String, dynamic>) continue;
        final g = PolygonGainer.fromJson(t);
        if (g != null) {
          list.add(g);
          toCache.add(t);
        }
      }
      if (toCache.isNotEmpty) {
        await _cache.setList(cacheKey, toCache);
        _onFreshGainers?.call(toCache);
      }
      if (list.isNotEmpty) return list;
      // 休市时接口常返回空，先读本地 48h 内缓存，再试远端（Supabase）供新用户
      final stale = await _cache.getList(cacheKey, maxAge: const Duration(hours: 48));
      if (stale != null && stale.isNotEmpty) return _parseGainersFromCached(stale, limit);
      final fromRemote = await _fallbackGainers?.call();
      if (fromRemote != null && fromRemote.isNotEmpty) return fromRemote;
      return [];
    } catch (e) {
      debugPrint('PolygonRepository getTopGainers: $e');
      rethrow;
    }
  }

  List<PolygonGainer> _parseGainersFromCached(List<dynamic> cached, int limit) {
    final list = <PolygonGainer>[];
    for (var i = 0; i < cached.length && list.length < limit; i++) {
      final t = cached[i];
      if (t is Map<String, dynamic>) {
        final g = PolygonGainer.fromJson(t);
        if (g != null) list.add(g);
      }
    }
    return list;
  }

  /// 跌幅前 N。休市时接口返回空则用最近一次缓存（最多 48 小时）当昨日数据
  Future<List<PolygonGainer>> getTopLosers({int limit = 20}) async {
    if (!isAvailable) return [];
    const cacheKey = 'polygon_losers_20';
    final cached = await _cache.getList(cacheKey, maxAge: const Duration(minutes: 5));
    if (cached != null && cached.isNotEmpty) {
      final list = _parseGainersFromCached(cached, limit);
      if (list.isNotEmpty) return list;
    }
    try {
      final uri = Uri.parse('$_base/v2/snapshot/locale/us/markets/stocks/losers').replace(
        queryParameters: {'apiKey': _apiKey!},
      );
      final resp = await http.get(uri).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('请求超时'),
      );
      if (resp.statusCode != 200) {
        final msg = resp.body.isNotEmpty ? resp.body : 'HTTP ${resp.statusCode}';
        debugPrint('Polygon losers: $msg');
        throw Exception('API ${resp.statusCode}: ${msg.length > 120 ? msg.substring(0, 120) + "…" : msg}');
      }
      final map = jsonDecode(resp.body) as Map<String, dynamic>?;
      if (map == null) return [];
      final tickers = map['tickers'] as List<dynamic>?;
      if (tickers == null) return [];
      final list = <PolygonGainer>[];
      final toCache = <Map<String, dynamic>>[];
      for (var i = 0; i < tickers.length && list.length < limit; i++) {
        final t = tickers[i];
        if (t is! Map<String, dynamic>) continue;
        final g = PolygonGainer.fromJson(t);
        if (g != null) {
          list.add(g);
          toCache.add(t);
        }
      }
      if (toCache.isNotEmpty) {
        await _cache.setList(cacheKey, toCache);
        _onFreshLosers?.call(toCache);
      }
      if (list.isNotEmpty) return list;
      final stale = await _cache.getList(cacheKey, maxAge: const Duration(hours: 48));
      if (stale != null && stale.isNotEmpty) return _parseGainersFromCached(stale, limit);
      final fromRemote = await _fallbackLosers?.call();
      if (fromRemote != null && fromRemote.isNotEmpty) return fromRemote;
      return [];
    } catch (e) {
      debugPrint('PolygonRepository getTopLosers: $e');
      rethrow;
    }
  }

  /// K线/分时聚合 bars，缓存 5 分钟（历史数据变化少）
  Future<List<PolygonBar>?> getAggregates(
    String symbol, {
    required int multiplier,
    required String timespan,
    required int fromMs,
    required int toMs,
  }) async {
    if (!isAvailable) return null;
    final sym = symbol.trim().toUpperCase();
    if (sym.isEmpty) return null;
    final cacheKey = 'polygon_aggs_${sym}_${multiplier}_${timespan}_${fromMs}_$toMs';
    final cached = await _cache.getList(cacheKey, maxAge: const Duration(minutes: 5));
    if (cached != null && cached.isNotEmpty) {
      final list = <PolygonBar>[];
      for (final r in cached) {
        if (r is Map<String, dynamic>) {
          final bar = PolygonBar.fromJson(r);
          if (bar != null) list.add(bar);
        }
      }
      if (list.isNotEmpty) return list;
    }
    try {
      final uri = Uri.parse('$_base/v2/aggs/ticker/$sym/range/$multiplier/$timespan/$fromMs/$toMs').replace(
        queryParameters: {'apiKey': _apiKey!, 'adjusted': 'true', 'sort': 'asc'},
      );
      final resp = await http.get(uri).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('请求超时'),
      );
      if (resp.statusCode != 200) return null;
      final map = jsonDecode(resp.body) as Map<String, dynamic>?;
      if (map == null) return null;
      final results = map['results'] as List<dynamic>?;
      if (results == null) return [];
      final list = <PolygonBar>[];
      final toCache = <Map<String, dynamic>>[];
      for (final r in results) {
        if (r is! Map<String, dynamic>) continue;
        final bar = PolygonBar.fromJson(r);
        if (bar != null) {
          list.add(bar);
          toCache.add(r);
        }
      }
      if (toCache.isNotEmpty) await _cache.setList(cacheKey, toCache);
      return list;
    } catch (e) {
      debugPrint('PolygonRepository getAggregates($symbol): $e');
      return null;
    }
  }

  /// 全量美股列表（Polygon v3/reference/tickers，market=stocks 不限制 type，以包含 BRAI 等非 CS 标的）
  /// 分页至 next_url 为空，用于美股 Tab 展示全部标的
  Future<List<PolygonTickerSearchResult>> getAllUsTickers() async {
    if (!isAvailable) return [];
    final list = <PolygonTickerSearchResult>[];
    String? nextUrl;
    const limit = 1000;
    try {
      for (;;) {
        final uri = nextUrl == null
            ? Uri.parse('$_base/v3/reference/tickers').replace(
                queryParameters: {
                  'market': 'stocks',
                  'limit': limit.toString(),
                  'apiKey': _apiKey!,
                },
              )
            : () {
                final u = Uri.parse(nextUrl!);
                final q = Map<String, String>.from(u.queryParameters);
                q['apiKey'] = _apiKey!;
                return u.replace(queryParameters: q);
              }();
        final resp = await http.get(uri).timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw Exception('请求超时'),
        );
        if (resp.statusCode != 200) break;
        final map = jsonDecode(resp.body) as Map<String, dynamic>?;
        if (map == null) break;
        final results = map['results'] as List<dynamic>?;
        if (results != null) {
          for (final r in results) {
            if (r is! Map<String, dynamic>) continue;
            final ticker = r['ticker'] as String?;
            if (ticker == null || ticker.isEmpty) continue;
            final name = r['name'] as String? ?? ticker;
            final market = r['market'] as String?;
            list.add(PolygonTickerSearchResult(ticker: ticker, name: name, market: market));
          }
        }
        nextUrl = map['next_url'] as String?;
        if (nextUrl == null || nextUrl.isEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      return list;
    } catch (e) {
      if (kDebugMode) debugPrint('PolygonRepository getAllUsTickers: $e');
      return list;
    }
  }

  /// 搜索标的（Polygon v3 reference tickers），返回 ticker + name
  Future<List<PolygonTickerSearchResult>> searchTickers(String query, {int limit = 20}) async {
    if (!isAvailable) return [];
    final q = query.trim();
    if (q.isEmpty) return [];
    try {
      final uri = Uri.parse('$_base/v3/reference/tickers').replace(
        queryParameters: {
          'search': q,
          'limit': limit.toString(),
          'apiKey': _apiKey!,
        },
      );
      final resp = await http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('请求超时'),
      );
      if (resp.statusCode != 200) return [];
      final map = jsonDecode(resp.body) as Map<String, dynamic>?;
      if (map == null) return [];
      final results = map['results'] as List<dynamic>?;
      if (results == null) return [];
      final list = <PolygonTickerSearchResult>[];
      for (final r in results) {
        if (r is! Map<String, dynamic>) continue;
        final ticker = r['ticker'] as String?;
        if (ticker == null || ticker.isEmpty) continue;
        final name = r['name'] as String? ?? ticker;
        final market = r['market'] as String?;
        list.add(PolygonTickerSearchResult(ticker: ticker, name: name, market: market));
      }
      return list;
    } catch (e) {
      debugPrint('PolygonRepository searchTickers: $e');
      return [];
    }
  }

  /// 创建实时成交流（WebSocket），有成交即推送价格与成交量
  PolygonRealtime? openRealtime(String symbol) {
    if (!isAvailable || _apiKey == null) return null;
    return PolygonRealtime(apiKey: _apiKey!, symbol: symbol);
  }

  /// 多标的实时成交流，用于整体行情等
  PolygonRealtimeMulti? openRealtimeMulti(List<String> symbols) {
    if (!isAvailable || _apiKey == null || symbols.isEmpty) return null;
    return PolygonRealtimeMulti(apiKey: _apiKey!, symbols: symbols);
  }
}

/// 涨幅/跌幅榜单条（含当日 OHLCV、昨收，来自 snapshot day / prevDay）
class PolygonGainer {
  const PolygonGainer({
    required this.ticker,
    required this.todaysChangePerc,
    required this.todaysChange,
    this.price,
    this.updated,
    this.dayVolume,
    this.dayOpen,
    this.dayHigh,
    this.dayLow,
    this.prevClose,
  });
  final String ticker;
  final double todaysChangePerc;
  final double todaysChange;
  final double? price;
  final int? updated;
  /// 当日成交量（Snapshot day.v）
  final int? dayVolume;
  /// 当日开盘/最高/最低（day.o/h/l）
  final double? dayOpen;
  final double? dayHigh;
  final double? dayLow;
  /// 昨收（prevDay.c）
  final double? prevClose;

  /// 用实时价更新（WebSocket 成交推送），需有 prevClose 才能计算涨跌
  PolygonGainer copyWithRealtimePrice(double newPrice) {
    final prev = prevClose;
    if (prev == null || prev <= 0) {
      return PolygonGainer(
        ticker: ticker,
        todaysChangePerc: todaysChangePerc,
        todaysChange: todaysChange,
        price: newPrice,
        updated: DateTime.now().millisecondsSinceEpoch,
        dayVolume: dayVolume,
        dayOpen: dayOpen,
        dayHigh: dayHigh,
        dayLow: dayLow,
        prevClose: prevClose,
      );
    }
    final newChange = newPrice - prev;
    final newChangePerc = (newChange / prev) * 100;
    return PolygonGainer(
      ticker: ticker,
      todaysChangePerc: newChangePerc,
      todaysChange: newChange,
      price: newPrice,
      updated: DateTime.now().millisecondsSinceEpoch,
      dayVolume: dayVolume,
      dayOpen: dayOpen,
      dayHigh: dayHigh,
      dayLow: dayLow,
      prevClose: prevClose,
    );
  }

  static PolygonGainer? fromJson(Map<String, dynamic> json) {
    final ticker = json['ticker'] as String?;
    if (ticker == null) return null;
    final perc = (json['todaysChangePerc'] as num?)?.toDouble();
    final ch = (json['todaysChange'] as num?)?.toDouble();
    if (perc == null) return null;
    double? price;
    int? dayVolume;
    double? dayOpen, dayHigh, dayLow;
    double? prevClose;
    final day = json['day'] as Map<String, dynamic>?;
    if (day != null) {
      price = (day['c'] as num?)?.toDouble();
      dayVolume = (day['v'] as num?)?.toInt();
      dayOpen = (day['o'] as num?)?.toDouble();
      dayHigh = (day['h'] as num?)?.toDouble();
      dayLow = (day['l'] as num?)?.toDouble();
    }
    if (price == null) {
      final last = json['lastTrade'] as Map<String, dynamic>?;
      if (last != null) price = (last['p'] as num?)?.toDouble();
    }
    final prev = json['prevDay'] as Map<String, dynamic>?;
    if (prev != null) prevClose = (prev['c'] as num?)?.toDouble();
    return PolygonGainer(
      ticker: ticker,
      todaysChangePerc: perc,
      todaysChange: ch ?? 0,
      price: price,
      updated: json['updated'] as int?,
      dayVolume: dayVolume,
      dayOpen: dayOpen,
      dayHigh: dayHigh,
      dayLow: dayLow,
      prevClose: prevClose,
    );
  }
}

/// 单根 K 线/分时 bar（Polygon 返回 t 为毫秒）
class PolygonBar {
  const PolygonBar({
    required this.timeMs,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });
  final int timeMs;
  final double open;
  final double high;
  final double low;
  final double close;
  final int volume;

  double get time => timeMs / 1000.0;

  static PolygonBar? fromJson(Map<String, dynamic> json) {
    final t = json['t'] as int?;
    final c = (json['c'] as num?)?.toDouble();
    if (t == null || c == null) return null;
    return PolygonBar(
      timeMs: t,
      open: (json['o'] as num?)?.toDouble() ?? c,
      high: (json['h'] as num?)?.toDouble() ?? c,
      low: (json['l'] as num?)?.toDouble() ?? c,
      close: c,
      volume: (json['v'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 图表用 K 线/分时点（仅 Polygon 数据源）
class ChartCandle {
  const ChartCandle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume,
  });
  final double time;
  final double open;
  final double high;
  final double low;
  final double close;
  final int? volume;
  factory ChartCandle.fromBar(PolygonBar b) => ChartCandle(
        time: b.time,
        open: b.open,
        high: b.high,
        low: b.low,
        close: b.close,
        volume: b.volume,
      );
}

/// Polygon 最后成交结果
/// p: 成交价, s: 成交量, t: 时间戳(纳秒)
class PolygonLastTrade {
  const PolygonLastTrade({
    required this.symbol,
    required this.price,
    required this.size,
    this.timestampNs,
  });

  final String symbol;
  final double price;
  final int size;
  final int? timestampNs;

  /// 时间戳转 DateTime（纳秒 -> 毫秒）
  DateTime? get timestamp {
    if (timestampNs == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestampNs! ~/ 1000000);
  }

  static PolygonLastTrade? fromJson(Map<String, dynamic> json, {String? symbol}) {
    final p = (json['p'] as num?)?.toDouble();
    if (p == null) return null;
    final s = (json['s'] as num?)?.toInt() ?? 0;
    final t = (json['t'] as num?)?.toInt();
    return PolygonLastTrade(
      symbol: symbol ?? (json['T'] as String?) ?? '',
      price: p,
      size: s,
      timestampNs: t,
    );
  }
}

/// 标的搜索结果（Polygon tickers search）
class PolygonTickerSearchResult {
  const PolygonTickerSearchResult({
    required this.ticker,
    required this.name,
    this.market,
  });
  final String ticker;
  final String name;
  /// 市场类型：stocks, crypto, fx, indices 等（Polygon API 返回）
  final String? market;
}
