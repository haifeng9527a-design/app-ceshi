import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class LocalDebugMode {
  LocalDebugMode._();

  static bool get isEnabled {
    if (kIsWeb || !kDebugMode) return false;
    if (!Platform.isMacOS) return false;
    final raw = dotenv.env['LOCAL_DEV_MODE']?.trim().toLowerCase();
    if (raw == null || raw.isEmpty) return false;
    return raw == '1' || raw == 'true' || raw == 'yes' || raw == 'on';
  }
}
