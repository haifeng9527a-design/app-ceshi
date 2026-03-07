import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/design/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/components.dart';
import '../auth/login_page.dart';
import '../../api/users_api.dart';
import '../../core/api_client.dart';
import '../../core/firebase_bootstrap.dart';
import '../../core/models.dart';
import '../messages/message_models.dart';
import '../messages/messages_repository.dart';
import '../strategies/strategy_dialog.dart';
import '../strategies/strategies_page.dart';
import '../teachers/teacher_detail_page.dart';
import '../teachers/teacher_models.dart' as tmodels;
import '../teachers/teacher_repository.dart';

/// 将后端 TeacherProfile 转为首页/详情使用的 Teacher（UI 不变，仅数据源切换为真实数据）
Teacher _profileToTeacher(BuildContext context, tmodels.TeacherProfile p) {
  final l10n = AppLocalizations.of(context)!;
  final name = p.displayName?.trim().isNotEmpty == true
      ? p.displayName!
      : (p.realName?.trim().isNotEmpty == true
          ? p.realName!
          : l10n.profileTeacher);
  final title =
      p.title?.trim().isNotEmpty == true ? p.title! : l10n.featuredMentor;
  final bio = p.bio?.trim().isNotEmpty == true ? p.bio! : '';
  final tags = p.tags ?? const [];
  return Teacher(
    id: p.userId,
    name: name,
    title: title,
    avatarUrl: p.avatarUrl ?? '',
    bio: bio,
    tags: tags,
    wins: p.wins ?? 0,
    losses: p.losses ?? 0,
    rating: p.rating ?? 0,
    todayStrategy: p.todayStrategy?.trim().isNotEmpty == true
        ? p.todayStrategy!
        : l10n.featuredNoTodayStrategy,
    strategyHistory: const [],
    trades: const [],
    positions: const [],
    historyPositions: const [],
    pnlCurrent: (p.pnlCurrent ?? 0).toDouble(),
    pnlMonth: (p.pnlMonth ?? 0).toDouble(),
    pnlYear: (p.pnlYear ?? 0).toDouble(),
    pnlTotal: (p.pnlTotal ?? 0).toDouble(),
    comments: const [],
    articles: const [],
    schedules: const [],
  );
}

class FeaturedTeacherPage extends StatefulWidget {
  const FeaturedTeacherPage({super.key, this.teacherId});

  /// 指定交易员 ID 时，直接显示该交易员的策略中心（用于「进入交易策略中心」）
  final String? teacherId;

  @override
  State<FeaturedTeacherPage> createState() => _FeaturedTeacherPageState();
}

class _FeaturedTeacherPageState extends State<FeaturedTeacherPage> {
  final _repo = TeacherRepository();
  Teacher? _teacher;
  List<Teacher> _teachers = [];
  int _selectedIndex = 0;
  final PageController _pageController = PageController();
  bool _loading = true;
  String? _error;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final specifiedId =
        widget.teacherId?.trim().isNotEmpty == true ? widget.teacherId! : null;
    final userId = FirebaseBootstrap.isReady
        ? (FirebaseAuth.instance.currentUser?.uid ?? '')
        : '';
    if (userId.isEmpty && specifiedId == null) {
      setState(() {
        _loading = false;
        _teacher = null;
        _teachers = [];
        _error = 'not_logged_in';
      });
      return;
    }
    if (userId.isEmpty && specifiedId != null) {
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        final profile = await _repo.fetchProfile(specifiedId);
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          setState(() {
            _teacher =
                profile != null ? _profileToTeacher(context, profile) : null;
            _teachers = _teacher != null ? [_teacher!] : [];
            _selectedIndex = 0;
            _loading = false;
            if (_teacher == null) _error = l10n.featuredNoTeacherInfo;
          });
        }
      } catch (e) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          setState(() {
            _loading = false;
            _teachers = [];
            _error = e.toString().length > 80
                ? l10n.featuredLoadFailedRetry
                : e.toString();
          });
        }
      }
      return;
    }
    if (!ApiClient.instance.isAvailable) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _loading = false;
          _error = l10n.featuredServiceNotReady;
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final teachers = <Teacher>[];
      final selfProfile = await _repo.fetchProfile(userId);
      if (!mounted) return;
      final followedIds = await _repo.getFollowedTeacherIds(userId);
      if (!mounted) return;
      final seenIds = <String>{};
      if (selfProfile != null) {
        teachers.add(_profileToTeacher(context, selfProfile));
        seenIds.add(userId);
      }
      for (final tid in followedIds) {
        if (tid.isEmpty || seenIds.contains(tid)) continue;
        seenIds.add(tid);
        final p = await _repo.fetchProfile(tid);
        if (!mounted) return;
        if (p != null) {
          teachers.add(_profileToTeacher(context, p));
        }
      }
      if (teachers.isEmpty && specifiedId == null) {
        final p = await _repo.getRankOneTeacherProfile();
        if (!mounted) return;
        if (p != null) teachers.add(_profileToTeacher(context, p));
      }
      if (specifiedId != null && specifiedId.isNotEmpty) {
        final specProfile = await _repo.fetchProfile(specifiedId);
        if (!mounted) return;
        if (specProfile != null) {
          final specTeacher = _profileToTeacher(context, specProfile);
          final idx = teachers.indexWhere((t) => t.id == specifiedId);
          if (idx >= 0) {
            teachers.removeAt(idx);
            teachers.insert(0, specTeacher);
          } else {
            teachers.insert(0, specTeacher);
          }
        }
      }
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _teachers = teachers;
          _teacher = teachers.isNotEmpty ? teachers.first : null;
          _selectedIndex = 0;
          _loading = false;
          if (_teacher == null && _error == null) {
            _error = specifiedId != null
                ? l10n.featuredNoTeacherInfo
                : l10n.featuredNoFollowingOrRanking;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        final msg = e.toString().contains('Operation not permitted') ||
                e.toString().contains('Connection failed')
            ? l10n.featuredNetworkRestricted
            : (e.toString().length > 80
                ? l10n.featuredLoadFailedRetry
                : e.toString());
        setState(() {
          _loading = false;
          _teachers = [];
          _error = msg;
        });
      }
    }
  }

  void _onTeacherPageChanged(int index) {
    if (index >= 0 && index < _teachers.length) {
      setState(() {
        _selectedIndex = index;
        _teacher = _teachers[index];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }
    if (_error != null || _teacher == null) {
      final l10n = AppLocalizations.of(context)!;
      final isNotLoggedIn = _error == 'not_logged_in';
      return Scaffold(
        body: Center(
          child: Padding(
            padding: AppSpacing.allLg,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isNotLoggedIn
                      ? l10n.featuredNotStartedInvestment
                      : (_error ?? l10n.commonNoData),
                  style: AppTypography.bodySecondary.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 15,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                if (isNotLoggedIn)
                  AppButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const LoginPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.login, size: 20),
                    label: l10n.authLoginOrRegister,
                  )
                else
                  AppButton(
                    variant: AppButtonVariant.text,
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: l10n.commonRetry,
                  ),
              ],
            ),
          ),
        ),
      );
    }
    final teacher = _teacher!;
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: AppSpacing.only(
                left: AppSpacing.md,
                top: AppSpacing.sm,
                right: AppSpacing.md,
                bottom: AppSpacing.md,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  [
                    if (_teachers.length >= 2) ...[
                      SizedBox(
                        height: 170,
                        child: PageView.builder(
                          controller: _pageController,
                          itemCount: _teachers.length,
                          onPageChanged: _onTeacherPageChanged,
                          itemBuilder: (context, i) {
                            final t = _teachers[i];
                            return Padding(
                              padding: const EdgeInsets.only(right: AppSpacing.sm),
                              child: _HeroHeader(
                                teacher: t,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          TeacherDetailPage(teacher: t),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          _teachers.length,
                          (i) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs - 1),
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i == _selectedIndex
                                  ? AppColors.primary
                                  : AppColors.primarySubtle(0.3),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ] else
                      _HeroHeader(
                        teacher: teacher,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  TeacherDetailPage(teacher: teacher),
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: AppSpacing.md),
                    _SectionTitle(
                        title:
                            AppLocalizations.of(context)!.featuredPnlOverview),
                    _KpiGrid(teacher: teacher),
                    const SizedBox(height: AppSpacing.md),
                    _SectionTitle(
                        title: AppLocalizations.of(context)!
                            .featuredTodayStrategy),
                    _TodayStrategyStream(
                      teacherId: teacher.id,
                      teacherName: teacher.name,
                      teacherAvatarUrl: teacher.avatarUrl,
                      fallbackText: teacher.todayStrategy,
                      repo: _repo,
                      currentUserId:
                          FirebaseAuth.instance.currentUser?.uid ?? '',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerRight,
                      child: AppButton(
                        variant: AppButtonVariant.text,
                        label: AppLocalizations.of(context)!.featuredViewAllStrategies,
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => StrategiesPage(teacher: teacher),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _SectionTitle(
                        title: AppLocalizations.of(context)!
                            .featuredCurrentPositions),
                    _PositionsStream(
                        teacherId: teacher.id, repo: _repo, isHistory: false),
                    const SizedBox(height: AppSpacing.md),
                    _SectionTitle(
                        title: AppLocalizations.of(context)!
                            .featuredHistoryPositions),
                    _PositionsStream(
                        teacherId: teacher.id, repo: _repo, isHistory: true),
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

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.teacher, required this.onTap});

  final Teacher teacher;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          padding: AppSpacing.only(
            left: AppSpacing.md,
            top: AppSpacing.md,
            right: AppSpacing.md,
            bottom: AppSpacing.sm + AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [
                AppColors.surface2,
                AppColors.scaffold,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: AppColors.primary, width: 0.6),
            boxShadow: [
              BoxShadow(
                color: AppColors.primarySubtle(0.15),
                blurRadius: 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: _TeacherGlassCard(teacher: teacher, onTap: onTap),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: _MonthPnlChip(value: teacher.pnlMonth),
        ),
      ],
    );
  }
}

class _TeacherGlassCard extends StatelessWidget {
  const _TeacherGlassCard({required this.teacher, required this.onTap});

  final Teacher teacher;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: AppSpacing.only(
          left: AppSpacing.md - AppSpacing.xs / 2,
          top: AppSpacing.md + AppSpacing.xs / 2,
          right: AppSpacing.md - AppSpacing.xs / 2,
          bottom: AppSpacing.md - AppSpacing.xs / 2,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: AppColors.surfaceElevated,
          border: Border.all(color: AppColors.primary, width: 0.4),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: AppColors.primary,
              backgroundImage: teacher.avatarUrl.trim().isNotEmpty
                  ? NetworkImage(teacher.avatarUrl.trim())
                  : null,
              child: teacher.avatarUrl.trim().isEmpty
                  ? Text(
                      _initial(teacher.name),
                      style: AppTypography.title.copyWith(
                        fontSize: 20,
                        color: AppColors.surface,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: AppSpacing.md - AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    teacher.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    teacher.title,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm + AppSpacing.xs / 2),
                  _BattleStats(teacher: teacher),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BattleStats extends StatelessWidget {
  const _BattleStats({required this.teacher});

  final Teacher teacher;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final total = teacher.wins + teacher.losses;
    final winRate = total == 0 ? 0 : (teacher.wins / total * 100).round();
    return Row(
      children: [
        Expanded(
            child: _StatChipCompact(
                label: l10n.featuredWins, value: '${teacher.wins}')),
        const SizedBox(width: 8),
        Expanded(
            child: _StatChipCompact(
                label: l10n.featuredLosses, value: '${teacher.losses}')),
        const SizedBox(width: 8),
        Expanded(
            child: _StatChipCompact(
                label: l10n.featuredWinRate, value: '$winRate%')),
      ],
    );
  }
}

class _StatChipCompact extends StatelessWidget {
  const _StatChipCompact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: AppSpacing.symmetric(horizontal: AppSpacing.sm - AppSpacing.xs / 2, vertical: AppSpacing.sm - AppSpacing.xs / 2),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '$label $value',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: AppSpacing.xs,
          height: AppSpacing.md,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(AppSpacing.xs),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.teacher});

  final Teacher teacher;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
            child: _KpiTile(
                label: l10n.featuredPositionPnl, value: teacher.pnlCurrent)),
        const SizedBox(width: 8),
        Expanded(
            child:
                _KpiTile(label: l10n.featuredYearPnl, value: teacher.pnlYear)),
        const SizedBox(width: 8),
        Expanded(
            child: _KpiTile(
                label: l10n.featuredTotalPnl, value: teacher.pnlTotal)),
      ],
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final isProfit = value >= 0;
    final color = isProfit ? AppColors.positive : AppColors.negative;
    return AppCard(
      padding: AppSpacing.symmetric(horizontal: AppSpacing.sm + AppSpacing.xs / 2, vertical: AppSpacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 6),
          Text(
            _formatAmount(value),
            style:
                Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// 今日交易策略：优先显示交易员中心发布的最新一条策略，无则显示档案中的今日策略
class _TodayStrategyStream extends StatelessWidget {
  const _TodayStrategyStream({
    required this.teacherId,
    required this.teacherName,
    required this.teacherAvatarUrl,
    required this.fallbackText,
    required this.repo,
    required this.currentUserId,
  });

  final String teacherId;
  final String teacherName;
  final String teacherAvatarUrl;
  final String fallbackText;
  final TeacherRepository repo;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return StreamBuilder<List<tmodels.TeacherStrategy>>(
      stream: repo.watchPublishedStrategies(teacherId),
      builder: (context, stratSnapshot) {
        final strategies = stratSnapshot.data ?? const [];
        final latest = strategies.isNotEmpty ? strategies.first : null;
        final title = latest?.title ?? l10n.featuredCoreStrategy;
        final text = (latest?.content?.trim().isNotEmpty == true
                ? latest!.content!
                : (latest?.summary ?? '').trim().isNotEmpty == true
                    ? latest!.summary
                    : null) ??
            (fallbackText.trim().isNotEmpty
                ? fallbackText
                : l10n.featuredNoTodayStrategy);
        // 策略未加载完成时用空流，避免从教师级评论切换到策略评论时条数跳变
        final commentsStream = stratSnapshot.hasData
            ? (latest != null
                ? repo.watchStrategyComments(teacherId, latest.id)
                : repo.watchTeacherComments(teacherId))
            : Stream<List<Comment>>.value(const []);
        return StreamBuilder<List<Comment>>(
          stream: commentsStream,
          builder: (context, commentsSnapshot) {
            final comments = commentsSnapshot.data ?? const [];
            return _HeroStrategyCard(
              title: title,
              text: text,
              imageUrls: latest?.imageUrls,
              comments: comments,
              teacherId: teacherId,
              strategyId: latest?.id,
              teacherName: teacherName,
              teacherAvatarUrl: teacherAvatarUrl,
              currentUserId: currentUserId,
              repo: repo,
            );
          },
        );
      },
    );
  }
}

class _HeroStrategyCard extends StatefulWidget {
  const _HeroStrategyCard({
    required this.title,
    required this.text,
    this.imageUrls,
    required this.comments,
    required this.teacherId,
    this.strategyId,
    required this.teacherName,
    required this.teacherAvatarUrl,
    required this.currentUserId,
    required this.repo,
  });

  final String title;
  final String text;
  final List<String>? imageUrls;
  final List<Comment> comments;
  final String teacherId;
  final String? strategyId;
  final String teacherName;
  final String teacherAvatarUrl;
  final String currentUserId;
  final TeacherRepository repo;

  @override
  State<_HeroStrategyCard> createState() => _HeroStrategyCardState();
}

class _HeroStrategyCardState extends State<_HeroStrategyCard> {
  bool _showComments = false;
  Comment? _replyToComment;
  final Set<String> _expandedReplies = {};
  final List<Comment> _optimisticComments = [];
  OverlayEntry? _formOverlayEntry;
  int? _likeCountOverride;
  bool? _likedOverride;
  DateTime? _lastLikeToggleAt;

  @override
  void dispose() {
    _formOverlayEntry?.remove();
    _formOverlayEntry = null;
    super.dispose();
  }

  void _updateFormOverlay() {
    _formOverlayEntry?.markNeedsBuild();
  }

  void _syncFormOverlay() {
    if (_showComments && mounted) {
      _formOverlayEntry ??= OverlayEntry(
        builder: (context) => Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Material(
            color: AppColors.scaffold,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: _CommentForm(
                  teacherId: widget.teacherId,
                  strategyId: widget.strategyId,
                  currentUserId: widget.currentUserId,
                  repo: widget.repo,
                  replyToComment: _replyToComment,
                  onReplyConsumed: () {
                    setState(() => _replyToComment = null);
                    _updateFormOverlay();
                  },
                  onPosted: (userName, content, {Comment? replyTo}) {
                    _onCommentPosted(userName, content, replyTo: replyTo);
                    setState(() {
                      _replyToComment = null;
                      _updateFormOverlay();
                    });
                  },
                ),
              ),
            ),
          ),
        ),
      );
      Overlay.of(context).insert(_formOverlayEntry!);
    } else {
      _formOverlayEntry?.remove();
      _formOverlayEntry = null;
    }
  }

  void _onCommentPosted(String userName, String content, {Comment? replyTo}) {
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    setState(() {
      _optimisticComments.add(Comment(
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
    });
  }

  List<Comment> get _mergedComments {
    final fromStream = widget.comments;
    final merged = [...fromStream];
    for (final o in _optimisticComments) {
      if (!merged
          .any((c) => c.content == o.content && c.userName == o.userName)) {
        merged.add(o);
      }
    }
    merged.sort((a, b) => b.date.compareTo(a.date));
    return merged;
  }

  void _onLikeToggled(bool currentlyLiked, int currentCount) {
    setState(() {
      _lastLikeToggleAt = DateTime.now();
      _likedOverride = !currentlyLiked;
      _likeCountOverride = currentCount + (_likedOverride! ? 1 : -1);
    });
  }

  /// 抖音式评论：父评论按时间倒序，回复紧贴父评论下方、按时间正序；默认只显示 1 条回复，可展开
  List<Widget> _buildThreadedCommentsInline(List<Comment> list) {
    const accent = AppColors.primary;
    void onReplyTap(Comment c) {
      setState(() {
        _replyToComment = c;
        _showComments = true;
        _syncFormOverlay();
      });
      _updateFormOverlay();
    }

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
      final isExpanded = _expandedReplies.contains(parent.id);
      final showCount = replies.length <= 1
          ? replies.length
          : (isExpanded ? replies.length : 1);
      for (var i = 0; i < showCount; i++) {
        widgets.add(_CommentItem(
          comment: replies[i],
          onReplyTap: onReplyTap,
          isReply: true,
        ));
      }
      if (replies.length > 1) {
        final l10n = AppLocalizations.of(context)!;
        widgets.add(
          GestureDetector(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedReplies.remove(parent.id);
                } else {
                  _expandedReplies.add(parent.id);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.only(left: 78, bottom: 12),
              child: Text(
                isExpanded
                    ? l10n.featuredCollapse
                    : l10n.featuredExpandReplies(replies.length - 1),
                style: TextStyle(
                  color: accent.withValues(alpha: 0.9),
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

  void _syncLikeFromStream(int count, bool liked) {
    if (_lastLikeToggleAt != null &&
        DateTime.now().difference(_lastLikeToggleAt!).inSeconds < 3) {
      return;
    }
    if (_likeCountOverride == count && _likedOverride == liked) return;
    setState(() {
      _likeCountOverride = count;
      _likedOverride = liked;
    });
  }

  void _showForwardSheet(BuildContext context) {
    if (widget.currentUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(AppLocalizations.of(context)!.featuredLoginBeforeForward)),
      );
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      return;
    }
    final payload = {
      'teacher_id': widget.teacherId,
      'teacher_name': widget.teacherName,
      'avatar_url': widget.teacherAvatarUrl,
    };
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface2,
      builder: (ctx) => _ForwardConversationSheet(
        teacherPayload: payload,
        currentUserId: widget.currentUserId,
        onSent: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        return SizedBox(
          width: maxW,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [
                  AppColors.surface2,
                  AppColors.surface,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: AppColors.primary, width: 0.6),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.primary,
                  blurRadius: 12,
                  spreadRadius: -6,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () {
                    showStrategyDialog(
                      context,
                      widget.text,
                      _mergedComments,
                      teacherId: widget.teacherId,
                      strategyId: widget.strategyId,
                      currentUserId: widget.currentUserId,
                      repo: widget.repo,
                      onCommentPosted: _onCommentPosted,
                      initialShowComments: _showComments,
                    );
                  },
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.imageUrls != null &&
                            widget.imageUrls!.isNotEmpty) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              widget.imageUrls!.first,
                              height: 120,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(AppRadius.sm + AppSpacing.xs / 2),
                              ),
                              child: const Icon(
                                Icons.trending_up,
                                color: AppColors.surface,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm + AppSpacing.xs / 2),
                            Expanded(
                              child: Text(
                                widget.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(color: AppColors.primary),
                              ),
                            ),
                            const Spacer(),
                            const Icon(Icons.open_in_new, size: 16),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm + AppSpacing.xs / 2),
                        Text(
                          widget.text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontSize: 15,
                                    height: 1.4,
                                  ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          AppLocalizations.of(context)!
                              .featuredViewFullStrategy,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm + AppSpacing.xs / 2),
                Padding(
                  padding: AppSpacing.only(
                    left: AppSpacing.md + AppSpacing.xs / 2,
                    top: 0,
                    right: AppSpacing.md + AppSpacing.xs / 2,
                    bottom: AppSpacing.md + AppSpacing.xs / 2,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _showComments = !_showComments;
                                _syncFormOverlay();
                              });
                            },
                            icon: Icon(
                              _showComments
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 18,
                              color: AppColors.primary,
                            ),
                            label: Text(
                              _showComments
                                  ? AppLocalizations.of(context)!
                                      .featuredHideComments
                                  : AppLocalizations.of(context)!
                                      .featuredViewComments,
                              style: const TextStyle(color: AppColors.primary),
                            ),
                          ),
                          StreamBuilder<int>(
                            stream: widget.repo
                                .watchTeacherLikesCount(widget.teacherId),
                            builder: (context, likeSnap) {
                              final streamCount = likeSnap.data ?? 0;
                              final likeCount =
                                  _likeCountOverride ?? streamCount;
                              return StreamBuilder<bool>(
                                stream: widget.repo.watchUserLiked(
                                  teacherId: widget.teacherId,
                                  userId: widget.currentUserId,
                                ),
                                builder: (context, likedSnap) {
                                  final streamLiked = likedSnap.data ?? false;
                                  if (likeSnap.hasData && likedSnap.hasData) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      if (mounted) {
                                        _syncLikeFromStream(
                                            streamCount, streamLiked);
                                      }
                                    });
                                  }
                                  final liked = _likedOverride ?? streamLiked;
                                  return TextButton.icon(
                                    onPressed: widget.currentUserId.isEmpty
                                        ? null
                                        : () async {
                                            _onLikeToggled(liked, likeCount);
                                            await widget.repo.toggleLike(
                                              teacherId: widget.teacherId,
                                              userId: widget.currentUserId,
                                            );
                                          },
                                    icon: Icon(
                                      liked
                                          ? Icons.thumb_up
                                          : Icons.thumb_up_outlined,
                                      size: 18,
                                      color: liked
                                          ? AppColors.primary
                                          : null,
                                    ),
                                    label: Text('$likeCount'),
                                  );
                                },
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.share, size: 20),
                            onPressed: () => _showForwardSheet(context),
                            tooltip: AppLocalizations.of(context)!
                                .featuredForwardTooltip,
                          ),
                          const Spacer(),
                          Flexible(
                            child: Text(
                              AppLocalizations.of(context)!
                                  .featuredCommentsCount(
                                      _mergedComments.length),
                              style: Theme.of(context).textTheme.labelSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (_showComments) ...[
                        const SizedBox(height: 8),
                        const Divider(height: 1, color: AppColors.border),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 500),
                          child: SingleChildScrollView(
                            child: _mergedComments.isEmpty
                                ? _EmptyHint(
                                    text: AppLocalizations.of(context)!
                                        .featuredNoComments)
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: _buildThreadedCommentsInline(
                                        _mergedComments),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 80),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 转发到会话选择
class _ForwardConversationSheet extends StatelessWidget {
  const _ForwardConversationSheet({
    required this.teacherPayload,
    required this.currentUserId,
    required this.onSent,
  });

  final Map<String, String> teacherPayload;
  final String currentUserId;
  final VoidCallback onSent;

  static const Color _accent = AppColors.primary;

  Future<String> _getUserName(BuildContext context) async {
    try {
      if (!ApiClient.instance.isAvailable) {
        if (!context.mounted) return '';
        return AppLocalizations.of(context)!.commonUser;
      }
      final name = await UsersApi.instance.getDisplayName(currentUserId);
      if (!context.mounted) return '';
      return name.isNotEmpty ? name : AppLocalizations.of(context)!.commonUser;
    } catch (_) {
      if (!context.mounted) return '';
      return AppLocalizations.of(context)!.commonUser;
    }
  }

  Future<void> _sendToConversation(
    BuildContext context,
    Conversation conv,
    String senderName,
  ) async {
    final content = jsonEncode(teacherPayload);
    try {
      await MessagesRepository().sendMessage(
        conversationId: conv.id,
        senderId: currentUserId,
        senderName: senderName,
        content: content,
        messageType: 'teacher_share',
        receiverId: conv.peerId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!.featuredForwarded)),
        );
        onSent();
      }
    } catch (e) {
      if (context.mounted) {
        final msg = e.toString().length > 40
            ? e.toString().substring(0, 40)
            : e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!
                  .featuredForwardFailedWithMessage(msg))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollController) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: AppSpacing.allMd,
              child: Row(
                children: [
                  Text(
                    AppLocalizations.of(context)!.featuredForwardTo,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: _accent,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: onSent,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<List<Conversation>>(
                stream: MessagesRepository()
                    .watchConversations(userId: currentUserId),
                builder: (context, snapshot) {
                  final list = snapshot.data ?? [];
                  if (list.isEmpty) {
                    return Center(
                      child: Text(AppLocalizations.of(context)!
                          .featuredNoConversationAddFriend),
                    );
                  }
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final conv = list[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _accent,
                          child: Text(
                            (conv.title.isNotEmpty ? conv.title[0] : '?'),
                            style: const TextStyle(color: AppColors.surface),
                          ),
                        ),
                        title: Text(conv.title),
                        subtitle: Text(conv.subtitle),
                        onTap: () async {
                          final name = await _getUserName(context);
                          if (context.mounted) {
                            await _sendToConversation(context, conv, name);
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 评论输入框与发表按钮
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
  final void Function(String userName, String content, {Comment? replyTo})?
      onPosted;

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
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
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
          SnackBar(
              content: Text(
                  AppLocalizations.of(context)!.featuredLoginBeforeComment)),
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
          SnackBar(
              content:
                  Text(AppLocalizations.of(context)!.featuredCommentPublished)),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        final displayMsg = msg.length > 120 ? '${msg.substring(0, 120)}…' : msg;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!
                .featuredCommentPublishFailedWithMessage(displayMsg)),
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
    return AppCard(
      padding: AppSpacing.only(
        left: AppSpacing.sm + AppSpacing.xs / 2,
        top: AppSpacing.sm,
        right: AppSpacing.sm + AppSpacing.xs / 2,
        bottom: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              minLines: 1,
              maxLines: 3,
              enabled: !_submitting,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.featuredCommentHint,
                filled: true,
                fillColor: AppColors.scaffold,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: const BorderSide(color: AppColors.primary, width: 0.4),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: const BorderSide(color: AppColors.primary, width: 0.4),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.sm + AppSpacing.xs / 2, vertical: AppSpacing.sm),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm + AppSpacing.xs / 2),
          AppButton(
            onPressed: _submitting ? null : _submit,
            label: _submitting
                ? AppLocalizations.of(context)!.featuredPublishing
                : AppLocalizations.of(context)!.featuredPublish,
            loading: _submitting,
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
          style: const TextStyle(color: AppColors.textSecondary),
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
        style: const TextStyle(color: AppColors.textSecondary),
      ));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(
        text: content,
        style: const TextStyle(color: AppColors.textSecondary),
      ));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    const accent = AppColors.primary;
    final content = Padding(
      padding: EdgeInsets.only(
        bottom: 12,
        left: isReply ? 44 : 0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: isReply ? 12 : 16,
            backgroundColor: accent,
            backgroundImage: comment.avatarUrl != null &&
                    comment.avatarUrl!.trim().isNotEmpty
                ? NetworkImage(comment.avatarUrl!.trim())
                : null,
            child:
                comment.avatarUrl == null || comment.avatarUrl!.trim().isEmpty
                    ? Text(
                        comment.userName.characters.first,
                        style: const TextStyle(color: AppColors.surface),
                      )
                    : null,
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
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                    ),
                  ],
                ),
                if (comment.replyToContent != null &&
                    comment.replyToContent!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.textPrimary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(AppSpacing.sm),
                      border: Border(
                        left: BorderSide(
                            color: accent.withValues(alpha: 0.5), width: 3),
                      ),
                    ),
                    child: Text(
                      comment.replyToContent!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                RichText(
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                    children:
                        _buildContentSpans(comment.content, _mentionColor),
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

/// 从 Supabase teacher_positions 实时同步持仓，使用与交易中心一致的卡片 UI
class _PositionsStream extends StatelessWidget {
  const _PositionsStream({
    required this.teacherId,
    required this.repo,
    required this.isHistory,
  });

  final String teacherId;
  final TeacherRepository repo;
  final bool isHistory;

  @override
  Widget build(BuildContext context) {
    final stream = isHistory
        ? repo.watchHistoryPositions(teacherId)
        : repo.watchPositions(teacherId);
    return StreamBuilder<List<tmodels.TeacherPosition>>(
      stream: stream,
      builder: (context, snapshot) {
        final list = snapshot.data ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: list.map((p) => _PositionCardStyle(position: p)).toList(),
        );
      },
    );
  }
}

/// 与交易中心一致的持仓卡片：持仓中显示浮动盈亏+盈亏比例，历史持仓显示卖出时间/价格+已实现盈亏/比例
class _PositionCardStyle extends StatelessWidget {
  const _PositionCardStyle({required this.position});

  final tmodels.TeacherPosition position;

  static const Color _accent = AppColors.primary;
  static const Color _muted = AppColors.textTertiary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final dateFmt = DateFormat('yyyy-MM-dd HH:mm');
    final isHistory = position.isHistory;

    if (isHistory) {
      final amount = position.realizedPnlAmount ?? 0;
      final ratio = position.realizedPnlRatioPercent;
      final pnlColor = amount >= 0 ? AppColors.positive : AppColors.negative;
      final rows = <Widget>[
        if (position.buyTime != null)
          _positionLine(dateFmt.format(position.buyTime!),
              prefix: l10n.featuredBuy),
        _positionInline([
          (
            l10n.featuredCost,
            '${position.costPrice ?? position.buyPrice ?? '--'}'
          ),
          if (position.buyShares != null)
            (l10n.featuredQuantity, '${position.buyShares}'),
        ]),
        if (position.sellTime != null || position.sellPrice != null)
          _positionInline([
            if (position.sellTime != null)
              (l10n.featuredSell, dateFmt.format(position.sellTime!)),
            if (position.sellPrice != null)
              (l10n.featuredSellPrice, position.sellPrice!.toStringAsFixed(2)),
          ]),
      ];
      return _positionCard(
        asset: position.asset,
        amountText: '${amount >= 0 ? '+' : ''}${amount.toStringAsFixed(2)}',
        ratioText: ratio != null
            ? '${ratio >= 0 ? '+' : ''}${ratio.toStringAsFixed(2)}%'
            : null,
        pnlColor: pnlColor,
        detailRows: rows,
      );
    }

    final pnl = position.floatingPnl ?? 0;
    final ratio = position.pnlRatio;
    final pnlColor = pnl >= 0 ? AppColors.positive : AppColors.negative;
    final rows = <Widget>[
      if (position.buyTime != null)
        _positionLine(dateFmt.format(position.buyTime!),
            prefix: l10n.featuredBuy),
      _positionInline([
        (
          l10n.featuredCost,
          '${position.costPrice ?? position.buyPrice ?? '--'}'
        ),
        (l10n.featuredCurrentPrice, '${position.currentPrice ?? '--'}'),
        if (position.buyShares != null)
          (l10n.featuredQuantity, '${position.buyShares}'),
      ]),
    ];
    return _positionCard(
      asset: position.asset,
      amountText: '${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)}',
      ratioText: ratio != null
          ? '${ratio >= 0 ? '+' : ''}${ratio.toStringAsFixed(2)}%'
          : null,
      pnlColor: pnlColor,
      detailRows: rows,
    );
  }

  static Widget _positionCard({
    required String asset,
    required String amountText,
    required Color pnlColor,
    String? ratioText,
    required List<Widget> detailRows,
  }) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md - 4, vertical: AppSpacing.sm),
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    asset,
                    style: const TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      amountText,
                      style: TextStyle(
                        color: pnlColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    if (ratioText != null)
                      Text(
                        ratioText,
                        style: TextStyle(color: pnlColor, fontSize: 11),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...detailRows.map((w) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: w,
                )),
          ],
        ),
      ),
    );
  }

  /// 单行：前缀 + 内容（如 买入 2026-01-20 00:00）
  static Widget _positionLine(String value, {required String prefix}) {
    return Text.rich(
      TextSpan(
        style: const TextStyle(fontSize: 12),
        children: [
          TextSpan(text: '$prefix ', style: const TextStyle(color: _muted)),
          TextSpan(text: value, style: const TextStyle(color: AppColors.textPrimary)),
        ],
      ),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
  }

  /// 一行内多组 标签 数值，用 · 分隔
  static Widget _positionInline(List<(String, String)> pairs) {
    if (pairs.isEmpty) return const SizedBox.shrink();
    final spans = <InlineSpan>[];
    for (var i = 0; i < pairs.length; i++) {
      if (i > 0) {
        spans.add(const TextSpan(
            text: '  ', style: TextStyle(color: _muted, fontSize: 12)));
      }
      spans.add(TextSpan(
          text: '${pairs[i].$1} ',
          style: const TextStyle(color: _muted, fontSize: 12)));
      spans.add(TextSpan(
          text: pairs[i].$2,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)));
    }
    return Text.rich(
        TextSpan(style: const TextStyle(fontSize: 12), children: spans),
        maxLines: 1,
        overflow: TextOverflow.ellipsis);
  }
}

class _MonthPnlChip extends StatelessWidget {
  const _MonthPnlChip({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final isProfit = value >= 0;
    final color = isProfit ? AppColors.positive : AppColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary, width: 0.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.featuredMonthTotalPnl,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 4),
          Text(
            _formatAmount(value),
            style:
                Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary, width: 0.4),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

String _formatAmount(double value) {
  final prefix = value > 0 ? '+' : '';
  return '$prefix${value.toStringAsFixed(0)}';
}

String _initial(String name) {
  if (name.isEmpty) {
    return '';
  }
  return name[0];
}
