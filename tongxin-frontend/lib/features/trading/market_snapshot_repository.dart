import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import 'polygon_repository.dart';

/// 领涨/领跌快照通过 tongxin-backend 读写（后端代理 Supabase market_snapshots）
/// 避免前端直连 Supabase 暴露数据库
class MarketSnapshotRepository {
  final _api = ApiClient.instance;

  bool get isAvailable => _api.isAvailable;

  /// 从后端读取最近一次领涨快照
  Future<List<PolygonGainer>> getGainers({int limit = 20}) async {
    if (!isAvailable) return [];
    try {
      final resp = await _api.get('api/market/snapshots', queryParameters: {'type': 'gainers'}, withAuth: false);
      if (resp.statusCode != 200) return [];
      final payload = jsonDecode(resp.body);
      if (payload is! List || payload.isEmpty) return [];
      return _parsePayload(payload, limit);
    } catch (e) {
      debugPrint('MarketSnapshotRepository getGainers: $e');
      return [];
    }
  }

  /// 从后端读取最近一次领跌快照
  Future<List<PolygonGainer>> getLosers({int limit = 20}) async {
    if (!isAvailable) return [];
    try {
      final resp = await _api.get('api/market/snapshots', queryParameters: {'type': 'losers'}, withAuth: false);
      if (resp.statusCode != 200) return [];
      final payload = jsonDecode(resp.body);
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
      await _api.put('api/market/snapshots', body: {'type': 'gainers', 'payload': rawList});
    } catch (e) {
      debugPrint('MarketSnapshotRepository saveGainers: $e');
    }
  }

  /// 写入领跌快照
  Future<void> saveLosers(List<Map<String, dynamic>> rawList) async {
    if (!isAvailable || rawList.isEmpty) return;
    try {
      await _api.put('api/market/snapshots', body: {'type': 'losers', 'payload': rawList});
    } catch (e) {
      debugPrint('MarketSnapshotRepository saveLosers: $e');
    }
  }

  /// 从后端读取指数/外汇/加密货币快照（payload 为 [{symbol, name, close, change, percent_change}, ...]）
  Future<List<Map<String, dynamic>>> getQuotes(String type) async {
    if (!isAvailable) return [];
    try {
      final resp = await _api.get('api/market/snapshots', queryParameters: {'type': type}, withAuth: false);
      if (resp.statusCode != 200) return [];
      final payload = jsonDecode(resp.body);
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
      await _api.put('api/market/snapshots', body: {'type': type, 'payload': list});
    } catch (e) {
      debugPrint('MarketSnapshotRepository saveQuotes($type): $e');
    }
  }
}
