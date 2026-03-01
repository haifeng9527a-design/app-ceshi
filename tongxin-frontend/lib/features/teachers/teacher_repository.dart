import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

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

  Future<TeacherProfile?> fetchProfile(String userId) async {
    if (userId.isEmpty) {
      return null;
    }
    final row = await SupabaseBootstrap.client
        .from('teacher_profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) {
      return null;
    }
    // 个性签名与「我的」页同步，从 user_profiles 读取
    final userRow = await SupabaseBootstrap.client
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
    await SupabaseBootstrap.client
        .from('teacher_profiles')
        .upsert(profile.toMap());
  }

  Stream<List<TeacherStrategy>> watchStrategies(String teacherId) {
    return SupabaseBootstrap.client
        .from('trade_strategies')
        .stream(primaryKey: ['id'])
        .map(
          (rows) => rows
              .where((row) => row['teacher_id'] == teacherId)
              .map((row) => TeacherStrategy.fromMap(row))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        );
  }

  Stream<List<TeacherStrategy>> watchPublishedStrategies(String teacherId) {
    return SupabaseBootstrap.client
        .from('trade_strategies')
        .stream(primaryKey: ['id'])
        .map(
          (rows) => rows
              .where((row) =>
                  row['teacher_id'] == teacherId &&
                  (row['status'] as String? ?? '') == 'published')
              .map((row) => TeacherStrategy.fromMap(row))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        );
  }

  Stream<List<TeacherProfile>> watchPublicProfiles() {
    return SupabaseBootstrap.client
        .from('teacher_profiles')
        .stream(primaryKey: ['user_id'])
        .map(
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
    final rows = await SupabaseBootstrap.client
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
    if (teacherId.isEmpty || userId.isEmpty) {
      return Stream.value(false);
    }
    // Realtime 只支持单列 eq，按 teacher_id 订阅后在本端再按 user_id 过滤
    return SupabaseBootstrap.client
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
    if (teacherId.isEmpty) {
      return Stream.value(0);
    }
    return SupabaseBootstrap.client
        .from('teacher_follows')
        .stream(primaryKey: ['id'])
        .map(
          (rows) => rows
              .where((row) => row['teacher_id'] == teacherId)
              .length,
        );
  }

  /// 关注交易员。若已关注过（重复插入）则静默视为成功，不抛错。
  Future<void> followTeacher({
    required String teacherId,
    required String userId,
  }) async {
    if (teacherId.isEmpty || userId.isEmpty) {
      return;
    }
    try {
      await SupabaseBootstrap.client.from('teacher_follows').insert({
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
    if (teacherId.isEmpty || userId.isEmpty) {
      return;
    }
    await SupabaseBootstrap.client
        .from('teacher_follows')
        .delete()
        .eq('teacher_id', teacherId)
        .eq('user_id', userId);
  }

  /// 当前用户关注的交易员 ID 列表（按关注时间倒序，最近关注的在前）
  Future<List<String>> getFollowedTeacherIds(String userId) async {
    if (userId.isEmpty || !SupabaseBootstrap.isReady) {
      return [];
    }
    final rows = await SupabaseBootstrap.client
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
    if (!SupabaseBootstrap.isReady) {
      return null;
    }
    final rows = await SupabaseBootstrap.client
        .from('teacher_profiles')
        .select()
        .eq('status', 'approved')
        .order('pnl_month', ascending: false)
        .limit(1);
    if (rows == null || rows is! List || rows.isEmpty) {
      return null;
    }
    return TeacherProfile.fromMap(rows.first as Map<String, dynamic>);
  }

  /// 上传策略配图，返回公开 URL
  Future<String> uploadStrategyImage({
    required String teacherId,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final safeName = fileName.replaceAll(' ', '_');
    final path =
        'strategies/$teacherId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await SupabaseBootstrap.client.storage.from(_recordBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
          ),
        );
    return SupabaseBootstrap.client.storage.from(_recordBucket).getPublicUrl(path);
  }

  Future<void> addStrategy({
    required String teacherId,
    required String title,
    required String summary,
    required String content,
    List<String> imageUrls = const [],
  }) async {
    await SupabaseBootstrap.client.from('trade_strategies').insert({
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
    await SupabaseBootstrap.client
        .from('trade_strategies')
        .update({
          'status': status,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', strategyId);
  }

  Stream<List<TradeRecord>> watchTradeRecords(String teacherId) {
    return SupabaseBootstrap.client
        .from('trade_records')
        .stream(primaryKey: ['id'])
        .map(
          (rows) => rows
              .where((row) => row['teacher_id'] == teacherId)
              .map((row) => TradeRecord.fromMap(row))
              .toList()
            ..sort((a, b) {
              final aTime = a.sellTime ?? a.tradeTime ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bTime = b.sellTime ?? b.tradeTime ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bTime.compareTo(aTime);
            }),
        );
  }

  Stream<List<TeacherPosition>> watchPositions(String teacherId) {
    return SupabaseBootstrap.client
        .from('teacher_positions')
        .stream(primaryKey: ['id'])
        .map(
          (rows) => rows
              .where((row) => row['teacher_id'] == teacherId && (row['is_history'] as bool? ?? false) == false)
              .map((row) => TeacherPosition.fromMap(row))
              .toList(),
        );
  }

  /// 历史持仓（is_history = true），供关注页实时同步
  Stream<List<TeacherPosition>> watchHistoryPositions(String teacherId) {
    return SupabaseBootstrap.client
        .from('teacher_positions')
        .stream(primaryKey: ['id'])
        .map(
          (rows) => rows
              .where((row) => row['teacher_id'] == teacherId && (row['is_history'] as bool? ?? false) == true)
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
    final pnlAmount = (sellPrice - buyPrice) * sellQty;
    await SupabaseBootstrap.client.from('trade_records').insert({
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
    await SupabaseBootstrap.client.from('trade_records').insert(payload);
    if (attachmentUrl != null && attachmentUrl.isNotEmpty) {
      await SupabaseBootstrap.client.from('trade_record_files').insert({
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
    final safeName = fileName.replaceAll(' ', '_');
    final path =
        'records/$teacherId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await SupabaseBootstrap.client.storage.from(_recordBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
          ),
        );
    return SupabaseBootstrap.client.storage.from(_recordBucket).getPublicUrl(path);
  }

  Future<String> uploadTeacherAvatar({
    required String teacherId,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final safeName = fileName.replaceAll(' ', '_');
    final path =
        'teachers/$teacherId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await SupabaseBootstrap.client.storage.from(_avatarBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
          ),
        );
    return SupabaseBootstrap.client.storage.from(_avatarBucket).getPublicUrl(path);
  }

  Future<String> uploadTeacherVerification({
    required String teacherId,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
    required String category,
  }) async {
    final safeName = fileName.replaceAll(' ', '_');
    final path =
        'teachers/$teacherId/$category/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await SupabaseBootstrap.client.storage.from(_verifyBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
          ),
        );
    return SupabaseBootstrap.client.storage.from(_verifyBucket).getPublicUrl(path);
  }
}
