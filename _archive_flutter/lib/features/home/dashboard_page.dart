import 'package:flutter/material.dart';

import '../../core/app_webview_page.dart';
import '../../core/design/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/components.dart';
import '../market/market_page.dart';
import '../market/market_repository.dart';
import '../messages/messages_page.dart';
import '../rankings/rankings_page.dart';
import '../teachers/teacher_list_page.dart';
import '../teachers/teacher_models.dart';
import '../teachers/teacher_public_page.dart';
import '../teachers/teacher_repository.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: AppSpacing.only(
                left: AppSpacing.md,
                top: AppSpacing.md,
                right: AppSpacing.md,
                bottom: AppSpacing.xl,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  [
                    const _HeroBanner(),
                    SizedBox(height: AppSpacing.lg),
                    const _QuickActionGrid(),
                    SizedBox(height: AppSpacing.lg),
                    const _TrustHighlights(),
                    SizedBox(height: AppSpacing.xl),
                    _SectionTitle(
                      eyebrow: l10n.dashboardEyebrowMentor,
                      title: l10n.dashboardTitleMentor,
                      actionLabel: l10n.dashboardActionViewAll,
                      destination: const TeacherListPage(),
                    ),
                    SizedBox(height: AppSpacing.md),
                    const _MentorSpotlightSection(),
                    SizedBox(height: AppSpacing.xl),
                    _SectionTitle(
                      eyebrow: l10n.dashboardEyebrowRanking,
                      title: l10n.dashboardTitleRanking,
                      actionLabel: l10n.dashboardActionFullRanking,
                      destination: const RankingsPage(),
                    ),
                    SizedBox(height: AppSpacing.md),
                    const _LeaderboardPreview(),
                    SizedBox(height: AppSpacing.xl),
                    _SectionTitle(
                      eyebrow: l10n.dashboardEyebrowNews,
                      title: l10n.dashboardTitleNews,
                      actionLabel: l10n.dashboardActionMoreNews,
                      destination: const MarketPage(),
                    ),
                    SizedBox(height: AppSpacing.md),
                    const _MarketSnapshotSection(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: AppSpacing.allLg,
      decoration: BoxDecoration(
        borderRadius: AppRadius.lgAll,
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1B1430),
            AppColors.surfaceElevated,
            const Color(0xFF10202B).withValues(alpha: 0.92),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.28)),
        boxShadow: AppShadow.cardElevated,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.dashboardHeroTitle,
            style: AppTypography.title.copyWith(fontSize: 24, height: 1.25),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.dashboardHeroSubtitle,
            style: AppTypography.bodySecondary.copyWith(
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: l10n.dashboardHeroActionViewRanking,
                  icon: const Icon(Icons.leaderboard_outlined, size: 18),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RankingsPage()),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _HeroMetric(
                  label: l10n.dashboardHeroMetricDimensionLabel,
                  value: l10n.dashboardHeroMetricDimensionValue,
                  accent: AppColors.primary,
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _HeroMetric(
                  label: l10n.dashboardHeroMetricCountLabel,
                  value: l10n.dashboardHeroMetricCountValue,
                  accent: AppColors.positive,
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _HeroMetric(
                  label: l10n.dashboardHeroMetricUpdateLabel,
                  value: l10n.dashboardHeroMetricUpdateValue,
                  accent: AppColors.warning,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.allMd,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.72),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.caption),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: AppTypography.subtitle.copyWith(color: accent),
          ),
        ],
      ),
    );
  }
}

class _QuickActionGrid extends StatelessWidget {
  const _QuickActionGrid();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = [
      (
        title: l10n.dashboardQuickMarketTitle,
        subtitle: l10n.dashboardQuickMarketSubtitle,
        icon: Icons.show_chart,
        destination: const MarketPage(),
      ),
      (
        title: l10n.dashboardQuickMentorTitle,
        subtitle: l10n.dashboardQuickMentorSubtitle,
        icon: Icons.workspace_premium_outlined,
        destination: const TeacherListPage(),
      ),
      (
        title: l10n.dashboardQuickRankingTitle,
        subtitle: l10n.dashboardQuickRankingSubtitle,
        icon: Icons.emoji_events_outlined,
        destination: const RankingsPage(),
      ),
      (
        title: l10n.dashboardQuickMessageTitle,
        subtitle: l10n.dashboardQuickMessageSubtitle,
        icon: Icons.forum_outlined,
        destination: const MessagesPage(),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
        childAspectRatio: 1.12,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return AppCard(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => item.destination),
            );
          },
          padding: AppSpacing.allMd,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: AppRadius.mdAll,
                ),
                child: Icon(item.icon, color: AppColors.primary),
              ),
              const Spacer(),
              Text(item.title, style: AppTypography.subtitle),
              const SizedBox(height: AppSpacing.xs),
              Text(
                item.subtitle,
                style: AppTypography.caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TrustHighlights extends StatelessWidget {
  const _TrustHighlights();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final labels = [
      l10n.dashboardTrust1,
      l10n.dashboardTrust2,
      l10n.dashboardTrust3,
      l10n.dashboardTrust4,
    ];
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: labels
          .map(
            (label) => Container(
              padding: AppSpacing.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.verified_outlined,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(label, style: AppTypography.bodySecondary),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.eyebrow,
    required this.title,
    required this.actionLabel,
    required this.destination,
  });

  final String eyebrow;
  final String title;
  final String actionLabel;
  final Widget destination;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: AppTypography.meta.copyWith(color: AppColors.primary),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(title, style: AppTypography.subtitle),
            ],
          ),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => destination),
            );
          },
          child: Text(actionLabel),
        ),
      ],
    );
  }
}

class _MentorSpotlightSection extends StatefulWidget {
  const _MentorSpotlightSection();

  @override
  State<_MentorSpotlightSection> createState() => _MentorSpotlightSectionState();
}

class _MentorSpotlightSectionState extends State<_MentorSpotlightSection> {
  late final Future<List<TeacherProfile>> _future;

  @override
  void initState() {
    super.initState();
    _future = TeacherRepository().fetchRealRankings();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TeacherProfile>>(
      future: _future,
      builder: (context, snapshot) {
        final profiles = (snapshot.data ?? const <TeacherProfile>[])
            .take(5)
            .toList(growable: false);
        if (profiles.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 192,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: profiles.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, index) {
              final p = profiles[index];
              final name = (p.displayName?.trim().isNotEmpty == true)
                  ? p.displayName!.trim()
                  : ((p.realName?.trim().isNotEmpty == true)
                      ? p.realName!.trim()
                      : AppLocalizations.of(context)!.roleTrader);
              final title = (p.title?.trim().isNotEmpty == true)
                  ? p.title!.trim()
                  : AppLocalizations.of(context)!.dashboardMentorFallbackTitle;
              final avatarUrl = p.avatarUrl?.trim() ?? '';
              final hasAvatar = avatarUrl.isNotEmpty;
              final pnl = (p.pnlMonth ?? 0).toDouble();
              final wins = p.wins ?? 0;
              final losses = p.losses ?? 0;
              final total = wins + losses;
              final winRate = total > 0 ? ((wins / total) * 100).round() : 0;
              return SizedBox(
                width: 280,
                child: AppCard(
                  elevated: true,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TeacherPublicPage(teacherId: p.userId),
                      ),
                    );
                  },
                  padding: AppSpacing.allLg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: AppColors.primary.withValues(alpha: 0.18),
                            backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
                            child: hasAvatar
                                ? null
                                : Text(
                                    name.substring(0, 1).toUpperCase(),
                                    style: AppTypography.subtitle.copyWith(color: AppColors.primary),
                                  ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: AppTypography.subtitle),
                                const SizedBox(height: AppSpacing.xs),
                                Text(title, style: AppTypography.caption),
                              ],
                            ),
                          ),
                          Container(
                            padding: AppSpacing.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xs,
                            ),
                            decoration: BoxDecoration(
                              color: (pnl >= 0 ? AppColors.positive : AppColors.negative)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(0)}',
                              style: AppTypography.body.copyWith(
                                color: pnl >= 0 ? AppColors.positive : AppColors.negative,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        AppLocalizations.of(context)!.dashboardMentorTip,
                        style: AppTypography.bodySecondary.copyWith(height: 1.6),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          _MiniInfoChip(
                            label: AppLocalizations.of(context)!.featuredWins,
                            value: '$wins',
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          _MiniInfoChip(
                            label: AppLocalizations.of(context)!.featuredWinRate,
                            value: '$winRate%',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _MiniInfoChip extends StatelessWidget {
  const _MiniInfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Text(
        '$label $value',
        style: AppTypography.caption.copyWith(color: AppColors.textPrimary),
      ),
    );
  }
}

class _LeaderboardPreview extends StatefulWidget {
  const _LeaderboardPreview();

  @override
  State<_LeaderboardPreview> createState() => _LeaderboardPreviewState();
}

class _LeaderboardPreviewState extends State<_LeaderboardPreview> {
  late final Future<List<TeacherProfile>> _future;

  @override
  void initState() {
    super.initState();
    _future = TeacherRepository().fetchRealRankings();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TeacherProfile>>(
      future: _future,
      builder: (context, snapshot) {
        final profiles = (snapshot.data ?? const <TeacherProfile>[])
            .take(3)
            .toList(growable: false);
        if (profiles.isEmpty) return const SizedBox.shrink();
        return Column(
          children: List.generate(profiles.length, (index) {
            final p = profiles[index];
            final rank = index + 1;
            final name = (p.displayName?.trim().isNotEmpty == true)
                ? p.displayName!.trim()
                : ((p.realName?.trim().isNotEmpty == true)
                    ? p.realName!.trim()
                    : AppLocalizations.of(context)!.roleTrader);
            final title = (p.title?.trim().isNotEmpty == true)
                ? p.title!.trim()
                : AppLocalizations.of(context)!.dashboardMentorFallbackTitle;
            final avatarUrl = p.avatarUrl?.trim() ?? '';
            final hasAvatar = avatarUrl.isNotEmpty;
            final pnl = (p.pnlMonth ?? 0).toDouble();
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppCard(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RankingsPage()),
                  );
                },
                padding: AppSpacing.allMd,
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: AppColors.primary.withValues(alpha: 0.18),
                          backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
                          child: hasAvatar
                              ? null
                              : Text(
                                  name.substring(0, 1).toUpperCase(),
                                  style: AppTypography.caption.copyWith(color: AppColors.primary),
                                ),
                        ),
                        Positioned(
                          left: -4,
                          top: -4,
                          child: Container(
                            width: 18,
                            height: 18,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: rank == 1 ? AppColors.primary : AppColors.surface,
                              border: Border.all(
                                color: rank == 1
                                    ? AppColors.primary.withValues(alpha: 0.48)
                                    : AppColors.borderSubtle,
                              ),
                            ),
                            child: Text(
                              '$rank',
                              style: AppTypography.caption.copyWith(
                                color: rank == 1 ? AppColors.surface : AppColors.textPrimary,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: AppTypography.subtitle),
                          const SizedBox(height: AppSpacing.xs),
                          Text(title, style: AppTypography.caption),
                        ],
                      ),
                    ),
                    Text(
                      '${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(0)}',
                      style: AppTypography.dataSmall.copyWith(
                        color: pnl >= 0 ? AppColors.positive : AppColors.negative,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _MarketSnapshotSection extends StatefulWidget {
  const _MarketSnapshotSection();

  @override
  State<_MarketSnapshotSection> createState() => _MarketSnapshotSectionState();
}

class _MarketSnapshotSectionState extends State<_MarketSnapshotSection> {
  late final Future<List<MarketNewsItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = MarketRepository().getHotNews(limit: 6);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MarketNewsItem>>(
      future: _future,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <MarketNewsItem>[];
        if (items.isEmpty) {
          return AppCard(
            padding: AppSpacing.allMd,
            child: Text(
              AppLocalizations.of(context)!.dashboardNoHotNews,
              style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
            ),
          );
        }
        return Column(
          children: items.take(4).map((news) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppCard(
                onTap: () => _openUrl(context, news),
                padding: AppSpacing.allMd,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 10,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            news.title,
                            style: AppTypography.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            news.summary?.isNotEmpty == true
                                ? news.summary!
                                : '${news.source} · ${_timeText(news.publishedAt)}',
                            style: AppTypography.caption,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (news.tickers.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              news.tickers.take(2).join(' · '),
                              style: AppTypography.meta.copyWith(color: AppColors.primary),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    const Icon(Icons.open_in_new_rounded, size: 16, color: AppColors.textSecondary),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Future<void> _openUrl(BuildContext context, MarketNewsItem news) async {
    final uri = Uri.tryParse(news.url);
    if (uri == null) return;
    await openInAppWebView(
      context,
      url: news.url,
      title: news.title,
    );
  }

  String _timeText(DateTime? dt) {
    if (dt == null) return '--';
    final t = dt.toLocal();
    return '${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}

