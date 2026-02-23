import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';

class FirebaseBootstrap {
  static bool isReady = false;

  static Future<void> init() async {
    try {
      if (kIsWeb) {
        const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
        const appId = String.fromEnvironment('FIREBASE_APP_ID');
        const messagingSenderId =
            String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
        const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
        const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
        const storageBucket =
            String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
        const measurementId =
            String.fromEnvironment('FIREBASE_MEASUREMENT_ID');
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
