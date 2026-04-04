import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class FirebaseBootstrap {
  static bool isReady = false;
  static const String _fallbackApiKey = 'AIzaSyDtLh40QWY0oF1p3ka2vz9sto3OK1btkj0';
  static const String _fallbackAppId = '1:130160287801:ios:1c9a74150046fd9c26ade8';
  static const String _fallbackMessagingSenderId = '130160287801';
  static const String _fallbackProjectId = 'cesium-29c23';
  static const String _fallbackAuthDomain = 'cesium-29c23.firebaseapp.com';
  static const String _fallbackStorageBucket = 'cesium-29c23.firebasestorage.app';

  static String _webConfigValue(
    String key, {
    String fallback = '',
  }) {
    final fromDotenv = dotenv.env[key]?.trim();
    if (fromDotenv != null && fromDotenv.isNotEmpty) return fromDotenv;
    return fallback;
  }

  static Future<void> init() async {
    try {
      if (kIsWeb) {
        final apiKey = _webConfigValue(
          'FIREBASE_API_KEY',
          fallback: _fallbackApiKey,
        );
        final appId = _webConfigValue(
          'FIREBASE_APP_ID',
          fallback: _fallbackAppId,
        );
        final messagingSenderId = _webConfigValue(
          'FIREBASE_MESSAGING_SENDER_ID',
          fallback: _fallbackMessagingSenderId,
        );
        final projectId = _webConfigValue(
          'FIREBASE_PROJECT_ID',
          fallback: _fallbackProjectId,
        );
        final authDomain = _webConfigValue(
          'FIREBASE_AUTH_DOMAIN',
          fallback: _fallbackAuthDomain,
        );
        final storageBucket = _webConfigValue(
          'FIREBASE_STORAGE_BUCKET',
          fallback: _fallbackStorageBucket,
        );
        final measurementId = _webConfigValue('FIREBASE_MEASUREMENT_ID');
        if (apiKey.isEmpty ||
            appId.isEmpty ||
            messagingSenderId.isEmpty ||
            projectId.isEmpty) {
          throw StateError('Missing Firebase web config');
        }
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: apiKey,
            appId: appId,
            messagingSenderId: messagingSenderId,
            projectId: projectId,
            authDomain: authDomain.isEmpty ? null : authDomain,
            storageBucket: storageBucket.isEmpty ? null : storageBucket,
            measurementId: measurementId.isEmpty ? null : measurementId,
          ),
        );
      } else {
        await Firebase.initializeApp();
      }
      isReady = true;
      debugPrint('[通知] Firebase 初始化成功');
    } catch (error) {
      isReady = false;
      debugPrint('[通知] Firebase 初始化失败: $error');
    }
  }
}
