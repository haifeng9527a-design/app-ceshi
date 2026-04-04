import '../../api/misc_api.dart';
import '../../api/users_api.dart';
import '../../core/api_client.dart';

/// 客服系统：系统客服配置、用户分配（全部走后端 API）
class CustomerServiceRepository {
  CustomerServiceRepository();

  bool get _useApi => ApiClient.instance.isAvailable;

  Future<String?> getSystemCustomerServiceUserId() async {
    if (!_useApi) return null;
    return MiscApi.instance.getConfig('customer_service_user_id');
  }

  Future<String?> getCustomerServiceWelcomeMessage() async {
    if (!_useApi) return null;
    return MiscApi.instance.getConfig('customer_service_welcome_message');
  }

  Future<void> setCustomerServiceWelcomeMessage(String? message) async {
    if (!_useApi) return;
    await MiscApi.instance.setConfig('customer_service_welcome_message', message);
  }

  Future<String?> getCustomerServiceAvatarUrl() async {
    if (!_useApi) return null;
    return MiscApi.instance.getConfig('customer_service_avatar_url');
  }

  Future<void> setSystemCustomerServiceUserId(String userId) async {
    if (!_useApi) return;
    await MiscApi.instance.setConfig('customer_service_user_id', userId.trim().isEmpty ? null : userId.trim());
  }

  Future<void> setCustomerServiceAvatarUrl(String? url) async {
    if (!_useApi) return;
    final value = url?.trim().isEmpty == true ? null : url?.trim();
    await MiscApi.instance.setConfig('customer_service_avatar_url', value);
  }

  Future<void> setUserRole(String userId, String role) async {
    if (!_useApi) return;
    await MiscApi.instance.setUserRole(userId, role);
  }

  Future<bool> isCustomerServiceStaff(String userId) async {
    if (userId.isEmpty || !_useApi) return false;
    return MiscApi.instance.isCustomerServiceStaff(userId);
  }

  Future<List<String>> getOnlineCustomerServiceStaff() async {
    if (!_useApi) return [];
    return MiscApi.instance.getOnlineCustomerServiceStaff();
  }

  Future<List<String>> getAllCustomerServiceStaff() async {
    if (!_useApi) return [];
    return MiscApi.instance.getAllCustomerServiceStaff();
  }

  Future<String?> getAssignedStaff(String userId) async {
    if (userId.isEmpty || !_useApi) return null;
    return MiscApi.instance.getAssignedStaff(userId);
  }

  Future<void> assignUserToStaff({
    required String userId,
    required String staffId,
  }) async {
    if (!_useApi) return;
    await MiscApi.instance.assignUserToStaff(userId: userId, staffId: staffId);
  }

  Future<String> getSystemCustomerServiceDisplayName() async {
    final id = await getSystemCustomerServiceUserId();
    if (id == null || id.isEmpty) return '客服';
    if (!_useApi) return '客服';
    final name = await UsersApi.instance.getDisplayName(id);
    return name != '用户' ? name : '客服';
  }

  Future<List<Map<String, dynamic>>> getConversationsWithSystemCs() async {
    if (!_useApi) return [];
    return MiscApi.instance.getConversationsWithSystemCs();
  }

  Future<void> trySendWelcomeMessage({
    required String conversationId,
    required String peerId,
  }) async {
    if (!_useApi) return;
    await MiscApi.instance.trySendWelcomeMessage(conversationId: conversationId, peerId: peerId);
  }

  Future<Map<String, dynamic>> broadcastMessage(String message) async {
    if (!_useApi) return {'ok': false, 'error': 'API 未配置', 'count': 0};
    return MiscApi.instance.broadcastMessage(message);
  }

  Future<String?> assignOrGetStaffForUser(String userId) async {
    if (userId.isEmpty || !_useApi) return null;
    return MiscApi.instance.assignOrGetStaffForUser(userId);
  }
}
