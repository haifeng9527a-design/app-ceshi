import '../l10n/app_localizations.dart';

/// 将网络相关异常转为用户可读的友好提示，避免直接展示 SocketException 等堆栈。
class NetworkErrorHelper {
  NetworkErrorHelper._();

  /// 无网络或 DNS/连接失败时的统一提示。
  static const String noNetworkMessage = '无网络连接，请检查网络后重试';

  /// 通用“请稍后重试”提示。
  static const String tryAgainLaterMessage = '网络异常，请稍后重试';

  /// 判断是否为网络不可用类错误（无网、DNS 失败、连接超时等）。
  static bool isNetworkError(Object? error) {
    if (error == null) return false;
    final s = error.toString().toLowerCase();
    if (s.contains('socketexception') ||
        s.contains('clientexception') ||
        s.contains('failed host lookup') ||
        s.contains('no address associated with hostname') ||
        s.contains('connection refused') ||
        s.contains('network is unreachable') ||
        s.contains('connection timed out') ||
        s.contains('connection reset') ||
        s.contains('connection closed') ||
        s.contains('handshake exception') ||
        s.contains('errno: 7') ||
        s.contains('errno: 8') ||
        s.contains('timed out') ||
        s.contains('timeout') ||
        s.contains('unable to resolve host') ||
        s.contains('certificate') ||
        s.contains('ssl') ||
        s.contains('tls') ||
        s.contains('connection reset by peer')) {
      return true;
    }
    return false;
  }

  /// 是否为认证类错误（Token 过期、401 等），可提示重新登录。
  static bool isAuthError(Object? error) {
    if (error == null) return false;
    final s = error.toString().toLowerCase();
    return s.contains('401') ||
        (s.contains('jwt') && (s.contains('expired') || s.contains('invalid'))) ||
        s.contains('unauthorized') ||
        s.contains('invalid_api_key');
  }

  /// 认证失败时的统一提示。
  static const String authErrorMessage = '登录已过期或无效，请重新登录';

  /// 权限/RLS 类错误（403、policy 等）的提示。
  static const String permissionErrorMessage = '权限不足或操作被拒绝，请检查登录状态';

  /// 是否为权限/拒绝类错误（403、RLS policy 等）。
  static bool isPermissionError(Object? error) {
    if (error == null) return false;
    final s = error.toString().toLowerCase();
    return s.contains('403') ||
        s.contains('forbidden') ||
        s.contains('policy') ||
        s.contains('row level security') ||
        s.contains('rls');
  }

  /// 根据异常返回友好提示。若为网络类错误返回 [noNetworkMessage]，认证错误返回 [authErrorMessage]，权限错误返回 [permissionErrorMessage]，否则返回 null。
  static String? friendlyMessage(Object? error, {AppLocalizations? l10n}) {
    if (error == null) return null;
    if (l10n != null) {
      if (isNetworkError(error)) return l10n.networkNoConnection;
      if (isAuthError(error)) return l10n.networkAuthExpired;
      if (isPermissionError(error)) return l10n.networkPermissionDenied;
      return l10n.networkTryAgain;
    }
    if (isNetworkError(error)) return noNetworkMessage;
    if (isAuthError(error)) return authErrorMessage;
    if (isPermissionError(error)) return permissionErrorMessage;
    return null;
  }

  /// 得到最终要展示给用户的文案。
  /// [prefix] 如 "搜索失败"、"发送失败"、"撤回失败" 等；为 null 时仅返回友好/通用文案，不拼接前缀。
  /// [l10n] 传入时使用本地化文案。
  /// 非网络/认证错误时不展示原始异常，统一用 [tryAgainLaterMessage]。
  /// 调试时可在 logcat/控制台搜 [NetworkError] 查看真实异常。
  static String messageForUser(Object? error, {String? prefix, AppLocalizations? l10n}) {
    // 便于排查：打印真实错误（release 也可用 logcat 查看）
    if (error != null) {
      // ignore: avoid_print
      print('[NetworkError] ${prefix ?? "error"}: $error');
    }
    final friendly = friendlyMessage(error, l10n: l10n);
    final content = friendly ?? (l10n?.networkTryAgain ?? tryAgainLaterMessage);
    if (prefix != null && prefix.isNotEmpty) {
      return '$prefix：$content';
    }
    return content;
  }
}
