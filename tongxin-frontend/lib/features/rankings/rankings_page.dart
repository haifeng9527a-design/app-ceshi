import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/app_config_service.dart';
import '../../core/design/design_tokens.dart';
import '../../core/layout_mode.dart';
import '../../l10n/app_localizations.dart';
import '../teachers/teacher_models.dart';
import '../teachers/teacher_public_page.dart';
import '../teachers/teacher_repository.dart';

enum _RankingBoardType { allTime, weekly, monthly, quarterly, yearly }

class RankingsPage extends StatefulWidget {
  const RankingsPage({super.key});

  @override
  State<RankingsPage> createState() => _RankingsPageState();
}

class _RankingsPageState extends State<RankingsPage> {
  /// 用于重试时重新订阅 stream
  int _streamKey = 0;
  Stream<List<TeacherProfile>>? _cachedRankingsStream;
  final _repository = TeacherRepository();
  _RankingBoardType _boardType = _RankingBoardType.allTime;
  List<_RankingsContentCard> _introCards = const [];
  Timer? _cardsRefreshTimer;
  String _cardsHash = '';

  Future<void> _refreshRankingsContent() async {
    if (!ApiClient.instance.isAvailable) {
      await AppConfigService.instance.fetchAndCache();
      if (!mounted) return;
      setState(() {
        _introCards = _fallbackCardsFromConfig();
      });
      return;
    }
    try {
      final resp = await ApiClient.instance.get('api/rankings/content');
      if (resp.statusCode != 200) {
        throw StateError('load rankings content failed: ${resp.statusCode}');
      }
      final map = jsonDecode(resp.body) as Map<String, dynamic>;
      final rows = (map['cards'] as List<dynamic>? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList()
        ..sort((a, b) {
          final left = (a['sort_order'] as num?)?.toInt() ??
              int.tryParse(a['sort_order']?.toString() ?? '') ??
              0;
          final right = (b['sort_order'] as num?)?.toInt() ??
              int.tryParse(b['sort_order']?.toString() ?? '') ??
              0;
          return left.compareTo(right);
        });
      final cards = rows
          .map((row) => _RankingsContentCard(
                key: row['card_key']?.toString() ?? '',
                title: row['title']?.toString().trim() ?? '',
                summary: row['summary']?.toString().trim() ?? '',
                detail: row['detail']?.toString().trim() ?? '',
                extraLink: row['extra_link']?.toString().trim(),
              ))
          .where((c) => c.title.isNotEmpty && c.summary.isNotEmpty)
          .toList();
      final nextCards =
          cards.isNotEmpty ? cards : _fallbackCardsFromConfig();
      final nextHash = jsonEncode(nextCards.map((e) => e.toMap()).toList());
      if (!mounted) return;
      if (nextHash != _cardsHash) {
        setState(() {
          _cardsHash = nextHash;
          _introCards = nextCards;
        });
      }
    } catch (_) {
      await AppConfigService.instance.fetchAndCache();
      if (!mounted) return;
      final fallback = _fallbackCardsFromConfig();
      final nextHash = jsonEncode(fallback.map((e) => e.toMap()).toList());
      if (nextHash != _cardsHash) {
        setState(() {
          _cardsHash = nextHash;
          _introCards = fallback;
        });
      }
    }
  }

  Stream<List<TeacherProfile>> _rankingsStream() {
    if (!ApiClient.instance.isAvailable) {
      return Stream.value(<TeacherProfile>[]);
    }
    return _repository.watchRealRankings();
  }

  @override
  void initState() {
    super.initState();
    _cachedRankingsStream = _rankingsStream();
    _refreshRankingsContent();
    _cardsRefreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshRankingsContent(),
    );
  }

  @override
  void dispose() {
    _cardsRefreshTimer?.cancel();
    super.dispose();
  }

  void _resetRankingsStream() {
    _cachedRankingsStream = _rankingsStream();
  }

  String _boardTitle(BuildContext context, _RankingBoardType type) {
    final l10n = AppLocalizations.of(context)!;
    switch (type) {
      case _RankingBoardType.weekly:
        return l10n.rankingsBoardWeekly;
      case _RankingBoardType.monthly:
        return l10n.rankingsBoardMonthly;
      case _RankingBoardType.quarterly:
        return l10n.rankingsBoardQuarterly;
      case _RankingBoardType.yearly:
        return l10n.rankingsBoardYearly;
      case _RankingBoardType.allTime:
        return l10n.rankingsBoardAllTime;
    }
  }

  double _boardScore(TeacherProfile teacher, _RankingBoardType type) {
    switch (type) {
      case _RankingBoardType.weekly:
        return (teacher.pnlWeek ?? 0).toDouble();
      case _RankingBoardType.monthly:
        return (teacher.pnlMonth ?? 0).toDouble();
      case _RankingBoardType.quarterly:
        return (teacher.pnlQuarter ?? 0).toDouble();
      case _RankingBoardType.yearly:
        return (teacher.pnlYear ?? 0).toDouble();
      case _RankingBoardType.allTime:
        return (teacher.pnlTotal ?? 0).toDouble();
    }
  }

  List<TeacherProfile> _top10ByBoard(List<TeacherProfile> source) {
    if (source.length <= 10) return source;
    return source.take(10).toList();
  }

  String _teacherName(BuildContext context, TeacherProfile teacher) {
    if (teacher.displayName?.trim().isNotEmpty == true) {
      return teacher.displayName!;
    }
    if (teacher.realName?.trim().isNotEmpty == true) {
      return teacher.realName!;
    }
    return AppLocalizations.of(context)!.roleTrader;
  }

  _RankingViewModel _viewModelFor(
    BuildContext context,
    TeacherProfile teacher,
    int rank,
  ) {
    final wins = teacher.wins ?? 0;
    final losses = teacher.losses ?? 0;
    final total = wins + losses;
    final winRatePct = total > 0 ? (wins / total * 100).round() : 0;
    return _RankingViewModel(
      rank: rank,
      teacherId: teacher.userId,
      name: _teacherName(context, teacher),
      title: teacher.title?.trim().isNotEmpty == true
          ? teacher.title!
          : AppLocalizations.of(context)!.roleTrader,
      avatarUrl: teacher.avatarUrl?.trim(),
      wins: wins,
      losses: losses,
      winRatePct: winRatePct,
      score: _boardScore(teacher, _boardType),
    );
  }

  void _openTeacher(String teacherId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeacherPublicPage(teacherId: teacherId),
      ),
    );
  }

  Widget _buildMobileRankings(
    BuildContext context,
    List<TeacherProfile> rankings,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: rankings.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _RankIntro(
            cards: _introCards,
            boardType: _boardType,
            onChanged: (next) => setState(() => _boardType = next),
            boardTitleBuilder: (type) => _boardTitle(context, type),
          );
        }
        if (index == 1) {
          return _RankListTitle(
            title:
                '${_boardTitle(context, _boardType)} · ${AppLocalizations.of(context)!.rankingsTop10}',
          );
        }
        final rank = index - 1;
        final teacher = rankings[index - 2];
        final item = _viewModelFor(context, teacher, rank);
        final isTopThree = rank <= 3;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: isTopThree
              ? _TopThreeCard(
                  rank: item.rank,
                  name: item.name,
                  title: item.title,
                  avatarUrl: item.avatarUrl,
                  wins: item.wins,
                  losses: item.losses,
                  winRatePct: item.winRatePct,
                  monthPnl: item.score,
                  onTap: () => _openTeacher(item.teacherId),
                )
              : _RankingCard(
                  rank: item.rank,
                  name: item.name,
                  title: item.title,
                  avatarUrl: item.avatarUrl,
                  wins: item.wins,
                  losses: item.losses,
                  winRatePct: item.winRatePct,
                  monthPnl: item.score,
                  onTap: () => _openTeacher(item.teacherId),
                ),
        );
      },
    );
  }

  Widget _buildDesktopRankings(
    BuildContext context,
    List<TeacherProfile> rankings,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final items = [
      for (var i = 0; i < rankings.length; i++)
        _viewModelFor(context, rankings[i], i + 1),
    ];
    final boardTitle = _boardTitle(context, _boardType);
    final heroCard = _introCards.isNotEmpty ? _introCards.first : null;
    final sideCards = _introCards.skip(1).take(2).toList();
    final leader = items.isNotEmpty ? items.first : null;
    final totalWins = items.fold<int>(0, (sum, item) => sum + item.wins);
    final avgWinRate = items.isEmpty
        ? 0
        : items.fold<int>(0, (sum, item) => sum + item.winRatePct) ~/ items.length;

    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.scaffold),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1360),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DesktopRankingsHero(
                  title: boardTitle,
                  summary: heroCard?.summary ?? l10n.rankingsRealtimeTransparent,
                  detail: heroCard?.detail ?? '',
                  leaderName: leader?.name ?? '--',
                  leaderTitle: leader?.title ?? l10n.roleTrader,
                  leaderAvatarUrl: leader?.avatarUrl,
                  totalParticipants: items.length,
                  avgWinRate: avgWinRate,
                  totalWins: totalWins,
                  boardType: _boardType,
                  onChanged: (next) => setState(() => _boardType = next),
                  boardTitleBuilder: (type) => _boardTitle(context, type),
                ),
                if (sideCards.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      for (var i = 0; i < sideCards.length; i++) ...[
                        Expanded(
                          child: _DesktopInsightCard(card: sideCards[i]),
                        ),
                        if (i != sideCards.length - 1)
                          const SizedBox(width: AppSpacing.md),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                Text(
                  '$boardTitle · ${l10n.rankingsTop10}',
                  style: AppTypography.title.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '更适合网页端的展示模版：上方强调榜单摘要，下方聚焦核心席位和完整榜单。',
                  style: AppTypography.bodySecondary,
                ),
                const SizedBox(height: AppSpacing.lg),
                if (items.isEmpty)
                  const _DesktopEmptyState()
                else ...[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return _DesktopPodiumSection(
                        items: items.take(3).toList(),
                        onTap: _openTeacher,
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _DesktopLeaderboardSection(
                    title: boardTitle,
                    items: items,
                    onTap: _openTeacher,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final useDesktopLayout = LayoutMode.useDesktopLikeLayout(context);
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
          final rankings = _top10ByBoard(snapshot.data ?? const <TeacherProfile>[]);
          return useDesktopLayout
              ? _buildDesktopRankings(context, rankings)
              : _buildMobileRankings(context, rankings);
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
            const Icon(AppIcons.cloudOff,
                size: 48, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text(
              msg,
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 14),
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

  List<_RankingsContentCard> _fallbackCardsFromConfig() {
    final config = AppConfigService.instance;
    return [
      _RankingsContentCard(
        key: 'intro',
        title: config.rankingsIntroTitle,
        summary: config.rankingsIntroSummary,
        detail: config.rankingsIntroDetail,
      ),
      _RankingsContentCard(
        key: 'signup',
        title: config.rankingsSignupTitle,
        summary: config.rankingsSignupSummary,
        detail: config.rankingsSignupDetail,
        extraLink: config.rankingsSignupEntryUrl,
      ),
      _RankingsContentCard(
        key: 'activity',
        title: config.rankingsActivityTitle,
        summary: config.rankingsActivitySummary,
        detail: config.rankingsActivityDetail,
      ),
    ];
  }
}

class _RankingsContentCard {
  const _RankingsContentCard({
    required this.key,
    required this.title,
    required this.summary,
    required this.detail,
    this.extraLink,
  });

  final String key;
  final String title;
  final String summary;
  final String detail;
  final String? extraLink;

  Map<String, dynamic> toMap() => {
        'key': key,
        'title': title,
        'summary': summary,
        'detail': detail,
        'extraLink': extraLink,
      };
}

class _RankingViewModel {
  const _RankingViewModel({
    required this.rank,
    required this.teacherId,
    required this.name,
    required this.title,
    required this.avatarUrl,
    required this.wins,
    required this.losses,
    required this.winRatePct,
    required this.score,
  });

  final int rank;
  final String teacherId;
  final String name;
  final String title;
  final String? avatarUrl;
  final int wins;
  final int losses;
  final int winRatePct;
  final double score;
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
                  backgroundImage:
                      hasAvatar ? NetworkImage(avatarUrl!.trim()) : null,
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
                        child: _StatPill(
                            label: AppLocalizations.of(context)!.featuredWins,
                            value: '$wins'),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _StatPill(
                            label: AppLocalizations.of(context)!.featuredLosses,
                            value: '$losses'),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _StatPill(
                            label:
                                AppLocalizations.of(context)!.featuredWinRate,
                            value: '$winRatePct%'),
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
    final hasAvatar = avatarUrl != null && avatarUrl!.trim().isNotEmpty;
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
                      _StatPill(
                          label: AppLocalizations.of(context)!.featuredWins,
                          value: '$wins'),
                      _StatPill(
                          label: AppLocalizations.of(context)!.featuredLosses,
                          value: '$losses'),
                      _StatPill(
                          label: AppLocalizations.of(context)!.featuredWinRate,
                          value: '$winRatePct%'),
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
        border: Border.all(
            color: const Color(0xFFD4AF37).withOpacity(0.35), width: 0.3),
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
    final amountColor =
        isProfit ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
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
  const _RankIntro({
    required this.cards,
    required this.boardType,
    required this.onChanged,
    required this.boardTitleBuilder,
  });

  final List<_RankingsContentCard> cards;
  final _RankingBoardType boardType;
  final ValueChanged<_RankingBoardType> onChanged;
  final String Function(_RankingBoardType) boardTitleBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RankIntroConfigCards(
          cards: cards,
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _RankingBoardType.values.map((type) {
              final selected = type == boardType;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(boardTitleBuilder(type)),
                  selected: selected,
                  onSelected: (_) => onChanged(type),
                  selectedColor: const Color(0xFFD4AF37).withOpacity(0.2),
                  backgroundColor: const Color(0xFF111215),
                  side: BorderSide(
                    color: selected
                        ? const Color(0xFFD4AF37)
                        : const Color(0xFF30363D),
                    width: selected ? 1.0 : 0.6,
                  ),
                  labelStyle: TextStyle(
                    color: selected
                        ? const Color(0xFFD4AF37)
                        : const Color(0xFF9CA3AF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _RankIntroConfigCards extends StatefulWidget {
  const _RankIntroConfigCards({
    required this.cards,
  });

  final List<_RankingsContentCard> cards;

  @override
  State<_RankIntroConfigCards> createState() => _RankIntroConfigCardsState();
}

class _RankIntroConfigCardsState extends State<_RankIntroConfigCards> {
  late final PageController _controller;
  late final Timer _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.96);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final count = _items(context).length;
      if (count <= 1) return;
      final next = (_index + 1) % count;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 420),
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

  List<_IntroConfigItem> _items(BuildContext context) {
    final source = widget.cards;
    if (source.isEmpty) return const [];
    const accents = [
      Color(0xFFD4AF37),
      Color(0xFF4F9D8A),
      Color(0xFF7A87D8),
      Color(0xFFEF9F4A),
      Color(0xFFCC78E6),
    ];
    const icons = [
      Icons.emoji_events_outlined,
      Icons.how_to_reg_outlined,
      Icons.campaign_outlined,
      Icons.star_border_outlined,
      Icons.auto_awesome_outlined,
    ];
    return source.asMap().entries.map((entry) {
      final idx = entry.key;
      final card = entry.value;
      final extraLink = (card.extraLink ?? '').trim();
      final content = extraLink.isEmpty
          ? card.detail
          : '${card.detail}\n\n${AppLocalizations.of(context)!.profileLinkPrefix}\n$extraLink';
      return _IntroConfigItem(
        title: card.title,
        summary: card.summary,
        accent: accents[idx % accents.length],
        icon: icons[idx % icons.length],
        onLearnMore: () => _showInfoDialog(
          context: context,
          title: card.title,
          content: content,
          extraActionLabel: extraLink.isEmpty
              ? null
              : AppLocalizations.of(context)!.groupCopyInviteLink,
          onExtraAction: extraLink.isEmpty
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: extraLink));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppLocalizations.of(context)!.groupLinkCopied),
                      ),
                    );
                  }
                },
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items(context);
    return Column(
      children: [
        SizedBox(
          height: 152,
          child: PageView.builder(
            controller: _controller,
            itemCount: items.length,
            onPageChanged: (value) => setState(() => _index = value),
            itemBuilder: (context, i) {
              final item = items[i];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _InfoConfigCard(
                  title: item.title,
                  summary: item.summary,
                  accent: item.accent,
                  icon: item.icon,
                  onLearnMore: item.onLearnMore,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            items.length,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == _index ? 18 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == _index
                    ? const Color(0xFFD4AF37)
                    : const Color(0xFF3D3D42),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _IntroConfigItem {
  const _IntroConfigItem({
    required this.title,
    required this.summary,
    required this.accent,
    required this.icon,
    required this.onLearnMore,
  });

  final String title;
  final String summary;
  final Color accent;
  final IconData icon;
  final VoidCallback onLearnMore;
}

class _InfoConfigCard extends StatelessWidget {
  const _InfoConfigCard({
    required this.title,
    required this.summary,
    required this.accent,
    required this.icon,
    required this.onLearnMore,
  });

  final String title;
  final String summary;
  final Color accent;
  final IconData icon;
  final VoidCallback onLearnMore;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111215),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: const Color(0xFFE8D5A3),
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            summary,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFB8B8BC),
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: onLearnMore,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 3,
                    width: 24,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppLocalizations.of(context)!.rankingsLearnMore,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w600,
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

Future<void> _showInfoDialog({
  required BuildContext context,
  required String title,
  required String content,
  String? extraActionLabel,
  Future<void> Function()? onExtraAction,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Text(
          content,
          style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(height: 1.55),
        ),
      ),
      actions: [
        if (extraActionLabel != null && onExtraAction != null)
          TextButton(
            onPressed: () async {
              await onExtraAction();
            },
            child: Text(extraActionLabel),
          ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(AppLocalizations.of(context)!.groupClose),
        ),
      ],
    ),
  );
}

class _RankListTitle extends StatelessWidget {
  const _RankListTitle({required this.title});

  final String title;

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
            title,
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
        gradient: const [
          Color(0xFF1A1625),
          Color(0xFF2D1B3D),
          Color(0xFF1A0F26)
        ],
        accent: const Color(0xFFD4AF37),
      ),
      _PromoSlide(
        title: l10n.rankingsPromo2Title,
        subtitle: l10n.rankingsPromo2Subtitle,
        gradient: const [
          Color(0xFF0F1A1F),
          Color(0xFF1A2F2A),
          Color(0xFF0D1612)
        ],
        accent: const Color(0xFF2E8B6E),
      ),
      _PromoSlide(
        title: l10n.rankingsPromo3Title,
        subtitle: l10n.rankingsPromo3Subtitle,
        gradient: const [
          Color(0xFF1F1510),
          Color(0xFF2A1F15),
          Color(0xFF1A120D)
        ],
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

class _DesktopRankingsHero extends StatelessWidget {
  const _DesktopRankingsHero({
    required this.title,
    required this.summary,
    required this.detail,
    required this.leaderName,
    required this.leaderTitle,
    required this.leaderAvatarUrl,
    required this.totalParticipants,
    required this.avgWinRate,
    required this.totalWins,
    required this.boardType,
    required this.onChanged,
    required this.boardTitleBuilder,
  });

  final String title;
  final String summary;
  final String detail;
  final String leaderName;
  final String leaderTitle;
  final String? leaderAvatarUrl;
  final int totalParticipants;
  final int avgWinRate;
  final int totalWins;
  final _RankingBoardType boardType;
  final ValueChanged<_RankingBoardType> onChanged;
  final String Function(_RankingBoardType) boardTitleBuilder;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 36,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF12100B),
                      const Color(0xFF0A0A0A),
                      const Color(0xFF040404),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -40,
              left: -20,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.08),
                ),
              ),
            ),
            Positioned(
              right: -40,
              top: 30,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF6E5417).withValues(alpha: 0.12),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.34),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: AppColors.primary.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                'BLACK GOLD RANKING',
                                style: AppTypography.meta.copyWith(
                                  color: const Color(0xFFF0D78A),
                                  letterSpacing: 0.9,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              title,
                              style: AppTypography.title.copyWith(
                                fontSize: 36,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFFFF4D6),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              summary,
                              style: AppTypography.body.copyWith(
                                color: const Color(0xFFD7C89B),
                                height: 1.55,
                              ),
                            ),
                            if (detail.trim().isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                detail,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.caption.copyWith(
                                  color: const Color(0xFF9F9577),
                                  height: 1.55,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xl),
                      Container(
                        width: 280,
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFF17130A),
                              const Color(0xFF0D0C09),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.24),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.24),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '榜首观察',
                              style: AppTypography.meta.copyWith(
                                color: const Color(0xFFE7C86C),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.primary.withValues(alpha: 0.4),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary.withValues(alpha: 0.12),
                                        blurRadius: 14,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: _DesktopAvatar(
                                    name: leaderName,
                                    avatarUrl: leaderAvatarUrl,
                                    size: 68,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        leaderName,
                                        style: AppTypography.subtitle.copyWith(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFFFFF1C7),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        leaderTitle,
                                        style: AppTypography.caption.copyWith(
                                          color: const Color(0xFFCDBA84),
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Container(
                              width: 42,
                              height: 3,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              '突出榜首老师的标签、风格与近况，这一块要像网页端运营位。',
                              style: AppTypography.caption.copyWith(
                                color: const Color(0xFFC5B48A),
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.md,
                    children: [
                      _DesktopMetricCard(
                        label: '参与人数',
                        value: '$totalParticipants',
                        helper: '当前展示 Top 10',
                      ),
                      _DesktopMetricCard(
                        label: '平均胜率',
                        value: '$avgWinRate%',
                        helper: '基于当前榜单样本',
                      ),
                      _DesktopMetricCard(
                        label: '总胜场',
                        value: '$totalWins',
                        helper: '榜单活跃度参考',
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: _RankingBoardType.values.map((type) {
                      final selected = type == boardType;
                      return ChoiceChip(
                        label: Text(boardTitleBuilder(type)),
                        selected: selected,
                        onSelected: (_) => onChanged(type),
                        selectedColor: AppColors.primary.withValues(alpha: 0.18),
                        backgroundColor: const Color(0xFF121212),
                        side: BorderSide(
                          color: selected
                              ? AppColors.primary
                              : AppColors.primary.withValues(alpha: 0.14),
                        ),
                        labelStyle: AppTypography.bodySecondary.copyWith(
                          color: selected
                              ? const Color(0xFFFFE6A0)
                              : const Color(0xFFAA9D78),
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopMetricCard extends StatelessWidget {
  const _DesktopMetricCard({
    required this.label,
    required this.value,
    required this.helper,
  });

  final String label;
  final String value;
  final String helper;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF16120B),
            const Color(0xFF0B0B0A),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.meta.copyWith(color: const Color(0xFFD7B968)),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: AppTypography.data.copyWith(
              fontSize: 28,
              color: const Color(0xFFFFE19A),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            helper,
            style: AppTypography.caption.copyWith(
              color: const Color(0xFFA69773),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopInsightCard extends StatelessWidget {
  const _DesktopInsightCard({required this.card});

  final _RankingsContentCard card;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF14110C),
            const Color(0xFF0A0A09),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 3,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            card.title,
            style: AppTypography.subtitle.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFFFFEBC0),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            card.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.body.copyWith(
              color: const Color(0xFFC5B48A),
              height: 1.55,
            ),
          ),
          if (card.extraLink?.trim().isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              card.extraLink!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(
                color: const Color(0xFFFFD772),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DesktopPodiumSection extends StatelessWidget {
  const _DesktopPodiumSection({
    required this.items,
    required this.onTap,
  });

  final List<_RankingViewModel> items;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final byRank = {
      for (final item in items) item.rank: item,
    };
    final ordered = [
      if (byRank[2] != null) byRank[2]!,
      if (byRank[1] != null) byRank[1]!,
      if (byRank[3] != null) byRank[3]!,
    ];
    final topPadding = <int, double>{1: 0, 2: 44, 3: 64};

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(36),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF171109),
            Color(0xFF0D0B08),
            Color(0xFF080808),
          ],
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            left: -80,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.05),
              ),
            ),
          ),
          Positioned(
            top: -80,
            right: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.04),
              ),
            ),
          ),
          Column(
            children: [
              Text(
                '冠军席位',
                textAlign: TextAlign.center,
                style: AppTypography.title.copyWith(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFFFF1CF),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'TOP 3 PODIUM',
                style: AppTypography.meta.copyWith(
                  color: const Color(0xFFE0C176),
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '把前三名收成一个高级模块，中间主卡更强，两侧陪衬更稳。',
                textAlign: TextAlign.center,
                style: AppTypography.bodySecondary.copyWith(
                  color: const Color(0xFFC8B68B),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < ordered.length; i++) ...[
                    Expanded(
                      flex: ordered[i].rank == 1 ? 5 : 4,
                      child: Padding(
                        padding: EdgeInsets.only(top: topPadding[ordered[i].rank] ?? 0),
                        child: _DesktopTopCard(
                          item: ordered[i],
                          onTap: () => onTap(ordered[i].teacherId),
                        ),
                      ),
                    ),
                    if (i != ordered.length - 1)
                      const SizedBox(width: AppSpacing.md),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DesktopTopCard extends StatelessWidget {
  const _DesktopTopCard({
    required this.item,
    required this.onTap,
  });

  final _RankingViewModel item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scoreColor =
        item.score >= 0 ? AppColors.positive : AppColors.negative;
    final palette = _DesktopPodiumPalette.forRank(item.rank);
    final isChampion = item.rank == 1;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: palette.glow.withValues(alpha: isChampion ? 0.18 : 0.1),
              blurRadius: isChampion ? 28 : 18,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(140),
                  topRight: Radius.circular(140),
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: palette.background,
                ),
                border: Border.all(color: palette.border, width: 1.15),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DesktopPodiumBadge(
                      rank: item.rank,
                      title: palette.title,
                      color: palette.badge,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      palette.subtitle,
                      style: AppTypography.meta.copyWith(
                        color: palette.titleColor.withValues(alpha: 0.86),
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Container(
                      width: isChampion ? 110 : 92,
                      height: isChampion ? 110 : 92,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(
                          colors: [
                            palette.badge.withValues(alpha: 0.95),
                            Colors.white.withValues(alpha: 0.65),
                            palette.badge.withValues(alpha: 0.95),
                          ],
                        ),
                      ),
                      child: _DesktopAvatar(
                        name: item.name,
                        avatarUrl: item.avatarUrl,
                        size: isChampion ? 102 : 84,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTypography.subtitle.copyWith(
                        fontSize: isChampion ? 26 : 22,
                        fontWeight: FontWeight.w800,
                        color: palette.titleColor,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySecondary.copyWith(
                        color: palette.subtleColor,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: scoreColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: scoreColor.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Text(
                        _formatAmount(item.score),
                        style: AppTypography.body.copyWith(
                          color: scoreColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: _DesktopPodiumStat(
                            label: '胜率',
                            value: '${item.winRatePct}%',
                            accent: palette.badge,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: _DesktopPodiumStat(
                            label: '战绩',
                            value: '${item.wins}/${item.losses}',
                            accent: palette.badge,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: palette.badge.withValues(alpha: 0.12),
                ),
              ),
              child: Text(
                palette.footer,
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(
                  color: palette.subtleColor,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopPodiumStat extends StatelessWidget {
  const _DesktopPodiumStat({
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
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.04),
            Colors.white.withValues(alpha: 0.01),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: AppTypography.meta.copyWith(color: accent.withValues(alpha: 0.9)),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: AppTypography.dataSmall.copyWith(
              fontSize: 18,
              color: const Color(0xFFFFF0CF),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopPodiumBadge extends StatelessWidget {
  const _DesktopPodiumBadge({
    required this.rank,
    required this.title,
    required this.color,
  });

  final int rank;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF090909),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.36)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.16),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium_rounded, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            '$rank  $title',
            style: AppTypography.meta.copyWith(
              color: color,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopPodiumPalette {
  const _DesktopPodiumPalette({
    required this.title,
    required this.subtitle,
    required this.footer,
    required this.background,
    required this.badge,
    required this.border,
    required this.glow,
    required this.titleColor,
    required this.subtleColor,
  });

  final String title;
  final String subtitle;
  final String footer;
  final List<Color> background;
  final Color badge;
  final Color border;
  final Color glow;
  final Color titleColor;
  final Color subtleColor;

  static _DesktopPodiumPalette forRank(int rank) {
    switch (rank) {
      case 1:
        return const _DesktopPodiumPalette(
          title: '冠军',
          subtitle: '冠军主位',
          footer: '主视觉核心位',
          background: [
            Color(0xFF241908),
            Color(0xFF181107),
            Color(0xFF0D0A06),
          ],
          badge: Color(0xFFF0C35A),
          border: Color(0x66D4AF37),
          glow: Color(0xFFD4AF37),
          titleColor: Color(0xFFFFF1C8),
          subtleColor: Color(0xFFD7C38A),
        );
      case 2:
        return const _DesktopPodiumPalette(
          title: '亚军',
          subtitle: '亚军席位',
          footer: '克制稳重的次席位',
          background: [
            Color(0xFF1B1D22),
            Color(0xFF121317),
            Color(0xFF090A0C),
          ],
          badge: Color(0xFFB9C0CC),
          border: Color(0x40B9C0CC),
          glow: Color(0xFF8B949E),
          titleColor: Color(0xFFF2F4F8),
          subtleColor: Color(0xFFBAC0CA),
        );
      default:
        return const _DesktopPodiumPalette(
          title: '季军',
          subtitle: '季军席位',
          footer: '补足层次的第三席',
          background: [
            Color(0xFF24160F),
            Color(0xFF16100C),
            Color(0xFF090706),
          ],
          badge: Color(0xFFC98A56),
          border: Color(0x40C98A56),
          glow: Color(0xFF9A5E36),
          titleColor: Color(0xFFF9E3D3),
          subtleColor: Color(0xFFD4B199),
        );
    }
  }
}

class _DesktopLeaderboardSection extends StatelessWidget {
  const _DesktopLeaderboardSection({
    required this.title,
    required this.items,
    required this.onTap,
  });

  final String title;
  final List<_RankingViewModel> items;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF12100C),
            const Color(0xFF080808),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '完整榜单',
                style: AppTypography.subtitle.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFFFEDBE),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                title,
                style: AppTypography.bodySecondary.copyWith(
                  color: const Color(0xFFD0BE91),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const _DesktopLeaderboardHeader(),
          const SizedBox(height: AppSpacing.sm),
          for (final item in items) ...[
            _DesktopLeaderboardRow(
              item: item,
              onTap: () => onTap(item.teacherId),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _DesktopLeaderboardHeader extends StatelessWidget {
  const _DesktopLeaderboardHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          SizedBox(
            width: 68,
            child: Text(
              '排名',
              style: AppTypography.meta.copyWith(color: const Color(0xFFBCA86A)),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              '交易员',
              style: AppTypography.meta.copyWith(color: const Color(0xFFBCA86A)),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '胜率',
              style: AppTypography.meta.copyWith(color: const Color(0xFFBCA86A)),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '战绩',
              style: AppTypography.meta.copyWith(color: const Color(0xFFBCA86A)),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '收益',
                style: AppTypography.meta.copyWith(color: const Color(0xFFBCA86A)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopLeaderboardRow extends StatelessWidget {
  const _DesktopLeaderboardRow({
    required this.item,
    required this.onTap,
  });

  final _RankingViewModel item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scoreColor =
        item.score >= 0 ? AppColors.positive : AppColors.negative;
    final isTopRank = item.rank <= 3;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: isTopRank ? const Color(0xFF16120B) : const Color(0xFF101010),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isTopRank
                ? AppColors.primary.withValues(alpha: 0.18)
                : AppColors.primary.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 68,
              child: Text(
                '${item.rank}',
                style: AppTypography.dataSmall.copyWith(
                  color: item.rank <= 3
                      ? const Color(0xFFFFDB82)
                      : const Color(0xFFE6D8B1),
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  _DesktopAvatar(
                    name: item.name,
                    avatarUrl: item.avatarUrl,
                    size: 42,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.body.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFFFEFC5),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(
                            color: const Color(0xFFAA9D78),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                '${item.winRatePct}%',
                style: AppTypography.body.copyWith(
                  color: const Color(0xFFE9DDB8),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                '${item.wins}/${item.losses}',
                style: AppTypography.bodySecondary.copyWith(
                  color: const Color(0xFFB6A883),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _formatAmount(item.score),
                  style: AppTypography.dataSmall.copyWith(
                    color: scoreColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopAvatar extends StatelessWidget {
  const _DesktopAvatar({
    required this.name,
    required this.avatarUrl,
    required this.size,
  });

  final String name;
  final String? avatarUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl != null && avatarUrl!.trim().isNotEmpty;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFF1D180C),
      backgroundImage: hasAvatar ? NetworkImage(avatarUrl!.trim()) : null,
      child: hasAvatar
          ? null
          : Text(
              name.isEmpty ? '?' : name.substring(0, 1),
              style: AppTypography.body.copyWith(
                color: const Color(0xFFFFDF8B),
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

class _DesktopEmptyState extends StatelessWidget {
  const _DesktopEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF120F0A),
            const Color(0xFF080808),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.emoji_events_outlined,
            color: AppColors.primary.withValues(alpha: 0.9),
            size: 42,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '榜单数据加载中',
            style: AppTypography.subtitle.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFFFFEDBE),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '这个模版已经就位，等实时数据回来后会直接填入顶部卡片和下方榜单列表。',
            textAlign: TextAlign.center,
            style: AppTypography.bodySecondary.copyWith(
              height: 1.5,
              color: const Color(0xFFB7AA86),
            ),
          ),
        ],
      ),
    );
  }
}

