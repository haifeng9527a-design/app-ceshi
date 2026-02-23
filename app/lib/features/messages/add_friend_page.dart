import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/network_error_helper.dart';
import '../../core/supabase_bootstrap.dart';
import '../../core/user_restrictions.dart';
import 'friend_models.dart';
import 'friends_repository.dart';
import 'supabase_user_sync.dart';

class AddFriendPage extends StatefulWidget {
  const AddFriendPage({super.key});

  @override
  State<AddFriendPage> createState() => _AddFriendPageState();
}

class _AddFriendPageState extends State<AddFriendPage> {
  final _emailController = TextEditingController();
  final _idController = TextEditingController();
  final _repository = FriendsRepository();
  bool _loading = false;
  FriendProfile? _result;
  int _tabIndex = 0;

  @override
  void dispose() {
    _emailController.dispose();
    _idController.dispose();
    super.dispose();
  }

  Future<void> _searchEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showMessage('请输入邮箱');
      return;
    }
    setState(() => _loading = true);
    try {
      final profile = await _repository.findByEmail(email);
      setState(() => _result = profile);
      if (profile == null) {
        _showMessage('未找到该用户');
      }
    } catch (error) {
      _showMessage(NetworkErrorHelper.messageForUser(error, prefix: '搜索失败'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _searchId() async {
    final shortId = _idController.text.trim();
    if (shortId.isEmpty) {
      _showMessage('请输入账号ID');
      return;
    }
    setState(() => _loading = true);
    try {
      final profile = await _repository.findByShortId(shortId);
      setState(() => _result = profile);
      if (profile == null) {
        _showMessage('未找到该用户');
      }
    } catch (error) {
      _showMessage(NetworkErrorHelper.messageForUser(error, prefix: '搜索失败'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openScanner() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScanPage()),
    );
    if (result == null || result.isEmpty) {
      return;
    }
    _idController.text = result;
    setState(() => _tabIndex = 1);
    await _searchId();
  }

  Future<void> _sendRequest() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final target = _result;
    if (currentUser == null || target == null) {
      return;
    }
    final restrictions = await UserRestrictions.getMyRestrictionRow();
    if (!UserRestrictions.canAddFriend(restrictions)) {
      UserRestrictions.clearCache();
      _showMessage(UserRestrictions.getAccountStatusMessage(restrictions));
      return;
    }
    setState(() => _loading = true);
    try {
      await _repository.sendFriendRequest(
        requesterId: currentUser.uid,
        receiverId: target.userId,
      );
      _showMessage('好友申请已发送');
    } on Exception catch (e) {
      final msg = e.toString();
      if (msg.contains('already_friends')) {
        _showMessage('你们已是好友');
      } else if (msg.contains('already_pending')) {
        _showMessage('已发送过申请，请等待对方处理');
      } else {
        _showMessage(NetworkErrorHelper.messageForUser(e, prefix: '发送失败'));
      }
    } catch (error) {
      _showMessage(NetworkErrorHelper.messageForUser(error, prefix: '发送失败'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('添加好友'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SegmentTabs(
            leftLabel: '邮箱',
            middleLabel: '账号ID',
            rightLabel: '二维码',
            index: _tabIndex,
            onChanged: (value) => setState(() => _tabIndex = value),
          ),
          const SizedBox(height: 16),
          if (_tabIndex == 0) ...[
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: '对方邮箱',
                hintText: '请输入对方注册邮箱',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loading ? null : _searchEmail,
              child: const Text('搜索'),
            ),
          ] else if (_tabIndex == 1) ...[
            TextField(
              controller: _idController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '账号 ID（6-9位数字）',
                hintText: '请输入对方账号 ID',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loading ? null : _searchId,
              child: const Text('搜索'),
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: _openScanner,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('扫码添加'),
            ),
            const SizedBox(height: 16),
            const _MyQrCard(),
          ],
          if (_result != null) ...[
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF1A1C21),
                  child: Text(
                    _result!.displayName.isEmpty
                        ? '用'
                        : _result!.displayName[0],
                    style: const TextStyle(color: Color(0xFFD4AF37)),
                  ),
                ),
                title: Text(_result!.displayName),
                subtitle: Text(_result!.email),
                trailing: FilledButton(
                  onPressed: _loading ? null : _sendRequest,
                  child: const Text('添加'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SegmentTabs extends StatelessWidget {
  const _SegmentTabs({
    required this.leftLabel,
    required this.middleLabel,
    required this.rightLabel,
    required this.index,
    required this.onChanged,
  });

  final String leftLabel;
  final String middleLabel;
  final String rightLabel;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF111215),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2D34)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentTab(
              label: leftLabel,
              selected: index == 0,
              onTap: () => onChanged(0),
            ),
          ),
          Expanded(
            child: _SegmentTab(
              label: middleLabel,
              selected: index == 1,
              onTap: () => onChanged(1),
            ),
          ),
          Expanded(
            child: _SegmentTab(
              label: rightLabel,
              selected: index == 2,
              onTap: () => onChanged(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentTab extends StatelessWidget {
  const _SegmentTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFD4AF37) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.black : const Color(0xFFD4AF37),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MyQrCard extends StatelessWidget {
  const _MyQrCard();

  Future<String?> _loadShortId(String userId) async {
    if (!SupabaseBootstrap.isReady) {
      return null;
    }
    final row = await SupabaseBootstrap.client
        .from('user_profiles')
        .select('short_id')
        .eq('user_id', userId)
        .maybeSingle();
    final current = row?['short_id'] as String?;
    if (current != null && current.trim().isNotEmpty) {
      return current;
    }
    await SupabaseUserSync().ensureShortId(userId);
    final refreshed = await SupabaseBootstrap.client
        .from('user_profiles')
        .select('short_id')
        .eq('user_id', userId)
        .maybeSingle();
    return refreshed?['short_id'] as String?;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<String?>(
      future: _loadShortId(user.uid),
      builder: (context, snapshot) {
        final shortId = snapshot.data?.trim();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  '我的二维码',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                if (shortId != null && shortId.isNotEmpty)
                  QrImageView(
                    data: shortId,
                    size: 180,
                    backgroundColor: Colors.white,
                  )
                else
                  Container(
                    height: 180,
                    width: 180,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '生成中...',
                      style: TextStyle(color: Color(0xFF6C6F77)),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  shortId == null || shortId.isEmpty
                      ? '账号ID：生成中...'
                      : '账号ID：$shortId',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6C6F77)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QrScanPage extends StatefulWidget {
  const _QrScanPage();

  @override
  State<_QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<_QrScanPage> {
  bool _found = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫码添加'),
      ),
      body: MobileScanner(
        onDetect: (capture) {
          if (_found) return;
          if (capture.barcodes.isEmpty) {
            return;
          }
          final value = capture.barcodes.first.rawValue;
          if (value == null || value.isEmpty) {
            return;
          }
          _found = true;
          Navigator.of(context).pop(value);
        },
      ),
    );
  }
}
