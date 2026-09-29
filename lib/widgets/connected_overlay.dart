import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';

/// Confirmación visual "ASADOR CONECTADO" (≈1,4 s) antes del panel.
Future<void> showConnectedOverlay(BuildContext context, {required String deviceName}) {
  HapticFeedback.mediumImpact();
  return Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, a, _) => FadeTransition(
      opacity: a,
      child: _ConnectedOverlay(deviceName: deviceName),
    ),
  ));
}

class _ConnectedOverlay extends StatefulWidget {
  const _ConnectedOverlay({required this.deviceName});

  final String deviceName;

  @override
  State<_ConnectedOverlay> createState() => _ConnectedOverlayState();
}

class _ConnectedOverlayState extends State<_ConnectedOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.background.withValues(alpha: 0.94),
      body: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final ring = Curves.easeOutCubic.transform((_c.value / 0.6).clamp(0.0, 1.0));
            final check = Curves.easeOut.transform(((_c.value - 0.35) / 0.5).clamp(0.0, 1.0));
            final text = Curves.easeOut.transform(((_c.value - 0.5) / 0.5).clamp(0.0, 1.0));
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 112,
                  child: CustomPaint(painter: _CheckPainter(ring: ring, check: check)),
                ),
                const SizedBox(height: 28),
                Opacity(
                  opacity: text,
                  child: Transform.translate(
                    offset: Offset(0, 12 * (1 - text)),
                    child: Column(
                      children: [
                        Text(
                          'ASADOR CONECTADO',
                          style: theme.textTheme.titleLarge?.copyWith(letterSpacing: 3),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.deviceName,
                          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter({required this.ring, required this.check});

  final double ring;
  final double check;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 3;
    canvas.drawCircle(c, r * ring, Paint()..color = AppColors.successSoft);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      math.pi * 2 * ring,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = AppColors.success,
    );
    if (check <= 0) return;
    final p1 = c + Offset(-r * 0.36, r * 0.02);
    final p2 = c + Offset(-r * 0.08, r * 0.30);
    final p3 = c + Offset(r * 0.40, -r * 0.26);
    final path = Path()..moveTo(p1.dx, p1.dy);
    final firstLen = (p2 - p1).distance;
    final secondLen = (p3 - p2).distance;
    final drawn = (firstLen + secondLen) * check;
    if (drawn <= firstLen) {
      final q = Offset.lerp(p1, p2, drawn / firstLen)!;
      path.lineTo(q.dx, q.dy);
    } else {
      path.lineTo(p2.dx, p2.dy);
      final q = Offset.lerp(p2, p3, (drawn - firstLen) / secondLen)!;
      path.lineTo(q.dx, q.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = AppColors.success,
    );
  }

  @override
  bool shouldRepaint(covariant _CheckPainter old) => old.ring != ring || old.check != check;
}
