import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/supabase_bootstrap.dart';
import 'polygon_repository.dart';

/// 领涨/领跌快照存 Supabase，休市时新用户或本地无缓存时从此读取
class MarketSnapshotRepository {
  static const _table = 'market_snapshots';

  bool get isAvailable => SupabaseBootstrap.isReady;

  /// 从 Supabase 读取最近一次领涨快照
  Future<List<PolygonGainer>> getGainers({int limit = 20}) async {
    if (!isAvailable) return [];
    try {
      final res = await SupabaseBootstrap.client
          .from(_table)
          .select('payload')
          .eq('type', 'gainers')
          .maybeSingle();
      final payload = res?['payload'];
      if (payload is! List || payload.isEmpty) return [];
      return _parsePayload(payload, limit);
    } catch (e) {
      debugPrint('MarketSnapshotRepository getGainers: $e');
      return [];
    }
  }

  /// 从 Supabase 读取最近一次领跌快照
  Future<List<PolygonGainer>> getLosers({int limit = 20}) async {
    if (!isAvailable) return [];
    try {
      final res = await SupabaseBootstrap.client
          .from(_table)
          .select('payload')
          .eq('type', 'losers')
          .maybeSingle();
      final payload = res?['payload'];
      if (payload is! List || payload.isEmpty) return [];
      return _parsePayload(payload, limit);
    } catch (e) {
      debugPrint('MarketSnapshotRepository getLosers: $e');
      return [];
    }
  }

  List<PolygonGainer> _parsePayload(List<dynamic> payload, int limit) {
    final list = <PolygonGainer>[];
    for (var i = 0; i < payload.length && list.length < limit; i++) {
      final t = payload[i];
      if (t is Map<String, dynamic>) {
        final g = PolygonGainer.fromJson(t);
        if (g != null) list.add(g);
      }
    }
    return list;
  }

  /// 写入领涨快照（开市时 Polygon 返回数据后调用）
  Future<void> saveGainers(List<Map<String, dynamic>> rawList) async {
    if (!isAvailable || rawList.isEmpty) return;
    try {
      await SupabaseBootstrap.client.from(_table).upsert(
        {
          'type': 'gainers',
          'payload': rawList,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'type',
      );
    } catch (e) {
      debugPrint('MarketSnapshotRepository saveGainers: $e');
    }
  }

  /// 写入领跌快照
  Future<void> saveLosers(List<Map<String, dynamic>> rawList) async {
    if (!isAvailable || rawList.isEmpty) return;
    try {
      await SupabaseBootstrap.client.from(_table).upsert(
        {
          'type': 'losers',
          'payload': rawList,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'type',
      );
    } catch (e) {
      debugPrint('MarketSnapshotRepository saveLosers: $e');
    }
  }

  /// 从 Supabase 读取指数/外汇/加密货币快照（payload 为 [{symbol, name, close, change, percent_change}, ...]）
  Future<List<Map<String, dynamic>>> getQuotes(String type) async {
    if (!isAvailable) return [];
    try {
      final res = await SupabaseBootstrap.client
          .from(_table)
          .select('payload')
          .eq('type', type)
          .maybeSingle();
      final payload = res?['payload'];
      if (payload is! List || payload.isEmpty) return [];
      return payload
          .whereType<Map<String, dynamic>>()
          .where((m) => m['symbol'] != null)
          .toList();
    } catch (e) {
      debugPrint('MarketSnapshotRepository getQuotes($type): $e');
      return [];
    }
  }

  /// 写入指数/外汇/加密货币快照
  Future<void> saveQuotes(
    String type,
    List<Map<String, dynamic>> list,
  ) async {
    if (!isAvailable || list.isEmpty) return;
    try {
      await SupabaseBootstrap.client.from(_table).upsert(
        {
          'type': type,
          'payload': list,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'type',
      );
    } catch (e) {
      debugPrint('MarketSnapshotRepository saveQuotes($type): $e');
    }
  }
}
