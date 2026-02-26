import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Agora 声网配置：从 .env 读取
/// 需在 .env 中配置 AGORA_APP_ID；生产环境建议用 Token 鉴权，AGORA_TOKEN 可由后端下发
class AgoraConfig {
  static String? get appId => dotenv.env['AGORA_APP_ID']?.trim();
  static String? get token => dotenv.env['AGORA_TOKEN']?.trim();

  static bool get isAvailable => appId != null && appId!.isNotEmpty;
}
