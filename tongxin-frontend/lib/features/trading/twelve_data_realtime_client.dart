import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class TwelveDataRealtimeQuote {
  const TwelveDataRealtimeQuote({
    required this.symbol,
    required this.price,
    this.change,
    this.percentChange,
    this.open,
    this.high,
    this.low,
    this.volume,
    this.timestampMs,
  });

  final String symbol;
  final double price;
  final double? change;
  final double? percentChange;
  final double? open;
  final double? high;
  final double? low;
  final int? volume;
  final int? timestampMs;
}

/// 直连 Twelve Data WebSocket：
/// wss://ws.twelvedata.com/v1/quotes/price?apikey=...
class TwelveDataRealtimeClient {
  TwelveDataRealtimeClient()
      : _apiKey = dotenv.env['TWELVE_DATA_API_KEY']?.trim();

  final String? _apiKey;
  static const Duration _reconnectDelay = Duration(seconds: 2);
  WebSocketChannel? _channel;
  final _controller = StreamController<TwelveDataRealtimeQuote>.broadcast();
  bool _closed = false;
  bool _connected = false;
  Set<String> _symbols = <String>{};
  Timer? _reconnectTimer;

  Stream<TwelveDataRealtimeQuote> get stream => _controller.stream;
  bool get isAvailable => _apiKey != null && _apiKey!.isNotEmpty;

  void connect() {
    if (_closed || !isAvailable || _connected) return;
    try {
      final uri = Uri.parse(
        'wss://ws.twelvedata.com/v1/quotes/price?apikey=${Uri.encodeComponent(_apiKey!)}',
      );
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _channel = WebSocketChannel.connect(uri);
      _connected = true;
      _channel!.stream.listen(
        _onMessage,
        onError: (e) {
          debugPrint('TwelveDataRealtimeClient error: $e');
          _handleDisconnected();
        },
        onDone: () {
          _handleDisconnected();
        },
        cancelOnError: false,
      );
      if (_symbols.isNotEmpty) {
        _sendReset();
        _sendSubscribe(_symbols.toList());
      }
    } catch (e) {
      _connected = false;
      debugPrint('TwelveDataRealtimeClient connect: $e');
    }
  }

  void subscribeSymbols(Set<String> symbols) {
    if (_closed) return;
    final normalized = symbols
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    _symbols = normalized;
    if (!_connected) {
      connect();
      return;
    }
    _sendReset();
    if (_symbols.isEmpty) return;
    _sendSubscribe(_symbols.toList());
  }

  void _handleDisconnected() {
    _connected = false;
    _channel = null;
    if (_closed) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null) return;
    _reconnectTimer = Timer(_reconnectDelay, () {
      _reconnectTimer = null;
      connect();
    });
  }

  void _sendReset() {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode({'action': 'reset'}));
    } catch (e) {
      debugPrint('TwelveDataRealtimeClient reset: $e');
    }
  }

  void _sendSubscribe(List<String> symbols) {
    if (_channel == null || symbols.isEmpty) return;
    try {
      const chunkSize = 200;
      for (var i = 0; i < symbols.length; i += chunkSize) {
        final end = (i + chunkSize > symbols.length) ? symbols.length : i + chunkSize;
        final chunk = symbols.sublist(i, end);
        _channel!.sink.add(
          jsonEncode({
            'action': 'subscribe',
            'params': {'symbols': chunk.join(',')},
          }),
        );
      }
    } catch (e) {
      debugPrint('TwelveDataRealtimeClient subscribe: $e');
    }
  }

  void _onMessage(dynamic raw) {
    if (_closed || raw is! String) return;
    dynamic data;
    try {
      data = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (data is List) {
      for (final item in data) {
        _emitQuote(item);
      }
      return;
    }
    _emitQuote(data);
  }

  void _emitQuote(dynamic item) {
    if (item is! Map<String, dynamic>) return;
    final symbol = (item['symbol'] ?? item['s'])?.toString().trim();
    final price = _toDouble(item['price'] ?? item['close'] ?? item['p']);
    if (symbol == null || symbol.isEmpty || price == null || price <= 0) return;
    _controller.add(
      TwelveDataRealtimeQuote(
        symbol: symbol,
        price: price,
        change: _toDouble(item['change']),
        percentChange: _toDouble(item['percent_change'] ?? item['percentChange']),
        open: _toDouble(item['open']),
        high: _toDouble(item['high']),
        low: _toDouble(item['low']),
        volume: _toInt(item['volume']),
        timestampMs: _toInt(item['timestamp'] ?? item['ts'] ?? item['time']),
      ),
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

  void dispose() {
    _closed = true;
    _connected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _channel?.sink.close();
    _controller.close();
  }
}
