import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../api/teachers_api.dart';
import '../../core/api_client.dart';
import '../../core/models.dart' as core_models;
import '../../core/supabase_bootstrap.dart';
import 'teacher_models.dart';

class TeacherRepository {
  /// 将 TeacherProfile 转为 Teacher（供策略中心等页面使用）
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
  static const String _recordBucket = 'teacher-records';
  static const String _avatarBucket = 'avatars';
  static const String _verifyBucket = 'teacher-verify';

  SupabaseClient? get _client => SupabaseBootstrap.clientOrNull;
  bool get _hasClient => _client != null && SupabaseBootstrap.isReady;
  bool get _useApi => ApiClient.instance.isAvailable;

  Future<TeacherProfile?> fetchProfile(String userId) async {
    if (userId.isEmpty) return null;
    if (_useApi) return TeachersApi.instance.getProfile(userId);
    if (!_hasClient) return null;
    final row = await _client!
        .from('teacher_profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) {
      return null;
    }
    // 个性签名与「我的」页同步，从 user_profiles 读取
    final userRow = await _client!
        .from('user_profiles')
        .select('signature')
        .eq('user_id', userId)
        .maybeSingle();
    final map = Map<String, dynamic>.from(row);
    if (userRow != null && userRow['signature'] != null) {
      map['signature'] = userRow['signature'];
    }
    return TeacherProfile.fromMap(map);
  }

  Future<void> upsertProfile(TeacherProfile profile) async {
    if (!_hasClient) return;
    await _client!
        .from('teacher_profiles')
        .upsert(profile.toMap());
  }

  Stream<List<TeacherStrategy>> watchStrategies(String teacherId) {
    if (teacherId.isEmpty) return Stream.value(const []);
    if (_useApi) {
      return Stream.periodic(const Duration(seconds: 10), (_) => null)
          .asyncMap((_) => TeachersApi.instance.getStrategies(teacherId))
          .map((list) => list..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
    }
    if (!_hasClient) return Stream.value(const []);
    return _client!
        .from('trade_strategies')
        .stream(primaryKey: ['id']).map(
      (rows) => rows
          .where((row) => row['teacher_id'] == teacherId)
          .map((row) => TeacherStrategy.fromMap(row))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
    );
  }

  Stream<List<TeacherStrategy>> watchPublishedStrategies(String teacherId) {
    if (teacherId.isEmpty) return Stream.value(const []);
    if (_useApi) {
      return Stream.periodic(const Duration(seconds: 10), (_) => null)
          .asyncMap((_) => TeachersApi.instance.getStrategies(teacherId))
          .map((list) => list.where((s) => s.status == 'published').toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
    }
    if (!_hasClient) return Stream.value(const []);
    return _client!
        .from('trade_strategies')
        .stream(primaryKey: ['id']).map(
      (rows) => rows
          .where((row) =>
              row['teacher_id'] == teacherId &&
              (row['status'] as String? ?? '') == 'published')
          .map((row) => TeacherStrategy.fromMap(row))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
    );
  }

  static List<core_models.Comment> _commentRowsToComments(List<Map<String, dynamic>> rows) {
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
        if (ts is DateTime) dt = ts;
        else if (ts is String) dt = DateTime.tryParse(ts);
      }
      final date = dt != null
          ? '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
              '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
          : '';
      return MapEntry(dt ?? DateTime.fromMillisecondsSinceEpoch(0), core_models.Comment(
        id: id,
        userName: userName,
        content: content,
        date: date,
        replyToCommentId: replyToId,
        replyToContent: replyToContent,
        avatarUrl: avatarUrl?.isNotEmpty == true ? avatarUrl : null,
      ));
    }).toList();
    list.sort((a, b) => b.key.compareTo(a.key));
    return list.map((e) => e.value).toList();
  }

  /// 监听指定交易员的评论（全部，用于兼容）
  Stream<List<core_models.Comment>> watchTeacherComments(String teacherId) {
    if (teacherId.isEmpty) return Stream.value(const []);
    if (_useApi) {
      return Stream.periodic(const Duration(seconds: 5), (_) => null)
          .asyncMap((_) => TeachersApi.instance.getComments(teacherId))
          .map(_commentRowsToComments);
    }
    if (!_hasClient) return Stream.value(const []);
    return _client!
        .from('teacher_comments')
        .stream(primaryKey: ['id']).map(
      (rows) {
        final list = rows
            .where((row) =>
                row['teacher_id'] == teacherId && row['strategy_id'] == null)
            .map((row) {
          final id = row['id'] as String? ?? '';
          final userName = row['user_name'] as String? ?? '用户';
          final content = row['content'] as String? ?? '';
          final replyToId = row['reply_to_comment_id']?.toString();
          final replyToContent = row['reply_to_content'] as String?;

          final avatarUrl = (row['avatar_url'] as String?)?.trim();
          final ts = row['comment_time'] ?? row['created_at'];
          DateTime? dt;
          if (ts != null) {
            if (ts is DateTime)
              dt = ts;
            else if (ts is String) dt = DateTime.tryParse(ts);
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
      },
    );
  }

  /// 监听指定策略的评论
  Stream<List<core_models.Comment>> watchStrategyComments(
    String teacherId,
    String strategyId,
  ) {
    if (teacherId.isEmpty || strategyId.isEmpty) return Stream.value(const []);
    if (_useApi) {
      return Stream.periodic(const Duration(seconds: 5), (_) => null)
          .asyncMap((_) => TeachersApi.instance.getComments(teacherId, strategyId: strategyId))
          .map(_commentRowsToComments);
    }
    if (!_hasClient) return Stream.value(const []);
    return _client!
        .from('teacher_comments')
        .stream(primaryKey: ['id']).map(
      (rows) {
        final list = rows
            .where((row) =>
                row['teacher_id'] == teacherId &&
                row['strategy_id'] == strategyId)
            .map((row) {
          final id = row['id'] as String? ?? '';
          final userName = row['user_name'] as String? ?? '用户';
          final content = row['content'] as String? ?? '';
          final replyToId = row['reply_to_comment_id']?.toString();
          final replyToContent = row['reply_to_content'] as String?;
          final avatarUrl = (row['avatar_url'] as String?)?.trim();
          final ts = row['comment_time'] ?? row['created_at'];
          DateTime? dt;
          if (ts != null) {
            if (ts is DateTime)
              dt = ts;
            else if (ts is String) dt = DateTime.tryParse(ts);
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
      },
    );
  }

  /// 监听指定交易员策略的点赞数
  Stream<int> watchTeacherLikesCount(String teacherId) {
    if (teacherId.isEmpty || !_hasClient) return Stream.value(0);
    return _client!
        .from('teacher_strategy_likes')
        .stream(primaryKey: ['teacher_id', 'user_id']).map(
      (rows) => rows.where((r) => r['teacher_id'] == teacherId).length,
    );
  }

  /// 当前用户是否已点赞
  Stream<bool> watchUserLiked({
    required String teacherId,
    required String userId,
  }) {
    if (teacherId.isEmpty || userId.isEmpty || !_hasClient) return Stream.value(false);
    return _client!
        .from('teacher_strategy_likes')
        .stream(primaryKey: ['teacher_id', 'user_id']).map(
      (rows) => rows.any(
        (r) => r['teacher_id'] == teacherId && r['user_id'] == userId,
      ),
    );
  }

  /// 点赞/取消点赞
  Future<void> toggleLike({
    required String teacherId,
    required String userId,
  }) async {
    if (teacherId.isEmpty || userId.isEmpty || !_hasClient) return;
    final existing = await _client!
        .from('teacher_strategy_likes')
        .select('teacher_id')
        .eq('teacher_id', teacherId)
        .eq('user_id', userId)
        .maybeSingle();
    if (existing != null) {
      await _client!
          .from('teacher_strategy_likes')
          .delete()
          .eq('teacher_id', teacherId)
          .eq('user_id', userId);
    } else {
      await _client!.from('teacher_strategy_likes').insert({
        'teacher_id': teacherId,
        'user_id': userId,
      });
    }
  }

  /// 发表评论，返回使用的昵称（用于乐观更新）
  /// [strategyId] 可选，指定则评论关联到该策略
  /// [replyToCommentId] 可选，被回复的评论 ID
  /// [replyToContent] 可选，被回复评论的内容摘要
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
    if (_useApi) {
      final name = await TeachersApi.instance.insertComment(
        teacherId: teacherId,
        content: content,
        strategyId: strategyId,
        replyToCommentId: replyToCommentId,
        replyToContent: replyToContent,
      );
      return name ?? '用户';
    }
    if (!_hasClient) return '用户';
    String userName = '用户';
    String? avatarUrl;
    try {
      final profile = await _client!
          .from('user_profiles')
          .select('display_name, avatar_url')
          .eq('user_id', userId)
          .maybeSingle();
      if (profile != null) {
        final dn = profile['display_name'] as String?;
        if (dn?.trim().isNotEmpty == true) userName = dn!.trim();
        final av = profile['avatar_url'] as String?;
        if (av?.trim().isNotEmpty == true) avatarUrl = av!.trim();
      }
    } catch (_) {
      // 忽略资料查询失败，使用默认昵称
    }
    final data = <String, dynamic>{
      'teacher_id': teacherId,
      'user_id': userId,
      'user_name': userName,
      'avatar_url': avatarUrl,
      'content': content.trim(),
      'comment_time': DateTime.now().toIso8601String(),
    };
    if (strategyId != null && strategyId.isNotEmpty) {
      data['strategy_id'] = strategyId;
    }
    if (replyToCommentId != null && replyToCommentId.isNotEmpty) {
      data['reply_to_comment_id'] = replyToCommentId;
      if (replyToContent != null && replyToContent.isNotEmpty) {
        data['reply_to_content'] = replyToContent.length > 50
            ? '${replyToContent.substring(0, 50)}…'
            : replyToContent;
      }
    }
    await _client!.from('teacher_comments').insert(data);
    return userName;
  }

  Stream<List<TeacherProfile>> watchPublicProfiles() {
    if (_useApi) {
      return Stream.periodic(const Duration(seconds: 15), (_) => null)
          .asyncMap((_) => TeachersApi.instance.getTeachers());
    }
    if (!_hasClient) return Stream.value(const []);
    return _client!
        .from('teacher_profiles')
        .stream(primaryKey: ['user_id']).map(
      (rows) => rows
          .where((row) => (row['status'] as String? ?? '') != 'blocked')
          .map((row) => TeacherProfile.fromMap(row))
          .toList(),
    );
  }

  /// 一次性查询当前用户是否已关注该交易员（不依赖 Realtime，适合按钮点击时用）
  Future<bool> getFollowStatus({
    required String teacherId,
    required String userId,
  }) async {
    if (teacherId.isEmpty || userId.isEmpty) return false;
    if (_useApi) return TeachersApi.instance.getFollowStatus(teacherId, userId);
    if (!_hasClient) return false;
    final rows = await _client!
        .from('teacher_follows')
        .select('id')
        .eq('teacher_id', teacherId)
        .eq('user_id', userId);
    return rows.isNotEmpty;
  }

  Stream<bool> watchFollowStatus({
    required String teacherId,
    required String userId,
  }) {
    if (teacherId.isEmpty || userId.isEmpty) return Stream.value(false);
    if (_useApi) {
      return Stream.periodic(const Duration(seconds: 5), (_) => null)
          .asyncMap((_) => TeachersApi.instance.getFollowStatus(teacherId, userId));
    }
    if (!_hasClient) return Stream.value(false);
    // Realtime 只支持单列 eq，按 teacher_id 订阅后在本端再按 user_id 过滤
    return _client!
        .from('teacher_follows')
        .stream(primaryKey: ['id'])
        .eq('teacher_id', teacherId)
        .map(
          (rows) => rows.any(
            (row) => row['user_id'] == userId,
          ),
        );
  }

  Stream<int> watchFollowerCount(String teacherId) {
    if (teacherId.isEmpty) return Stream.value(0);
    if (_useApi) {
      return Stream.periodic(const Duration(seconds: 10), (_) => null)
          .asyncMap((_) => TeachersApi.instance.getFollowerCount(teacherId));
    }
    return _client!
        .from('teacher_follows')
        .stream(primaryKey: ['id']).map(
      (rows) => rows.where((row) => row['teacher_id'] == teacherId).length,
    );
  }

  /// 关注交易员。若已关注过（重复插入）则静默视为成功，不抛错。
  Future<void> followTeacher({
    required String teacherId,
    required String userId,
  }) async {
    if (teacherId.isEmpty || userId.isEmpty) return;
    if (_useApi) {
      await TeachersApi.instance.follow(teacherId, userId);
      return;
    }
    if (!_hasClient) return;
    try {
      await _client!.from('teacher_follows').insert({
        'teacher_id': teacherId,
        'user_id': userId,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('duplicate') ||
          msg.contains('unique') ||
          msg.contains('already exists')) {
        return;
      }
      rethrow;
    }
  }

  Future<void> unfollowTeacher({
    required String teacherId,
    required String userId,
  }) async {
    if (teacherId.isEmpty || userId.isEmpty) return;
    if (_useApi) {
      await TeachersApi.instance.unfollow(teacherId, userId);
      return;
    }
    if (!_hasClient) return;
    await _client!
        .from('teacher_follows')
        .delete()
        .eq('teacher_id', teacherId)
        .eq('user_id', userId);
  }

  /// 当前用户关注的交易员 ID 列表（按关注时间倒序，最近关注的在前）
  Future<List<String>> getFollowedTeacherIds(String userId) async {
    if (userId.isEmpty) return [];
    if (_useApi) return TeachersApi.instance.getFollowedTeacherIds(userId);
    if (!_hasClient) return [];
    final rows = await _client!
        .from('teacher_follows')
        .select('teacher_id')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => r['teacher_id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  /// 排名第一的交易员（已通过、按本月盈亏降序取第一条）
  Future<TeacherProfile?> getRankOneTeacherProfile() async {
    if (_useApi) return TeachersApi.instance.getRankOne();
    if (!_hasClient) return null;
    final rows = await _client!
        .from('teacher_profiles')
        .select()
        .eq('status', 'approved')
        .order('pnl_month', ascending: false)
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return TeacherProfile.fromMap(Map<String, dynamic>.from(list.first as Map));
  }

  /// 上传策略配图，返回公开 URL
  Future<String> uploadStrategyImage({
    required String teacherId,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (!_hasClient) throw StateError('Supabase 未配置');
    final safeName = fileName.replaceAll(' ', '_');
    final path =
        'strategies/$teacherId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await _client!.storage.from(_recordBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
          ),
        );
    return _client!.storage
        .from(_recordBucket)
        .getPublicUrl(path);
  }

  Future<void> addStrategy({
    required String teacherId,
    required String title,
    required String summary,
    required String content,
    List<String> imageUrls = const [],
  }) async {
    if (!_hasClient) return;
    await _client!.from('trade_strategies').insert({
      'teacher_id': teacherId,
      'title': title,
      'summary': summary,
      'content': content,
      'image_urls': imageUrls.isEmpty ? null : imageUrls,
      'status': 'published',
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> updateStrategyStatus({
    required String strategyId,
    required String status,
  }) async {
    if (!_hasClient) return;
    await _client!.from('trade_strategies').update({
      'status': status,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', strategyId);
  }

  Stream<List<TradeRecord>> watchTradeRecords(String teacherId) {
    if (!_hasClient) return Stream.value(const []);
    return _client!
        .from('trade_records')
        .stream(primaryKey: ['id']).map(
      (rows) => rows
          .where((row) => row['teacher_id'] == teacherId)
          .map((row) => TradeRecord.fromMap(row))
          .toList()
        ..sort((a, b) {
          final aTime = a.sellTime ??
              a.tradeTime ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = b.sellTime ??
              b.tradeTime ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        }),
    );
  }

  Stream<List<TeacherPosition>> watchPositions(String teacherId) {
    if (!_hasClient) return Stream.value(const []);
    return _client!
        .from('teacher_positions')
        .stream(primaryKey: ['id']).map(
      (rows) => rows
          .where((row) =>
              row['teacher_id'] == teacherId &&
              (row['is_history'] as bool? ?? false) == false)
          .map((row) => TeacherPosition.fromMap(row))
          .toList(),
    );
  }

  /// 历史持仓（is_history = true），供关注页实时同步
  Stream<List<TeacherPosition>> watchHistoryPositions(String teacherId) {
    if (!_hasClient) return Stream.value(const []);
    return _client!
        .from('teacher_positions')
        .stream(primaryKey: ['id']).map(
      (rows) => rows
          .where((row) =>
              row['teacher_id'] == teacherId &&
              (row['is_history'] as bool? ?? false) == true)
          .map((row) => TeacherPosition.fromMap(row))
          .toList(),
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
    if (!_hasClient) return;
    final pnlAmount = (sellPrice - buyPrice) * sellQty;
    await _client!.from('trade_records').insert({
      'teacher_id': teacherId,
      'symbol': symbol,
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
      'created_at': DateTime.now().toUtc().toIso8601String(),
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
    final payload = {
      'teacher_id': teacherId,
      'symbol': symbol,
      'side': side,
      'pnl': pnl,
      'trade_time': (tradeTime ?? DateTime.now()).toIso8601String(),
      'created_at': DateTime.now().toIso8601String(),
    };
    if (attachmentUrl != null && attachmentUrl.isNotEmpty) {
      payload['attachment_url'] = attachmentUrl;
    }
    if (!_hasClient) return;
    await _client!.from('trade_records').insert(payload);
    if (attachmentUrl != null && attachmentUrl.isNotEmpty) {
      await _client!.from('trade_record_files').insert({
        'teacher_id': teacherId,
        'file_url': attachmentUrl,
        'file_type': 'image',
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<String> uploadTradeRecordFile({
    required String teacherId,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (!_hasClient) throw StateError('Supabase 未配置');
    final safeName = fileName.replaceAll(' ', '_');
    final path =
        'records/$teacherId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await _client!.storage.from(_recordBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
          ),
        );
    return _client!.storage
        .from(_recordBucket)
        .getPublicUrl(path);
  }

  Future<String> uploadTeacherAvatar({
    required String teacherId,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (!_hasClient) throw StateError('Supabase 未配置');
    final safeName = fileName.replaceAll(' ', '_');
    final path =
        'teachers/$teacherId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await _client!.storage.from(_avatarBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
          ),
        );
    return _client!.storage
        .from(_avatarBucket)
        .getPublicUrl(path);
  }

  Future<String> uploadTeacherVerification({
    required String teacherId,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
    required String category,
  }) async {
    if (!_hasClient) throw StateError('Supabase 未配置');
    final safeName = fileName.replaceAll(' ', '_');
    final path =
        'teachers/$teacherId/$category/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await _client!.storage.from(_verifyBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
          ),
        );
    return _client!.storage
        .from(_verifyBucket)
        .getPublicUrl(path);
  }
}
