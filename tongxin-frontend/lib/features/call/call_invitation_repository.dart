import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../api/misc_api.dart';
import '../../core/api_client.dart';

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

  /// 统一从后端请求该频道的 Agora RTC Token。
  Future<String?> fetchAgoraToken(String channelId, {int? uid}) async {
    if (!_useApi) return null;
    try {
      final token = await MiscApi.instance.getAgoraToken(channelId, uid: uid);
      if (token != null && token.isNotEmpty) return token;
    } catch (e) {
      print('[TH_CALL] fetchAgoraToken API 调用异常: $e');
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
    final list =
        await MiscApi.instance.getCallRecords(peerUserId, limit: limit);
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
  Future<Map<String, dynamic>?> fetchLatestRingingInvitation(
      String myUserId) async {
    if (!_useApi) return null;
    return MiscApi.instance.getLatestRingingInvitation();
  }

  /// 监听单条邀请状态变化（主叫监听被叫拒绝；被叫弹窗监听主叫取消）
  Stream<String?> watchInvitationStatus(String invitationId) {
    if (!_useApi) return Stream.value(null);
    return (() async* {
      var nextDelaySeconds = 5;
      while (true) {
        final status = await getStatus(invitationId);
        yield status;
        if (status == null) {
          nextDelaySeconds = math.min(30, nextDelaySeconds * 2);
        } else {
          nextDelaySeconds = 5;
        }
        await Future<void>.delayed(Duration(seconds: nextDelaySeconds));
      }
    })();
  }

  /// 被叫：postgres_changes 订阅 INSERT + 轮询兜底（Realtime 不推送时仍能收到来电）
  Stream<Map<String, dynamic>> watchIncomingInvitations(String myUserId) {
    if (!_useApi) return const Stream.empty();
    final emittedIds = <String>{};
    return (() async* {
      var nextDelaySeconds = 5;
      while (true) {
        final inv = await fetchLatestRingingInvitation(myUserId);
        if (inv != null && inv.isNotEmpty) {
          final id = inv['id']?.toString();
          if (id != null && id.isNotEmpty && !emittedIds.contains(id)) {
            emittedIds.add(id);
            yield inv;
          }
          nextDelaySeconds = 5;
        } else {
          nextDelaySeconds = math.min(30, nextDelaySeconds * 2);
        }
        await Future<void>.delayed(Duration(seconds: nextDelaySeconds));
      }
    })();
  }
}
