import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../features/trading/trading_api_client.dart';
import 'api_client.dart';
import 'firebase_bootstrap.dart';

/// App 启动阶段主动同步交易相关数据，避免首次进入交易页看到旧数据。
class StartupDataSyncService {
  StartupDataSyncService._();
  static final StartupDataSyncService instance = StartupDataSyncService._();

  static const Duration _cooldown = Duration(seconds: 45);

  bool _running = false;
  DateTime? _lastSuccessAt;

  Future<void> syncTradingDataOnAppStart({bool force = false}) async {
    if (_running) return;
    if (!ApiClient.instance.isAvailable) return;
    if (!FirebaseBootstrap.isReady) return;
    if (FirebaseAuth.instance.currentUser == null) return;

    final now = DateTime.now();
    if (!force &&
        _lastSuccessAt != null &&
        now.difference(_lastSuccessAt!) < _cooldown) {
      return;
    }

    _running = true;
    try {
      final api = TradingApiClient.instance;
      await Future.wait<void>([
        _ignoreError(() => api.getSummary()),
        _ignoreError(() => api.getAccount()),
        _ignoreError(() => api.getOpenOrders(page: 1, pageSize: 5)),
        _ignoreError(() => api.getHistoryOrders(page: 1, pageSize: 5)),
        _ignoreError(() => api.getPositions(page: 1, pageSize: 5)),
        _ignoreError(() => api.getFills(page: 1, pageSize: 5)),
        _ignoreError(() => api.getLedger(page: 1, pageSize: 5)),
      ]);
      _lastSuccessAt = DateTime.now();
    } finally {
      _running = false;
    }
  }

  Future<void> _ignoreError(Future<dynamic> Function() loader) async {
    try {
      await loader();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[StartupDataSyncService] ignore sync error: $e');
      }
    }
  }
}
