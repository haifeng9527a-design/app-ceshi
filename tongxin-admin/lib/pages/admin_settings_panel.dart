import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../core/supabase_bootstrap.dart';
import '../l10n/admin_strings.dart';
import '../repo/customer_service_repository.dart';

class AdminSettingsPanel extends StatefulWidget {
  const AdminSettingsPanel({super.key});

  @override
  State<AdminSettingsPanel> createState() => _AdminSettingsPanelState();
}

class _AdminSettingsPanelState extends State<AdminSettingsPanel> {
  final _csRepo = CustomerServiceRepository();
  final _avatarController = TextEditingController();
  final _welcomeController = TextEditingController();
  final _broadcastController = TextEditingController();
  final _picker = ImagePicker();

  String? _systemCsUserId;
  bool _broadcasting = false;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _csStaff = [];
  bool _loading = true;
  String? _loadError;
  bool _saving = false;
  bool _uploadingAvatar = false;

  static const Color _accent = Color(0xFFD4AF37);

  @override
  void initState() {
    super.initState();
    _avatarController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _avatarController.dispose();
    _welcomeController.dispose();
    _broadcastController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final csId = await _csRepo.getSystemCustomerServiceUserId();
      final avatarUrl = await _csRepo.getCustomerServiceAvatarUrl();
      final welcomeMsg = await _csRepo.getCustomerServiceWelcomeMessage();
      final usersRes = await SupabaseBootstrap.client
          .from('user_profiles')
          .select('user_id, display_name, email, short_id, avatar_url')
          .order('display_name');
      final users = (usersRes as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final csStaffRes = await SupabaseBootstrap.client
          .from('user_profiles')
          .select('user_id, display_name, email, short_id')
          .eq('role', 'customer_service');
      final staff = (csStaffRes as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _systemCsUserId = csId;
        _avatarController.text = avatarUrl ?? '';
        _welcomeController.text = welcomeMsg ?? '';
        _users = users;
        _csStaff = staff;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('AdminSettingsPanel _load: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _saveSystemCs(String? userId) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _csRepo.setSystemCustomerServiceUserId(userId ?? '');
      await _csRepo.setCustomerServiceAvatarUrl(
        _avatarController.text.trim().isEmpty ? null : _avatarController.text.trim(),
      );
      await _csRepo.setCustomerServiceWelcomeMessage(
        _welcomeController.text.trim().isEmpty ? null : _welcomeController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AdminStrings.adminSaved)),
      );
      setState(() {
        _systemCsUserId = userId;
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AdminStrings.adminSaveFailed(e.toString())),
          backgroundColor: Colors.red.shade700,
        ),
      );
      setState(() => _saving = false);
    }
  }

  Future<void> _setUserAsSystemCs(String userId) async {
    await _saveSystemCs(userId);
  }

  Future<void> _addCsStaff(String userId) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _csRepo.setUserRole(userId, 'customer_service');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AdminStrings.adminSaved)),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AdminStrings.adminSaveFailed(e.toString())),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _uploadAvatar() async {
    if (_uploadingAvatar || !SupabaseBootstrap.isReady) return;
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _uploadingAvatar = true);
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      final safeExt = ['jpg', 'jpeg', 'png', 'webp'].contains(ext) ? ext : 'jpg';
      final path = 'customer_service/cs_avatar_${DateTime.now().millisecondsSinceEpoch}.$safeExt';
      await SupabaseBootstrap.client.storage.from('avatars').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: safeExt == 'png' ? 'image/png' : safeExt == 'webp' ? 'image/webp' : 'image/jpeg',
              upsert: true,
            ),
          );
      final url = SupabaseBootstrap.client.storage.from('avatars').getPublicUrl(path);
      await _csRepo.setCustomerServiceAvatarUrl(url);
      if (!mounted) return;
      setState(() {
        _avatarController.text = url;
        _uploadingAvatar = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AdminStrings.adminSaved)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingAvatar = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AdminStrings.adminSaveFailed(e.toString())),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _doBroadcast() async {
    final msg = _broadcastController.text.trim();
    if (msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AdminStrings.adminCsBroadcastEmpty)),
      );
      return;
    }
    setState(() => _broadcasting = true);
    try {
      final res = await _csRepo.broadcastMessage(msg);
      if (!mounted) return;
      final ok = res['ok'] == true;
      final count = res['count'] as int? ?? 0;
      final err = res['error']?.toString();
      if (ok) {
        _broadcastController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AdminStrings.adminCsBroadcastSuccess('$count')),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err ?? ''),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _broadcasting = false);
    }
  }

  Future<void> _removeCsStaff(String userId) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _csRepo.setUserRole(userId, 'user');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AdminStrings.adminSaved)),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AdminStrings.adminSaveFailed(e.toString())),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _userLabel(Map<String, dynamic> u) {
    final name = u['display_name']?.toString().trim();
    final email = u['email']?.toString().trim();
    final shortId = u['short_id']?.toString();
    if (name != null && name.isNotEmpty) return name;
    if (email != null && email.isNotEmpty) return email;
    return shortId ?? u['user_id']?.toString() ?? '—';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          AdminStrings.adminSettings,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: _accent,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          AdminStrings.adminSettingsDesc,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
        ),
        const SizedBox(height: 24),
        Text(
          AdminStrings.adminCsConfig,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: _accent),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: Color(0xFFD4AF37))))
        else if (_loadError != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 12),
                  Text(_loadError!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh, size: 18), label: Text(AdminStrings.commonRetry)),
                ],
              ),
            ),
          )
        else ...[
          _buildRow(AdminStrings.adminCsSystemAccount, _systemCsUserId != null && _systemCsUserId!.isNotEmpty
              ? _userLabel(_users.firstWhere((u) => u['user_id'] == _systemCsUserId, orElse: () => {'user_id': _systemCsUserId, 'display_name': _systemCsUserId}))
              : AdminStrings.adminCsNotConfigured),
          const SizedBox(height: 8),
          Text(AdminStrings.adminCsSystemAccountHint, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6C6F77))),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _users.take(20).map((u) {
              final uid = u['user_id']?.toString() ?? '';
              final isCurrent = uid == _systemCsUserId;
              return FilterChip(
                label: Text(_userLabel(u)),
                selected: isCurrent,
                onSelected: isCurrent ? null : (_) => _setUserAsSystemCs(uid),
                selectedColor: _accent.withOpacity(0.3),
                checkmarkColor: _accent,
              );
            }).toList(),
          ),
          if (_users.length > 20)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('... 共 ${_users.length} 个用户，可在用户管理中操作', style: Theme.of(context).textTheme.bodySmall),
            ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _avatarController,
                  decoration: InputDecoration(
                    labelText: AdminStrings.adminCsAvatarUrl,
                    hintText: 'https://... 或点击上传',
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _saveSystemCs(_systemCsUserId),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  FilledButton.icon(
                    onPressed: _uploadingAvatar ? null : _uploadAvatar,
                    icon: _uploadingAvatar
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.upload_file, size: 20),
                    label: Text(AdminStrings.adminCsUploadAvatar),
                  ),
                  if (_avatarController.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        _avatarController.text.trim(),
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(width: 64, height: 64, child: Icon(Icons.broken_image)),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _welcomeController,
            decoration: InputDecoration(
              labelText: AdminStrings.adminCsWelcomeMessage,
              hintText: AdminStrings.adminCsWelcomeMessageHint,
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: 3,
            onSubmitted: (_) => _saveSystemCs(_systemCsUserId),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : () => _saveSystemCs(_systemCsUserId),
            child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : Text(AdminStrings.commonSave),
          ),
          const SizedBox(height: 32),
          Text(
            AdminStrings.adminCsBroadcast,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: _accent),
          ),
          const SizedBox(height: 4),
          Text(AdminStrings.adminCsBroadcastHint, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6C6F77))),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _broadcastController,
                  decoration: const InputDecoration(
                    hintText: '输入群发内容...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _broadcasting ? null : _doBroadcast,
                icon: _broadcasting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.send, size: 20),
                label: Text(AdminStrings.adminCsBroadcastSend),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text(
            AdminStrings.adminCsStaff,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: _accent),
          ),
          const SizedBox(height: 4),
          Text(AdminStrings.adminCsStaffHint, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6C6F77))),
          const SizedBox(height: 12),
          ..._csStaff.map((u) {
            final uid = u['user_id']?.toString() ?? '';
            return ListTile(
              leading: CircleAvatar(
                radius: 20,
                backgroundColor: _accent.withOpacity(0.2),
                child: Text(_userLabel(u).isNotEmpty ? _userLabel(u)[0].toUpperCase() : '?', style: const TextStyle(color: _accent)),
              ),
              title: Text(_userLabel(u)),
              subtitle: Text(uid),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                onPressed: _saving ? null : () => _removeCsStaff(uid),
                tooltip: AdminStrings.adminRemoveCsStaff,
              ),
            );
          }),
          const SizedBox(height: 12),
          Text('添加客服人员：从下方选择用户', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _users
                .where((u) => !_csStaff.any((s) => s['user_id'] == u['user_id']))
                .take(15)
                .map((u) {
              final uid = u['user_id']?.toString() ?? '';
              return ActionChip(
                label: Text(_userLabel(u)),
                onPressed: _saving ? null : () => _addCsStaff(uid),
                avatar: const Icon(Icons.add, size: 18, color: Color(0xFFD4AF37)),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: Color(0xFF6C6F77), fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
