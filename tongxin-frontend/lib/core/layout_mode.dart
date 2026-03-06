import 'package:flutter/widgets.dart';

/// 统一布局模式判断：
/// - 大屏（宽度 >= 1100）走 PC 布局
/// - 手机横屏（短边 < 600）也走 PC 风格布局
class LayoutMode {
  LayoutMode._();

  static const double desktopBreakpoint = 1100;
  static const double handsetShortestSideMax = 600;

  static bool isHandsetLandscape(BuildContext context) {
    final mq = MediaQuery.of(context);
    return mq.orientation == Orientation.landscape &&
        mq.size.shortestSide < handsetShortestSideMax;
  }

  static bool useDesktopLikeLayout(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= desktopBreakpoint) return true;
    return isHandsetLandscape(context);
  }
}
