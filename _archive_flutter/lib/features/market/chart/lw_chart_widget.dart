// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../trading/polygon_repository.dart';

// Web-only imports — only referenced inside kIsWeb guards.
// The conditional import pattern keeps mobile builds from breaking.
import 'lw_chart_stub.dart'
    if (dart.library.html) 'lw_chart_web.dart' as lw_web;

/// TradingView lightweight-charts v4 wrapper widget.
///
/// On web: renders a full candlestick + volume chart via JS interop.
/// On other platforms: shows a plain fallback container.
class LwChartWidget extends StatefulWidget {
  const LwChartWidget({
    super.key,
    required this.candles,
    this.height = 300.0,
    this.darkMode = true,
    this.onLoadMoreHistory,
    this.latestCandle,
  });

  final List<ChartCandle> candles;
  final double height;
  final bool darkMode;
  final Future<void> Function(int earliestMs)? onLoadMoreHistory;

  /// When this value changes the chart calls `lwUpdate` for the last candle
  /// (real-time price update without a full redraw).
  final ChartCandle? latestCandle;

  @override
  State<LwChartWidget> createState() => _LwChartWidgetState();
}

class _LwChartWidgetState extends State<LwChartWidget> {
  // Unique id scoped to this widget instance.
  late final String _chartId;
  late final String _viewType;

  // Track what was last pushed to JS so we only re-send when data changes.
  List<ChartCandle>? _lastCandles;
  ChartCandle? _lastLatestCandle;

  // Whether the HtmlElementView has been created (web only).
  bool _viewCreated = false;

  @override
  void initState() {
    super.initState();
    _chartId = 'lw-chart-${UniqueKey().toString().replaceAll('[#', '').replaceAll(']', '')}';
    _viewType = _chartId;

    if (kIsWeb) {
      lw_web.registerViewFactory(_viewType, _chartId);
      // Push data after the first frame when the DOM element exists.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        lw_web.create(_chartId, widget.darkMode);
        _viewCreated = true;
        _pushData();
      });
    }
  }

  @override
  void didUpdateWidget(LwChartWidget old) {
    super.didUpdateWidget(old);
    if (!kIsWeb || !_viewCreated) return;

    // Full data reload when the candles list changes.
    if (!identical(widget.candles, old.candles) ||
        widget.candles.length != old.candles.length) {
      _pushData();
      return;
    }

    // Incremental real-time update when only latestCandle changes.
    if (widget.latestCandle != null &&
        widget.latestCandle != _lastLatestCandle) {
      _lastLatestCandle = widget.latestCandle;
      lw_web.update(_chartId, _candleToJson(widget.latestCandle!));
    }
  }

  @override
  void dispose() {
    if (kIsWeb) {
      lw_web.destroy(_chartId);
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data helpers
  // ---------------------------------------------------------------------------

  void _pushData() {
    final candles = widget.candles;
    if (candles.isEmpty) return;
    _lastCandles = candles;
    _lastLatestCandle = widget.latestCandle;

    final candleList = candles
        .map((c) => {
              'time': c.time.toInt(),
              'open': c.open,
              'high': c.high,
              'low': c.low,
              'close': c.close,
            })
        .toList();

    final volList = candles
        .where((c) => c.volume != null)
        .map((c) => {
              'time': c.time.toInt(),
              'value': c.volume,
              'color': c.close >= c.open ? '#26A17B40' : '#E8414240',
            })
        .toList();

    lw_web.setData(
      _chartId,
      jsonEncode(candleList),
      volList.isNotEmpty ? jsonEncode(volList) : null,
    );
  }

  static String _candleToJson(ChartCandle c) => jsonEncode({
        'time': c.time.toInt(),
        'open': c.open,
        'high': c.high,
        'low': c.low,
        'close': c.close,
        if (c.volume != null) 'volume': c.volume,
      });

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return Container(
        height: widget.height,
        color: Colors.black,
        child: const Center(
          child: Text(
            'Chart: web only',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    if (widget.candles.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    // 支持 height == double.infinity（在 Expanded 内使用时）
    if (widget.height == double.infinity) {
      return SizedBox.expand(child: lw_web.buildHtmlView(_viewType));
    }
    return SizedBox(
      height: widget.height,
      child: lw_web.buildHtmlView(_viewType),
    );
  }
}
