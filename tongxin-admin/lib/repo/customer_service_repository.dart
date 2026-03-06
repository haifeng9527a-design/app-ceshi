import 'dart:convert';

import '../core/admin_api_client.dart';

class CustomerServiceRepository {
  CustomerServiceRepository();
  final _api = AdminApiClient.instance;

  Future<List<Map<String, dynamic>>> listUsersBasic() async {
    final resp = await _api.get('api/admin/users/basic');
    if (resp.statusCode != 200) {
      throw StateError('获取用户列表失败(${resp.statusCode})：${resp.body}');
    }
    final rows = jsonDecode(resp.body) as List<dynamic>;
    return rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> listCustomerServiceStaffBasic() async {
    final resp = await _api.get('api/admin/customer-service/staff-basic');
    if (resp.statusCode != 200) {
      throw StateError('获取客服列表失败(${resp.statusCode})：${resp.body}');
    }
    final rows = jsonDecode(resp.body) as List<dynamic>;
    return rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, int>> getAssignmentStats() async {
    final resp = await _api.get('api/customer-service/stats');
    if (resp.statusCode != 200) {
      throw StateError('获取分配统计失败(${resp.statusCode})：${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final raw = Map<String, dynamic>.from(
      (json['assignment_by_staff'] as Map?) ?? const {},
    );
    final out = <String, int>{};
    raw.forEach((key, value) {
      out[key] = (value as num?)?.toInt() ?? 0;
    });
    return out;
  }

  Future<String?> getSystemCustomerServiceUserId() async {
    final resp = await _api.get('api/config/customer_service_user_id');
    if (resp.statusCode != 200) {
      throw StateError('读取系统客服配置失败(${resp.statusCode})：${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final v = json['value']?.toString().trim();
    return (v != null && v.isNotEmpty) ? v : null;
  }

  Future<String?> getCustomerServiceWelcomeMessage() async {
    final resp = await _api.get('api/config/customer_service_welcome_message');
    if (resp.statusCode != 200) {
      throw StateError('读取欢迎语失败(${resp.statusCode})：${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final v = json['value']?.toString().trim();
    return (v != null && v.isNotEmpty) ? v : null;
  }

  Future<void> setCustomerServiceWelcomeMessage(String? message) async {
    final value = message?.trim().isEmpty == true ? null : message?.trim();
    final resp = await _api.patch(
      'api/config/customer_service_welcome_message',
      body: {'value': value},
    );
    if (resp.statusCode != 200) {
      throw StateError('保存欢迎语失败(${resp.statusCode})：${resp.body}');
    }
  }

  Future<String?> getCustomerServiceAvatarUrl() async {
    final resp = await _api.get('api/config/customer_service_avatar_url');
    if (resp.statusCode != 200) {
      throw StateError('读取客服头像配置失败(${resp.statusCode})：${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final v = json['value']?.toString().trim();
    return (v != null && v.isNotEmpty) ? v : null;
  }

  Future<void> setSystemCustomerServiceUserId(String userId) async {
    final value = userId.trim().isEmpty ? null : userId.trim();
    final resp = await _api.patch(
      'api/config/customer_service_user_id',
      body: {'value': value},
    );
    if (resp.statusCode != 200) {
      throw StateError('保存系统客服失败(${resp.statusCode})：${resp.body}');
    }
  }

  Future<void> setCustomerServiceAvatarUrl(String? url) async {
    final value = url?.trim().isEmpty == true ? null : url?.trim();
    final resp = await _api.patch(
      'api/config/customer_service_avatar_url',
      body: {'value': value},
    );
    if (resp.statusCode != 200) {
      throw StateError('保存客服头像失败(${resp.statusCode})：${resp.body}');
    }
  }

  Future<void> setUserRole(String userId, String role) async {
    final resp = await _api.patch(
      'api/users/$userId/role',
      body: {'role': role},
    );
    if (resp.statusCode != 200) {
      throw StateError('更新用户角色失败(${resp.statusCode})：${resp.body}');
    }
  }

  Future<Map<String, dynamic>> broadcastMessage(String message) async {
    final resp = await _api.post(
      'api/customer-service/broadcast',
      body: {'message': message.trim()},
    );
    if (resp.statusCode != 200) {
      return {'ok': false, 'error': resp.body, 'count': 0};
    }
    return Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
  }

  Future<String> uploadCustomerServiceAvatar({
    required String contentBase64,
    required String contentType,
    required String fileName,
  }) async {
    final resp = await _api.post(
      'api/admin/upload/customer-service-avatar',
      body: {
        'content_base64': contentBase64,
        'content_type': contentType,
        'file_name': fileName,
      },
    );
    if (resp.statusCode != 200) {
      throw StateError('上传客服头像失败(${resp.statusCode})：${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final url = json['url']?.toString().trim();
    if (url == null || url.isEmpty) {
      throw StateError('上传客服头像失败：服务端未返回URL');
    }
    return url;
  }
}
