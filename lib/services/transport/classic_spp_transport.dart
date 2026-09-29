import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../core/utils/system_settings.dart';
import '../../models/bluetooth_models.dart';
import 'motor_transport.dart';

/// Bluetooth Clásico SPP (Android) — compatible con el firmware ESP32 actual
/// (`BluetoothSerial`), igual que el `BluetoothClient` del APK de Kodular.
///
/// La parte nativa está en `android/.../ClassicSppChannel.kt`.
/// En iOS no existe: Apple solo permite SPP a accesorios certificados MFi.
class ClassicSppTransport implements MotorTransport {
  ClassicSppTransport() {
    if (isSupported) {
      _connSub = _connChannel.receiveBroadcastStream().listen(
        _onConnectionEvent,
        onError: (Object _) {},
      );
    }
  }

  static const _methods = MethodChannel('asador/spp');
  static const _adapterChannel = EventChannel('asador/spp/adapter');
  static const _discoveryChannel = EventChannel('asador/spp/discovery');
  static const _connChannel = EventChannel('asador/spp/connection');

  final _link = StreamController<LinkEvent>.broadcast();
  final _incoming = StreamController<Uint8List>.broadcast();
  StreamSubscription<dynamic>? _connSub;
  bool _connected = false;

  late final Stream<AdapterStatus> _adapterStream = _adapterChannel
      .receiveBroadcastStream()
      .map((e) => _parseAdapter(e as String?));

  @override
  TransportKind get kind => TransportKind.classic;

  @override
  bool get isSupported => Platform.isAndroid;

  @override
  bool get isConnected => _connected;

  @override
  Stream<LinkEvent> get linkEvents => _link.stream;

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  // ------------------------------------------------------------- adaptador

  @override
  Stream<AdapterStatus> adapterStatusStream() =>
      isSupported ? _adapterStream : Stream.value(AdapterStatus.unsupported);

  @override
  Future<AdapterStatus> adapterStatus() async {
    if (!isSupported) return AdapterStatus.unsupported;
    final raw = await _methods.invokeMethod<String>('adapterState');
    final status = _parseAdapter(raw);
    if (status == AdapterStatus.on) {
      final granted = await _methods.invokeMethod<bool>('hasPermissions');
      if (granted != true) return AdapterStatus.unauthorized;
    }
    return status;
  }

  @override
  Future<bool> requestPermissions() async {
    if (!isSupported) return false;
    try {
      // Android 12+: BLUETOOTH_SCAN + BLUETOOTH_CONNECT.
      // Android ≤ 11: ubicación (necesaria para el descubrimiento clásico).
      await UniversalBle.requestPermissions(withAndroidFineLocation: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestEnable() async {
    if (!isSupported) return false;
    try {
      return await _methods.invokeMethod<bool>('requestEnable') ?? false;
    } on PlatformException {
      return false;
    }
  }

  // ------------------------------------------------------------ dispositivos

  @override
  Future<List<BtDevice>> knownDevices() async {
    if (!isSupported) return const [];
    final list =
        await _methods.invokeListMethod<dynamic>('bondedDevices') ?? [];
    return list
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => _deviceFromMap(m, bondedDefault: true))
        .toList();
  }

  @override
  Stream<BtDevice> scan({required Duration timeout}) {
    late final StreamController<BtDevice> controller;
    StreamSubscription<dynamic>? sub;
    Timer? timer;
    var finished = false;
    final startedAt = DateTime.now();

    Future<void> finish() async {
      if (finished) return;
      finished = true;
      timer?.cancel();
      await sub?.cancel();
      try {
        await _methods.invokeMethod<void>('cancelDiscovery');
      } catch (_) {}
      if (!controller.isClosed) await controller.close();
    }

    controller = StreamController<BtDevice>(
      onListen: () async {
        sub = _discoveryChannel.receiveBroadcastStream().listen((event) {
          if (event is! Map) return;
          final type = event['type'];
          if (type == 'found') {
            controller.add(_deviceFromMap(event));
          } else if (type == 'finished') {
            // Ignora el "finished" de un descubrimiento anterior cancelado.
            if (DateTime.now().difference(startedAt) >
                const Duration(seconds: 2)) {
              unawaited(finish());
            }
          }
        });
        final ok = await _methods.invokeMethod<bool>('startDiscovery');
        if (ok != true) {
          controller.addError(
            const TransportException(
              'scan_failed',
              'No se pudo iniciar la búsqueda Bluetooth.',
            ),
          );
          await finish();
          return;
        }
        timer = Timer(timeout, () => unawaited(finish()));
      },
      onCancel: finish,
    );
    return controller.stream;
  }

  @override
  Future<void> stopScan() async {
    if (!isSupported) return;
    try {
      await _methods.invokeMethod<void>('cancelDiscovery');
    } catch (_) {}
  }

  // -------------------------------------------------------------- conexión

  @override
  Future<void> connect(BtDevice device, {required Duration timeout}) async {
    try {
      await _methods.invokeMethod<bool>('connect', {
        'address': device.id,
        'timeoutMs': timeout.inMilliseconds,
      });
      _connected = true;
    } on PlatformException catch (e) {
      throw TransportException(e.code, _friendly(e.code));
    }
  }

  @override
  Future<void> disconnect() async {
    if (!isSupported) return;
    await _methods.invokeMethod<void>('disconnect');
  }

  @override
  Future<void> write(Uint8List bytes) async {
    try {
      await _methods.invokeMethod<void>('write', {'bytes': bytes});
    } on PlatformException catch (e) {
      throw TransportException(e.code, _friendly(e.code));
    }
  }

  void _onConnectionEvent(dynamic event) {
    if (event is! Map) return;
    switch (event['type']) {
      case 'state':
        final connected = event['connected'] == true;
        _connected = connected;
        final reason = event['reason'] as String?;
        _link.add(
          LinkEvent(
            connected: connected,
            byUser: reason == 'user',
            reason: reason,
          ),
        );
      case 'data':
        final bytes = event['bytes'];
        if (bytes is Uint8List) _incoming.add(bytes);
    }
  }

  @override
  Future<void> openSystemSettings() => SystemSettings.openBluetooth();

  @override
  Future<void> dispose() async {
    await _connSub?.cancel();
    await _link.close();
    await _incoming.close();
  }

  // ---------------------------------------------------------------- helpers

  static AdapterStatus _parseAdapter(String? raw) => switch (raw) {
    'on' => AdapterStatus.on,
    'off' => AdapterStatus.off,
    'turningOn' => AdapterStatus.turningOn,
    'turningOff' => AdapterStatus.off,
    'unsupported' => AdapterStatus.unsupported,
    _ => AdapterStatus.unknown,
  };

  static BtDevice _deviceFromMap(
    Map<dynamic, dynamic> m, {
    bool bondedDefault = false,
  }) {
    return BtDevice(
      id: (m['address'] as String?) ?? '',
      name: m['name'] as String?,
      kind: TransportKind.classic,
      rssi: m['rssi'] as int?,
      bonded: (m['bonded'] as bool?) ?? bondedDefault,
    );
  }

  static String _friendly(String code) => switch (code) {
    'bluetooth_off' => 'Bluetooth está apagado.',
    'permission' => 'Falta el permiso de Bluetooth. Concédelo en Ajustes.',
    'connect_failed' =>
      'No se pudo conectar. Verifica que el asador esté encendido y cerca.',
    'not_connected' => 'El asador no está conectado.',
    'io_error' => 'Se perdió la comunicación con el asador.',
    'invalid_address' => 'Dispositivo no válido.',
    'unsupported' => 'Este teléfono no tiene Bluetooth.',
    _ => 'Error de Bluetooth ($code).',
  };
}
