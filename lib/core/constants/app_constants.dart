/// Constantes globales de la app y del perfil BLE propuesto.
class AppConstants {
  AppConstants._();

  static const String appName = 'ASADOR';
  static const String appTagline = 'Control inteligente de rotación';

  // ------------------------------------------------------------------ BLE
  // Perfil propuesto para el firmware BLE (NO existe en el firmware actual,
  // que es Bluetooth Clásico). Se usa el "Nordic UART Service" (NUS) por ser
  // un estándar de facto: se puede probar con nRF Connect sin la app.
  //
  //   ESP32 (servidor GATT)
  //   └─ Service  6E400001-B5A3-F393-E0A9-E50E24DCCA9E   (NUS)
  //      ├─ RX    6E400002-…   Write / WriteNoResponse  ← la app escribe "0","1","4".."8"
  //      └─ TX    6E400003-…   Notify                    → estado opcional
  static const String bleServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String bleRxCharUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const String bleTxCharUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

  /// Prefijo de nombre anunciado por el ESP32 BLE (filtro de escaneo).
  static const String bleNamePrefix = 'ASADOR';

  // ------------------------------------------------------------- tiempos
  static const Duration scanTimeout = Duration(seconds: 12);
  static const Duration connectTimeout = Duration(seconds: 12);

  /// Reintentos automáticos tras pérdida de conexión no solicitada.
  static const int reconnectAttempts = 3;
  static const Duration reconnectBaseDelay = Duration(seconds: 2);
}
