import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/network_error_helper.dart';
import '../messages/chat_detail_page.dart';
import '../messages/friends_repository.dart';
import '../messages/message_models.dart';
import '../messages/messages_repository.dart';
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

  static const Color _accent = Color(0xFFD4AF37);
  static const Color _muted = Color(0xFF6C6F77);
  static const Color _surface = Color(0xFF1A1C21);

  @override
  Widget build(BuildContext context) {
    final repository = TeacherRepository();
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isOwner = currentUserId == teacherId;
    return Scaffold(
      backgroundColor: const Color(0xFF111215),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _accent, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '交易员主页',
          style: TextStyle(color: _accent, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: FutureBuilder<TeacherProfile?>(
        future: repository.fetchProfile(teacherId),
        builder: (context, snapshot) {
          final profile = snapshot.data;
          if (profile == null) {
            return const Center(child: Text('暂无交易员信息', style: TextStyle(color: _muted)));
          }
          final isApproved = (profile.status ?? '') == 'approved';
          final listChildren = [
              _HeaderBlock(
                profile: profile,
                teacherId: teacherId,
                repository: repository,
              ),
              const SizedBox(height: 20),
              _StatsBlock(profile: profile),
              const SizedBox(height: 24),
              _SectionBlock(
                title: '个人介绍',
                child: _BioCard(
                  bio: profile.bio?.trim().isNotEmpty == true
                      ? profile.bio!
                      : null,
                ),
              ),
              _SectionBlock(
                title: '擅长品种',
                child: _SpecialtiesWrap(specialties: profile.specialties),
              ),
              if (isApproved) ...[
                _SectionBlock(
                  title: '交易策略',
                  child: StreamBuilder<List<TeacherStrategy>>(
                    stream: repository.watchPublishedStrategies(teacherId),
                    builder: (context, strategySnapshot) {
                      final items =
                          strategySnapshot.data ?? const <TeacherStrategy>[];
                      if (items.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            '暂无公开策略',
                            style: TextStyle(color: _muted, fontSize: 14),
                          ),
                        );
                      }
                      return Column(
                        children: items
                            .map(
                              (item) => Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.06),
                                  ),
                                ),
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
                                              color: Colors.white,
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
                  title: '我的交易记录',
                  child: StreamBuilder<List<TradeRecord>>(
                    stream: repository.watchTradeRecords(teacherId),
                    builder: (context, recordSnapshot) {
                      final items =
                          recordSnapshot.data ?? const <TradeRecord>[];
                      if (items.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            '暂无交易记录',
                            style: TextStyle(color: _muted, fontSize: 14),
                          ),
                        );
                      }
                      return Column(
                        children: items
                            .map(
                              (item) => Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.06),
                                  ),
                                ),
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
                                              color: Colors.white,
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
                  padding: EdgeInsets.fromLTRB(16, 0, 16, isOwner ? 24 : 88),
                  children: listChildren,
                ),
              ),
              _BottomFollowBar(
                teacherId: teacherId,
                teacherDisplayName: (profile.displayName?.trim().isNotEmpty == true)
                    ? profile.displayName!
                    : (profile.realName?.trim().isNotEmpty == true
                        ? profile.realName!
                        : '交易员'),
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
  }

  static String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _BottomFollowBar extends StatelessWidget {
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

  static const Color _accent = Color(0xFFD4AF37);

  Future<void> _openPrivateChat(BuildContext context) async {
    if (currentUserId.isEmpty) return;
    final navigator = Navigator.of(context);
    try {
      final conv = await MessagesRepository().createOrGetDirectConversation(
        currentUserId: currentUserId,
        friendId: teacherId,
        friendName: teacherDisplayName,
      );
      if (!context.mounted) return;
      // 关掉交易员页，清掉下层可能是的群聊，只保留根路由后压入私聊，避免点发消息后仍停在群聊
      navigator.pop();
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => ChatDetailPage(
            conversation: conv,
            initialMessages: const <ChatMessage>[],
          ),
        ),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(NetworkErrorHelper.messageForUser(e, prefix: '打开私聊失败')),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomPad),
      decoration: BoxDecoration(
        color: const Color(0xFF111215),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      child: SafeArea(
        top: false,
        child: isOwner
            ? SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('这是您的主页，无法添加自己')),
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: const Color(0xFF111215),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '加好友',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              )
            : isAlreadyFriend
                ? SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: currentUserId.isEmpty
                          ? null
                          : () => _openPrivateChat(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: const Color(0xFF111215),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '发消息',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  )
                : SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: currentUserId.isEmpty
                          ? null
                          : () async {
                              try {
                                await FriendsRepository().sendFriendRequest(
                                  requesterId: currentUserId,
                                  receiverId: teacherId,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('已发送好友申请')),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  final msg = e.toString();
                                  String displayMsg;
                                  if (msg.contains('already_friends')) {
                                    displayMsg = '你们已是好友';
                                  } else if (msg.contains('already_pending')) {
                                    displayMsg = '已发送过申请，请等待对方处理';
                                  } else {
                                    displayMsg = NetworkErrorHelper.messageForUser(e, prefix: '加好友失败');
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(displayMsg)),
                                  );
                                }
                              }
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: const Color(0xFF111215),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '加好友',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
      ),
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

  static const Color _accent = Color(0xFFD4AF37);
  static const Color _muted = Color(0xFF6C6F77);
  static const Color _surface = Color(0xFF1A1C21);

  @override
  Widget build(BuildContext context) {
    final name = (profile.displayName?.trim().isNotEmpty == true)
        ? profile.displayName!
        : ((profile.realName?.trim().isNotEmpty == true)
            ? profile.realName!
            : '交易员');
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
                        color: Color(0xFF111215),
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
                            color: Colors.white,
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
                            '关注 $count',
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
                    const Text(
                      '个性签名',
                      style: TextStyle(color: _muted, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      signature,
                      style: const TextStyle(
                        color: Colors.white70,
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
            border: Border.all(color: _accent.withOpacity(0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(
                label: '执照/注册编号',
                value: profile.licenseNo,
              ),
              const SizedBox(height: 10),
              _InfoRow(
                label: '主要市场',
                value: profile.markets,
              ),
              const SizedBox(height: 10),
              _InfoRow(
                label: '交易风格',
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

  static const Color _accent = Color(0xFFD4AF37);
  static const Color _muted = Color(0xFF6C6F77);

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
              color: Colors.white,
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

  static const Color _accent = Color(0xFFD4AF37);
  static const Color _muted = Color(0xFF6C6F77);
  static const Color _surface = Color(0xFF1A1C21);

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
        border: Border.all(color: _accent.withOpacity(0.2)),
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
              const Text(
                '战绩与收益',
                style: TextStyle(
                  color: Colors.white,
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
                  label: '总收益',
                ),
              ),
              Expanded(
                child: _StatItem(
                  value: _formatPnl(month),
                  label: '月收益',
                ),
              ),
              Expanded(
                child: _StatItem(
                  value: _formatPnl(current),
                  label: '浮动盈亏',
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
                  label: '胜场',
                ),
              ),
              Expanded(
                child: _StatItem(
                  value: '$losses',
                  label: '败场',
                ),
              ),
              Expanded(
                child: _StatItem(
                  value: '$winRate%',
                  label: '胜率',
                ),
              ),
              Expanded(
                child: _StatItem(
                  value: '$rating',
                  label: '评分',
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

  static const Color _accent = Color(0xFFD4AF37);
  static const Color _muted = Color(0xFF6C6F77);

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
                : (isNegative ? const Color(0xFFE57373) : Colors.white),
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

  static const Color _surface = Color(0xFF1A1C21);
  static const Color _muted = Color(0xFF6C6F77);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Text(
        bio ?? '暂无介绍',
        style: TextStyle(
          color: bio != null ? Colors.white.withOpacity(0.88) : _muted,
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

  static const Color _accent = Color(0xFFD4AF37);
  static const Color _surface = Color(0xFF1A1C21);
  static const Color _muted = Color(0xFF6C6F77);

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
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: const Center(
          child: Text('暂无', style: TextStyle(color: _muted, fontSize: 14)),
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: list
            .map(
              (item) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _accent.withOpacity(0.4)),
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

  static const Color _accent = Color(0xFFD4AF37);

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
                  color: Colors.white,
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
