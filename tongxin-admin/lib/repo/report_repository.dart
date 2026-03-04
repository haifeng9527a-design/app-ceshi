import '../core/supabase_bootstrap.dart';

class ReportRepository {
  ReportRepository();

  final _client = SupabaseBootstrap.client;

  /// 管理员：获取举报列表
  Future<List<Map<String, dynamic>>> fetchReports({String? statusFilter}) async {
    var query = _client.from('user_reports').select();
    if (statusFilter != null &&
        statusFilter.isNotEmpty &&
        statusFilter != 'all') {
      query = query.eq('status', statusFilter);
    }
    final res = await query.order('created_at', ascending: false);
    return (res as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// 管理员：更新举报状态
  Future<void> updateReportStatus({
    required int reportId,
    required String status,
    String? adminNotes,
    required String reviewedBy,
  }) async {
    await _client.from('user_reports').update({
      'status': status,
      'admin_notes': adminNotes,
      'reviewed_at': DateTime.now().toIso8601String(),
      'reviewed_by': reviewedBy,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', reportId);
  }
}
