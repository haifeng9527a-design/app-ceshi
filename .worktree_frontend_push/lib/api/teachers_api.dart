import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../features/teachers/teacher_models.dart';

/// 交易员相关 API
class TeachersApi {
  TeachersApi._();
  static final TeachersApi instance = TeachersApi._();
  final _api = ApiClient.instance;

  /// GET /api/teachers — 交易员列表（已通过，非 blocked）
  Future<List<TeacherProfile>> getTeachers() async {
    if (!_api.isAvailable) return [];
    final resp = await _api.get('api/teachers');
    if (resp.statusCode != 200) return [];
    try {
      final list = jsonDecode(resp.body) as List? ?? [];
      return list.map((e) => TeacherProfile.fromMap(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  /// GET /api/teachers/rankings
  Future<List<TeacherProfile>> getRankings() async {
    if (!_api.isAvailable) return [];
    final resp = await _api.get('api/teachers/rankings');
    if (resp.statusCode != 200) return [];
    try {
      final list = jsonDecode(resp.body) as List? ?? [];
      return list.map((e) => TeacherProfile.fromMap(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  /// 轮询排行榜流
  Stream<List<TeacherProfile>> watchRankings({Duration interval = const Duration(seconds: 10)}) async* {
    while (true) {
      yield await getRankings();
      await Future<void>.delayed(interval);
    }
  }

  /// GET /api/teachers/rank-one
  Future<TeacherProfile?> getRankOne() async {
    if (!_api.isAvailable) return null;
    final resp = await _api.get('api/teachers/rank-one');
    if (resp.statusCode != 200) return null;
    try {
      final json = jsonDecode(resp.body);
      if (json == null) return null;
      return TeacherProfile.fromMap(Map<String, dynamic>.from(json as Map));
    } catch (_) {
      return null;
    }
  }

  /// GET /api/teachers/:userId
  Future<TeacherProfile?> getProfile(String userId) async {
    if (!_api.isAvailable) return null;
    final resp = await _api.get('api/teachers/$userId');
    if (resp.statusCode != 200) return null;
    try {
      final json = jsonDecode(resp.body);
      if (json == null) return null;
      return TeacherProfile.fromMap(Map<String, dynamic>.from(json as Map));
    } catch (_) {
      return null;
    }
  }

  /// GET /api/teachers/:userId/strategies
  Future<List<TeacherStrategy>> getStrategies(String teacherId) async {
    if (!_api.isAvailable) return [];
    final resp = await _api.get('api/teachers/$teacherId/strategies');
    if (resp.statusCode != 200) {
      if (kDebugMode) debugPrint('[TeachersApi] GET strategies => ${resp.statusCode} ${resp.body}');
      return [];
    }
    try {
      final list = jsonDecode(resp.body) as List? ?? [];
      return list.map((e) => TeacherStrategy.fromMap(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  /// GET /api/teachers/:userId/follow-status
  Future<bool> getFollowStatus(String teacherId, String userId) async {
    if (!_api.isAvailable) return false;
    final resp = await _api.get('api/teachers/$teacherId/follow-status');
    if (resp.statusCode != 200) return false;
    try {
      final json = jsonDecode(resp.body) as Map?;
      return json?['is_following'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  /// POST /api/teachers/:userId/follow
  Future<void> follow(String teacherId, String userId) async {
    if (!_api.isAvailable) return;
    await _api.post('api/teachers/$teacherId/follow');
  }

  /// DELETE /api/teachers/:userId/follow
  Future<void> unfollow(String teacherId, String userId) async {
    if (!_api.isAvailable) return;
    await _api.delete('api/teachers/$teacherId/follow');
  }

  /// GET /api/teachers/:userId/follower-count
  Future<int> getFollowerCount(String teacherId) async {
    if (!_api.isAvailable) return 0;
    final resp = await _api.get('api/teachers/$teacherId/follower-count');
    if (resp.statusCode != 200) return 0;
    try {
      final json = jsonDecode(resp.body) as Map?;
      return json?['count'] as int? ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// GET /api/users/me/followed-teachers
  Future<List<String>> getFollowedTeacherIds(String userId) async {
    if (!_api.isAvailable) return [];
    final resp = await _api.get('api/users/me/followed-teachers');
    if (resp.statusCode != 200) return [];
    try {
      final list = jsonDecode(resp.body) as List? ?? [];
      return list.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  /// POST /api/teachers/:userId/comments
  Future<String?> insertComment({
    required String teacherId,
    required String content,
    String? strategyId,
    String? replyToCommentId,
    String? replyToContent,
  }) async {
    if (!_api.isAvailable) return null;
    final body = <String, dynamic>{
      'content': content,
      if (strategyId != null && strategyId.isNotEmpty) 'strategy_id': strategyId,
      if (replyToCommentId != null && replyToCommentId.isNotEmpty) 'reply_to_comment_id': replyToCommentId,
      if (replyToContent != null && replyToContent.isNotEmpty) 'reply_to_content': replyToContent.length > 50 ? '${replyToContent.substring(0, 50)}…' : replyToContent,
    };
    final resp = await _api.post('api/teachers/$teacherId/comments', body: body);
    if (resp.statusCode != 200) return null;
    try {
      final json = jsonDecode(resp.body) as Map?;
      return json?['user_name'] as String? ?? '用户';
    } catch (_) {
      return '用户';
    }
  }

  /// GET /api/teachers/:userId/comments
  Future<List<Map<String, dynamic>>> getComments(String teacherId, {String? strategyId}) async {
    if (!_api.isAvailable) return [];
    var url = 'api/teachers/$teacherId/comments';
    if (strategyId != null && strategyId.isNotEmpty) {
      url += '?strategy_id=$strategyId';
    }
    final resp = await _api.get(url);
    if (resp.statusCode != 200) return [];
    try {
      final list = jsonDecode(resp.body) as List? ?? [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> upsertMyProfile(Map<String, dynamic> payload) async {
    if (!_api.isAvailable) return;
    await _api.put('api/teachers/me/profile', body: payload);
  }

  Future<int> getLikeCount(String teacherId) async {
    if (!_api.isAvailable) return 0;
    final resp = await _api.get('api/teachers/$teacherId/likes/count');
    if (resp.statusCode != 200) return 0;
    try {
      final json = jsonDecode(resp.body) as Map?;
      return (json?['count'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<bool> getMyLikeStatus(String teacherId) async {
    if (!_api.isAvailable) return false;
    final resp = await _api.get('api/teachers/$teacherId/likes/me');
    if (resp.statusCode != 200) return false;
    try {
      final json = jsonDecode(resp.body) as Map?;
      return json?['liked'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> toggleLike(String teacherId) async {
    if (!_api.isAvailable) return false;
    final resp = await _api.post('api/teachers/$teacherId/likes/toggle');
    if (resp.statusCode != 200) return false;
    try {
      final json = jsonDecode(resp.body) as Map?;
      return json?['liked'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> addStrategy({
    required String title,
    required String summary,
    required String content,
    List<String> imageUrls = const [],
  }) async {
    if (!_api.isAvailable) return;
    await _api.post('api/teachers/me/strategies', body: {
      'title': title,
      'summary': summary,
      'content': content,
      'image_urls': imageUrls,
      'status': 'published',
    });
  }

  Future<void> updateStrategyStatus({
    required String strategyId,
    required String status,
  }) async {
    if (!_api.isAvailable) return;
    await _api.patch('api/teachers/strategies/$strategyId/status', body: {
      'status': status,
    });
  }

  Future<List<TradeRecord>> getTradeRecords(String teacherId) async {
    if (!_api.isAvailable) return [];
    final resp = await _api.get('api/teachers/$teacherId/trade-records');
    if (resp.statusCode != 200) return [];
    try {
      final list = jsonDecode(resp.body) as List? ?? [];
      return list
          .map((e) => TradeRecord.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<TeacherPosition>> getPositions(
    String teacherId, {
    bool history = false,
  }) async {
    if (!_api.isAvailable) return [];
    final resp = await _api.get(
      'api/teachers/$teacherId/positions',
      queryParameters: {'history': history ? 'true' : 'false'},
    );
    if (resp.statusCode != 200) return [];
    try {
      final list = jsonDecode(resp.body) as List? ?? [];
      return list
          .map((e) => TeacherPosition.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addTradeRecord(Map<String, dynamic> payload) async {
    if (!_api.isAvailable) return;
    await _api.post('api/teachers/me/trade-records', body: payload);
  }

  Future<String?> uploadBase64(
    String path, {
    required List<int> bytes,
    required String fileName,
    required String contentType,
    String? category,
  }) async {
    if (!_api.isAvailable) return null;
    final resp = await _api.post(path, body: {
      'content_base64': base64Encode(bytes),
      'file_name': fileName,
      'content_type': contentType,
      if (category != null) 'category': category,
    });
    if (resp.statusCode != 200) return null;
    try {
      final json = jsonDecode(resp.body) as Map?;
      final url = json?['url']?.toString().trim();
      return url != null && url.isNotEmpty ? url : null;
    } catch (_) {
      return null;
    }
  }
}
