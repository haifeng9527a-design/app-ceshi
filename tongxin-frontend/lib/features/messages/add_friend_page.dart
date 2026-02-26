import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/network_error_helper.dart';
import '../../core/pc_dashboard_theme.dart';
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
      backgroundColor: PcDashboardTheme.surface,
      appBar: AppBar(
        title: Text('添加好友', style: PcDashboardTheme.titleMedium),
        backgroundColor: PcDashboardTheme.surfaceVariant,
        foregroundColor: PcDashboardTheme.text,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(PcDashboardTheme.contentPadding),
        children: [
          _SegmentTabs(
            leftLabel: '邮箱',
            middleLabel: '账号ID',
            rightLabel: '二维码',
            index: _tabIndex,
            onChanged: (value) => setState(() => _tabIndex = value),
          ),
          const SizedBox(height: 20),
          if (_tabIndex == 0) ...[
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: PcDashboardTheme.bodyLarge,
              decoration: PcDashboardTheme.inputDecoration(
                hintText: '请输入对方注册邮箱',
              ).copyWith(labelText: '对方邮箱', labelStyle: PcDashboardTheme.bodyMedium),
            ),
            const SizedBox(height: 16),
            _SearchButton(
              loading: _loading,
              onPressed: _searchEmail,
              label: '搜索',
            ),
          ] else if (_tabIndex == 1) ...[
            TextField(
              controller: _idController,
              keyboardType: TextInputType.number,
              style: PcDashboardTheme.bodyLarge,
              decoration: PcDashboardTheme.inputDecoration(
                hintText: '请输入对方账号 ID',
              ).copyWith(labelText: '账号 ID（6-9位数字）', labelStyle: PcDashboardTheme.bodyMedium),
            ),
            const SizedBox(height: 16),
            _SearchButton(
              loading: _loading,
              onPressed: _searchId,
              label: '搜索',
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openScanner,
                icon: const Icon(Icons.qr_code_scanner, size: 20),
                label: const Text('扫码添加'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: PcDashboardTheme.accent,
                  side: const BorderSide(color: PcDashboardTheme.accent),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(PcDashboardTheme.radiusMd),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const _MyQrCard(),
          ],
          if (_result != null) ...[
            const SizedBox(height: 20),
            Container(
              decoration: PcDashboardTheme.cardDecoration(),
              padding: PcDashboardTheme.cardPadding,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: PcDashboardTheme.surfaceElevated,
                    child: Text(
                      _result!.displayName.isEmpty
                          ? '用'
                          : _result!.displayName[0],
                      style: PcDashboardTheme.titleMedium.copyWith(
                        color: PcDashboardTheme.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _result!.displayName,
                          style: PcDashboardTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _result!.email,
                          style: PcDashboardTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: _loading ? null : _sendRequest,
                    style: FilledButton.styleFrom(
                      backgroundColor: PcDashboardTheme.accent,
                      foregroundColor: PcDashboardTheme.surface,
                    ),
                    child: const Text('添加'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SearchButton extends StatelessWidget {
  const _SearchButton({
    required this.loading,
    required this.onPressed,
    required this.label,
  });

  final bool loading;
  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: PcDashboardTheme.accent,
          foregroundColor: PcDashboardTheme.surface,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PcDashboardTheme.radiusMd),
          ),
        ),
        child: loading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label, style: PcDashboardTheme.titleSmall.copyWith(color: PcDashboardTheme.surface)),
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
        color: PcDashboardTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(PcDashboardTheme.radiusMd),
        border: Border.all(color: PcDashboardTheme.border),
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
        color: selected ? PcDashboardTheme.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(PcDashboardTheme.radiusSm),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(PcDashboardTheme.radiusSm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                label,
                style: PcDashboardTheme.titleSmall.copyWith(
                  color: selected ? PcDashboardTheme.surface : PcDashboardTheme.accent,
                ),
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
        return Container(
          decoration: PcDashboardTheme.cardDecoration(),
          padding: PcDashboardTheme.cardPadding,
          child: Column(
            children: [
              Text('我的二维码', style: PcDashboardTheme.titleSmall),
              const SizedBox(height: 16),
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
                    color: PcDashboardTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(PcDashboardTheme.radiusSm),
                  ),
                  child: Text(
                    '生成中...',
                    style: PcDashboardTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                shortId == null || shortId.isEmpty
                    ? '账号ID：生成中...'
                    : '账号ID：$shortId',
                style: PcDashboardTheme.bodySmall,
              ),
            ],
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
      backgroundColor: PcDashboardTheme.surface,
      appBar: AppBar(
        title: Text('扫码添加', style: PcDashboardTheme.titleMedium),
        backgroundColor: PcDashboardTheme.surfaceVariant,
        foregroundColor: PcDashboardTheme.text,
        elevation: 0,
        scrolledUnderElevation: 0,
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
