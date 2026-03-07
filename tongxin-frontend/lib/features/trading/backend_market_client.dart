import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'polygon_repository.dart';
import 'trading_cache.dart';
import '../market/market_repository.dart';

/// 请求后端行情代理（tongxin-backend），不直连 Polygon/Twelve Data；所有结果做本地缓存
class BackendMarketClient {
  BackendMarketClient(String baseUrl)
      : _base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
  final String _base;
  final _cache = TradingCache.instance;

  static const _quotesMaxAge = Duration(seconds: 15);
  static const _candlesMaxAge = Duration(minutes: 2);
  static const _gainersLosersMaxAge = Duration(minutes: 5);
  static const _searchMaxAge = Duration(minutes: 5);
  static const _tickersFromCacheMaxAge = Duration(hours: 1);
  static const _forexPairsMaxAge = Duration(minutes: 10);
  static const _cryptoPairsMaxAge = Duration(minutes: 10);

  /// 从后端 stock_quote_cache 表获取 symbol+name 列表，秒开美股列表
  Future<List<MarketSearchResult>?> getTickersFromCache() async {
    const cacheKey = 'backend_tickers_from_cache';
    final cached = await _cache.getList(cacheKey, maxAge: _tickersFromCacheMaxAge);
    if (cached != null && cached.isNotEmpty) {
      final list = <MarketSearchResult>[];
      for (final e in cached) {
        if (e is! Map<String, dynamic>) continue;
        final s = e['s'] as String?;
        final n = e['n'] as String?;
        if (s == null || s.isEmpty) continue;
        list.add(MarketSearchResult(
          symbol: s,
          name: n ?? s,
          market: e['m'] as String?,
          stockType: e['t'] as String?,
          is24HourTrading: ((e['h24'] as num?)?.toInt() ?? 0) == 1,
        ));
      }
      if (list.isNotEmpty) return list;
    }
    try {
      final uri = Uri.parse('${_base}api/tickers-from-cache');
      final resp = await http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('请求超时'),
      );
      if (resp.statusCode != 200) return null;
      final list = jsonDecode(resp.body) as List<dynamic>?;
      if (list == null || list.isEmpty) return null;
      final result = <MarketSearchResult>[];
      final toCache = <Map<String, dynamic>>[];
      for (final e in list) {
        if (e is! Map<String, dynamic>) continue;
        final s = (e['symbol'] as String?)?.trim();
        final n = e['name'] as String?;
        if (s == null || s.isEmpty) continue;
        final market = e['market'] as String?;
        final type = e['stock_type'] as String?;
        final is24h = e['is_24h_trading'] == true;
        result.add(MarketSearchResult(
          symbol: s,
          name: n ?? s,
          market: market,
          stockType: type,
          is24HourTrading: is24h,
        ));
        toCache.add({
          's': s,
          'n': n ?? s,
          'm': market,
          't': type,
          'h24': is24h ? 1 : 0,
        });
      }
      if (result.isNotEmpty) {
        try {
          await _cache.setList(cacheKey, toCache);
        } catch (_) {}
        return result;
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[Backend getTickersFromCache] $e');
      return null;
    }
  }

  /// 批量写入 symbol+name 到服务器 stock_quote_cache（无报价也可，用于预填股票列表）
  Future<bool> upsertTickersToServer(List<MarketSearchResult> tickers) async {
    if (tickers.isEmpty) return true;
    try {
      final body = tickers.map((t) => {'symbol': t.symbol, 'name': t.name}).toList();
      final uri = Uri.parse('${_base}api/tickers-upsert');
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('请求超时'),
      );
      if (resp.statusCode != 200) {
        if (kDebugMode) debugPrint('[Backend upsertTickersToServer] ${resp.statusCode} ${resp.body}');
        return false;
      }
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[Backend upsertTickersToServer] $e');
      return false;
    }
  }

  Future<BackendStockTickersPage> getStockTickersPage({
    required int page,
    required int pageSize,
    required String sortColumn,
    required bool sortAscending,
    int maxAgeHours = 0,
  }) async {
    final query = <String, String>{
      'page': page.toString(),
      'pageSize': pageSize.toString(),
      'sortColumn': sortColumn,
      'sortAscending': sortAscending ? 'true' : 'false',
    };
    if (maxAgeHours > 0) {
      query['maxAgeHours'] = maxAgeHours.toString();
    }
    final uri = Uri.parse('${_base}api/tickers-page').replace(
      queryParameters: query,
    );
    try {
      final resp = await http.get(uri).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw Exception('请求超时'),
      );
      if (resp.statusCode != 200) {
        return BackendStockTickersPage.empty(page: page, pageSize: pageSize);
      }
      final map = jsonDecode(resp.body) as Map<String, dynamic>?;
      if (map == null) return BackendStockTickersPage.empty(page: page, pageSize: pageSize);
      final parsed = BackendStockTickersPage.fromJson(map) ??
          BackendStockTickersPage.empty(page: page, pageSize: pageSize);
      return parsed;
    } catch (_) {
      return BackendStockTickersPage.empty(page: page, pageSize: pageSize);
    }
  }

  /// [realtime] 为 true 且仅请求单只时：不读本地缓存，请求带 realtime=1，后端直连 Polygon 返回实时数据（详情页用）
  Future<Map<String, MarketQuote>> getQuotes(List<String> symbols, {bool realtime = false}) async {
    if (symbols.isEmpty) return {};
    final sorted = List<String>.from(symbols)..sort();
    final cacheKey = 'backend_quotes_${sorted.join(",")}';
    final useRealtime = realtime && symbols.length == 1;
    if (!useRealtime) {
      final cached = await _cache.get(cacheKey, maxAge: _quotesMaxAge);
      if (cached != null && cached is Map<String, dynamic>) {
        final out = <String, MarketQuote>{};
        for (final sym in symbols) {
          final s = sym.trim();
          if (s.isEmpty) continue;
          final raw = cached[s] as Map<String, dynamic>?;
          if (raw == null) {
            out[s] = MarketQuote.failed(s, '无数据');
            continue;
          }
          final q = MarketQuote.fromSnapshotMap(raw);
          if (q != null) {
            out[s] = q;
          } else {
            out[s] = MarketQuote.failed(s, raw['error_reason'] as String? ?? '解析失败');
          }
        }
        return out;
      }
    }
    final queryParams = <String, String>{'symbols': symbols.join(',')};
    if (useRealtime) queryParams['realtime'] = '1';
    final uri = Uri.parse('${_base}api/quotes').replace(
      queryParameters: queryParams,
    );
    try {
      final timeoutSec = symbols.length > 25 ? 45 : 15;
      final resp = await http.get(uri).timeout(
        Duration(seconds: timeoutSec),
        onTimeout: () => throw Exception('请求超时'),
      );
      if (resp.statusCode != 200) {
        if (kDebugMode) debugPrint('[Backend getQuotes] ${resp.statusCode} ${resp.body}');
        return _failedMap(symbols, 'HTTP ${resp.statusCode}');
      }
      final map = jsonDecode(resp.body) as Map<String, dynamic>?;
      if (map == null) return _failedMap(symbols, '无效响应');
      final out = <String, MarketQuote>{};
      for (final sym in symbols) {
        final s = sym.trim();
        if (s.isEmpty) continue;
        final raw = map[s] as Map<String, dynamic>?;
        if (raw == null) {
          out[s] = MarketQuote.failed(s, '无数据');
          continue;
        }
        final q = MarketQuote.fromSnapshotMap(raw);
        if (q != null) {
          out[s] = q;
        } else {
          out[s] = MarketQuote.failed(s, raw['error_reason'] as String? ?? '解析失败');
        }
      }
      final hasAnySuccess = out.values.any((q) => !q.hasError && q.price > 0);
      if (!useRealtime && hasAnySuccess) {
        try {
          await _cache.set(cacheKey, map);
        } catch (_) {}
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('[Backend getQuotes] $e');
      return _failedMap(symbols, e.toString());
    }
  }

  Map<String, MarketQuote> _failedMap(List<String> symbols, String reason) {
    final out = <String, MarketQuote>{};
    for (final s in symbols) {
      final t = s.trim();
      if (t.isEmpty) continue;
      out[t] = MarketQuote.failed(t, reason);
    }
    return out;
  }

  Future<BackendForexPairsPage> getForexPairsPage({
    required int page,
    int pageSize = 30,
  }) async {
    final cacheKey = 'backend_forex_pairs_${page}_$pageSize';
    final cached = await _cache.get(cacheKey, maxAge: _forexPairsMaxAge);
    if (cached is Map<String, dynamic>) {
      final parsed = BackendForexPairsPage.fromJson(cached);
      if (parsed != null) return parsed;
    }
    final uri = Uri.parse('${_base}api/forex/pairs').replace(
      queryParameters: {
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      },
    );
    try {
      final resp = await http.get(uri).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('请求超时'),
      );
      if (resp.statusCode != 200) {
        return const BackendForexPairsPage(items: [], total: 0, page: 1, pageSize: 30, hasMore: false);
      }
      final map = jsonDecode(resp.body) as Map<String, dynamic>?;
      if (map == null) {
        return const BackendForexPairsPage(items: [], total: 0, page: 1, pageSize: 30, hasMore: false);
      }
      final parsed = BackendForexPairsPage.fromJson(map) ??
          const BackendForexPairsPage(items: [], total: 0, page: 1, pageSize: 30, hasMore: false);
      if (parsed.items.isNotEmpty) {
        try {
          await _cache.set(cacheKey, map);
        } catch (_) {}
      }
      return parsed;
    } catch (_) {
      return const BackendForexPairsPage(items: [], total: 0, page: 1, pageSize: 30, hasMore: false);
    }
  }

  Future<Map<String, MarketQuote>> getForexQuotes(List<String> symbols) async {
    if (symbols.isEmpty) return {};
    final uri = Uri.parse('${_base}api/forex/quotes').replace(
      queryParameters: {'symbols': symbols.join(',')},
    );
    try {
      final resp = await http.get(uri).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw Exception('请求超时'),
      );
      if (resp.statusCode != 200) return _failedMap(symbols, 'HTTP ${resp.statusCode}');
      final map = jsonDecode(resp.body) as Map<String, dynamic>?;
      if (map == null) return _failedMap(symbols, '无效响应');
      final out = <String, MarketQuote>{};
      for (final s in symbols) {
        final raw = map[s] as Map<String, dynamic>?;
        if (raw == null) {
          out[s] = MarketQuote.failed(s, '无数据');
          continue;
        }
        final q = MarketQuote.fromSnapshotMap(raw);
        out[s] = q ?? MarketQuote.failed(s, raw['error_reason'] as String? ?? '解析失败');
      }
      return out;
    } catch (e) {
      return _failedMap(symbols, e.toString());
    }
  }

  Future<BackendCryptoPairsPage> getCryptoPairsPage({
    required int page,
    int pageSize = 30,
  }) async {
    final cacheKey = 'backend_crypto_pairs_${page}_$pageSize';
    final cached = await _cache.get(cacheKey, maxAge: _cryptoPairsMaxAge);
    if (cached is Map<String, dynamic>) {
      final parsed = BackendCryptoPairsPage.fromJson(cached);
      if (parsed != null) return parsed;
    }
    final uri = Uri.parse('${_base}api/crypto/pairs').replace(
      queryParameters: {
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      },
    );
    try {
      final resp = await http.get(uri).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('请求超时'),
      );
      if (resp.statusCode != 200) {
        return const BackendCryptoPairsPage(items: [], total: 0, page: 1, pageSize: 30, hasMore: false);
      }
      final map = jsonDecode(resp.body) as Map<String, dynamic>?;
      if (map == null) {
        return const BackendCryptoPairsPage(items: [], total: 0, page: 1, pageSize: 30, hasMore: false);
      }
      final parsed = BackendCryptoPairsPage.fromJson(map) ??
          const BackendCryptoPairsPage(items: [], total: 0, page: 1, pageSize: 30, hasMore: false);
      if (parsed.items.isNotEmpty) {
        try {
          await _cache.set(cacheKey, map);
        } catch (_) {}
      }
      return parsed;
    } catch (_) {
      return const BackendCryptoPairsPage(items: [], total: 0, page: 1, pageSize: 30, hasMore: false);
    }
  }

  Future<Map<String, MarketQuote>> getCryptoQuotes(List<String> symbols) async {
    if (symbols.isEmpty) return {};
    final uri = Uri.parse('${_base}api/crypto/quotes').replace(
      queryParameters: {'symbols': symbols.join(',')},
    );
    try {
      final resp = await http.get(uri).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw Exception('请求超时'),
      );
      if (resp.statusCode != 200) return _failedMap(symbols, 'HTTP ${resp.statusCode}');
      final map = jsonDecode(resp.body) as Map<String, dynamic>?;
      if (map == null) return _failedMap(symbols, '无效响应');
      final out = <String, MarketQuote>{};
      for (final s in symbols) {
        final raw = map[s] as Map<String, dynamic>?;
        if (raw == null) {
          out[s] = MarketQuote.failed(s, '无数据');
          continue;
        }
        final q = MarketQuote.fromSnapshotMap(raw);
        out[s] = q ?? MarketQuote.failed(s, raw['error_reason'] as String? ?? '解析失败');
      }
      return out;
    } catch (e) {
      return _failedMap(symbols, e.toString());
    }
  }

  /// 当日 OHLC + 昨收（详情页用），走后端 /api/quotes?realtime=1
  Future<PolygonGainer?> getDaySnapshot(String symbol) async {
    final m = await getQuotes([symbol.trim()], realtime: true);
    final q = m[symbol.trim()];
    if (q == null || q.hasError || q.price <= 0) return null;
    final prevClose = q.change != 0 ? q.price - q.change : null;
    return PolygonGainer(
      ticker: q.symbol,
      todaysChangePerc: q.changePercent,
      todaysChange: q.change,
      price: q.price,
      dayOpen: q.open,
      dayHigh: q.high,
      dayLow: q.low,
      dayVolume: q.volume,
      prevClose: prevClose,
    );
  }

  /// [lastDays] 非 null 时请求多日数据（用于分时 2天/3天/4天 合并显示），会传 fromMs/toMs 给后端
  Future<List<ChartCandle>> getCandles(String symbol, String interval, {int? lastDays, void Function(String)? onError}) async {
    final sym = symbol.trim();
    if (sym.isEmpty) return [];
    final toMs = DateTime.now().millisecondsSinceEpoch;
    final fromMs = lastDays != null && lastDays > 0
        ? toMs - lastDays * 24 * 3600 * 1000
        : null;
    final cacheKey = fromMs != null
        ? 'backend_candles_${sym}_${interval}_${fromMs}_$toMs'
        : 'backend_candles_${sym}_$interval';
    final cached = await _cache.getList(cacheKey, maxAge: _candlesMaxAge);
    if (cached != null && cached.isNotEmpty) {
      final result = <ChartCandle>[];
      for (final e in cached) {
        if (e is! Map<String, dynamic>) continue;
        final t = (e['t'] as num?)?.toDouble();
        final c = (e['c'] as num?)?.toDouble();
        if (t == null || c == null) continue;
        result.add(ChartCandle(
          time: t / 1000.0,
          open: (e['o'] as num?)?.toDouble() ?? c,
          high: (e['h'] as num?)?.toDouble() ?? c,
          low: (e['l'] as num?)?.toDouble() ?? c,
          close: c,
          volume: (e['v'] as num?)?.toInt(),
        ));
      }
      if (result.isNotEmpty) return result;
    }
    final queryParams = <String, String>{'symbol': sym, 'interval': interval};
    if (fromMs != null) {
      queryParams['fromMs'] = fromMs.toString();
      queryParams['toMs'] = toMs.toString();
    }
    final uri = Uri.parse('${_base}api/candles').replace(
      queryParameters: queryParams,
    );
    try {
      if (kDebugMode) debugPrint('[Backend getCandles] GET $uri');
      // 后端拉 20 年历史时可能较慢，超时放宽到 45 秒
      final resp = await http.get(uri).timeout(
        const Duration(seconds: 45),
        onTimeout: () => throw Exception('请求超时(45s)'),
      );
      if (resp.statusCode != 200) {
        final msg = 'HTTP ${resp.statusCode}';
        if (kDebugMode) debugPrint('[Backend getCandles] $sym $interval => $msg');
        onError?.call(msg);
        return [];
      }
      final list = jsonDecode(resp.body) as List<dynamic>?;
      if (list == null) {
        if (kDebugMode) debugPrint('[Backend getCandles] $sym $interval => 响应非数组');
        onError?.call('响应格式错误');
        return [];
      }
      final result = <ChartCandle>[];
      final toCache = <Map<String, dynamic>>[];
      for (final e in list) {
        if (e is! Map<String, dynamic>) continue;
        final t = (e['t'] as num?)?.toDouble();
        final c = (e['c'] as num?)?.toDouble();
        if (t == null || c == null) continue;
        result.add(ChartCandle(
          time: t / 1000.0,
          open: (e['o'] as num?)?.toDouble() ?? c,
          high: (e['h'] as num?)?.toDouble() ?? c,
          low: (e['l'] as num?)?.toDouble() ?? c,
          close: c,
          volume: (e['v'] as num?)?.toInt(),
        ));
        toCache.add(e);
      }
      if (kDebugMode) debugPrint('[Backend getCandles] $sym $interval => ${result.length} 根K线');
      if (toCache.isNotEmpty) {
        try {
          await _cache.setList(cacheKey, toCache);
        } catch (_) {}
      }
      return result;
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (kDebugMode) debugPrint('[Backend getCandles] $sym $interval 请求失败: $e');
      onError?.call(msg);
      return [];
    }
  }

  /// 加载早于 [olderThanMs] 的 K 线（用于向左滑动加载更多、补全近 20 年）
  /// 请求 GET /api/candles?symbol=&interval=&fromMs=&toMs=
  Future<List<ChartCandle>> getCandlesOlderThan(
    String symbol,
    String interval, {
    required int olderThanMs,
    int limit = 500,
  }) async {
    final sym = symbol.trim();
    if (sym.isEmpty) return [];
    final intervalMs = _intervalMs(interval);
    final toMs = olderThanMs - 1;
    final fromMs = (olderThanMs - limit * intervalMs).clamp(0, toMs - 1);
    final uri = Uri.parse('${_base}api/candles').replace(
      queryParameters: {
        'symbol': sym,
        'interval': interval,
        'fromMs': fromMs.toString(),
        'toMs': toMs.toString(),
      },
    );
    try {
      if (kDebugMode) debugPrint('[Backend getCandlesOlderThan] GET $uri');
      final resp = await http.get(uri).timeout(
        const Duration(seconds: 45),
        onTimeout: () => throw Exception('请求超时(45s)'),
      );
      if (resp.statusCode != 200) return [];
      final list = jsonDecode(resp.body) as List<dynamic>?;
      if (list == null) return [];
      final result = <ChartCandle>[];
      for (final e in list) {
        if (e is! Map<String, dynamic>) continue;
        final t = (e['t'] as num?)?.toDouble();
        final c = (e['c'] as num?)?.toDouble();
        if (t == null || c == null) continue;
        result.add(ChartCandle(
          time: t / 1000.0,
          open: (e['o'] as num?)?.toDouble() ?? c,
          high: (e['h'] as num?)?.toDouble() ?? c,
          low: (e['l'] as num?)?.toDouble() ?? c,
          close: c,
          volume: (e['v'] as num?)?.toInt(),
        ));
      }
      if (kDebugMode) debugPrint('[Backend getCandlesOlderThan] $sym $interval => ${result.length} 根');
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('[Backend getCandlesOlderThan] $sym 失败: $e');
      return [];
    }
  }

  static int _intervalMs(String interval) {
    if (interval == '1day') return 86400 * 1000;
    if (interval == '1week') return 7 * 86400 * 1000;
    if (interval == '1month') return 30 * 86400 * 1000;
    if (interval == '1h') return 3600 * 1000;
    if (interval == '30min') return 30 * 60 * 1000;
    if (interval == '15min') return 15 * 60 * 1000;
    if (interval == '5min') return 5 * 60 * 1000;
    if (interval == '1min') return 60 * 1000;
    return 86400 * 1000;
  }

  Future<List<PolygonGainer>> getGainers({int limit = 20}) async {
    const cacheKey = 'backend_gainers_20';
    final cached = await _cache.getList(cacheKey, maxAge: _gainersLosersMaxAge);
    if (cached != null && cached.isNotEmpty) {
      final result = <PolygonGainer>[];
      for (final e in cached) {
        if (e is! Map<String, dynamic>) continue;
        final g = PolygonGainer.fromJson(e);
        if (g != null) result.add(g);
      }
      if (result.isNotEmpty) return result.take(limit).toList();
    }
    final uri = Uri.parse('${_base}api/gainers').replace(
      queryParameters: {'limit': limit.toString()},
    );
    try {
      final resp = await http.get(uri).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('请求超时'),
      );
      if (resp.statusCode != 200) return [];
      final list = jsonDecode(resp.body) as List<dynamic>?;
      if (list == null) return [];
      final result = <PolygonGainer>[];
      final toCache = <Map<String, dynamic>>[];
      for (final e in list) {
        if (e is! Map<String, dynamic>) continue;
        final g = PolygonGainer.fromJson(e);
        if (g != null) {
          result.add(g);
          toCache.add(e);
        }
      }
      if (toCache.isNotEmpty) {
        try {
          await _cache.setList(cacheKey, toCache);
        } catch (_) {}
      }
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('[Backend getGainers] $e');
      return [];
    }
  }

  Future<List<PolygonGainer>> getLosers({int limit = 20}) async {
    const cacheKey = 'backend_losers_20';
    final cached = await _cache.getList(cacheKey, maxAge: _gainersLosersMaxAge);
    if (cached != null && cached.isNotEmpty) {
      final result = <PolygonGainer>[];
      for (final e in cached) {
        if (e is! Map<String, dynamic>) continue;
        final g = PolygonGainer.fromJson(e);
        if (g != null) result.add(g);
      }
      if (result.isNotEmpty) return result.take(limit).toList();
    }
    final uri = Uri.parse('${_base}api/losers').replace(
      queryParameters: {'limit': limit.toString()},
    );
    try {
      final resp = await http.get(uri).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('请求超时'),
      );
      if (resp.statusCode != 200) return [];
      final list = jsonDecode(resp.body) as List<dynamic>?;
      if (list == null) return [];
      final result = <PolygonGainer>[];
      final toCache = <Map<String, dynamic>>[];
      for (final e in list) {
        if (e is! Map<String, dynamic>) continue;
        final g = PolygonGainer.fromJson(e);
        if (g != null) {
          result.add(g);
          toCache.add(e);
        }
      }
      if (toCache.isNotEmpty) {
        try {
          await _cache.setList(cacheKey, toCache);
        } catch (_) {}
      }
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('[Backend getLosers] $e');
      return [];
    }
  }

  Future<List<MarketSearchResult>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final cacheKey = 'backend_search_${q.replaceAll(RegExp(r'[^\w\s-]'), '_')}';
    final cached = await _cache.getList(cacheKey, maxAge: _searchMaxAge);
    if (cached != null && cached.isNotEmpty) {
      return cached
          .where((e) => e is Map<String, dynamic> && e['ticker'] != null)
          .map((e) => MarketSearchResult(
                symbol: e['ticker'] as String,
                name: (e['name'] as String?) ?? e['ticker'] as String,
                market: e['market'] as String?,
              ))
          .toList();
    }
    final uri = Uri.parse('${_base}api/search').replace(
      queryParameters: {'q': q},
    );
    try {
      final resp = await http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('请求超时'),
      );
      if (resp.statusCode != 200) return [];
      final list = jsonDecode(resp.body) as List<dynamic>?;
      if (list == null) return [];
      final result = list
          .where((e) => e is Map<String, dynamic> && e['ticker'] != null)
          .map((e) => MarketSearchResult(
                symbol: e['ticker'] as String,
                name: (e['name'] as String?) ?? e['ticker'] as String,
                market: e['market'] as String?,
              ))
          .toList();
      final toCache = list.whereType<Map<String, dynamic>>().toList();
      if (toCache.isNotEmpty) {
        try {
          await _cache.setList(cacheKey, toCache);
        } catch (_) {}
      }
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('[Backend search] $e');
      return [];
    }
  }

  static const _ratiosMaxAge = Duration(minutes: 10);
  static const _companyActionsMaxAge = Duration(hours: 1);

  Future<Map<String, dynamic>?> getKeyRatios(String symbol) async {
    final sym = symbol.trim();
    if (sym.isEmpty) return null;
    final cacheKey = 'backend_ratios_$sym';
    final cached = await _cache.get(cacheKey, maxAge: _ratiosMaxAge);
    if (cached != null && cached is Map<String, dynamic>) return cached;
    final uri = Uri.parse('${_base}api/ratios').replace(queryParameters: {'symbol': sym});
    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 10), onTimeout: () => throw Exception('请求超时'));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      if (data == null) return null;
      final map = data is Map<String, dynamic> ? data : null;
      if (map != null) try { await _cache.set(cacheKey, map); } catch (_) {}
      return map;
    } catch (e) {
      if (kDebugMode) debugPrint('[Backend getKeyRatios] $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getDividends(String symbol) async {
    final sym = symbol.trim();
    if (sym.isEmpty) return [];
    final cacheKey = 'backend_dividends_$sym';
    final cached = await _cache.getList(cacheKey, maxAge: _companyActionsMaxAge);
    if (cached != null && cached.isNotEmpty) return cached.whereType<Map<String, dynamic>>().toList();
    final uri = Uri.parse('${_base}api/dividends').replace(queryParameters: {'symbol': sym});
    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 10), onTimeout: () => throw Exception('请求超时'));
      if (resp.statusCode != 200) return [];
      final list = jsonDecode(resp.body);
      if (list is! List) return [];
      final result = list.whereType<Map<String, dynamic>>().toList();
      if (result.isNotEmpty) try { await _cache.setList(cacheKey, result); } catch (_) {}
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('[Backend getDividends] $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getSplits(String symbol) async {
    final sym = symbol.trim();
    if (sym.isEmpty) return [];
    final cacheKey = 'backend_splits_$sym';
    final cached = await _cache.getList(cacheKey, maxAge: _companyActionsMaxAge);
    if (cached != null && cached.isNotEmpty) return cached.whereType<Map<String, dynamic>>().toList();
    final uri = Uri.parse('${_base}api/splits').replace(queryParameters: {'symbol': sym});
    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 10), onTimeout: () => throw Exception('请求超时'));
      if (resp.statusCode != 200) return [];
      final list = jsonDecode(resp.body);
      if (list is! List) return [];
      final result = list.whereType<Map<String, dynamic>>().toList();
      if (result.isNotEmpty) try { await _cache.setList(cacheKey, result); } catch (_) {}
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('[Backend getSplits] $e');
      return [];
    }
  }
}

class BackendForexPairsPage {
  const BackendForexPairsPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.hasMore,
  });

  final List<MarketSearchResult> items;
  final int total;
  final int page;
  final int pageSize;
  final bool hasMore;

  static BackendForexPairsPage? fromJson(Map<String, dynamic> m) {
    final rows = m['items'];
    if (rows is! List) return null;
    final items = <MarketSearchResult>[];
    for (final r in rows) {
      if (r is! Map<String, dynamic>) continue;
      final symbol = (r['symbol'] as String?)?.trim();
      if (symbol == null || symbol.isEmpty) continue;
      final name = (r['name'] as String?)?.trim();
      items.add(MarketSearchResult(
        symbol: symbol,
        name: (name == null || name.isEmpty) ? symbol : name,
        market: (r['market'] as String?) ?? 'forex',
      ));
    }
    return BackendForexPairsPage(
      items: items,
      total: (m['total'] as num?)?.toInt() ?? items.length,
      page: (m['page'] as num?)?.toInt() ?? 1,
      pageSize: (m['pageSize'] as num?)?.toInt() ?? items.length,
      hasMore: m['hasMore'] == true,
    );
    }
}

class BackendCryptoPairsPage {
  const BackendCryptoPairsPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.hasMore,
  });

  final List<MarketSearchResult> items;
  final int total;
  final int page;
  final int pageSize;
  final bool hasMore;

  static BackendCryptoPairsPage? fromJson(Map<String, dynamic> m) {
    final rows = m['items'];
    if (rows is! List) return null;
    final items = <MarketSearchResult>[];
    for (final r in rows) {
      if (r is! Map<String, dynamic>) continue;
      final symbol = (r['symbol'] as String?)?.trim();
      if (symbol == null || symbol.isEmpty) continue;
      final name = (r['name'] as String?)?.trim();
      items.add(MarketSearchResult(
        symbol: symbol,
        name: (name == null || name.isEmpty) ? symbol : name,
        market: (r['market'] as String?) ?? 'crypto',
      ));
    }
    return BackendCryptoPairsPage(
      items: items,
      total: (m['total'] as num?)?.toInt() ?? items.length,
      page: (m['page'] as num?)?.toInt() ?? 1,
      pageSize: (m['pageSize'] as num?)?.toInt() ?? items.length,
      hasMore: m['hasMore'] == true,
    );
  }
}

class BackendStockTickersPage {
  const BackendStockTickersPage({
    required this.items,
    required this.quotes,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.hasMore,
  });

  final List<MarketSearchResult> items;
  final Map<String, MarketQuote> quotes;
  final int total;
  final int page;
  final int pageSize;
  final bool hasMore;

  static BackendStockTickersPage empty({required int page, required int pageSize}) {
    return BackendStockTickersPage(
      items: const [],
      quotes: const {},
      total: 0,
      page: page,
      pageSize: pageSize,
      hasMore: false,
    );
  }

  static BackendStockTickersPage? fromJson(Map<String, dynamic> m) {
    final rows = m['items'];
    if (rows is! List) return null;
    final items = <MarketSearchResult>[];
    final quotes = <String, MarketQuote>{};
    for (final r in rows) {
      if (r is! Map<String, dynamic>) continue;
      final symbol = (r['symbol'] as String?)?.trim().toUpperCase();
      if (symbol == null || symbol.isEmpty) continue;
      final name = (r['name'] as String?)?.trim();
      items.add(MarketSearchResult(
        symbol: symbol,
        name: (name == null || name.isEmpty) ? symbol : name,
        market: (r['market'] as String?) ?? 'stocks',
        stockType: r['stock_type'] as String?,
        is24HourTrading: r['is_24h_trading'] == true,
      ));
      final quote = MarketQuote.fromSnapshotMap({
        'symbol': symbol,
        'name': (name == null || name.isEmpty) ? symbol : name,
        'close': r['close'],
        'change': r['change'],
        'percent_change': r['percent_change'],
        'open': r['open'],
        'high': r['high'],
        'low': r['low'],
        'volume': r['volume'],
        'prev_close': r['prev_close'],
      });
      if (quote != null && !quote.hasError && quote.price > 0) {
        quotes[symbol] = quote;
      }
    }
    return BackendStockTickersPage(
      items: items,
      quotes: quotes,
      total: (m['total'] as num?)?.toInt() ?? items.length,
      page: (m['page'] as num?)?.toInt() ?? 1,
      pageSize: (m['pageSize'] as num?)?.toInt() ?? items.length,
      hasMore: m['hasMore'] == true,
    );
  }
}
