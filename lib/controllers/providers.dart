import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/protocol_config.dart';
import '../models/bluetooth_models.dart';
import '../services/settings_repository.dart';
import '../services/transport/ble_transport.dart';
import '../services/transport/classic_spp_transport.dart';
import '../services/transport/motor_transport.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Estructura Riverpod
///
///   settingsRepositoryProvider   Provider           persistencia
///   transportsProvider           Provider           {classic: SPP, ble: BLE}
///   protocolConfigProvider       NotifierProvider   comandos configurables
///   bluetoothControllerProvider  NotifierProvider   adaptador · escaneo · enlace · reconexión
///   motorControllerProvider      NotifierProvider   velocidad · sentido · start/stop · seguridad
///
/// La UI solo lee estado (`ref.watch`) y llama métodos de los controladores.
/// Los controladores solo hablan con `MotorTransport`, nunca con plugins.
/// ─────────────────────────────────────────────────────────────────────────

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository();
});

final transportsProvider = Provider<Map<TransportKind, MotorTransport>>((ref) {
  final map = <TransportKind, MotorTransport>{
    TransportKind.classic: ClassicSppTransport(),
    TransportKind.ble: BleTransport(),
  };
  ref.onDispose(() {
    for (final t in map.values) {
      t.dispose();
    }
  });
  return map;
});

final protocolConfigProvider =
    NotifierProvider<ProtocolConfigNotifier, ProtocolConfig>(ProtocolConfigNotifier.new);

class ProtocolConfigNotifier extends Notifier<ProtocolConfig> {
  @override
  ProtocolConfig build() {
    _load();
    return const ProtocolConfig();
  }

  Future<void> _load() async {
    final saved = await ref.read(settingsRepositoryProvider).loadProtocol();
    state = saved;
  }

  Future<void> save(ProtocolConfig config) async {
    state = config;
    await ref.read(settingsRepositoryProvider).saveProtocol(config);
  }

  Future<void> resetToOriginal() => save(const ProtocolConfig());
}
