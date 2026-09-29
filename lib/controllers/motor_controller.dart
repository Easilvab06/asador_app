import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/protocol_config.dart';
import '../models/bluetooth_models.dart';
import '../models/motor_state.dart';
import '../services/protocol/command_queue.dart';
import 'bluetooth_controller.dart';
import 'providers.dart';

final motorControllerProvider =
    NotifierProvider<MotorController, MotorState>(MotorController.new);

/// Lógica del motor + medidas de seguridad.
///
/// * Solo se envían comandos con enlace activo; los controles se deshabilitan
///   sin conexión.
/// * Velocidad: se envía solo al cambiar de nivel y con throttle.
/// * STOP: siempre se envía, cancela cualquier maniobra en curso.
/// * Inversión segura: STOP → espera → "0" → (opcional) reanudar velocidad.
/// * Pérdida de enlace: el estado real pasa a "desconocido" (el ESP32 no
///   informa) y se aborta cualquier maniobra.
class MotorController extends Notifier<MotorState> {
  late CommandQueue _queue;
  late LatestValueThrottle<int> _speedThrottle;
  int _reverseToken = 0;
  bool _directionLabelFlipped = false;

  ProtocolConfig get _cfg => ref.read(protocolConfigProvider);

  @override
  MotorState build() {
    _queue = CommandQueue(
      writer: (bytes) {
        final bt = ref.read(bluetoothControllerProvider.notifier);
        return bt.transport.write(bytes);
      },
      config: () => ref.read(protocolConfigProvider),
    );
    _speedThrottle = LatestValueThrottle<int>(
      interval: const Duration(milliseconds: 250),
      onEmit: (level) => _send(_cfg.speedCommand(level)),
    );
    ref.onDispose(_speedThrottle.cancel);

    // Reaccionar a cambios de enlace.
    ref.listen<LinkStatus>(
      bluetoothControllerProvider.select((s) => s.link),
      (prev, next) {
        if (prev == LinkStatus.connected && next != LinkStatus.connected) {
          _abortReverse();
          _speedThrottle.cancel();
          // El motor puede seguir girando o no: depende del firmware.
          state = state.copyWith(
            run: MotorRun.unknown,
            reversePhase: ReversePhase.idle,
            reverseProgress: 0,
            sending: false,
          );
        }
        if (next == LinkStatus.connected && prev != LinkStatus.connected) {
          // Conexión nueva o reconexión: el ESP32 no reporta estado.
          state = state.copyWith(run: MotorRun.unknown, clearError: true);
        }
      },
    );

    // Si cambia el rango del protocolo, re-encajar el nivel.
    ref.listen<ProtocolConfig>(protocolConfigProvider, (prev, next) {
      final lvl = state.level.clamp(next.speedMin, next.speedMax);
      if (lvl != state.level) state = state.copyWith(level: lvl);
    });

    Future.microtask(_loadPrefs);
    final cfg = ref.read(protocolConfigProvider);
    return MotorState(
      run: MotorRun.stopped,
      level: cfg.speedDefault,
      direction: MotorDirection.clockwise,
    );
  }

  Future<void> _loadPrefs() async {
    _directionLabelFlipped = await ref.read(settingsRepositoryProvider).loadDirectionFlipped();
    if (_directionLabelFlipped) {
      state = state.copyWith(direction: MotorDirection.counterClockwise);
    }
  }

  bool get _linked => ref.read(bluetoothControllerProvider).isConnected;

  // --------------------------------------------------------------- acciones

  /// Selecciona nivel. Si gira, se envía (throttled). Si está parado solo
  /// preselecciona: arrancar requiere pulsar INICIAR (evita arranques
  /// accidentales al tocar el control).
  void setLevel(int level) {
    final cfg = _cfg;
    final lvl = level.clamp(cfg.speedMin, cfg.speedMax);
    if (lvl == state.level) return;
    state = state.copyWith(level: lvl);
    if (state.isRunning && !state.isReversing && _linked) {
      _speedThrottle.add(lvl);
    }
  }

  /// Arranque = enviar el nivel actual (así arrancaba el slider original).
  Future<void> start() async {
    if (!_linked || state.isReversing) return;
    final ok = await _send(_cfg.speedCommand(state.level));
    if (ok) state = state.copyWith(run: MotorRun.running);
  }

  /// Parada: SIEMPRE se envía y cancela cualquier maniobra.
  Future<void> stop() async {
    _speedThrottle.cancel();
    _abortReverse();
    state = state.copyWith(reversePhase: ReversePhase.idle, reverseProgress: 0);
    if (!_linked) return;
    final ok = await _send(_cfg.stopCommand);
    if (ok) state = state.copyWith(run: MotorRun.stopped);
  }

  /// Cambio de sentido con protección.
  Future<void> reverse() async {
    if (!_linked || state.isReversing) return;
    final cfg = _cfg;
    final token = ++_reverseToken;
    bool aborted() => token != _reverseToken || !_linked;
    final wasRunning = state.run != MotorRun.stopped; // "desconocido" se trata como girando

    if (wasRunning) {
      _speedThrottle.cancel();
      state = state.copyWith(reversePhase: ReversePhase.stopping, reverseProgress: 0);
      if (!await _send(cfg.stopCommand) || aborted()) return _endReverse(token);
      state = state.copyWith(run: MotorRun.stopped, reversePhase: ReversePhase.waiting);

      // Espera a que el motor (y la carga) se detengan antes de invertir.
      final total = cfg.reverseStopDelayMs;
      const tick = 50;
      for (var t = 0; t < total; t += tick) {
        await Future<void>.delayed(const Duration(milliseconds: tick));
        if (aborted()) return _endReverse(token);
        state = state.copyWith(reverseProgress: ((t + tick) / total).clamp(0.0, 1.0));
      }
    }

    if (aborted()) return _endReverse(token);
    state = state.copyWith(reversePhase: ReversePhase.switching, reverseProgress: 1);
    if (!await _send(cfg.directionCommand) || aborted()) return _endReverse(token);
    state = state.copyWith(direction: state.direction.flipped);

    if (wasRunning && cfg.resumeAfterReverse && !aborted()) {
      state = state.copyWith(reversePhase: ReversePhase.resuming);
      if (await _send(cfg.speedCommand(state.level)) && !aborted()) {
        state = state.copyWith(run: MotorRun.running);
      }
    }
    await _endReverse(token);
  }

  /// Solo cambia la ETIQUETA del sentido (sin enviar nada) para sincronizarla
  /// con el giro real observado — el firmware no informa el sentido.
  Future<void> syncDirectionLabel() async {
    _directionLabelFlipped = !_directionLabelFlipped;
    state = state.copyWith(direction: state.direction.flipped);
    await ref.read(settingsRepositoryProvider).saveDirectionFlipped(_directionLabelFlipped);
  }

  /// Parada "best effort" al cerrar la app (si está configurado).
  Future<void> onAppDetached() async {
    if (_cfg.stopOnAppClose && _linked) await _send(_cfg.stopCommand);
  }

  void clearError() => state = state.copyWith(clearError: true);

  // ---------------------------------------------------------------- interno

  void _abortReverse() => _reverseToken++;

  Future<void> _endReverse(int token) async {
    // Si otro flujo (STOP / desconexión) abortó la maniobra, ya dejó el estado limpio.
    if (token != _reverseToken) return;
    state = state.copyWith(reversePhase: ReversePhase.idle, reverseProgress: 0);
  }

  Future<bool> _send(String command) async {
    if (!_linked) return false;
    state = state.copyWith(sending: true, clearError: true);
    try {
      await _queue.send(command);
      return true;
    } on TransportException catch (e) {
      state = state.copyWith(lastError: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(lastError: 'No se pudo enviar el comando.');
      return false;
    } finally {
      state = state.copyWith(sending: false);
    }
  }
}
