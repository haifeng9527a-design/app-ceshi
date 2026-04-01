import 'dart:async';
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
export '../trading/polygon_repository.dart'
    show ChartCandle, PolygonBar, PolygonGainer;
export '../trading/polygon_realtime.dart'
    show PolygonRealtime, PolygonRealtimeMulti, PolygonTradeUpdate;

// ---------- Symbol 规范化与降级 ----------

/// 用户 symbol 解析为各数据源实际使用的 symbol
class SymbolResolver {
  SymbolResolver._();

  /// Polygon 常见指数需加 "I:" 前缀（如 I:SPX, I:DJI, I:RUT）
  static const _polygonIndices = {
    'SPX',
    'NDX',
    'DJI',
    'IXIC',
    'VIX',
    'RUT',
    'HSI',
    'N225'
  };

  static const _cryptoBases = {
    'BTC', 'ETH', 'SOL', 'XRP', 'DOGE', 'AVAX', 'BNB', 'ADA', 'DOT',
    'MATIC', 'LINK', 'LTC', 'TRX', 'ATOM', 'UNI', 'USDT', 'USDC',
    'DAI', 'BCH', 'ETC', 'XLM', 'FIL', 'APT', 'ARB', 'OP',
  };

  /// 是否已知指数（走 Polygon 时用 I: 前缀，或 Twelve Data 兜底）
  static bool isIndex(String symbol) {
    return _polygonIndices.contains(symbol.trim().toUpperCase());
  }

  /// 是否外汇（含 / 或 6 位无斜杠如 EURUSD）
  static bool isFx(String symbol) {
    final s = symbol.trim().toUpperCase();
    if (s.contains('/')) return s.length >= 7 && s.contains('/') && !isCrypto(s);
    return s.length == 6 && s.runes.every((r) => r >= 0x41 && r <= 0x5A);
  }

  /// 是否加密货币（含 / 或常见 crypto 代码）
  static bool isCrypto(String symbol) {
    final s = symbol.trim();
    if (s.contains('/')) {
      final parts = s.toUpperCase().split('/');
      if (parts.length == 2) {
        return _cryptoBases.contains(parts[0]) || _cryptoBases.contains(parts[1]);
      }
    }
    final u = s.toUpperCase();
    return _cryptoBases.contains(u) ||
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
  static ({String polygon, String twelve, bool usePolygon, bool useTwelve})
      resolve(String symbol) {
    final s = symbol.trim();
    final u = s.toUpperCase();
    if (s.isEmpty)
      return (polygon: s, twelve: s, usePolygon: false, useTwelve: false);
    if (isUsStock(s)) {
      return (polygon: u, twelve: s, usePolygon: true, useTwelve: false);
    }
    if (isIndex(s)) {
      return (polygon: 'I:$u', twelve: u, usePolygon: true, useTwelve: true);
    }
    if (isFx(s) || isCrypto(s)) {
      return (
        polygon: '',
        twelve: forTwelve(s),
        usePolygon: false,
        useTwelve: true
      );
    }
    return (
      polygon: u,
      twelve: forTwelve(s),
      usePolygon: true,
      useTwelve: true
    );
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
    final url = dotenv.env['TONGXIN_API_URL']?.trim() ??
        dotenv.env['BACKEND_URL']?.trim();
    return (url != null && url.isNotEmpty) ? BackendMarketClient(url) : null;
  }

  final MarketSnapshotRepository _snapshotRepo;
  final StockQuoteCacheRepository _quoteCacheRepo;
  late final PolygonRepository _polygon;
  final TwelveDataRepository _twelve;
  final BackendMarketClient? _backend;
  // 当前需求：统一走后端 API 代理，不在端上直连第三方。
  static const bool _directThirdPartyOnly = false;

  bool get polygonAvailable => useBackend || _polygon.isAvailable;
  bool get twelveDataAvailable => useBackend || _twelve.isAvailable;
  bool get forexBackendAvailable => _backend != null;
  bool get cryptoBackendAvailable => _backend != null;

  /// 是否使用后端代理（有 TONGXIN_API_URL 时 K 线等优先走后端）
  bool get useBackend => !_directThirdPartyOnly && _backend != null;

  /// 是否美股代码（SymbolResolver 判定：非指数、纯字母 1～5 位）
  static bool _isUsStock(String symbol) => SymbolResolver.isUsStock(symbol);

  static Set<String>? _stock24hSymbolsCache;

  static Set<String> _stock24hSymbols() {
    if (_stock24hSymbolsCache != null) return _stock24hSymbolsCache!;
    final raw = dotenv.env['STOCK_24H_SYMBOLS']?.trim() ?? '';
    if (raw.isEmpty) {
      _stock24hSymbolsCache = <String>{};
      return _stock24hSymbolsCache!;
    }
    final set = raw
        .split(RegExp(r'[,\s;|]+'))
        .map((e) => e.trim().toUpperCase())
        .where((e) => e.isNotEmpty)
        .toSet();
    _stock24hSymbolsCache = set;
    return set;
  }

  static bool _is24hStock({
    required String symbol,
    String? name,
    String? type,
    String? primaryExchange,
  }) {
    final s = symbol.trim().toUpperCase();
    if (s.isEmpty) return false;
    if (_stock24hSymbols().contains(s)) return true;
    final n = (name ?? '').toLowerCase();
    if (n.contains('24h') || n.contains('24 hour') || n.contains('overnight')) {
      return true;
    }
    final t = (type ?? '').trim().toUpperCase();
    if (t == '24H') return true;
    final ex = (primaryExchange ?? '').trim().toUpperCase();
    if (ex == 'BOATS' || ex == 'BLUEOCEAN') return true;
    return false;
  }

  // ---------- 搜索 ----------

  /// 搜索标的（股票 + 外汇 + 加密货币）
  Future<List<MarketSearchResult>> searchSymbols(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final out = <MarketSearchResult>[];
    final seen = <String>{};
    void add(MarketSearchResult item) {
      final key = item.symbol.toUpperCase();
      if (seen.contains(key)) return;
      out.add(item);
      seen.add(key);
    }

    if (useBackend) {
      final backendList = await _backend!.search(q);
      for (final item in backendList) {
        add(item);
      }
    } else {
      final list = await _polygon.searchTickers(q, limit: 20);
      for (final r in list) {
        add(MarketSearchResult(
          symbol: r.ticker,
          name: r.name,
          market: r.market,
          stockType: r.type,
          is24HourTrading: _is24hStock(
            symbol: r.ticker,
            name: r.name,
            type: r.type,
            primaryExchange: r.primaryExchange,
          ),
        ));
      }
    }

    // 叠加 Twelve Data 的全量外汇/加密列表检索，保证与股票搜索体验一致
    try {
      final lc = q.toLowerCase();
      final forex = await getAllForexPairs();
      final crypto = await getAllCryptoPairs();
      for (final item in [...forex, ...crypto]) {
        final sym = item.symbol.toLowerCase();
        final name = item.name.toLowerCase();
        if (sym.contains(lc) || name.contains(lc)) {
          add(item);
          if (out.length >= 100) break;
        }
      }
    } catch (_) {}
    return out;
  }

  Future<List<MarketSearchResult>> searchStocks(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    if (useBackend) {
      final backendList = await _backend!.search(q);
      return backendList
          .where((item) => isStockMarket(item.market))
          .toList(growable: false);
    }
    final list = await _polygon.searchTickers(q, limit: 50);
    return list
        .map((r) => MarketSearchResult(
              symbol: r.ticker,
              name: r.name,
              market: r.market ?? 'stocks',
              stockType: r.type,
              is24HourTrading: _is24hStock(
                symbol: r.ticker,
                name: r.name,
                type: r.type,
                primaryExchange: r.primaryExchange,
              ),
            ))
        .toList(growable: false);
  }

  Future<List<MarketSearchResult>> searchForexPairs(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final all = await getAllForexPairs();
    return all.where((item) {
      return item.symbol.toLowerCase().contains(q) ||
          item.name.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  Future<List<MarketSearchResult>> searchCryptoPairs(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final all = await getAllCryptoPairs();
    return all.where((item) {
      return item.symbol.toLowerCase().contains(q) ||
          item.name.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  static String normalizeMarket(String? market) {
    final m = (market ?? '').trim().toLowerCase();
    if (m == 'stocks' || m == 'stock') return 'stocks';
    if (m == 'fx' || m == 'forex') return 'forex';
    if (m == 'crypto' || m == 'cryptocurrency') return 'crypto';
    if (m == 'indices' || m == 'index') return 'indices';
    return m;
  }

  static bool isStockMarket(String? market) =>
      normalizeMarket(market) == 'stocks' ||
      normalizeMarket(market) == 'indices';

  static bool isForexMarket(String? market) =>
      normalizeMarket(market) == 'forex';

  static bool isCryptoMarket(String? market) =>
      normalizeMarket(market) == 'crypto';

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
      _quoteDebugLog(
          sym, 'result', 'hasError=true errorReason=${q.errorReason}');
      return q;
    }
    if (SymbolResolver.isFx(sym)) {
      if (_backend == null) {
        final q = MarketQuote.failed(sym, '外汇仅支持后端 API 数据');
        _quoteDebugLog(
            sym, 'result', 'hasError=true errorReason=${q.errorReason}');
        return q;
      }
      final m = await _backend!.getForexQuotes([sym]);
      return m[sym] ?? m[SymbolResolver.forTwelve(sym)] ?? MarketQuote.failed(sym, '无数据');
    }
    if (useBackend) {
      final m = await _backend!.getQuotes([sym], realtime: realtime);
      return m[sym] ?? MarketQuote.failed(sym, '无数据');
    }
    final r = SymbolResolver.resolve(sym);
    _quoteDebugLog(sym, 'resolve',
        'polygonSymbol=${r.polygon.isEmpty ? "(none)" : r.polygon} twelveSymbol=${r.twelve} usePolygon=${r.usePolygon} useTwelve=${r.useTwelve}');

    if (r.usePolygon && _polygon.isAvailable) {
      try {
        // 优先用 Snapshot（含今开/最高/最低/成交量），与详情页同源，列表也能显示
        final snap = await _polygon.getTickerSnapshot(r.polygon);
        if (snap != null) {
          _quoteDebugLog(sym, 'Polygon', 'snapshot ok');
          final price = snap.price ?? (snap.prevClose ?? 0);
          final prevClose = snap.prevClose;
          final change = (prevClose != null && prevClose > 0)
              ? (price - prevClose)
              : snap.todaysChange;
          final changePercent = (prevClose != null && prevClose > 0)
              ? ((change / prevClose) * 100)
              : snap.todaysChangePerc;
          final q = MarketQuote(
            symbol: sym,
            name: null,
            price: price,
            change: change,
            changePercent: changePercent,
            prevClose: prevClose,
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
          final change = prev != null && prev > 0 && trade != null
              ? trade.price - prev
              : 0.0;
          final changePercent =
              prev != null && prev > 0 ? (change / prev * 100) : 0.0;
          final q = MarketQuote(
            symbol: sym,
            name: null,
            price: price,
            change: change,
            changePercent: changePercent,
            prevClose: prev,
            open: null,
            high: null,
            low: null,
            volume: null,
          );
          _quoteDebugLog(sym, 'result', 'hasError=false');
          return q;
        }
        _quoteDebugLog(
            sym, 'Polygon', 'fail: 无数据(statusCode/body 见上方 Polygon 日志)');
      } catch (e) {
        _quoteDebugLog(sym, 'Polygon', 'fail: $e');
        if (!r.useTwelve) {
          final q = MarketQuote.failed(sym, 'Polygon: $e');
          _quoteDebugLog(
              sym, 'result', 'hasError=true errorReason=${q.errorReason}');
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
        _quoteDebugLog(
            sym, 'result', 'hasError=true errorReason=${q.errorReason}');
        return q;
      }
      final q2 = MarketQuote.failed(sym, 'Twelve Data 无数据');
      _quoteDebugLog(
          sym, 'result', 'hasError=true errorReason=${q2.errorReason}');
      return q2;
    }
    if (!_polygon.isAvailable && !_twelve.isAvailable) {
      final q = MarketQuote.failed(sym, '未配置 API Key');
      _quoteDebugLog(
          sym, 'result', 'hasError=true errorReason=${q.errorReason} (权限/配置)');
      return q;
    }
    final q3 = MarketQuote.failed(sym, '数据源无数据');
    _quoteDebugLog(
        sym, 'result', 'hasError=true errorReason=${q3.errorReason}');
    return q3;
  }

  /// 批量报价（经 SymbolResolver；失败项返回带 errorReason 的 MarketQuote，键为原始 symbol）
  /// 有后端时统一走后端 /api/quotes（后端已含 stock_quote_cache 兜底）
  Future<Map<String, MarketQuote>> getQuotes(List<String> symbols) async {
    if (symbols.isEmpty) return {};
    if (useBackend) return _backend!.getQuotes(symbols);
    final out = <String, MarketQuote>{};
    final twelveRequest = <String>[];
    final fxSymbols = <String>[];
    final stockSymbols = <String>[];
    for (final s in symbols) {
      final sym = s.trim();
      if (sym.isEmpty) continue;
      if (SymbolResolver.isFx(sym)) {
        fxSymbols.add(sym);
        continue;
      }
      final r = SymbolResolver.resolve(sym);
      if (kDebugMode) {
        _quoteDebugLog(sym, 'resolve',
            'polygonSymbol=${r.polygon.isEmpty ? "(none)" : r.polygon} twelveSymbol=${r.twelve} usePolygon=${r.usePolygon} useTwelve=${r.useTwelve}');
      }
      if (!r.usePolygon && !r.useTwelve) {
        out[sym] = MarketQuote.failed(sym, '无法解析 symbol');
        _quoteDebugLog(sym, 'result', 'hasError=true errorReason=无法解析 symbol');
        continue;
      }
      if (r.usePolygon && SymbolResolver.isUsStock(sym)) {
        stockSymbols.add(sym);
      }
      if (r.useTwelve) twelveRequest.add(r.twelve);
    }

    // 美股优先批量拉取，避免逐只请求造成启动阶段“慢慢显示”。
    if (stockSymbols.isNotEmpty && _polygon.isAvailable) {
      try {
        final batch = await _polygon.getBatchSnapshots(stockSymbols);
        for (final s in stockSymbols) {
          final g = batch[s.toUpperCase()];
          if (g == null) continue;
          final price = g.price ?? (g.prevClose ?? 0);
          if (price <= 0) continue;
          final prevClose = g.prevClose;
          final change = (prevClose != null && prevClose > 0)
              ? (price - prevClose)
              : g.todaysChange;
          final changePercent = (prevClose != null && prevClose > 0)
              ? (change / prevClose * 100)
              : g.todaysChangePerc;
          out[s] = MarketQuote(
            symbol: s,
            name: null,
            price: price,
            change: change,
            changePercent: changePercent,
            prevClose: prevClose,
            open: g.dayOpen,
            high: g.dayHigh,
            low: g.dayLow,
            volume: g.dayVolume,
          );
          _quoteDebugLog(s, 'PolygonBatch', 'ok');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[Quote batch] Polygon batch exception: $e');
      }
    }
    if (fxSymbols.isNotEmpty) {
      if (_backend != null) {
        final fxMap = await _backend!.getForexQuotes(fxSymbols);
        for (final s in fxSymbols) {
          out[s] = fxMap[s] ??
              fxMap[SymbolResolver.forTwelve(s)] ??
              MarketQuote.failed(s, '无数据');
        }
      } else {
        for (final s in fxSymbols) {
          out[s] = MarketQuote.failed(s, '外汇仅支持后端 API 数据');
          _quoteDebugLog(
              s, 'result', 'hasError=true errorReason=外汇仅支持后端 API 数据');
        }
      }
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
              _quoteDebugLog(
                  s, 'result', 'hasError=true errorReason=Twelve Data 无数据');
            }
          }
        }
      } catch (e) {
        if (kDebugMode)
          debugPrint('[Quote batch] Twelve request exception: $e');
        for (final sym in symbols) {
          final s = sym.trim();
          if (s.isEmpty) continue;
          final r = SymbolResolver.resolve(s);
          if (r.useTwelve && !out.containsKey(s)) {
            out[s] = MarketQuote.failed(s, 'Twelve Data: $e');
            _quoteDebugLog(s, 'Twelve', 'fail: $e');
            _quoteDebugLog(
                s, 'result', 'hasError=true errorReason=Twelve Data: $e');
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
          _quoteDebugLog(s, 'result',
              'hasError=true errorReason=未配置 TWELVE_DATA_API_KEY (权限/配置)');
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
  Future<List<ChartCandle>> getCandles(String symbol, String interval,
      {int? lastDays, void Function(String)? onError}) async {
    final sym = symbol.trim();
    if (sym.isEmpty) return [];
    if (useBackend)
      return _backend!
          .getCandles(sym, interval, lastDays: lastDays, onError: onError);
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
          multiplier: multiplier,
          timespan: timespan,
          fromMs: fromMs,
          toMs: toMs);
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
        final list = await _twelve.getTimeSeries(r.twelve,
            interval: tdInterval, outputsize: 120);
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
    if (useBackend) {
      return _backend!.getCandlesOlderThan(sym, interval,
          olderThanMs: olderThanMs, limit: limit);
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
          multiplier: multiplier,
          timespan: timespan,
          fromMs: fromMs,
          toMs: toMs);
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
  static List<ChartCandle> mergeAndDedupeCandles(
      List<ChartCandle> prepend, List<ChartCandle> existing) {
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
  Future<List<PolygonGainer>?> getCachedGainersOnly(
      {Duration maxAge = const Duration(hours: 48)}) async {
    // 业务要求：涨跌幅相关榜单数据始终直连第三方，不走后端代理
    return _polygon.getCachedGainersOnly(maxAge: maxAge);
  }

  /// 仅读缓存领跌（不请求 API）
  Future<List<PolygonGainer>?> getCachedLosersOnly(
      {Duration maxAge = const Duration(hours: 48)}) async {
    // 业务要求：涨跌幅相关榜单数据始终直连第三方，不走后端代理
    return _polygon.getCachedLosersOnly(maxAge: maxAge);
  }

  /// 领涨榜（优先后端，否则 Polygon + 缓存/Supabase 回退）
  Future<List<PolygonGainer>> getTopGainers({int limit = 20}) async {
    // 业务要求：涨跌幅相关榜单数据始终直连第三方，不走后端代理
    return _polygon.getTopGainers(limit: limit);
  }

  /// 领跌榜
  Future<List<PolygonGainer>> getTopLosers({int limit = 20}) async {
    // 业务要求：涨跌幅相关榜单数据始终直连第三方，不走后端代理
    return _polygon.getTopLosers(limit: limit);
  }

  static const _usTickersCacheKey = 'us_tickers';
  static const _usTickersCacheMaxAge = Duration(days: 7);

  /// 将报价写入本地 DB（拉取到新数据后调用，供下次秒开）
  /// 同时 upsert 对应 tickers：不存在则新增，存在则更新，保持数据全面
  /// 异步存储，调用方不应 await，避免影响 UI 显示
  Future<void> persistQuotesToLocalDb(Map<String, MarketQuote> quotes) async {
    if (quotes.isEmpty) return;
    try {
      final tickers = quotes.entries
          .where((e) => !e.value.hasError)
          .map((e) => MarketSearchResult(
                symbol: e.key,
                name: e.value.name ?? e.key,
                market: 'stocks',
              ))
          .toList();
      if (tickers.isNotEmpty) {
        await MarketDb.instance.upsertTickers(tickers);
        unawaited(syncTickersToServer(tickers));
      }
      await MarketDb.instance.upsertQuotes(quotes);
    } catch (_) {}
  }

  /// 从本地 DB 读取美股列表+报价（优先，有则秒开）
  Future<({List<MarketSearchResult> tickers, Map<String, MarketQuote> quotes})?>
      getTickersFromLocalDb({
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

  /// 分页从本地 DB 读取美股列表+报价（一次加载 [limit] 条，避免 UI 卡顿）
  Future<({List<MarketSearchResult> tickers, Map<String, MarketQuote> quotes})?>
      getTickersFromLocalDbPage({
    String? sortColumn,
    bool sortAscending = false,
    required int limit,
    int offset = 0,
  }) async {
    try {
      final result = await MarketDb.instance.getTickersAndQuotesPage(
        sortColumn: sortColumn,
        sortAscending: sortAscending,
        limit: limit,
        offset: offset,
      );
      if (result.tickers.isEmpty) return null;
      return result;
    } catch (_) {
      return null;
    }
  }

  /// 本地 DB 中 tickers 总数
  Future<int> getTickerCount() async {
    try {
      return await MarketDb.instance.getTickerCount();
    } catch (_) {
      return 0;
    }
  }

  /// 从后端 stock_quote_cache 读取美股列表（后端代理，避免前端直连 Supabase）
  /// 返回空列表表示后端未配置或表无数据；成功时异步写入本地缓存供下次秒开（不阻塞 UI）
  Future<List<MarketSearchResult>> getTickersFromStockQuoteCache() async {
    if (useBackend) {
      final list = await _backend!.getTickersFromCache();
      if (list != null && list.isNotEmpty) {
        final payload = list
            .map((r) => {
                  's': r.symbol,
                  'n': r.name,
                  'm': r.market,
                  't': r.stockType,
                  'h24': r.is24HourTrading == true ? 1 : 0,
                })
            .toList();
        unawaited(TradingCache.instance.setList(_usTickersCacheKey, payload));
        return list;
      }
      return [];
    }
    final list = await _quoteCacheRepo.getAllTickers();
    if (list.isNotEmpty) {
      final payload =
          list
              .map((r) => {
                    's': r.symbol,
                    'n': r.name,
                    'm': r.market,
                    't': r.stockType,
                    'h24': r.is24HourTrading == true ? 1 : 0,
                  })
              .toList();
      unawaited(TradingCache.instance.setList(_usTickersCacheKey, payload));
    }
    return list;
  }

  /// 仅后端模式：从 stock_quote_cache 按排序字段分页读取（含报价）
  Future<BackendStockTickersPage> getStockTickersPageFromServer({
    required int page,
    required int pageSize,
    required String sortColumn,
    required bool sortAscending,
  }) async {
    if (_backend == null) {
      return BackendStockTickersPage.empty(page: page, pageSize: pageSize);
    }
    return _backend!.getStockTickersPage(
      page: page,
      pageSize: pageSize,
      sortColumn: sortColumn,
      sortAscending: sortAscending,
    );
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
    final raw = await TradingCache.instance
        .getList(_usTickersCacheKey, maxAge: _usTickersCacheMaxAge);
    if (raw == null || raw.isEmpty) return null;
    final list = <MarketSearchResult>[];
    for (final e in raw) {
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
    if (list.isEmpty) return null;
    list.sort((a, b) => a.symbol.compareTo(b.symbol));
    return list;
  }

  /// 全量美股列表（Polygon v3 reference tickers，market=stocks 含各 type，约 8000+ 条）；结果异步写入本地缓存（不阻塞 UI）
  /// 按 symbol 排序以保证跨会话/设备/语言的一致性
  Future<List<MarketSearchResult>> getAllUsTickers() async {
    final list = await _polygon.getAllUsTickers();
    final result = list
        .map((r) => MarketSearchResult(
              symbol: r.ticker,
              name: r.name,
              market: r.market,
              stockType: r.type,
              is24HourTrading: _is24hStock(
                symbol: r.ticker,
                name: r.name,
                type: r.type,
                primaryExchange: r.primaryExchange,
              ),
            ))
        .toList();
    result.sort((a, b) => a.symbol.compareTo(b.symbol));
    if (result.isNotEmpty) {
      final payload = result
          .map((r) => {
                's': r.symbol,
                'n': r.name,
                'm': r.market,
                't': r.stockType,
                'h24': r.is24HourTrading == true ? 1 : 0,
              })
          .toList();
      unawaited(TradingCache.instance.setList(_usTickersCacheKey, payload));
    }
    return result;
  }

  /// 获取全部外汇交易对（symbol + name）
  Future<List<MarketSearchResult>> getAllForexPairs() async {
    if (_backend == null) return [];
    const pageSize = 240;
    var page = 1;
    final all = <MarketSearchResult>[];
    while (true) {
      final chunk = await _backend!.getForexPairsPage(page: page, pageSize: pageSize);
      if (chunk.items.isEmpty) break;
      all.addAll(chunk.items);
      if (!chunk.hasMore) break;
      page += 1;
    }
    return all;
  }

  /// 服务端分页外汇交易对（优先后端；无后端时本地分页兜底）
  Future<BackendForexPairsPage> getForexPairsPage({
    required int page,
    int pageSize = 30,
  }) async {
    if (_backend != null) {
      return _backend!.getForexPairsPage(page: page, pageSize: pageSize);
    }
    return BackendForexPairsPage(
      items: const [],
      total: 0,
      page: page < 1 ? 1 : page,
      pageSize: pageSize <= 0 ? 30 : pageSize,
      hasMore: false,
    );
  }

  /// 从服务端按 symbols 获取外汇报价（会触发后端更新并落库）
  Future<Map<String, MarketQuote>> getForexQuotesBySymbols(
      List<String> symbols) async {
    if (symbols.isEmpty) return {};
    if (_backend != null) return _backend!.getForexQuotes(symbols);
    return {};
  }

  /// 获取全部加密货币交易对（symbol + name）
  Future<List<MarketSearchResult>> getAllCryptoPairs() async {
    if (_backend != null) {
      const pageSize = 240;
      var page = 1;
      final all = <MarketSearchResult>[];
      while (true) {
        final chunk = await _backend!.getCryptoPairsPage(page: page, pageSize: pageSize);
        if (chunk.items.isEmpty) break;
        all.addAll(chunk.items);
        if (!chunk.hasMore) break;
        page += 1;
      }
      return all;
    }
    final list = await _twelve.getCryptoPairs();
    return list
        .map((e) => MarketSearchResult(
              symbol: e.symbol,
              name: e.name,
              market: 'crypto',
            ))
        .toList();
  }

  Future<BackendCryptoPairsPage> getCryptoPairsPage({
    required int page,
    int pageSize = 30,
  }) async {
    if (_backend != null) {
      return _backend!.getCryptoPairsPage(page: page, pageSize: pageSize);
    }
    return BackendCryptoPairsPage(
      items: const [],
      total: 0,
      page: page < 1 ? 1 : page,
      pageSize: pageSize <= 0 ? 30 : pageSize,
      hasMore: false,
    );
  }

  Future<Map<String, MarketQuote>> getCryptoQuotesBySymbols(
      List<String> symbols) async {
    if (symbols.isEmpty) return {};
    if (_backend != null) return _backend!.getCryptoQuotes(symbols);
    return getQuotes(symbols);
  }

  Future<({List<(double, int)> bids, List<(double, int)> asks})> getCryptoDepth(
    String symbol, {
    int limit = 5,
  }) async {
    if (_backend == null) {
      return (bids: const <(double, int)>[], asks: const <(double, int)>[]);
    }
    return _backend!.getCryptoDepth(symbol, limit: limit);
  }

  /// 将股票列表同步到服务器 stock_quote_cache（存在则更新，不存在则新增）
  /// 已停用：后端自行更新 tickers，前端不再调用 upsertTickersToServer
  Future<void> syncTickersToServer(List<MarketSearchResult> tickers) async {
    // 后端自行更新，前端停止调用
    return;
  }

  /// 缓存领涨（短 TTL），用于交易 Tab 等
  Future<List<PolygonGainer>?> getCachedGainers(
      {int limit = 10, Duration maxAge = const Duration(seconds: 60)}) async {
    // 业务要求：涨跌幅相关榜单数据始终直连第三方，不走后端代理
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

  /// 美股前收（详情页涨跌幅等），有后端时从 quote 反推，否则 Polygon /prev
  Future<double?> getPreviousClose(String symbol) async {
    if (!_isUsStock(symbol)) return null;
    if (useBackend) {
      final m = await _backend!.getQuotes([symbol.trim()], realtime: true);
      final q = m[symbol.trim()];
      if (q != null && !q.hasError && q.price > 0 && q.change != 0) {
        return q.price - q.change;
      }
      return null;
    }
    return _polygon.getPreviousClose(symbol);
  }

  /// 当日 OHLC + 成交量 + 昨收：有后端时走后端，否则 Polygon Snapshot
  Future<PolygonGainer?> getDaySnapshot(String symbol) async {
    if (!_isUsStock(symbol)) return null;
    if (useBackend) return _backend!.getDaySnapshot(symbol.trim());
    final resolved = SymbolResolver.forPolygon(symbol.trim());
    if (resolved.isEmpty) return null;
    return _polygon.getTickerSnapshot(resolved);
  }

  /// K 线/分时聚合（自定义时间范围；symbol 经 SymbolResolver 转 Polygon 格式如 I:SPX）
  /// 有后端代理时优先走后端（后端 Polygon 权限更全，可获取股票分钟级数据）
  Future<List<ChartCandle>> getAggregates(
    String symbol, {
    required int multiplier,
    required String timespan,
    required int fromMs,
    required int toMs,
  }) async {
    if (useBackend && _backend != null) {
      final interval = _aggregatesToInterval(multiplier, timespan);
      final list = await _backend!.getCandles(
        symbol.trim(),
        interval,
        fromMs: fromMs,
        toMs: toMs,
        onError: (_) {},
      );
      if (list.isEmpty) return [];
      final startSec = fromMs / 1000.0;
      final endSec = toMs / 1000.0;
      return list
          .where((c) => c.time >= startSec && c.time <= endSec)
          .toList();
    }
    final resolved = SymbolResolver.forPolygon(symbol.trim());
    final bars = await _polygon.getAggregates(
        resolved.isEmpty ? symbol : resolved,
        multiplier: multiplier,
        timespan: timespan,
        fromMs: fromMs,
        toMs: toMs);
    if (bars == null || bars.isEmpty) return [];
    return bars.map((b) => ChartCandle.fromBar(b)).toList();
  }

  static String _aggregatesToInterval(int multiplier, String timespan) {
    if (timespan == 'minute') {
      if (multiplier == 1) return '1min';
      if (multiplier == 5) return '5min';
      if (multiplier == 15) return '15min';
      if (multiplier == 30) return '30min';
      return '5min';
    }
    if (timespan == 'hour') return '1h';
    if (timespan == 'day') return '1day';
    return '1day';
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

  /// 首页热点新闻（英文）
  Future<List<MarketNewsItem>> getHotNews({int limit = 6}) async {
    if (_backend == null) return const [];
    final rows = await _backend!.getHotNews(limit: limit);
    return rows.map(MarketNewsItem.fromMap).whereType<MarketNewsItem>().toList();
  }

  /// 个股新闻（英文）
  Future<List<MarketNewsItem>> getTickerNews(
    String symbol, {
    int limit = 20,
  }) async {
    if (_backend == null) return const [];
    final rows = await _backend!.getTickerNews(symbol, limit: limit);
    return rows.map(MarketNewsItem.fromMap).whereType<MarketNewsItem>().toList();
  }

  /// 个股公告（由新闻流中公告类筛选）
  Future<List<MarketNewsItem>> getTickerAnnouncements(
    String symbol, {
    int limit = 20,
  }) async {
    if (_backend == null) return const [];
    final rows = await _backend!.getTickerAnnouncements(symbol, limit: limit);
    return rows.map(MarketNewsItem.fromMap).whereType<MarketNewsItem>().toList();
  }
}

// ---------- 统一模型（UI 使用） ----------

/// 搜索命中项
class MarketSearchResult {
  const MarketSearchResult({
    required this.symbol,
    required this.name,
    this.market,
    this.stockType,
    this.is24HourTrading,
  });
  final String symbol;
  final String name;

  /// 市场类型：stocks, crypto, fx, indices 等
  final String? market;
  /// 证券类型（如 CS, ETF, ETN, ADRC ...）
  final String? stockType;
  /// 是否 24 小时可交易（来源：配置或启发式识别）
  final bool? is24HourTrading;
}

class MarketNewsItem {
  const MarketNewsItem({
    required this.title,
    required this.url,
    required this.source,
    this.id,
    this.summary,
    this.imageUrl,
    this.publishedAt,
    this.tickers = const [],
    this.isAnnouncement = false,
    this.lang = 'en',
  });

  final String? id;
  final String title;
  final String? summary;
  final String url;
  final String source;
  final String? imageUrl;
  final DateTime? publishedAt;
  final List<String> tickers;
  final bool isAnnouncement;
  final String lang;

  static MarketNewsItem? fromMap(Map<String, dynamic> map) {
    final title = (map['title'] as String?)?.trim() ?? '';
    final url = (map['url'] as String?)?.trim() ?? '';
    if (title.isEmpty || url.isEmpty) return null;
    final source = (map['source'] as String?)?.trim();
    final publishedRaw = (map['published_utc'] ?? map['publishedAt'])?.toString();
    final publishedAt = (publishedRaw == null || publishedRaw.isEmpty)
        ? null
        : DateTime.tryParse(publishedRaw);
    final rawTickers = map['tickers'];
    final tickers = rawTickers is List
        ? rawTickers
            .map((e) => e.toString().trim().toUpperCase())
            .where((e) => e.isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    return MarketNewsItem(
      id: map['id']?.toString(),
      title: title,
      summary: (map['summary'] as String?)?.trim(),
      url: url,
      source: source == null || source.isEmpty ? 'Unknown' : source,
      imageUrl: (map['image_url'] as String?)?.trim(),
      publishedAt: publishedAt,
      tickers: tickers,
      isAnnouncement: map['is_announcement'] == true,
      lang: (map['lang'] as String?)?.trim().isNotEmpty == true
          ? (map['lang'] as String).trim()
          : 'en',
    );
  }
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
    this.quoteVolume,
    this.weightedAvgPrice,
    this.tradeCount,
    this.openTimeMs,
    this.closeTimeMs,
    this.bid,
    this.ask,
    this.bidSize,
    this.askSize,
    this.prevClose,
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
  final double? quoteVolume;
  final double? weightedAvgPrice;
  final int? tradeCount;
  final int? openTimeMs;
  final int? closeTimeMs;

  /// 买一价（Polygon lastQuote，需 Stocks Quote 权限）
  final double? bid;

  /// 卖一价
  final double? ask;

  /// 买一量
  final int? bidSize;

  /// 卖一量
  final int? askSize;
  final double? prevClose;

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
    final prevClose = _toDouble(m['prev_close']);
    final rawChange = _toDouble(m['change']) ?? 0;
    final change = (prevClose != null && prevClose > 0) ? (close - prevClose) : rawChange;
    final changePercent = (prevClose != null && prevClose > 0)
        ? (change / prevClose * 100)
        : (_toDouble(m['percent_change']) ?? 0);
    return MarketQuote(
      symbol: symbol,
      name: m['name'] as String?,
      price: close,
      change: change,
      changePercent: changePercent,
      open: _toDouble(m['open']),
      high: _toDouble(m['high']),
      low: _toDouble(m['low']),
      volume: _toInt(m['volume']),
      quoteVolume: _toDouble(m['quote_volume']),
      weightedAvgPrice: _toDouble(m['weighted_avg_price']),
      tradeCount: _toInt(m['trade_count']),
      openTimeMs: _toInt(m['open_time']),
      closeTimeMs: _toInt(m['close_time']),
      bid: _toDouble(m['bid']),
      ask: _toDouble(m['ask']),
      bidSize: _toInt(m['bidSize']),
      askSize: _toInt(m['askSize']),
      prevClose: prevClose,
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
        if (quoteVolume != null) 'quote_volume': quoteVolume,
        if (weightedAvgPrice != null) 'weighted_avg_price': weightedAvgPrice,
        if (tradeCount != null) 'trade_count': tradeCount,
        if (openTimeMs != null) 'open_time': openTimeMs,
        if (closeTimeMs != null) 'close_time': closeTimeMs,
        if (bid != null) 'bid': bid,
        if (ask != null) 'ask': ask,
        if (bidSize != null) 'bidSize': bidSize,
        if (askSize != null) 'askSize': askSize,
        if (prevClose != null) 'prev_close': prevClose,
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
