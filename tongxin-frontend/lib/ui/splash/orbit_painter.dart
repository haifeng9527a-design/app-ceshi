import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tv_theme.dart';

/// 粒子：固定 seed 生成位置，每帧只改 alpha/轻微 drift
class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.baseAlpha,
    required this.driftPhase,
    required this.colorIndex,
    required this.radius,
  });

  final double x;
  final double y;
  final double baseAlpha;
  final double driftPhase;
  final int colorIndex;
  final double radius;
}

/// Orbit 数据轨道启动页 CustomPainter：粒子 + 轨道 + 节点 + 核心脉冲
class OrbitPainter extends CustomPainter {
  OrbitPainter({
    required this.t,
    required this.breath,
    required this.pulse,
    required this.orbitSpeeds,
    List<Color>? nodeColors,
  }) : nodeColors = nodeColors ?? _defaultNodeColors;

  static List<_Particle>? _cachedParticles;
  static List<_Particle> get particles =>
      _cachedParticles ??= _buildParticles(80);

  final double t;
  /// 背景呼吸 0..1（sin 波）
  final double breath;
  /// 核心脉冲 0..1（sin 波）
  final double pulse;
  /// 4 条轨道角速度（弧度/秒或比例）
  final List<double> orbitSpeeds;
  final List<Color> nodeColors;

  static const _defaultNodeColors = [
    TvTheme.splashAccentCyan,
    TvTheme.splashAccentPurple,
    TvTheme.splashAccentGold,
    TvTheme.splashAccentTeal,
  ];

  static List<_Particle> _buildParticles(int n) {
    final rand = math.Random(0x4F52424954); // "ORBIT" in ASCII hex
    final list = <_Particle>[];
    final w = 800.0;
    final h = 600.0;
    for (int i = 0; i < n; i++) {
      list.add(_Particle(
        x: (rand.nextDouble() - 0.5) * w * 1.2,
        y: (rand.nextDouble() - 0.5) * h * 1.2,
        baseAlpha: 0.08 + rand.nextDouble() * 0.22,
        driftPhase: rand.nextDouble() * 2 * math.pi,
        colorIndex: rand.nextInt(4),
        radius: 1.0 + rand.nextDouble() * 1.2,
      ));
    }
    return list;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final scale = math.min(size.width, size.height) / 600;

    canvas.save();
    canvas.translate(cx, cy);

    _paintParticles(canvas, size, scale);
    _paintOrbits(canvas, scale);
    _paintCore(canvas, scale);

    canvas.restore();
  }

  void _paintParticles(Canvas canvas, Size size, double scale) {
    final drift = t * 2 * math.pi * 0.15;
    final particleList = particles;
    final palette = [
      TvTheme.splashAccentCyan,
      TvTheme.splashAccentPurple,
      TvTheme.splashAccentGold,
      TvTheme.splashAccentTeal,
    ];
    for (final p in particleList) {
      final alphaFlicker = 0.7 + 0.3 * math.sin(drift + p.driftPhase);
      final alpha = (p.baseAlpha * alphaFlicker).clamp(0.0, 1.0);
      final dx = 4 * math.sin(drift * 0.7 + p.driftPhase);
      final dy = 3 * math.cos(drift * 0.5 + p.driftPhase * 1.3);
      final x = p.x * scale + dx;
      final y = p.y * scale + dy;
      final paint = Paint()
        ..color = palette[p.colorIndex % palette.length].withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), p.radius * scale, paint);
    }
  }

  void _paintOrbits(Canvas canvas, double scale) {
    const steps = 120;
    const lineWidth = 2.0;
    const nodeCount = 5;
    final radii = [0.18, 0.24, 0.32, 0.42].map((r) => r * 280 * scale).toList();

    for (int track = 0; track < orbitSpeeds.length && track < radii.length; track++) {
      final r = radii[track];
      final angleOffset = t * orbitSpeeds[track] * 2 * math.pi;
      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineWidth
        ..color = nodeColors[track % nodeColors.length].withValues(alpha: 0.18);

      final path = Path();
      for (int i = 0; i <= steps; i++) {
        final angle = angleOffset + (i / steps) * 2 * math.pi * 0.85;
        final x = r * math.cos(angle);
        final y = r * math.sin(angle);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, strokePaint);

      for (int k = 0; k < nodeCount; k++) {
        final frac = 0.12 + 0.76 * (k / (nodeCount - 1));
        final a = angleOffset + frac * 2 * math.pi * 0.85;
        final nx = r * math.cos(a);
        final ny = r * math.sin(a);
        final nodeColor = nodeColors[track % nodeColors.length];
        final nodePaint = Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.2, -0.2),
            radius: 1.2,
            colors: [
              nodeColor.withValues(alpha: 0.9),
              nodeColor.withValues(alpha: 0.5),
            ],
          ).createShader(Rect.fromCircle(center: Offset(nx, ny), radius: 4 * scale));
        canvas.drawCircle(Offset(nx, ny), (3.5 * scale).clamp(2.0, 4.0), nodePaint);
      }
    }
  }

  void _paintCore(Canvas canvas, double scale) {
    final glowRadius = (28 + 14 * pulse) * scale;
    final coreRadius = (10 + 2 * math.sin(t * 2 * math.pi)) * scale;
    final glowAlpha = 0.15 + 0.12 * pulse;

    final glowPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [
          TvTheme.splashAccentCyan.withValues(alpha: glowAlpha),
          TvTheme.splashBg2.withValues(alpha: 0.6),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: glowRadius));
    canvas.drawCircle(Offset.zero, glowRadius, glowPaint);

    final corePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.25, -0.25),
        radius: 1.0,
        colors: [
          TvTheme.splashTextPrimary.withValues(alpha: 0.95),
          TvTheme.splashAccentCyan.withValues(alpha: 0.7),
          TvTheme.splashBg2.withValues(alpha: 0.9),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: coreRadius));
    canvas.drawCircle(Offset.zero, coreRadius, corePaint);

    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = TvTheme.splashAccentCyan.withValues(alpha: 0.4);
    canvas.drawCircle(Offset.zero, coreRadius, edgePaint);
  }

  @override
  bool shouldRepaint(covariant OrbitPainter old) {
    return old.t != t || old.breath != breath || old.pulse != pulse;
  }
}
