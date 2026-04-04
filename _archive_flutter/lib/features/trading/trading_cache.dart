import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 行情/历史数据本地文件缓存，减少重复请求、提升首屏与滑动手感
class TradingCache {
  TradingCache._();
  static final TradingCache instance = TradingCache._();
  bool get _disabledOnWeb => kIsWeb;

  static const String _dirName = 'trading_cache';
  Directory? _dir;
  bool _init = false;

  Future<Directory> _getDir() async {
    if (_disabledOnWeb) {
      throw UnsupportedError('TradingCache disabled on web');
    }
    if (_dir != null) return _dir!;
    if (_init) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return _getDir();
    }
    _init = true;
    try {
      final root = await getApplicationDocumentsDirectory();
      _dir = Directory('${root.path}/$_dirName');
      if (!await _dir!.exists()) await _dir!.create(recursive: true);
    } catch (e) {
      debugPrint('TradingCache _getDir: $e');
    }
    return _dir!;
  }

  /// 文件名长度限制，避免 File name too long (errno 63)
  static const int _maxFileKeyLength = 180;

  int _hashKey(String key) {
    int h = 0;
    for (int i = 0; i < key.length; i++) {
      h = ((h * 31) + key.codeUnitAt(i)) & 0x7fffffff;
    }
    return h;
  }

  String _fileKey(String key) {
    final sanitized = key.replaceAll(RegExp(r'[^\w\-.]'), '_');
    if (sanitized.length <= _maxFileKeyLength) return sanitized;
    return 'h_${_hashKey(key).toRadixString(16)}';
  }

  /// 读取缓存，若不存在或已过期返回 null
  Future<Map<String, dynamic>?> get(String key, {Duration maxAge = const Duration(seconds: 1)}) async {
    if (_disabledOnWeb) return null;
    try {
      final dir = await _getDir();
      final file = File('${dir.path}/${_fileKey(key)}.json');
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final map = jsonDecode(content) as Map<String, dynamic>?;
      if (map == null) return null;
      final cachedAt = map['cachedAt'] as int?;
      if (cachedAt == null) return null;
      final age = DateTime.now().millisecondsSinceEpoch - cachedAt;
      if (age > maxAge.inMilliseconds) return null;
      final data = map['data'];
      if (data is Map<String, dynamic>) return data;
      if (data is List) return {'list': data};
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 读取缓存中的列表（如 gainers、aggregates、candles）
  Future<List<dynamic>?> getList(String key, {Duration maxAge = const Duration(minutes: 1)}) async {
    if (_disabledOnWeb) return null;
    final map = await get(key, maxAge: maxAge);
    if (map == null) return null;
    final list = map['list'] as List<dynamic>?;
    return list;
  }

  /// 读取缓存中的数值（如 previous close）
  Future<double?> getDouble(String key, {Duration maxAge = const Duration(hours: 24)}) async {
    if (_disabledOnWeb) return null;
    final map = await get(key, maxAge: maxAge);
    if (map == null) return null;
    final v = map['v'];
    if (v is num) return v.toDouble();
    return null;
  }

  /// 写入缓存
  Future<void> set(String key, Map<String, dynamic> value, {Duration? maxAge}) async {
    if (_disabledOnWeb) return;
    try {
      final dir = await _getDir();
      final file = File('${dir.path}/${_fileKey(key)}.json');
      final payload = {
        'cachedAt': DateTime.now().millisecondsSinceEpoch,
        'data': value,
      };
      await file.writeAsString(jsonEncode(payload));
    } catch (e) {
      debugPrint('TradingCache set: $e');
    }
  }

  Future<void> setList(String key, List<dynamic> list, {Duration? maxAge}) async {
    if (_disabledOnWeb) return;
    await set(key, {'list': list}, maxAge: maxAge);
  }

  Future<void> setDouble(String key, double value, {Duration? maxAge}) async {
    if (_disabledOnWeb) return;
    await set(key, {'v': value}, maxAge: maxAge);
  }
}
