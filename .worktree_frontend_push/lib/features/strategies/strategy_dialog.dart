import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../l10n/app_localizations.dart';
import '../auth/login_page.dart';
import '../teachers/teacher_repository.dart';

/// 展示完整投资策略弹窗，含评论列表与发表
void showStrategyDialog(
  BuildContext context,
  String text,
  List<Comment> comments, {
  required String teacherId,
  String? strategyId,
  required String currentUserId,
  required TeacherRepository repo,
  required void Function(String userName, String content) onCommentPosted,
  bool initialShowComments = false,
}) {
  final screenW = MediaQuery.of(context).size.width;
  final maxW = (screenW > 420) ? 400.0 : (screenW - 40);
  showDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: _StrategyDialogContent(
          text: text,
          comments: comments,
          teacherId: teacherId,
          strategyId: strategyId,
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
    required this.currentUserId,
    required this.repo,
    required this.onCommentPosted,
    this.initialShowComments = false,
  });

  final String text;
  final List<Comment> comments;
  final String teacherId;
  final String? strategyId;
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
    final merged = [...widget.comments, ...dialogOptimistic]
      ..sort((a, b) => b.date.compareTo(a.date));
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

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
                final showCount = replies.length <= 1 ? replies.length : (isExpanded ? replies.length : 1);
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
                          isExpanded ? AppLocalizations.of(context)!.featuredCollapse : AppLocalizations.of(context)!.featuredExpandReplies(replies.length - 1),
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

            return ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
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
                        mainAxisSize: MainAxisSize.max,
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
                                icon: Icon(Icons.close, color: Colors.white70, size: 22),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.white.withOpacity(0.08),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: bgCard,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: accent.withOpacity(0.15), width: 0.5),
                            ),
                            child: Text(
                              widget.text,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withOpacity(0.9),
                                height: 1.7,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: () {
                                  setState(() => showComments = !showComments);
                                },
                                icon: Icon(
                                  showComments ? Icons.expand_less : Icons.expand_more,
                                  color: accent,
                                  size: 20,
                                ),
                                label: Text(
                                  showComments ? AppLocalizations.of(context)!.featuredHideComments : AppLocalizations.of(context)!.featuredViewComments,
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
                            SizedBox(height: 20, child: Divider(height: 1, color: Colors.white.withOpacity(0.08))),
                            Expanded(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.only(top: 8),
                                child: merged.isEmpty
                                    ? _EmptyHint(text: AppLocalizations.of(context)!.featuredNoComments)
                                    : Align(
                                        alignment: Alignment.centerLeft,
                                        widthFactor: 1,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: buildThreadedComments(merged, (c) {
                                            setState(() {
                                              showComments = true;
                                              replyToComment = c;
                                            });
                                          }),
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (showComments)
                            AnimatedPadding(
                              duration: const Duration(milliseconds: 200),
                              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                            child: _CommentForm(
                              teacherId: widget.teacherId,
                              strategyId: widget.strategyId,
                              currentUserId: widget.currentUserId,
                              repo: widget.repo,
                                replyToComment: replyToComment,
                                onReplyConsumed: () => setState(() => replyToComment = null),
                                onPosted: (userName, content, {Comment? replyTo}) {
                                  widget.onCommentPosted(userName, content);
                                  setState(() => replyToComment = null);
                                  final now = DateTime.now();
                                  final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
                                      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
                                  dialogOptimistic.add(Comment(
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
                                  ));
                                  setState(() {});
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
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
