import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../trading/backend_market_client.dart';
import '../trading/market_snapshot_repository.dart';

import 'market_db.dart';
import '../trading/polygon_realtime.dart';
import '../trading/polygon_repository.dart';
import '../trading/stock_quote_cache_repository.dart';
import '../trading/trading_cache.dart';
import '../trading/twelve_data_repository.dart';

// Re-export types so UI only imports market_repository (no direct PolygonRepository)
export '../trading/polygon_repository.dart' show ChartCandle, PolygonBar, PolygonGainer;
export '../trading/polygon_realtime.dart' show PolygonRealtime, PolygonRealtimeMulti, PolygonTradeUpdate;

// ---------- Symbol 规范化与降级 ----------

/// 用户 symbol 解析为各数据源实际使用的 symbol
class SymbolResolver {
  SymbolResolver._();

  /// Polygon 常见指数需加 "I:" 前缀（如 I:SPX, I:DJI, I:RUT）
  static const _polygonIndices = {'SPX', 'NDX', 'DJI', 'IXIC', 'VIX', 'RUT', 'HSI', 'N225'};

  /// 是否已知指数（走 Polygon 时用 I: 前缀，或 Twelve Data 兜底）
  static bool isIndex(String symbol) {
    return _polygonIndices.contains(symbol.trim().toUpperCase());
  }

  /// 是否外汇（含 / 或 6 位无斜杠如 EURUSD）
  static bool isFx(String symbol) {
    final s = symbol.trim().toUpperCase();
    if (s.contains('/')) return s.length >= 7 && s.contains('/');
    return s.length == 6 && s.runes.every((r) => r >= 0x41 && r <= 0x5A);
  }

  /// 是否加密货币（含 / 或常见 crypto 代码）
  static bool isCrypto(String symbol) {
    final s = symbol.trim();
    if (s.contains('/')) return true;
    final u = s.toUpperCase();
    return u == 'BTC' || u == 'ETH' || u == 'SOL' || u == 'XRP' || u == 'DOGE' || u == 'AVAX' ||
        (u.endsWith('USD') && u.length >= 6);
  }

  /// 美股（纯字母 1～5 位，非指数）
  static bool isUsStock(String symbol) {
    final s = symbol.trim().toUpperCase();
    if (s.isEmpty || s.length > 5 || s.contains('/')) return false;
    if (!s.runes.every((r) => r >= 0x41 && r <= 0x5A)) return false;
    return !_polygonIndices.contains(s);
  }

  /// 用于 Polygon 的 symbol：美股原样，指数加 I:
  static String forPolygon(String symbol) {
    final s = symbol.trim().toUpperCase();
    if (s.isEmpty) return symbol;
    if (_polygonIndices.contains(s)) return 'I:$s';
    return s;
  }

  /// 用于 Twelve Data 的 symbol：外汇/加密货币统一为 XXX/YYY
  static String forTwelve(String symbol) {
    final s = symbol.trim();
    if (s.isEmpty) return symbol;
    if (s.contains('/')) return s;
    final u = s.toUpperCase();
    if (u.length == 6 && u.runes.every((r) => r >= 0x41 && r <= 0x5A)) {
      return '${u.substring(0, 3)}/${u.substring(3)}';
    }
    if (u == 'BTC' || u == 'ETH') return '$u/USD';
    return s;
  }

  /// 解析结果：用哪个数据源、对应 symbol
  static ({String polygon, String twelve, bool usePolygon, bool useTwelve}) resolve(String symbol) {
    final s = symbol.trim();
    final u = s.toUpperCase();
    if (s.isEmpty) return (polygon: s, twelve: s, usePolygon: false, useTwelve: false);
    if (isUsStock(s)) {
      return (polygon: u, twelve: s, usePolygon: true, useTwelve: false);
    }
    if (isIndex(s)) {
      return (polygon: 'I:$u', twelve: u, usePolygon: true, useTwelve: true);
    }
    if (isFx(s) || isCrypto(s)) {
      return (polygon: '', twelve: forTwelve(s), usePolygon: false, useTwelve: true);
    }
    return (polygon: u, twelve: forTwelve(s), usePolygon: true, useTwelve: true);
  }
}

/// 统一行情门面：优先走后端代理（TONGXIN_API_URL），否则直连 Polygon + Twelve Data
class MarketRepository {
  MarketRepository()
      : _snapshotRepo = MarketSnapshotRepository(),
        _quoteCacheRepo = StockQuoteCacheRepository(),
        _twelve = TwelveDataRepository(),
        _backend = _createBackend() {
    _polygon = PolygonRepository(
      onFreshGainers: (r) => _snapshotRepo.saveGainers(r),
      onFreshLosers: (r) => _snapshotRepo.saveLosers(r),
      fallbackGainers: () => _snapshotRepo.getGainers(),
      fallbackLosers: () => _snapshotRepo.getLosers(),
    );
  }

  static BackendMarketClient? _createBackend() {
    final url = dotenv.env['TONGXIN_API_URL']?.trim() ?? dotenv.env['BACKEND_URL']?.trim();
    return (url != null && url.isNotEmpty) ? BackendMarketClient(url) : null;
  }

  final MarketSnapshotRepository _snapshotRepo;
  final StockQuoteCacheRepository _quoteCacheRepo;
  late final PolygonRepository _polygon;
  final TwelveDataRepository _twelve;
  final BackendMarketClient? _backend;

  bool get polygonAvailable => _backend != null || _polygon.isAvailable;
  bool get twelveDataAvailable => _backend != null || _twelve.isAvailable;
  /// 是否使用后端代理（有 TONGXIN_API_URL 时 K 线等优先走后端）
  bool get useBackend => _backend != null;

  /// 是否美股代码（SymbolResolver 判定：非指数、纯字母 1～5 位）
  static bool _isUsStock(String symbol) => SymbolResolver.isUsStock(symbol);

  // ---------- 搜索 ----------

  /// 搜索标的（优先后端，否则 Polygon tickers）
  Future<List<MarketSearchResult>> searchSymbols(String query) async {
    if (query.trim().isEmpty) return [];
    if (_backend != null) return _backend!.search(query);
    final list = await _polygon.searchTickers(query.trim(), limit: 20);
    return list.map((r) => MarketSearchResult(symbol: r.ticker, name: r.name, market: r.market)).toList();
  }

  // ---------- 报价 ----------

  /// Debug 仅 debug 模式打印，便于定位：symbol 错 / 限流 / 权限 / 解析错
  static void _quoteDebugLog(String symbol, String stage, String message) {
    if (kDebugMode) debugPrint('[Quote $symbol] $stage: $message');
  }

  /// 单标的报价（经 SymbolResolver 规范化；失败时返回带 errorReason 的 MarketQuote，不返回 null）
  /// [realtime] 为 true 时走后端实时接口（不读缓存，直连 Polygon），用于详情页
  Future<MarketQuote> getQuote(String symbol, {bool realtime = false}) async {
    final sym = symbol.trim();
    if (sym.isEmpty) {
      final q = MarketQuote.failed(sym, 'symbol 为空');
      _quoteDebugLog(sym, 'result', 'hasError=true errorReason=${q.errorReason}');
      return q;
    }
    if (_backend != null) {
      final m = await _backend!.getQuotes([sym], realtime: realtime);
      return m[sym] ?? MarketQuote.failed(sym, '无数据');
    }
    final r = SymbolResolver.resolve(sym);
    _quoteDebugLog(sym, 'resolve', 'polygonSymbol=${r.polygon.isEmpty ? "(none)" : r.polygon} twelveSymbol=${r.twelve} usePolygon=${r.usePolygon} useTwelve=${r.useTwelve}');

    if (r.usePolygon && _polygon.isAvailable) {
      try {
        // 优先用 Snapshot（含今开/最高/最低/成交量），与详情页同源，列表也能显示
        final snap = await _polygon.getTickerSnapshot(r.polygon);
        if (snap != null) {
          _quoteDebugLog(sym, 'Polygon', 'snapshot ok');
          final price = snap.price ?? (snap.prevClose ?? 0);
          final change = snap.todaysChange ?? 0.0;
          final changePercent = snap.todaysChangePerc ?? 0.0;
          final q = MarketQuote(
            symbol: sym,
            name: null,
            price: price,
            change: change,
            changePercent: changePercent,
            open: snap.dayOpen,
            high: snap.dayHigh,
            low: snap.dayLow,
            volume: snap.dayVolume,
          );
          _quoteDebugLog(sym, 'result', 'hasError=false');
          return q;
        }
        final trade = await _polygon.getLastTrade(r.polygon);
        final prev = await _polygon.getPreviousClose(r.polygon);
        if (trade != null || prev != null) {
          _quoteDebugLog(sym, 'Polygon', 'ok (last+prev)');
          final price = trade?.price ?? (prev ?? 0);
          final change = prev != null && prev > 0 && trade != null ? trade.price - prev : 0.0;
          final changePercent = prev != null && prev > 0 ? (change / prev * 100) : 0.0;
          final q = MarketQuote(
            symbol: sym,
            name: null,
            price: price,
            change: change,
            changePercent: changePercent,
            open: null,
            high: null,
            low: null,
            volume: null,
          );
          _quoteDebugLog(sym, 'result', 'hasError=false');
          return q;
        }
        _quoteDebugLog(sym, 'Polygon', 'fail: 无数据(statusCode/body 见上方 Polygon 日志)');
      } catch (e) {
        _quoteDebugLog(sym, 'Polygon', 'fail: $e');
        if (!r.useTwelve) {
          final q = MarketQuote.failed(sym, 'Polygon: $e');
          _quoteDebugLog(sym, 'result', 'hasError=true errorReason=${q.errorReason}');
          return q;
        }
      }
    }
    if (r.useTwelve && _twelve.isAvailable) {
      try {
        final q = await _twelve.getQuote(r.twelve);
        if (q != null) {
          _quoteDebugLog(sym, 'Twelve', 'ok');
          final out = MarketQuote(
            symbol: sym,
            name: null,
            price: q.close,
            change: q.change,
            changePercent: q.percentChange,
            open: q.open,
            high: q.high,
            low: q.low,
            volume: q.volume,
          );
          _quoteDebugLog(sym, 'result', 'hasError=false');
          return out;
        }
        _quoteDebugLog(sym, 'Twelve', 'fail: 无数据');
      } catch (e) {
        _quoteDebugLog(sym, 'Twelve', 'fail: $e');
        final q = MarketQuote.failed(sym, 'Twelve Data: $e');
        _quoteDebugLog(sym, 'result', 'hasError=true errorReason=${q.errorReason}');
        return q;
      }
      final q2 = MarketQuote.failed(sym, 'Twelve Data 无数据');
      _quoteDebugLog(sym, 'result', 'hasError=true errorReason=${q2.errorReason}');
      return q2;
    }
    if (!_polygon.isAvailable && !_twelve.isAvailable) {
      final q = MarketQuote.failed(sym, '未配置 API Key');
      _quoteDebugLog(sym, 'result', 'hasError=true errorReason=${q.errorReason} (权限/配置)');
      return q;
    }
    final q3 = MarketQuote.failed(sym, '数据源无数据');
    _quoteDebugLog(sym, 'result', 'hasError=true errorReason=${q3.errorReason}');
    return q3;
  }

  /// 批量报价（经 SymbolResolver；失败项返回带 errorReason 的 MarketQuote，键为原始 symbol）
  /// 有后端时统一走后端 /api/quotes（后端已含 stock_quote_cache 兜底）
  Future<Map<String, MarketQuote>> getQuotes(List<String> symbols) async {
    if (symbols.isEmpty) return {};
    if (_backend != null) return _backend!.getQuotes(symbols);
    final out = <String, MarketQuote>{};
    final twelveRequest = <String>[];
    for (final s in symbols) {
      final sym = s.trim();
      if (sym.isEmpty) continue;
      final r = SymbolResolver.resolve(sym);
      if (kDebugMode) {
        _quoteDebugLog(sym, 'resolve', 'polygonSymbol=${r.polygon.isEmpty ? "(none)" : r.polygon} twelveSymbol=${r.twelve} usePolygon=${r.usePolygon} useTwelve=${r.useTwelve}');
      }
      if (!r.usePolygon && !r.useTwelve) {
        out[sym] = MarketQuote.failed(sym, '无法解析 symbol');
        _quoteDebugLog(sym, 'result', 'hasError=true errorReason=无法解析 symbol');
        continue;
      }
      if (r.useTwelve) twelveRequest.add(r.twelve);
    }
    if (twelveRequest.isNotEmpty && _twelve.isAvailable) {
      try {
        final twelveUnique = twelveRequest.toSet().toList();
        final tdMap = await _twelve.getQuotes(twelveUnique);
        for (final sym in symbols) {
          final s = sym.trim();
          if (s.isEmpty) continue;
          final r = SymbolResolver.resolve(s);
          if (!r.useTwelve) continue;
          final q = tdMap[r.twelve];
          if (q != null) {
            out[s] = MarketQuote(
              symbol: s,
              name: null,
              price: q.close,
              change: q.change,
              changePercent: q.percentChange,
              open: q.open,
              high: q.high,
              low: q.low,
              volume: q.volume,
            );
            _quoteDebugLog(s, 'Twelve', 'ok');
            _quoteDebugLog(s, 'result', 'hasError=false');
          } else {
            if (!out.containsKey(s)) {
              out[s] = MarketQuote.failed(s, 'Twelve Data 无数据');
              _quoteDebugLog(s, 'Twelve', 'fail: 无数据');
              _quoteDebugLog(s, 'result', 'hasError=true errorReason=Twelve Data 无数据');
            }
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[Quote batch] Twelve request exception: $e');
        for (final sym in symbols) {
          final s = sym.trim();
          if (s.isEmpty) continue;
          final r = SymbolResolver.resolve(s);
          if (r.useTwelve && !out.containsKey(s)) {
            out[s] = MarketQuote.failed(s, 'Twelve Data: $e');
            _quoteDebugLog(s, 'Twelve', 'fail: $e');
            _quoteDebugLog(s, 'result', 'hasError=true errorReason=Twelve Data: $e');
          }
        }
      }
    } else if (twelveRequest.isNotEmpty) {
      for (final sym in symbols) {
        final s = sym.trim();
        if (s.isEmpty) continue;
        final r = SymbolResolver.resolve(s);
        if (r.useTwelve && !r.usePolygon && !out.containsKey(s)) {
          out[s] = MarketQuote.failed(s, '未配置 TWELVE_DATA_API_KEY');
          _quoteDebugLog(s, 'Twelve', 'fail: 未配置 API Key');
          _quoteDebugLog(s, 'result', 'hasError=true errorReason=未配置 TWELVE_DATA_API_KEY (权限/配置)');
        }
      }
    }
    for (final sym in symbols) {
      final s = sym.trim();
      if (s.isEmpty) continue;
      final r = SymbolResolver.resolve(s);
      if (r.usePolygon && !out.containsKey(s)) {
        out[s] = await getQuote(s);
      }
    }
    return out;
  }

  // ---------- K 线 / 分时 ----------

  /// K 线或分时：interval 如 "1min", "5min", "15min", "1h", "1day"（symbol 经 SymbolResolver）
  /// [lastDays] 非 null 时覆盖默认时间范围，用于多日分时（如 2/3/4 天）
  /// [onError] 请求失败时回调，便于界面展示原因
  Future<List<ChartCandle>> getCandles(String symbol, String interval, {int? lastDays, void Function(String)? onError}) async {
    final sym = symbol.trim();
    if (sym.isEmpty) return [];
    if (_backend != null) return _backend!.getCandles(sym, interval, lastDays: lastDays, onError: onError);
    final r = SymbolResolver.resolve(sym);
    final toMs = DateTime.now().millisecondsSinceEpoch;
    int fromMs;
    if (lastDays != null && lastDays > 0) {
      fromMs = toMs - lastDays * 24 * 3600 * 1000;
    } else if (interval == '1day') {
      fromMs = toMs - 60 * 24 * 3600 * 1000;
    } else if (interval == '1h') {
      fromMs = toMs - 72 * 3600 * 1000;
    } else {
      fromMs = toMs - 24 * 3600 * 1000;
    }
    if (r.usePolygon && _polygon.isAvailable) {
      int multiplier = 1;
      String timespan = 'minute';
      if (interval == '1min') {
        multiplier = 1;
        timespan = 'minute';
      } else if (interval == '5min') {
        multiplier = 5;
        timespan = 'minute';
      } else if (interval == '15min') {
        multiplier = 15;
        timespan = 'minute';
      } else if (interval == '30min') {
        multiplier = 30;
        timespan = 'minute';
      } else if (interval == '1h') {
        multiplier = 1;
        timespan = 'hour';
      } else if (interval == '1day') {
        multiplier = 1;
        timespan = 'day';
      } else {
        multiplier = 5;
        timespan = 'minute';
      }
      final bars = await _polygon.getAggregates(r.polygon,
          multiplier: multiplier, timespan: timespan, fromMs: fromMs, toMs: toMs);
      if (bars != null && bars.isNotEmpty) {
        return bars.map((b) => ChartCandle.fromBar(b)).toList();
      }
    }
    if (r.useTwelve && _twelve.isAvailable) {
      final tdInterval = interval == '1day' ? '1day' : interval;
      if (lastDays != null && lastDays > 0) {
        final list = await _twelve.getTimeSeriesRange(
          r.twelve,
          interval: tdInterval,
          startDateMs: fromMs,
          endDateMs: toMs,
          outputsize: lastDays * 500,
        );
        if (list.isNotEmpty) return list;
      } else {
        final list = await _twelve.getTimeSeries(r.twelve, interval: tdInterval, outputsize: 120);
        if (list.isNotEmpty) return list;
      }
    }
    return [];
  }

  /// 分时（当日/近期）：默认 5 分钟线
  Future<List<ChartCandle>> getIntraday(String symbol) async {
    return getCandles(symbol, '5min');
  }

  /// 加载早于指定时间戳的 K 线（用于视口向左拖动加载更多历史）
  /// 返回按时间升序的 bars（oldest first），可直接 prepend 到现有列表
  Future<List<ChartCandle>> getCandlesOlderThan(
    String symbol,
    String interval, {
    required int olderThanMs,
    int limit = 500,
  }) async {
    final sym = symbol.trim();
    if (sym.isEmpty) return [];
    if (_backend != null) {
      return _backend!.getCandlesOlderThan(sym, interval, olderThanMs: olderThanMs, limit: limit);
    }
    final r = SymbolResolver.resolve(sym);
    final toMs = olderThanMs - 1;
    final intervalMs = _intervalMs(interval);
    final fromMs = (olderThanMs - limit * intervalMs).clamp(0, toMs - 1);
    if (r.usePolygon && _polygon.isAvailable) {
      int multiplier = 1;
      String timespan = 'minute';
      if (interval == '1min') {
        multiplier = 1;
        timespan = 'minute';
      } else if (interval == '5min') {
        multiplier = 5;
        timespan = 'minute';
      } else if (interval == '15min') {
        multiplier = 15;
        timespan = 'minute';
      } else if (interval == '30min') {
        multiplier = 30;
        timespan = 'minute';
      } else if (interval == '1h') {
        multiplier = 1;
        timespan = 'hour';
      } else if (interval == '1day') {
        multiplier = 1;
        timespan = 'day';
      } else if (interval == '1week') {
        multiplier = 1;
        timespan = 'week';
      } else if (interval == '1month') {
        multiplier = 1;
        timespan = 'month';
      } else if (interval == '1year') {
        multiplier = 1;
        timespan = 'year';
      } else {
        multiplier = 5;
        timespan = 'minute';
      }
      final bars = await _polygon.getAggregates(r.polygon,
          multiplier: multiplier, timespan: timespan, fromMs: fromMs, toMs: toMs);
      if (bars != null && bars.isNotEmpty) {
        final list = bars.map((b) => ChartCandle.fromBar(b)).toList();
        return list.length > limit ? list.sublist(list.length - limit) : list;
      }
    }
    if (r.useTwelve && _twelve.isAvailable) {
      final tdInterval = interval == '1day' ? '1day' : interval;
      final list = await _twelve.getTimeSeriesRange(
        r.twelve,
        interval: tdInterval,
        startDateMs: fromMs,
        endDateMs: toMs,
        outputsize: limit,
      );
      if (list.length > limit) return list.sublist(list.length - limit);
      return list;
    }
    return [];
  }

  static int _intervalMs(String interval) {
    if (interval == '1day') return 86400 * 1000;
    if (interval == '1week') return 7 * 86400 * 1000;
    if (interval == '1month') return 30 * 86400 * 1000;
    if (interval == '1year') return 365 * 86400 * 1000;
    if (interval == '1h') return 3600 * 1000;
    if (interval == '30min') return 30 * 60 * 1000;
    if (interval == '15min') return 15 * 60 * 1000;
    if (interval == '5min') return 5 * 60 * 1000;
    if (interval == '1min') return 60 * 1000;
    return 5 * 60 * 1000;
  }

  /// 合并 prepend + existing，按 timestamp 升序排序，同一 timestampMs 只保留一根（优先 OHLCV 更完整）
  static List<ChartCandle> mergeAndDedupeCandles(List<ChartCandle> prepend, List<ChartCandle> existing) {
    final combined = [...prepend, ...existing];
    combined.sort((a, b) => a.time.compareTo(b.time));
    final byTsMs = <int, ChartCandle>{};
    for (final c in combined) {
      final ts = (c.time * 1000).round();
      final cur = byTsMs[ts];
      if (cur == null || _candleCompleteness(c) > _candleCompleteness(cur)) {
        byTsMs[ts] = c;
      }
    }
    final keys = byTsMs.keys.toList()..sort();
    return keys.map((k) => byTsMs[k]!).toList();
  }

  static int _candleCompleteness(ChartCandle c) {
    int s = 0;
    if (c.open != 0) s++;
    if (c.high != 0) s++;
    if (c.low != 0) s++;
    if (c.close != 0) s++;
    if (c.volume != null && c.volume! > 0) s++;
    return s;
  }

  // ---------- 美股领涨/领跌 ----------

  /// 仅读缓存领涨（不请求 API），用于首屏秒出；走后端时由后端缓存
  Future<List<PolygonGainer>?> getCachedGainersOnly({Duration maxAge = const Duration(hours: 48)}) async {
    if (_backend != null) return _backend!.getGainers(limit: 20);
    return _polygon.getCachedGainersOnly(maxAge: maxAge);
  }

  /// 仅读缓存领跌（不请求 API）
  Future<List<PolygonGainer>?> getCachedLosersOnly({Duration maxAge = const Duration(hours: 48)}) async {
    if (_backend != null) return _backend!.getLosers(limit: 20);
    return _polygon.getCachedLosersOnly(maxAge: maxAge);
  }

  /// 领涨榜（优先后端，否则 Polygon + 缓存/Supabase 回退）
  Future<List<PolygonGainer>> getTopGainers({int limit = 20}) async {
    if (_backend != null) return _backend!.getGainers(limit: limit);
    return _polygon.getTopGainers(limit: limit);
  }

  /// 领跌榜
  Future<List<PolygonGainer>> getTopLosers({int limit = 20}) async {
    if (_backend != null) return _backend!.getLosers(limit: limit);
    return _polygon.getTopLosers(limit: limit);
  }

  static const _usTickersCacheKey = 'us_tickers';
  static const _usTickersCacheMaxAge = Duration(days: 7);

  /// 将报价写入本地 DB（拉取到新数据后调用，供下次秒开）
  Future<void> persistQuotesToLocalDb(Map<String, MarketQuote> quotes) async {
    if (quotes.isEmpty) return;
    try {
      await MarketDb.instance.upsertQuotes(quotes);
    } catch (_) {}
  }

  /// 从本地 DB 读取美股列表+报价（优先，有则秒开）
  Future<({List<MarketSearchResult> tickers, Map<String, MarketQuote> quotes})?> getTickersFromLocalDb({
    String? sortColumn,
    bool sortAscending = false,
  }) async {
    try {
      final result = await MarketDb.instance.getTickersAndQuotes(
        sortColumn: sortColumn,
        sortAscending: sortAscending,
      );
      if (result.tickers.isEmpty) return null;
      return result;
    } catch (_) {
      return null;
    }
  }

  /// 从后端 stock_quote_cache 读取美股列表（后端代理，避免前端直连 Supabase）
  /// 返回空列表表示后端未配置或表无数据；成功时写入本地缓存供下次秒开
  Future<List<MarketSearchResult>> getTickersFromStockQuoteCache() async {
    if (_backend != null) {
      final list = await _backend!.getTickersFromCache();
      if (list != null && list.isNotEmpty) {
        final payload = list.map((r) => {'s': r.symbol, 'n': r.name, 'm': r.market}).toList();
        await TradingCache.instance.setList(_usTickersCacheKey, payload);
        return list;
      }
      return [];
    }
    final list = await _quoteCacheRepo.getAllTickers();
    if (list.isNotEmpty) {
      final payload = list.map((r) => {'s': r.symbol, 'n': r.name, 'm': r.market}).toList();
      await TradingCache.instance.setList(_usTickersCacheKey, payload);
    }
    return list;
  }

  static const _bundledTickersAsset = 'assets/us_tickers_fallback.json';

  /// 从应用内置资源读取美股列表（S&P 500），用于首次进入无缓存时的秒开
  Future<List<MarketSearchResult>> getBundledUsTickers() async {
    try {
      final raw = await rootBundle.loadString(_bundledTickersAsset);
      final list = jsonDecode(raw) as List<dynamic>?;
      if (list == null || list.isEmpty) return [];
      final result = <MarketSearchResult>[];
      for (final e in list) {
        if (e is! Map<String, dynamic>) continue;
        final s = e['s'] as String?;
        final n = e['n'] as String?;
        if (s == null || s.isEmpty) continue;
        result.add(MarketSearchResult(symbol: s, name: n ?? s, market: null));
      }
      result.sort((a, b) => a.symbol.compareTo(b.symbol));
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('MarketRepository getBundledUsTickers: $e');
      return [];
    }
  }

  /// 从本地缓存读取全量美股列表（若有且未过期），用于首屏秒开
  /// 按 symbol 排序以保证与 getAllUsTickers 一致（旧缓存可能未排序）
  Future<List<MarketSearchResult>?> getCachedUsTickers() async {
    final raw = await TradingCache.instance.getList(_usTickersCacheKey, maxAge: _usTickersCacheMaxAge);
    if (raw == null || raw.isEmpty) return null;
    final list = <MarketSearchResult>[];
    for (final e in raw) {
      if (e is! Map<String, dynamic>) continue;
      final s = e['s'] as String?;
      final n = e['n'] as String?;
      if (s == null || s.isEmpty) continue;
      list.add(MarketSearchResult(symbol: s, name: n ?? s, market: e['m'] as String?));
    }
    if (list.isEmpty) return null;
    list.sort((a, b) => a.symbol.compareTo(b.symbol));
    return list;
  }

  /// 全量美股列表（Polygon v3 reference tickers，market=stocks 含各 type，约 8000+ 条）；结果写入本地缓存
  /// 按 symbol 排序以保证跨会话/设备/语言的一致性
  Future<List<MarketSearchResult>> getAllUsTickers() async {
    final list = await _polygon.getAllUsTickers();
    final result = list.map((r) => MarketSearchResult(symbol: r.ticker, name: r.name, market: r.market)).toList();
    result.sort((a, b) => a.symbol.compareTo(b.symbol));
    if (result.isNotEmpty) {
      final payload = result.map((r) => {'s': r.symbol, 'n': r.name, 'm': r.market}).toList();
      await TradingCache.instance.setList(_usTickersCacheKey, payload);
    }
    return result;
  }

  /// 缓存领涨（短 TTL），用于交易 Tab 等
  Future<List<PolygonGainer>?> getCachedGainers({int limit = 10, Duration maxAge = const Duration(seconds: 60)}) async {
    if (_backend != null) return _backend!.getGainers(limit: limit);
    return _polygon.getCachedGainers(limit: limit, maxAge: maxAge);
  }

  // ---------- 加密货币 ----------

  static const _defaultCryptoSymbols = [
    'BTC/USD',
    'ETH/USD',
    'SOL/USD',
    'XRP/USD',
    'DOGE/USD',
    'AVAX/USD',
  ];
  static const _defaultCryptoNames = {
    'BTC/USD': '比特币',
    'ETH/USD': '以太坊',
    'SOL/USD': 'Solana',
    'XRP/USD': '瑞波币',
    'DOGE/USD': '狗狗币',
    'AVAX/USD': '雪崩',
  };

  /// 加密货币报价（默认常见币种，可传自定义 symbols）
  Future<List<MarketQuote>> getCryptoQuotes([List<String>? symbols]) async {
    final list = symbols ?? _defaultCryptoSymbols;
    if (list.isEmpty) return [];
    final map = await _twelve.getQuotes(list);
    final result = <MarketQuote>[];
    for (final sym in list) {
      final q = map[sym];
      if (q == null) continue;
      result.add(MarketQuote(
        symbol: q.symbol,
        name: _defaultCryptoNames[q.symbol] ?? q.symbol,
        price: q.close,
        change: q.change,
        changePercent: q.percentChange,
        open: q.open,
        high: q.high,
        low: q.low,
        volume: q.volume,
      ));
    }
    return result;
  }

  // ---------- 实时（WebSocket） ----------

  PolygonRealtime? openRealtime(String symbol) {
    return _polygon.openRealtime(symbol);
  }

  PolygonRealtimeMulti? openRealtimeMulti(List<String> symbols) {
    return _polygon.openRealtimeMulti(symbols);
  }

  // ---------- Polygon 直通（仅用于仍需 snapshot/aggregates 精细控制的场景，UI 尽量用上面接口） ----------

  /// 美股前收（详情页涨跌幅等），数据来源：Polygon /v2/aggs/ticker/{sym}/prev
  Future<double?> getPreviousClose(String symbol) async {
    if (!_isUsStock(symbol)) return null;
    return _polygon.getPreviousClose(symbol);
  }

  /// 当日 OHLC + 成交量 + 昨收：详情页直连 Polygon Snapshot，保证实时数据不绕后端
  Future<PolygonGainer?> getDaySnapshot(String symbol) async {
    if (!_isUsStock(symbol)) return null;
    final resolved = SymbolResolver.forPolygon(symbol.trim());
    if (resolved.isEmpty) return null;
    return _polygon.getTickerSnapshot(resolved);
  }

  /// K 线/分时聚合（自定义时间范围；symbol 经 SymbolResolver 转 Polygon 格式如 I:SPX）
  Future<List<ChartCandle>> getAggregates(
    String symbol, {
    required int multiplier,
    required String timespan,
    required int fromMs,
    required int toMs,
  }) async {
    final resolved = SymbolResolver.forPolygon(symbol.trim());
    final bars = await _polygon.getAggregates(resolved.isEmpty ? symbol : resolved,
        multiplier: multiplier, timespan: timespan, fromMs: fromMs, toMs: toMs);
    if (bars == null || bars.isEmpty) return [];
    return bars.map((b) => ChartCandle.fromBar(b)).toList();
  }

  /// 财务比率（市盈率等），仅后端代理时可用
  Future<Map<String, dynamic>?> getKeyRatios(String symbol) async {
    if (_backend == null) return null;
    return _backend!.getKeyRatios(symbol.trim());
  }

  /// 分红历史，仅后端代理时可用
  Future<List<Map<String, dynamic>>> getDividends(String symbol) async {
    if (_backend == null) return [];
    return _backend!.getDividends(symbol.trim());
  }

  /// 拆股历史，仅后端代理时可用
  Future<List<Map<String, dynamic>>> getSplits(String symbol) async {
    if (_backend == null) return [];
    return _backend!.getSplits(symbol.trim());
  }
}

// ---------- 统一模型（UI 使用） ----------

/// 搜索命中项
class MarketSearchResult {
  const MarketSearchResult({
    required this.symbol,
    required this.name,
    this.market,
  });
  final String symbol;
  final String name;
  /// 市场类型：stocks, crypto, fx, indices 等
  final String? market;
}

/// 统一报价（美股来自 Polygon last+prev，其余来自 Twelve Data）
class MarketQuote {
  const MarketQuote({
    required this.symbol,
    required this.price,
    required this.change,
    required this.changePercent,
    this.name,
    this.open,
    this.high,
    this.low,
    this.volume,
    this.errorReason,
  });
  final String symbol;
  final String? name;
  final double price;
  final double change;
  final double changePercent;
  final double? open;
  final double? high;
  final double? low;
  final int? volume;
  /// 非空表示加载失败，UI 可显示「加载失败·点重试」
  final String? errorReason;

  bool get hasError => errorReason != null && errorReason!.isNotEmpty;
  bool get isUp => changePercent >= 0;

  /// 失败时返回的占位报价（不返回 null）
  factory MarketQuote.failed(String symbol, String reason) => MarketQuote(
        symbol: symbol,
        price: 0,
        change: 0,
        changePercent: 0,
        errorReason: reason,
      );

  /// 从缓存/快照 Map 解析（键可为 snake_case：close, percent_change）
  static MarketQuote? fromSnapshotMap(Map<String, dynamic> m) {
    final symbol = m['symbol'] as String?;
    final close = _toDouble(m['close']);
    if (symbol == null || close == null) return null;
    return MarketQuote(
      symbol: symbol,
      name: m['name'] as String?,
      price: close,
      change: _toDouble(m['change']) ?? 0,
      changePercent: _toDouble(m['percent_change']) ?? 0,
      open: _toDouble(m['open']),
      high: _toDouble(m['high']),
      low: _toDouble(m['low']),
      volume: _toInt(m['volume']),
      errorReason: m['error_reason'] as String?,
    );
  }

  /// 转为快照/缓存用 Map
  Map<String, dynamic> toSnapshotMap() => {
        'symbol': symbol,
        if (name != null) 'name': name,
        'close': price,
        'change': change,
        'percent_change': changePercent,
        if (open != null) 'open': open,
        if (high != null) 'high': high,
        if (low != null) 'low': low,
        if (volume != null) 'volume': volume,
        if (errorReason != null) 'error_reason': errorReason,
      };

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}
