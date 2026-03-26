import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../l10n/app_localizations.dart';
import '../auth/login_page.dart';
import '../teachers/teacher_repository.dart';
import 'strategy_image_preview.dart';

/// 展示完整投资策略弹窗，含评论列表与发表
void showStrategyDialog(
  BuildContext context,
  String text,
  List<Comment> comments, {
  required String teacherId,
  String? strategyId,
  List<String>? imageUrls,
  required String currentUserId,
  required TeacherRepository repo,
  required void Function(String userName, String content) onCommentPosted,
  bool initialShowComments = false,
}) {
  final screenW = MediaQuery.of(context).size.width;
  final isDesktop = screenW >= 960;
  final double maxW;
  if (isDesktop) {
    final available = screenW - 96;
    if (available > 1180) {
      maxW = 1180;
    } else if (available < 960) {
      maxW = 960;
    } else {
      maxW = available;
    }
  } else if (screenW > 640) {
    maxW = 720;
  } else {
    maxW = screenW - 32;
  }
  showDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 40 : 16,
        vertical: isDesktop ? 24 : 32,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: _StrategyDialogContent(
          text: text,
          comments: comments,
          teacherId: teacherId,
          strategyId: strategyId,
          imageUrls: imageUrls,
          currentUserId: currentUserId,
          repo: repo,
          onCommentPosted: onCommentPosted,
          initialShowComments: initialShowComments,
        ),
      ),
    ),
  );
}

class _StrategyDialogContent extends StatefulWidget {
  const _StrategyDialogContent({
    required this.text,
    required this.comments,
    required this.teacherId,
    this.strategyId,
    this.imageUrls,
    required this.currentUserId,
    required this.repo,
    required this.onCommentPosted,
    this.initialShowComments = false,
  });

  final String text;
  final List<Comment> comments;
  final String teacherId;
  final String? strategyId;
  final List<String>? imageUrls;
  final String currentUserId;
  final TeacherRepository repo;
  final void Function(String userName, String content) onCommentPosted;
  final bool initialShowComments;

  @override
  State<_StrategyDialogContent> createState() => _StrategyDialogContentState();
}

class _StrategyDialogContentState extends State<_StrategyDialogContent> {
  late bool showComments;
  Comment? replyToComment;
  final List<Comment> dialogOptimistic = [];
  final Set<String> expandedReplies = {};

  @override
  void initState() {
    super.initState();
    showComments = widget.initialShowComments;
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFD4AF37);
    const bgCard = Color(0xFF0B0C0E);
    const radius = 24.0;
    final media = MediaQuery.of(context);
    final screenW = media.size.width;
    final isDesktop = screenW >= 960;
    final merged = [...widget.comments, ...dialogOptimistic]
      ..sort((a, b) => b.date.compareTo(a.date));
    final allImageUrls = (widget.imageUrls ?? const <String>[])
        .where((u) => u.trim().isNotEmpty)
        .toList(growable: false);
    final maxHeight = media.size.height * (isDesktop ? 0.84 : 0.75);

    /// 抖音式：父评论倒序，回复紧贴父评论下方、正序；默认只显示 1 条回复，可展开
    List<Widget> buildThreadedComments(
      List<Comment> list,
      void Function(Comment) onReplyTap,
    ) {
      final topLevel = list.where((c) => c.replyToCommentId == null).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      final widgets = <Widget>[];
      for (final parent in topLevel) {
        widgets.add(_CommentItem(
          comment: parent,
          onReplyTap: onReplyTap,
          isReply: false,
        ));
        final descendantIds = <String>{parent.id};
        var changed = true;
        while (changed) {
          changed = false;
          for (final c in list) {
            if (c.replyToCommentId != null &&
                descendantIds.contains(c.replyToCommentId) &&
                !descendantIds.contains(c.id)) {
              descendantIds.add(c.id);
              changed = true;
            }
          }
        }
        final replies = list
            .where((c) =>
                c.replyToCommentId != null &&
                descendantIds.contains(c.replyToCommentId))
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
        final isExpanded = expandedReplies.contains(parent.id);
        final showCount =
            replies.length <= 1 ? replies.length : (isExpanded ? replies.length : 1);
        for (var i = 0; i < showCount; i++) {
          widgets.add(_CommentItem(
            comment: replies[i],
            onReplyTap: onReplyTap,
            isReply: true,
          ));
        }
        if (replies.length > 1) {
          widgets.add(
            GestureDetector(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    expandedReplies.remove(parent.id);
                  } else {
                    expandedReplies.add(parent.id);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 78, bottom: 12),
                child: Text(
                  isExpanded
                      ? AppLocalizations.of(context)!.featuredCollapse
                      : AppLocalizations.of(context)!.featuredExpandReplies(
                          replies.length - 1,
                        ),
                  style: TextStyle(
                    color: accent.withOpacity(0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }
      }
      return widgets;
    }

    void handleReplyTap(Comment c) {
      setState(() {
        showComments = true;
        replyToComment = c;
      });
    }

    void handlePosted(String userName, String content, {Comment? replyTo}) {
      widget.onCommentPosted(userName, content);
      setState(() => replyToComment = null);
      final now = DateTime.now();
      final date =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      dialogOptimistic.add(
        Comment(
          id: 'local-${now.millisecondsSinceEpoch}',
          userName: userName,
          content: content,
          date: date,
          replyToCommentId: replyTo?.id,
          replyToContent: replyTo != null
              ? (replyTo.content.length > 50
                  ? '${replyTo.content.substring(0, 50)}…'
                  : replyTo.content)
              : null,
        ),
      );
      setState(() {});
    }

    Widget buildCommentComposer() {
      return AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: _CommentForm(
          teacherId: widget.teacherId,
          strategyId: widget.strategyId,
          currentUserId: widget.currentUserId,
          repo: widget.repo,
          replyToComment: replyToComment,
          onReplyConsumed: () => setState(() => replyToComment = null),
          onPosted: handlePosted,
        ),
      );
    }

    Widget buildCommentThread() {
      return merged.isEmpty
          ? _EmptyHint(text: AppLocalizations.of(context)!.featuredNoComments)
          : SingleChildScrollView(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: buildThreadedComments(merged, handleReplyTap),
                ),
              ),
            );
    }

    Widget buildStrategyBody() {
      return SingleChildScrollView(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (allImageUrls.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(isDesktop ? 12 : 0),
                decoration: isDesktop
                    ? BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      )
                    : null,
                child: StrategyImagePreviewGrid(
                  imageUrls: allImageUrls,
                  spacing: 10,
                  borderRadius: isDesktop ? 16 : 12,
                  onImageTap: (i) => showStrategyImageViewer(
                    context,
                    imageUrls: allImageUrls,
                    initialIndex: i,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(isDesktop ? 22 : 18),
              decoration: BoxDecoration(
                color: bgCard,
                borderRadius: BorderRadius.circular(isDesktop ? 20 : 16),
                border: Border.all(color: accent.withOpacity(0.15), width: 0.5),
              ),
              child: Text(
                widget.text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withOpacity(0.9),
                  height: 1.8,
                  fontSize: isDesktop ? 16 : 15,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (isDesktop) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          height: maxHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A1C21), Color(0xFF0D0E11)],
            ),
            border: Border.all(color: accent.withOpacity(0.6), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(0.15),
                blurRadius: 24,
                spreadRadius: -4,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 32,
                spreadRadius: -8,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: accent.withOpacity(0.4)),
                      ),
                      child: const Icon(Icons.trending_up, color: accent, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)!.strategiesFullStrategy,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            AppLocalizations.of(context)!.featuredCommentsCount(merged.length),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.55),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => showComments = !showComments),
                      icon: Icon(
                        showComments ? Icons.forum_outlined : Icons.chat_bubble_outline,
                        color: accent,
                        size: 18,
                      ),
                      label: Text(
                        showComments
                            ? AppLocalizations.of(context)!.featuredHideComments
                            : AppLocalizations.of(context)!.featuredViewComments,
                        style: const TextStyle(color: accent),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white70, size: 22),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.08),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.025),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: buildStrategyBody(),
                        ),
                      ),
                      if (showComments) ...[
                        const SizedBox(width: 24),
                        SizedBox(
                          width: 360,
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.025),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: Colors.white.withOpacity(0.05)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      AppLocalizations.of(context)!.featuredViewComments,
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      AppLocalizations.of(context)!.featuredCommentsCount(
                                        merged.length,
                                      ),
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.55),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(
                                  height: 20,
                                  child: Divider(
                                    height: 1,
                                    color: Colors.white.withOpacity(0.08),
                                  ),
                                ),
                                Expanded(child: buildCommentThread()),
                                const SizedBox(height: 12),
                                buildCommentComposer(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        height: maxHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1C21), Color(0xFF0D0E11)],
          ),
          border: Border.all(color: accent.withOpacity(0.6), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.15),
              blurRadius: 24,
              spreadRadius: -4,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 32,
              spreadRadius: -8,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: accent.withOpacity(0.4)),
                    ),
                    child: const Icon(Icons.trending_up, color: accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context)!.strategiesFullStrategy,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white70, size: 22),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.08),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(child: buildStrategyBody()),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => showComments = !showComments),
                    icon: Icon(
                      showComments ? Icons.expand_less : Icons.expand_more,
                      color: accent,
                      size: 20,
                    ),
                    label: Text(
                      showComments
                          ? AppLocalizations.of(context)!.featuredHideComments
                          : AppLocalizations.of(context)!.featuredViewComments,
                      style: TextStyle(
                        color: accent.withOpacity(0.95),
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    AppLocalizations.of(context)!.featuredCommentsCount(merged.length),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              if (showComments) ...[
                SizedBox(
                  height: 20,
                  child: Divider(height: 1, color: Colors.white.withOpacity(0.08)),
                ),
                Expanded(child: buildCommentThread()),
                const SizedBox(height: 8),
                buildCommentComposer(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showStrategyImageViewer(
  BuildContext context, {
  required List<String> imageUrls,
  int initialIndex = 0,
}) async {
  final urls = imageUrls.where((u) => u.trim().isNotEmpty).toList(growable: false);
  if (urls.isEmpty) return;
  final start = initialIndex.clamp(0, urls.length - 1);
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _StrategyImageViewerPage(
        imageUrls: urls,
        initialIndex: start,
      ),
      fullscreenDialog: true,
    ),
  );
}

class _StrategyImageViewerPage extends StatefulWidget {
  const _StrategyImageViewerPage({
    required this.imageUrls,
    required this.initialIndex,
  });

  final List<String> imageUrls;
  final int initialIndex;

  @override
  State<_StrategyImageViewerPage> createState() => _StrategyImageViewerPageState();
}

class _StrategyImageViewerPageState extends State<_StrategyImageViewerPage> {
  late final PageController _pageController;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1}/${widget.imageUrls.length}'),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.imageUrls.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) {
          return Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Image.network(
                widget.imageUrls[i],
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111215),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD4AF37), width: 0.4),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _CommentForm extends StatefulWidget {
  const _CommentForm({
    required this.teacherId,
    this.strategyId,
    required this.currentUserId,
    required this.repo,
    this.replyToComment,
    this.onReplyConsumed,
    this.onPosted,
  });

  final String teacherId;
  final String? strategyId;
  final String currentUserId;
  final TeacherRepository repo;
  final Comment? replyToComment;
  final VoidCallback? onReplyConsumed;
  final void Function(String userName, String content, {Comment? replyTo})? onPosted;

  @override
  State<_CommentForm> createState() => _CommentFormState();
}

class _CommentFormState extends State<_CommentForm> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _submitting = false;
  Comment? _pendingReplyTo;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_CommentForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.replyToComment != null &&
        widget.replyToComment != oldWidget.replyToComment) {
      _pendingReplyTo = widget.replyToComment;
      _controller.text = '@${widget.replyToComment!.userName} ';
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
        widget.onReplyConsumed?.call();
      });
    }
  }

  Future<void> _submit() async {
    final content = _controller.text.trim();
    if (content.isEmpty) return;
    if (widget.currentUserId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.featuredLoginBeforeComment)),
        );
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
      }
      return;
    }
    setState(() => _submitting = true);
    try {
      final replyTo = _pendingReplyTo ?? widget.replyToComment;
      final userName = await widget.repo.insertComment(
        teacherId: widget.teacherId,
        userId: widget.currentUserId,
        content: content,
        strategyId: widget.strategyId,
        replyToCommentId: replyTo?.id,
        replyToContent: replyTo?.content,
      );
      _controller.clear();
      _pendingReplyTo = null;
      if (mounted) {
        widget.onPosted?.call(userName, content, replyTo: replyTo);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.featuredCommentPublished)),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context)!.featuredCommentPublishFailed}: ${msg.length > 120 ? msg.substring(0, 120) + '…' : msg}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFD4AF37);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111215),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.25), width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              minLines: 1,
              maxLines: 3,
              enabled: !_submitting,
              style: TextStyle(color: Colors.white.withOpacity(0.9),
                  fontSize: 15),
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.featuredCommentHint,
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                filled: true,
                fillColor: const Color(0xFF0B0C0E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: accent.withOpacity(0.4)),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: const Color(0xFF111215),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(_submitting ? AppLocalizations.of(context)!.featuredPublishing : AppLocalizations.of(context)!.featuredPublish,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// 抖音风格 @ 提及色（蓝色）
const _mentionColor = Color(0xFF5B9EFF);

class _CommentItem extends StatelessWidget {
  const _CommentItem({
    required this.comment,
    this.onReplyTap,
    this.isReply = false,
  });

  final Comment comment;
  final void Function(Comment)? onReplyTap;
  final bool isReply;

  static List<TextSpan> _buildContentSpans(String content, Color mentionColor) {
    final spans = <TextSpan>[];
    final regex = RegExp(r'@(\S+)');
    int lastEnd = 0;
    for (final match in regex.allMatches(content)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: content.substring(lastEnd, match.start),
          style: TextStyle(color: Colors.white.withOpacity(0.88)),
        ));
      }
      spans.add(TextSpan(
        text: '@${match.group(1)}',
        style: TextStyle(color: mentionColor, fontWeight: FontWeight.w600),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < content.length) {
      spans.add(TextSpan(
        text: content.substring(lastEnd),
        style: TextStyle(color: Colors.white.withOpacity(0.88)),
      ));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(
        text: content,
        style: TextStyle(color: Colors.white.withOpacity(0.88)),
      ));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFD4AF37);
    final initial = comment.userName.isNotEmpty
        ? comment.userName.characters.first.toUpperCase()
        : '?';
    final hasAvatar = comment.avatarUrl != null &&
        comment.avatarUrl!.trim().isNotEmpty;
    final content = Padding(
      padding: EdgeInsets.only(
        bottom: 16,
        left: isReply ? 40 : 0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: isReply ? 14 : 18,
            backgroundColor: accent.withOpacity(0.2),
            backgroundImage: hasAvatar
                ? NetworkImage(comment.avatarUrl!.trim())
                : null,
            child: hasAvatar
                ? null
                : Text(
                    initial,
                    style: TextStyle(
                      color: accent,
                      fontSize: isReply ? 14 : 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      comment.userName,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Text(
                      comment.date,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                if (comment.replyToContent != null &&
                    comment.replyToContent!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border(
                        left: BorderSide(color: accent.withOpacity(0.5), width: 3),
                      ),
                    ),
                    child: Text(
                      comment.replyToContent!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white54,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                RichText(
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withOpacity(0.88),
                      height: 1.5,
                    ),
                    children: _buildContentSpans(comment.content, _mentionColor),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (onReplyTap != null) {
      return GestureDetector(
        onLongPress: () {
          HapticFeedback.mediumImpact();
          onReplyTap!(comment);
        },
        behavior: HitTestBehavior.opaque,
        child: content,
      );
    }
    return content;
  }
}
