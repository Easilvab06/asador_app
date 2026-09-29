import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/bluetooth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../models/bluetooth_models.dart';
import '../../widgets/bluetooth_banner.dart';
import '../../widgets/device_card.dart';
import '../../widgets/radar_scan.dart';

/// Hoja de selección del ESP32. Devuelve el dispositivo si se conectó.
Future<BtDevice?> showDeviceSelectionSheet(BuildContext context) {
  return showModalBottomSheet<BtDevice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _DeviceSelectionSheet(),
  );
}

class _DeviceSelectionSheet extends ConsumerStatefulWidget {
  const _DeviceSelectionSheet();

  @override
  ConsumerState<_DeviceSelectionSheet> createState() => _DeviceSelectionSheetState();
}

class _DeviceSelectionSheetState extends ConsumerState<_DeviceSelectionSheet> {
  bool _showAll = false;
  String? _connectingId;
  late final BluetoothController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = ref.read(bluetoothControllerProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_ctrl.startScan()));
  }

  @override
  void dispose() {
    unawaited(_ctrl.stopScan());
    super.dispose();
  }

  Future<void> _connect(BtDevice d) async {
    setState(() => _connectingId = d.id);
    final ok = await _ctrl.connect(d);
    if (!mounted) return;
    setState(() => _connectingId = null);
    if (ok) Navigator.of(context).pop(d);
  }

  @override
  Widget build(BuildContext context) {
    final bt = ref.watch(bluetoothControllerProvider);
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    final filtered = _showAll
        ? bt.devices
        : bt.devices.where((d) => d.looksLikeAsador || d.bonded).toList();
    final hidden = bt.devices.length - filtered.length;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 12 + media.viewPadding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                RadarScan(active: bt.scanning, size: 64),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Seleccionar asador', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text(
                        bt.scanning ? 'Buscando dispositivos cercanos…' : '${bt.devices.length} dispositivos',
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: bt.scanning ? 'Detener búsqueda' : 'Buscar de nuevo',
                  onPressed: bt.scanning ? () => unawaited(_ctrl.stopScan()) : () => unawaited(_ctrl.startScan()),
                  icon: Icon(
                    bt.scanning ? Icons.stop_circle_outlined : Icons.refresh_rounded,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            if (_ctrl.canChooseTransport) ...[
              const SizedBox(height: 16),
              _TransportSelector(
                value: bt.transport,
                enabled: !bt.link.isBusy,
                onChanged: (k) async {
                  await _ctrl.setTransport(k);
                  if (mounted) unawaited(_ctrl.startScan());
                },
              ),
            ],
            const SizedBox(height: 16),
            BluetoothBanner(
              status: bt.adapter,
              transport: bt.transport,
              onEnable: () async {
                if (await _ctrl.requestEnable()) unawaited(_ctrl.startScan());
              },
              onPermissions: () => unawaited(_ctrl.startScan()),
              onOpenSettings: () => unawaited(_ctrl.openSystemSettings()),
            ),
            if (bt.error != null && bt.link == LinkStatus.error)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  bt.error!,
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.danger),
                ),
              ),
            Flexible(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: filtered.isEmpty
                    ? _EmptyState(
                        key: const ValueKey('empty'),
                        scanning: bt.scanning,
                        transport: bt.transport,
                      )
                    : ListView.separated(
                        key: const ValueKey('list'),
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final d = filtered[i];
                          return DeviceCard(
                            device: d,
                            connecting: _connectingId == d.id,
                            enabled: _connectingId == null && bt.adapter.isReady,
                            onConnect: () => unawaited(_connect(d)),
                          );
                        },
                      ),
              ),
            ),
            if (hidden > 0 || _showAll)
              TextButton(
                onPressed: () => setState(() => _showAll = !_showAll),
                child: Text(
                  _showAll ? 'Mostrar solo asadores' : 'Mostrar todos ($hidden más)',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TransportSelector extends StatelessWidget {
  const _TransportSelector({required this.value, required this.onChanged, required this.enabled});

  final TransportKind value;
  final ValueChanged<TransportKind> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<TransportKind>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: TransportKind.classic,
              label: Text('Clásico (actual)'),
              icon: Icon(Icons.settings_input_antenna_rounded, size: 18),
            ),
            ButtonSegment(
              value: TransportKind.ble,
              label: Text('BLE'),
              icon: Icon(Icons.bluetooth_rounded, size: 18),
            ),
          ],
          selected: {value},
          onSelectionChanged: enabled ? (s) => onChanged(s.first) : null,
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? AppColors.emberSoft : AppColors.surfaceHigh,
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? AppColors.ember : AppColors.textSecondary,
            ),
            side: const WidgetStatePropertyAll(BorderSide(color: AppColors.stroke)),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value == TransportKind.classic
              ? 'Firmware actual (BluetoothSerial). Muestra los emparejados en Ajustes y los cercanos.'
              : 'Requiere el firmware BLE del asador. Compatible también con iPhone.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({super.key, required this.scanning, required this.transport});

  final bool scanning;
  final TransportKind transport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            scanning ? Icons.radar_rounded : Icons.bluetooth_disabled_rounded,
            size: 36,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 12),
          Text(
            scanning ? 'Buscando tu asador…' : 'No se encontró ningún asador',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            transport == TransportKind.classic
                ? 'Enciende el ESP32. Si no aparece, emparéjalo primero en Ajustes › Bluetooth.'
                : 'Enciende el ESP32 con el firmware BLE y acércate a menos de 10 m.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
