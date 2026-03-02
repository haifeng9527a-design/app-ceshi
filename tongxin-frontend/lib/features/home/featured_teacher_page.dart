import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../auth/login_page.dart';
import '../../core/firebase_bootstrap.dart';
import '../../core/models.dart';
import '../../core/supabase_bootstrap.dart';
import '../messages/chat_detail_page.dart';
import '../messages/message_models.dart';
import '../messages/messages_repository.dart';
import '../strategies/strategy_dialog.dart';
import '../strategies/strategies_page.dart';
import '../teachers/teacher_detail_page.dart';
import '../teachers/teacher_models.dart' as tmodels;
import '../teachers/teacher_repository.dart';

/// 将后端 TeacherProfile 转为首页/详情使用的 Teacher（UI 不变，仅数据源切换为真实数据）
Teacher _profileToTeacher(tmodels.TeacherProfile p) {
  final name = p.displayName?.trim().isNotEmpty == true
      ? p.displayName!
      : (p.realName?.trim().isNotEmpty == true ? p.realName! : '交易员');
  final title = p.title?.trim().isNotEmpty == true ? p.title! : '导师';
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
        : '暂无今日策略',
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
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final specifiedId = widget.teacherId?.trim().isNotEmpty == true ? widget.teacherId! : null;
    if (specifiedId != null) {
      setState(() { _loading = true; _error = null; });
      try {
        final profile = await _repo.fetchProfile(specifiedId);
        if (mounted) {
          setState(() {
            _teacher = profile != null ? _profileToTeacher(profile) : null;
            _loading = false;
            if (_teacher == null) _error = '暂无交易员信息';
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = e.toString().length > 80 ? '加载失败，请重试' : e.toString();
          });
        }
      }
      return;
    }
    final userId = FirebaseBootstrap.isReady
        ? (FirebaseAuth.instance.currentUser?.uid ?? '')
        : '';
    if (userId.isEmpty) {
      setState(() {
        _loading = false;
        _teacher = null;
        _error = 'not_logged_in';
      });
      return;
    }
    if (!SupabaseBootstrap.isReady) {
      setState(() {
        _loading = false;
        _error = '服务未就绪';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      tmodels.TeacherProfile? profile;
      // 优先：当前用户本人是交易员 → 关注页显示自己的数据
      profile = await _repo.fetchProfile(userId);
      if (profile == null) {
        // 非交易员：显示第一个关注的交易员
        final followedIds = await _repo.getFollowedTeacherIds(userId);
        if (followedIds.isNotEmpty) {
          profile = await _repo.fetchProfile(followedIds.first);
        }
      }
      if (profile == null) {
        // 无关注时：显示排名第一的交易员
        profile = await _repo.getRankOneTeacherProfile();
      }
      if (mounted) {
        setState(() {
          _teacher = profile != null ? _profileToTeacher(profile) : null;
          _loading = false;
          if (_teacher == null && _error == null) {
            _error = '暂无关注或排名数据';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('Operation not permitted') ||
                e.toString().contains('Connection failed')
            ? '网络连接被限制，请检查网络或在本机终端运行应用后重试'
            : (e.toString().length > 80 ? '加载失败，请重试' : e.toString());
        setState(() {
          _loading = false;
          _error = msg;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
        ),
      );
    }
    if (_error != null || _teacher == null) {
      final isNotLoggedIn = _error == 'not_logged_in';
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isNotLoggedIn ? '你还没有开启自己的投资之旅' : (_error ?? '暂无数据'),
                  style: const TextStyle(color: Color(0xFF6C6F77), fontSize: 15),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (isNotLoggedIn)
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const LoginPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.login, size: 20),
                    label: const Text('登录/注册'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD4AF37),
                      foregroundColor: const Color(0xFF111215),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  )
                else
                  TextButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  [
                  _HeroHeader(
                    teacher: teacher,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TeacherDetailPage(teacher: teacher),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(title: '盈亏概览'),
                  _KpiGrid(teacher: teacher),
                  const SizedBox(height: 16),
                  _SectionTitle(title: '今日交易策略'),
                  _TodayStrategyStream(
                    teacherId: teacher.id,
                    teacherName: teacher.name,
                    teacherAvatarUrl: teacher.avatarUrl,
                    fallbackText: teacher.todayStrategy,
                    repo: _repo,
                    currentUserId: FirebaseAuth.instance.currentUser?.uid ?? '',
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => StrategiesPage(teacher: teacher),
                          ),
                        );
                      },
                      child: const Text('查看全部交易策略'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(title: '目前持仓'),
                  _PositionsStream(teacherId: teacher.id, repo: _repo, isHistory: false),
                  const SizedBox(height: 16),
                  _SectionTitle(title: '历史持仓'),
                  _PositionsStream(teacherId: teacher.id, repo: _repo, isHistory: true),
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [
                Color(0xFF1A1C20),
                Color(0xFF0D0E11),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: const Color(0xFFD4AF37), width: 0.6),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFD4AF37).withOpacity(0.15),
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
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color(0xFF15171B),
          border: Border.all(color: const Color(0xFFD4AF37), width: 0.4),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: const Color(0xFFD4AF37),
              backgroundImage: teacher.avatarUrl.trim().isNotEmpty
                  ? NetworkImage(teacher.avatarUrl.trim())
                  : null,
              child: teacher.avatarUrl.trim().isEmpty
                  ? Text(
                      _initial(teacher.name),
                      style: const TextStyle(
                        fontSize: 20,
                        color: Color(0xFF111215),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    teacher.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    teacher.title,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
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

class _FeaturedHeader extends StatelessWidget {
  const _FeaturedHeader({required this.teacher, required this.onTap});

  final Teacher teacher;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: const Color(0xFF111215),
          border: Border.all(color: const Color(0xFFD4AF37), width: 0.6),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: const Color(0xFFD4AF37),
              backgroundImage: teacher.avatarUrl.trim().isNotEmpty
                  ? NetworkImage(teacher.avatarUrl.trim())
                  : null,
              child: teacher.avatarUrl.trim().isEmpty
                  ? Text(
                      _initial(teacher.name),
                      style: const TextStyle(
                        fontSize: 22,
                        color: Color(0xFF111215),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      teacher.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    _MonthPnlChip(value: teacher.pnlMonth),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  teacher.title,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
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
    final total = teacher.wins + teacher.losses;
    final winRate = total == 0 ? 0 : (teacher.wins / total * 100).round();
    return Row(
      children: [
        Expanded(child: _StatChipCompact(label: '胜场', value: '${teacher.wins}')),
        const SizedBox(width: 8),
        Expanded(child: _StatChipCompact(label: '败场', value: '${teacher.losses}')),
        const SizedBox(width: 8),
        Expanded(child: _StatChipCompact(label: '胜率', value: '$winRate%')),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1F23),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD4AF37), width: 0.4),
      ),
      child: Text(
        '$label $value',
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}

class _StatChipCompact extends StatelessWidget {
  const _StatChipCompact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1F23),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD4AF37), width: 0.4),
      ),
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
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: const Color(0xFFD4AF37),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
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
    return Row(
      children: [
        Expanded(child: _KpiTile(label: '持仓盈亏', value: teacher.pnlCurrent)),
        const SizedBox(width: 8),
        Expanded(child: _KpiTile(label: '年度盈亏', value: teacher.pnlYear)),
        const SizedBox(width: 8),
        Expanded(child: _KpiTile(label: '总盈亏', value: teacher.pnlTotal)),
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
    final color = isProfit ? const Color(0xFF29C36A) : const Color(0xFFE54848);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111215),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD4AF37), width: 0.4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 6),
          Text(
            _formatAmount(value),
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionText,
    required this.onActionTap,
    required this.trailing,
    required this.onTitleTap,
  });

  final String title;
  final String actionText;
  final VoidCallback onActionTap;
  final Widget trailing;
  final VoidCallback onTitleTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InkWell(
          onTap: onTitleTap,
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onActionTap,
          child: Text(actionText),
        ),
        const Spacer(),
        trailing,
      ],
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
    return StreamBuilder<List<tmodels.TeacherStrategy>>(
      stream: repo.watchPublishedStrategies(teacherId),
      builder: (context, stratSnapshot) {
        final strategies = stratSnapshot.data ?? const [];
        final latest = strategies.isNotEmpty ? strategies.first : null;
        final title = latest?.title ?? '核心策略';
        final text = (latest?.content?.trim().isNotEmpty == true
                ? latest!.content!
                : (latest?.summary ?? '').trim().isNotEmpty == true
                    ? latest!.summary
                    : null) ??
            (fallbackText.trim().isNotEmpty ? fallbackText : '暂无今日策略');
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
    this.title = '核心策略',
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
            color: const Color(0xFF0D0E11),
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
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    setState(() {
      _optimisticComments.add(Comment(
        id: 'local-${now.millisecondsSinceEpoch}',
        userName: userName,
        content: content,
        date: date,
        replyToCommentId: replyTo?.id,
        replyToContent: replyTo != null
            ? (replyTo.content.length > 50 ? '${replyTo.content.substring(0, 50)}…' : replyTo.content)
            : null,
      ));
    });
  }

  List<Comment> get _mergedComments {
    final fromStream = widget.comments;
    final merged = [...fromStream];
    for (final o in _optimisticComments) {
      if (!merged.any((c) => c.content == o.content && c.userName == o.userName)) {
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
    const accent = Color(0xFFD4AF37);
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
                  _expandedReplies.remove(parent.id);
                } else {
                  _expandedReplies.add(parent.id);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.only(left: 78, bottom: 12),
              child: Text(
                isExpanded ? '收起' : '展开 ${replies.length - 1} 条回复',
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
        const SnackBar(content: Text('请先登录后再转发')),
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
      backgroundColor: const Color(0xFF1A1C21),
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
                  Color(0xFF1B1C20),
                  Color(0xFF0F1012),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: const Color(0xFFD4AF37), width: 0.6),
              boxShadow: [
                BoxShadow(
                  color: Color(0xFFD4AF37),
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
                        if (widget.imageUrls != null && widget.imageUrls!.isNotEmpty) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              widget.imageUrls!.first,
                              height: 120,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
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
                                widget.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(color: const Color(0xFFD4AF37)),
                              ),
                            ),
                            const Spacer(),
                            const Icon(Icons.open_in_new, size: 16),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontSize: 15,
                                height: 1.4,
                              ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '点击查看完整投资策略',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: const Color(0xFFD4AF37)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
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
                              _showComments ? Icons.expand_less : Icons.expand_more,
                              size: 18,
                              color: const Color(0xFFD4AF37),
                            ),
                            label: Text(
                              _showComments ? '隐藏评论' : '查看评论',
                              style: const TextStyle(color: Color(0xFFD4AF37)),
                            ),
                          ),
                          StreamBuilder<int>(
                            stream: widget.repo.watchTeacherLikesCount(widget.teacherId),
                            builder: (context, likeSnap) {
                              final streamCount = likeSnap.data ?? 0;
                              final likeCount = _likeCountOverride ?? streamCount;
                              return StreamBuilder<bool>(
                                stream: widget.repo.watchUserLiked(
                                  teacherId: widget.teacherId,
                                  userId: widget.currentUserId,
                                ),
                                builder: (context, likedSnap) {
                                  final streamLiked = likedSnap.data ?? false;
                                  if (likeSnap.hasData && likedSnap.hasData) {
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      if (mounted) _syncLikeFromStream(streamCount, streamLiked);
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
                                      liked ? Icons.thumb_up : Icons.thumb_up_outlined,
                                      size: 18,
                                      color: liked ? const Color(0xFFD4AF37) : null,
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
                            tooltip: '转发',
                          ),
                          const Spacer(),
                          Flexible(
                            child: Text(
                              '${_mergedComments.length}条',
                              style: Theme.of(context).textTheme.labelSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (_showComments) ...[
                        const SizedBox(height: 8),
                        const Divider(height: 1, color: Color(0xFF2A2C31)),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 500),
                          child: SingleChildScrollView(
                            child: _mergedComments.isEmpty
                                ? const _EmptyHint(text: '暂无评论')
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: _buildThreadedCommentsInline(_mergedComments),
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

  static const Color _accent = Color(0xFFD4AF37);

  Future<String> _getUserName() async {
    try {
      final r = await SupabaseBootstrap.client
          .from('user_profiles')
          .select('display_name')
          .eq('user_id', currentUserId)
          .maybeSingle();
      final n = r?['display_name'] as String?;
      return (n?.trim().isNotEmpty == true) ? n!.trim() : '用户';
    } catch (_) {
      return '用户';
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
          const SnackBar(content: Text('已转发')),
        );
        onSent();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('转发失败: ${e.toString().length > 40 ? e.toString().substring(0, 40) : e}')),
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
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    '转发到',
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
                stream: MessagesRepository().watchConversations(userId: currentUserId),
                builder: (context, snapshot) {
                  final list = snapshot.data ?? [];
                  if (list.isEmpty) {
                    return const Center(
                      child: Text('暂无会话，请先添加好友或加入群聊'),
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
                            style: const TextStyle(color: Color(0xFF111215)),
                          ),
                        ),
                        title: Text(conv.title),
                        subtitle: Text(conv.subtitle),
                        onTap: () async {
                          final name = await _getUserName();
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

/// 四角花纹装饰
class _CornerOrnament extends StatelessWidget {
  const _CornerOrnament({required this.rotation, required this.size, required this.color});

  final double rotation;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotation,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _CornerOrnamentPainter(color: color),
        ),
      ),
    );
  }
}

class _CornerOrnamentPainter extends CustomPainter {
  _CornerOrnamentPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const len = 40.0;
    const r = 10.0;

    void drawL(Paint p, double offset) {
      final path = Path();
      path.moveTo(offset, size.height);
      path.lineTo(offset, r + offset);
      path.quadraticBezierTo(offset, offset, r + offset, offset);
      path.lineTo(size.width, offset);
      canvas.drawPath(path, p);
    }

    final paint = Paint()
      ..color = color.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    drawL(paint, 0);

    paint.strokeWidth = 1.0;
    paint.color = color.withOpacity(0.5);
    drawL(paint, 8);

    paint.strokeWidth = 0.8;
    paint.color = color.withOpacity(0.3);
    drawL(paint, 14);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
          const SnackBar(content: Text('请先登录后再发表评论')),
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
          const SnackBar(content: Text('评论已发表')),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发表失败: ${msg.length > 120 ? msg.substring(0, 120) + '…' : msg}'),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111215),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD4AF37), width: 0.4),
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
                hintText: '写下你的评论…',
                filled: true,
                fillColor: const Color(0xFF0B0C0E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: Color(0xFFD4AF37), width: 0.4),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: Color(0xFFD4AF37), width: 0.4),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? '发表中…' : '发表'),
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
          style: const TextStyle(color: Colors.white70),
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
        style: const TextStyle(color: Colors.white70),
      ));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(
        text: content,
        style: const TextStyle(color: Colors.white70),
      ));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFD4AF37);
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
            child: comment.avatarUrl == null ||
                    comment.avatarUrl!.trim().isEmpty
                ? Text(
                    comment.userName.characters.first,
                    style: const TextStyle(color: Color(0xFF111215)),
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
                        color: Colors.white54,
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
                const SizedBox(height: 4),
                RichText(
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
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

  static const Color _accent = Color(0xFFD4AF37);
  static const Color _muted = Color(0xFF6C6F77);

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('yyyy-MM-dd HH:mm');
    final isHistory = position.isHistory;

    if (isHistory) {
      final amount = position.realizedPnlAmount ?? 0;
      final ratio = position.realizedPnlRatioPercent;
      final pnlColor = amount >= 0 ? Colors.green : Colors.red;
      final rows = <Widget>[
        if (position.buyTime != null)
          _positionLine(dateFmt.format(position.buyTime!), prefix: '买入'),
        _positionInline([
          ('成本', '${position.costPrice ?? position.buyPrice ?? '--'}'),
          if (position.buyShares != null) ('数量', '${position.buyShares}'),
        ]),
        if (position.sellTime != null || position.sellPrice != null)
          _positionInline([
            if (position.sellTime != null) ('卖出', dateFmt.format(position.sellTime!)),
            if (position.sellPrice != null) ('卖出价', position.sellPrice!.toStringAsFixed(2)),
          ]),
      ];
      return _positionCard(
        asset: position.asset,
        amountText: '${amount >= 0 ? '+' : ''}${amount.toStringAsFixed(2)}',
        ratioText: ratio != null ? '${ratio >= 0 ? '+' : ''}${ratio.toStringAsFixed(2)}%' : null,
        pnlColor: pnlColor,
        detailRows: rows,
      );
    }

    final pnl = position.floatingPnl ?? 0;
    final ratio = position.pnlRatio;
    final pnlColor = pnl >= 0 ? Colors.green : Colors.red;
    final rows = <Widget>[
      if (position.buyTime != null)
        _positionLine(dateFmt.format(position.buyTime!), prefix: '买入'),
      _positionInline([
        ('成本', '${position.costPrice ?? position.buyPrice ?? '--'}'),
        ('现价', '${position.currentPrice ?? '--'}'),
        if (position.buyShares != null) ('数量', '${position.buyShares}'),
      ]),
    ];
    return _positionCard(
      asset: position.asset,
      amountText: '${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)}',
      ratioText: ratio != null ? '${ratio >= 0 ? '+' : ''}${ratio.toStringAsFixed(2)}%' : null,
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
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF1A1C21),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: _accent, width: 0.4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          TextSpan(text: value, style: const TextStyle(color: Colors.white)),
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
      if (i > 0) spans.add(TextSpan(text: '  ', style: TextStyle(color: _muted, fontSize: 12)));
      spans.add(TextSpan(text: '${pairs[i].$1} ', style: const TextStyle(color: _muted, fontSize: 12)));
      spans.add(TextSpan(text: pairs[i].$2, style: const TextStyle(color: Colors.white, fontSize: 12)));
    }
    return Text.rich(TextSpan(style: const TextStyle(fontSize: 12), children: spans), maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  static Widget _labelVal(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 13),
        children: [
          TextSpan(text: '$label ', style: const TextStyle(color: _muted)),
          TextSpan(text: value, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0C0E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD4AF37), width: 0.3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: valueColor ?? const Color(0xFFE5E5E7)),
          ),
        ],
      ),
    );
  }
}

class _StatStack extends StatelessWidget {
  const _StatStack({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0C0E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD4AF37), width: 0.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: const Color(0xFFB9A56A),
                ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: valueColor ?? const Color(0xFFEAE7DF)),
          ),
        ],
      ),
    );
  }
}

class _PnlGrid extends StatelessWidget {
  const _PnlGrid({required this.teacher});

  final Teacher teacher;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _PnlTile(
                label: '目前持仓盈亏',
                value: teacher.pnlCurrent,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _PnlTile(
                label: '年度盈亏',
                value: teacher.pnlYear,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _PnlTile(
                label: '总盈亏',
                value: teacher.pnlTotal,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PnlSection extends StatelessWidget {
  const _PnlSection({required this.teacher});

  final Teacher teacher;

  @override
  Widget build(BuildContext context) {
    return _PnlGrid(teacher: teacher);
  }
}

class _PnlStrip extends StatelessWidget {
  const _PnlStrip({required this.teacher});

  final Teacher teacher;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111215),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD4AF37), width: 0.4),
      ),
      child: Row(
        children: [
          Expanded(
            child: _PnlMini(label: '目前持仓', value: teacher.pnlCurrent),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _PnlMini(label: '年度盈亏', value: teacher.pnlYear),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _PnlMini(label: '总盈亏', value: teacher.pnlTotal),
          ),
        ],
      ),
    );
  }
}

class _PnlMini extends StatelessWidget {
  const _PnlMini({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final isProfit = value >= 0;
    final color = isProfit ? const Color(0xFF29C36A) : const Color(0xFFE54848);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 4),
        Text(
          _formatAmount(value),
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _MainTabs extends StatelessWidget {
  const _MainTabs();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF111215),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD4AF37), width: 0.4),
      ),
      child: const TabBar(
        indicator: BoxDecoration(
          color: Color(0xFFD4AF37),
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        labelColor: Color(0xFF111215),
        unselectedLabelColor: Color(0xFFE5E5E7),
        tabs: [
          Tab(text: '今日策略'),
          Tab(text: '持仓'),
          Tab(text: '历史'),
        ],
      ),
    );
  }
}
class _PnlTile extends StatelessWidget {
  const _PnlTile({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final isProfit = value >= 0;
    final color = isProfit ? const Color(0xFF29C36A) : const Color(0xFFE54848);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0C0E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD4AF37), width: 0.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 6),
          Text(
            _formatAmount(value),
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: color),
          ),
        ],
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
    final color = isProfit ? const Color(0xFF29C36A) : const Color(0xFFE54848);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111215),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD4AF37), width: 0.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '本月总盈亏',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 4),
          Text(
            _formatAmount(value),
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _PositionCard extends StatelessWidget {
  const _PositionCard({required this.position});

  final PositionRecord position;

  @override
  Widget build(BuildContext context) {
    final isProfit = position.pnlAmount >= 0;
    final pnlColor = isProfit ? const Color(0xFF29C36A) : const Color(0xFFE54848);
    final pnlRatioText = _formatPercent(position.pnlRatio);
    final floatingColor =
        position.floatingPnl >= 0 ? const Color(0xFF29C36A) : const Color(0xFFE54848);
    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111215),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD4AF37), width: 0.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                position.asset,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatAmount(position.pnlAmount),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: pnlColor),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '持仓盈亏金额',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _InfoPair(
                  label: '买入时间',
                  value: position.buyTime,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _InfoPair(
                  label: '买入股数',
                  value: position.buyShares,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _InfoPair(
                  label: '买入价格',
                  value: position.buyPrice,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _InfoPair(
                  label: '持仓成本',
                  value: position.costPrice,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _InfoPair(
                  label: '现价',
                  value: position.currentPrice,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _InfoPair(
                  label: '浮动盈亏',
                  value: _formatAmount(position.floatingPnl),
                  valueColor: floatingColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '持仓盈亏比例  $pnlRatioText',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: pnlColor),
          ),
        ],
      ),
    );
  }

}

class _InfoPair extends StatelessWidget {
  const _InfoPair({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0C0E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD4AF37), width: 0.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: valueColor ?? const Color(0xFFE5E5E7)),
          ),
        ],
      ),
    );
  }
}

class _StrategyCard extends StatelessWidget {
  const _StrategyCard({required this.item});

  final StrategyItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111215),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD4AF37), width: 0.4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  item.summary,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
          Text(
            item.date,
            style: Theme.of(context).textTheme.labelMedium,
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

class _TradeCard extends StatelessWidget {
  const _TradeCard({required this.trade});

  final TradeRecord trade;

  @override
  Widget build(BuildContext context) {
    final isProfit = trade.pnlAmount >= 0;
    final pnlColor = isProfit ? const Color(0xFF29C36A) : const Color(0xFFE54848);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111215),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD4AF37), width: 0.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            trade.asset,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          _tradeRow('买入', trade.buyTime, trade.buyShares, trade.buyPrice),
          const SizedBox(height: 6),
          _tradeRow('卖出', trade.sellTime, trade.sellShares, trade.sellPrice),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '盈利比例  ${_formatPercent(trade.pnlRatio)}',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: pnlColor),
              ),
              const Spacer(),
              Text(
                '盈亏金额  ${_formatAmount(trade.pnlAmount)}',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: pnlColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tradeRow(String label, String time, String shares, String price) {
    return Row(
      children: [
        Text(label),
        const SizedBox(width: 8),
        Expanded(child: Text(time)),
        const SizedBox(width: 8),
        Text('股数 $shares'),
        const SizedBox(width: 8),
        Text('价格 $price'),
      ],
    );
  }
}

String _formatPercent(double value) {
  final prefix = value > 0 ? '+' : '';
  return '$prefix${value.toStringAsFixed(1)}%';
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
