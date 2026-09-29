/// Estado de rotación tal como lo conoce la app.
///
/// El firmware original NO devuelve estado, así que la app solo sabe lo que
/// ha ordenado. Tras una reconexión el estado real es [unknown].
enum MotorRun {
  stopped,
  running,
  unknown;

  String get label => switch (this) {
        MotorRun.stopped => 'Detenido',
        MotorRun.running => 'Girando',
        MotorRun.unknown => 'Desconocido',
      };
}

/// Sentido de giro. Como "0" es (probablemente) un toggle y el ESP32 no
/// informa, el sentido es RELATIVO al arranque del ESP32. El usuario puede
/// sincronizar la etiqueta desde el panel (pulsación larga en la tarjeta).
enum MotorDirection {
  clockwise,
  counterClockwise;

  MotorDirection get flipped => this == MotorDirection.clockwise
      ? MotorDirection.counterClockwise
      : MotorDirection.clockwise;

  String get label => switch (this) {
        MotorDirection.clockwise => 'Horario',
        MotorDirection.counterClockwise => 'Antihorario',
      };
}

/// Fase de la maniobra segura de inversión.
enum ReversePhase { idle, stopping, waiting, switching, resuming }

class MotorState {
  const MotorState({
    required this.run,
    required this.level,
    required this.direction,
    this.reversePhase = ReversePhase.idle,
    this.reverseProgress = 0,
    this.sending = false,
    this.lastError,
  });

  final MotorRun run;

  /// Nivel de velocidad en unidades del protocolo (original 4..8).
  final int level;
  final MotorDirection direction;
  final ReversePhase reversePhase;

  /// 0..1 durante la espera de inversión.
  final double reverseProgress;
  final bool sending;
  final String? lastError;

  bool get isRunning => run == MotorRun.running;
  bool get isReversing => reversePhase != ReversePhase.idle;

  MotorState copyWith({
    MotorRun? run,
    int? level,
    MotorDirection? direction,
    ReversePhase? reversePhase,
    double? reverseProgress,
    bool? sending,
    String? lastError,
    bool clearError = false,
  }) {
    return MotorState(
      run: run ?? this.run,
      level: level ?? this.level,
      direction: direction ?? this.direction,
      reversePhase: reversePhase ?? this.reversePhase,
      reverseProgress: reverseProgress ?? this.reverseProgress,
      sending: sending ?? this.sending,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}
