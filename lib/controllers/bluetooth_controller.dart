import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../models/bluetooth_models.dart';
import '../services/transport/motor_transport.dart';
import 'providers.dart';

class BluetoothState {
  const BluetoothState({
    required this.transport,
    this.adapter = AdapterStatus.unknown,
    this.link = LinkStatus.disconnected,
    this.device,
    this.lastDevice,
    this.scanning = false,
    this.devices = const [],
    this.error,
    this.reconnectAttempt = 0,
  });

  final TransportKind transport;
  final AdapterStatus adapter;
  final LinkStatus link;

  /// Dispositivo conectado / en conexión.
  final BtDevice? device;

  /// Último asador usado (reconexión rápida desde el inicio).
  final BtDevice? lastDevice;
  final bool scanning;
  final List<BtDevice> devices;
  final String? error;
  final int reconnectAttempt;

  bool get isConnected => link == LinkStatus.connected;

  BluetoothState copyWith({
    TransportKind? transport,
    AdapterStatus? adapter,
    LinkStatus? link,
    BtDevice? device,
    bool clearDevice = false,
    BtDevice? lastDevice,
    bool? scanning,
    List<BtDevice>? devices,
    String? error,
    bool clearError = false,
    int? reconnectAttempt,
  }) {
    return BluetoothState(
      transport: transport ?? this.transport,
      adapter: adapter ?? this.adapter,
      link: link ?? this.link,
      device: clearDevice ? null : (device ?? this.device),
      lastDevice: lastDevice ?? this.lastDevice,
      scanning: scanning ?? this.scanning,
      devices: devices ?? this.devices,
      error: clearError ? null : (error ?? this.error),
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
    );
  }
}

final bluetoothControllerProvider =
    NotifierProvider<BluetoothController, BluetoothState>(BluetoothController.new);

/// Adaptador · permisos · escaneo · conexión · detección de caída · reconexión.
class BluetoothController extends Notifier<BluetoothState> {
  StreamSubscription<AdapterStatus>? _adapterSub;
  final List<StreamSubscription<LinkEvent>> _linkSubs = [];
  StreamSubscription<BtDevice>? _scanSub;
  bool _reconnecting = false;
  bool _disposed = false;

  MotorTransport get transport => ref.read(transportsProvider)[state.transport]!;

  /// SPP solo existe en Android. En iOS la app es BLE obligatoriamente.
  bool get canChooseTransport => Platform.isAndroid;

  @override
  BluetoothState build() {
    _disposed = false;
    final transports = ref.read(transportsProvider);
    for (final t in transports.values) {
      if (!t.isSupported) continue;
      _linkSubs.add(t.linkEvents.listen((e) => _onLink(t.kind, e)));
    }
    ref.onDispose(() {
      _disposed = true;
      _adapterSub?.cancel();
      _scanSub?.cancel();
      for (final s in _linkSubs) {
        s.cancel();
      }
      _linkSubs.clear();
    });

    // Android: Clásico por defecto (compatible con el ESP32 actual).
    // iOS: solo BLE.
    final initial = Platform.isIOS ? TransportKind.ble : TransportKind.classic;
    Future.microtask(() => _init(initial));
    return BluetoothState(transport: initial);
  }

  Future<void> _init(TransportKind fallback) async {
    final repo = ref.read(settingsRepositoryProvider);
    var kind = await repo.loadTransport() ?? fallback;
    if (kind == TransportKind.classic && !Platform.isAndroid) kind = TransportKind.ble;
    final last = await repo.loadLastDevice(kind);
    if (_disposed) return;
    state = state.copyWith(transport: kind, lastDevice: last);
    _watchAdapter();
    await refreshAdapter();
  }

  void _watchAdapter() {
    _adapterSub?.cancel();
    _adapterSub = transport.adapterStatusStream().listen(_onAdapter, onError: (_) {});
  }

  // --------------------------------------------------------------- adaptador

  Future<void> refreshAdapter() async {
    try {
      final status = await transport.adapterStatus();
      if (!_disposed) _onAdapter(status);
    } catch (_) {
      if (!_disposed) state = state.copyWith(adapter: AdapterStatus.unknown);
    }
  }

  void _onAdapter(AdapterStatus status) {
    final wasReady = state.adapter.isReady;
    state = state.copyWith(adapter: status);

    // (1) El usuario apaga Bluetooth → el enlace muere; no se reintenta.
    if (wasReady && !status.isReady &&
        (state.link == LinkStatus.connected || state.link == LinkStatus.reconnecting)) {
      _reconnecting = false;
      state = state.copyWith(
        link: LinkStatus.disconnected,
        error: 'Bluetooth se apagó. El asador quedó desconectado.',
      );
    }
    if (status.isReady && !wasReady) {
      // Al volver a encenderse, se revalidan permisos.
      unawaited(refreshAdapterPermissionsOnly());
    }
  }

  Future<void> refreshAdapterPermissionsOnly() async {
    try {
      final s = await transport.adapterStatus();
      if (!_disposed && s != state.adapter) state = state.copyWith(adapter: s);
    } catch (_) {}
  }

  /// Permisos + encendido. Devuelve true si el adaptador queda listo.
  Future<bool> ensureReady() async {
    var status = await transport.adapterStatus();

    if (status == AdapterStatus.unauthorized || status == AdapterStatus.unknown) {
      await transport.requestPermissions();
      status = await transport.adapterStatus();
    }
    if (status == AdapterStatus.off) {
      // Android: diálogo del sistema. iOS: devuelve false → la UI guía.
      final enabled = await transport.requestEnable();
      if (enabled) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        status = await transport.adapterStatus();
        if (status == AdapterStatus.unauthorized) {
          await transport.requestPermissions();
          status = await transport.adapterStatus();
        }
      }
    }
    if (!_disposed) state = state.copyWith(adapter: status);
    return status.isReady;
  }

  Future<bool> requestEnable() async {
    final ok = await transport.requestEnable();
    await refreshAdapter();
    return ok;
  }

  Future<void> openSystemSettings() => transport.openSystemSettings();

  Future<void> setTransport(TransportKind kind) async {
    if (kind == state.transport || state.link != LinkStatus.disconnected) return;
    if (kind == TransportKind.classic && !Platform.isAndroid) return;
    await stopScan();
    final repo = ref.read(settingsRepositoryProvider);
    await repo.saveTransport(kind);
    final last = await repo.loadLastDevice(kind);
    state = BluetoothState(transport: kind, lastDevice: last);
    _watchAdapter();
    await refreshAdapter();
  }

  // --------------------------------------------------------------- escaneo

  Future<void> startScan() async {
    if (state.scanning) return;
    state = state.copyWith(clearError: true);
    if (!await ensureReady()) return;

    List<BtDevice> known = const [];
    try {
      known = await transport.knownDevices();
    } catch (_) {}
    state = state.copyWith(scanning: true, devices: _sorted(known));

    await _scanSub?.cancel();
    _scanSub = transport.scan(timeout: AppConstants.scanTimeout).listen(
      _mergeDevice,
      onError: (Object e) {
        state = state.copyWith(
          error: e is TransportException ? e.message : 'Error durante la búsqueda.',
        );
      },
      onDone: () {
        if (!_disposed) state = state.copyWith(scanning: false);
      },
    );
  }

  void _mergeDevice(BtDevice d) {
    if (d.id.isEmpty) return;
    final list = [...state.devices];
    final i = list.indexOf(d);
    if (i >= 0) {
      final old = list[i];
      list[i] = old.copyWith(rssi: d.rssi, name: d.name ?? old.name, bonded: old.bonded || d.bonded);
    } else {
      list.add(d);
    }
    state = state.copyWith(devices: _sorted(list));
  }

  List<BtDevice> _sorted(List<BtDevice> list) {
    final l = [...list];
    int score(BtDevice d) =>
        (d.looksLikeAsador ? 1000 : 0) + (d.bonded ? 200 : 0) + (d.name != null ? 100 : 0) + (d.rssi ?? -120);
    l.sort((a, b) => score(b).compareTo(score(a)));
    return l;
  }

  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    await transport.stopScan();
    if (!_disposed && state.scanning) state = state.copyWith(scanning: false);
  }

  // -------------------------------------------------------------- conexión

  Future<bool> connect(BtDevice device) async {
    if (state.link.isBusy) return false;
    await stopScan();
    if (!await ensureReady()) return false;

    _reconnecting = false;
    state = state.copyWith(
      link: LinkStatus.connecting,
      device: device,
      clearError: true,
      reconnectAttempt: 0,
    );
    try {
      await transport.connect(device, timeout: AppConstants.connectTimeout);
      await ref.read(settingsRepositoryProvider).saveLastDevice(device);
      state = state.copyWith(link: LinkStatus.connected, lastDevice: device);
      return true;
    } on TransportException catch (e) {
      state = state.copyWith(link: LinkStatus.error, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(link: LinkStatus.error, error: 'No se pudo conectar.');
      return false;
    }
  }

  Future<void> disconnect() async {
    _reconnecting = false;
    try {
      await transport.disconnect();
    } catch (_) {}
    state = state.copyWith(link: LinkStatus.disconnected, clearError: true);
  }

  void clearError() => state = state.copyWith(clearError: true);

  void _onLink(TransportKind kind, LinkEvent e) {
    if (_disposed || kind != state.transport) return;
    if (e.connected) {
      if (state.link != LinkStatus.connecting) {
        state = state.copyWith(link: LinkStatus.connected, reconnectAttempt: 0);
      }
      return;
    }
    // Desconexión.
    if (e.byUser || state.link == LinkStatus.connecting) return;
    if (state.link == LinkStatus.connected) {
      // (3)(4) Pérdida de señal o ESP32 apagado → reconexión automática.
      unawaited(_reconnectLoop());
    }
  }

  Future<void> _reconnectLoop() async {
    final device = state.device;
    if (device == null || _reconnecting) return;
    _reconnecting = true;

    for (var attempt = 1; attempt <= AppConstants.reconnectAttempts; attempt++) {
      if (!_reconnecting || _disposed) return;
      if (!state.adapter.isReady) break;
      state = state.copyWith(link: LinkStatus.reconnecting, reconnectAttempt: attempt);
      await Future<void>.delayed(AppConstants.reconnectBaseDelay * attempt);
      if (!_reconnecting || _disposed) return;
      try {
        await transport.connect(device, timeout: AppConstants.connectTimeout);
        _reconnecting = false;
        state = state.copyWith(link: LinkStatus.connected, reconnectAttempt: 0, clearError: true);
        return;
      } catch (_) {
        // siguiente intento
      }
    }
    _reconnecting = false;
    if (_disposed) return;
    state = state.copyWith(
      link: LinkStatus.disconnected,
      reconnectAttempt: 0,
      error: state.adapter.isReady
          ? 'Se perdió la conexión con el asador.'
          : 'Bluetooth se apagó. El asador quedó desconectado.',
    );
  }
}
