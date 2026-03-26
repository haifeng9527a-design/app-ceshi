import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// 聊天图片/视频/文件专用缓存：本机可长期保留，实现「先本机再网络」。
/// 在用户自己的手机上，缓存保留时长不受限，仅受 maxNrOfCacheObjects 约束。
class ChatMediaCache {
  ChatMediaCache._();

  static const String _key = 'chat_media_cache';

  static final CacheManager instance = CacheManager(
    Config(
      _key,
      stalePeriod: const Duration(days: 365),
      maxNrOfCacheObjects: 1000,
    ),
  );
}
