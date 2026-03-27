import 'dart:math';

import 'package:flutter/material.dart';

class FinanceBackground extends StatefulWidget {
  const FinanceBackground({super.key, required this.child});

  final Widget child;

  @override
  State<FinanceBackground> createState() => _FinanceBackgroundState();
}

class _FinanceBackgroundState extends State<FinanceBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    final random = Random(42);
    _particles = List.generate(36, (index) {
      return _Particle(
        x: random.nextDouble(),
        y: random.nextDouble(),
        size: 2.0 + random.nextDouble() * 6,
        speed: 0.02 + random.nextDouble() * 0.06,
        isSymbol: random.nextDouble() > 0.7,
        phase: random.nextDouble() * pi * 2,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return RepaintBoundary(
                  child: CustomPaint(
                    painter: _FinanceBackgroundPainter(
                      t: _controller.value,
                      particles: _particles,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _FinanceBackgroundPainter extends CustomPainter {
  _FinanceBackgroundPainter({
    required this.t,
    required this.particles,
  });

  final double t;
  final List<_Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()..color = const Color(0xFFD4AF37).withOpacity(0.18);
    final symbolStyle = const TextStyle(
      color: Color(0xFFD4AF37),
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    for (final p in particles) {
      final dx = (p.x + 0.02 * sin(t * 2 * pi + p.phase)) * size.width;
      final dy = ((p.y + t * p.speed) % 1.0) * size.height;
      if (p.isSymbol) {
        final textSpan = TextSpan(text: r'$', style: symbolStyle);
        final painter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, Offset(dx, dy));
      } else {
        canvas.drawCircle(Offset(dx, dy), p.size, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FinanceBackgroundPainter oldDelegate) {
    return oldDelegate.t != t;
  }
}

class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.isSymbol,
    required this.phase,
  });

  final double x;
  final double y;
  final double size;
  final double speed;
  final bool isSymbol;
  final double phase;
}
