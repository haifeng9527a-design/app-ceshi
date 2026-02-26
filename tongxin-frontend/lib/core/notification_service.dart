import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:flutter/material.dart';

import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:getuiflut/getuiflut.dart';
import 'package:permission_handler/permission_handler.dart';

import '../features/call/call_invitation_repository.dart';
import '../features/call/incoming_call_dialog.dart';
import '../features/messages/chat_detail_page.dart';
import '../features/messages/friends_repository.dart';
import '../features/messages/message_models.dart';
import '../features/messages/messages_repository.dart';
import 'firebase_bootstrap.dart';
import 'supabase_bootstrap.dart';

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static final Getuiflut _getui = Getuiflut();
  static String? _pendingGetuiCid;
  static final MessagesRepository _messagesRepository = MessagesRepository();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// 当前正在看的会话 ID（在聊天详情页时设置），用于前台收到该会话消息时不弹通知
  static String? _currentConversationId;

  static bool _initialized = false;

  /// 是否已完成推送初始化（用于应用恢复时若未初始化则重试）
  static bool get isInitialized => _initialized;

  /// 来电 Realtime/轮询订阅：登录后全局监听，收到即弹接听界面
  static StreamSubscription<Map<String, dynamic>>? _incomingCallSubscription;

  /// 聊天详情页在 initState 时调用，dispose 时传 null
  static void setCurrentConversationId(String? conversationId) {
    _currentConversationId = conversationId;
  }

  static const AndroidNotificationChannel _defaultChannel =
      AndroidNotificationChannel(
    'messages',
    '消息通知',
    description: '聊天消息通知，确保能弹出系统通知栏与声音',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  /// 来电专用渠道：后台/锁屏时也能醒目显示，类似微信/QQ 来电通知
  static const AndroidNotificationChannel _incomingCallChannel =
      AndroidNotificationChannel(
    'incoming_call',
    '来电',
    description: '语音/视频来电提醒，请保持开启以便后台收到来电',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static const int _maxInitRetries = 3;
  static const Duration _initRetryDelay = Duration(seconds: 2);

  static Future<void> init({int retryCount = 0}) async {
    debugPrint('[通知] NotificationService.init 开始 (retry=$retryCount)');
    if (_initialized) {
      debugPrint('[通知] 已初始化过，跳过');
      return;
    }
    if (!FirebaseBootstrap.isReady) {
      if (retryCount >= _maxInitRetries) {
        debugPrint('[通知] Firebase 未就绪且已达最大重试次数，推送可能不可用');
        return;
      }
      debugPrint('[通知] Firebase 未就绪，${_initRetryDelay.inSeconds} 秒后重试 (${retryCount + 1}/$_maxInitRetries)');
      Future.delayed(_initRetryDelay, () async {
        await init(retryCount: retryCount + 1);
      });
      return;
    }
    if (!kIsWeb && Platform.isAndroid) {
      final status = await Permission.notification.request();
      debugPrint('[通知] Android 通知权限请求结果: $status');
    }

    if (!Platform.isMacOS) {
      await _localNotifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (response) {
          _handleNotificationPayload(response.payload);
        },
      );
      debugPrint('[通知] 本地通知插件已初始化');
    } else {
      debugPrint('[通知] macOS 暂不初始化本地通知插件，跳过');
    }

    if (!kIsWeb && Platform.isAndroid) {
      final android = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_defaultChannel);
      await android?.createNotificationChannel(_incomingCallChannel);
      debugPrint('[通知] Android 通知渠道已创建（消息 + 来电）');
    }

    try {
      final fcmPerm = await FirebaseMessaging.instance.requestPermission();
      debugPrint('[通知] FCM requestPermission 结果: $fcmPerm');
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      debugPrint('[通知] FCM 权限/配置 失败（如 macOS 可能不支持）: $e');
    }

    FirebaseMessaging.onMessage.listen(
      _showLocalNotification,
      onError: (e, st) {
        debugPrint('[通知] FCM onMessage 流错误: $e\n$st');
      },
    );
    debugPrint('[通知] FCM onMessage 监听已注册');
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNotificationData(message.data);
    });
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        _handleNotificationData(initial.data);
      }
    } catch (e) {
      debugPrint('[通知] FCM getInitialMessage 失败: $e');
    }
    // 冷启动或由「来电通知」fullScreenIntent 拉起：通过本地通知的 launch 信息弹接听界面（macOS 未初始化本地通知则跳过）
    if (!Platform.isMacOS) {
      final launchDetails = await _localNotifications.getNotificationAppLaunchDetails();
      if (launchDetails != null &&
          launchDetails.didNotificationLaunchApp &&
          launchDetails.notificationResponse != null) {
        final payload = launchDetails.notificationResponse!.payload;
        if (payload != null && payload.isNotEmpty) {
          _handleNotificationPayload(payload);
        }
      }
    }

    await _initGetui();

    try {
      final token = await FirebaseMessaging.instance.getToken();
      debugPrint('[通知] FCM token 获取: ${token != null ? "成功" : "null"}');
      if (token != null) {
        await _saveDeviceToken(token: token, platform: 'fcm');
      }
    } catch (error) {
      debugPrint('[通知] FCM token 获取失败: $error');
    }
    _initialized = true;
    debugPrint('[通知] NotificationService.init 完成');
    Future.delayed(const Duration(seconds: 1), () async {
      await refreshBadgeFromUnread();
    });
    FirebaseMessaging.instance.onTokenRefresh.listen(_saveToken);
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) {
        _incomingCallSubscription?.cancel();
        _incomingCallSubscription = null;
        return;
      }
      _incomingCallSubscription?.cancel();
      _incomingCallSubscription = CallInvitationRepository()
          .watchIncomingInvitations(user.uid)
          .listen((invitation) {
        final data = <String, dynamic>{
          'invitationId': invitation['id']?.toString(),
          'channelId': invitation['channel_id']?.toString(),
          'fromUserName': invitation['from_user_name']?.toString().trim() ?? '对方',
          'callType': invitation['call_type']?.toString() ?? 'voice',
          'fromAvatarUrl': invitation['from_avatar_url']?.toString().trim(),
        };
        if (data['invitationId'] != null &&
            (data['invitationId'] as String).isNotEmpty &&
            data['channelId'] != null &&
            (data['channelId'] as String).isNotEmpty) {
          debugPrint('[来电] Realtime/轮询收到邀请，弹接听界面');
          _openIncomingCallIfNeeded(data);
        }
      });
      debugPrint('[来电] 已订阅 Realtime 来电 userId=${user.uid}');
      final pending = _pendingGetuiCid;
      if (pending != null) {
        await _saveDeviceToken(token: pending, platform: 'getui');
        _pendingGetuiCid = null;
      }
      try {
        final fresh = await FirebaseMessaging.instance.getToken();
        if (fresh != null) {
          await _saveDeviceToken(token: fresh, platform: 'fcm');
        }
      } catch (error) {
        debugPrint('FCM token unavailable: $error');
      }
    });
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    debugPrint('[通知] FCM onMessage 收到: notification=${message.notification != null}');
    final data = message.data;
    final isCallInvitation = data['messageType']?.toString() == 'call_invitation';

    if (isCallInvitation) {
      // 来电：立即弹出接听界面（前台也会弹），并显示带铃声的来电通知
      debugPrint('[来电] FCM 收到来电，弹接听界面');
      _openIncomingCallIfNeeded(Map<String, dynamic>.from(data));
      final fromUserName = data['fromUserName']?.toString().trim() ?? '对方';
      final isVideo = data['callType']?.toString() == 'video';
      final title = isVideo ? '视频通话' : '语音通话';
      final body = '$fromUserName 邀请你${isVideo ? '视频' : '语音'}通话';
      try {
        final payload = _encodePayload(data);
        final invIdStr = data['invitationId']?.toString();
        final int id = (invIdStr != null && invIdStr.isNotEmpty)
            ? invIdStr.hashCode.abs() % 0x7FFFFFFF
            : DateTime.now().millisecondsSinceEpoch % 0x7FFFFFFF;
        await _localNotifications.show(
          id: id,
          title: title,
          body: body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              _incomingCallChannel.id,
              _incomingCallChannel.name,
              channelDescription: _incomingCallChannel.description,
              importance: Importance.max,
              priority: Priority.max,
              playSound: true,
              enableVibration: true,
              fullScreenIntent: true,
              category: AndroidNotificationCategory.call,
            ),
            iOS: const DarwinNotificationDetails(presentSound: true),
          ),
          payload: payload,
        );
      } catch (e) {
        debugPrint('[通知] 来电通知显示失败: $e');
      }
      return;
    }

    final conversationId = data['conversationId']?.toString().trim() ?? '';
    if (conversationId.isNotEmpty && conversationId == _currentConversationId) {
      try {
        await refreshBadgeFromUnread();
      } catch (_) {}
      return;
    }
    final notification = message.notification;
    String title = notification?.title ?? '新消息';
    String body = notification?.body ?? '';
    if (notification == null) {
      if (data.isNotEmpty) {
        title = data['title']?.toString().trim().isNotEmpty == true
            ? data['title']!.toString().trim()
            : title;
        body = data['body']?.toString().trim().isNotEmpty == true
            ? data['body']!.toString().trim()
            : (body.isEmpty ? '你收到一条新消息' : body);
        debugPrint('[通知] 使用 data 兜底显示通知');
      } else {
        debugPrint('[通知] 消息无 notification 且无 data，不显示系统通知');
        return;
      }
    }
    try {
      final payload = _encodePayload(data);
      final id = DateTime.now().millisecondsSinceEpoch % 0x7FFFFFFF;
      await _localNotifications.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _defaultChannel.id,
            _defaultChannel.name,
            channelDescription: _defaultChannel.description,
            importance: Importance.max,
            priority: Priority.max,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: payload,
      );
      debugPrint('[通知] 本地通知已显示 id=$id');
    } catch (e) {
      debugPrint('[通知] 显示本地通知失败: $e');
    }
    try {
      await refreshBadgeFromUnread();
    } catch (_) {}
  }

  static Future<void> _saveToken(String token) async {
    await _saveDeviceToken(token: token, platform: 'fcm');
  }

  static Future<void> _saveDeviceToken({
    required String token,
    required String platform,
  }) async {
    if (!SupabaseBootstrap.isReady) {
      debugPrint('[通知] 保存 token 跳过: Supabase 未就绪');
      return;
    }
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || userId.isEmpty) {
      debugPrint('[通知] 保存 token 跳过: 用户未登录 (platform=$platform)');
      return;
    }
    debugPrint('[通知] 保存 device_token: platform=$platform userId=$userId');
    await SupabaseBootstrap.client.from('device_tokens').upsert({
      'user_id': userId,
      'token': token,
      'platform': platform,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> _initGetui() async {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }
    _getui.addEventHandler(
      onReceiveClientId: (String message) async {
        final cid = message.trim();
        if (cid.isEmpty) {
          return;
        }
        final userId = FirebaseAuth.instance.currentUser?.uid;
        if (userId == null || userId.isEmpty) {
          _pendingGetuiCid = cid;
          return;
        }
        await _saveDeviceToken(token: cid, platform: 'getui');
      },
      onNotificationMessageArrived: (dynamic msg) async {
        debugPrint('[通知] 个推 onNotificationMessageArrived 收到');
        if (msg is Map<String, dynamic>) {
          await _showGetuiLocalNotification(msg);
        }
      },
      onNotificationMessageClicked: (message) async {
        final payload = _extractGetuiPayload(message);
        _handleNotificationPayload(payload);
      },
      onTransmitUserMessageReceive: (dynamic msg) async {
        debugPrint('[通知] 个推 onTransmitUserMessageReceive 收到');
        if (msg is Map<String, dynamic>) {
          await _showGetuiLocalNotification(msg);
          final payload = _extractGetuiPayload(msg);
          _handleNotificationPayload(payload);
        }
      },
      onReceiveOnlineState: (_) async {},
      onRegisterDeviceToken: (_) async {},
      onReceivePayload: (_) async {},
      onReceiveNotificationResponse: (_) async {},
      onAppLinkPayload: (_) async {},
      onPushModeResult: (_) async {},
      onSetTagResult: (_) async {},
      onAliasResult: (_) async {},
      onQueryTagResult: (_) async {},
      onWillPresentNotification: (_) async {},
      onOpenSettingsForNotification: (_) async {},
      onGrantAuthorization: (_) async {},
      onLiveActivityResult: (_) async {},
      onRegisterPushToStartTokenResult: (_) async {},
    );
    // 个推 SDK 通过 addEventHandler 已注册，原生端按文档在 Android 自动初始化
    _getui.initGetuiSdk;
  }

  static String _encodePayload(Map<String, dynamic> data) {
    if (data.isEmpty) {
      return '';
    }
    return jsonEncode(data);
  }

  /// 个推消息到达时显示本地通知并更新角标（notification 或 transmission 均支持）
  static Future<void> _showGetuiLocalNotification(Map<String, dynamic> message) async {
    try {
      final payloadStr = _extractGetuiPayload(message);
      Map<String, dynamic>? decodedPayload;
      if (payloadStr != null && payloadStr.isNotEmpty) {
        try {
          final d = jsonDecode(payloadStr);
          if (d is Map<String, dynamic>) decodedPayload = d;
        } catch (_) {}
      }
      // 来电类：不参与「当前会话不弹通知」逻辑，且使用来电渠道
      final isCallInvitation = decodedPayload?['messageType']?.toString() == 'call_invitation';
      if (!isCallInvitation) {
        final conversationId = decodedPayload?['conversationId']?.toString().trim();
        if (conversationId != null &&
            conversationId.isNotEmpty &&
            conversationId == _currentConversationId) {
          try {
            await refreshBadgeFromUnread();
          } catch (_) {}
          return;
        }
      }
      String title = '新消息';
      String body = '你收到一条新消息';
      if (message['title'] is String) title = message['title'] as String;
      if (message['body'] is String) body = message['body'] as String;
      if (message['content'] is String) body = message['content'] as String;
      if (message['msg'] is String) body = message['msg'] as String;
      final notif = message['notification'];
      if (notif is Map) {
        if (notif['title'] is String) title = notif['title'] as String;
        if (notif['body'] is String) body = notif['body'] as String;
      }
      // transmission 透传：标题/正文在 payload 的 JSON 里；来电用 payload 里的文案
      if (decodedPayload != null) {
        final t = decodedPayload['title']?.toString().trim();
        final b = decodedPayload['body']?.toString().trim();
        if (t != null && t.isNotEmpty) title = t;
        if (b != null && b.isNotEmpty) body = b;
        if (isCallInvitation) {
          final from = decodedPayload['fromUserName']?.toString().trim() ?? '对方';
          final isVideo = decodedPayload['callType']?.toString() == 'video';
          title = isVideo ? '视频通话' : '语音通话';
          body = '$from 邀请你${isVideo ? '视频' : '语音'}通话';
        }
      }
      final channel = isCallInvitation ? _incomingCallChannel : _defaultChannel;
      final id = isCallInvitation && decodedPayload?['invitationId'] != null
          ? (decodedPayload!['invitationId'] as String).hashCode.abs() % 0x7FFFFFFF
          : DateTime.now().millisecondsSinceEpoch % 0x7FFFFFFF;
      await _localNotifications.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: Importance.max,
            priority: Priority.max,
            playSound: true,
            enableVibration: true,
            fullScreenIntent: isCallInvitation,
            category: isCallInvitation ? AndroidNotificationCategory.call : null,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: payloadStr,
      );
      debugPrint('[通知] 个推本地通知已显示${isCallInvitation ? "（来电）" : ""}');
      // 来电：同时唤起应用并弹出全屏接听界面（与微信等一致），不再只依赖用户点通知
      if (isCallInvitation && decodedPayload != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _openIncomingCallIfNeeded(decodedPayload!);
        });
      }
      int? badgeNum;
      if (payloadStr != null && payloadStr.isNotEmpty) {
        try {
          final decoded = jsonDecode(payloadStr);
          if (decoded is Map<String, dynamic>) {
            final badgeFromPayload = decoded['badge']?.toString();
            badgeNum = badgeFromPayload != null && badgeFromPayload.isNotEmpty
                ? int.tryParse(badgeFromPayload)
                : null;
          }
        } catch (_) {}
      }
      if (badgeNum == null && message['badge'] != null) {
        badgeNum = int.tryParse(message['badge'].toString());
      }
      if (badgeNum != null && badgeNum >= 0) {
        await updateBadgeCount(badgeNum);
      } else {
        await refreshBadgeFromUnread();
      }
    } catch (e) {
      debugPrint('[通知] 个推本地通知失败: $e');
    }
  }

  static String? _extractGetuiPayload(Map<String, dynamic> message) {
    final raw = message['payload'] ??
        message['transmissionContent'] ??
        message['content'];
    if (raw == null) {
      return null;
    }
    if (raw is String) {
      return raw;
    }
    return jsonEncode(raw);
  }

  static void _handleNotificationData(Map<String, dynamic> data) {
    if (data.isEmpty) return;
    final messageType = data['messageType']?.toString() ?? '';
    if (messageType == 'call_invitation') {
      _openIncomingCallIfNeeded(data);
      return;
    }
    _openConversationIfNeeded(data);
  }

  static void _handleNotificationPayload(String? payload) {
    if (payload == null || payload.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return;
      final messageType = decoded['messageType']?.toString() ?? '';
      if (messageType == 'call_invitation') {
        _openIncomingCallIfNeeded(decoded);
        return;
      }
      _openConversationIfNeeded(decoded);
    } catch (_) {
      // Ignore malformed payloads.
    }
  }

  static void _openIncomingCallIfNeeded(Map<String, dynamic> data) {
    final invitationId = data['invitationId']?.toString();
    final channelId = data['channelId']?.toString();
    if (invitationId == null || invitationId.isEmpty || channelId == null || channelId.isEmpty) return;
    final fromUserName = data['fromUserName']?.toString().trim() ?? '对方';
    final callType = data['callType']?.toString() ?? 'voice';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;
      showIncomingCallDialog(
        context: ctx,
        invitationId: invitationId,
        fromUserName: fromUserName,
        channelId: channelId,
        callType: callType,
        fromAvatarUrl: data['fromAvatarUrl']?.toString().trim(),
      );
    });
  }

  /// 收到来电但无法弹窗时显示本地通知（如 context 为 null），用户点击后打开来电对话框
  static Future<void> showIncomingCallFallbackNotification({
    required String invitationId,
    required String channelId,
    required String fromUserName,
    required String callType,
  }) async {
    if (kIsWeb) return;
    try {
      final isVideo = callType == 'video';
      final payload = jsonEncode({
        'messageType': 'call_invitation',
        'invitationId': invitationId,
        'channelId': channelId,
        'callType': callType,
        'fromUserName': fromUserName,
      });
      final id = invitationId.hashCode.abs() % 0x7FFFFFFF;
      await _localNotifications.show(
        id: id,
        title: isVideo ? '视频通话' : '语音通话',
        body: '$fromUserName 邀请你${isVideo ? '视频' : '语音'}通话',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _incomingCallChannel.id,
            _incomingCallChannel.name,
            channelDescription: _incomingCallChannel.description,
            importance: Importance.max,
            priority: Priority.max,
            playSound: true,
            enableVibration: true,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.call,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('[通知] 来电备用通知失败: $e');
    }
  }

  /// 从后台恢复时调用：重新获取并保存 FCM token（防止 token 刷新后未写入 DB 导致收不到推送）
  static Future<void> ensureTokenSavedOnResume() async {
    if (kIsWeb || !FirebaseBootstrap.isReady) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _saveDeviceToken(token: token, platform: 'fcm');
    } catch (_) {}
  }

  /// 根据当前用户未读数刷新应用图标角标（与首页一致：聊天未读 + 好友请求数）
  static Future<void> refreshBadgeFromUnread() async {
    if (kIsWeb) return;
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null || userId.isEmpty) return;
      final chatUnread = await _messagesRepository.getTotalUnreadCount(userId);
      final friendRequests =
          await FriendsRepository().getIncomingRequestCount(userId);
      final total = chatUnread + friendRequests;
      await updateBadgeCount(total);
    } catch (_) {}
  }

  /// 更新应用图标角标（未读消息数），与系统「信息」、小红书等一致；0 时清除角标。
  /// 部分机型 isAppBadgeSupported 为 false 但角标仍有效，故始终尝试设置。
  static Future<void> updateBadgeCount(int count) async {
    if (kIsWeb) return;
    try {
      if (count <= 0) {
        await FlutterAppBadger.removeBadge();
      } else {
        await FlutterAppBadger.updateBadgeCount(count);
      }
      debugPrint('[通知] 角标 updateBadgeCount(count=$count) 已执行');
    } catch (e) {
      debugPrint('[通知] 角标更新失败: $e');
    }
  }

  static Future<void> _openConversationIfNeeded(
    Map<String, dynamic> data,
  ) async {
    final conversationId = data['conversationId']?.toString() ?? '';
    if (conversationId.isEmpty) {
      return;
    }
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || userId.isEmpty) {
      return;
    }
    final conversation =
        await _messagesRepository.fetchConversationById(
      conversationId: conversationId,
      currentUserId: userId,
    );
    if (conversation == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = navigatorKey.currentState;
      if (navigator == null) {
        return;
      }
      navigator.push(
        MaterialPageRoute(
          builder: (_) => ChatDetailPage(
            conversation: conversation,
            initialMessages: const <ChatMessage>[],
          ),
        ),
      );
    });
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseBootstrap.init();
  await SupabaseBootstrap.init();
  if (kIsWeb || !Platform.isAndroid) return;
  final data = message.data;
  final isCallInvitation = data['messageType']?.toString() == 'call_invitation';
  final notification = message.notification;
  String title = notification?.title ?? '新消息';
  String body = notification?.body ?? '你收到一条新消息';
  if (notification == null && data.isNotEmpty) {
    final t = data['title']?.toString().trim();
    final b = data['body']?.toString().trim();
    if (t != null && t.isNotEmpty) title = t;
    if (b != null && b.isNotEmpty) body = b;
    if (isCallInvitation) {
      final from = data['fromUserName']?.toString().trim() ?? '对方';
      final isVideo = data['callType']?.toString() == 'video';
      title = isVideo ? '视频通话' : '语音通话';
      body = '$from 邀请你${isVideo ? '视频' : '语音'}通话';
    }
  }
  const messagesChannel = AndroidNotificationChannel(
    'messages',
    '消息通知',
    description: '聊天消息通知',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );
  const incomingCallChannel = AndroidNotificationChannel(
    'incoming_call',
    '来电',
    description: '语音/视频来电提醒',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );
  final plugin = FlutterLocalNotificationsPlugin();
  try {
    if (!Platform.isMacOS) {
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
    }
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(messagesChannel);
    await android?.createNotificationChannel(incomingCallChannel);
    final channel = isCallInvitation ? incomingCallChannel : messagesChannel;
    final id = isCallInvitation && data['invitationId'] != null
        ? (data['invitationId'] as String).hashCode.abs() % 0x7FFFFFFF
        : DateTime.now().millisecondsSinceEpoch % 0x7FFFFFFF;
    await plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          fullScreenIntent: isCallInvitation,
          category: isCallInvitation ? AndroidNotificationCategory.call : null,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: data.isEmpty ? null : jsonEncode(data),
    );
  } catch (e) {
    debugPrint(
        'NotificationService: background show notification failed: $e');
  }
  try {
    // 优先使用服务端下发的角标数，这样不点开 App 也能更新图标数字
    final badgeFromPayload = message.data['badge']?.toString();
    final int? badgeNum = badgeFromPayload != null && badgeFromPayload.isNotEmpty
        ? int.tryParse(badgeFromPayload)
        : null;
    if (badgeNum != null && badgeNum >= 0) {
      await NotificationService.updateBadgeCount(badgeNum);
    } else {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null && userId.isNotEmpty && SupabaseBootstrap.isReady) {
        final total = await MessagesRepository().getTotalUnreadCount(userId);
        await NotificationService.updateBadgeCount(total);
      } else {
        await NotificationService.updateBadgeCount(1);
      }
    }
  } catch (_) {}
}
