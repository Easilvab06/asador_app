import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/bluetooth_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/bluetooth_models.dart';
import '../../widgets/bluetooth_banner.dart';
import '../../widgets/common.dart';
import '../../widgets/connected_overlay.dart';
import '../../widgets/connection_status.dart';
import '../device_selection/device_selection_sheet.dart';
import '../motor_control/motor_control_screen.dart';
import '../settings/settings_screen.dart';
import '../splash/splash_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bt = ref.watch(bluetoothControllerProvider);
    final ctrl = ref.read(bluetoothControllerProvider.notifier);
    final theme = Theme.of(context);
    final last = bt.lastDevice;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final pad = box.maxWidth < 380 ? 16.0 : 24.0;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(pad, 12, pad, 0),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          const BrandMark(size: 40),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              AppConstants.appName,
                              style: theme.textTheme.titleLarge?.copyWith(letterSpacing: 4),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Ajustes',
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
                            ),
                            icon: const Icon(Icons.tune_rounded, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(pad, 24, pad, pad),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Hola 👋', style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary)),
                          const SizedBox(height: 6),
                          Text(
                            'Conecta tu asador para\nempezar a girar.',
                            style: theme.textTheme.headlineMedium?.copyWith(height: 1.2),
                          ),
                          const SizedBox(height: 28),
                          BluetoothBanner(
                            status: bt.adapter,
                            transport: bt.transport,
                            onEnable: () => unawaited(ctrl.requestEnable()),
                            onPermissions: () => unawaited(ctrl.ensureReady()),
                            onOpenSettings: () => unawaited(ctrl.openSystemSettings()),
                          ),
                          AppCard(
                            child: Column(
                              children: [
                                StatusRow(
                                  icon: Icons.bluetooth_rounded,
                                  label: 'Bluetooth · ${bt.transport.shortLabel}',
                                  style: StatusStyle.adapter(bt.adapter),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Divider(height: 1),
                                ),
                                StatusRow(
                                  icon: Icons.outdoor_grill_rounded,
                                  label: 'Dispositivo',
                                  style: StatusStyle.link(bt.link, attempt: bt.reconnectAttempt),
                                  detail: bt.device?.displayName ?? last?.displayName,
                                ),
                              ],
                            ),
                          ),
                          if (bt.error != null) ...[
                            const SizedBox(height: 12),
                            _ErrorLine(message: bt.error!, onClose: ctrl.clearError),
                          ],
                          const Spacer(),
                          const SizedBox(height: 24),
                          if (bt.isConnected) ...[
                            PrimaryButton(
                              label: 'Abrir panel de control',
                              icon: Icons.tune_rounded,
                              color: AppColors.success,
                              onPressed: () => _openControl(context),
                            ),
                          ] else ...[
                            if (last != null) ...[
                              PrimaryButton(
                                label: 'Conectar ${last.displayName}',
                                icon: Icons.bolt_rounded,
                                loading: bt.link.isBusy,
                                onPressed: bt.adapter == AdapterStatus.unsupported
                                    ? null
                                    : () => _quickConnect(context, ref, last),
                              ),
                              const SizedBox(height: 12),
                              PrimaryButton(
                                label: 'Buscar otro asador',
                                outlined: true,
                                color: AppColors.textSecondary,
                                onPressed: bt.link.isBusy ? null : () => _openPicker(context, ref),
                              ),
                            ] else
                              PrimaryButton(
                                label: 'Conectar asador',
                                icon: Icons.bluetooth_searching_rounded,
                                loading: bt.link.isBusy,
                                onPressed: bt.adapter == AdapterStatus.unsupported
                                    ? null
                                    : () => _openPicker(context, ref),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context, WidgetRef ref) async {
    final device = await showDeviceSelectionSheet(context);
    if (device == null || !context.mounted) return;
    await _afterConnected(context, device);
  }

  Future<void> _quickConnect(BuildContext context, WidgetRef ref, BtDevice device) async {
    final ok = await ref.read(bluetoothControllerProvider.notifier).connect(device);
    if (!ok || !context.mounted) return;
    await _afterConnected(context, device);
  }

  Future<void> _afterConnected(BuildContext context, BtDevice device) async {
    await showConnectedOverlay(context, deviceName: device.displayName);
    if (!context.mounted) return;
    _openControl(context);
  }

  void _openControl(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MotorControlScreen()));
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textPrimary)),
          ),
          IconButton(
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
