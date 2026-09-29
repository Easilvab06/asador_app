import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Apertura de ajustes del sistema respetando las reglas de cada plataforma.
class SystemSettings {
  SystemSettings._();

  static const _android = MethodChannel('asador/spp');

  /// Android → Ajustes › Bluetooth.
  /// iOS → Ajustes › (esta app). Apple no permite enlazar directamente a la
  /// pantalla de Bluetooth; desde ahí el usuario ve el permiso Bluetooth y
  /// puede volver atrás a Ajustes › Bluetooth o usar el Centro de control.
  static Future<void> openBluetooth() async {
    if (Platform.isAndroid) {
      try {
        await _android.invokeMethod<void>('openBluetoothSettings');
      } on PlatformException {
        // Sin acción: la UI ya muestra instrucciones.
      }
      return;
    }
    await openApp();
  }

  static Future<void> openApp() async {
    final uri = Uri.parse('app-settings:');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}
