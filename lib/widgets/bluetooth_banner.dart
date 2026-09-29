import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../models/bluetooth_models.dart';

/// Aviso contextual cuando Bluetooth no está listo, con la acción que
/// cada plataforma realmente permite.
class BluetoothBanner extends StatelessWidget {
  const BluetoothBanner({
    super.key,
    required this.status,
    required this.transport,
    required this.onEnable,
    required this.onPermissions,
    required this.onOpenSettings,
  });

  final AdapterStatus status;
  final TransportKind transport;
  final VoidCallback onEnable;
  final VoidCallback onPermissions;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final content = _content();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, a) => SizeTransition(
        sizeFactor: a,
        child: FadeTransition(opacity: a, child: child),
      ),
      child: content == null
          ? const SizedBox.shrink(key: ValueKey('none'))
          : _BannerBody(key: ValueKey(status), data: content),
    );
  }

  _BannerData? _content() {
    switch (status) {
      case AdapterStatus.on:
      case AdapterStatus.unknown:
      case AdapterStatus.turningOn:
        return null;
      case AdapterStatus.off:
        if (Platform.isIOS) {
          return _BannerData(
            icon: Icons.bluetooth_disabled_rounded,
            color: AppColors.danger,
            title: 'Bluetooth está apagado',
            body: 'iOS no permite que las apps lo activen. Desliza desde la esquina '
                'superior derecha para abrir el Centro de control y toca el icono '
                'de Bluetooth, o ve a Ajustes › Bluetooth.',
            action: 'Abrir Ajustes',
            onTap: onOpenSettings,
          );
        }
        return _BannerData(
          icon: Icons.bluetooth_disabled_rounded,
          color: AppColors.danger,
          title: 'Bluetooth está apagado',
          body: 'Actívalo para buscar y controlar el asador. No necesitas salir de la app.',
          action: 'Activar Bluetooth',
          onTap: onEnable,
        );
      case AdapterStatus.unauthorized:
        return _BannerData(
          icon: Icons.lock_outline_rounded,
          color: AppColors.warning,
          title: 'Permiso de Bluetooth necesario',
          body: Platform.isIOS
              ? 'Permite el acceso a Bluetooth en Ajustes › Asador › Bluetooth.'
              : 'La app necesita permiso para buscar y conectarse a dispositivos cercanos.',
          action: Platform.isIOS ? 'Abrir Ajustes' : 'Conceder permiso',
          onTap: Platform.isIOS ? onOpenSettings : onPermissions,
        );
      case AdapterStatus.unsupported:
        return _BannerData(
          icon: Icons.error_outline_rounded,
          color: AppColors.danger,
          title: transport == TransportKind.classic
              ? 'Bluetooth Clásico no disponible'
              : 'Bluetooth no disponible',
          body: transport == TransportKind.classic
              ? 'Este dispositivo no admite Bluetooth Clásico SPP.'
              : 'Este dispositivo no admite Bluetooth Low Energy.',
        );
    }
  }
}

class _BannerData {
  _BannerData({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    this.action,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onTap;
}

class _BannerBody extends StatelessWidget {
  const _BannerBody({super.key, required this.data});

  final _BannerData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: data.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        border: Border.all(color: data.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(data.icon, color: data.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  data.body,
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary, height: 1.4),
                ),
                if (data.action != null) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: data.onTap,
                    style: TextButton.styleFrom(
                      foregroundColor: data.color,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(data.action!, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
