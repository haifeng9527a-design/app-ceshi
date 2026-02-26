import 'package:flutter/foundation.dart';

/// K 线视口控制器：可见区间 [visibleStartIndex, visibleStartIndex + visibleCount]
/// 支持左右滑动(pan)、双指缩放(zoom)，默认 80 根，最小 30，最大 400（与常见行情软件一致）
class ChartViewportController extends ChangeNotifier {
  ChartViewportController({
    double initialVisibleCount = 80,
    this.minVisibleCount = 30,
    this.maxVisibleCount = 400,
  }) : _visibleCount = initialVisibleCount.clamp(30.0, 400.0);

  double _visibleStartIndex = 0;
  double _visibleCount = 80;
  final double minVisibleCount;
  final double maxVisibleCount;

  double get visibleStartIndex => _visibleStartIndex;
  double get visibleCount => _visibleCount;

  /// 总根数变化时（例如 prepend 了更多历史），调用此方法保持画面不跳
  void addStartOffset(int n) {
    if (n <= 0) return;
    _visibleStartIndex += n;
    notifyListeners();
  }

  /// 初始化视口：使最右侧对齐最后一根（显示最近 visibleCount 根）
  void initFromCandlesLength(int length) {
    if (length <= 0) return;
    _visibleCount = _visibleCount.clamp(minVisibleCount, maxVisibleCount).clamp(1.0, length.toDouble());
    _visibleStartIndex = (length - _visibleCount).clamp(0.0, double.infinity);
    notifyListeners();
  }

  /// 横向拖动：dx 为正表示向右拖（看更晚），visibleStartIndex 增加
  /// 与常见行情软件一致：约 1 根 K 线宽度的滑动对应移动 1 根
  static const double _panFactor = 1.0;
  void onPan(double dx, double contentWidth, int totalCandles) {
    if (totalCandles <= 0 || contentWidth <= 0) return;
    final candleWidth = contentWidth / _visibleCount;
    if (candleWidth <= 0) return;
    final deltaIndex = (dx / candleWidth) * _panFactor;
    double newStart = _visibleStartIndex + deltaIndex;
    final maxStart = (totalCandles - _visibleCount).clamp(0.0, double.infinity);
    newStart = newStart.clamp(0.0, maxStart);
    if (newStart != _visibleStartIndex) {
      _visibleStartIndex = newStart;
      notifyListeners();
    }
  }

  /// 双指缩放：scale > 1 表示放大（可见根数变少），scale < 1 表示缩小
  /// 变化速度减半（阻尼），并 clamp 在 minVisibleCount~maxVisibleCount（默认 30~400）
  /// [scaleStartCount] 若提供则相对手势开始时的根数计算，否则相对当前 _visibleCount
  static const double _zoomDamp = 0.5;
  void onZoom(double scale, int totalCandles, {double? scaleStartCount}) {
    if (totalCandles <= 0) return;
    final base = scaleStartCount ?? _visibleCount;
    final rawCount = base / scale;
    double newCount = base + (rawCount - base) * _zoomDamp;
    newCount = newCount.clamp(minVisibleCount, maxVisibleCount).clamp(1.0, totalCandles.toDouble());
    double newStart = _visibleStartIndex;
    final maxStart = (totalCandles - newCount).clamp(0.0, double.infinity);
    newStart = newStart.clamp(0.0, maxStart);
    if (newCount != _visibleCount || newStart != _visibleStartIndex) {
      _visibleCount = newCount;
      _visibleStartIndex = newStart;
      notifyListeners();
    }
  }

  /// 当前可见区间 [start, end) 整数索引，用于 sublist
  (int start, int end) visibleRange(int totalCandles) {
    final start = _visibleStartIndex.floor().clamp(0, totalCandles);
    final end = (_visibleStartIndex + _visibleCount).ceil().clamp(0, totalCandles);
    return (start, end);
  }

  /// 是否处于「最新」视口（最右侧对齐最后一根 K 线）
  bool isAtRealtime(int totalCandles) {
    if (totalCandles <= 0) return true;
    final maxStart = (totalCandles - _visibleCount).clamp(0.0, double.infinity);
    return _visibleStartIndex >= maxStart - 0.5;
  }

  /// 回到最新视口：startIndex = length - visibleCount
  void goToRealtime(int totalCandles) {
    if (totalCandles <= 0) return;
    final newStart = (totalCandles - _visibleCount).clamp(0.0, double.infinity);
    if (newStart != _visibleStartIndex) {
      _visibleStartIndex = newStart;
      notifyListeners();
    }
  }
}
