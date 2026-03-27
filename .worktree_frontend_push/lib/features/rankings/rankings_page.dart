import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/teachers_api.dart';
import '../../core/api_client.dart';
import '../../core/design/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../teachers/teacher_models.dart';
import '../teachers/teacher_public_page.dart';

class RankingsPage extends StatefulWidget {
  const RankingsPage({super.key});

  @override
  State<RankingsPage> createState() => _RankingsPageState();
}

class _RankingsPageState extends State<RankingsPage> {
  /// 用于重试时重新订阅 stream
  int _streamKey = 0;
  Stream<List<TeacherProfile>>? _cachedRankingsStream;

  Stream<List<TeacherProfile>> _rankingsStream() {
    if (!ApiClient.instance.isAvailable) {
      return Stream.value(<TeacherProfile>[]);
    }
    return TeachersApi.instance.watchRankings();
  }

  @override
  void initState() {
    super.initState();
    _cachedRankingsStream = _rankingsStream();
  }

  void _resetRankingsStream() {
    _cachedRankingsStream = _rankingsStream();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.navRankings),
      ),
      body: StreamBuilder<List<TeacherProfile>>(
        key: ValueKey<int>(_streamKey),
        stream: _cachedRankingsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildErrorAndRetry(
              context,
              snapshot.error,
              onRetry: () => setState(() {
                _resetRankingsStream();
                _streamKey++;
              }),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }
          final list = snapshot.data ?? const <TeacherProfile>[];
          final rankings = List<TeacherProfile>.from(list)
            ..sort((a, b) {
              final pa = (a.pnlMonth ?? 0).toDouble();
              final pb = (b.pnlMonth ?? 0).toDouble();
              return pb.compareTo(pa);
            });
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: rankings.length + 2,
            itemBuilder: (context, index) {
              if (index == 0) {
                return const _RankIntro();
              }
              if (index == 1) {
                return const _RankListTitle();
              }
              final rank = index - 1;
              final teacher = rankings[index - 2];
              final name = teacher.displayName?.trim().isNotEmpty == true
                  ? teacher.displayName!
                  : (teacher.realName?.trim().isNotEmpty == true
                      ? teacher.realName!
                      : 'Trader');
              final wins = teacher.wins ?? 0;
              final losses = teacher.losses ?? 0;
              final total = wins + losses;
              final winRatePct =
                  total > 0 ? (wins / total * 100).round() : 0;
              final isTopThree = rank <= 3;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: isTopThree
                    ? _TopThreeCard(
                        rank: rank,
                        name: name,
                        title: teacher.title?.trim().isNotEmpty == true
                            ? teacher.title!
                            : AppLocalizations.of(context)!.roleTrader,
                        avatarUrl: teacher.avatarUrl?.trim(),
                        wins: wins,
                        losses: losses,
                        winRatePct: winRatePct,
                        monthPnl: (teacher.pnlMonth ?? 0).toDouble(),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  TeacherPublicPage(teacherId: teacher.userId),
                            ),
                          );
                        },
                      )
                    : _RankingCard(
                        rank: rank,
                        name: name,
                        title: teacher.title?.trim().isNotEmpty == true
                            ? teacher.title!
                            : AppLocalizations.of(context)!.roleTrader,
                        avatarUrl: teacher.avatarUrl?.trim(),
                        wins: wins,
                        losses: losses,
                        winRatePct: winRatePct,
                        monthPnl: (teacher.pnlMonth ?? 0).toDouble(),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  TeacherPublicPage(teacherId: teacher.userId),
                            ),
                          );
                        },
                      ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildErrorAndRetry(
    BuildContext context,
    Object? error, {
    required VoidCallback onRetry,
  }) {
    final errStr = error?.toString() ?? '';
    final msg = errStr.contains('Operation not permitted') ||
            errStr.contains('Connection failed')
        ? AppLocalizations.of(context)!.networkNoConnection
        : AppLocalizations.of(context)!.networkTryAgain;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.cloudOff, size: 48, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text(
              msg,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(AppIcons.retry),
              label: Text(AppLocalizations.of(context)!.commonRetry),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatAmount(double value) {
  final prefix = value > 0 ? '+' : '';
  return '$prefix${value.toStringAsFixed(0)}';
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({
    required this.rank,
    required this.name,
    required this.title,
    this.avatarUrl,
    required this.wins,
    required this.losses,
    required this.winRatePct,
    required this.monthPnl,
    required this.onTap,
  });

  final int rank;
  final String name;
  final String title;
  final String? avatarUrl;
  final int wins;
  final int losses;
  final int winRatePct;
  final double monthPnl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl != null && avatarUrl!.trim().isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xFF111215),
          border: Border.all(
            color: const Color(0xFFD4AF37).withOpacity(0.4),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFFD4AF37),
                  backgroundImage: hasAvatar
                      ? NetworkImage(avatarUrl!.trim())
                      : null,
                  child: hasAvatar
                      ? null
                      : Text(
                          '$rank',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF111215),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
                if (hasAvatar)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Color(0xFFD4AF37),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$rank',
                        style: const TextStyle(
                          fontSize: 9,
                          color: Color(0xFF111215),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: const Color(0xFFD4AF37)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: const Color(0xFF9CA3AF),
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: _StatPill(label: AppLocalizations.of(context)!.featuredWins, value: '$wins'),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _StatPill(label: AppLocalizations.of(context)!.featuredLosses, value: '$losses'),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _StatPill(
                            label: AppLocalizations.of(context)!.featuredWinRate, value: '$winRatePct%'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _MonthPnlChip(value: monthPnl),
          ],
        ),
      ),
    );
  }
}

class _TopThreeCard extends StatelessWidget {
  const _TopThreeCard({
    required this.rank,
    required this.name,
    required this.title,
    this.avatarUrl,
    required this.wins,
    required this.losses,
    required this.winRatePct,
    required this.monthPnl,
    required this.onTap,
  });

  final int rank;
  final String name;
  final String title;
  final String? avatarUrl;
  final int wins;
  final int losses;
  final int winRatePct;
  final double monthPnl;
  final VoidCallback onTap;

  static const _rankColors = [
    Color(0xFFD4AF37), // 1 金
    Color(0xFFA8B2C1), // 2 银
    Color(0xFFCD7F32), // 3 铜
  ];

  @override
  Widget build(BuildContext context) {
    final rankColor = rank <= 3 ? _rankColors[rank - 1] : _rankColors[2];
    final hasAvatar =
        avatarUrl != null && avatarUrl!.trim().isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: rankColor.withOpacity(0.08),
          border: Border.all(color: rankColor.withOpacity(0.5), width: 0.8),
        ),
        child: Row(
          children: [
            _TopThreeRankBadge(rank: rank, color: rankColor),
            const SizedBox(width: 8),
            if (hasAvatar)
              CircleAvatar(
                radius: 16,
                backgroundColor: rankColor.withOpacity(0.3),
                backgroundImage: NetworkImage(avatarUrl!.trim()),
              )
            else
              CircleAvatar(
                radius: 16,
                backgroundColor: rankColor.withOpacity(0.25),
                child: Text(
                  name.isNotEmpty ? name[0] : '?',
                  style: TextStyle(
                    color: rankColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: rankColor,
                          fontWeight: FontWeight.w700,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: const Color(0xFF9CA3AF),
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      _StatPill(label: AppLocalizations.of(context)!.featuredWins, value: '$wins'),
                      _StatPill(label: AppLocalizations.of(context)!.featuredLosses, value: '$losses'),
                      _StatPill(label: AppLocalizations.of(context)!.featuredWinRate, value: '$winRatePct%'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _MonthPnlChip(value: monthPnl),
          ],
        ),
      ),
    );
  }
}

class _TopThreeRankBadge extends StatelessWidget {
  const _TopThreeRankBadge({required this.rank, required this.color});

  final int rank;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.2),
        border: Border.all(color: color, width: 1.2),
      ),
      alignment: Alignment.center,
      child: Text(
        '$rank',
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0C0E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.35), width: 0.3),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '$label $value',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 10),
        ),
      ),
    );
  }
}

class _MonthPnlChip extends StatelessWidget {
  const _MonthPnlChip({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final isProfit = value >= 0;
    final amountColor = isProfit
        ? const Color(0xFF22C55E)
        : const Color(0xFFEF4444);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: amountColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _formatAmount(value),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: amountColor,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
      ),
    );
  }
}

class _RankIntro extends StatelessWidget {
  const _RankIntro();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PromoCarousel(),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _IntroPill(icon: Icons.verified_outlined, text: AppLocalizations.of(context)!.rankingsMentorVerified),
            _IntroPill(icon: Icons.auto_graph, text: AppLocalizations.of(context)!.rankingsStrategyTraceable),
            _IntroPill(icon: Icons.groups_outlined, text: AppLocalizations.of(context)!.rankingsCommunitySupport),
          ],
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _RankListTitle extends StatelessWidget {
  const _RankListTitle();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Row(
        children: [
          Icon(Icons.emoji_events, color: const Color(0xFFD4AF37), size: 16),
          const SizedBox(width: 6),
          Text(
            l10n.rankingsMonthProfitRank,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFFE8D5A3),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.rankingsRealtimeTransparent,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6B6B70),
                  fontSize: 11,
                ),
          ),
        ],
      ),
    );
  }
}

class _PromoCarousel extends StatefulWidget {
  const _PromoCarousel();

  @override
  State<_PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<_PromoCarousel> {
  final PageController _controller = PageController(viewportFraction: 0.88);
  int _index = 0;
  late final Timer _timer;

  List<_PromoSlide> _slides(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return [
      _PromoSlide(
        title: l10n.rankingsPromo1Title,
        subtitle: l10n.rankingsPromo1Subtitle,
        gradient: const [Color(0xFF1A1625), Color(0xFF2D1B3D), Color(0xFF1A0F26)],
        accent: const Color(0xFFD4AF37),
      ),
      _PromoSlide(
        title: l10n.rankingsPromo2Title,
        subtitle: l10n.rankingsPromo2Subtitle,
        gradient: const [Color(0xFF0F1A1F), Color(0xFF1A2F2A), Color(0xFF0D1612)],
        accent: const Color(0xFF2E8B6E),
      ),
      _PromoSlide(
        title: l10n.rankingsPromo3Title,
        subtitle: l10n.rankingsPromo3Subtitle,
        gradient: const [Color(0xFF1F1510), Color(0xFF2A1F15), Color(0xFF1A120D)],
        accent: const Color(0xFFC9A227),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 168,
          child: PageView.builder(
            controller: _controller,
            itemCount: _slides(context).length,
            onPageChanged: (value) => setState(() => _index = value),
            itemBuilder: (context, index) {
              return _PromoCard(slide: _slides(context)[index]);
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _slides(context).length,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              margin: const EdgeInsets.symmetric(horizontal: 5),
              width: i == _index ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == _index
                    ? const Color(0xFFD4AF37)
                    : const Color(0xFF3D3D42),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final slides = _slides(context);
      final next = (_index + 1) % slides.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
      setState(() => _index = next);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _controller.dispose();
    super.dispose();
  }
}

class _PromoSlide {
  const _PromoSlide({
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.accent,
  });

  final String title;
  final String subtitle;
  final List<Color> gradient;
  final Color accent;
}

class _PromoCard extends StatelessWidget {
  const _PromoCard({required this.slide});

  final _PromoSlide slide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: slide.accent.withOpacity(0.12),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: slide.gradient,
          ),
          border: Border.all(
            color: slide.accent.withOpacity(0.35),
            width: 0.8,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  slide.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: const Color(0xFFF5F5F5),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        height: 1.25,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  slide.subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFB8B8BC),
                        height: 1.4,
                        fontSize: 13,
                      ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Container(
                      height: 3,
                      width: 28,
                      decoration: BoxDecoration(
                        color: slide.accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(context)!.rankingsLearnMore,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: slide.accent,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IntroPill extends StatelessWidget {
  const _IntroPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111215),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD4AF37), width: 0.3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFFD4AF37)),
          const SizedBox(width: 8),
          Text(text, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}
