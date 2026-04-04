import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'polygon_realtime.dart';

/// 通过后端 WebSocket 代理订阅 Polygon 行情
/// 前端连 ws://host/ws/quotes，后端用 POLYGON_API_KEY 连 Polygon
/// 发送：{ action: 'subscribe', symbols: ['AAPL','MSFT'] } 或 { action: 'subscribe', symbols: ['*'] } 订阅全部
/// 接收：Polygon 原始格式 { ev: 'T', sym, p, s, t }
class BackendRealtimeClient {
  BackendRealtimeClient({required String baseUrl})
      : _wsUrl = _httpToWs(baseUrl.trim());

  final String _wsUrl;
  WebSocketChannel? _channel;
  final _controller = StreamController<PolygonTradeUpdate>.broadcast();
  bool _closed = false;
  bool _subscribeAll = false;
  List<String> _symbols = [];

  Stream<PolygonTradeUpdate> get stream => _controller.stream;

  static String _httpToWs(String url) {
    if (url.startsWith('https://')) return url.replaceFirst('https://', 'wss://');
    if (url.startsWith('http://')) return url.replaceFirst('http://', 'ws://');
    if (url.startsWith('wss://') || url.startsWith('ws://')) return url;
    return 'ws://$url';
  }

  void connect({List<String> symbols = const [], bool subscribeAll = false}) {
    if (_closed) return;
    if (!subscribeAll && symbols.isEmpty) return;
    _subscribeAll = subscribeAll;
    _symbols = symbols.map((s) => s.trim().toUpperCase()).where((s) => s.isNotEmpty).toList();

    try {
      final uri = Uri.parse(_wsUrl).replace(path: '/ws/quotes');
      _channel = WebSocketChannel.connect(uri);
      _channel!.stream.listen(
        _onMessage,
        onError: (e) => debugPrint('BackendRealtimeClient error: $e'),
        onDone: () {
          if (!_closed) debugPrint('BackendRealtimeClient done');
        },
        cancelOnError: false,
      );
      _channel!.sink.add(jsonEncode({
        'action': 'subscribe',
        'symbols': subscribeAll ? ['*'] : _symbols,
      }));
    } catch (e) {
      debugPrint('BackendRealtimeClient connect: $e');
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
      if (sym == null || sym.isEmpty) return;
      if (!_subscribeAll && !_symbols.contains(sym)) return;
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
