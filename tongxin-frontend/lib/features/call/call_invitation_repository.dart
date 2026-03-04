import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  CallInvitationRepository({SupabaseClient? client})
      : _client = client ?? SupabaseBootstrap.clientOrNull;

  final SupabaseClient? _client;

  bool get _hasClient => _client != null && SupabaseBootstrap.isReady;

  bool get _useApi => ApiClient.instance.isAvailable;

  /// 发起邀请：优先走 API，否则 Edge Function 或直插
  Future<String> createInvitation({
    required String fromUserId,
    required String fromUserName,
    required String toUserId,
    required String channelId,
    required String callType,
  }) async {
    if (_useApi) {
      final id = await MiscApi.instance.createCallInvitation(
        toUserId: toUserId,
        channelId: channelId,
        fromUserName: fromUserName,
        callType: callType,
      );
      if (id != null && id.isNotEmpty) return id;
      throw StateError('创建通话邀请失败');
    }
    if (!_hasClient) throw StateError('Supabase 未配置，无法发起通话');
    final token = await FirebaseAuth.instance.currentUser?.getIdToken(true);
    if (token != null && token.isNotEmpty) {
      try {
        print('[TH_CALL] 调用 Edge Function create_call_invitation');
        final res = await _client!.functions.invoke(
          'create_call_invitation',
          body: {
            'from_user_id': fromUserId,
            'from_user_name': fromUserName,
            'to_user_id': toUserId,
            'channel_id': channelId,
            'call_type': callType,
          },
          headers: {'Authorization': 'Bearer $token'},
        );
        if (res.status == 200 && res.data != null) {
          final id = res.data is Map ? (res.data as Map)['id'] : null;
          if (id != null) {
            print('[TH_CALL] Edge Function 返回成功 id=$id');
            return id as String;
          }
        }
        final msg = res.data is Map ? (res.data as Map)['error']?.toString() : null;
        print('[TH_CALL] Edge Function 返回异常 status=${res.status} error=$msg');
        throw Exception(msg ?? '通话服务返回异常(${res.status})');
      } catch (e) {
        rethrow;
      }
    }
    print('[TH_CALL] 无 Firebase Token，直插 call_invitations（受 RLS 限制）');
    final res = await _client!.from('call_invitations').insert({
      'from_user_id': fromUserId,
      'from_user_name': fromUserName,
      'to_user_id': toUserId,
      'channel_id': channelId,
      'call_type': callType,
      'status': 'ringing',
    }).select('id').single();
    return res['id'] as String;
  }

  /// 更新状态：接听 / 拒绝 / 取消
  Future<void> updateStatus(String id, String status) async {
    debugPrint('[TH_CALL] updateStatus id=$id status=$status');
    if (_useApi) {
      await MiscApi.instance.updateCallInvitationStatus(id, status);
      return;
    }
    await _client!
        .from('call_invitations')
        .update({'status': status}).eq('id', id);
  }

  /// 向 Edge Function 请求该频道的 Agora RTC Token（需在 Supabase 配置 AGORA_APP_ID、AGORA_APP_CERTIFICATE）
  /// 若未配置或请求失败，返回 null，客户端将使用空字符串（仅当控制台未开启 Token 鉴权时有效）
  Future<String?> fetchAgoraToken(String channelId, {int? uid}) async {
    if (!_hasClient) return null;
    final authToken = await FirebaseAuth.instance.currentUser?.getIdToken(true);
    if (authToken == null || authToken.isEmpty) return null;
    try {
      final res = await _client!.functions.invoke(
        'get_agora_token',
        body: {'channel_id': channelId, if (uid != null) 'uid': uid},
        headers: {'Authorization': 'Bearer $authToken'},
      );
      if (res.status != 200 || res.data == null) return null;
      final data = res.data is Map ? res.data as Map : null;
      final token = data?['token']?.toString();
      return token != null && token.isNotEmpty ? token : null;
    } catch (e) {
      print('[TH_CALL] fetchAgoraToken 异常: $e');
      return null;
    }
  }

  /// 查询与某人的通话记录（主叫/被叫均可查，需 RLS 允许 from_user_id=我 或 to_user_id=我）
  Future<List<CallRecord>> listForConversation({
    required String myUserId,
    required String peerUserId,
    int limit = 50,
  }) async {
    if (peerUserId.isEmpty) return [];
    if (_useApi) {
      final list = await MiscApi.instance.getCallRecords(peerUserId, limit: limit);
      return list.map((m) {
        final createdAt = m['created_at']?.toString();
        return CallRecord(
          id: m['id'] as String? ?? '',
          fromUserId: m['from_user_id'] as String? ?? '',
          toUserId: m['to_user_id'] as String? ?? '',
          callType: m['call_type'] as String? ?? 'voice',
          status: m['status'] as String? ?? 'ringing',
          createdAt: createdAt != null && createdAt.isNotEmpty
              ? (DateTime.tryParse(createdAt) ?? DateTime.now())
              : DateTime.now(),
        );
      }).toList();
    }
    if (!_hasClient) return [];
    final res = await _client!
        .from('call_invitations')
        .select('id, from_user_id, to_user_id, call_type, status, created_at')
        .or('and(from_user_id.eq.$myUserId,to_user_id.eq.$peerUserId),and(from_user_id.eq.$peerUserId,to_user_id.eq.$myUserId)')
        .order('created_at', ascending: false)
        .limit(limit);
    final list = res as List<dynamic>? ?? [];
    return list.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      final createdAt = m['created_at']?.toString();
      return CallRecord(
        id: m['id'] as String? ?? '',
        fromUserId: m['from_user_id'] as String? ?? '',
        toUserId: m['to_user_id'] as String? ?? '',
        callType: m['call_type'] as String? ?? 'voice',
        status: m['status'] as String? ?? 'ringing',
        createdAt: createdAt != null && createdAt.isNotEmpty
            ? (DateTime.tryParse(createdAt) ?? DateTime.now())
            : DateTime.now(),
      );
    }).toList();
  }

  /// 查询邀请当前状态
  Future<String?> getStatus(String id) async {
    if (_useApi) {
      final inv = await MiscApi.instance.getCallInvitation(id);
      final status = inv?['status'] as String?;
      debugPrint('[TH_CALL] getStatus id=$id => status=$status');
      return status;
    }
    if (!_hasClient) return null;
    final res = await _client!
        .from('call_invitations')
        .select('status')
        .eq('id', id)
        .maybeSingle();
    final status = res?['status'] as String?;
    print('[TH_CALL] getStatus id=$id => status=$status');
    return status;
  }

  /// 被叫：轮询「发给我且 status=ringing、2 分钟内」的最新一条邀请（Realtime 不推送时的兜底）
  Future<Map<String, dynamic>?> fetchLatestRingingInvitation(String myUserId) async {
    if (_useApi) return MiscApi.instance.getLatestRingingInvitation();
    if (!_hasClient) return null;
    final since = DateTime.now().toUtc().subtract(const Duration(minutes: 2)).toIso8601String();
    final res = await _client!
        .from('call_invitations')
        .select()
        .eq('to_user_id', myUserId)
        .eq('status', 'ringing')
        .gte('created_at', since)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return res != null ? Map<String, dynamic>.from(res) : null;
  }

  /// 监听单条邀请状态变化（主叫监听被叫拒绝；被叫弹窗监听主叫取消）
  Stream<String?> watchInvitationStatus(String invitationId) {
    if (!_hasClient) return Stream.value(null);
    return _client!
        .from('call_invitations')
        .stream(primaryKey: ['id'])
        .map((list) {
          final row = list.cast<Map<String, dynamic>>().where(
            (r) => r['id']?.toString() == invitationId,
          ).firstOrNull;
          return row?['status'] as String?;
        });
  }

  /// 被叫：postgres_changes 订阅 INSERT + 轮询兜底（Realtime 不推送时仍能收到来电）
  Stream<Map<String, dynamic>> watchIncomingInvitations(String myUserId) {
    if (_useApi) {
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
    if (!_hasClient) return const Stream.empty();
    late StreamController<Map<String, dynamic>> controller;
    RealtimeChannel? channel;
    Timer? pollTimer;
    final emittedIds = <String>{};

    void emitIfNew(Map<String, dynamic> invitation) {
      final id = invitation['id']?.toString();
      if (id == null || id.isEmpty || emittedIds.contains(id)) return;
      emittedIds.add(id);
      if (!controller.isClosed) controller.add(invitation);
    }

    controller = StreamController<Map<String, dynamic>>(
      onListen: () {
        channel = _client!
            .channel('call_invitations_$myUserId')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'call_invitations',
              callback: (payload) {
                final newRecord = payload.newRecord;
                final toUserId = newRecord['to_user_id']?.toString();
                final status = newRecord['status']?.toString() ?? '';
                if (toUserId != myUserId || status != 'ringing') return;
                final createdAt = newRecord['created_at']?.toString();
                if (createdAt != null && createdAt.isNotEmpty) {
                  try {
                    final t = DateTime.parse(createdAt);
                    if (DateTime.now().difference(t).inMinutes > 2) return;
                  } catch (_) {}
                }
                emitIfNew(Map<String, dynamic>.from(newRecord));
              },
            )
            .subscribe();
        debugPrint('[来电] postgres_changes 已订阅 call_invitations INSERT userId=$myUserId');

        // 轮询兜底：每 2 秒查一次 ringing 邀请，Realtime 未推送时仍能弹窗
        pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
          if (controller.isClosed) return;
          try {
            final inv = await fetchLatestRingingInvitation(myUserId);
            if (inv != null) emitIfNew(inv);
          } catch (_) {}
        });
      },
      onCancel: () {
        channel?.unsubscribe();
        pollTimer?.cancel();
      },
    );

    return controller.stream;
  }
}
