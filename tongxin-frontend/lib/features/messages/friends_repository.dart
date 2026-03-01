import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_bootstrap.dart';
import 'friend_models.dart';

class FriendsRepository {
  FriendsRepository({SupabaseClient? client})
      : _client = client ?? SupabaseBootstrap.client;

  final SupabaseClient _client;

  static String _roleLabel(String? role, String teacherStatus) {
    final r = (role ?? '').toString().trim().toLowerCase();
    final status = teacherStatus.toString().trim().toLowerCase();
    if (r == 'admin') return '管理员';
    if (r == 'vip') return '会员';
    if (r == 'teacher' || status == 'approved') return '交易员';
    return '普通用户';
  }

  static FriendProfile _profileFromRow(
    Map<String, dynamic> row, {
    String? teacherStatus,
  }) {
    final upStatus = row['teacher_status'] as String? ?? 'pending';
    final ts = teacherStatus ?? upStatus;
    return FriendProfile(
      userId: row['user_id'] as String,
      displayName: (row['display_name'] as String?) ??
          (row['email'] as String?)?.split('@').first ??
          '用户',
      email: row['email'] as String? ?? '',
      avatarUrl: row['avatar_url'] as String?,
      status: row['status'] as String? ?? 'offline',
      shortId: row['short_id'] as String?,
      level: (row['level'] as int?) ?? 0,
      roleLabel: _roleLabel(row['role'] as String?, ts),
      lastOnlineAt: _parseDateTime(row['last_online_at']),
    );
  }

  Future<FriendProfile?> findByEmail(String email) async {
    final result = await _client
        .from('user_profiles')
        .select('user_id, display_name, email, avatar_url, status, short_id, role, level, teacher_status, last_online_at')
        .eq('email', email)
        .maybeSingle();
    if (result == null) {
      return null;
    }
    final uid = result['user_id'] as String?;
    if (uid == null) return null;
    final tp = await _client
        .from('teacher_profiles')
        .select('status')
        .eq('user_id', uid)
        .maybeSingle();
    return _profileFromRow(result, teacherStatus: tp?['status'] as String?);
  }

  Future<FriendProfile?> findById(String userId) async {
    final result = await _client
        .from('user_profiles')
        .select('user_id, display_name, email, avatar_url, status, short_id, role, level, teacher_status, last_online_at')
        .eq('user_id', userId)
        .maybeSingle();
    if (result == null) {
      return null;
    }
    final tp = await _client
        .from('teacher_profiles')
        .select('status')
        .eq('user_id', userId)
        .maybeSingle();
    return _profileFromRow(result, teacherStatus: tp?['status'] as String?);
  }

  Future<FriendProfile?> findByShortId(String shortId) async {
    final trimmed = shortId.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final result = await _client
        .from('user_profiles')
        .select('user_id, display_name, email, avatar_url, status, short_id, role, level, teacher_status, last_online_at')
        .eq('short_id', trimmed)
        .maybeSingle();
    if (result == null) {
      return null;
    }
    final uid = result['user_id'] as String?;
    if (uid == null) return null;
    final tp = await _client
        .from('teacher_profiles')
        .select('status')
        .eq('user_id', uid)
        .maybeSingle();
    return _profileFromRow(result, teacherStatus: tp?['status'] as String?);
  }

  /// 当前用户的好友数量流（用于展示「关注 X」等）
  Stream<int> watchFriendCount({required String userId}) {
    return watchFriends(userId: userId).map((list) => list.length);
  }

  Stream<List<FriendProfile>> watchFriends({required String userId}) {
    return _client
        .from('friends')
        .stream(primaryKey: ['user_id', 'friend_id'])
        .eq('user_id', userId)
        .asyncMap((rows) async {
      if (rows.isEmpty) {
        return <FriendProfile>[];
      }
      final friendIds = rows
          .map((row) => row['friend_id'] as String?)
          .whereType<String>()
          .toList();
      if (friendIds.isEmpty) {
        return <FriendProfile>[];
      }
      final profiles = await _client
          .from('user_profiles')
          .select('user_id, display_name, email, avatar_url, status, short_id, role, level, teacher_status, last_online_at')
          .inFilter('user_id', friendIds);
      final teacherRows = await _client
          .from('teacher_profiles')
          .select('user_id, status')
          .inFilter('user_id', friendIds);
      final teacherStatusMap = {
        for (final r in teacherRows) r['user_id'] as String: r['status'] as String?,
      };
      return profiles.map<FriendProfile>((row) {
        return _profileFromRow(
          row,
          teacherStatus: teacherStatusMap[row['user_id'] as String],
        );
      }).toList();
    });
  }

  Stream<Map<String, String>> watchRemarks({required String userId}) {
    return _client
        .from('friend_remarks')
        .stream(primaryKey: ['user_id', 'friend_id'])
        .eq('user_id', userId)
        .asyncMap((rows) async {
      if (rows.isEmpty) {
        return <String, String>{};
      }
      final friendIds = rows
          .map((row) => row['friend_id'] as String?)
          .whereType<String>()
          .toList();
      final profiles = friendIds.isEmpty
          ? <Map<String, dynamic>>[]
          : await _client
              .from('user_profiles')
              .select()
              .inFilter('user_id', friendIds);
      final profileMap = {
        for (final row in profiles) row['user_id'] as String: row,
      };
      final remarks = <String, String>{};
      for (final row in rows) {
        final friendId = row['friend_id'] as String?;
        final remark = row['remark'] as String?;
        if (friendId == null || remark == null || remark.trim().isEmpty) {
          continue;
        }
        remarks['id:$friendId'] = remark;
        remarks[friendId] = remark;
        final profile = profileMap[friendId];
        final displayName = (profile?['display_name'] as String?)?.trim();
        final email = (profile?['email'] as String?)?.trim();
        if (displayName != null && displayName.isNotEmpty) {
          remarks['name:$displayName'] = remark;
        }
        if (email != null && email.isNotEmpty) {
          remarks['email:$email'] = remark;
        }
      }
      return remarks;
    });
  }

  Future<void> saveRemark({
    required String userId,
    required String friendId,
    required String remark,
  }) async {
    final trimmed = remark.trim();
    if (trimmed.isEmpty) {
      await _client
          .from('friend_remarks')
          .delete()
          .eq('user_id', userId)
          .eq('friend_id', friendId);
      return;
    }
    await _client.from('friend_remarks').upsert({
      'user_id': userId,
      'friend_id': friendId,
      'remark': trimmed,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// 待处理的好友请求数量（用于角标等）
  Future<int> getIncomingRequestCount(String userId) async {
    if (userId.isEmpty) return 0;
    try {
      final list = await _client
          .from('friend_requests')
          .select('id')
          .eq('receiver_id', userId)
          .eq('status', 'pending');
      return list.length;
    } catch (_) {
      return 0;
    }
  }

  Stream<List<FriendRequestItem>> watchIncomingRequests({
    required String userId,
  }) {
    return _client
        .from('friend_requests')
        .stream(primaryKey: ['id'])
        .eq('receiver_id', userId)
        .asyncMap((rows) async {
      final pending = rows
          .where((row) => row['status'] == 'pending')
          .toList();
      if (pending.isEmpty) {
        return <FriendRequestItem>[];
      }
      final requesterIds = pending
          .map((row) => row['requester_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final profiles = await _client
          .from('user_profiles')
          .select()
          .inFilter('user_id', requesterIds);
      final profileMap = {
        for (final row in profiles)
          row['user_id'] as String: row,
      };
      return pending.map<FriendRequestItem>((row) {
        final requesterId = row['requester_id'] as String;
        final profile = profileMap[requesterId];
        return FriendRequestItem(
          requestId: row['id'] as String,
          requesterId: requesterId,
          requesterName: (profile?['display_name'] as String?) ??
              (profile?['email'] as String?)?.split('@').first ??
              '用户',
          requesterEmail: profile?['email'] as String? ?? '',
          requesterAvatar: profile?['avatar_url'] as String?,
          requesterShortId: profile?['short_id'] as String?,
          status: row['status'] as String? ?? 'pending',
          createdAt: _parseDateTime(row['created_at']),
        );
      }).toList();
    });
  }

  static DateTime? _parseDateTime(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  /// 收到的申请：作为接收方的好友申请
  Stream<List<FriendRequestItem>> _watchIncomingFriendRequestRecords(
    String userId,
  ) {
    return _client
        .from('friend_requests')
        .stream(primaryKey: ['id'])
        .eq('receiver_id', userId)
        .asyncMap((rows) async {
      if (rows.isEmpty) return <FriendRequestItem>[];
      final requesterIds = rows
          .map((row) => row['requester_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final profiles = await _client
          .from('user_profiles')
          .select()
          .inFilter('user_id', requesterIds);
      final profileMap = {
        for (final row in profiles)
          row['user_id'] as String: row,
      };
      return rows.map<FriendRequestItem>((row) {
        final requesterId = row['requester_id'] as String;
        final profile = profileMap[requesterId];
        return FriendRequestItem(
          requestId: row['id'] as String,
          requesterId: requesterId,
          requesterName: (profile?['display_name'] as String?) ??
              (profile?['email'] as String?)?.split('@').first ??
              '用户',
          requesterEmail: profile?['email'] as String? ?? '',
          requesterAvatar: profile?['avatar_url'] as String?,
          requesterShortId: profile?['short_id'] as String?,
          status: row['status'] as String? ?? 'pending',
          createdAt: _parseDateTime(row['created_at']),
        );
      }).toList();
    });
  }

  /// 发出的申请：作为申请方的好友申请
  Stream<List<FriendRequestItem>> _watchOutgoingFriendRequestRecords(
    String userId,
  ) {
    return _client
        .from('friend_requests')
        .stream(primaryKey: ['id'])
        .eq('requester_id', userId)
        .asyncMap((rows) async {
      if (rows.isEmpty) return <FriendRequestItem>[];
      final receiverIds = rows
          .map((row) => row['receiver_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final profiles = await _client
          .from('user_profiles')
          .select()
          .inFilter('user_id', receiverIds);
      final profileMap = {
        for (final row in profiles)
          row['user_id'] as String: row,
      };
      return rows.map<FriendRequestItem>((row) {
        final receiverId = row['receiver_id'] as String;
        final profile = profileMap[receiverId];
        return FriendRequestItem(
          requestId: row['id'] as String,
          requesterId: userId,
          requesterName: '',
          requesterEmail: '',
          requesterAvatar: null,
          requesterShortId: null,
          status: row['status'] as String? ?? 'pending',
          createdAt: _parseDateTime(row['created_at']),
          isOutgoing: true,
          receiverId: receiverId,
          receiverName: (profile?['display_name'] as String?) ??
              (profile?['email'] as String?)?.split('@').first ??
              '用户',
          receiverAvatar: profile?['avatar_url'] as String?,
          receiverShortId: profile?['short_id'] as String?,
        );
      }).toList();
    });
  }

  /// 所有系统消息记录：收到的 + 发出的好友申请（待处理/已通过/已拒绝），按时间倒序
  Stream<List<FriendRequestItem>> watchAllFriendRequestRecords({
    required String userId,
  }) {
    List<FriendRequestItem>? lastIncoming;
    List<FriendRequestItem>? lastOutgoing;
    final controller = StreamController<List<FriendRequestItem>>.broadcast();

    void emit() {
      if (lastIncoming != null && lastOutgoing != null) {
        final merged = [...lastIncoming!, ...lastOutgoing!];
        merged.sort((a, b) {
          final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bt.compareTo(at);
        });
        controller.add(merged);
      }
    }

    late final StreamSubscription<List<FriendRequestItem>> subIn;
    late final StreamSubscription<List<FriendRequestItem>> subOut;
    subIn = _watchIncomingFriendRequestRecords(userId).listen((list) {
      lastIncoming = list;
      emit();
    }, onError: controller.addError, onDone: () {});
    subOut = _watchOutgoingFriendRequestRecords(userId).listen((list) {
      lastOutgoing = list;
      emit();
    }, onError: controller.addError, onDone: () {});

    controller.onCancel = () async {
      await subIn.cancel();
      await subOut.cancel();
    };

    return controller.stream;
  }

  /// 发送好友申请。拒绝后可再次申请（会更新为 pending 并再次推送）。
  /// 若已是好友或已发过待处理申请，会抛出异常，由调用方提示。
  Future<void> sendFriendRequest({
    required String requesterId,
    required String receiverId,
  }) async {
    if (requesterId == receiverId) {
      return;
    }
    final existing = await _client
        .from('friend_requests')
        .select()
        .eq('requester_id', requesterId)
        .eq('receiver_id', receiverId)
        .maybeSingle();
    final status = existing?['status'] as String?;
    if (existing != null && status == 'accepted') {
      throw Exception('already_friends');
    }
    if (existing != null && status == 'pending') {
      throw Exception('already_pending');
    }
    if (existing != null && status == 'rejected') {
      // 拒绝后可再次申请：将原记录改为 pending 并再次推送
      await _client
          .from('friend_requests')
          .update({
            'status': 'pending',
            'created_at': DateTime.now().toIso8601String(),
          })
          .eq('id', existing['id']);
      await _sendFriendRequestPush(requesterId: requesterId, receiverId: receiverId);
      return;
    }
    await _client.from('friend_requests').insert({
      'requester_id': requesterId,
      'receiver_id': receiverId,
      'status': 'pending',
    });
    await _sendFriendRequestPush(requesterId: requesterId, receiverId: receiverId);
  }

  Future<void> _sendFriendRequestPush({
    required String requesterId,
    required String receiverId,
  }) async {
    try {
      final profile = await _client
          .from('user_profiles')
          .select('display_name,email')
          .eq('user_id', requesterId)
          .maybeSingle();
      final displayName = (profile?['display_name'] as String?) ??
          (profile?['email'] as String?)?.split('@').first ??
          '用户';
      await _client.functions.invoke('send_push', body: {
        'receiverId': receiverId,
        'title': '好友请求',
        'body': '$displayName 请求添加你为好友',
        'messageType': 'friend_request',
        'requesterId': requesterId,
      });
    } catch (_) {
      // Ignore push failures to avoid blocking friend requests.
    }
  }

  Future<void> acceptRequest({
    required String requestId,
    required String requesterId,
    required String receiverId,
  }) async {
    await _client
        .from('friend_requests')
        .update({'status': 'accepted'}).eq('id', requestId);
    await _client.from('friends').insert([
      {'user_id': requesterId, 'friend_id': receiverId},
      {'user_id': receiverId, 'friend_id': requesterId},
    ]);
  }

  Future<void> rejectRequest({required String requestId}) async {
    await _client
        .from('friend_requests')
        .update({'status': 'rejected'}).eq('id', requestId);
  }

  /// 删除好友：同时清理 friends 与 friend_requests，避免删除后再次添加仍提示「已是好友」。
  Future<void> deleteFriend({
    required String userId,
    required String friendId,
  }) async {
    await _client
        .from('friends')
        .delete()
        .eq('user_id', userId)
        .eq('friend_id', friendId);
    await _client
        .from('friends')
        .delete()
        .eq('user_id', friendId)
        .eq('friend_id', userId);
    // 清理好友申请记录（sendFriendRequest 用 friend_requests.status=='accepted' 判断已是好友）
    await _client
        .from('friend_requests')
        .delete()
        .eq('requester_id', userId)
        .eq('receiver_id', friendId);
    await _client
        .from('friend_requests')
        .delete()
        .eq('requester_id', friendId)
        .eq('receiver_id', userId);
    // 清理双方对该好友的备注
    await _client
        .from('friend_remarks')
        .delete()
        .eq('user_id', userId)
        .eq('friend_id', friendId);
    await _client
        .from('friend_remarks')
        .delete()
        .eq('user_id', friendId)
        .eq('friend_id', userId);
  }

  /// 判断两人是否为好友（双向关系存在即可）
  /// 同时检查 friends 表与 friend_requests 表，避免数据不一致
  Future<bool> isFriend({
    required String userId,
    required String friendId,
  }) async {
    if (userId.isEmpty || friendId.isEmpty || userId == friendId) {
      return false;
    }
    final friendsRow = await _client
        .from('friends')
        .select('user_id')
        .eq('user_id', userId)
        .eq('friend_id', friendId)
        .maybeSingle();
    if (friendsRow != null) return true;
    // 若 friends 表无记录，再查 friend_requests（accepted 表示已是好友）
    final req1 = await _client
        .from('friend_requests')
        .select('status')
        .eq('requester_id', userId)
        .eq('receiver_id', friendId)
        .maybeSingle();
    if (req1?['status'] == 'accepted') return true;
    final req2 = await _client
        .from('friend_requests')
        .select('status')
        .eq('requester_id', friendId)
        .eq('receiver_id', userId)
        .maybeSingle();
    return req2?['status'] == 'accepted';
  }
}
