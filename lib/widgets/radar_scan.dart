import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Ondas concéntricas durante la búsqueda de dispositivos.
class RadarScan extends StatefulWidget {
  const RadarScan({super.key, required this.active, this.size = 120});

  final bool active;
  final double size;

  @override
  State<RadarScan> createState() => _RadarScanState();
}

class _RadarScanState extends State<RadarScan> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant RadarScan old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat();
    if (!widget.active && _c.isAnimating) _c.animateTo(1, duration: const Duration(milliseconds: 300));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _RadarPainter(t: _c.value, active: widget.active),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: widget.size * 0.36,
              height: widget.size * 0.36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.active ? AppColors.emberSoft : AppColors.surfaceHigh,
                border: Border.all(
                  color: widget.active ? AppColors.ember.withValues(alpha: 0.6) : AppColors.stroke,
                ),
              ),
              child: Icon(
                Icons.bluetooth_searching_rounded,
                size: widget.size * 0.17,
                color: widget.active ? AppColors.ember : AppColors.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.t, required this.active});

  final double t;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    if (!active) return;
    final c = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1.0;
      final radius = maxR * (0.2 + 0.8 * p);
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = AppColors.ember.withValues(alpha: (1 - p) * 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => old.t != t || old.active != active;
}
