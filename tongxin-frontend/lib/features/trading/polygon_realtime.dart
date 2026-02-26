import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Polygon 股票成交流（WebSocket），实时推送最新价与成交量
/// 文档: https://polygon.io/docs/websocket/stocks/trades
class PolygonRealtime {
  PolygonRealtime({required String apiKey, required String symbol})
      : _apiKey = apiKey,
        _symbol = symbol.trim().toUpperCase();

  final String _apiKey;
  final String _symbol;
  static const _wsUrl = 'wss://socket.polygon.io/stocks';

  WebSocketChannel? _channel;
  final _controller = StreamController<PolygonTradeUpdate>.broadcast();
  bool _closed = false;

  Stream<PolygonTradeUpdate> get stream => _controller.stream;

  void connect() {
    if (_closed || _symbol.isEmpty) return;
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      _channel!.stream.listen(
        _onMessage,
        onError: (e) => debugPrint('PolygonRealtime error: $e'),
        onDone: () {
          if (!_closed) debugPrint('PolygonRealtime done');
        },
        cancelOnError: false,
      );
      // 先认证再订阅
      _channel!.sink.add(jsonEncode({'action': 'auth', 'params': _apiKey}));
      _channel!.sink.add(jsonEncode({'action': 'subscribe', 'params': 'T.$_symbol'}));
    } catch (e) {
      debugPrint('PolygonRealtime connect: $e');
    }
  }

  void _onMessage(dynamic message) {
    if (_closed) return;
    if (message is! String) return;
    try {
      final data = jsonDecode(message);
      if (data is List) {
        for (final item in data) {
          _handleEvent(item);
        }
      } else {
        _handleEvent(data);
      }
    } catch (_) {}
  }

  void _handleEvent(dynamic data) {
    if (data is! Map<String, dynamic>) return;
    final ev = data['ev'] as String?;
    if (ev == 'T') {
      final sym = data['sym'] as String?;
      if (sym != _symbol) return;
      final p = (data['p'] as num?)?.toDouble();
      final s = (data['s'] as num?)?.toInt() ?? 0;
      final t = (data['t'] as num?)?.toInt();
      if (p != null) {
        final update = PolygonTradeUpdate(price: p, size: s, timestampMs: t, symbol: _symbol);
        if (!_controller.isClosed) _controller.add(update);
      }
    }
  }

  void dispose() {
    _closed = true;
    _channel?.sink.close();
    _controller.close();
  }
}

/// 多标的实时成交流：一次连接订阅多个股票，推送带 [symbol]
class PolygonRealtimeMulti {
  PolygonRealtimeMulti({required String apiKey, required List<String> symbols})
      : _apiKey = apiKey,
        _symbols = symbols.map((s) => s.trim().toUpperCase()).where((s) => s.isNotEmpty).toList();

  final String _apiKey;
  final List<String> _symbols;
  static const _wsUrl = 'wss://socket.polygon.io/stocks';

  WebSocketChannel? _channel;
  final _controller = StreamController<PolygonTradeUpdate>.broadcast();
  bool _closed = false;

  Stream<PolygonTradeUpdate> get stream => _controller.stream;

  void connect() {
    if (_closed || _symbols.isEmpty) return;
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      _channel!.stream.listen(
        _onMessage,
        onError: (e) => debugPrint('PolygonRealtimeMulti error: $e'),
        onDone: () {
          if (!_closed) debugPrint('PolygonRealtimeMulti done');
        },
        cancelOnError: false,
      );
      _channel!.sink.add(jsonEncode({'action': 'auth', 'params': _apiKey}));
      for (final sym in _symbols) {
        _channel!.sink.add(jsonEncode({'action': 'subscribe', 'params': 'T.$sym'}));
      }
    } catch (e) {
      debugPrint('PolygonRealtimeMulti connect: $e');
    }
  }

  void _onMessage(dynamic message) {
    if (_closed) return;
    if (message is! String) return;
    try {
      final data = jsonDecode(message);
      if (data is List) {
        for (final item in data) _handleEvent(item);
      } else {
        _handleEvent(data);
      }
    } catch (_) {}
  }

  void _handleEvent(dynamic data) {
    if (data is! Map<String, dynamic>) return;
    final ev = data['ev'] as String?;
    if (ev == 'T') {
      final sym = data['sym'] as String?;
      if (sym == null || !_symbols.contains(sym)) return;
      final p = (data['p'] as num?)?.toDouble();
      final s = (data['s'] as num?)?.toInt() ?? 0;
      final t = (data['t'] as num?)?.toInt();
      if (p != null && !_controller.isClosed) {
        _controller.add(PolygonTradeUpdate(price: p, size: s, timestampMs: t, symbol: sym));
      }
    }
  }

  void dispose() {
    _closed = true;
    _channel?.sink.close();
    _controller.close();
  }
}

/// 单笔成交推送（多标的时 [symbol] 不为空）
class PolygonTradeUpdate {
  const PolygonTradeUpdate({
    required this.price,
    required this.size,
    this.timestampMs,
    this.symbol,
  });
  final double price;
  final int size;
  final int? timestampMs;
  /// 多标的订阅时表示该笔成交所属标的
  final String? symbol;
}
