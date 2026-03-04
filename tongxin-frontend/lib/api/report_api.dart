import 'dart:convert';

import '../core/api_client.dart';

/// 举报相关 API
class ReportApi {
  ReportApi._();
  static final ReportApi instance = ReportApi._();
  final _api = ApiClient.instance;

  /// 上传举报截图，返回 URL 列表
  Future<List<String>> uploadScreenshots({
    required List<String> contentBase64List,
    List<String>? contentTypes,
    List<String>? fileNames,
  }) async {
    if (!_api.isAvailable || contentBase64List.isEmpty || contentBase64List.length > 5) return [];
    final items = contentBase64List.asMap().entries.map((e) {
      final i = e.key;
      return {
        'content_base64': e.value,
        if (contentTypes != null && i < contentTypes.length) 'content_type': contentTypes[i],
        if (fileNames != null && i < fileNames.length) 'file_name': fileNames[i],
      };
    }).toList();
    final resp = await _api.post('api/upload/report-screenshots', body: {'items': items});
    if (resp.statusCode != 200) return [];
    try {
      final json = jsonDecode(resp.body) as Map?;
      final list = json?['urls'] as List? ?? [];
      return list.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  /// GET /api/reports — 管理员：举报列表
  Future<List<Map<String, dynamic>>> fetchReports({String? statusFilter}) async {
    if (!_api.isAvailable) return [];
    var url = 'api/reports';
    if (statusFilter != null && statusFilter.isNotEmpty && statusFilter != 'all') {
      url += '?status=$statusFilter';
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

  /// PATCH /api/reports/:id — 管理员：更新举报状态
  Future<void> updateReportStatus({
    required int reportId,
    required String status,
    String? adminNotes,
    required String reviewedBy,
  }) async {
    if (!_api.isAvailable) return;
    await _api.patch('api/reports/$reportId', body: {
      'status': status,
      if (adminNotes != null) 'admin_notes': adminNotes,
    });
  }

  /// 提交举报
  Future<void> submitReport({
    required String reporterId,
    required String reportedUserId,
    required String reason,
    String? content,
    List<String> screenshotUrls = const [],
  }) async {
    if (!_api.isAvailable) return;
    await _api.post('api/reports', body: {
      'reported_user_id': reportedUserId,
      'reason': reason,
      if (content != null && content.trim().isNotEmpty) 'content': content.trim(),
      'screenshot_urls': screenshotUrls,
    });
  }
}
