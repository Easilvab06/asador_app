import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';

/// Parada: un solo toque, siempre visible, rojo inconfundible.
/// (Una parada nunca debe exigir confirmación.)
class StopButton extends StatefulWidget {
  const StopButton({super.key, required this.onPressed, this.enabled = true, this.emphasized = true});

  final VoidCallback onPressed;
  final bool enabled;

  /// true cuando el motor gira (o estado desconocido): máximo contraste.
  final bool emphasized;

  @override
  State<StopButton> createState() => _StopButtonState();
}

class _StopButtonState extends State<StopButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled;
    final strong = on && widget.emphasized;
    final bg = strong ? AppColors.danger : (on ? AppColors.dangerSoft : AppColors.surfaceHigh);
    final fg = strong ? Colors.white : (on ? AppColors.danger : AppColors.textTertiary);

    return Semantics(
      button: true,
      enabled: on,
      label: 'Detener motor',
      child: GestureDetector(
        onTapDown: on ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: on ? (_) => setState(() => _down = false) : null,
        onTap: on
            ? () {
                HapticFeedback.heavyImpact();
                widget.onPressed();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: const Duration(milliseconds: 110),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            height: 64,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppTheme.radiusM),
              boxShadow: strong
                  ? [BoxShadow(color: AppColors.danger.withValues(alpha: 0.28), blurRadius: 24, offset: const Offset(0, 8))]
                  : const [],
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(color: fg, borderRadius: BorderRadius.circular(3)),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'DETENER MOTOR',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
