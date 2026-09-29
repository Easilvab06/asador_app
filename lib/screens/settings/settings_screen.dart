import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/bluetooth_controller.dart';
import '../../controllers/providers.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/protocol_config.dart';
import '../../core/theme/app_colors.dart';
import '../../models/bluetooth_models.dart';
import '../../widgets/common.dart';

/// Ajustes: tecnología Bluetooth y protocolo configurable.
/// Permite adaptar la app a los comandos reales del firmware sin recompilar.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _dir;
  late final TextEditingController _stop;
  late final TextEditingController _tpl;

  @override
  void initState() {
    super.initState();
    final c = ref.read(protocolConfigProvider);
    _dir = TextEditingController(text: c.directionCommand);
    _stop = TextEditingController(text: c.stopCommand);
    _tpl = TextEditingController(text: c.speedTemplate);
  }

  @override
  void dispose() {
    _dir.dispose();
    _stop.dispose();
    _tpl.dispose();
    super.dispose();
  }

  void _update(ProtocolConfig c) => unawaited(ref.read(protocolConfigProvider.notifier).save(c));

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(protocolConfigProvider);
    final bt = ref.watch(bluetoothControllerProvider);
    final btCtrl = ref.read(bluetoothControllerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (Platform.isAndroid) ...[
                  const SectionLabel('Tecnología Bluetooth'),
                  const SizedBox(height: 10),
                  AppCard(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: RadioGroupCompat<TransportKind>(
                      value: bt.transport,
                      enabled: bt.link == LinkStatus.disconnected,
                      onChanged: (k) => unawaited(btCtrl.setTransport(k)),
                      options: const {
                        TransportKind.classic: (
                          'Bluetooth Clásico (SPP)',
                          'Firmware actual del ESP32. Solo Android.'
                        ),
                        TransportKind.ble: (
                          'Bluetooth Low Energy',
                          'Firmware BLE. Android + iPhone.'
                        ),
                      },
                    ),
                  ),
                  if (bt.link != LinkStatus.disconnected)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Text('Desconecta el asador para cambiar la tecnología.',
                          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textTertiary)),
                    ),
                  const SizedBox(height: 24),
                ],
                SectionLabel(
                  'Protocolo ESP32',
                  trailing: TextButton(
                    onPressed: () async {
                      await ref.read(protocolConfigProvider.notifier).resetToOriginal();
                      const d = ProtocolConfig();
                      _dir.text = d.directionCommand;
                      _stop.text = d.stopCommand;
                      _tpl.text = d.speedTemplate;
                    },
                    child: const Text('Restaurar original'),
                  ),
                ),
                const SizedBox(height: 10),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Valores por defecto extraídos del APK original: velocidad "4"–"8", '
                        'sentido "0", parada "1", sin terminador.',
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      _CmdField(
                        label: 'Comando de parada',
                        controller: _stop,
                        onChanged: (v) => _update(cfg.copyWith(stopCommand: v)),
                      ),
                      const SizedBox(height: 12),
                      _CmdField(
                        label: 'Comando de cambio de sentido',
                        controller: _dir,
                        onChanged: (v) => _update(cfg.copyWith(directionCommand: v)),
                      ),
                      const SizedBox(height: 12),
                      _CmdField(
                        label: 'Plantilla de velocidad ({v} = nivel)',
                        controller: _tpl,
                        onChanged: (v) {
                          if (v.contains('{v}')) _update(cfg.copyWith(speedTemplate: v));
                        },
                      ),
                      const SizedBox(height: 16),
                      Text('Rango de niveles: ${cfg.speedMin} – ${cfg.speedMax}',
                          style: theme.textTheme.titleMedium),
                      RangeSlider(
                        values: RangeValues(cfg.speedMin.toDouble(), cfg.speedMax.toDouble()),
                        min: 0,
                        max: 9,
                        divisions: 9,
                        activeColor: AppColors.ember,
                        labels: RangeLabels('${cfg.speedMin}', '${cfg.speedMax}'),
                        onChanged: (r) {
                          final a = r.start.round();
                          final b = r.end.round();
                          if (b <= a) return;
                          _update(cfg.copyWith(
                            speedMin: a,
                            speedMax: b,
                            speedDefault: cfg.speedDefault.clamp(a, b),
                          ));
                        },
                      ),
                      Text(
                        'Atención: con un solo carácter, los niveles 0 y 1 chocarían con '
                        'los comandos de sentido y parada originales.',
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
                      ),
                      const SizedBox(height: 16),
                      Text('Terminador', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: '', label: Text('Ninguno')),
                          ButtonSegment(value: '\n', label: Text(r'\n')),
                          ButtonSegment(value: '\r\n', label: Text(r'\r\n')),
                        ],
                        selected: {cfg.terminator},
                        onSelectionChanged: (s) => _update(cfg.copyWith(terminator: s.first)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const SectionLabel('Seguridad'),
                const SizedBox(height: 10),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Pausa antes de invertir: ${(cfg.reverseStopDelayMs / 1000).toStringAsFixed(1)} s',
                          style: theme.textTheme.titleMedium),
                      Slider(
                        value: cfg.reverseStopDelayMs.toDouble(),
                        min: 500,
                        max: 5000,
                        divisions: 18,
                        activeColor: AppColors.ember,
                        onChanged: (v) => _update(cfg.copyWith(reverseStopDelayMs: v.round())),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Reanudar giro tras invertir'),
                        subtitle: const Text('Reenvía el nivel de velocidad después del cambio de sentido.'),
                        value: cfg.resumeAfterReverse,
                        onChanged: (v) => _update(cfg.copyWith(resumeAfterReverse: v)),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Detener al cerrar la app'),
                        subtitle: const Text(
                          'Intenta enviar STOP si el sistema cierra la app. No garantizado: '
                          'la protección real debe estar en el firmware.',
                        ),
                        value: cfg.stopOnAppClose,
                        onChanged: (v) => _update(cfg.copyWith(stopOnAppClose: v)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const SectionLabel('Perfil BLE'),
                const SizedBox(height: 10),
                AppCard(
                  child: SelectableText(
                    'Servicio  ${AppConstants.bleServiceUuid}\n'
                    'RX write  ${AppConstants.bleRxCharUuid}\n'
                    'TX notify ${AppConstants.bleTxCharUuid}\n'
                    'Nombre    ${AppConstants.bleNamePrefix}…',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: AppColors.textSecondary,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CmdField extends StatelessWidget {
  const _CmdField({required this.label, required this.controller, required this.onChanged});

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: (v) {
        if (v.isNotEmpty) onChanged(v);
      },
      maxLength: 16,
      decoration: InputDecoration(labelText: label, counterText: ''),
      style: const TextStyle(fontFamily: 'monospace'),
    );
  }
}

/// Lista de opciones exclusivas con título y subtítulo.
class RadioGroupCompat<T> extends StatelessWidget {
  const RadioGroupCompat({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });

  final T value;
  final Map<T, (String, String)> options;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: options.entries.map((e) {
        final selected = e.key == value;
        return ListTile(
          enabled: enabled,
          onTap: enabled ? () => onChanged(e.key) : null,
          leading: Icon(
            selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
            color: selected ? AppColors.ember : AppColors.textTertiary,
          ),
          title: Text(e.value.$1, style: theme.textTheme.titleMedium),
          subtitle: Text(e.value.$2, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
        );
      }).toList(),
    );
  }
}
