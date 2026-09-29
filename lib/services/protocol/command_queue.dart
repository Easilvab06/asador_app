import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../core/constants/protocol_config.dart';

/// Serializa y espacia los comandos hacia el ESP32.
///
/// * Un solo comando en vuelo a la vez (sin escrituras simultáneas).
/// * Intervalo mínimo entre comandos ([ProtocolConfig.minCommandIntervalMs]).
/// * Codifica exactamente como `SendText` de Kodular: texto → bytes UTF-8
///   (ASCII para "0".."9") + terminador configurable (original: ninguno).
class CommandQueue {
  CommandQueue({required this.writer, required this.config});

  final Future<void> Function(Uint8List bytes) writer;
  ProtocolConfig Function() config;

  Future<void> _tail = Future<void>.value();
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  static Uint8List encode(String command, ProtocolConfig cfg) =>
      Uint8List.fromList(utf8.encode('$command${cfg.terminator}'));

  /// Encola [command]; el Future completa cuando se ha escrito (o falla).
  Future<void> send(String command) {
    final completer = Completer<void>();
    _tail = _tail.then((_) async {
      try {
        final cfg = config();
        final gap = DateTime.now().difference(_lastSent);
        final min = Duration(milliseconds: cfg.minCommandIntervalMs);
        if (gap < min) await Future<void>.delayed(min - gap);
        await writer(encode(command, cfg));
        _lastSent = DateTime.now();
        completer.complete();
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}

/// Coalescencia de valores de velocidad: mientras el usuario arrastra, solo
/// se envía el último nivel cada [interval] (throttle con envío final).
class LatestValueThrottle<T> {
  LatestValueThrottle({required this.interval, required this.onEmit});

  final Duration interval;
  final Future<void> Function(T value) onEmit;

  T? _pending;
  bool _hasPending = false;
  Timer? _timer;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  void add(T value) {
    _pending = value;
    _hasPending = true;
    final since = DateTime.now().difference(_last);
    if (since >= interval && _timer == null) {
      _flush();
    } else {
      _timer ??= Timer(interval - since, _flush);
    }
  }

  void _flush() {
    _timer?.cancel();
    _timer = null;
    if (!_hasPending) return;
    final v = _pending as T;
    _hasPending = false;
    _last = DateTime.now();
    unawaited(onEmit(v).catchError((Object _) {}));
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _hasPending = false;
  }
}
