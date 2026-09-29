import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/system_settings.dart';
import '../../models/bluetooth_models.dart';
import 'motor_transport.dart';

/// Bluetooth Low Energy (Android + iOS) sobre `universal_ble` (BSD-3).
///
///   BLE Device ─► Service 6E400001 (NUS) ─► RX 6E400002 (Write) ─► ESP32
///                                       └─► TX 6E400003 (Notify) ◄─ ESP32
///
/// Los BYTES enviados son exactamente los mismos que en SPP ("0","1","4".."8"),
/// de modo que el firmware BLE solo cambia la capa de radio, no la lógica.
class BleTransport implements MotorTransport {
  final _link = StreamController<LinkEvent>.broadcast();
  final _incoming = StreamController<Uint8List>.broadcast();

  String? _deviceId;
  bool _connected = false;
  bool _userDisconnect = false;
  StreamSubscription<bool>? _connSub;
  StreamSubscription<Uint8List>? _valueSub;

  @override
  TransportKind get kind => TransportKind.ble;

  @override
  bool get isSupported => Platform.isAndroid || Platform.isIOS;

  @override
  bool get isConnected => _connected;

  @override
  Stream<LinkEvent> get linkEvents => _link.stream;

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  // ------------------------------------------------------------- adaptador

  @override
  Stream<AdapterStatus> adapterStatusStream() =>
      UniversalBle.availabilityStream.map(_mapAvailability);

  @override
  Future<AdapterStatus> adapterStatus() async {
    final state = await UniversalBle.getBluetoothAvailabilityState();
    final status = _mapAvailability(state);
    if (status == AdapterStatus.on && Platform.isAndroid) {
      final ok = await UniversalBle.hasPermissions(withAndroidFineLocation: false);
      if (!ok) return AdapterStatus.unauthorized;
    }
    return status;
  }

  @override
  Future<bool> requestPermissions() async {
    try {
      // iOS: el diálogo de permiso lo lanza CoreBluetooth la primera vez.
      await UniversalBle.requestPermissions(withAndroidFineLocation: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestEnable() async {
    // Apple NO permite activar Bluetooth desde una app.
    if (!Platform.isAndroid) return false;
    try {
      return await UniversalBle.enableBluetooth();
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------ dispositivos

  @override
  Future<List<BtDevice>> knownDevices() async => const [];

  @override
  Stream<BtDevice> scan({required Duration timeout}) {
    late final StreamController<BtDevice> controller;
    StreamSubscription<BleDevice>? sub;
    Timer? timer;
    var finished = false;

    Future<void> finish() async {
      if (finished) return;
      finished = true;
      timer?.cancel();
      await sub?.cancel();
      try {
        await UniversalBle.stopScan();
      } catch (_) {}
      if (!controller.isClosed) await controller.close();
    }

    controller = StreamController<BtDevice>(
      onListen: () async {
        sub = UniversalBle.scanStream.listen((d) {
          controller.add(BtDevice(
            id: d.deviceId,
            name: d.name,
            kind: TransportKind.ble,
            rssi: d.rssi,
            // Marca como "asador" si anuncia el servicio NUS.
            bonded: d.services
                .map((s) => s.toLowerCase())
                .contains(AppConstants.bleServiceUuid),
          ));
        });
        try {
          await UniversalBle.startScan();
        } catch (e) {
          controller.addError(const TransportException(
              'scan_failed', 'No se pudo iniciar la búsqueda BLE.'));
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
    try {
      await UniversalBle.stopScan();
    } catch (_) {}
  }

  // -------------------------------------------------------------- conexión

  @override
  Future<void> connect(BtDevice device, {required Duration timeout}) async {
    await _teardown();
    _deviceId = device.id;
    _userDisconnect = false;

    try {
      await UniversalBle.connect(device.id, timeout: timeout);
      final services = await UniversalBle.discoverServices(device.id);

      final service = services.where(
        (s) => s.uuid.toLowerCase() == AppConstants.bleServiceUuid,
      );
      if (service.isEmpty) {
        await UniversalBle.disconnect(device.id);
        throw const TransportException(
          'service_missing',
          'Este dispositivo no tiene el servicio del asador. '
              '¿Está cargado el firmware BLE?',
        );
      }

      // TX (notify) es opcional: el firmware actual no envía estado.
      try {
        await UniversalBle.subscribeNotifications(
          device.id,
          AppConstants.bleServiceUuid,
          AppConstants.bleTxCharUuid,
        );
        _valueSub = UniversalBle.characteristicValueStream(
          device.id,
          AppConstants.bleTxCharUuid,
        ).listen(_incoming.add);
      } catch (_) {}

      _connSub = UniversalBle.connectionStream(device.id).listen((connected) {
        if (connected == _connected) return;
        _connected = connected;
        _link.add(LinkEvent(
          connected: connected,
          byUser: !connected && _userDisconnect,
          reason: connected ? 'connected' : (_userDisconnect ? 'user' : 'lost'),
        ));
      });

      _connected = true;
      _link.add(const LinkEvent(connected: true, reason: 'connected'));
    } on TransportException {
      rethrow;
    } catch (e) {
      throw const TransportException(
        'connect_failed',
        'No se pudo conectar. Verifica que el asador esté encendido y cerca.',
      );
    }
  }

  @override
  Future<void> disconnect() async {
    final id = _deviceId;
    if (id == null) return;
    _userDisconnect = true;
    try {
      await UniversalBle.disconnect(id);
    } catch (_) {}
    if (_connected) {
      _connected = false;
      _link.add(const LinkEvent(connected: false, byUser: true, reason: 'user'));
    }
    await _teardown();
  }

  @override
  Future<void> write(Uint8List bytes) async {
    final id = _deviceId;
    if (id == null || !_connected) {
      throw const TransportException('not_connected', 'El asador no está conectado.');
    }
    try {
      // Con respuesta: confirma que el ESP32 recibió el comando.
      await UniversalBle.write(
        id,
        AppConstants.bleServiceUuid,
        AppConstants.bleRxCharUuid,
        bytes,
      );
    } catch (_) {
      throw const TransportException('io_error', 'Se perdió la comunicación con el asador.');
    }
  }

  Future<void> _teardown() async {
    await _connSub?.cancel();
    await _valueSub?.cancel();
    _connSub = null;
    _valueSub = null;
  }

  @override
  Future<void> openSystemSettings() => SystemSettings.openBluetooth();

  @override
  Future<void> dispose() async {
    await _teardown();
    await _link.close();
    await _incoming.close();
  }

  static AdapterStatus _mapAvailability(AvailabilityState s) => switch (s) {
        AvailabilityState.poweredOn => AdapterStatus.on,
        AvailabilityState.poweredOff => AdapterStatus.off,
        AvailabilityState.unauthorized => AdapterStatus.unauthorized,
        AvailabilityState.unsupported => AdapterStatus.unsupported,
        AvailabilityState.resetting => AdapterStatus.turningOn,
        AvailabilityState.unknown => AdapterStatus.unknown,
      };
}
