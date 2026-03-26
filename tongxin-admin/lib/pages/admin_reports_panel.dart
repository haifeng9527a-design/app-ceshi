import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../l10n/admin_strings.dart';
import '../repo/report_repository.dart' as report_repo;

class AdminReportsPanel extends StatefulWidget {
  const AdminReportsPanel({super.key});

  @override
  State<AdminReportsPanel> createState() => _AdminReportsPanelState();
}

class _AdminReportsPanelState extends State<AdminReportsPanel> {
  final _reportRepo = report_repo.ReportRepository();
  List<Map<String, dynamic>> _reports = [];
  Map<int, List<Map<String, dynamic>>> _appealsByReportId = {};
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
      final reportIds = list
          .map((e) => (e['id'] as num?)?.toInt())
          .whereType<int>()
          .toList(growable: false);
      final appealsByReportId = await _reportRepo.fetchAppealsByReportIds(reportIds);
      final ids = <String>{};
      for (final r in list) {
        final rid = r['reporter_id']?.toString();
        final ruid = r['reported_user_id']?.toString();
        if (rid != null && rid.isNotEmpty) ids.add(rid);
        if (ruid != null && ruid.isNotEmpty) ids.add(ruid);
      }
      final names = <String, String>{};
      if (ids.isNotEmpty) {
        final profileMap = await _reportRepo.fetchUserProfilesBatch(ids.toList());
        for (final uid in ids) {
          final m = profileMap[uid] ?? const <String, dynamic>{};
          final dn = m['display_name']?.toString().trim();
          final email = m['email']?.toString().trim();
          final sid = m['short_id']?.toString();
          names[uid] = dn?.isNotEmpty == true ? dn! : (email?.isNotEmpty == true ? email! : (sid ?? uid));
        }
      }
      if (!mounted) return;
      setState(() {
        _reports = list;
        _appealsByReportId = appealsByReportId;
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

  Future<void> _resolveReport(
    Map<String, dynamic> report,
    _ResolveFormData form,
  ) async {
    try {
      final reportId = report['id'] as int;
      final reportedUserId = report['reported_user_id']?.toString() ?? '';
      final payload = report_repo.ReportActionPayload(
        freeze: form.freeze,
        ban: form.ban,
        restrictSendMessage: form.restrictSendMessage,
        restrictAddFriend: form.restrictAddFriend,
        restrictJoinGroup: form.restrictJoinGroup,
        restrictCreateGroup: form.restrictCreateGroup,
        durationDays: form.durationDays,
      );
      await _reportRepo.resolveReport(
        reportId: reportId,
        reportedUserId: reportedUserId,
        status: form.status,
        adminNotes: form.notes?.trim().isEmpty == true ? null : form.notes?.trim(),
        reviewedBy: _getReviewedBy(),
        actions: payload,
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

  Future<void> _resolveAppeal(
    Map<String, dynamic> appeal, {
    required bool approved,
  }) async {
    final notesCtl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(approved ? '通过申诉' : '驳回申诉'),
          content: TextField(
            controller: notesCtl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '处理备注（可选）',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AdminStrings.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(approved ? '确认通过' : '确认驳回'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      final appealId = (appeal['id'] as num?)?.toInt();
      final appellantId = appeal['appellant_id']?.toString();
      if (appealId == null || appellantId == null || appellantId.isEmpty) return;
      await _reportRepo.resolveAppeal(
        appealId: appealId,
        appellantId: appellantId,
        status: approved ? 'approved' : 'rejected',
        reviewedBy: _getReviewedBy(),
        adminNotes: notesCtl.text.trim().isEmpty ? null : notesCtl.text.trim(),
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
    } finally {
      notesCtl.dispose();
    }
  }

  String _reviewTrail(Map<String, dynamic> r) {
    final by = r['reviewed_by']?.toString().trim();
    final atRaw = r['reviewed_at']?.toString();
    if ((by == null || by.isEmpty) && (atRaw == null || atRaw.isEmpty)) {
      return '未处理';
    }
    final at = atRaw != null ? DateTime.tryParse(atRaw) : null;
    final ds = at == null
        ? (atRaw ?? '—')
        : '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return '${by ?? '管理员'} · $ds';
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
    if (urls is String) {
      final raw = urls.trim();
      if (raw.isEmpty) return [];
      // 兼容 Postgres text[] 形态：{"a","b"} 或 {a,b}
      if (raw.startsWith('{') && raw.endsWith('}')) {
        final body = raw.substring(1, raw.length - 1).trim();
        if (body.isEmpty) return [];
        return body
            .split(',')
            .map((e) => e.trim().replaceAll('"', ''))
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return [raw];
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
                reviewTrail: _reviewTrail(r),
                screenshotUrls: _screenshotUrls(r['screenshot_urls']),
                appeals: _appealsByReportId[(r['id'] as num?)?.toInt() ?? -1] ?? const [],
                onResolve: () => _showResolveDialog(r),
                onResolveAppeal: (appeal, approved) => _resolveAppeal(appeal, approved: approved),
              )),
      ],
    );
  }

  Future<void> _showResolveDialog(Map<String, dynamic> report) async {
    final result = await showDialog<_ResolveFormData>(
      context: context,
      builder: (ctx) => _ResolveReportDialog(report: report),
    );
    if (result != null) {
      await _resolveReport(report, result);
    }
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.reporterLabel,
    required this.reportedLabel,
    required this.reasonLabel,
    required this.statusLabel,
    required this.reviewTrail,
    required this.screenshotUrls,
    required this.appeals,
    required this.onResolve,
    required this.onResolveAppeal,
  });

  final Map<String, dynamic> report;
  final String reporterLabel;
  final String reportedLabel;
  final String reasonLabel;
  final String statusLabel;
  final String reviewTrail;
  final List<String> screenshotUrls;
  final List<Map<String, dynamic>> appeals;
  final VoidCallback onResolve;
  final Future<void> Function(Map<String, dynamic> appeal, bool approved) onResolveAppeal;

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
            _row('处理记录', reviewTrail),
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
            if (appeals.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('申诉记录', style: const TextStyle(color: _accent, fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 8),
              ...appeals.map((a) {
                final appealStatus = a['status']?.toString() ?? 'pending';
                final appealContent = a['appeal_content']?.toString().trim();
                final appealBy = a['appellant_id']?.toString() ?? '—';
                final appealAt = a['created_at']?.toString() ?? '';
                final reviewBy = a['reviewed_by']?.toString();
                final reviewAt = a['reviewed_at']?.toString();
                final appealNotes = a['admin_notes']?.toString().trim();
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('状态：$appealStatus  ·  申诉人：$appealBy'),
                      if (appealAt.isNotEmpty) Text('提交时间：$appealAt', style: Theme.of(context).textTheme.bodySmall),
                      if (appealContent != null && appealContent.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        SelectableText(appealContent),
                      ],
                      if (appealNotes != null && appealNotes.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('处理备注：$appealNotes', style: Theme.of(context).textTheme.bodySmall),
                      ],
                      if ((reviewBy != null && reviewBy.isNotEmpty) || (reviewAt != null && reviewAt.isNotEmpty))
                        Text(
                          '处理人：${reviewBy ?? '—'}  ${reviewAt ?? ''}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (appealStatus == 'pending') ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            FilledButton(
                              onPressed: () => onResolveAppeal(a, true),
                              style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                              child: const Text('通过申诉并恢复限制'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: () => onResolveAppeal(a, false),
                              child: const Text('驳回申诉'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ],
            if (status == 'pending') ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  FilledButton(
                    onPressed: onResolve,
                    style: FilledButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.black),
                    child: const Text('处理工单'),
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

class _ResolveFormData {
  const _ResolveFormData({
    required this.status,
    required this.freeze,
    required this.ban,
    required this.restrictSendMessage,
    required this.restrictAddFriend,
    required this.restrictJoinGroup,
    required this.restrictCreateGroup,
    required this.durationDays,
    this.notes,
  });

  final String status;
  final bool freeze;
  final bool ban;
  final bool restrictSendMessage;
  final bool restrictAddFriend;
  final bool restrictJoinGroup;
  final bool restrictCreateGroup;
  final int durationDays;
  final String? notes;
}

class _ResolveReportDialog extends StatefulWidget {
  const _ResolveReportDialog({required this.report});
  final Map<String, dynamic> report;

  @override
  State<_ResolveReportDialog> createState() => _ResolveReportDialogState();
}

class _ResolveReportDialogState extends State<_ResolveReportDialog> {
  final _notesController = TextEditingController();
  String _status = 'approved';
  bool _freeze = true;
  bool _ban = false;
  bool _restrictSendMessage = true;
  bool _restrictAddFriend = true;
  bool _restrictJoinGroup = false;
  bool _restrictCreateGroup = false;
  int _durationDays = 30;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('举报处理'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('审核结论'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('通过并处罚'),
                    selected: _status == 'approved',
                    onSelected: (_) => setState(() => _status = 'approved'),
                  ),
                  ChoiceChip(
                    label: const Text('驳回'),
                    selected: _status == 'rejected',
                    onSelected: (_) => setState(() => _status = 'rejected'),
                  ),
                ],
              ),
              if (_status == 'approved') ...[
                const SizedBox(height: 16),
                const Text('处罚动作（可多选）'),
                const SizedBox(height: 8),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('冻结账号'),
                  value: _freeze,
                  onChanged: (v) => setState(() => _freeze = v ?? false),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('封禁账号'),
                  value: _ban,
                  onChanged: (v) => setState(() => _ban = v ?? false),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('停止发消息'),
                  value: _restrictSendMessage,
                  onChanged: (v) => setState(() => _restrictSendMessage = v ?? false),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('停止加好友'),
                  value: _restrictAddFriend,
                  onChanged: (v) => setState(() => _restrictAddFriend = v ?? false),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('停止加群'),
                  value: _restrictJoinGroup,
                  onChanged: (v) => setState(() => _restrictJoinGroup = v ?? false),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('停止建群'),
                  value: _restrictCreateGroup,
                  onChanged: (v) => setState(() => _restrictCreateGroup = v ?? false),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('时长'),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _durationDays,
                      items: const [
                        DropdownMenuItem(value: 7, child: Text('7天')),
                        DropdownMenuItem(value: 30, child: Text('30天')),
                        DropdownMenuItem(value: 90, child: Text('90天')),
                        DropdownMenuItem(value: 0, child: Text('永久')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _durationDays = v);
                      },
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '处理备注',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AdminStrings.commonCancel),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              _ResolveFormData(
                status: _status,
                freeze: _status == 'approved' ? _freeze : false,
                ban: _status == 'approved' ? _ban : false,
                restrictSendMessage: _status == 'approved' ? _restrictSendMessage : false,
                restrictAddFriend: _status == 'approved' ? _restrictAddFriend : false,
                restrictJoinGroup: _status == 'approved' ? _restrictJoinGroup : false,
                restrictCreateGroup: _status == 'approved' ? _restrictCreateGroup : false,
                durationDays: _durationDays,
                notes: _notesController.text,
              ),
            );
          },
          child: const Text('确认处理'),
        ),
      ],
    );
  }
}
