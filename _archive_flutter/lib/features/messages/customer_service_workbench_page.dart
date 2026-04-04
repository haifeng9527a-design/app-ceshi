import 'package:flutter/material.dart';

import '../../api/users_api.dart';
import '../../core/api_client.dart';
import '../../l10n/app_localizations.dart';
import 'chat_detail_page.dart';
import 'customer_service_repository.dart';
import 'message_models.dart';

/// 客服工作台：客服人员查看并回复所有用户与系统客服的会话
class CustomerServiceWorkbenchPage extends StatefulWidget {
  const CustomerServiceWorkbenchPage({super.key});

  @override
  State<CustomerServiceWorkbenchPage> createState() =>
      _CustomerServiceWorkbenchPageState();
}

class _CustomerServiceWorkbenchPageState
    extends State<CustomerServiceWorkbenchPage> {
  final _csRepo = CustomerServiceRepository();
  List<Map<String, dynamic>> _conversations = [];
  Map<String, String> _peerNames = {};
  Map<String, String?> _peerAvatars = {};
  bool _loading = true;
  String? _loadError;
  String? _csId;
  String? _csDisplayName;

  static const Color _accent = Color(0xFFD4AF37);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final csId = await _csRepo.getSystemCustomerServiceUserId();
      final csName = await _csRepo.getSystemCustomerServiceDisplayName();
      if (csId == null || csId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loadError = '未配置系统客服';
          _loading = false;
        });
        return;
      }
      final list = await _csRepo.getConversationsWithSystemCs();
      final peerIds = list
          .map((r) => r['peer_user_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final names = <String, String>{};
      final avatars = <String, String?>{};
      if (peerIds.isNotEmpty) {
        if (ApiClient.instance.isAvailable) {
          final batch = await UsersApi.instance.getProfilesBatch(peerIds);
          for (final uid in peerIds) {
            final p = batch[uid];
            if (p != null) {
              names[uid] = p['display_name'] ?? '用户';
              avatars[uid] = p['avatar_url'];
            }
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _csId = csId;
        _csDisplayName = csName;
        _conversations = list;
        _peerNames = names;
        _peerAvatars = avatars;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('CustomerServiceWorkbenchPage _load: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  String _peerName(String? peerId) {
    if (peerId == null || peerId.isEmpty) return '—';
    return _peerNames[peerId] ?? peerId;
  }

  String? _peerAvatar(String? peerId) {
    if (peerId == null || peerId.isEmpty) return null;
    return _peerAvatars[peerId];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profileCsWorkbench),
        backgroundColor: const Color(0xFF0B0C0E),
        foregroundColor: _accent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _loadError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _load,
                          child: Text(l10n.commonRetry),
                        ),
                      ],
                    ),
                  ),
                )
              : _conversations.isEmpty
                  ? Center(
                      child: Text(
                        l10n.msgNoConversations,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _conversations.length,
                        itemBuilder: (context, index) {
                          final c = _conversations[index];
                          final peerId = c['peer_user_id'] as String? ?? '';
                          final lastMsg = c['last_message']?.toString() ?? '';
                          final lastTime = c['last_time'] != null
                              ? DateTime.tryParse(c['last_time'].toString())
                              : null;
                          final unread = c['unread_count'] as int? ?? 0;
                          return ListTile(
                            leading: CircleAvatar(
                              radius: 24,
                              backgroundColor: _accent.withOpacity(0.2),
                              backgroundImage: _peerAvatar(peerId) != null
                                  ? NetworkImage(_peerAvatar(peerId)!)
                                  : null,
                              child: _peerAvatar(peerId) != null
                                  ? null
                                  : Text(
                                      _peerName(peerId).isNotEmpty
                                          ? _peerName(peerId)[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: _accent,
                                        fontSize: 18,
                                      ),
                                    ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _peerName(peerId),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (unread > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color:
                                          Theme.of(context).colorScheme.error,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      unread > 99 ? '99+' : '$unread',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              lastMsg.isEmpty ? '—' : lastMsg,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 13,
                              ),
                            ),
                            trailing: lastTime != null
                                ? Text(
                                    _formatTime(lastTime),
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 12,
                                    ),
                                  )
                                : null,
                            onTap: () => _openChat(context, c),
                          );
                        },
                      ),
                    ),
    );
  }

  String _formatTime(DateTime t) {
    final local = t.isUtc ? t.toLocal() : t;
    final now = DateTime.now();
    if (now.year == local.year &&
        now.month == local.month &&
        now.day == local.day) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.month}/${local.day}';
  }

  Future<void> _openChat(
      BuildContext context, Map<String, dynamic> convRow) async {
    final convId = convRow['id'] as String? ?? '';
    final peerId = convRow['peer_user_id'] as String? ?? '';
    if (convId.isEmpty || _csId == null || _csDisplayName == null) return;

    final conversation = Conversation.fromSupabase(
      row: convRow,
      unreadCount: 0,
      peerId: peerId,
    );

    if (!context.mounted) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ChatDetailPage(
              conversation: conversation,
              initialMessages: const <ChatMessage>[],
              overrideSenderId: _csId,
              overrideSenderName: _csDisplayName,
            ),
          ),
        )
        .then((_) => _load());
  }
}
