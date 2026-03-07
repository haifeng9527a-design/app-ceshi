import 'dart:async';
import 'dart:typed_data';

import '../../api/teachers_api.dart';
import '../../core/api_client.dart';
import '../../core/models.dart' as core_models;
import 'teacher_models.dart';

class TeacherRepository {
  Stream<T> _asBroadcast<T>(Stream<T> stream) {
    if (stream.isBroadcast) return stream;
    return stream.asBroadcastStream();
  }

  static core_models.Teacher profileToTeacher(TeacherProfile p) {
    final name = p.displayName?.trim().isNotEmpty == true
        ? p.displayName!
        : (p.realName?.trim().isNotEmpty == true ? p.realName! : '交易员');
    final title = p.title?.trim().isNotEmpty == true ? p.title! : '导师';
    final bio = p.bio?.trim().isNotEmpty == true ? p.bio! : '';
    final tags = p.tags ?? const [];
    return core_models.Teacher(
      id: p.userId,
      name: name,
      title: title,
      avatarUrl: p.avatarUrl ?? '',
      bio: bio,
      tags: tags,
      wins: p.wins ?? 0,
      losses: p.losses ?? 0,
      rating: p.rating ?? 0,
      todayStrategy: p.todayStrategy?.trim().isNotEmpty == true
          ? p.todayStrategy!
          : '暂无今日策略',
      strategyHistory: const [],
      trades: const [],
      positions: const [],
      historyPositions: const [],
      pnlCurrent: (p.pnlCurrent ?? 0).toDouble(),
      pnlMonth: (p.pnlMonth ?? 0).toDouble(),
      pnlYear: (p.pnlYear ?? 0).toDouble(),
      pnlTotal: (p.pnlTotal ?? 0).toDouble(),
      comments: const [],
      articles: const [],
      schedules: const [],
    );
  }

  TeacherRepository();

  bool get _useApi => ApiClient.instance.isAvailable;

  Stream<T> _pollImmediately<T>(
    Future<T> Function() fetch, {
    required Duration interval,
  }) async* {
    while (true) {
      yield await fetch();
      await Future<void>.delayed(interval);
    }
  }

  Future<TeacherProfile?> fetchProfile(String userId) async {
    if (userId.isEmpty || !_useApi) return null;
    return TeachersApi.instance.getProfile(userId);
  }

  Future<void> upsertProfile(TeacherProfile profile) async {
    if (!_useApi) return;
    await TeachersApi.instance.upsertMyProfile(profile.toMap());
  }

  Stream<List<TeacherStrategy>> watchStrategies(String teacherId) {
    if (teacherId.isEmpty || !_useApi) return Stream.value(const []);
    return _asBroadcast(_pollImmediately(
      () => TeachersApi.instance.getStrategies(teacherId),
      interval: const Duration(seconds: 10),
    ).map((list) => list..sort((a, b) => b.createdAt.compareTo(a.createdAt))));
  }

  Stream<List<TeacherStrategy>> watchPublishedStrategies(String teacherId) {
    if (teacherId.isEmpty || !_useApi) return Stream.value(const []);
    return _asBroadcast(_pollImmediately(
      () => TeachersApi.instance.getStrategies(teacherId),
      interval: const Duration(seconds: 10),
    ).map((list) => list.where((s) => s.status == 'published').toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt))));
  }

  static List<core_models.Comment> _commentRowsToComments(
    List<Map<String, dynamic>> rows,
  ) {
    final list = rows.map((row) {
      final id = row['id'] as String? ?? '';
      final userName = row['user_name'] as String? ?? '用户';
      final content = row['content'] as String? ?? '';
      final replyToId = row['reply_to_comment_id']?.toString();
      final replyToContent = row['reply_to_content'] as String?;
      final avatarUrl = (row['avatar_url'] as String?)?.trim();
      final ts = row['comment_time'] ?? row['created_at'];
      DateTime? dt;
      if (ts != null) {
        if (ts is DateTime) {
          dt = ts;
        } else if (ts is String) {
          dt = DateTime.tryParse(ts);
        }
      }
      final date = dt != null
          ? '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
              '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
          : '';
      return MapEntry(
        dt ?? DateTime.fromMillisecondsSinceEpoch(0),
        core_models.Comment(
          id: id,
          userName: userName,
          content: content,
          date: date,
          replyToCommentId: replyToId,
          replyToContent: replyToContent,
          avatarUrl: avatarUrl?.isNotEmpty == true ? avatarUrl : null,
        ),
      );
    }).toList();
    list.sort((a, b) => b.key.compareTo(a.key));
    return list.map((e) => e.value).toList();
  }

  Stream<List<core_models.Comment>> watchTeacherComments(String teacherId) {
    if (teacherId.isEmpty || !_useApi) return Stream.value(const []);
    return _asBroadcast(_pollImmediately(
      () => TeachersApi.instance.getComments(teacherId),
      interval: const Duration(seconds: 5),
    ).map(_commentRowsToComments));
  }

  Stream<List<core_models.Comment>> watchStrategyComments(
    String teacherId,
    String strategyId,
  ) {
    if (teacherId.isEmpty || strategyId.isEmpty || !_useApi) {
      return Stream.value(const []);
    }
    return _asBroadcast(_pollImmediately(
      () => TeachersApi.instance.getComments(teacherId, strategyId: strategyId),
      interval: const Duration(seconds: 5),
    ).map(_commentRowsToComments));
  }

  Stream<int> watchTeacherLikesCount(String teacherId) {
    if (teacherId.isEmpty || !_useApi) return Stream.value(0);
    return _pollImmediately(
      () => TeachersApi.instance.getLikeCount(teacherId),
      interval: const Duration(seconds: 5),
    );
  }

  Stream<bool> watchUserLiked({
    required String teacherId,
    required String userId,
  }) {
    if (teacherId.isEmpty || userId.isEmpty || !_useApi) {
      return Stream.value(false);
    }
    return _pollImmediately(
      () => TeachersApi.instance.getMyLikeStatus(teacherId),
      interval: const Duration(seconds: 5),
    );
  }

  Future<void> toggleLike({
    required String teacherId,
    required String userId,
  }) async {
    if (teacherId.isEmpty || userId.isEmpty || !_useApi) return;
    await TeachersApi.instance.toggleLike(teacherId);
  }

  Future<String> insertComment({
    required String teacherId,
    required String userId,
    required String content,
    String? strategyId,
    String? replyToCommentId,
    String? replyToContent,
  }) async {
    if (teacherId.isEmpty || userId.isEmpty || content.trim().isEmpty) {
      return '用户';
    }
    if (!_useApi) return '用户';
    final name = await TeachersApi.instance.insertComment(
      teacherId: teacherId,
      content: content,
      strategyId: strategyId,
      replyToCommentId: replyToCommentId,
      replyToContent: replyToContent,
    );
    return name ?? '用户';
  }

  Stream<List<TeacherProfile>> watchPublicProfiles() {
    if (!_useApi) return Stream.value(const []);
    return Stream.periodic(const Duration(seconds: 15), (_) => null)
        .asyncMap((_) => TeachersApi.instance.getTeachers());
  }

  Future<bool> getFollowStatus({
    required String teacherId,
    required String userId,
  }) async {
    if (teacherId.isEmpty || userId.isEmpty || !_useApi) return false;
    return TeachersApi.instance.getFollowStatus(teacherId, userId);
  }

  Stream<bool> watchFollowStatus({
    required String teacherId,
    required String userId,
  }) {
    if (teacherId.isEmpty || userId.isEmpty || !_useApi) {
      return Stream.value(false);
    }
    return _pollImmediately(
      () => TeachersApi.instance.getFollowStatus(teacherId, userId),
      interval: const Duration(seconds: 5),
    );
  }

  Stream<int> watchFollowerCount(String teacherId) {
    if (teacherId.isEmpty || !_useApi) return Stream.value(0);
    return _pollImmediately(
      () => TeachersApi.instance.getFollowerCount(teacherId),
      interval: const Duration(seconds: 10),
    );
  }

  Future<void> followTeacher({
    required String teacherId,
    required String userId,
  }) async {
    if (teacherId.isEmpty || userId.isEmpty || !_useApi) return;
    await TeachersApi.instance.follow(teacherId, userId);
  }

  Future<void> unfollowTeacher({
    required String teacherId,
    required String userId,
  }) async {
    if (teacherId.isEmpty || userId.isEmpty || !_useApi) return;
    await TeachersApi.instance.unfollow(teacherId, userId);
  }

  Future<List<String>> getFollowedTeacherIds(String userId) async {
    if (userId.isEmpty || !_useApi) return [];
    return TeachersApi.instance.getFollowedTeacherIds(userId);
  }

  Future<TeacherProfile?> getRankOneTeacherProfile() async {
    if (!_useApi) return null;
    return TeachersApi.instance.getRankOne();
  }

  Future<String> uploadStrategyImage({
    required String teacherId,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (!_useApi) throw StateError('API 未配置');
    final url = await TeachersApi.instance.uploadBase64(
      'api/upload/teacher-strategy-image',
      bytes: bytes,
      fileName: fileName,
      contentType: contentType,
    );
    if (url == null || url.isEmpty) throw StateError('策略图片上传失败');
    return url;
  }

  Future<void> addStrategy({
    required String teacherId,
    required String title,
    required String summary,
    required String content,
    List<String> imageUrls = const [],
  }) async {
    if (!_useApi) return;
    await TeachersApi.instance.addStrategy(
      title: title,
      summary: summary,
      content: content,
      imageUrls: imageUrls,
    );
  }

  Future<void> updateStrategyStatus({
    required String strategyId,
    required String status,
  }) async {
    if (!_useApi) return;
    await TeachersApi.instance.updateStrategyStatus(
      strategyId: strategyId,
      status: status,
    );
  }

  Stream<List<TradeRecord>> watchTradeRecords(String teacherId) {
    if (!_useApi) return Stream.value(const []);
    return _pollImmediately(
      () => TeachersApi.instance.getTradeRecords(teacherId),
      interval: const Duration(seconds: 5),
    );
  }

  Stream<List<TeacherPosition>> watchPositions(String teacherId) {
    if (!_useApi) return Stream.value(const []);
    return _pollImmediately(
      () => TeachersApi.instance.getPositions(teacherId),
      interval: const Duration(seconds: 5),
    );
  }

  Stream<List<TeacherPosition>> watchHistoryPositions(String teacherId) {
    if (!_useApi) return Stream.value(const []);
    return _pollImmediately(
      () => TeachersApi.instance.getPositions(teacherId, history: true),
      interval: const Duration(seconds: 5),
    );
  }

  Future<void> addTradeRecordDetail({
    required String teacherId,
    required String symbol,
    required String stockName,
    required DateTime buyTime,
    required double buyPrice,
    required double buyQty,
    required DateTime sellTime,
    required double sellPrice,
    required double sellQty,
  }) async {
    if (!_useApi) return;
    final pnlAmount = (sellPrice - buyPrice) * sellQty;
    await TeachersApi.instance.addTradeRecord({
      'teacher_id': teacherId,
      'symbol': symbol,
      'asset': symbol,
      'side': 'buy',
      'buy_time': buyTime.toUtc().toIso8601String(),
      'buy_price': buyPrice,
      'buy_shares': buyQty,
      'sell_time': sellTime.toUtc().toIso8601String(),
      'sell_price': sellPrice,
      'sell_shares': sellQty,
      'pnl': pnlAmount,
      'pnl_amount': pnlAmount,
      'trade_time': sellTime.toUtc().toIso8601String(),
    });
  }

  Future<void> addTradeRecord({
    required String teacherId,
    required String symbol,
    required String side,
    required num pnl,
    DateTime? tradeTime,
    String? attachmentUrl,
  }) async {
    if (!_useApi) return;
    final payload = <String, dynamic>{
      'teacher_id': teacherId,
      'symbol': symbol,
      'asset': symbol,
      'side': side,
      'pnl': pnl,
      'trade_time': (tradeTime ?? DateTime.now()).toIso8601String(),
    };
    if (attachmentUrl != null && attachmentUrl.isNotEmpty) {
      payload['attachment_url'] = attachmentUrl;
    }
    await TeachersApi.instance.addTradeRecord(payload);
  }

  Future<String> uploadTradeRecordFile({
    required String teacherId,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (!_useApi) throw StateError('API 未配置');
    final url = await TeachersApi.instance.uploadBase64(
      'api/upload/teacher-trade-record-file',
      bytes: bytes,
      fileName: fileName,
      contentType: contentType,
    );
    if (url == null || url.isEmpty) throw StateError('交易记录附件上传失败');
    return url;
  }

  Future<String> uploadTeacherAvatar({
    required String teacherId,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (!_useApi) throw StateError('API 未配置');
    final url = await TeachersApi.instance.uploadBase64(
      'api/upload/teacher-avatar',
      bytes: bytes,
      fileName: fileName,
      contentType: contentType,
    );
    if (url == null || url.isEmpty) throw StateError('交易员头像上传失败');
    return url;
  }

  Future<String> uploadTeacherVerification({
    required String teacherId,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
    required String category,
  }) async {
    if (!_useApi) throw StateError('API 未配置');
    final url = await TeachersApi.instance.uploadBase64(
      'api/upload/teacher-verification',
      bytes: bytes,
      fileName: fileName,
      contentType: contentType,
      category: category,
    );
    if (url == null || url.isEmpty) throw StateError('认证资料上传失败');
    return url;
  }
}
