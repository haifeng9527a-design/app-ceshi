import 'dart:async';

import '../../api/friends_api.dart';
import '../../api/users_api.dart';
import '../../core/api_client.dart';
import 'friend_models.dart';

class FriendsRepository {
  FriendsRepository();

  bool get _useApi => ApiClient.instance.isAvailable;

  static String _roleLabel(String? role, String teacherStatus) {
    final r = (role ?? '').toString().trim().toLowerCase();
    final status = teacherStatus.toString().trim().toLowerCase();
    if (r == 'admin') return '管理员';
    if (r == 'vip') return '会员';
    if (r == 'teacher' || status == 'approved') return '交易员';
    if (r == 'customer_service') return '客服';
    return '普通用户';
  }

  static FriendProfile _profileFromRow(
    Map<String, dynamic> row, {
    String? teacherStatus,
    String? avatarUrlOverride,
    String? roleLabelOverride,
  }) {
    final upStatus = row['teacher_status'] as String? ?? 'pending';
    final ts = teacherStatus ?? upStatus;
    final avatar = avatarUrlOverride?.trim().isNotEmpty == true
        ? avatarUrlOverride
        : (row['avatar_url'] as String?);
    final roleLabel = roleLabelOverride ?? _roleLabel(row['role'] as String?, ts);
    return FriendProfile(
      userId: row['user_id'] as String,
      displayName: (row['display_name'] as String?) ??
          (row['email'] as String?)?.split('@').first ??
          '用户',
      email: row['email'] as String? ?? '',
      avatarUrl: avatar,
      status: row['status'] as String? ?? 'offline',
      shortId: row['short_id'] as String?,
      level: (row['level'] as int?) ?? 0,
      roleLabel: roleLabel,
      lastOnlineAt: _parseDateTime(row['last_online_at']),
    );
  }

  Future<FriendProfile?> findByEmail(String email) async {
    if (!_useApi) return null;
    return FriendsApi.instance.searchByEmail(email);
  }

  Future<FriendProfile?> findById(String userId) async {
    if (!_useApi) return null;
    final m = await UsersApi.instance.getProfile(userId);
    return m != null ? _profileFromRow(m) : null;
  }

  Future<FriendProfile?> findByShortId(String shortId) async {
    if (!_useApi) return null;
    return FriendsApi.instance.searchByShortId(shortId.trim());
  }

  Stream<int> watchFriendCount({required String userId}) {
    return watchFriends(userId: userId).map((list) => list.length);
  }

  Stream<List<FriendProfile>> watchFriends({required String userId}) {
    if (!_useApi) return Stream.value(<FriendProfile>[]);
    return FriendsApi.instance.watchFriends(userId: userId);
  }

  Stream<Map<String, String>> watchRemarks({required String userId}) {
    if (!_useApi) return Stream.value(<String, String>{});
    return FriendsApi.instance.watchRemarks(userId: userId);
  }

  Future<void> saveRemark({
    required String userId,
    required String friendId,
    required String remark,
  }) async {
    if (!_useApi) return;
    await FriendsApi.instance.saveRemark(userId: userId, friendId: friendId, remark: remark);
  }

  Future<int> getIncomingRequestCount(String userId) async {
    if (userId.isEmpty || !_useApi) return 0;
    return FriendsApi.instance.getIncomingRequestCount(userId);
  }

  Stream<List<FriendRequestItem>> watchIncomingRequests({
    required String userId,
  }) async* {
    if (!_useApi) {
      yield <FriendRequestItem>[];
      return;
    }
    yield await FriendsApi.instance.getIncomingRequests();
    await for (final _ in Stream.periodic(const Duration(seconds: 5))) {
      yield await FriendsApi.instance.getIncomingRequests();
    }
  }

  static DateTime? _parseDateTime(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  Stream<List<FriendRequestItem>> watchAllFriendRequestRecords({
    required String userId,
  }) async* {
    if (!_useApi) {
      yield <FriendRequestItem>[];
      return;
    }
    yield await FriendsApi.instance.getAllRequestRecords();
    await for (final _ in Stream.periodic(const Duration(seconds: 5))) {
      yield await FriendsApi.instance.getAllRequestRecords();
    }
  }

  Future<void> sendFriendRequest({
    required String requesterId,
    required String receiverId,
  }) async {
    if (requesterId == receiverId) return;
    if (!_useApi) return;
    await FriendsApi.instance.sendFriendRequest(requesterId: requesterId, receiverId: receiverId);
  }

  Future<void> acceptRequest({
    required String requestId,
    required String requesterId,
    required String receiverId,
  }) async {
    if (!_useApi) return;
    await FriendsApi.instance.acceptRequest(requestId: requestId, requesterId: requesterId, receiverId: receiverId);
  }

  Future<void> rejectRequest({required String requestId}) async {
    if (!_useApi) return;
    await FriendsApi.instance.rejectRequest(requestId: requestId);
  }

  Future<void> deleteFriend({
    required String userId,
    required String friendId,
  }) async {
    if (!_useApi) return;
    await FriendsApi.instance.deleteFriend(userId: userId, friendId: friendId);
  }

  Future<void> ensureCustomerServiceFriend({
    required String userId,
    required String customerServiceId,
  }) async {
    if (userId.isEmpty || customerServiceId.isEmpty || userId == customerServiceId) return;
    if (!_useApi) return;
    await FriendsApi.instance.ensureCustomerServiceFriend(userId: userId, customerServiceId: customerServiceId);
  }

  Future<bool> isFriend({
    required String userId,
    required String friendId,
  }) async {
    if (userId.isEmpty || friendId.isEmpty || userId == friendId) return false;
    if (!_useApi) return false;
    return FriendsApi.instance.isFriend(userId: userId, friendId: friendId);
  }
}
