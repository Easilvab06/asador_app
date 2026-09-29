import 'dart:async';
import 'dart:typed_data';

import '../../models/bluetooth_models.dart';

/// Evento de cambio de enlace emitido por un transporte.
class LinkEvent {
  const LinkEvent({required this.connected, this.byUser = false, this.reason});

  final bool connected;

  /// true si la desconexión la pidió el usuario (no se reintenta).
  final bool byUser;
  final String? reason;
}

/// Contrato común para Bluetooth Clásico (SPP) y BLE.
///
/// El resto de la app (controladores, UI, protocolo) NO sabe qué tecnología
/// hay debajo: solo envía bytes. Así, migrar el ESP32 de SPP a BLE no exige
/// tocar la lógica del motor.
abstract class MotorTransport {
  TransportKind get kind;

  /// false si la plataforma no admite esta tecnología (SPP en iOS).
  bool get isSupported;

  Stream<AdapterStatus> adapterStatusStream();
  Future<AdapterStatus> adapterStatus();

  /// Solicita permisos en tiempo de ejecución. Devuelve true si se conceden.
  Future<bool> requestPermissions();

  /// Android: diálogo del sistema para activar Bluetooth.
  /// iOS: siempre false (Apple no lo permite) → la UI guía al usuario.
  Future<bool> requestEnable();

  /// Dispositivos ya conocidos (emparejados en SPP). BLE: lista vacía.
  Future<List<BtDevice>> knownDevices();

  /// Búsqueda activa. El stream se cierra al terminar o al cancelar.
  Stream<BtDevice> scan({required Duration timeout});

  Future<void> stopScan();

  Future<void> connect(BtDevice device, {required Duration timeout});

  Future<void> disconnect();

  bool get isConnected;

  Stream<LinkEvent> get linkEvents;

  /// Escritura serializada de bytes crudos hacia el ESP32.
  Future<void> write(Uint8List bytes);

  /// Datos recibidos (el firmware original no envía nada; preparado para STATUS).
  Stream<Uint8List> get incoming;

  /// Abre los ajustes de Bluetooth del sistema (Android) o de la app (iOS).
  Future<void> openSystemSettings();

  Future<void> dispose();
}
