import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../models/bluetooth_models.dart';
import 'common.dart';

class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.device,
    required this.onConnect,
    this.connecting = false,
    this.enabled = true,
  });

  final BtDevice device;
  final VoidCallback onConnect;
  final bool connecting;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final featured = device.looksLikeAsador;
    final status = device.kind == TransportKind.classic
        ? (device.bonded ? 'Emparejado' : 'Disponible')
        : (device.bonded ? 'Servicio asador' : 'Disponible');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: featured ? AppColors.surfaceHigh : AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        border: Border.all(
          color: connecting
              ? AppColors.ember
              : (featured ? AppColors.ember.withValues(alpha: 0.35) : AppColors.strokeSoft),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: featured ? AppColors.emberSoft : AppColors.surfaceHigher,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              featured ? Icons.outdoor_grill_rounded : Icons.bluetooth_rounded,
              color: featured ? AppColors.ember : AppColors.textSecondary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    PulsingDot(
                      color: device.bonded ? AppColors.success : AppColors.info,
                      size: 6,
                    ),
                    Flexible(
                      child: Text(
                        '$status · ${device.id}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (device.rssi != null) ...[
            SignalBars(bars: device.signalBars),
            const SizedBox(width: 10),
          ],
          SizedBox(
            height: 38,
            child: FilledButton(
              onPressed: enabled && !connecting ? onConnect : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.ember,
                disabledBackgroundColor: AppColors.surfaceHigher,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: connecting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ember),
                    )
                  : const Text('Conectar'),
            ),
          ),
        ],
      ),
    );
  }
}
