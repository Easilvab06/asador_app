import 'dart:convert';

import 'package:asador/core/constants/protocol_config.dart';
import 'package:asador/models/bluetooth_models.dart';
import 'package:asador/services/protocol/command_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Protocolo original (extraído del APK)', () {
    const cfg = ProtocolConfig();

    test('rango de velocidad 4..8, inicial 6', () {
      expect(cfg.speedMin, 4);
      expect(cfg.speedMax, 8);
      expect(cfg.speedDefault, 6);
      expect(cfg.levels, 5);
    });

    test('velocidad se envía como entero en texto, sin terminador', () {
      expect(utf8.decode(CommandQueue.encode(cfg.speedCommand(6), cfg)), '6');
      expect(CommandQueue.encode(cfg.speedCommand(4), cfg), [0x34]);
      expect(CommandQueue.encode(cfg.speedCommand(8), cfg), [0x38]);
    });

    test('niveles fuera de rango se recortan', () {
      expect(cfg.speedCommand(2), '4');
      expect(cfg.speedCommand(99), '8');
    });

    test('sentido = "0", parada = "1"', () {
      expect(CommandQueue.encode(cfg.directionCommand, cfg), [0x30]);
      expect(CommandQueue.encode(cfg.stopCommand, cfg), [0x31]);
    });

    test('terminador y plantilla configurables', () {
      final c = cfg.copyWith(terminator: '\n', speedTemplate: 'S{v}');
      expect(utf8.decode(CommandQueue.encode(c.speedCommand(5), c)), 'S5\n');
    });

    test('JSON ida y vuelta', () {
      final c = cfg.copyWith(stopCommand: 'X', reverseStopDelayMs: 2500);
      final r = ProtocolConfig.fromJson(c.toJson());
      expect(r.stopCommand, 'X');
      expect(r.reverseStopDelayMs, 2500);
    });

    test('JSON con rango inválido vuelve al original', () {
      final r = ProtocolConfig.fromJson({'speedMin': 9, 'speedMax': 3});
      expect(r.speedMin, 4);
      expect(r.speedMax, 8);
    });
  });

  group('CommandQueue', () {
    test('serializa y respeta el intervalo mínimo', () async {
      final sent = <String>[];
      final times = <DateTime>[];
      final q = CommandQueue(
        writer: (b) async {
          sent.add(utf8.decode(b));
          times.add(DateTime.now());
        },
        config: () => const ProtocolConfig(minCommandIntervalMs: 50),
      );
      await Future.wait([q.send('1'), q.send('0'), q.send('6')]);
      expect(sent, ['1', '0', '6']);
      expect(times[1].difference(times[0]).inMilliseconds, greaterThanOrEqualTo(45));
      expect(times[2].difference(times[1]).inMilliseconds, greaterThanOrEqualTo(45));
    });

    test('un error no bloquea la cola', () async {
      var calls = 0;
      final q = CommandQueue(
        writer: (b) async {
          calls++;
          if (calls == 1) throw const TransportException('io_error', 'x');
        },
        config: () => const ProtocolConfig(minCommandIntervalMs: 0),
      );
      await expectLater(q.send('1'), throwsA(isA<TransportException>()));
      await q.send('6');
      expect(calls, 2);
    });
  });

  group('LatestValueThrottle', () {
    test('coalesce: envía el primero y el último', () async {
      final out = <int>[];
      final t = LatestValueThrottle<int>(
        interval: const Duration(milliseconds: 80),
        onEmit: (v) async => out.add(v),
      );
      for (var i = 4; i <= 8; i++) {
        t.add(i);
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(out, [4, 8]);
    });
  });
}
