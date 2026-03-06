import 'dart:convert';
import 'dart:io';

import '../../api/report_api.dart';
import '../../core/api_client.dart';

enum ReportReason {
  harassment('harassment'),
  spam('spam'),
  fraud('fraud'),
  inappropriate('inappropriate'),
  other('other');

  const ReportReason(this.value);
  final String value;
}

class ReportRepository {
  ReportRepository();

  bool get _useApi => ApiClient.instance.isAvailable;

  static const int _maxScreenshots = 5;

  Future<List<String>> uploadScreenshots({
    required String reporterId,
    required List<File> files,
  }) async {
    if (files.isEmpty || files.length > _maxScreenshots || !_useApi) return [];
    final base64List = <String>[];
    final types = <String>[];
    final names = <String>[];
    for (final f in files) {
      final bytes = await f.readAsBytes();
      base64List.add(base64Encode(bytes));
      final ext = f.path.split('.').last.toLowerCase();
      final safeExt = ['jpg', 'jpeg', 'png', 'webp'].contains(ext) ? ext : 'jpg';
      types.add(_contentType(safeExt));
      names.add(f.path.split('/').last);
    }
    return ReportApi.instance.uploadScreenshots(
      contentBase64List: base64List,
      contentTypes: types,
      fileNames: names,
    );
  }

  String _contentType(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  Future<void> submitReport({
    required String reporterId,
    required String reportedUserId,
    required String reason,
    String? content,
    List<String> screenshotUrls = const [],
  }) async {
    if (!_useApi) {
      throw StateError('API 不可用，无法提交举报');
    }
    await ReportApi.instance.submitReport(
      reporterId: reporterId,
      reportedUserId: reportedUserId,
      reason: reason,
      content: content,
      screenshotUrls: screenshotUrls,
    );
  }

  Future<List<Map<String, dynamic>>> fetchReports({String? statusFilter}) async {
    if (!_useApi) return [];
    return ReportApi.instance.fetchReports(statusFilter: statusFilter);
  }

  Future<void> updateReportStatus({
    required int reportId,
    required String status,
    String? adminNotes,
    required String reviewedBy,
  }) async {
    if (!_useApi) {
      throw StateError('API 不可用，无法更新举报状态');
    }
    await ReportApi.instance.updateReportStatus(
      reportId: reportId,
      status: status,
      adminNotes: adminNotes,
      reviewedBy: reviewedBy,
    );
  }
}
