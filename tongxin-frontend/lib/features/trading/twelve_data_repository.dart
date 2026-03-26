import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'polygon_repository.dart';
import 'trading_cache.dart';

/// Twelve Data API 封装：全球指数、外汇、加密货币
/// 提供行情（最新价、涨跌）、K 线/分时（OHLCV）
/// 需在 .env 配置 TWELVE_DATA_API_KEY，见 https://twelvedata.com
class TwelveDataRepository {
  TwelveDataRepository() : _apiKey = dotenv.env['TWELVE_DATA_API_KEY']?.trim();

  final String? _apiKey;
  static const _base = 'https://api.twelvedata.com';
  final _cache = TradingCache.instance;
  static const _symbolsCacheMaxAge = Duration(days: 7);

  bool get isAvailable => _apiKey != null && _apiKey!.isNotEmpty;

  /// 实时报价：最新价、涨跌、涨跌幅、开盘/高低、成交量（若有）
  /// symbol: 美股 AAPL；指数 DJI, SPX, NDX, IXIC；外汇 EUR/USD；加密货币 BTC/USD
  Future<TwelveDataQuote?> getQuote(String symbol) async {
    if (!isAvailable) return null;
    final sym = symbol.trim();
    if (sym.isEmpty) return null;
    final cacheKey = 'td_quote_$sym';
    final cached =
        await _cache.get(cacheKey, maxAge: const Duration(seconds: 30));
    if (cached is Map<String, dynamic>) {
      return TwelveDataQuote.fromJson(cached, symbol: sym);
    }
    try {
      final uri = Uri.parse('$_base/quote').replace(
        queryParameters: {'symbol': sym, 'apikey': _apiKey!},
      );
      final resp = await http.get(uri).timeout(
            const Duration(seconds: 12),
            onTimeout: () => throw Exception('请求超时'),
          );
      if (resp.statusCode != 200) {
        if (kDebugMode) {
          final body = resp.body.length > 200
              ? '${resp.body.substring(0, 200)}…'
              : resp.body;
          debugPrint(
              '[Twelve getQuote $sym] HTTP ${resp.statusCode} body=$body');
        }
        return null;
      }
      final map = jsonDecode(resp.body) as Map<String, dynamic>?;
      if (map == null) return null;
      // Twelve Data 错误时仍返回 200，body 含 code 和 message
      final code = map['code'];
      if (code != null && code != 200 && code != 0) {
        debugPrint('TwelveData quote $sym: code=$code ${map['message']}');
        return null;
      }
      final q = TwelveDataQuote.fromJson(map, symbol: sym);
      if (q != null) {
        await _cache.set(cacheKey, map);
      } else if (kDebugMode && map.isNotEmpty) {
        debugPrint(
            'TwelveData quote $sym: parse failed, keys=${map.keys.toList()}');
      }
      return q;
    } catch (e) {
      debugPrint('TwelveDataRepository getQuote($symbol): $e');
      return null;
    }
  }

  /// 批量报价（一次请求多个 symbol，减少限流、提高成功率）
  /// 返回 symbol -> quote，解析失败的 symbol 不在 map 中
  Future<Map<String, TwelveDataQuote?>> getQuotes(List<String> symbols) async {
    final out = <String, TwelveDataQuote?>{};
    if (!isAvailable || symbols.isEmpty) return out;
    final list =
        symbols.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (list.isEmpty) return out;
    try {
      final uri = Uri.parse('$_base/quote').replace(
        queryParameters: {'symbol': list.join(','), 'apikey': _apiKey!},
      );
      final resp = await http.get(uri).timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('请求超时'),
          );
      if (resp.statusCode != 200) {
        if (kDebugMode) {
          final body = resp.body.length > 200
              ? '${resp.body.substring(0, 200)}…'
              : resp.body;
          debugPrint('[Twelve getQuotes] HTTP ${resp.statusCode} body=$body');
        }
        return out;
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is! Map<String, dynamic>) continue;
          final sym = item['symbol'] as String?;
          if (sym == null) continue;
          final code = item['code'];
          if (code != null && code != 200 && code != 0) {
            debugPrint('TwelveData quote $sym: code=$code ${item['message']}');
            continue;
          }
          final q = TwelveDataQuote.fromJson(item, symbol: sym);
          if (q != null) {
            out[sym] = q;
            await _cache.set('td_quote_$sym', item);
          }
        }
        return out;
      }
      if (decoded is Map<String, dynamic>) {
        // 批量 quote 常见返回：{ "EUR/USD": {...}, "USD/JPY": {...} }
        // 该结构没有 data 字段，顶层 key 即 symbol。
        var parsedAnyFromSymbolMap = false;
        for (final e in decoded.entries) {
          final sym = e.key.trim();
          final item = e.value;
          if (sym.isEmpty || item is! Map<String, dynamic>) continue;
          final q = TwelveDataQuote.fromJson(item, symbol: sym);
          if (q != null) {
            out[sym] = q;
            await _cache.set('td_quote_$sym', item);
            parsedAnyFromSymbolMap = true;
          }
        }
        if (parsedAnyFromSymbolMap) return out;

        final code = decoded['code'];
        if (code != null && code != 200 && code != 0) {
          debugPrint('TwelveData getQuotes: code=$code ${decoded['message']}');
          return out;
        }
        final data = decoded['data'];
        if (data is List) {
          for (final item in data) {
            if (item is! Map<String, dynamic>) continue;
            final sym = item['symbol'] as String? ?? item['symbol']?.toString();
            if (sym == null || sym.isEmpty) continue;
            final q = TwelveDataQuote.fromJson(item, symbol: sym);
            if (q != null) {
              out[sym] = q;
              await _cache.set('td_quote_$sym', item);
            }
          }
          return out;
        }
        if (data is Map) {
          for (final e in data.entries) {
            final sym = e.key is String ? e.key as String : e.key?.toString();
            if (sym == null || sym.isEmpty) continue;
            final item = e.value;
            if (item is! Map<String, dynamic>) continue;
            final q = TwelveDataQuote.fromJson(item, symbol: sym);
            if (q != null) {
              out[sym] = q;
              await _cache.set('td_quote_$sym', item);
            }
          }
          return out;
        }
        // 单条响应（只请求了一个 symbol 时）
        final sym = list.isNotEmpty ? list.first : decoded['symbol'] as String?;
        if (sym != null) {
          final q = TwelveDataQuote.fromJson(decoded, symbol: sym);
          if (q != null) {
            out[sym] = q;
            await _cache.set('td_quote_$sym', decoded);
          }
        }
      }
    } catch (e) {
      debugPrint('TwelveDataRepository getQuotes: $e');
    }
    return out;
  }

  /// K 线/分时：OHLCV，可转成 ChartCandle 给现有图表用
  /// interval: 1min, 5min, 15min, 1h, 1day 等
  /// outputsize: 默认 120，最大 5000（付费）
  /// endDateMs: 若设置，只返回时间早于该时间戳的数据（用于加载更早历史）
  Future<List<ChartCandle>> getTimeSeries(
    String symbol, {
    required String interval,
    int outputsize = 120,
    int? endDateMs,
  }) async {
    if (!isAvailable) return [];
    final sym = symbol.trim();
    if (sym.isEmpty) return [];
    final cacheKey = 'td_ts_${sym}_${interval}_${outputsize}_${endDateMs ?? 0}';
    final cached =
        await _cache.getList(cacheKey, maxAge: const Duration(minutes: 2));
    if (cached != null && cached.isNotEmpty) {
      final list = <ChartCandle>[];
      for (final e in cached) {
        if (e is Map<String, dynamic>) {
          final c = TwelveDataBar.fromJson(e);
          if (c != null) list.add(c.toChartCandle());
        }
      }
      if (list.isNotEmpty) return list;
    }
    try {
      final params = <String, String>{
        'symbol': sym,
        'interval': interval,
        'outputsize': outputsize.toString(),
        'apikey': _apiKey!,
      };
      if (endDateMs != null) {
        final end = DateTime.fromMillisecondsSinceEpoch(endDateMs);
        params['end_date'] =
            '${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')} ${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}:${end.second.toString().padLeft(2, '0')}';
      }
      final uri = Uri.parse('$_base/time_series').replace(
        queryParameters: params,
      );
      final resp = await http.get(uri).timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('请求超时'),
          );
      if (resp.statusCode != 200) return [];
      final map = jsonDecode(resp.body) as Map<String, dynamic>?;
      if (map == null) return [];
      final values = map['values'] as List<dynamic>?;
      if (values == null) return [];
      final list = <ChartCandle>[];
      final toCache = <Map<String, dynamic>>[];
      for (final v in values) {
        if (v is! Map<String, dynamic>) continue;
        final bar = TwelveDataBar.fromJson(v);
        if (bar != null) {
          list.add(bar.toChartCandle());
          toCache.add(v);
        }
      }
      if (toCache.isNotEmpty) await _cache.setList(cacheKey, toCache);
      return list;
    } catch (e) {
      debugPrint('TwelveDataRepository getTimeSeries($symbol): $e');
      return [];
    }
  }

  /// 按时间范围加载 K 线（供加载更多历史：olderThanMs -> start/end）
  /// 返回按时间升序的 candles；startDateMs <= bar time < endDateMs
  Future<List<ChartCandle>> getTimeSeriesRange(
    String symbol, {
    required String interval,
    required int startDateMs,
    required int endDateMs,
    int outputsize = 5000,
  }) async {
    if (!isAvailable) return [];
    final sym = symbol.trim();
    if (sym.isEmpty) return [];
    try {
      final startDt = DateTime.fromMillisecondsSinceEpoch(startDateMs);
      final endDt = DateTime.fromMillisecondsSinceEpoch(endDateMs);
      final startStr = _formatDateTimeForApi(startDt);
      final endStr = _formatDateTimeForApi(endDt);
      final params = <String, String>{
        'symbol': sym,
        'interval': interval,
        'start_date': startStr,
        'end_date': endStr,
        'apikey': _apiKey!,
      };
      final uri = Uri.parse('$_base/time_series').replace(
        queryParameters: params,
      );
      final resp = await http.get(uri).timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('请求超时'),
          );
      if (resp.statusCode != 200) {
        if (kDebugMode) {
          final body = resp.body.length > 200
              ? '${resp.body.substring(0, 200)}…'
              : resp.body;
          debugPrint(
              '[Twelve getTimeSeriesRange $sym] HTTP ${resp.statusCode} body=$body');
        }
        return [];
      }
      final map = jsonDecode(resp.body) as Map<String, dynamic>?;
      if (map == null) return [];
      final code = map['code'];
      if (code != null && code != 200 && code != 0) {
        if (kDebugMode)
          debugPrint(
              'TwelveData getTimeSeriesRange $sym: code=$code ${map['message']}');
        return [];
      }
      final values = map['values'] as List<dynamic>?;
      if (values == null) return [];
      final list = <ChartCandle>[];
      for (final v in values) {
        if (v is! Map<String, dynamic>) continue;
        final bar = TwelveDataBar.fromJson(v);
        if (bar != null) list.add(bar.toChartCandle());
      }
      list.sort((a, b) => a.time.compareTo(b.time));
      return list;
    } catch (e) {
      debugPrint('TwelveDataRepository getTimeSeriesRange($symbol): $e');
      return [];
    }
  }

  /// 获取全部外汇交易对列表（symbol + name）
  /// 优先命中本地缓存，失败时返回空列表
  Future<List<TwelveDataInstrument>> getForexPairs() async {
    return _getInstruments(
      endpoint: '/forex_pairs',
      cacheKey: 'td_forex_pairs',
      market: 'forex',
    );
  }

  /// 获取全部加密货币交易对列表（symbol + name）
  /// 优先命中本地缓存，失败时返回空列表
  Future<List<TwelveDataInstrument>> getCryptoPairs() async {
    return _getInstruments(
      endpoint: '/cryptocurrencies',
      cacheKey: 'td_crypto_pairs',
      market: 'crypto',
    );
  }

  Future<List<TwelveDataInstrument>> _getInstruments({
    required String endpoint,
    required String cacheKey,
    required String market,
  }) async {
    final cached = await _cache.getList(cacheKey, maxAge: _symbolsCacheMaxAge);
    if (cached != null && cached.isNotEmpty) {
      final parsed = <TwelveDataInstrument>[];
      for (final e in cached) {
        if (e is! Map<String, dynamic>) continue;
        final symbol = (e['symbol'] as String?)?.trim();
        final name = (e['name'] as String?)?.trim();
        if (symbol == null || symbol.isEmpty) continue;
        parsed.add(TwelveDataInstrument(
          symbol: symbol,
          name: (name == null || name.isEmpty) ? symbol : name,
          market: market,
        ));
      }
      if (parsed.isNotEmpty) return parsed;
    }
    if (!isAvailable) return [];
    try {
      final uri = Uri.parse('$_base$endpoint').replace(
        queryParameters: {'apikey': _apiKey!},
      );
      final resp = await http.get(uri).timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw Exception('请求超时'),
          );
      if (resp.statusCode != 200) return [];
      final map = jsonDecode(resp.body) as Map<String, dynamic>?;
      if (map == null) return [];
      final code = map['code'];
      if (code != null && code != 200 && code != 0) return [];

      final rows = map['data'];
      if (rows is! List) return [];
      final result = <TwelveDataInstrument>[];
      final toCache = <Map<String, dynamic>>[];
      final seen = <String>{};

      for (final row in rows) {
        if (row is! Map<String, dynamic>) continue;
        final symbol = (row['symbol'] as String?)?.trim();
        if (symbol == null || symbol.isEmpty) continue;
        if (!symbol.contains('/')) continue;
        if (seen.contains(symbol)) continue;
        final base = (row['currency_base'] as String?)?.trim();
        final quote = (row['currency_quote'] as String?)?.trim();
        final rowName = (row['name'] as String?)?.trim();
        final name = (rowName != null && rowName.isNotEmpty)
            ? rowName
            : (base != null &&
                    base.isNotEmpty &&
                    quote != null &&
                    quote.isNotEmpty)
                ? '$base/$quote'
                : symbol;
        result.add(TwelveDataInstrument(
          symbol: symbol,
          name: name,
          market: market,
        ));
        toCache.add({'symbol': symbol, 'name': name});
        seen.add(symbol);
      }
      result.sort((a, b) => a.symbol.compareTo(b.symbol));
      if (toCache.isNotEmpty) {
        await _cache.setList(cacheKey, toCache);
      }
      return result;
    } catch (e) {
      debugPrint('TwelveDataRepository _getInstruments($endpoint): $e');
      return [];
    }
  }

  static String _formatDateTimeForApi(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}

class TwelveDataInstrument {
  const TwelveDataInstrument({
    required this.symbol,
    required this.name,
    required this.market,
  });

  final String symbol;
  final String name;
  final String market;
}

/// Twelve Data 报价（quote 接口）
class TwelveDataQuote {
  const TwelveDataQuote({
    required this.symbol,
    required this.close,
    required this.change,
    required this.percentChange,
    this.open,
    this.high,
    this.low,
    this.volume,
  });
  final String symbol;
  final double close;
  final double change;
  final double percentChange;
  final double? open;
  final double? high;
  final double? low;
  final int? volume;

  static TwelveDataQuote? fromJson(Map<String, dynamic> json,
      {required String symbol}) {
    final close = _toDouble(json['close']);
    if (close == null) return null;
    return TwelveDataQuote(
      symbol: symbol,
      close: close,
      change: _toDouble(json['change']) ?? 0,
      percentChange: _toDouble(json['percent_change']) ?? 0,
      open: _toDouble(json['open']),
      high: _toDouble(json['high']),
      low: _toDouble(json['low']),
      volume: _toInt(json['volume']),
    );
  }

  /// 从快照 Map（如 Supabase payload 单项）构建，键可为 snake_case
  static TwelveDataQuote? fromSnapshotMap(Map<String, dynamic> m) {
    final symbol = m['symbol'] as String?;
    final close = _toDouble(m['close']);
    if (symbol == null || close == null) return null;
    return TwelveDataQuote(
      symbol: symbol,
      close: close,
      change: _toDouble(m['change']) ?? 0,
      percentChange: _toDouble(m['percent_change']) ?? 0,
      open: _toDouble(m['open']),
      high: _toDouble(m['high']),
      low: _toDouble(m['low']),
      volume: _toInt(m['volume']),
    );
  }

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

/// Twelve Data 单根 K 线（time_series 里一条）
class TwelveDataBar {
  const TwelveDataBar({
    required this.datetime,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume,
  });
  final String datetime;
  final double open;
  final double high;
  final double low;
  final double close;
  final int? volume;

  double get timeMs {
    final dt = DateTime.tryParse(datetime);
    return dt?.millisecondsSinceEpoch.toDouble() ?? 0;
  }

  ChartCandle toChartCandle() => ChartCandle(
        time: timeMs / 1000.0,
        open: open,
        high: high,
        low: low,
        close: close,
        volume: volume,
      );

  static TwelveDataBar? fromJson(Map<String, dynamic> json) {
    final datetime = json['datetime'] as String?;
    final close = TwelveDataQuote._toDouble(json['close']);
    if (datetime == null || close == null) return null;
    return TwelveDataBar(
      datetime: datetime,
      open: TwelveDataQuote._toDouble(json['open']) ?? close,
      high: TwelveDataQuote._toDouble(json['high']) ?? close,
      low: TwelveDataQuote._toDouble(json['low']) ?? close,
      close: close,
      volume: TwelveDataQuote._toInt(json['volume']),
    );
  }
}
