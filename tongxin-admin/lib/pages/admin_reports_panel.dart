import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../core/supabase_bootstrap.dart';
import '../l10n/admin_strings.dart';
import '../repo/report_repository.dart';

class AdminReportsPanel extends StatefulWidget {
  const AdminReportsPanel({super.key});

  @override
  State<AdminReportsPanel> createState() => _AdminReportsPanelState();
}

class _AdminReportsPanelState extends State<AdminReportsPanel> {
  final _reportRepo = ReportRepository();
  List<Map<String, dynamic>> _reports = [];
  Map<String, String> _userNames = {};
  bool _loading = true;
  String? _loadError;
  String _statusFilter = 'all';

  static const Color _accent = Color(0xFFD4AF37);

  String _getReviewedBy() {
    final v = dotenv.env['ADMIN_USERNAME'];
    return (v != null && v.trim().isNotEmpty) ? v.trim() : 'admin';
  }

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final filter = _statusFilter == 'all' ? null : _statusFilter;
      final list = await _reportRepo.fetchReports(statusFilter: filter);
      final ids = <String>{};
      for (final r in list) {
        final rid = r['reporter_id']?.toString();
        final ruid = r['reported_user_id']?.toString();
        if (rid != null && rid.isNotEmpty) ids.add(rid);
        if (ruid != null && ruid.isNotEmpty) ids.add(ruid);
      }
      final names = <String, String>{};
      if (ids.isNotEmpty) {
        final res = await SupabaseBootstrap.client
            .from('user_profiles')
            .select('user_id, display_name, email, short_id')
            .inFilter('user_id', ids.toList());
        for (final row in (res as List<dynamic>)) {
          final m = row as Map<String, dynamic>;
          final uid = m['user_id']?.toString();
          if (uid == null) continue;
          final dn = m['display_name']?.toString().trim();
          final email = m['email']?.toString().trim();
          final sid = m['short_id']?.toString();
          names[uid] = dn?.isNotEmpty == true
              ? dn!
              : (email?.isNotEmpty == true ? email! : (sid ?? uid));
        }
      }
      if (!mounted) return;
      setState(() {
        _reports = list;
        _userNames = names;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('AdminReportsPanel _loadReports: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _updateStatus(int reportId, String status, {String? notes}) async {
    try {
      await _reportRepo.updateReportStatus(
        reportId: reportId,
        status: status,
        adminNotes: notes,
        reviewedBy: _getReviewedBy(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AdminStrings.adminSaved)),
      );
      _loadReports();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AdminStrings.adminSaveFailed(e.toString()))),
      );
    }
  }

  String _userLabel(String? userId) {
    if (userId == null || userId.isEmpty) return '—';
    return _userNames[userId] ?? userId;
  }

  String _reasonLabel(String? reason) {
    switch (reason) {
      case 'harassment': return AdminStrings.reportReasonHarassment;
      case 'spam': return AdminStrings.reportReasonSpam;
      case 'fraud': return AdminStrings.reportReasonFraud;
      case 'inappropriate': return AdminStrings.reportReasonInappropriate;
      case 'other': return AdminStrings.reportReasonOther;
      default: return reason ?? '—';
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'pending': return AdminStrings.adminPending;
      case 'approved': return AdminStrings.adminApproved;
      case 'rejected': return AdminStrings.adminRejected;
      default: return status ?? '—';
    }
  }

  List<String> _screenshotUrls(dynamic urls) {
    if (urls == null) return [];
    if (urls is List) {
      return urls.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          AdminStrings.adminReports,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: _accent,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          AdminStrings.adminReportsDesc,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(AdminStrings.adminFilterByStatusReports, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: _statusFilter,
              items: [
                DropdownMenuItem(value: 'all', child: Text(AdminStrings.adminAll)),
                DropdownMenuItem(value: 'pending', child: Text(AdminStrings.adminPending)),
                DropdownMenuItem(value: 'approved', child: Text(AdminStrings.adminApproved)),
                DropdownMenuItem(value: 'rejected', child: Text(AdminStrings.adminRejected)),
              ],
              onChanged: (v) {
                if (v != null) setState(() { _statusFilter = v; _loadReports(); });
              },
            ),
            const SizedBox(width: 16),
            TextButton.icon(
              onPressed: _loading ? null : _loadReports,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(AdminStrings.adminRefresh),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
        else if (_loadError != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_loadError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          )
        else if (_reports.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(AdminStrings.adminReportNoData, style: Theme.of(context).textTheme.bodyLarge),
            ),
          )
        else
          ..._reports.map((r) => _ReportCard(
                report: r,
                reporterLabel: _userLabel(r['reporter_id']?.toString()),
                reportedLabel: _userLabel(r['reported_user_id']?.toString()),
                reasonLabel: _reasonLabel(r['reason']?.toString()),
                statusLabel: _statusLabel(r['status']?.toString()),
                screenshotUrls: _screenshotUrls(r['screenshot_urls']),
                onApprove: () => _updateStatus(r['id'] as int, 'approved'),
                onReject: () => _showRejectDialog(r['id'] as int),
              )),
      ],
    );
  }

  Future<void> _showRejectDialog(int reportId) async {
    final notes = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: Text(AdminStrings.adminReject),
          content: TextField(
            controller: c,
            decoration: InputDecoration(
              labelText: AdminStrings.adminReportNotes,
              hintText: AdminStrings.adminReportNotes,
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AdminStrings.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: Text(AdminStrings.adminReject),
            ),
          ],
        );
      },
    );
    if (notes != null) await _updateStatus(reportId, 'rejected', notes: notes.isEmpty ? null : notes);
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.reporterLabel,
    required this.reportedLabel,
    required this.reasonLabel,
    required this.statusLabel,
    required this.screenshotUrls,
    required this.onApprove,
    required this.onReject,
  });

  final Map<String, dynamic> report;
  final String reporterLabel;
  final String reportedLabel;
  final String reasonLabel;
  final String statusLabel;
  final List<String> screenshotUrls;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  static const Color _accent = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final status = report['status']?.toString() ?? 'pending';
    final content = report['content']?.toString().trim();
    final adminNotes = report['admin_notes']?.toString().trim();
    final createdAt = report['created_at'] != null
        ? DateTime.tryParse(report['created_at'].toString())
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(statusLabel),
                  backgroundColor: status == 'pending'
                      ? Colors.orange.withOpacity(0.2)
                      : status == 'approved'
                          ? Colors.green.withOpacity(0.2)
                          : Colors.red.withOpacity(0.2),
                ),
                const SizedBox(width: 12),
                if (createdAt != null)
                  Text(
                    createdAt.toIso8601String().split('T').first,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _row(AdminStrings.adminReportReporter, reporterLabel),
            _row(AdminStrings.adminReportReported, reportedLabel),
            _row(AdminStrings.reportReason, reasonLabel),
            if (content != null && content.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(AdminStrings.reportContent, style: const TextStyle(color: _accent, fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 4),
              SelectableText(content, style: Theme.of(context).textTheme.bodyMedium),
            ],
            if (adminNotes != null && adminNotes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(AdminStrings.adminReportNotes, style: const TextStyle(color: _accent, fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 4),
              SelectableText(adminNotes, style: Theme.of(context).textTheme.bodySmall),
            ],
            if (screenshotUrls.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(AdminStrings.reportScreenshots, style: const TextStyle(color: _accent, fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: screenshotUrls.map((url) => GestureDetector(
                  onTap: () => _showImage(context, url),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: url,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => const SizedBox(width: 80, height: 80, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                      errorWidget: (_, __, ___) => const SizedBox(width: 80, height: 80, child: Icon(Icons.broken_image)),
                    ),
                  ),
                )).toList(),
              ),
            ],
            if (status == 'pending') ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  FilledButton(
                    onPressed: onApprove,
                    style: FilledButton.styleFrom(backgroundColor: Colors.green),
                    child: Text(AdminStrings.adminApprove),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    child: Text(AdminStrings.adminReject),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Color(0xFF6C6F77), fontSize: 13))),
          Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  void _showImage(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: InteractiveViewer(
          child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
