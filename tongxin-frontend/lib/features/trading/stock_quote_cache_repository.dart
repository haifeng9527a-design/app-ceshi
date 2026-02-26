import 'package:flutter/foundation.dart';

import '../../core/supabase_bootstrap.dart';
import '../market/market_repository.dart';

/// 从 Supabase stock_quote_cache 表读取股票报价（与后端 supabaseQuoteCache 同表）
/// 用于股票列表优先展示 Supabase 中已有缓存，休市或无实时数据时也能看到最近一次行情
class StockQuoteCacheRepository {
  static const _table = 'stock_quote_cache';

  /// 与后端兜底一致：24 小时内更新过的记录才视为有效
  static const _defaultMaxAgeMs = 24 * 60 * 60 * 1000;

  bool get isAvailable => SupabaseBootstrap.isReady;

  /// 按代码批量从 Supabase 读取报价，返回 Map<symbol, MarketQuote>
  /// [maxAge] 默认 24 小时，只取在此时间内更新过的行
  Future<Map<String, MarketQuote>> getBySymbols(
    List<String> symbols, {
    Duration? maxAge,
  }) async {
    if (!isAvailable || symbols.isEmpty) return {};
    final trimmed = symbols.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (trimmed.isEmpty) return {};
    final symbolsUpper = trimmed.map((s) => s.toUpperCase()).toSet().toList();
    final upperToOriginal = <String, String>{};
    for (final s in trimmed) {
      upperToOriginal[s.toUpperCase()] = s;
    }
    final maxAgeMs = maxAge?.inMilliseconds ?? _defaultMaxAgeMs;
    final since = DateTime.now().toUtc().subtract(Duration(milliseconds: maxAgeMs)).toIso8601String();
    try {
      // 表字段：symbol, name, close, change, percent_change, open, high, low, volume, prev_close, error_reason, updated_at
      final res = await SupabaseBootstrap.client
          .from(_table)
          .select('symbol, name, close, change, percent_change, open, high, low, volume, prev_close, error_reason, updated_at')
          .inFilter('symbol', symbolsUpper)
          .gte('updated_at', since);
      final list = res as List<dynamic>?;
      final out = <String, MarketQuote>{};
      if (list == null) return out;
      for (final row in list) {
        if (row is! Map<String, dynamic>) continue;
        final symbol = row['symbol'] as String?;
        if (symbol == null || symbol.isEmpty) continue;
        final payload = _rowToPayload(row);
        final q = MarketQuote.fromSnapshotMap(payload);
        if (q != null) {
          final key = upperToOriginal[symbol.toUpperCase()] ?? symbol;
          out[key] = q;
        }
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('StockQuoteCacheRepository getBySymbols: $e');
      return {};
    }
  }

  /// 将表的一行转为 fromSnapshotMap 可用的 Map（键：close, change, percent_change 等）
  static Map<String, dynamic> _rowToPayload(Map<String, dynamic> row) {
    return {
      'symbol': row['symbol'],
      'name': row['name'],
      'close': row['close'],
      'change': row['change'],
      'percent_change': row['percent_change'],
      'open': row['open'],
      'high': row['high'],
      'low': row['low'],
      'volume': row['volume'],
      'error_reason': row['error_reason'],
    };
  }
}
