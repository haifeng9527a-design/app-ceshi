import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../core/firebase_bootstrap.dart';

/// 自选列表持久化（shared_preferences）
class WatchlistRepository {
  WatchlistRepository._();
  static final WatchlistRepository instance = WatchlistRepository._();

  static const String _key = 'market_watchlist';
  DateTime? _lastServerSyncAt;
  static const Duration _serverSyncInterval = Duration(seconds: 20);

  bool get _canSyncServer {
    if (!ApiClient.instance.isAvailable) return false;
    if (!FirebaseBootstrap.isReady) return false;
    return FirebaseAuth.instance.currentUser != null;
  }

  /// 获取自选列表（symbol 列表，顺序保持添加顺序）
  Future<List<String>> getWatchlist({bool forceSync = false}) async {
    try {
      if (_canSyncServer) {
        final now = DateTime.now();
        final shouldSync = forceSync ||
            _lastServerSyncAt == null ||
            now.difference(_lastServerSyncAt!) >= _serverSyncInterval;
        if (shouldSync) {
          await syncFromServerIfLoggedIn();
        }
      }
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_key);
      if (json == null || json.isEmpty) return [];
      final list = jsonDecode(json) as List<dynamic>?;
      if (list == null) return [];
      return list
          .map((e) => e.toString().trim().toUpperCase())
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('WatchlistRepository getWatchlist: $e');
      return [];
    }
  }

  /// App 启动后调用：仅登录状态同步远端自选到本地；未登录不做网络请求
  Future<void> syncFromServerIfLoggedIn() async {
    if (!_canSyncServer) return;
    try {
      final resp = await ApiClient.instance.get('api/watchlist');
      if (resp.statusCode != 200) return;
      final body = jsonDecode(resp.body);
      final symbols = _parseSymbolsFromResponse(body);
      await _save(symbols);
      _lastServerSyncAt = DateTime.now();
    } catch (e) {
      debugPrint('WatchlistRepository syncFromServerIfLoggedIn: $e');
    }
  }

  /// 添加自选（已存在则不重复）
  Future<void> addWatchlist(String symbol) async {
    final s = symbol.trim().toUpperCase();
    if (s.isEmpty) return;
    try {
      final list = await getWatchlist();
      if (list.contains(s)) return;
      if (_canSyncServer) {
        final resp =
            await ApiClient.instance.post('api/watchlist', body: {'symbol': s});
        if (resp.statusCode == 200) {
          final body = jsonDecode(resp.body);
          final symbols = _parseSymbolsFromResponse(body);
          await _save(symbols);
          _lastServerSyncAt = DateTime.now();
          return;
        }
      }
      final next = [...list, s];
      await _save(next);
    } catch (e) {
      debugPrint('WatchlistRepository addWatchlist: $e');
    }
  }

  /// 移除自选
  Future<void> removeWatchlist(String symbol) async {
    final s = symbol.trim().toUpperCase();
    if (s.isEmpty) return;
    try {
      final list = await getWatchlist();
      if (_canSyncServer) {
        final resp = await ApiClient.instance.delete('api/watchlist/$s');
        if (resp.statusCode == 200) {
          final body = jsonDecode(resp.body);
          final symbols = _parseSymbolsFromResponse(body);
          await _save(symbols);
          _lastServerSyncAt = DateTime.now();
          return;
        }
      }
      final next = list.where((x) => x != s).toList();
      await _save(next);
    } catch (e) {
      debugPrint('WatchlistRepository removeWatchlist: $e');
    }
  }

  Future<void> _save(List<String> list) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = <String>[];
    final seen = <String>{};
    for (final item in list) {
      final s = item.trim().toUpperCase();
      if (s.isEmpty || seen.contains(s)) continue;
      seen.add(s);
      normalized.add(s);
    }
    await prefs.setString(_key, jsonEncode(normalized));
  }

  List<String> _parseSymbolsFromResponse(dynamic body) {
    final raw = body is Map<String, dynamic>
        ? body['symbols']
        : (body is List ? body : const <dynamic>[]);
    if (raw is! List) return <String>[];
    final out = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      final s = item.toString().trim().toUpperCase();
      if (s.isEmpty || seen.contains(s)) continue;
      seen.add(s);
      out.add(s);
    }
    return out;
  }
}
