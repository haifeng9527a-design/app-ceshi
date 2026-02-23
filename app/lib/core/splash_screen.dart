import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/notification_settings_guide.dart';
import '../features/home/home_page.dart';

// ---------------------------------------------------------------------------
// APP 名称与副标题
// ---------------------------------------------------------------------------
const String kSplashAppName = 'tufei';
const String kSplashTagline = 'Professional · Connected · Forward';

/// 开机动画：中央地球 + 弧线上小球/金融符号 + 下方 APP 名
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const Duration _displayDuration = Duration(milliseconds: 3200);
  static const Duration _fadeOutDuration = Duration(milliseconds: 400);

  late final AnimationController _entrance;
  late final AnimationController _rotate;
  late final AnimationController _particles;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _rotate = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    _particles = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();

    _entrance.forward();
    Future.delayed(_displayDuration, _onSplashDone);
  }

  Future<void> _onSplashDone() async {
    if (!mounted) return;
    if (!kIsWeb) {
      await NotificationSettingsGuide.showIfNeeded(context);
    }
    if (!mounted) return;
    _goToHome();
  }

  void _goToHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HomePage(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: _fadeOutDuration,
      ),
    );
  }

  @override
  void dispose() {
    _entrance.dispose();
    _rotate.dispose();
    _particles.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            _buildBackground(),
            AnimatedBuilder(
              animation: Listenable.merge([_entrance, _rotate, _particles, _pulse]),
              builder: (context, _) {
                return CustomPaint(
                  painter: _SplashPainter(
                    entrance: _entrance.value,
                    rotate: _rotate.value * 2 * math.pi,
                    particlesPhase: _particles.value,
                    pulse: _pulse.value,
                  ),
                  size: Size.infinite,
                );
              },
            ),
            // 必须随 _entrance 重建，否则透明度不会更新，名字一直不显示
            AnimatedBuilder(
              animation: _entrance,
              builder: (context, _) => _buildTextOverlay(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.4,
          colors: [
            Color(0xFF0C1444),
            Color(0xFF060818),
            Color(0xFF000000),
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
    );
  }

  /// 下方：APP 名称「tufei」仅用字体与光晕呈现，无黑底
  Widget _buildTextOverlay() {
    final tagT = ((_entrance.value - 0.35) / 0.4).clamp(0.0, 1.0);
    return Positioned(
      left: 0,
      right: 0,
      bottom: MediaQuery.of(context).padding.bottom + 52,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            kSplashAppName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w300,
              letterSpacing: 14,
              color: Color(0xFFE8F4F8),
              shadows: [
                Shadow(
                  color: Color(0x504FC3F7),
                  offset: Offset(0, 0),
                  blurRadius: 24,
                ),
                Shadow(
                  color: Color(0x3081D4FA),
                  offset: Offset(0, 0),
                  blurRadius: 40,
                ),
                Shadow(
                  color: Color(0x20000000),
                  offset: Offset(0, 2),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Opacity(
            opacity: Curves.easeOutCubic.transform(tagT),
            child: Text(
              kSplashTagline,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                letterSpacing: 2.5,
                color: const Color(0xFF94A3B8).withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SplashPainter extends CustomPainter {
  _SplashPainter({
    required this.entrance,
    required this.rotate,
    required this.particlesPhase,
    required this.pulse,
  });

  final double entrance;
  final double rotate;
  final double particlesPhase;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final t = Curves.easeOutCubic.transform(entrance);
    if (t <= 0) return;

    canvas.save();
    canvas.translate(cx, cy);

    // 1) 外层旋转弧线 + 弧线上的小球与金融符号
    final arcStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    const sweep = 2.2;
    final arcColors = [
      [0xFF0EA5E9, 0xFF7DD3FC],
      [0xFF06B6D4, 0xFF22D3EE],
      [0xFF8B5CF6, 0xFFA78BFA],
      [0xFFF59E0B, 0xFFFBBF24],
    ];
    final financeSymbols = ['\$', '↑', '•', '¥'];
    for (int i = 0; i < 4; i++) {
      final r = 98.0 + i * 38.0;
      final show = ((t - 0.12 - i * 0.06) / 0.2).clamp(0.0, 1.0);
      if (show <= 0) continue;
      final angle = rotate + i * 0.35;
      final colors = arcColors[i % arcColors.length];
      arcStroke.color = Color.lerp(
        Color(colors[0]),
        Color(colors[1]),
        0.4 + 0.3 * math.sin(angle),
      )!.withValues(alpha: 0.32 * show);
      _drawArc(canvas, r, angle, arcStroke);

      // 弧线上：5 个小球 + 1 个金融符号
      final orbShow = ((t - 0.2 - i * 0.05) / 0.25).clamp(0.0, 1.0);
      if (orbShow > 0) {
        for (int k = 0; k < 5; k++) {
          final frac = 0.15 + 0.7 * (k / 4);
          final a = angle + frac * sweep;
          final ox = r * math.cos(a);
          final oy = r * math.sin(a);
          final orbR = 3.2 - 0.4 * (k % 2);
          final orbPaint = Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.3, -0.3),
              radius: 1.2,
              colors: [
                Color(colors[1]).withValues(alpha: 0.95 * orbShow),
                Color(colors[0]).withValues(alpha: 0.75 * orbShow),
              ],
            ).createShader(Rect.fromCircle(center: Offset(ox, oy), radius: orbR));
          canvas.drawCircle(Offset(ox, oy), orbR, orbPaint);
        }
        // 该弧中段画一个金融符号
        final symFrac = 0.5;
        final sa = angle + symFrac * sweep;
        final sx = r * math.cos(sa);
        final sy = r * math.sin(sa);
        _drawSymbol(canvas, financeSymbols[i % financeSymbols.length], sx, sy, Color(colors[1]).withValues(alpha: 0.95 * orbShow));
      }
    }

    // 2b) 地球外围单环（轨道感）
    final ringR = 52.0;
    final ringShow = (t / 0.35).clamp(0.0, 1.0);
    if (ringShow > 0) {
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      ringPaint.color = const Color(0xFF4FC3F7).withValues(alpha: 0.18 * ringShow);
      canvas.drawCircle(Offset.zero, ringR, ringPaint);
    }

    // 3) 中央地球（蓝+绿球体，高光随 rotate 转动，一眼能看出是地球）
    final earthR = 32.0 * (0.7 + 0.3 * t);
    if (earthR > 2) {
      final glowR = earthR + 20;
      final glowPaint = Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [
            const Color(0xFF26A69A).withValues(alpha: 0.2 * t),
            const Color(0xFF4FC3F7).withValues(alpha: 0.12 * t),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: glowR));
      canvas.drawCircle(Offset.zero, glowR, glowPaint);

      final lightX = math.cos(rotate);
      final lightY = math.sin(rotate);
      // 高光偏蓝，背光面偏绿，中间带明显绿色带（陆地感）
      final earthPaint = Paint()
        ..shader = RadialGradient(
          center: Alignment(lightX * 0.35, lightY * 0.35),
          radius: 0.95,
          colors: [
            const Color(0xFF90CAF9),
            const Color(0xFF4FC3F7),
            const Color(0xFF2E7D32),
            const Color(0xFF26A69A),
            const Color(0xFF00695C),
          ],
          stops: const [0.0, 0.2, 0.45, 0.7, 1.0],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: earthR));
      canvas.drawCircle(Offset.zero, earthR, earthPaint);

      final edgePaint = Paint()
        ..color = const Color(0xFF80CBC4).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawCircle(Offset.zero, earthR, edgePaint);
    }

    // 5) 粒子（多色：青、蓝、紫、琥珀）
    final particleShow = (t - 0.22) / 0.3;
    if (particleShow > 0) {
      const n = 56;
      final palette = [
        const Color(0xFF7DD3FC),
        const Color(0xFF22D3EE),
        const Color(0xFFA78BFA),
        const Color(0xFFFBBF24),
      ];
      for (int i = 0; i < n; i++) {
        final seed = (i * 1.618 + particlesPhase).remainder(1.0);
        final x = (math.sin(i * 0.7) * 140 + math.cos(i * 0.3) * 80) * (0.8 + 0.4 * seed);
        final y = (math.cos(i * 0.5) * 180 + seed * 200 - particlesPhase * 220) % 400 - 200;
        final alpha = (0.12 + 0.28 * math.sin(seed * 2 * math.pi + particlesPhase * 2 * math.pi)) * particleShow;
        final r = 1.0 + 0.9 * (i % 3);
        final particlePaint = Paint()
          ..color = palette[i % palette.length].withValues(alpha: alpha);
        canvas.drawCircle(Offset(x, y), r, particlePaint);
      }
    }

    canvas.restore();
  }

  void _drawArc(Canvas canvas, double r, double startAngle, Paint paint) {
    const sweep = 2.2;
    final path = Path();
    path.arcTo(Rect.fromCircle(center: Offset.zero, radius: r), startAngle, sweep, false);
    canvas.drawPath(path, paint);
  }

  void _drawDiamond(Canvas canvas, double halfSize, Paint paint) {
    final path = Path()
      ..moveTo(0, -halfSize)
      ..lineTo(halfSize, 0)
      ..lineTo(0, halfSize)
      ..lineTo(-halfSize, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawSymbol(Canvas canvas, String symbol, double x, double y, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: symbol, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _SplashPainter old) {
    return old.entrance != entrance ||
        old.rotate != rotate ||
        old.particlesPhase != particlesPhase ||
        old.pulse != pulse;
  }
}
