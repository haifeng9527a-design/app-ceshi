import 'dart:convert';

import '../core/admin_api_client.dart';

class ReportActionPayload {
  const ReportActionPayload({
    this.freeze = false,
    this.ban = false,
    this.restrictSendMessage = false,
    this.restrictAddFriend = false,
    this.restrictJoinGroup = false,
    this.restrictCreateGroup = false,
    this.durationDays = 30,
  });

  final bool freeze;
  final bool ban;
  final bool restrictSendMessage;
  final bool restrictAddFriend;
  final bool restrictJoinGroup;
  final bool restrictCreateGroup;
  final int durationDays;

  bool get hasAny =>
      freeze ||
      ban ||
      restrictSendMessage ||
      restrictAddFriend ||
      restrictJoinGroup ||
      restrictCreateGroup;
}

class ReportRepository {
  ReportRepository();

  final _api = AdminApiClient.instance;

  /// 管理员：获取举报列表
  Future<List<Map<String, dynamic>>> fetchReports({String? statusFilter}) async {
    var path = 'api/reports';
    if (statusFilter != null && statusFilter.isNotEmpty && statusFilter != 'all') {
      path = '$path?status=$statusFilter';
    }
    final resp = await _api.get(path);
    if (resp.statusCode != 200) {
      throw StateError('获取举报列表失败(${resp.statusCode})：${resp.body}');
    }
    final res = jsonDecode(resp.body) as List<dynamic>;
    return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// 管理员：更新举报状态
  Future<void> updateReportStatus({
    required int reportId,
    required String status,
    String? adminNotes,
    required String reviewedBy,
  }) async {
    final resp = await _api.patch('api/reports/$reportId', body: {
      'status': status,
      'admin_notes': adminNotes,
    });
    if (resp.statusCode != 200) {
      throw StateError('更新举报状态失败(${resp.statusCode})：${resp.body}');
    }
  }

  Future<void> resolveReport({
    required int reportId,
    required String reportedUserId,
    required String status,
    required String reviewedBy,
    String? adminNotes,
    ReportActionPayload? actions,
  }) async {
    final payload = actions ?? const ReportActionPayload();
    final resp = await _api.patch('api/reports/$reportId', body: {
      'status': status,
      'admin_notes': adminNotes,
      'reported_user_id': reportedUserId,
      'freeze': payload.freeze,
      'ban': payload.ban,
      'restrict_send_message': payload.restrictSendMessage,
      'restrict_add_friend': payload.restrictAddFriend,
      'restrict_join_group': payload.restrictJoinGroup,
      'restrict_create_group': payload.restrictCreateGroup,
      'duration_days': payload.durationDays,
    });
    if (resp.statusCode != 200) {
      throw StateError('处理举报失败(${resp.statusCode})：${resp.body}');
    }
  }

  Future<Map<int, List<Map<String, dynamic>>>> fetchAppealsByReportIds(
    List<int> reportIds,
  ) async {
    if (reportIds.isEmpty) return {};
    final out = <int, List<Map<String, dynamic>>>{};
    for (final rid in reportIds) {
      final resp = await _api.get('api/reports/$rid/appeals');
      if (resp.statusCode != 200) continue;
      final res = jsonDecode(resp.body) as List<dynamic>;
      out[rid] = res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return out;
  }

  Future<Map<String, Map<String, dynamic>>> fetchUserProfilesBatch(
    List<String> userIds,
  ) async {
    final ids = userIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList(growable: false);
    if (ids.isEmpty) return {};
    final resp = await _api.get('api/user-profiles/batch?ids=${ids.join(',')}');
    if (resp.statusCode != 200) {
      throw StateError('获取用户资料失败(${resp.statusCode})：${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final out = <String, Map<String, dynamic>>{};
    json.forEach((key, value) {
      if (value is Map) out[key] = Map<String, dynamic>.from(value);
    });
    return out;
  }

  Future<void> resolveAppeal({
    required int appealId,
    required String appellantId,
    required String status,
    required String reviewedBy,
    String? adminNotes,
    bool clearRestrictionsWhenApproved = true,
  }) async {
    final resp = await _api.patch('api/reports/appeals/$appealId', body: {
        'status': status,
        'admin_notes': adminNotes,
        'clear_restrictions': status == 'approved' && clearRestrictionsWhenApproved,
      });
    if (resp.statusCode != 200) {
      throw StateError('处理申诉失败(${resp.statusCode})：${resp.body}');
    }
  }
}
