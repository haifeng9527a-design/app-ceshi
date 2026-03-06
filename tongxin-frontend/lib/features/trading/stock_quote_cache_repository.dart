import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../market/market_repository.dart';

/// 从 tongxin-backend 读取股票报价缓存（后端代理 Supabase stock_quote_cache）
/// 避免前端直连 Supabase 暴露数据库
class StockQuoteCacheRepository {
  String? get _baseUrl {
    final url = dotenv.env['TONGXIN_API_URL']?.trim();
    if (url != null && url.isNotEmpty) return url.endsWith('/') ? url : '$url/';
    return null;
  }

  bool get isAvailable => _baseUrl != null;

  /// 从后端 stock_quote_cache 读取股票列表（symbol + name），供美股 Tab 展示
  Future<List<MarketSearchResult>> getAllTickers() async {
    if (!isAvailable) return [];
    try {
      final uri = Uri.parse('${_baseUrl}api/tickers-from-cache');
      final resp = await http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('请求超时'),
      );
      if (resp.statusCode != 200) return [];
      final list = jsonDecode(resp.body) as List<dynamic>?;
      if (list == null || list.isEmpty) return [];
      final result = <MarketSearchResult>[];
      final seen = <String>{};
      for (final row in list) {
        if (row is! Map<String, dynamic>) continue;
        final symbol = (row['symbol'] as String?)?.trim();
        if (symbol == null || symbol.isEmpty || seen.contains(symbol)) continue;
        seen.add(symbol);
        final name = row['name'] as String? ?? symbol;
        result.add(MarketSearchResult(
          symbol: symbol,
          name: name,
          market: row['market'] as String?,
          stockType: row['stock_type'] as String?,
          is24HourTrading: row['is_24h_trading'] == true,
        ));
      }
      result.sort((a, b) => a.symbol.compareTo(b.symbol));
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('StockQuoteCacheRepository getAllTickers: $e');
      return [];
    }
  }

  /// 按代码批量从后端读取报价，返回 Map<symbol, MarketQuote>
  /// 后端 /api/quotes 已包含 stock_quote_cache 兜底，此方法供 MarketRepository 在无 backend 时不再直连 Supabase
  Future<Map<String, MarketQuote>> getBySymbols(
    List<String> symbols, {
    Duration? maxAge,
  }) async {
    if (!isAvailable || symbols.isEmpty) return {};
    final trimmed = symbols.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (trimmed.isEmpty) return {};
    try {
      final uri = Uri.parse('${_baseUrl}api/quotes').replace(
        queryParameters: {'symbols': trimmed.join(',')},
      );
      final resp = await http.get(uri).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('请求超时'),
      );
      if (resp.statusCode != 200) return {};
      final map = jsonDecode(resp.body) as Map<String, dynamic>?;
      if (map == null) return {};
      final out = <String, MarketQuote>{};
      for (final sym in trimmed) {
        final raw = map[sym] as Map<String, dynamic>?;
        if (raw != null) {
          final q = MarketQuote.fromSnapshotMap(raw);
          if (q != null) out[sym] = q;
        }
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('StockQuoteCacheRepository getBySymbols: $e');
      return {};
    }
  }
}
