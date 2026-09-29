/// ============================================================================
/// PROTOCOLO ESP32
/// ============================================================================
///
/// Valores EXTRAÍDOS del APK original `Kanka_2_copy.apk` (Kodular) — archivo
/// `Screen2.yail`, decompilado. Todos los envíos usan `BluetoothClient.SendText`
/// (texto ASCII/UTF-8) SIN delimitador ni salto de línea, y solo si
/// `BluetoothClient.IsConnected` es verdadero.
///
///   Componente            Evento             Envía
///   ───────────────────   ────────────────   ─────────────────────────────
///   Slider1 (4..8, ini 6) PositionChanged    "4" | "5" | "6" | "7" | "8"
///   Lottie3 (flecha ⇄)    Click              "0"
///   Lottie2 (power ⏻)     Click              "1"
///
/// ⚠ NO puede determinarse a partir del APK (depende del firmware):
///   • Si "0" ALTERNA el sentido o fija un sentido concreto.
///   • Si "1" es STOP puro o un toggle encendido/apagado.
///   • Qué velocidad real / PWM corresponde a cada nivel 4..8.
///   • Si tras "1" un nuevo nivel de velocidad vuelve a arrancar el motor.
///   • El ESP32 no envía respuesta alguna (la app original nunca lee datos).
///
/// Por eso todo es configurable en [ProtocolConfig] (y editable desde la
/// pantalla Ajustes → Protocolo) sin tocar el resto de la app.
library;

/// Comandos por defecto — idénticos a los del APK original.
class MotorCommand {
  MotorCommand._();

  /// Lottie3 · flecha bidireccional → `SendText("0")`.
  static const String toggleDirection = '0';

  /// Lottie2 · botón power → `SendText("1")`.
  static const String stop = '1';

  /// Slider1.MinValue
  static const int speedMin = 4;

  /// Slider1.MaxValue
  static const int speedMax = 8;

  /// Slider1.ThumbPosition inicial
  static const int speedDefault = 6;

  /// `format as decimal (ThumbPosition, 0)` → "4".."8".
  static const String speedTemplate = '{v}';

  /// SendText no añade delimitador.
  static const String terminator = '';
}

/// Configuración en tiempo de ejecución del protocolo (persistida).
class ProtocolConfig {
  const ProtocolConfig({
    this.directionCommand = MotorCommand.toggleDirection,
    this.stopCommand = MotorCommand.stop,
    this.speedMin = MotorCommand.speedMin,
    this.speedMax = MotorCommand.speedMax,
    this.speedDefault = MotorCommand.speedDefault,
    this.speedTemplate = MotorCommand.speedTemplate,
    this.terminator = MotorCommand.terminator,
    this.reverseStopDelayMs = 1500,
    this.resumeAfterReverse = true,
    this.minCommandIntervalMs = 150,
    this.stopOnAppClose = false,
  });

  /// Comando de cambio de sentido (original: "0", se asume toggle).
  final String directionCommand;

  /// Comando de parada (original: "1").
  final String stopCommand;

  /// Rango de niveles de velocidad (original 4..8).
  final int speedMin;
  final int speedMax;
  final int speedDefault;

  /// Plantilla del comando de velocidad. `{v}` se sustituye por el nivel.
  /// Original: "{v}" → "6". Ejemplo alternativo para otro firmware: "S{v}".
  final String speedTemplate;

  /// Sufijo añadido a cada comando. Original: "" (vacío).
  /// Si el firmware lee líneas (`readStringUntil('\n')`) usar "\n".
  final String terminator;

  /// Protección de inversión: tiempo de espera entre STOP y cambio de sentido
  /// para que el motor y la carga (carne) se detengan antes de invertir.
  final int reverseStopDelayMs;

  /// Tras invertir, reenviar el nivel de velocidad para reanudar el giro.
  final bool resumeAfterReverse;

  /// Intervalo mínimo entre comandos (anti-ráfagas).
  final int minCommandIntervalMs;

  /// Enviar STOP cuando la app pasa a segundo plano de forma definitiva
  /// (detached). En un asador normalmente NO se desea (ver README §Seguridad).
  final bool stopOnAppClose;

  int get levels => speedMax - speedMin + 1;

  String speedCommand(int level) =>
      speedTemplate.replaceAll('{v}', level.clamp(speedMin, speedMax).toString());

  ProtocolConfig copyWith({
    String? directionCommand,
    String? stopCommand,
    int? speedMin,
    int? speedMax,
    int? speedDefault,
    String? speedTemplate,
    String? terminator,
    int? reverseStopDelayMs,
    bool? resumeAfterReverse,
    int? minCommandIntervalMs,
    bool? stopOnAppClose,
  }) {
    return ProtocolConfig(
      directionCommand: directionCommand ?? this.directionCommand,
      stopCommand: stopCommand ?? this.stopCommand,
      speedMin: speedMin ?? this.speedMin,
      speedMax: speedMax ?? this.speedMax,
      speedDefault: speedDefault ?? this.speedDefault,
      speedTemplate: speedTemplate ?? this.speedTemplate,
      terminator: terminator ?? this.terminator,
      reverseStopDelayMs: reverseStopDelayMs ?? this.reverseStopDelayMs,
      resumeAfterReverse: resumeAfterReverse ?? this.resumeAfterReverse,
      minCommandIntervalMs: minCommandIntervalMs ?? this.minCommandIntervalMs,
      stopOnAppClose: stopOnAppClose ?? this.stopOnAppClose,
    );
  }

  Map<String, Object> toJson() => {
        'directionCommand': directionCommand,
        'stopCommand': stopCommand,
        'speedMin': speedMin,
        'speedMax': speedMax,
        'speedDefault': speedDefault,
        'speedTemplate': speedTemplate,
        'terminator': terminator,
        'reverseStopDelayMs': reverseStopDelayMs,
        'resumeAfterReverse': resumeAfterReverse,
        'minCommandIntervalMs': minCommandIntervalMs,
        'stopOnAppClose': stopOnAppClose,
      };

  factory ProtocolConfig.fromJson(Map<String, dynamic> j) {
    const d = ProtocolConfig();
    T read<T>(String k, T fallback) {
      final v = j[k];
      return v is T ? v : fallback;
    }

    final min = read<int>('speedMin', d.speedMin);
    final max = read<int>('speedMax', d.speedMax);
    final validRange = min < max;
    return ProtocolConfig(
      directionCommand: read('directionCommand', d.directionCommand),
      stopCommand: read('stopCommand', d.stopCommand),
      speedMin: validRange ? min : d.speedMin,
      speedMax: validRange ? max : d.speedMax,
      speedDefault: read<int>('speedDefault', d.speedDefault)
          .clamp(validRange ? min : d.speedMin, validRange ? max : d.speedMax),
      speedTemplate: read('speedTemplate', d.speedTemplate),
      terminator: read('terminator', d.terminator),
      reverseStopDelayMs: read('reverseStopDelayMs', d.reverseStopDelayMs),
      resumeAfterReverse: read('resumeAfterReverse', d.resumeAfterReverse),
      minCommandIntervalMs: read('minCommandIntervalMs', d.minCommandIntervalMs),
      stopOnAppClose: read('stopOnAppClose', d.stopOnAppClose),
    );
  }
}
