import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../api/misc_api.dart';
import '../../core/api_client.dart';
import '../../core/supabase_bootstrap.dart';

/// 单条通话记录（用于聊天窗口内展示呼叫记录）
class CallRecord {
  const CallRecord({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.callType,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String fromUserId;
  final String toUserId;
  final String callType;
  final String status;
  final DateTime createdAt;

  bool get isVoice => callType == 'voice';
  bool get isVideo => callType == 'video';

  /// 当前用户是否为发起方（主叫）
  bool isMine(String currentUserId) => fromUserId == currentUserId;

  /// 这条记录的「操作者」是否是当前用户（用于聊天里左右对齐：我操作的显示在右侧，对方操作的显示在左侧）
  /// 已接听/已拒绝：操作者 = 被叫(to)；已取消：操作者 = 主叫(from)；未接听：按发起方(from)算
  bool isActionByMe(String currentUserId) {
    switch (status) {
      case 'accepted':
      case 'rejected':
        return toUserId == currentUserId;
      case 'cancelled':
        return fromUserId == currentUserId;
      case 'ringing':
      default:
        return fromUserId == currentUserId;
    }
  }

  String timeLabel() {
    final t = createdAt.isUtc ? createdAt.toLocal() : createdAt;
    final hour = t.hour.toString().padLeft(2, '0');
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

/// 通话邀请：增删改查 + 被叫用 postgres_changes 收 INSERT（来电）
class CallInvitationRepository {
  CallInvitationRepository();

  bool get _useApi => ApiClient.instance.isAvailable;

  /// 发起邀请：优先走 API，否则 Edge Function 或直插
  Future<String> createInvitation({
    required String fromUserId,
    required String fromUserName,
    required String toUserId,
    required String channelId,
    required String callType,
  }) async {
    if (!_useApi) throw StateError('API 未配置，无法发起通话');
    final id = await MiscApi.instance.createCallInvitation(
      toUserId: toUserId,
      channelId: channelId,
      fromUserName: fromUserName,
      callType: callType,
    );
    if (id != null && id.isNotEmpty) return id;
    throw StateError('创建通话邀请失败');
  }

  /// 更新状态：接听 / 拒绝 / 取消
  Future<void> updateStatus(String id, String status) async {
    debugPrint('[TH_CALL] updateStatus id=$id status=$status');
    if (!_useApi) return;
    await MiscApi.instance.updateCallInvitationStatus(id, status);
  }

  /// 向 Supabase Edge Function 请求该频道的 Agora RTC Token。
  /// 当前项目内已部署 `get_agora_token`，优先直连函数，避免先请求不存在的后端路由导致通话接入变慢。
  /// 若未配置或请求失败，返回 null，客户端将使用空字符串（仅当控制台未开启 Token 鉴权时有效）。
  Future<String?> fetchAgoraToken(String channelId, {int? uid}) async {
    if (SupabaseBootstrap.isReady) {
      final authToken = await FirebaseAuth.instance.currentUser?.getIdToken(true);
      if (authToken != null && authToken.isNotEmpty) {
        try {
          final client = SupabaseBootstrap.clientOrNull;
          if (client != null) {
            final res = await client.functions.invoke(
              'get_agora_token',
              body: {'channel_id': channelId, if (uid != null) 'uid': uid},
              headers: {'Authorization': 'Bearer $authToken'},
            );
            if (res.status == 200 && res.data != null) {
              final data = res.data is Map ? res.data as Map : null;
              final token = data?['token']?.toString();
              if (token != null && token.isNotEmpty) return token;
            } else {
              print('[TH_CALL] get_agora_token 返回异常 status=${res.status} data=${res.data}');
            }
          }
        } catch (e) {
          print('[TH_CALL] fetchAgoraToken 函数调用异常: $e');
        }
      }
    }

    if (_useApi) {
      try {
        final token = await MiscApi.instance.getAgoraToken(channelId, uid: uid);
        if (token != null && token.isNotEmpty) return token;
      } catch (e) {
        print('[TH_CALL] fetchAgoraToken API 调用异常: $e');
      }
    }

    return null;
  }

  /// 查询与某人的通话记录（主叫/被叫均可查，需 RLS 允许 from_user_id=我 或 to_user_id=我）
  Future<List<CallRecord>> listForConversation({
    required String myUserId,
    required String peerUserId,
    int limit = 50,
  }) async {
    if (peerUserId.isEmpty) return [];
    if (!_useApi) return [];
    final list = await MiscApi.instance.getCallRecords(peerUserId, limit: limit);
    return list.map((m) {
      final row = Map<String, dynamic>.from(m);
      final createdAt = row['created_at']?.toString();
      return CallRecord(
        id: row['id'] as String? ?? '',
        fromUserId: row['from_user_id'] as String? ?? '',
        toUserId: row['to_user_id'] as String? ?? '',
        callType: row['call_type'] as String? ?? 'voice',
        status: row['status'] as String? ?? 'ringing',
        createdAt: createdAt != null && createdAt.isNotEmpty
            ? (DateTime.tryParse(createdAt) ?? DateTime.now())
            : DateTime.now(),
      );
    }).toList();
  }

  /// 查询邀请当前状态
  Future<String?> getStatus(String id) async {
    if (!_useApi) return null;
    final inv = await MiscApi.instance.getCallInvitation(id);
    final status = inv?['status'] as String?;
    print('[TH_CALL] getStatus id=$id => status=$status');
    return status;
  }

  /// 被叫：轮询「发给我且 status=ringing、2 分钟内」的最新一条邀请（Realtime 不推送时的兜底）
  Future<Map<String, dynamic>?> fetchLatestRingingInvitation(String myUserId) async {
    if (!_useApi) return null;
    return MiscApi.instance.getLatestRingingInvitation();
  }

  /// 监听单条邀请状态变化（主叫监听被叫拒绝；被叫弹窗监听主叫取消）
  Stream<String?> watchInvitationStatus(String invitationId) {
    if (!_useApi) return Stream.value(null);
    return Stream.periodic(const Duration(seconds: 2), (_) => null)
        .asyncMap((_) => getStatus(invitationId));
  }

  /// 被叫：postgres_changes 订阅 INSERT + 轮询兜底（Realtime 不推送时仍能收到来电）
  Stream<Map<String, dynamic>> watchIncomingInvitations(String myUserId) {
    if (!_useApi) return const Stream.empty();
    final emittedIds = <String>{};
    return Stream.periodic(const Duration(seconds: 2), (_) => null)
        .asyncMap((_) => fetchLatestRingingInvitation(myUserId))
        .where((m) => m != null && m.isNotEmpty)
        .map((m) => m!)
        .where((inv) {
          final id = inv['id']?.toString();
          if (id == null || id.isEmpty || emittedIds.contains(id)) return false;
          emittedIds.add(id);
          return true;
        });
  }
}
