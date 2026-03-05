import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tv_theme.dart';
import 'orbit_painter.dart';
import '../../core/notification_settings_guide.dart';

/// 开发时设为 true 可跳过启动动画，直接进入首页
const bool debugSkipSplash = false;

/// Orbit 数据轨道启动页（TradingView/Fintech 风格）
/// 动画结束后自动 pushReplacement 到 nextBuilder 或指定路由
class TvOrbitSplash extends StatefulWidget {
  const TvOrbitSplash({
    super.key,
    this.nextBuilder,
    this.nextRouteName,
    this.duration = const Duration(milliseconds: 2600),
    this.title = 'tufei',
    this.subtitle = 'Professional · Connected · Forward',
  }) : assert(
          nextBuilder != null || nextRouteName != null,
          'Provide nextBuilder or nextRouteName',
        );

  final Widget Function()? nextBuilder;
  final String? nextRouteName;
  final Duration duration;
  final String title;
  final String subtitle;

  @override
  State<TvOrbitSplash> createState() => _TvOrbitSplashState();
}

class _TvOrbitSplashState extends State<TvOrbitSplash>
    with TickerProviderStateMixin {
  late final AnimationController _controller;

  /// 轨道角速度（比例，乘 t 得到弧度）
  static const List<double> _orbitSpeeds = [0.28, 0.35, 0.45, 0.60];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    if (kDebugMode && debugSkipSplash) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _navigateAway());
      return;
    }
    _controller.forward();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _navigateAway();
      }
    });
  }

  Future<void> _navigateAway() async {
    if (!mounted) return;
    if (!kIsWeb) {
      await NotificationSettingsGuide.showIfNeeded(context);
    }
    if (!mounted) return;
    final nextWidget = widget.nextBuilder != null ? widget.nextBuilder!() : null;
    if (nextWidget != null) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => nextWidget,
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    } else if (widget.nextRouteName != null) {
      Navigator.of(context).pushReplacementNamed(widget.nextRouteName!);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kDebugMode && debugSkipSplash) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return Stack(
            fit: StackFit.expand,
            children: [
              _buildBackground(size),
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final t = _controller.value;
                    final breath =
                        0.5 + 0.5 * math.sin(t * 2 * math.pi * 1.2);
                    final pulse =
                        0.5 + 0.5 * math.sin(t * 2 * math.pi * 0.8);
                    return CustomPaint(
                      painter: OrbitPainter(
                        t: t,
                        breath: breath,
                        pulse: pulse,
                        orbitSpeeds: _orbitSpeeds
                            .map((s) => s * 2 * math.pi)
                            .toList(),
                      ),
                      size: size,
                    );
                  },
                ),
              ),
              _buildLogoOverlay(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBackground(Size size) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final breath = 0.5 + 0.5 * math.sin(t * 2 * math.pi * 1.2);
        final centerBrightness = 0.3 + 0.2 * breath;
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.4,
              colors: [
                TvTheme.splashBg2.withValues(alpha: centerBrightness),
                TvTheme.splashBg2.withValues(alpha: 0.6),
                TvTheme.splashBg,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLogoOverlay() {
    final logoOpacity = Curves.easeOut.transform(
      ((_controller.value - 0.55) / 0.45).clamp(0.0, 1.0),
    );
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Positioned(
          left: 0,
          right: 0,
          bottom: MediaQuery.of(context).padding.bottom + 52,
          child: Opacity(
            opacity: logoOpacity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLogoText(widget.title),
                const SizedBox(height: 14),
                Opacity(
                  opacity: 0.6,
                  child: Text(
                    widget.subtitle,
                    textAlign: TextAlign.center,
                    style: TvTheme.splashSubtitleStyle,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Logo 字距拉开：T U F E I
  Widget _buildLogoText(String title) {
    return Text(
      title.toUpperCase(),
      textAlign: TextAlign.center,
      style: TvTheme.splashLogoStyle.copyWith(
        letterSpacing: 14,
        shadows: TvTheme.splashLogoShadow,
      ),
    );
  }
}
