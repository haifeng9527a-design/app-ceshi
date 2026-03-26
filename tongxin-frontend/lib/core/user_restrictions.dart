import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../api/users_api.dart';
import '../core/api_client.dart';
import '../l10n/app_localizations.dart';

/// 当前用户限制状态（后台在 user_profiles 中配置，此处只读校验）
class UserRestrictions {
  UserRestrictions._();

  static Map<String, dynamic>? _cachedRow;
  static String? _cachedUserId;
  static DateTime? _cachedAt;
  static const _cacheDuration = Duration(seconds: 15);

  static Future<Map<String, dynamic>?> getMyRestrictionRow() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return null;
    if (_cachedUserId == uid && _cachedAt != null && DateTime.now().difference(_cachedAt!) < _cacheDuration) {
      return _cachedRow;
    }
    try {
      if (!ApiClient.instance.isAvailable) return null;
      final row = await UsersApi.instance.getMyRestrictions();
      _cachedRow = row;
      _cachedUserId = uid;
      _cachedAt = DateTime.now();
      return _cachedRow;
    } catch (_) {
      _cachedRow = null;
      _cachedUserId = uid;
      _cachedAt = DateTime.now();
      return null;
    }
  }

  static bool _isRestricted(dynamic v) {
    if (v == null) return false;
    if (v == true) return true;
    if (v == 1) return true;
    if (v.toString().toLowerCase() == 'true') return true;
    return false;
  }

  static void clearCache() {
    _cachedRow = null;
    _cachedUserId = null;
    _cachedAt = null;
  }

  static bool _isInEffect(String? iso) {
    if (iso == null || iso.trim().isEmpty) return false;
    final d = DateTime.tryParse(iso);
    return d != null && d.isAfter(DateTime.now());
  }

  static bool isBannedOrFrozen(Map<String, dynamic>? row) {
    if (row == null) return false;
    return _isInEffect(row['banned_until']?.toString()) || _isInEffect(row['frozen_until']?.toString());
  }

  static bool isRestrictedLogin(Map<String, dynamic>? row) {
    if (row == null) return false;
    if (isBannedOrFrozen(row)) return true;
    return _isRestricted(row['restrict_login']);
  }

  static bool canSendMessage(Map<String, dynamic>? row) {
    if (row == null) return true;
    if (isBannedOrFrozen(row)) return false;
    return !_isRestricted(row['restrict_send_message']);
  }

  static bool canAddFriend(Map<String, dynamic>? row) {
    if (row == null) return true;
    if (isBannedOrFrozen(row)) return false;
    return !_isRestricted(row['restrict_add_friend']);
  }

  static bool canJoinGroup(Map<String, dynamic>? row) {
    if (row == null) return true;
    if (isBannedOrFrozen(row)) return false;
    return !_isRestricted(row['restrict_join_group']);
  }

  static bool canCreateGroup(Map<String, dynamic>? row) {
    if (row == null) return true;
    if (isBannedOrFrozen(row)) return false;
    return !_isRestricted(row['restrict_create_group']);
  }

  /// 用于 APP 展示的账号状态文案
  static String getAccountStatusMessage(Map<String, dynamic>? row, BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (row == null) return l10n.restrictStatusNormal;
    final banned = row['banned_until']?.toString();
    final frozen = row['frozen_until']?.toString();
    if (_isInEffect(banned)) {
      final d = DateTime.tryParse(banned!);
      final date = d != null ? '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}' : '—';
      return l10n.restrictBannedUntil(date);
    }
    if (_isInEffect(frozen)) {
      final d = DateTime.tryParse(frozen!);
      final date = d != null ? '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}' : '—';
      return l10n.restrictFrozenUntil(date);
    }
    if (_isRestricted(row['restrict_login'])) return l10n.restrictLogin;
    if (_isRestricted(row['restrict_send_message'])) return l10n.restrictSendMessage;
    if (_isRestricted(row['restrict_add_friend'])) return l10n.restrictAddFriend;
    if (_isRestricted(row['restrict_join_group'])) return l10n.restrictJoinGroup;
    if (_isRestricted(row['restrict_create_group'])) return l10n.restrictCreateGroup;
    return l10n.restrictStatusNormal;
  }

  /// 是否有限制（用于决定是否展示状态条）
  static bool hasAnyRestriction(Map<String, dynamic>? row) {
    if (row == null) return false;
    if (isBannedOrFrozen(row)) return true;
    return _isRestricted(row['restrict_login']) ||
        _isRestricted(row['restrict_send_message']) ||
        _isRestricted(row['restrict_add_friend']) ||
        _isRestricted(row['restrict_join_group']) ||
        _isRestricted(row['restrict_create_group']);
  }
}
