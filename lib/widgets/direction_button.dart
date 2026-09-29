import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../models/motor_state.dart';
import 'common.dart';

/// Control de sentido: MANTENER PULSADO para confirmar (evita toques
/// accidentales). Si el motor gira, el controlador aplica STOP → espera →
/// inversión → reanudación, y aquí se muestra el progreso.
class DirectionControl extends StatelessWidget {
  const DirectionControl({
    super.key,
    required this.direction,
    required this.phase,
    required this.progress,
    required this.enabled,
    required this.onReverse,
    required this.onSyncLabel,
  });

  final MotorDirection direction;
  final ReversePhase phase;
  final double progress;
  final bool enabled;
  final VoidCallback onReverse;
  final VoidCallback onSyncLabel;

  bool get _cw => direction == MotorDirection.clockwise;

  String get _phaseText => switch (phase) {
        ReversePhase.stopping => 'Deteniendo motor…',
        ReversePhase.waiting => 'Esperando parada segura…',
        ReversePhase.switching => 'Invirtiendo sentido…',
        ReversePhase.resuming => 'Reanudando giro…',
        ReversePhase.idle => 'Mantén pulsado para invertir',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = phase != ReversePhase.idle;

    return AppCard(
      highlight: busy ? AppColors.warning : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            'Sentido de giro',
            trailing: Tooltip(
              message: 'Corregir etiqueta (no envía comandos)',
              child: InkResponse(
                onTap: onSyncLabel,
                radius: 20,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.tune_rounded, size: 18, color: AppColors.textTertiary),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 450),
                transitionBuilder: (child, anim) => RotationTransition(
                  turns: Tween(begin: 0.6, end: 1.0).animate(
                    CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
                  ),
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: Icon(
                  _cw ? Icons.rotate_right_rounded : Icons.rotate_left_rounded,
                  key: ValueKey(direction),
                  size: 34,
                  color: enabled ? AppColors.textPrimary : AppColors.textTertiary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        '${_cw ? '↻' : '↺'}  ${direction.label}',
                        key: ValueKey(direction),
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(height: 2),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        _phaseText,
                        key: ValueKey(phase),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: busy ? AppColors.warning : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _HoldButton(
            enabled: enabled && !busy,
            busyProgress: busy ? progress : null,
            label: 'Invertir sentido',
            onConfirmed: onReverse,
          ),
        ],
      ),
    );
  }
}

/// Botón de mantener-para-confirmar con relleno progresivo.
class _HoldButton extends StatefulWidget {
  const _HoldButton({
    required this.enabled,
    required this.label,
    required this.onConfirmed,
    this.busyProgress,
  });

  final bool enabled;
  final String label;
  final VoidCallback onConfirmed;
  final double? busyProgress;

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        HapticFeedback.heavyImpact();
        widget.onConfirmed();
        _hold.value = 0;
      }
    });

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  void _down() {
    if (!widget.enabled) return;
    HapticFeedback.selectionClick();
    _hold.forward(from: 0);
  }

  void _up() {
    if (_hold.isAnimating) _hold.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = widget.busyProgress != null;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: '${widget.label}. Mantener pulsado.',
      onLongPress: widget.enabled ? widget.onConfirmed : null,
      // Listener (eventos crudos) en vez de GestureDetector: la pulsación
      // larga no compite en la arena de gestos con el scroll ni con la tarjeta.
      child: Listener(
        onPointerDown: (_) => _down(),
        onPointerUp: (_) => _up(),
        onPointerCancel: (_) => _up(),
        child: AnimatedBuilder(
          animation: _hold,
          builder: (context, _) {
            final fill = busy ? widget.busyProgress!.clamp(0.0, 1.0) : _hold.value;
            final color = busy ? AppColors.warning : AppColors.ember;
            return ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusM),
              child: Container(
                height: 52,
                color: AppColors.surfaceHigh,
                child: Stack(
                  children: [
                    FractionallySizedBox(
                      widthFactor: fill,
                      child: Container(color: color.withValues(alpha: 0.22)),
                    ),
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.swap_horiz_rounded,
                            size: 20,
                            color: widget.enabled || busy ? color : AppColors.textTertiary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            busy ? 'Cambiando…' : widget.label.toUpperCase(),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: widget.enabled || busy ? AppColors.textPrimary : AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
