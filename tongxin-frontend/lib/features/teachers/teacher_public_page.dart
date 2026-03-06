import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/design/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../auth/login_page.dart';
import '../../core/network_error_helper.dart';
import '../../ui/components/components.dart';
import '../home/featured_teacher_page.dart';
import '../messages/friends_repository.dart';
import 'teacher_models.dart';
import 'teacher_repository.dart';

class TeacherPublicPage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final repository = TeacherRepository();
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        final currentUserId = authSnapshot.data?.uid ?? '';
        final isOwner = currentUserId == teacherId;
        return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _accent, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          AppLocalizations.of(context)!.teachersProfileTitle,
          style: const TextStyle(color: _accent, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: FutureBuilder<TeacherProfile?>(
        future: repository.fetchProfile(teacherId),
        builder: (context, snapshot) {
          final profile = snapshot.data;
          if (profile == null) {
            return Center(child: Text(AppLocalizations.of(context)!.teachersNoTeacherInfo, style: const TextStyle(color: _muted)));
          }
          final isApproved = (profile.status ?? '') == 'approved';
          final listChildren = [
              _HeaderBlock(
                profile: profile,
                teacherId: teacherId,
                repository: repository,
              ),
              const SizedBox(height: AppSpacing.lg),
              _StatsBlock(profile: profile),
              const SizedBox(height: AppSpacing.xl),
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
              if (isApproved) ...[
                _SectionBlock(
                  title: AppLocalizations.of(context)!.teachersStrategySection,
                  child: StreamBuilder<List<TeacherStrategy>>(
                    stream: repository.watchPublishedStrategies(teacherId),
                    builder: (context, strategySnapshot) {
                      final items =
                          strategySnapshot.data ?? const <TeacherStrategy>[];
                      if (items.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            AppLocalizations.of(context)!.teachersNoPublicStrategy,
                            style: const TextStyle(color: _muted, fontSize: 14),
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
                                            item.title,
                                            style: const TextStyle(
                                              color: AppColors.textPrimary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          if ((item.content ?? item.summary)
                                              .trim()
                                              .isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              (item.content ?? item.summary)
                                                  .trim(),
                                              style: const TextStyle(
                                                color: _muted,
                                                fontSize: 12,
                                              ),
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Text(
                                      _formatDate(item.createdAt),
                                      style: const TextStyle(
                                        color: _muted,
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
              if (isOwner && isApproved) ...[
                _SectionBlock(
                  title: AppLocalizations.of(context)!.teachersMyTradeRecords,
                  child: StreamBuilder<List<TradeRecord>>(
                    stream: repository.watchTradeRecords(teacherId),
                    builder: (context, recordSnapshot) {
                      final items =
                          recordSnapshot.data ?? const <TradeRecord>[];
                      if (items.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            AppLocalizations.of(context)!.teachersNoTradeRecords,
                            style: const TextStyle(color: _muted, fontSize: 14),
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
                                              color: _muted,
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
                                          color: _accent,
                                          size: 20,
                                        ),
                                        onPressed: () {
                                          showDialog(
                                            context: context,
                                            builder: (_) => Dialog(
                                              backgroundColor: _surface,
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
                                          color: _muted,
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
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    isOwner ? AppSpacing.xl : AppSpacing.xxxl + AppSpacing.sm,
                  ),
                  children: listChildren,
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
                repository: repository,
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
}

class _BottomFollowBar extends StatefulWidget {
  const _BottomFollowBar({
    required this.teacherId,
    required this.teacherDisplayName,
    required this.currentUserId,
    required this.isOwner,
    required this.repository,
    this.isAlreadyFriend = false,
  });

  final String teacherId;
  final String teacherDisplayName;
  final String currentUserId;
  final bool isOwner;
  final TeacherRepository repository;
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
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
          ),
          child: SafeArea(
            top: false,
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

  static const Color _accent = AppColors.primary;
  static const Color _muted = AppColors.textTertiary;
  static const Color _surface = AppColors.surface2;

  @override
  Widget build(BuildContext context) {
    final name = (profile.displayName?.trim().isNotEmpty == true)
        ? profile.displayName!
        : ((profile.realName?.trim().isNotEmpty == true)
            ? profile.realName!
            : AppLocalizations.of(context)!.profileTeacher);
    // 个性签名优先用 user_profiles.signature（与「我的」页同步），无则用 teacher_profiles.title
    final signature = (profile.signature?.trim().isNotEmpty == true
            ? profile.signature
            : null) ??
        (profile.title?.trim().isNotEmpty == true ? profile.title! : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: _accent,
              backgroundImage: profile.avatarUrl?.trim().isNotEmpty == true
                  ? NetworkImage(profile.avatarUrl!.trim())
                  : null,
              child: profile.avatarUrl?.trim().isNotEmpty == true
                  ? null
                  : Text(
                      name.isEmpty ? '?' : name[0],
                      style: const TextStyle(
                        fontSize: 24,
                        color: AppColors.surface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      StreamBuilder<int>(
                        stream: FriendsRepository().watchFriendCount(userId: teacherId),
                        builder: (context, countSnapshot) {
                          final count = countSnapshot.data ?? 0;
                          return Text(
                            AppLocalizations.of(context)!.teachersFollowingCount(count),
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 12,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  if (signature != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      AppLocalizations.of(context)!.teachersSignatureLabel,
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      signature,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _accent.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(
                label: AppLocalizations.of(context)!.teachersLicenseNoLabel,
                value: profile.licenseNo,
              ),
              const SizedBox(height: 10),
              _InfoRow(
                label: AppLocalizations.of(context)!.teachersMainMarket,
                value: profile.markets,
              ),
              const SizedBox(height: 10),
              _InfoRow(
                label: AppLocalizations.of(context)!.teachersTradingStyleShort,
                value: profile.style,
              ),
            ],
          ),
        ),
      ],
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
  const _StatsBlock({required this.profile});

  final TeacherProfile profile;

  static const Color _accent = AppColors.primary;
  static const Color _surface = AppColors.surface2;

  @override
  Widget build(BuildContext context) {
    final total = profile.pnlTotal ?? 0;
    final month = profile.pnlMonth ?? 0;
    final current = profile.pnlCurrent ?? 0;
    final wins = profile.wins ?? 0;
    final losses = profile.losses ?? 0;
    final totalTrades = wins + losses;
    final winRate = totalTrades > 0
        ? (100.0 * wins / totalTrades).toStringAsFixed(0)
        : '0';
    final rating = profile.rating ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
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
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatItem(
                  value: _formatPnl(total),
                  label: AppLocalizations.of(context)!.teachersTotalEarnings,
                ),
              ),
              Expanded(
                child: _StatItem(
                  value: _formatPnl(month),
                  label: AppLocalizations.of(context)!.teachersMonthlyEarnings,
                ),
              ),
              Expanded(
                child: _StatItem(
                  value: _formatPnl(current),
                  label: AppLocalizations.of(context)!.featuredFloatingPnl,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatItem(
                  value: '$wins',
                  label: AppLocalizations.of(context)!.featuredWins,
                ),
              ),
              Expanded(
                child: _StatItem(
                  value: '$losses',
                  label: AppLocalizations.of(context)!.featuredLosses,
                ),
              ),
              Expanded(
                child: _StatItem(
                  value: '$winRate%',
                  label: AppLocalizations.of(context)!.featuredWinRate,
                ),
              ),
              Expanded(
                child: _StatItem(
                  value: '$rating',
                  label: AppLocalizations.of(context)!.teachersRatingLabel,
                ),
              ),
            ],
          ),
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
  const _StatItem({required this.value, required this.label});

  final String value;
  final String label;

  static const Color _accent = AppColors.primary;
  static const Color _muted = AppColors.textTertiary;

  @override
  Widget build(BuildContext context) {
    final isPositive = value.startsWith('+');
    final isNegative = value.startsWith('-') && !value.startsWith('-0');
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: isPositive
                ? _accent
                : (isNegative ? AppColors.negative : AppColors.textPrimary),
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
      ],
    );
  }
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
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
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Center(
          child: Text(AppLocalizations.of(context)!.commonNone, style: const TextStyle(color: _muted, fontSize: 14)),
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: list
            .map(
              (item) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
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

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({required this.title, required this.child});

  final String title;
  final Widget child;

  static const Color _accent = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
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
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
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
