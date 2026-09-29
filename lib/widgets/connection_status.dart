import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../models/bluetooth_models.dart';
import 'common.dart';

/// Color/texto canónicos por estado — usados en toda la app.
class StatusStyle {
  const StatusStyle(this.color, this.text, {this.pulse = false});

  final Color color;
  final String text;
  final bool pulse;

  static StatusStyle adapter(AdapterStatus s) => switch (s) {
        AdapterStatus.on => const StatusStyle(AppColors.success, 'Disponible'),
        AdapterStatus.off => const StatusStyle(AppColors.danger, 'Apagado'),
        AdapterStatus.turningOn => const StatusStyle(AppColors.warning, 'Activando…', pulse: true),
        AdapterStatus.unauthorized => const StatusStyle(AppColors.warning, 'Sin permiso'),
        AdapterStatus.unsupported => const StatusStyle(AppColors.danger, 'No compatible'),
        AdapterStatus.unknown => const StatusStyle(AppColors.textTertiary, 'Comprobando…', pulse: true),
      };

  static StatusStyle link(LinkStatus s, {int attempt = 0}) => switch (s) {
        LinkStatus.connected => const StatusStyle(AppColors.success, 'Conectado', pulse: true),
        LinkStatus.connecting => const StatusStyle(AppColors.warning, 'Conectando…', pulse: true),
        LinkStatus.reconnecting =>
          StatusStyle(AppColors.warning, 'Reconectando… ($attempt)', pulse: true),
        LinkStatus.error => const StatusStyle(AppColors.danger, 'Error de conexión'),
        LinkStatus.disconnected => const StatusStyle(AppColors.textTertiary, 'No conectado'),
      };
}

/// Fila de estado "● Disponible" con etiqueta.
class StatusRow extends StatelessWidget {
  const StatusRow({super.key, required this.icon, required this.label, required this.style, this.detail});

  final IconData icon;
  final String label;
  final StatusStyle style;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: AppColors.textSecondary, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: theme.textTheme.labelSmall),
              const SizedBox(height: 4),
              Row(
                children: [
                  PulsingDot(color: style.color, pulse: style.pulse, size: 7),
                  const SizedBox(width: 4),
                  Flexible(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        style.text,
                        key: ValueKey(style.text),
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ),
                ],
              ),
              if (detail != null)
                Text(
                  detail!,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Píldora compacta de conexión para la barra superior del panel.
class ConnectionPill extends StatelessWidget {
  const ConnectionPill({super.key, required this.link, this.attempt = 0});

  final LinkStatus link;
  final int attempt;

  @override
  Widget build(BuildContext context) {
    final st = StatusStyle.link(link, attempt: attempt);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.fromLTRB(6, 4, 14, 4),
      decoration: BoxDecoration(
        color: st.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: st.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulsingDot(color: st.color, pulse: st.pulse, size: 7),
          Text(
            st.text.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: st.color),
          ),
        ],
      ),
    );
  }
}
