import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';
import 'firebase_bootstrap.dart';
import '../features/messages/chat_db.dart';
import '../features/messages/message_models.dart';

/// 行情推送（通过 chat WebSocket 复用连接）
class MarketQuoteUpdate {
  const MarketQuoteUpdate({
    required this.symbol,
    required this.price,
    this.size = 0,
    this.timestampMs,
    this.market,
    this.change,
    this.percentChange,
  });
  final String symbol;
  final double price;
  final int size;
  final int? timestampMs;
  final String? market;
  final double? change;
  final double? percentChange;
}

/// 聊天 WebSocket 服务：App 启动时连接，断线重连
/// 连接 ws://host/ws/chat?token=Firebase_Token
/// 发送：{ type: 'subscribe', conversation_ids: [...] }
/// 发送：{ type: 'subscribe_market', symbols: ['AAPL','EUR/USD'] }
/// 发送：{ type: 'send', conversation_id, content, ... }
/// 接收：{ type: 'new_message', message: {...} }
/// 接收：{ type: 'market_quote', symbol, price, market?, ... }
class ChatWebSocketService {
  ChatWebSocketService._();
  static final ChatWebSocketService instance = ChatWebSocketService._();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  String? _currentUserId;
  final Set<String> _subscribedIds = {};
  Set<String> _lastSentSubscribedIds = {};
  int _reconnectAttempts = 0;
  int _connectionGeneration = 0;
  static const int _maxReconnectDelayMs = 30000;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  static const int _heartbeatIntervalMs = 20000; // 20 秒，防止 Render 等代理因空闲关闭连接
  bool _disposed = false;
  bool _isConnecting = false;
  final Set<String> _marketSymbols = {};
  final _marketQuoteController = StreamController<MarketQuoteUpdate>.broadcast();
  final _callInvitationController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool get isConnected => _channel != null;
  Set<String> get subscribedConversationIds => Set<String>.from(_subscribedIds);

  /// 行情推送流（通过 chat WebSocket 复用，后端 ingestors 写入时推送）
  Stream<MarketQuoteUpdate> get marketQuoteStream => _marketQuoteController.stream;
  Stream<Map<String, dynamic>> get callInvitationStream =>
      _callInvitationController.stream;

  String? get _wsBaseUrl {
    final url = dotenv.env['TONGXIN_API_URL']?.trim();
    if (url == null || url.isEmpty) return null;
    final u = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    if (u.startsWith('https://')) return u.replaceFirst('https://', 'wss://');
    if (u.startsWith('http://')) return u.replaceFirst('http://', 'ws://');
    return 'wss://$u';
  }

  /// 在已连接且用户相同时不重复连接，避免 authStateChanges（如 token 刷新）触发频繁断开重连
  Future<void> connectIfNeeded(String userId) async {
    if (_currentUserId == userId &&
        (_channel != null || _isConnecting || _reconnectTimer != null)) {
      return;
    }
    await connect();
  }

  /// App 启动时调用，需在 Firebase 登录后
  Future<void> connect() async {
    if (_disposed) return;
    if (_isConnecting) return;
    if (!ApiClient.instance.isAvailable || !FirebaseBootstrap.isReady) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final base = _wsBaseUrl;
    if (base == null) return;

    final token = await user.getIdToken();
    if (token == null || token.isEmpty) return;

    final previousChannel = _channel;
    final previousSubscription = _subscription;
    final generation = ++_connectionGeneration;
    _isConnecting = true;
    _currentUserId = user.uid;
    final uri = Uri.parse('$base/ws/chat?token=$token');
    if (kDebugMode) debugPrint('[ChatWs] 正在连接 $base/ws/chat');
    try {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _channel = null;
      _subscription = null;
      _stopHeartbeat();

      if (previousSubscription != null) {
        unawaited(previousSubscription.cancel());
      }
      if (previousChannel != null) {
        try {
          previousChannel.sink.close();
        } catch (_) {}
      }

      final channel = WebSocketChannel.connect(uri);
      if (generation != _connectionGeneration) {
        try {
          channel.sink.close();
        } catch (_) {}
        return;
      }
      _channel = channel;

      _subscription = channel.stream.listen(
        _onMessage,
        onError: (e) {
          if (generation != _connectionGeneration) return;
          if (kDebugMode) debugPrint('[ChatWs] error: $e');
          _stopHeartbeat();
          if (identical(_channel, channel)) {
            _channel = null;
            _subscription = null;
          }
          _scheduleReconnect(generation);
        },
        onDone: () {
          if (generation != _connectionGeneration) return;
          if (kDebugMode) debugPrint('[ChatWs] 连接断开');
          _stopHeartbeat();
          if (identical(_channel, channel)) {
            _channel = null;
            _subscription = null;
          }
          if (!_disposed) _scheduleReconnect(generation);
        },
        cancelOnError: false,
      );
      _reconnectAttempts = 0;
      _startHeartbeat(generation);
      if (kDebugMode) debugPrint('[ChatWs] 连接成功 uid=${user.uid.length > 12 ? user.uid.substring(0, 12) : user.uid}');
      // 重连后服务端订阅状态已丢失，这里强制重发一次。
      if (_subscribedIds.isNotEmpty) _sendSubscribe(force: true);
      if (_marketSymbols.isNotEmpty) _sendMarketSubscribe();
    } catch (e) {
      if (generation != _connectionGeneration) return;
      if (kDebugMode) debugPrint('[ChatWs] 连接失败: $e');
      _channel = null;
      _subscription = null;
      _stopHeartbeat();
      _scheduleReconnect(generation);
    } finally {
      if (generation == _connectionGeneration) {
        _isConnecting = false;
      }
    }
  }

  void _startHeartbeat(int generation) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: _heartbeatIntervalMs), (_) {
      if (_channel == null || _disposed || generation != _connectionGeneration) {
        return;
      }
      try {
        _channel!.sink.add(_encode({'type': 'ping'}));
      } catch (_) {}
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _scheduleReconnect(int generation) {
    if (_disposed || _reconnectTimer != null) return;
    if (generation != _connectionGeneration) return;
    _reconnectAttempts++;
    final delayMs = (_reconnectAttempts * 2 * 1000).clamp(2000, _maxReconnectDelayMs);
    if (kDebugMode) debugPrint('[ChatWs] ${delayMs}ms 后重连 (第 $_reconnectAttempts 次)');
    late final Timer timer;
    timer = Timer(Duration(milliseconds: delayMs), () {
      if (!identical(_reconnectTimer, timer)) return;
      _reconnectTimer = null;
      if (_disposed || generation != _connectionGeneration) return;
      connect();
    });
    _reconnectTimer = timer;
  }

  void _onMessage(dynamic data) {
    try {
      final map = data is String ? data : null;
      if (map == null) return;
      final decoded = _parseJson(map);
      if (decoded == null) return;
      final type = decoded['type'] as String?;
      if (type == 'new_message') {
        final msg = decoded['message'];
        if (msg is Map) {
          final m = Map<String, dynamic>.from(msg);
          final convId = (m['conversation_id'] ?? '').toString();
          final sender = (m['sender_id'] ?? '').toString();
          final content = (m['content'] ?? '').toString();
          final preview = content.length > 20 ? '${content.substring(0, 20)}...' : content;
          if (kDebugMode) debugPrint('[ChatWs] 收到新消息 conv=${convId.length > 8 ? convId.substring(0, 8) : convId} sender=${sender.length > 12 ? sender.substring(0, 12) : sender} content=$preview');
          _handleNewMessage(m); // 不 await，避免阻塞
        }
      } else if (type == 'market_quote') {
        final sym = decoded['symbol']?.toString().trim().toUpperCase();
        final price = (decoded['price'] as num?)?.toDouble();
        if (sym != null && sym.isNotEmpty && price != null && price > 0 && !_marketQuoteController.isClosed) {
          if (kDebugMode && _marketSymbols.contains(sym)) {
            debugPrint('[ChatWs] 收到行情 $sym=$price');
          }
          _marketQuoteController.add(MarketQuoteUpdate(
            symbol: sym,
            price: price,
            size: (decoded['size'] as num?)?.toInt() ?? 0,
            timestampMs: (decoded['timestamp'] as num?)?.toInt(),
            market: decoded['market']?.toString(),
            change: (decoded['change'] as num?)?.toDouble(),
            percentChange: (decoded['percent_change'] as num?)?.toDouble(),
          ));
        }
      } else if (type == 'call_invitation') {
        final payload = Map<String, dynamic>.from(decoded);
        if (!_callInvitationController.isClosed) {
          if (kDebugMode) {
            final invitationId = payload['invitationId']?.toString() ?? '';
            final fromUser = payload['fromUserName']?.toString() ?? '对方';
            debugPrint(
              '[ChatWs] 收到来电 invitation=${invitationId.isNotEmpty ? invitationId.substring(0, invitationId.length > 8 ? 8 : invitationId.length) : "-"} from=$fromUser',
            );
          }
          _callInvitationController.add(payload);
        }
      } else if (type == 'error') {
        if (kDebugMode) debugPrint('[ChatWs] 服务端错误: ${decoded['error']}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatWs] parse error: $e');
    }
  }

  Map<String, dynamic>? _parseJson(String s) {
    try {
      final decoded = jsonDecode(s);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleNewMessage(Map<String, dynamic> row) async {
    final convId = row['conversation_id'] as String?;
    final uid = _currentUserId;
    if (convId == null || uid == null) return;
    try {
      final senderId = row['sender_id'] as String? ?? '';
      // 若是自己发的，先删除本地临时消息，避免重复显示
      if (senderId == uid) {
        await ChatDb.instance.deleteLocalMessageMatch(
          conversationId: convId,
          currentUserId: uid,
          senderId: senderId,
          content: row['content'] as String? ?? '',
          messageType: row['message_type'] as String? ?? 'text',
          mediaUrl: row['media_url'] as String?,
        );
      }
      final msg = ChatMessage.fromSupabase(row: row, currentUserId: uid);
      await ChatDb.instance.upsertMessages(
        conversationId: convId,
        currentUserId: uid,
        list: [msg],
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatWs] handleNewMessage error: $e');
    }
  }

  /// 订阅会话，收到新消息时自动写入本地并刷新 UI
  void subscribe(List<String> conversationIds) {
    if (conversationIds.isEmpty) return;
    var changed = false;
    for (final id in conversationIds) {
      if (id.isNotEmpty && _subscribedIds.add(id)) {
        changed = true;
      }
    }
    if (changed) _sendSubscribe();
  }

  void _sendSubscribe({bool force = false}) {
    if (_channel == null || _subscribedIds.isEmpty) return;
    if (!force && setEquals(_lastSentSubscribedIds, _subscribedIds)) return;
    try {
      final ids = _subscribedIds.toList()..sort();
      _channel!.sink.add(_encode({
        'type': 'subscribe',
        'conversation_ids': ids,
      }));
      _lastSentSubscribedIds = Set<String>.from(_subscribedIds);
      if (kDebugMode) debugPrint('[ChatWs] 已订阅 ${_subscribedIds.length} 个会话');
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatWs] sendSubscribe error: $e');
    }
  }

  /// 订阅行情（通过 chat WebSocket，复用连接）
  void subscribeMarket(List<String> symbols) {
    if (symbols.isEmpty) return;
    for (final s in symbols) {
      final sym = s.trim().toUpperCase();
      if (sym.isNotEmpty) _marketSymbols.add(sym);
    }
    _sendMarketSubscribe();
  }

  void _sendMarketSubscribe() {
    if (_channel == null || _marketSymbols.isEmpty) return;
    try {
      _channel!.sink.add(_encode({
        'type': 'subscribe_market',
        'symbols': _marketSymbols.toList(),
      }));
      if (kDebugMode) debugPrint('[ChatWs] 已订阅行情 ${_marketSymbols.length} 个');
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatWs] sendMarketSubscribe error: $e');
    }
  }

  /// 通过 WebSocket 发送消息（连接时优先用 WS，否则回退 HTTP）
  /// 发送成功立即写入本地数据库，不等待服务器返回
  Future<String?> sendMessage({
    required String conversationId,
    required String senderId,
    required String senderName,
    required String content,
    String messageType = 'text',
    String? mediaUrl,
    int? durationMs,
    String? replyToMessageId,
    String? replyToSenderName,
    String? replyToContent,
  }) async {
    if (_channel != null) {
      try {
        final map = <String, dynamic>{
          'type': 'send',
          'conversation_id': conversationId,
          'content': content,
          'message_type': messageType,
          if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
          if (replyToSenderName != null) 'reply_to_sender_name': replyToSenderName,
          if (replyToContent != null) 'reply_to_content': replyToContent,
        };
        if (mediaUrl != null) map['media_url'] = mediaUrl;
        if (durationMs != null) map['duration_ms'] = durationMs;
        _channel!.sink.add(_encode(map));
        if (kDebugMode) {
          final preview = content.length > 20 ? '${content.substring(0, 20)}...' : content;
          final convPreview = conversationId.length > 8 ? conversationId.substring(0, 8) : conversationId;
          debugPrint('[ChatWs] 已发送 conv=$convPreview type=$messageType content=$preview');
        }

        // 发送成功立即写入本地数据库，不等待服务器返回
        final localId = 'local-${DateTime.now().microsecondsSinceEpoch}';
        final msg = ChatMessage(
          id: localId,
          senderId: senderId,
          senderName: senderName,
          content: content,
          messageType: messageType,
          time: DateTime.now(),
          isMine: true,
          mediaUrl: mediaUrl,
          durationMs: durationMs,
          replyToMessageId: replyToMessageId,
          replyToSenderName: replyToSenderName,
          replyToContent: replyToContent,
        );
        await ChatDb.instance.upsertMessages(
          conversationId: conversationId,
          currentUserId: senderId,
          list: [msg],
        );
        return null;
      } catch (e) {
        if (kDebugMode) debugPrint('[ChatWs] send error: $e');
        return null;
      }
    }
    return null;
  }

  String _encode(Map<String, dynamic> map) {
    return jsonEncode(map);
  }

  void disconnect() {
    _connectionGeneration++;
    _isConnecting = false;
    _reconnectAttempts = 0;
    _stopHeartbeat();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _subscribedIds.clear();
    _lastSentSubscribedIds = {};
    _marketSymbols.clear();
    _currentUserId = null;
  }

  void dispose() {
    _disposed = true;
    disconnect();
    _callInvitationController.close();
    _marketQuoteController.close();
  }
}
