import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/design/design_tokens.dart';
import '../../core/layout_mode.dart';
import '../../core/models.dart' show Comment;
import '../../l10n/app_localizations.dart';
import '../auth/login_page.dart';
import '../../core/network_error_helper.dart';
import '../../ui/components/components.dart';
import '../home/featured_teacher_page.dart';
import '../messages/friends_repository.dart';
import '../strategies/strategy_dialog.dart';
import '../strategies/strategy_image_preview.dart';
import 'teacher_models.dart';
import 'teacher_repository.dart';

class TeacherPublicPage extends StatefulWidget {
  const TeacherPublicPage({
    super.key,
    required this.teacherId,
    this.isAlreadyFriend = false,
  });

  final String teacherId;
  /// 从聊天「查看个人资料」进入时传 true，已是好友则显示「发消息」而非「加好友」
  final bool isAlreadyFriend;

  static const Color _accent = AppColors.primary;
  static const Color _muted = AppColors.textTertiary;
  static const Color _surface = AppColors.surface2;

  @override
  State<TeacherPublicPage> createState() => _TeacherPublicPageState();
}

class _TeacherPublicPageState extends State<TeacherPublicPage> {
  late final TeacherRepository _repository;
  late Future<TeacherProfile?> _profileFuture;
  late Future<TeacherPnlMetrics?> _metricsFuture;
  late final Stream<List<TeacherStrategy>> _publishedStrategiesStream;
  late final Stream<List<TradeRecord>> _tradeRecordsStream;

  @override
  void initState() {
    super.initState();
    _repository = TeacherRepository();
    _profileFuture = _repository.fetchProfile(widget.teacherId);
    _metricsFuture = _repository.fetchPnlMetrics(widget.teacherId);
    _publishedStrategiesStream = _repository.watchPublishedStrategies(
      widget.teacherId,
    );
    _tradeRecordsStream = _repository
        .watchTradeRecords(widget.teacherId)
        .asBroadcastStream();
  }

  @override
  Widget build(BuildContext context) {
    final teacherId = widget.teacherId;
    final isAlreadyFriend = widget.isAlreadyFriend;
    final useDesktopLayout = LayoutMode.useDesktopLikeLayout(context);
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        final currentUserId = authSnapshot.data?.uid ?? '';
        final isOwner = currentUserId == teacherId;
        return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: TeacherPublicPage._accent,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          AppLocalizations.of(context)!.teachersProfileTitle,
          style: const TextStyle(
            color: TeacherPublicPage._accent,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: FutureBuilder<TeacherProfile?>(
        future: _profileFuture,
        builder: (context, snapshot) {
          final profile = snapshot.data;
          if (profile == null) {
            return Center(
              child: Text(
                AppLocalizations.of(context)!.teachersNoTeacherInfo,
                style: const TextStyle(color: TeacherPublicPage._muted),
              ),
            );
          }
          final isApproved = (profile.status ?? '') == 'approved';
          final listChildren = [
              _HeaderBlock(
                profile: profile,
                teacherId: teacherId,
                repository: _repository,
              ),
              const SizedBox(height: AppSpacing.lg),
              FutureBuilder<TeacherPnlMetrics?>(
                future: _metricsFuture,
                builder: (context, metricsSnapshot) {
                  final metrics =
                      metricsSnapshot.data ?? TeacherPnlMetrics.fromProfile(profile);
                  return _StatsBlock(profile: profile, metrics: metrics);
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              if (useDesktopLayout)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _SectionBlock(
                        title: AppLocalizations.of(context)!.teachersPersonalIntro,
                        child: _BioCard(
                          bio: profile.bio?.trim().isNotEmpty == true
                              ? profile.bio!
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: _SectionBlock(
                        title: AppLocalizations.of(context)!.teachersExpertiseProducts,
                        child: _SpecialtiesWrap(specialties: profile.specialties),
                      ),
                    ),
                  ],
                )
              else ...[
                _SectionBlock(
                  title: AppLocalizations.of(context)!.teachersPersonalIntro,
                  child: _BioCard(
                    bio: profile.bio?.trim().isNotEmpty == true
                        ? profile.bio!
                        : null,
                  ),
                ),
                _SectionBlock(
                  title: AppLocalizations.of(context)!.teachersExpertiseProducts,
                  child: _SpecialtiesWrap(specialties: profile.specialties),
                ),
              ],
              if (isApproved) ...[
                _SectionBlock(
                  title: (isOwner || isAlreadyFriend)
                      ? AppLocalizations.of(context)!.teachersStrategySection
                      : AppLocalizations.of(context)!.strategiesHistoryStrategies,
                  child: StreamBuilder<List<TeacherStrategy>>(
                    stream: _publishedStrategiesStream,
                    builder: (context, strategySnapshot) {
                      final allItems =
                          strategySnapshot.data ?? const <TeacherStrategy>[];
                      final canSeeTodayStrategy = isOwner || isAlreadyFriend;
                      final items = canSeeTodayStrategy
                          ? allItems
                          : allItems
                              .where((item) => !_isTodayStrategy(item.createdAt))
                              .toList();
                      if (items.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            AppLocalizations.of(context)!.teachersNoPublicStrategy,
                            style: const TextStyle(
                              color: TeacherPublicPage._muted,
                              fontSize: 14,
                            ),
                          ),
                        );
                      }
                      return Column(
                        children: items
                            .map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                                child: StreamBuilder<List<Comment>>(
                                  stream: _repository.watchStrategyComments(
                                    teacherId,
                                    item.id,
                                  ),
                                  builder: (context, commentSnapshot) {
                                    final comments =
                                        commentSnapshot.data ?? const <Comment>[];
                                    return _TeacherStrategyHistoryCard(
                                      item: item,
                                      comments: comments,
                                      teacherId: teacherId,
                                      currentUserId: currentUserId,
                                      repository: _repository,
                                    );
                                  },
                                ),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                ),
              ],
              if (isOwner && isApproved) ...[
                _SectionBlock(
                  title: AppLocalizations.of(context)!.teachersMyTradeRecords,
                  child: StreamBuilder<List<TradeRecord>>(
                    stream: _tradeRecordsStream,
                    builder: (context, recordSnapshot) {
                      final items =
                          recordSnapshot.data ?? const <TradeRecord>[];
                      if (items.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            AppLocalizations.of(context)!.teachersNoTradeRecords,
                            style: const TextStyle(
                              color: TeacherPublicPage._muted,
                              fontSize: 14,
                            ),
                          ),
                        );
                      }
                      return Column(
                        children: items
                            .map(
                              (item) => AppCard(
                                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                                padding: const EdgeInsets.all(AppSpacing.md - 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.symbol,
                                            style: const TextStyle(
                                              color: AppColors.textPrimary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          Text(
                                            '${item.side}  PnL: ${item.pnl}',
                                            style: const TextStyle(
                                                  color: TeacherPublicPage._muted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (item.attachmentUrl != null &&
                                        item.attachmentUrl!.isNotEmpty)
                                      IconButton(
                                        icon: const Icon(
                                          Icons.image_outlined,
                                          color: TeacherPublicPage._accent,
                                          size: 20,
                                        ),
                                        onPressed: () {
                                          showDialog(
                                            context: context,
                                            builder: (_) => Dialog(
                                              backgroundColor:
                                                  TeacherPublicPage._surface,
                                              child: Image.network(
                                                item.attachmentUrl!,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    if (item.tradeTime != null)
                                      Text(
                                        _formatDate(item.tradeTime!),
                                        style: const TextStyle(
                                          color: TeacherPublicPage._muted,
                                          fontSize: 11,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                ),
              ],
            ];
          return Column(
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: useDesktopLayout ? 1240 : 760,
                    ),
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        useDesktopLayout ? AppSpacing.xl : AppSpacing.md,
                        0,
                        useDesktopLayout ? AppSpacing.xl : AppSpacing.md,
                        isOwner ? AppSpacing.xl : AppSpacing.xxxl + AppSpacing.sm,
                      ),
                      children: listChildren,
                    ),
                  ),
                ),
              ),
              _BottomFollowBar(
                teacherId: teacherId,
                teacherDisplayName: (profile.displayName?.trim().isNotEmpty == true)
                    ? profile.displayName!
                    : (profile.realName?.trim().isNotEmpty == true
                        ? profile.realName!
                        : AppLocalizations.of(context)!.profileTeacher),
                currentUserId: currentUserId,
                isOwner: isOwner,
                isAlreadyFriend: isAlreadyFriend,
                repository: _repository,
                maxWidth: useDesktopLayout ? 1240 : 760,
              ),
            ],
          );
        },
      ),
    );
      },
    );
  }

  static String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  static bool _isTodayStrategy(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now().toLocal();
    return local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
  }
}

class _BottomFollowBar extends StatefulWidget {
  const _BottomFollowBar({
    required this.teacherId,
    required this.teacherDisplayName,
    required this.currentUserId,
    required this.isOwner,
    required this.repository,
    required this.maxWidth,
    this.isAlreadyFriend = false,
  });

  final String teacherId;
  final String teacherDisplayName;
  final String currentUserId;
  final bool isOwner;
  final TeacherRepository repository;
  final double maxWidth;
  final bool isAlreadyFriend;

  @override
  State<_BottomFollowBar> createState() => _BottomFollowBarState();
}

class _BottomFollowBarState extends State<_BottomFollowBar> {
  /// 点击加好友时若返回「已是好友」，则设为 true 以立即切换按钮
  bool? _overrideIsFriend;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return FutureBuilder<bool>(
      future: widget.currentUserId.isNotEmpty
          ? FriendsRepository().isFriend(userId: widget.currentUserId, friendId: widget.teacherId)
          : Future.value(false),
      builder: (context, friendSnapshot) {
        final isFriend = _overrideIsFriend ?? friendSnapshot.data ?? widget.isAlreadyFriend;
        return Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomPad),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(
              top: BorderSide(color: AppColors.primary.withValues(alpha: 0.12)),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: widget.maxWidth),
                child: widget.isOwner || isFriend
                ? SizedBox(
                    width: double.infinity,
                    child: AppButton(
                      onPressed: () {
                        if (widget.currentUserId.isEmpty) {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const LoginPage()),
                          );
                          return;
                        }
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => FeaturedTeacherPage(teacherId: widget.teacherId),
                          ),
                        );
                      },
                      label: AppLocalizations.of(context)!.teachersEnterStrategyCenter,
                    ),
                  )
                : SizedBox(
                    width: double.infinity,
                    child: AppButton(
                    onPressed: () async {
                      if (widget.currentUserId.isEmpty) {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                        );
                        return;
                      }
                      try {
                        await FriendsRepository().sendFriendRequest(
                          requesterId: widget.currentUserId,
                          receiverId: widget.teacherId,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(AppLocalizations.of(context)!.msgFriendRequestSent)),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          final msg = e.toString();
                          String displayMsg;
                          if (msg.contains('already_friends')) {
                            displayMsg = AppLocalizations.of(context)!.msgAlreadyFriends;
                            if (mounted) setState(() => _overrideIsFriend = true);
                          } else if (msg.contains('already_pending')) {
                            displayMsg = AppLocalizations.of(context)!.msgAlreadyPending;
                          } else {
                            displayMsg = NetworkErrorHelper.messageForUser(e, prefix: AppLocalizations.of(context)!.msgAddFriendFailed, l10n: AppLocalizations.of(context));
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(displayMsg)),
                          );
                        }
                      }
                    },
                    label: AppLocalizations.of(context)!.msgAddFriend,
                  ),
                ),
              ),
            ),
          ),
        );
        },
      );
  }
}

class _HeaderBlock extends StatelessWidget {
  const _HeaderBlock({
    required this.profile,
    required this.teacherId,
    required this.repository,
  });

  final TeacherProfile profile;
  final String teacherId;
  final TeacherRepository repository;

  @override
  Widget build(BuildContext context) {
    final useDesktopLayout = LayoutMode.useDesktopLikeLayout(context);
    final name = (profile.displayName?.trim().isNotEmpty == true)
        ? profile.displayName!
        : ((profile.realName?.trim().isNotEmpty == true)
            ? profile.realName!
            : AppLocalizations.of(context)!.profileTeacher);
    final signature = (profile.signature?.trim().isNotEmpty == true
            ? profile.signature
            : null) ??
        (profile.title?.trim().isNotEmpty == true ? profile.title! : null);
    final tags = (profile.tags ?? const <String>[])
        .where((e) => e.trim().isNotEmpty)
        .toList();

    Widget followerBadge() {
      return StreamBuilder<int>(
        stream: FriendsRepository().watchFriendCount(userId: teacherId),
        builder: (context, countSnapshot) {
          final count = countSnapshot.data ?? 0;
          return Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.scaffold.withValues(alpha: 0.94),
                  AppColors.surface.withValues(alpha: 0.72),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '关注',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count',
                  style: AppTypography.subtitle.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    Widget identityBlock() {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.surface.withValues(alpha: 0.82),
              AppColors.surfaceElevated.withValues(alpha: 0.68),
            ],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: useDesktopLayout
              ? MainAxisAlignment.spaceBetween
              : MainAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primary.withValues(alpha: 0.92),
                            AppColors.primaryDim.withValues(alpha: 0.72),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.16),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: useDesktopLayout ? 44 : 38,
                        backgroundColor: AppColors.surface,
                        backgroundImage: profile.avatarUrl?.trim().isNotEmpty == true
                            ? NetworkImage(profile.avatarUrl!.trim())
                            : null,
                        child: profile.avatarUrl?.trim().isNotEmpty == true
                            ? null
                            : Text(
                                name.isEmpty ? '?' : name[0],
                                style: const TextStyle(
                                  fontSize: 24,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: AppTypography.title.copyWith(
                              fontSize: useDesktopLayout ? 30 : 24,
                              fontWeight: FontWeight.w800,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            signature ?? AppLocalizations.of(context)!.teachersNoIntro,
                            style: AppTypography.body.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.6,
                            ),
                            maxLines: useDesktopLayout ? 3 : 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (useDesktopLayout) ...[
                      const SizedBox(width: AppSpacing.md),
                      followerBadge(),
                    ],
                  ],
                ),
                if (!useDesktopLayout) ...[
                  const SizedBox(height: AppSpacing.lg),
                  followerBadge(),
                ],
              ],
            ),
            if (tags.isNotEmpty) ...[
              SizedBox(height: useDesktopLayout ? AppSpacing.xl : AppSpacing.lg),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.scaffold.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: tags
                      .map(
                        (tag) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Text(
                            tag,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ],
        ),
      );
    }

    Widget factGrid() {
      final facts = [
        _ProfileFactCard(
          label: AppLocalizations.of(context)!.teachersYearsExperience,
          value: profile.yearsExperience != null ? '${profile.yearsExperience} 年' : null,
        ),
        _ProfileFactCard(
          label: AppLocalizations.of(context)!.teachersMainMarket,
          value: profile.markets,
        ),
        _ProfileFactCard(
          label: AppLocalizations.of(context)!.teachersTradingStyleShort,
          value: profile.style,
        ),
        _ProfileFactCard(
          label: AppLocalizations.of(context)!.teachersLicenseNoLabel,
          value: profile.licenseNo,
        ),
      ];

      return Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.surface.withValues(alpha: 0.78),
              AppColors.surfaceElevated.withValues(alpha: 0.58),
            ],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: facts[0]),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: facts[1]),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(child: facts[2]),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: facts[3]),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surfaceElevated,
            AppColors.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: useDesktopLayout
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: identityBlock()),
                const SizedBox(width: AppSpacing.xl),
                Expanded(flex: 5, child: factGrid()),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                identityBlock(),
                const SizedBox(height: AppSpacing.lg),
                factGrid(),
              ],
            ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, this.value});

  final String label;
  final String? value;

  static const Color _muted = AppColors.textTertiary;

  @override
  Widget build(BuildContext context) {
    final text = value?.trim().isNotEmpty == true ? value!.trim() : '—';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(
              color: _muted,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatsBlock extends StatelessWidget {
  const _StatsBlock({
    required this.profile,
    required this.metrics,
  });

  final TeacherProfile profile;
  final TeacherPnlMetrics metrics;

  static const Color _accent = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    final useDesktopLayout = LayoutMode.useDesktopLikeLayout(context);
    final total = metrics.totalRealizedPnl;
    final month = metrics.monthRealizedPnl;
    final current = metrics.floatingPnl;
    final wins = metrics.wins;
    final losses = metrics.losses;
    final totalTrades = wins + losses;
    final winRate = totalTrades > 0
        ? (100.0 * wins / totalTrades).toStringAsFixed(0)
        : '0';
    final rating = profile.rating ?? 0;
    final statItems = [
      _StatData(
        value: _formatPnl(total),
        label: AppLocalizations.of(context)!.teachersTotalEarnings,
      ),
      _StatData(
        value: _formatPnl(month),
        label: AppLocalizations.of(context)!.teachersMonthlyEarnings,
      ),
      _StatData(
        value: _formatPnl(current),
        label: AppLocalizations.of(context)!.featuredFloatingPnl,
      ),
      _StatData(
        value: '$wins',
        label: AppLocalizations.of(context)!.featuredWins,
      ),
      _StatData(
        value: '$losses',
        label: AppLocalizations.of(context)!.featuredLosses,
      ),
      _StatData(
        value: '$winRate%',
        label: AppLocalizations.of(context)!.featuredWinRate,
      ),
      _StatData(
        value: '$rating',
        label: AppLocalizations.of(context)!.teachersRatingLabel,
      ),
    ];
    final primary = statItems.take(3).toList();
    final secondary = statItems.skip(3).toList();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)!.teachersRecordAndEarnings,
                style: AppTypography.subtitle.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (useDesktopLayout) ...[
            Row(
              children: [
                for (var i = 0; i < primary.length; i++) ...[
                  Expanded(
                    child: _StatItem(
                      value: primary[i].value,
                      label: primary[i].label,
                      compact: false,
                    ),
                  ),
                  if (i != primary.length - 1)
                    const SizedBox(width: AppSpacing.md),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                for (var i = 0; i < secondary.length; i++) ...[
                  Expanded(
                    child: _StatItem(
                      value: secondary[i].value,
                      label: secondary[i].label,
                      compact: true,
                    ),
                  ),
                  if (i != secondary.length - 1)
                    const SizedBox(width: AppSpacing.md),
                ],
              ],
            ),
          ] else ...[
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: statItems
                  .map(
                    (item) => _StatItem(
                      value: item.value,
                      label: item.label,
                      compact: true,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatPnl(num n) {
    if (n > 0) return '+${n.toStringAsFixed(2)}';
    if (n < 0) return n.toStringAsFixed(2);
    return '0.00';
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.value,
    required this.label,
    required this.compact,
  });

  final String value;
  final String label;
  final bool compact;

  static const Color _accent = AppColors.primary;
  static const Color _muted = AppColors.textTertiary;

  @override
  Widget build(BuildContext context) {
    final isPositive = value.startsWith('+');
    final isNegative = value.startsWith('-') && !value.startsWith('-0');
    return Container(
      width: compact ? 156 : null,
      padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surface,
            AppColors.surface2.withValues(alpha: 0.82),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isPositive
              ? _accent.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: TextStyle(
              color: isPositive
                  ? _accent
                  : (isNegative ? AppColors.negative : AppColors.textPrimary),
              fontWeight: FontWeight.w700,
              fontSize: compact ? 20 : 26,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatData {
  const _StatData({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;
}

class _BioCard extends StatelessWidget {
  const _BioCard({this.bio});

  final String? bio;

  static const Color _surface = AppColors.surface2;
  static const Color _muted = AppColors.textTertiary;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Text(
        bio ?? AppLocalizations.of(context)!.teachersNoIntro,
        style: TextStyle(
          color: bio != null ? Colors.white.withValues(alpha: 0.88) : _muted,
          fontSize: 14,
          height: 1.6,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _SpecialtiesWrap extends StatelessWidget {
  const _SpecialtiesWrap({this.specialties});

  final List<String>? specialties;

  static const Color _accent = AppColors.primary;
  static const Color _surface = AppColors.surface2;
  static const Color _muted = AppColors.textTertiary;

  @override
  Widget build(BuildContext context) {
    final list =
        (specialties ?? const <String>[]).where((s) => s.trim().isNotEmpty).toList();
    if (list.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Center(
          child: Text(AppLocalizations.of(context)!.commonNone, style: const TextStyle(color: _muted, fontSize: 14)),
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: list
            .map(
              (item) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _accent.withValues(alpha: 0.4)),
                ),
                child: Text(
                  item,
                  style: const TextStyle(
                    color: _accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _StrategyImagePreview extends StatelessWidget {
  const _StrategyImagePreview({required this.item});

  final TeacherStrategy item;

  @override
  Widget build(BuildContext context) {
    final allImageUrls = (item.imageUrls ?? const <String>[])
        .where((u) => u.trim().isNotEmpty)
        .toList(growable: false);
    if (allImageUrls.isEmpty) return const SizedBox.shrink();
    return StrategyImagePreviewGrid(
      imageUrls: allImageUrls,
      onImageTap: (i) => showStrategyImageViewer(
        context,
        imageUrls: allImageUrls,
        initialIndex: i,
      ),
    );
  }
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({required this.title, required this.child});

  final String title;
  final Widget child;

  static const Color _accent = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: AppTypography.subtitle.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ProfileFactCard extends StatelessWidget {
  const _ProfileFactCard({
    required this.label,
    this.value,
  });

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final text = value?.trim().isNotEmpty == true ? value!.trim() : '—';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surface,
            AppColors.surface2.withValues(alpha: 0.82),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _TeacherStrategyHistoryCard extends StatelessWidget {
  const _TeacherStrategyHistoryCard({
    required this.item,
    required this.comments,
    required this.teacherId,
    required this.currentUserId,
    required this.repository,
  });

  final TeacherStrategy item;
  final List<Comment> comments;
  final String teacherId;
  final String currentUserId;
  final TeacherRepository repository;

  @override
  Widget build(BuildContext context) {
    final content = (item.content?.trim().isNotEmpty == true
            ? item.content!
            : item.summary.trim())
        .trim();
    final previewComments = comments.take(2).toList();
    final allImageUrls = (item.imageUrls ?? const <String>[])
        .where((u) => u.trim().isNotEmpty)
        .toList(growable: false);

    return InkWell(
      onTap: () {
        showStrategyDialog(
          context,
          content.isNotEmpty
              ? content
              : AppLocalizations.of(context)!.featuredNoStrategyContent,
          comments,
          teacherId: teacherId,
          strategyId: item.id,
          imageUrls: allImageUrls,
          currentUserId: currentUserId,
          repo: repository,
          onCommentPosted: (_, __) {},
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.insights_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: AppTypography.subtitle.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _TeacherPublicPageState._formatDate(item.createdAt),
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Text(
                    '${comments.length} 评论',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            if (allImageUrls.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              _StrategyImagePreview(item: item),
            ],
            if (content.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                content,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: previewComments.isEmpty
                  ? Text(
                      '暂无评论，登录后可查看并参与历史策略讨论。',
                      style: AppTypography.bodySecondary.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '最新评论',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ...previewComments.map(
                          (comment) => Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: _StrategyCommentPreview(comment: comment),
                          ),
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

class _StrategyCommentPreview extends StatelessWidget {
  const _StrategyCommentPreview({
    required this.comment,
  });

  final Comment comment;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = comment.avatarUrl?.trim();
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
    final initial = comment.userName.isNotEmpty ? comment.userName[0] : '?';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: AppColors.primary.withValues(alpha: 0.12),
          backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
          child: hasAvatar
              ? null
              : Text(
                  initial,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      comment.userName,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    comment.date,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              if (comment.replyToContent?.trim().isNotEmpty == true) ...[
                Text(
                  '回复：${comment.replyToContent!}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 2),
              ],
              Text(
                comment.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySecondary.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
