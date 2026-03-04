import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/supabase_bootstrap.dart';
import '../../l10n/app_localizations.dart';
import '../messages/friend_models.dart';
import '../messages/friends_repository.dart';
import 'report_repository.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key, this.initialReportedUser});

  /// 若从某用户详情页进入，可预填被举报用户
  final FriendProfile? initialReportedUser;

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final _searchController = TextEditingController();
  final _contentController = TextEditingController();
  final _friendsRepo = FriendsRepository();
  final _reportRepo = ReportRepository();
  final _picker = ImagePicker();

  FriendProfile? _reportedUser;
  bool _searching = false;
  ReportReason? _selectedReason;
  final List<File> _screenshots = [];
  bool _submitting = false;

  static const Color _accent = Color(0xFFD4AF37);

  @override
  void initState() {
    super.initState();
    _reportedUser = widget.initialReportedUser;
    if (_reportedUser != null) {
      _searchController.text = _reportedUser!.shortId ?? _reportedUser!.email;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _searchUser() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    try {
      FriendProfile? p;
      if (q.contains('@')) {
        p = await _friendsRepo.findByEmail(q);
      } else {
        p = await _friendsRepo.findByShortId(q);
      }
      if (!mounted) return;
      setState(() {
        _reportedUser = p;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _reportedUser = null;
        _searching = false;
      });
    }
  }

  Future<void> _pickScreenshots() async {
    if (_screenshots.length >= 5) return;
    final picked = await _picker.pickMultiImage();
    if (picked.isEmpty) return;
    final remaining = 5 - _screenshots.length;
    final toAdd = picked.take(remaining).map((x) => File(x.path)).toList();
    setState(() => _screenshots.addAll(toAdd));
  }

  void _removeScreenshot(int index) {
    setState(() => _screenshots.removeAt(index));
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.authPleaseLoginToManage)),
      );
      return;
    }
    if (_reportedUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.reportPleaseSelectUser)),
      );
      return;
    }
    if (_selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.reportPleaseSelectReason)),
      );
      return;
    }
    if (_reportedUser!.userId == uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('不能举报自己')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      List<String> urls = [];
      if (_screenshots.isNotEmpty) {
        urls = await _reportRepo.uploadScreenshots(
          reporterId: uid,
          files: _screenshots,
        );
      }
      await _reportRepo.submitReport(
        reporterId: uid,
        reportedUserId: _reportedUser!.userId,
        reason: _selectedReason!.value,
        content: _contentController.text.trim().isNotEmpty ? _contentController.text.trim() : null,
        screenshotUrls: urls,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.reportSuccess)),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.reportFailed}: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.reportPageTitle),
        backgroundColor: const Color(0xFF0B0C0E),
        foregroundColor: _accent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 被举报用户
          Text(l10n.reportTargetUser, style: const TextStyle(color: _accent, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: l10n.reportTargetUserHint,
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onSubmitted: (_) => _searchUser(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _searching ? null : _searchUser,
                style: FilledButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.black),
                child: _searching ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : Text(l10n.commonSearch),
              ),
            ],
          ),
          if (_reportedUser != null) ...[
            const SizedBox(height: 12),
            _UserChip(profile: _reportedUser!, onClear: () => setState(() => _reportedUser = null)),
          ],
          const SizedBox(height: 24),

          // 举报原因
          Text(l10n.reportReason, style: const TextStyle(color: _accent, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ReportReason.values.map((r) {
              final label = _reasonLabel(r, l10n);
              final selected = _selectedReason == r;
              return FilterChip(
                label: Text(label),
                selected: selected,
                onSelected: (v) => setState(() => _selectedReason = v ? r : null),
                selectedColor: _accent.withOpacity(0.3),
                checkmarkColor: _accent,
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // 详细说明
          Text(l10n.reportContent, style: const TextStyle(color: _accent, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _contentController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: l10n.reportContentHint,
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 24),

          // 截图
          Row(
            children: [
              Text(l10n.reportScreenshots, style: const TextStyle(color: _accent, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text(l10n.reportScreenshotsMax, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...List.generate(_screenshots.length, (i) => _ScreenshotThumb(file: _screenshots[i], onRemove: () => _removeScreenshot(i))),
              if (_screenshots.length < 5)
                GestureDetector(
                  onTap: _pickScreenshots,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _accent.withOpacity(0.5)),
                    ),
                    child: const Icon(Icons.add_photo_alternate_outlined, color: _accent, size: 32),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 32),

          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _submitting
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : Text(l10n.reportSubmit),
          ),
        ],
      ),
    );
  }

  String _reasonLabel(ReportReason r, AppLocalizations l10n) {
    switch (r) {
      case ReportReason.harassment:
        return l10n.reportReasonHarassment;
      case ReportReason.spam:
        return l10n.reportReasonSpam;
      case ReportReason.fraud:
        return l10n.reportReasonFraud;
      case ReportReason.inappropriate:
        return l10n.reportReasonInappropriate;
      case ReportReason.other:
        return l10n.reportReasonOther;
    }
  }
}

class _UserChip extends StatelessWidget {
  const _UserChip({required this.profile, required this.onClear});

  final FriendProfile profile;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFD4AF37).withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          if (profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty)
            CachedNetworkImage(
              imageUrl: profile.avatarUrl!,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              imageBuilder: (_, img) => CircleAvatar(radius: 18, backgroundImage: img),
              placeholder: (_, __) => const CircleAvatar(radius: 18, child: Icon(Icons.person)),
              errorWidget: (_, __, ___) => const CircleAvatar(radius: 18, child: Icon(Icons.person)),
            )
          else
            const CircleAvatar(radius: 18, child: Icon(Icons.person)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(profile.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (profile.shortId != null) Text(profile.shortId!, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6))),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.close), onPressed: onClear, iconSize: 20),
        ],
      ),
    );
  }
}

class _ScreenshotThumb extends StatelessWidget {
  const _ScreenshotThumb({required this.file, required this.onRemove});

  final File file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(file, width: 80, height: 80, fit: BoxFit.cover),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: const CircleAvatar(radius: 12, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 16, color: Colors.white)),
          ),
        ),
      ],
    );
  }
}
