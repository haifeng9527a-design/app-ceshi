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
    if (!_api.isAvailable) {
      throw StateError('API 不可用，无法上传截图');
    }
    if (contentBase64List.isEmpty || contentBase64List.length > 5) {
      throw StateError('截图数量需为 1-5 张');
    }
    final items = contentBase64List.asMap().entries.map((e) {
      final i = e.key;
      return {
        'content_base64': e.value,
        if (contentTypes != null && i < contentTypes.length) 'content_type': contentTypes[i],
        if (fileNames != null && i < fileNames.length) 'file_name': fileNames[i],
      };
    }).toList();
    final resp = await _api.post('api/upload/report-screenshots', body: {'items': items});
    if (resp.statusCode != 200) {
      throw StateError('截图上传失败(${resp.statusCode})：${resp.body}');
    }
    try {
      final json = jsonDecode(resp.body) as Map?;
      final list = json?['urls'] as List? ?? [];
      final urls = list.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      if (urls.isEmpty) {
        throw StateError('截图上传失败：服务端未返回可用图片地址');
      }
      return urls;
    } catch (e) {
      throw StateError('截图上传响应解析失败：$e');
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
    if (!_api.isAvailable) {
      throw StateError('API 不可用，无法更新举报状态');
    }
    final resp = await _api.patch('api/reports/$reportId', body: {
      'status': status,
      if (adminNotes != null) 'admin_notes': adminNotes,
    });
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw StateError('更新举报状态失败(${resp.statusCode})：${resp.body}');
    }
  }

  /// 提交举报
  Future<void> submitReport({
    required String reporterId,
    required String reportedUserId,
    required String reason,
    String? content,
    List<String> screenshotUrls = const [],
  }) async {
    if (!_api.isAvailable) {
      throw StateError('API 不可用，无法提交举报');
    }
    final resp = await _api.post('api/reports', body: {
      'reported_user_id': reportedUserId,
      'reason': reason,
      if (content != null && content.trim().isNotEmpty) 'content': content.trim(),
      'screenshot_urls': screenshotUrls,
    });
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw StateError('提交举报失败(${resp.statusCode})：${resp.body}');
    }
  }
}
