package com.kanka.asador

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Registra el canal nativo de Bluetooth Clásico (SPP).
 *
 * El APK original (Kodular) usaba el componente BluetoothClient, que por debajo es
 * exactamente esto: un BluetoothSocket RFCOMM contra el UUID SPP 00001101-...
 * Mantenerlo en Android garantiza compatibilidad con el firmware ESP32 actual
 * (BluetoothSerial) sin tocarlo.
 */
class MainActivity : FlutterActivity() {

    private var spp: ClassicSppChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        spp = ClassicSppChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        spp?.onActivityResult(requestCode, resultCode)
    }

    override fun onDestroy() {
        spp?.dispose()
        spp = null
        super.onDestroy()
    }
}
