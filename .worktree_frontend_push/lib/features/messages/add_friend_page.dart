import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/network_error_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../core/pc_dashboard_theme.dart';
import '../../api/users_api.dart';
import '../../core/api_client.dart';
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
    final l10n = AppLocalizations.of(context)!;
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showMessage(l10n.addFriendEnterEmail);
      return;
    }
    setState(() => _loading = true);
    try {
      final profile = await _repository.findByEmail(email);
      setState(() => _result = profile);
      if (profile == null) {
        _showMessage(l10n.addFriendUserNotFound);
      }
    } catch (error) {
      _showMessage(NetworkErrorHelper.messageForUser(error, prefix: l10n.msgSearchFailed, l10n: l10n));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _searchId() async {
    final l10n = AppLocalizations.of(context)!;
    final shortId = _idController.text.trim();
    if (shortId.isEmpty) {
      _showMessage(l10n.addFriendEnterAccountId);
      return;
    }
    setState(() => _loading = true);
    try {
      final profile = await _repository.findByShortId(shortId);
      setState(() => _result = profile);
      if (profile == null) {
        _showMessage(l10n.addFriendUserNotFound);
      }
    } catch (error) {
      _showMessage(NetworkErrorHelper.messageForUser(error, prefix: l10n.msgSearchFailed, l10n: l10n));
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
    final l10n = AppLocalizations.of(context)!;
    final currentUser = FirebaseAuth.instance.currentUser;
    final target = _result;
    if (currentUser == null || target == null) {
      return;
    }
    final restrictions = await UserRestrictions.getMyRestrictionRow();
    if (!UserRestrictions.canAddFriend(restrictions)) {
      UserRestrictions.clearCache();
      _showMessage(UserRestrictions.getAccountStatusMessage(restrictions, context));
      return;
    }
    setState(() => _loading = true);
    try {
      await _repository.sendFriendRequest(
        requesterId: currentUser.uid,
        receiverId: target.userId,
      );
      _showMessage(l10n.addFriendRequestSent);
    } on Exception catch (e) {
      final msg = e.toString();
      if (msg.contains('already_friends')) {
        _showMessage(l10n.addFriendAlreadyFriends);
      } else if (msg.contains('already_pending')) {
        _showMessage(l10n.addFriendAlreadyPending);
      } else {
        _showMessage(NetworkErrorHelper.messageForUser(e, prefix: l10n.msgSendFailed, l10n: l10n));
      }
    } catch (error) {
      _showMessage(NetworkErrorHelper.messageForUser(error, prefix: l10n.msgSendFailed, l10n: l10n));
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
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: PcDashboardTheme.surface,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.messagesAddFriend, style: PcDashboardTheme.titleMedium),
        backgroundColor: PcDashboardTheme.surfaceVariant,
        foregroundColor: PcDashboardTheme.text,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(PcDashboardTheme.contentPadding),
        children: [
          _SegmentTabs(
            leftLabel: l10n.addFriendTabEmail,
            middleLabel: l10n.addFriendTabAccountId,
            rightLabel: l10n.addFriendTabQrCode,
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
                hintText: AppLocalizations.of(context)!.addFriendHintEmail,
              ).copyWith(labelText: l10n.addFriendLabelTargetEmail, labelStyle: PcDashboardTheme.bodyMedium),
            ),
            const SizedBox(height: 16),
            _SearchButton(
              loading: _loading,
              onPressed: _searchEmail,
              label: AppLocalizations.of(context)!.commonSearch,
            ),
          ] else if (_tabIndex == 1) ...[
            TextField(
              controller: _idController,
              keyboardType: TextInputType.number,
              style: PcDashboardTheme.bodyLarge,
              decoration: PcDashboardTheme.inputDecoration(
                hintText: AppLocalizations.of(context)!.addFriendHintId,
              ).copyWith(labelText: l10n.addFriendLabelAccountIdRule, labelStyle: PcDashboardTheme.bodyMedium),
            ),
            const SizedBox(height: 16),
            _SearchButton(
              loading: _loading,
              onPressed: _searchId,
              label: AppLocalizations.of(context)!.commonSearch,
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openScanner,
                icon: const Icon(Icons.qr_code_scanner, size: 20),
                label: Text(AppLocalizations.of(context)!.addFriendScanQr),
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
                          ? '?'
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
                    child: Text(AppLocalizations.of(context)!.commonAdd),
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
    if (ApiClient.instance.isAvailable) {
      final profile = await UsersApi.instance.getProfile(userId);
      final shortId = profile?['short_id'] as String?;
      if (shortId != null && shortId.trim().isNotEmpty) return shortId;
      await SupabaseUserSync().ensureShortId(userId);
      final refreshed = await UsersApi.instance.getProfile(userId);
      return refreshed?['short_id'] as String?;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
              Text(AppLocalizations.of(context)!.addFriendMyQrCode, style: PcDashboardTheme.titleSmall),
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
                    l10n.commonGenerating,
                    style: PcDashboardTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                shortId == null || shortId.isEmpty
                    ? l10n.addFriendAccountIdGenerating
                    : l10n.addFriendAccountIdValue(shortId),
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
        title: Text(AppLocalizations.of(context)!.addFriendScanQr, style: PcDashboardTheme.titleMedium),
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
