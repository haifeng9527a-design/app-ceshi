import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 单条行情推送（来自 /ws/market）
class WsQuote {
  const WsQuote({
    required this.symbol,
    required this.price,
    this.change,
    this.percentChange,
    this.market,
    this.open,
    this.high,
    this.low,
    this.volume,
    this.timestamp,
  });

  final String symbol;
  final double price;
  final double? change;
  final double? percentChange;
  final String? market;
  final double? open;
  final double? high;
  final double? low;
  final double? volume;
  final int? timestamp;

  factory WsQuote.fromJson(Map<String, dynamic> j) => WsQuote(
        symbol: j['symbol'] as String,
        price: (j['price'] as num).toDouble(),
        change: j['change'] != null ? (j['change'] as num).toDouble() : null,
        percentChange: j['percent_change'] != null
            ? (j['percent_change'] as num).toDouble()
            : null,
        market: j['market'] as String?,
        open: j['open'] != null ? (j['open'] as num).toDouble() : null,
        high: j['high'] != null ? (j['high'] as num).toDouble() : null,
        low: j['low'] != null ? (j['low'] as num).toDouble() : null,
        volume: j['volume'] != null ? (j['volume'] as num).toDouble() : null,
        timestamp: j['timestamp'] as int?,
      );
}

/// 独立行情 WebSocket 服务：连接 /ws/market，无需 Firebase 鉴权
///
/// 用法：
///   MarketWsService.instance.connect();
///   MarketWsService.instance.subscribe(['BTC/USD', 'ETH/USD']);
///   MarketWsService.instance.quoteStream.listen((q) { ... });
///   MarketWsService.instance.unsubscribe(['BTC/USD']);
class MarketWsService {
  MarketWsService._();
  static final MarketWsService instance = MarketWsService._();

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _disposed = false;
  bool _connecting = false;
  int _generation = 0;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  final Set<String> _subscribedSymbols = {};

  static const int _pingIntervalMs = 20000;
  static const int _maxReconnectMs = 30000;
  int _reconnectAttempts = 0;

  final _quoteController = StreamController<WsQuote>.broadcast();
  final _connectedController = StreamController<bool>.broadcast();

  Stream<WsQuote> get quoteStream => _quoteController.stream;
  Stream<bool> get connectedStream => _connectedController.stream;
  bool get isConnected => _channel != null;
  Set<String> get subscribedSymbols => Set.unmodifiable(_subscribedSymbols);

  String? get _wsUrl {
    final base = dotenv.env['TONGXIN_API_URL']?.trim() ??
        dotenv.env['BACKEND_URL']?.trim();
    if (base == null || base.isEmpty) return null;
    final wsBase = base
        .replaceFirst(RegExp(r'^https://'), 'wss://')
        .replaceFirst(RegExp(r'^http://'), 'ws://')
        .replaceAll(RegExp(r'/$'), '');
    return '$wsBase/ws/market';
  }

  void connect() {
    if (_disposed || _connecting || _channel != null) return;
    final url = _wsUrl;
    if (url == null) {
      debugPrint('[marketWs] TONGXIN_API_URL not set, cannot connect');
      return;
    }
    _doConnect(url);
  }

  void _doConnect(String url) {
    _connecting = true;
    final gen = ++_generation;
    debugPrint('[marketWs] connecting to $url (gen=$gen)');
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _sub = _channel!.stream.listen(
        (raw) {
          if (gen != _generation) return;
          _onMessage(raw);
        },
        onError: (e) {
          if (gen != _generation) return;
          debugPrint('[marketWs] error: $e');
          _onDisconnect();
        },
        onDone: () {
          if (gen != _generation) return;
          debugPrint('[marketWs] disconnected');
          _onDisconnect();
        },
        cancelOnError: true,
      );
      _connecting = false;
      _reconnectAttempts = 0;
      _connectedController.add(true);
      _startPing();
      // 重连后自动补发订阅
      if (_subscribedSymbols.isNotEmpty) {
        _sendRaw({'type': 'subscribe', 'symbols': _subscribedSymbols.toList()});
      }
    } catch (e) {
      _connecting = false;
      debugPrint('[marketWs] connect failed: $e');
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = msg['type'] as String?;
    if (type == 'quote') {
      try {
        _quoteController.add(WsQuote.fromJson(msg));
      } catch (e) {
        debugPrint('[marketWs] parse error: $e');
      }
    }
    // type == 'connected' / 'pong' / 'subscribed' — 静默忽略
  }

  void _onDisconnect() {
    _channel = null;
    _sub?.cancel();
    _sub = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    _connectedController.add(false);
    if (!_disposed) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delay =
        (1000 * (1 << _reconnectAttempts.clamp(0, 5))).clamp(1000, _maxReconnectMs);
    _reconnectAttempts++;
    final url = _wsUrl;
    if (url == null) return;
    debugPrint('[marketWs] reconnect in ${delay}ms (attempt=$_reconnectAttempts)');
    _reconnectTimer =
        Timer(Duration(milliseconds: delay), () => _doConnect(url));
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(
      const Duration(milliseconds: _pingIntervalMs),
      (_) => _sendRaw({'type': 'ping'}),
    );
  }

  void _sendRaw(Map<String, dynamic> payload) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(payload));
    } catch (e) {
      debugPrint('[marketWs] send error: $e');
    }
  }

  /// 订阅 symbols，已连接时立即发送，未连接时暂存待重连后补发
  void subscribe(List<String> symbols) {
    if (symbols.isEmpty) return;
    final normalized = symbols.map((s) => s.toUpperCase()).toList();
    _subscribedSymbols.addAll(normalized);
    if (_channel != null) {
      _sendRaw({'type': 'subscribe', 'symbols': normalized});
    } else {
      connect();
    }
  }

  /// 取消订阅
  void unsubscribe(List<String> symbols) {
    if (symbols.isEmpty) return;
    final normalized = symbols.map((s) => s.toUpperCase()).toList();
    for (final s in normalized) {
      _subscribedSymbols.remove(s);
    }
    _sendRaw({'type': 'unsubscribe', 'symbols': normalized});
  }

  /// 替换全部订阅（滚动换页时调用）
  void replaceSubscriptions(List<String> symbols) {
    final next = symbols.map((s) => s.toUpperCase()).toSet();
    final toRemove = _subscribedSymbols.difference(next).toList();
    final toAdd = next.difference(_subscribedSymbols).toList();
    if (toRemove.isNotEmpty) unsubscribe(toRemove);
    if (toAdd.isNotEmpty) subscribe(toAdd);
  }

  void disconnect() {
    _generation++;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _sub = null;
    _connecting = false;
  }

  void dispose() {
    _disposed = true;
    disconnect();
    _quoteController.close();
    _connectedController.close();
  }
}
