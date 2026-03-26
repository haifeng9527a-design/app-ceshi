import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../l10n/app_localizations.dart';
import '../auth/login_page.dart';
import '../teachers/teacher_models.dart' as tmodels;
import '../teachers/teacher_repository.dart';
import 'strategy_dialog.dart';
import 'strategy_image_preview.dart';

class StrategiesPage extends StatelessWidget {
  const StrategiesPage({super.key, required this.teacher});

  final Teacher teacher;
  static const Color _pageBg = Color(0xFF0B0D12);

  @override
  Widget build(BuildContext context) {
    final repo = TeacherRepository();
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final canSeeTodayStrategy = currentUserId.isNotEmpty;

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.strategiesPageTitle),
      ),
      body: StreamBuilder<List<tmodels.TeacherStrategy>>(
        stream: repo.watchPublishedStrategies(teacher.id),
        builder: (context, stratSnapshot) {
          final strategies = stratSnapshot.data ?? const [];
          final latest = canSeeTodayStrategy && strategies.isNotEmpty
              ? strategies.first
              : null;
          final history = canSeeTodayStrategy
              ? (strategies.length > 1
                  ? strategies.sublist(1)
                  : const <tmodels.TeacherStrategy>[])
              : strategies
                  .where((s) => !_isTodayStrategy(s.createdAt))
                  .toList();

          return ListView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _SectionTitle(title: AppLocalizations.of(context)!.strategiesTodayStrategies),
              if (!canSeeTodayStrategy)
                _InfoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '登录后可查看今日交易策略，当前仅展示历史交易策略。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const LoginPage()),
                          );
                        },
                        icon: const Icon(Icons.login),
                        label: Text(AppLocalizations.of(context)!.authLoginOrRegister),
                      ),
                    ],
                  ),
                )
              else if (latest != null)
                StreamBuilder<List<Comment>>(
                  stream: repo.watchStrategyComments(teacher.id, latest.id),
                  builder: (context, commentsSnapshot) {
                    final comments = commentsSnapshot.data ?? const [];
                    return _StrategyCard(
                      strategy: latest,
                      fallbackText: teacher.todayStrategy,
                      teacherId: teacher.id,
                      currentUserId: currentUserId,
                      repo: repo,
                      comments: comments,
                      onCommentPosted: null,
                    );
                  },
                )
              else
                _InfoCard(
                  child: Text(
                    teacher.todayStrategy,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              const SizedBox(height: 24),
              _SectionTitle(title: AppLocalizations.of(context)!.strategiesHistoryStrategies),
              if (history.isEmpty)
                _InfoCard(
                  child: Text(
                    AppLocalizations.of(context)!.strategiesNoHistory,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white54,
                    ),
                  ),
                )
              else
                ...history.map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: StreamBuilder<List<Comment>>(
                      stream: repo.watchStrategyComments(teacher.id, s.id),
                      builder: (context, commentsSnapshot) {
                        final comments = commentsSnapshot.data ?? const [];
                        return _StrategyCard(
                          strategy: s,
                          fallbackText: s.summary,
                          teacherId: teacher.id,
                          currentUserId: currentUserId,
                          repo: repo,
                          comments: comments,
                          onCommentPosted: null,
                        );
                      },
                    ),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

bool _isTodayStrategy(DateTime dt) {
  final local = dt.toLocal();
  final now = DateTime.now().toLocal();
  return local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111215),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD4AF37), width: 0.4),
      ),
      child: child,
    );
  }
}

class _StrategyCard extends StatelessWidget {
  const _StrategyCard({
    required this.strategy,
    required this.fallbackText,
    required this.teacherId,
    required this.currentUserId,
    required this.repo,
    required this.comments,
    required this.onCommentPosted,
  });

  final tmodels.TeacherStrategy strategy;
  final String fallbackText;
  final String teacherId;
  final String currentUserId;
  final TeacherRepository repo;
  final List<Comment> comments;
  final void Function(String, String)? onCommentPosted;

  @override
  Widget build(BuildContext context) {
    final text = (strategy.content?.trim().isNotEmpty == true
            ? strategy.content!
            : (strategy.summary.trim().isNotEmpty ? strategy.summary : null)) ??
        (fallbackText.trim().isNotEmpty ? fallbackText : AppLocalizations.of(context)!.featuredNoStrategyContent);
    final allImageUrls = (strategy.imageUrls ?? const <String>[])
        .where((u) => u.trim().isNotEmpty)
        .toList(growable: false);

    return InkWell(
      onTap: () {
        showStrategyDialog(
          context,
          text,
          comments,
          teacherId: teacherId,
          strategyId: strategy.id,
          imageUrls: allImageUrls,
          currentUserId: currentUserId,
          repo: repo,
          onCommentPosted: onCommentPosted ?? (_, __) {},
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF111215),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD4AF37), width: 0.4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (allImageUrls.isNotEmpty) ...[
              StrategyImagePreviewGrid(
                imageUrls: allImageUrls,
                onImageTap: (i) => showStrategyImageViewer(
                  context,
                  imageUrls: allImageUrls,
                  initialIndex: i,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4AF37),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.trending_up,
                    color: Color(0xFF111215),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    strategy.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: const Color(0xFFD4AF37),
                    ),
                  ),
                ),
                const Icon(Icons.open_in_new, size: 16, color: Color(0xFFD4AF37)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.featuredViewFullStrategy,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: const Color(0xFFD4AF37),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.chat_bubble_outline, size: 14, color: Colors.white54),
                const SizedBox(width: 4),
                Text(
                  AppLocalizations.of(context)!.featuredCommentsCount(comments.length),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
