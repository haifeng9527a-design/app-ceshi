import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 自选列表持久化（shared_preferences）
class WatchlistRepository {
  WatchlistRepository._();
  static final WatchlistRepository instance = WatchlistRepository._();

  static const String _key = 'market_watchlist';

  /// 获取自选列表（symbol 列表，顺序保持添加顺序）
  Future<List<String>> getWatchlist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_key);
      if (json == null || json.isEmpty) return [];
      final list = jsonDecode(json) as List<dynamic>?;
      if (list == null) return [];
      return list.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    } catch (e) {
      debugPrint('WatchlistRepository getWatchlist: $e');
      return [];
    }
  }

  /// 添加自选（已存在则不重复）
  Future<void> addWatchlist(String symbol) async {
    final s = symbol.trim();
    if (s.isEmpty) return;
    try {
      final list = await getWatchlist();
      if (list.contains(s)) return;
      list.add(s);
      await _save(list);
    } catch (e) {
      debugPrint('WatchlistRepository addWatchlist: $e');
    }
  }

  /// 移除自选
  Future<void> removeWatchlist(String symbol) async {
    final s = symbol.trim();
    if (s.isEmpty) return;
    try {
      final list = await getWatchlist();
      list.remove(s);
      await _save(list);
    } catch (e) {
      debugPrint('WatchlistRepository removeWatchlist: $e');
    }
  }

  Future<void> _save(List<String> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list));
  }
}
