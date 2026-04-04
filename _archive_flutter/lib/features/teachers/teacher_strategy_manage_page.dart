import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/design/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/components.dart';
import 'teacher_models.dart';
import 'teacher_repository.dart';

class TeacherStrategyManagePage extends StatefulWidget {
  const TeacherStrategyManagePage({super.key});

  @override
  State<TeacherStrategyManagePage> createState() =>
      _TeacherStrategyManagePageState();
}

class _TeacherStrategyManagePageState extends State<TeacherStrategyManagePage> {
  final _repository = TeacherRepository();
  String _statusLabel = 'pending';
  bool _loadingProfile = true;
  bool _actionInProgress = false;

  static const Color _accent = AppColors.primary;

  @override
  void initState() {
    super.initState();
    _loadProfileStatus();
  }

  Future<void> _loadProfileStatus() async {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (userId.isEmpty) {
      if (!mounted) return;
      setState(() => _loadingProfile = false);
      return;
    }
    final profile = await _repository.fetchProfile(userId);
    if (!mounted) return;
    setState(() {
      _statusLabel = (profile?.status ?? 'pending').trim().toLowerCase();
      _loadingProfile = false;
    });
  }

  Future<void> _addStrategyDialog() async {
    final result = await Navigator.of(context).push<_StrategyComposeResult>(
      MaterialPageRoute(
        builder: (_) => const _StrategyComposerPage(),
        fullscreenDialog: true,
      ),
    );
    if (result == null) return;
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (userId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.teachersPleaseLoginFirst),
        ),
      );
      return;
    }
    try {
      final List<String> imageUrls = [];
      for (final x in result.images) {
        final bytes = await x.readAsBytes();
        final name = x.name.isNotEmpty
            ? x.name
            : 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final mime = x.mimeType ?? 'image/jpeg';
        final url = await _repository.uploadStrategyImage(
          teacherId: userId,
          fileName: name,
          bytes: bytes,
          contentType: mime,
        );
        imageUrls.add(url);
      }
      await _repository.addStrategy(
        teacherId: userId,
        title: result.title,
        summary: '',
        content: result.content,
        imageUrls: imageUrls,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.teachersStrategyPublished),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppLocalizations.of(context)!.teachersPublishFailed}：$e'),
        ),
      );
    }
  }

  Future<void> _handleStrategyAction({
    required TeacherStrategy item,
    required String value,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    if (_actionInProgress) return;

    if (value == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.teachersDeleteStrategy),
          content: Text(l10n.teachersDeleteStrategyConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.msgDelete),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _actionInProgress = true);
    try {
      if (value == 'delete') {
        await _repository.deleteStrategy(strategyId: item.id);
      } else {
        await _repository.updateStrategyStatus(
          strategyId: item.id,
          status: value,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value == 'delete'
                ? l10n.teachersStrategyDeleted
                : (value == 'draft' ? l10n.teachersOffline : l10n.teachersOnline),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value == 'delete'
                ? '${l10n.teachersDeleteStrategyFailed}：$e'
                : '${l10n.teachersPublishFailed}：$e',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  String _strategyStatusText(AppLocalizations l10n, String status) {
    switch (status.trim().toLowerCase()) {
      case 'published':
        return l10n.teachersOnline;
      case 'draft':
        return l10n.teachersOffline;
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (userId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.teachersPublishStrategy)),
        body: Center(child: Text(l10n.teachersPleaseLoginFirst)),
      );
    }
    if (_loadingProfile) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: _accent)),
      );
    }
    if (_statusLabel != 'approved') {
      final hint = (_statusLabel == 'frozen' || _statusLabel == 'blocked')
          ? l10n.teachersStatusCannotPublishHint(
              _statusLabel == 'frozen' ? l10n.teachersFrozen : l10n.teachersBlocked,
            )
          : l10n.teachersStatusOpenAfterApproval;
      return Scaffold(
        appBar: AppBar(title: Text(l10n.teachersPublishStrategy)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              hint,
              style: const TextStyle(color: AppColors.textTertiary),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.teachersPublishStrategy)),
      body: StreamBuilder<List<TeacherStrategy>>(
        stream: _repository.watchStrategies(userId),
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <TeacherStrategy>[];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: AppButton(
                  onPressed: _addStrategyDialog,
                  label: l10n.teachersPublishStrategy,
                ),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                Text(
                  l10n.teachersNoStrategy,
                  style: const TextStyle(color: AppColors.textTertiary),
                )
              else
                ...items.map((item) {
                  final body = (item.content?.trim().isNotEmpty == true
                          ? item.content!
                          : item.summary.trim().isNotEmpty
                              ? item.summary
                              : '')
                      .trim();
                  final urls = (item.imageUrls ?? const <String>[])
                      .where((u) => u.trim().isNotEmpty)
                      .take(9)
                      .toList(growable: false);
                  return AppCard(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (urls.isNotEmpty) ...[
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: List.generate(urls.length, (i) {
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    width: 96,
                                    height: 96,
                                    child: Image.network(
                                      urls[i],
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const ColoredBox(
                                        color: Color(0xFF2A2C33),
                                        child: Icon(
                                          Icons.broken_image_outlined,
                                          color: _accent,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                            const SizedBox(height: 10),
                          ],
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (item.title.trim().isNotEmpty)
                                      Text(
                                        item.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    if (body.isNotEmpty) ...[
                                      if (item.title.trim().isNotEmpty)
                                        const SizedBox(height: 4),
                                      Text(body),
                                    ],
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) => _handleStrategyAction(
                                  item: item,
                                  value: value,
                                ),
                                itemBuilder: (context) {
                                  if (item.status == 'published') {
                                    return [
                                      PopupMenuItem<String>(
                                        value: 'draft',
                                        child: Text(l10n.teachersOffline),
                                      ),
                                      PopupMenuItem<String>(
                                        value: 'delete',
                                        child: Text(l10n.teachersDeleteStrategy),
                                      ),
                                    ];
                                  }
                                  return [
                                    PopupMenuItem<String>(
                                      value: 'published',
                                      child: Text(l10n.teachersOnline),
                                    ),
                                    PopupMenuItem<String>(
                                      value: 'delete',
                                      child: Text(l10n.teachersDeleteStrategy),
                                    ),
                                  ];
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Text(
                                    _strategyStatusText(l10n, item.status),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _PickedImage {
  const _PickedImage({
    required this.file,
    required this.bytes,
  });

  final XFile file;
  final Uint8List bytes;
}

class _StrategyComposeResult {
  const _StrategyComposeResult({
    required this.title,
    required this.content,
    required this.images,
  });

  final String title;
  final String content;
  final List<XFile> images;
}

class _StrategyComposerPage extends StatefulWidget {
  const _StrategyComposerPage();

  @override
  State<_StrategyComposerPage> createState() => _StrategyComposerPageState();
}

class _StrategyComposerPageState extends State<_StrategyComposerPage> {
  static const Color _accent = AppColors.primary;
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _imagePicker = ImagePicker();
  final List<_PickedImage> _images = [];

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final l10n = AppLocalizations.of(context)!;
    final remaining = 9 - _images.length;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.teachersStrategyMaxNineImages)),
      );
      return;
    }
    final picked = await _imagePicker.pickMultiImage(imageQuality: 85);
    if (picked.isEmpty || !mounted) return;

    final chosen = picked.take(remaining).toList(growable: false);
    final bytesList = await Future.wait(chosen.map((x) => x.readAsBytes()));
    if (!mounted) return;

    setState(() {
      for (var i = 0; i < chosen.length; i++) {
        _images.add(_PickedImage(file: chosen[i], bytes: bytesList[i]));
      }
    });

    if (picked.length > remaining) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.teachersStrategyExceedNineIgnored)),
      );
    }
  }

  void _submit() {
    final l10n = AppLocalizations.of(context)!;
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty && content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.teachersFillStrategyTitle)),
      );
      return;
    }
    final normalizedTitle = title.isNotEmpty
        ? title
        : (content.length > 20 ? '${content.substring(0, 20)}...' : content);
    Navigator.of(context).pop(
      _StrategyComposeResult(
        title: normalizedTitle,
        content: content,
        images: _images.map((e) => e.file).toList(growable: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.teachersPublishStrategy),
        actions: [
          TextButton(
            onPressed: _submit,
            child: Text(l10n.teachersPublish),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Text(
                '${l10n.teachersStrategyImage} (${_images.length}/9)',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _pickImages,
                icon: const Icon(
                  Icons.add_photo_alternate,
                  size: 18,
                  color: _accent,
                ),
                label: Text(
                  l10n.teachersAddImage,
                  style: const TextStyle(color: _accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...List.generate(_images.length, (index) {
                final image = _images[index];
                return SizedBox(
                  width: 104,
                  height: 104,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(image.bytes, fit: BoxFit.cover),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: InkWell(
                          onTap: () => setState(() => _images.removeAt(index)),
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              if (_images.length < 9)
                InkWell(
                  onTap: _pickImages,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2C33),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(
                      Icons.add,
                      color: _accent,
                      size: 28,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: l10n.teachersTitleLabel,
              labelStyle: const TextStyle(color: Color(0xFF6C6F77)),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _contentController,
            decoration: InputDecoration(
              labelText: l10n.teachersStrategyContent,
              labelStyle: const TextStyle(color: Color(0xFF6C6F77)),
            ),
            style: const TextStyle(color: Colors.white),
            maxLines: 8,
          ),
        ],
      ),
    );
  }
}
