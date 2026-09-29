import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/theme/app_colors.dart';

/// Visualización del espetón girando.
///
/// La velocidad angular converge suavemente hacia el objetivo (inercia), de
/// modo que arrancar, detener o invertir se ve físico y no abrupto.
class RotisserieAnimation extends StatefulWidget {
  const RotisserieAnimation({
    super.key,
    required this.running,
    required this.speed01,
    required this.clockwise,
    this.enabled = true,
  });

  final bool running;

  /// 0..1 — velocidad relativa.
  final double speed01;
  final bool clockwise;
  final bool enabled;

  @override
  State<RotisserieAnimation> createState() => _RotisserieAnimationState();
}

class _RotisserieAnimationState extends State<RotisserieAnimation>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _angle = 0;
  double _velocity = 0; // rad/s
  final _repaint = ValueNotifier<double>(0);

  double get _target {
    if (!widget.running || !widget.enabled) return 0;
    final v = 0.8 + widget.speed01 * 3.2; // rad/s
    return widget.clockwise ? v : -v;
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = now;
    _velocity += (_target - _velocity) * (1 - math.exp(-dt * 2.4));
    if (_velocity.abs() < 0.002 && _target == 0) _velocity = 0;
    _angle += _velocity * dt;
    _repaint.value = _angle;
    // Ahorro de batería: detener el ticker cuando el espetón está quieto.
    if (_velocity == 0 && _target == 0) {
      _ticker.stop();
      _last = Duration.zero;
    }
  }

  @override
  void didUpdateWidget(covariant RotisserieAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_ticker.isActive && _target != 0) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _SpitPainter(
            angle: _repaint,
            active: widget.running && widget.enabled,
            enabled: widget.enabled,
          ),
        ),
      ),
    );
  }
}

class _SpitPainter extends CustomPainter {
  _SpitPainter({required this.angle, required this.active, required this.enabled})
      : super(repaint: angle);

  final ValueNotifier<double> angle;
  final bool active;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final accent = enabled ? AppColors.ember : AppColors.textTertiary;

    // Halo cálido cuando gira.
    if (active) {
      canvas.drawCircle(
        c,
        r * 0.92,
        Paint()
          ..shader = RadialGradient(
            colors: [AppColors.ember.withValues(alpha: 0.16), Colors.transparent],
          ).createShader(Rect.fromCircle(center: c, radius: r * 0.92)),
      );
    }

    // Anillo exterior con marcas.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = AppColors.stroke;
    canvas.drawCircle(c, r * 0.9, ring);

    final tick = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.6;
    for (var i = 0; i < 60; i++) {
      final a = i / 60 * math.pi * 2;
      final major = i % 5 == 0;
      final inner = r * (major ? 0.80 : 0.84);
      tick.color = major ? AppColors.textTertiary : AppColors.strokeSoft;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * inner,
        c + Offset(math.cos(a), math.sin(a)) * r * 0.87,
        tick,
      );
    }

    // Arco de progreso que gira (indicador de movimiento).
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle.value);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [accent.withValues(alpha: 0), accent],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: r * 0.74));
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: r * 0.74),
      0,
      math.pi * 1.2,
      false,
      arc,
    );

    // Espetón: sección transversal con 3 piezas (vista frontal del eje).
    final chunk = Paint()..color = active ? const Color(0xFF8C4A2F) : AppColors.surfaceHigher;
    final chunkEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = active ? AppColors.ember.withValues(alpha: 0.7) : AppColors.stroke;
    for (var i = 0; i < 3; i++) {
      final a = i / 3 * math.pi * 2;
      final p = Offset(math.cos(a), math.sin(a)) * r * 0.30;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: p, width: r * 0.34, height: r * 0.26),
        Radius.circular(r * 0.08),
      );
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(a);
      canvas.translate(-p.dx, -p.dy);
      canvas.drawRRect(rect, chunk);
      canvas.drawRRect(rect, chunkEdge);
      canvas.restore();
    }

    // Horquillas del espetón.
    final fork = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = AppColors.textSecondary;
    for (var i = 0; i < 2; i++) {
      final a = i * math.pi;
      canvas.drawLine(Offset.zero, Offset(math.cos(a), math.sin(a)) * r * 0.62, fork);
    }
    canvas.restore();

    // Eje central.
    canvas.drawCircle(c, r * 0.07, Paint()..color = AppColors.surfaceHigher);
    canvas.drawCircle(
      c,
      r * 0.07,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = accent,
    );
  }

  @override
  bool shouldRepaint(covariant _SpitPainter old) =>
      old.active != active || old.enabled != enabled;
}
