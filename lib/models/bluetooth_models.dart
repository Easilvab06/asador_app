/// Tecnología de enlace con el ESP32.
enum TransportKind {
  /// Bluetooth Clásico SPP — lo que usa el APK/firmware actual. Solo Android.
  classic,

  /// Bluetooth Low Energy — Android + iOS. Requiere firmware BLE.
  ble;

  String get label => switch (this) {
        TransportKind.classic => 'Bluetooth Clásico',
        TransportKind.ble => 'Bluetooth LE',
      };

  String get shortLabel => switch (this) {
        TransportKind.classic => 'Clásico',
        TransportKind.ble => 'BLE',
      };
}

/// Estado del adaptador Bluetooth del teléfono.
enum AdapterStatus {
  unknown,
  unsupported,
  unauthorized,
  off,
  turningOn,
  on;

  bool get isReady => this == AdapterStatus.on;
}

/// Estado del enlace con el asador.
enum LinkStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error;

  bool get isConnected => this == LinkStatus.connected;
  bool get isBusy =>
      this == LinkStatus.connecting || this == LinkStatus.reconnecting;
}

/// Dispositivo Bluetooth visible para el usuario.
class BtDevice {
  const BtDevice({
    required this.id,
    required this.name,
    required this.kind,
    this.rssi,
    this.bonded = false,
  });

  /// MAC (Android) o identificador del sistema (iOS/BLE).
  final String id;
  final String? name;
  final TransportKind kind;
  final int? rssi;
  final bool bonded;

  String get displayName =>
      (name == null || name!.trim().isEmpty) ? 'Dispositivo sin nombre' : name!;

  /// Heurística para destacar el asador en la lista (no filtra).
  bool get looksLikeAsador {
    final n = (name ?? '').toUpperCase();
    return n.contains('ASADOR') || n.contains('KANKA') || n.contains('ESP32');
  }

  /// 0..4 barras de señal.
  int get signalBars {
    final r = rssi;
    if (r == null) return 0;
    if (r >= -60) return 4;
    if (r >= -70) return 3;
    if (r >= -80) return 2;
    if (r >= -90) return 1;
    return 0;
  }

  BtDevice copyWith({int? rssi, String? name, bool? bonded}) => BtDevice(
        id: id,
        name: name ?? this.name,
        kind: kind,
        rssi: rssi ?? this.rssi,
        bonded: bonded ?? this.bonded,
      );

  @override
  bool operator ==(Object other) =>
      other is BtDevice && other.id.toUpperCase() == id.toUpperCase();

  @override
  int get hashCode => id.toUpperCase().hashCode;
}

/// Excepción de transporte con mensaje listo para mostrar.
class TransportException implements Exception {
  const TransportException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'TransportException($code): $message';
}
