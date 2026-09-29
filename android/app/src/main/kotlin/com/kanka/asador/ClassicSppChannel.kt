package com.kanka.asador

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.Timer
import java.util.TimerTask
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Bluetooth Clásico SPP (RFCOMM) — equivalente directo del componente
 * `BluetoothClient` de App Inventor/Kodular usado por el APK original.
 *
 * Canales:
 *   MethodChannel  asador/spp             → comandos
 *   EventChannel   asador/spp/adapter     → "off" | "turningOn" | "on" | "turningOff" | "unsupported"
 *   EventChannel   asador/spp/discovery   → {type:"found",...} | {type:"finished"}
 *   EventChannel   asador/spp/connection  → {type:"state",connected,reason} | {type:"data",bytes}
 *
 * Todas las operaciones de socket (connect / write) se serializan en un único hilo,
 * lo que evita comandos simultáneos hacia el ESP32.
 */
@SuppressLint("MissingPermission")
class ClassicSppChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "AsadorSPP"
        private const val REQUEST_ENABLE_BT = 0x0B7
        /** UUID estándar Serial Port Profile (el mismo que usa BluetoothClient de Kodular). */
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }

    private val main = Handler(Looper.getMainLooper())
    private val io: ExecutorService = Executors.newSingleThreadExecutor()

    private val methods = MethodChannel(messenger, "asador/spp")
    private val adapterChannel = EventChannel(messenger, "asador/spp/adapter")
    private val discoveryChannel = EventChannel(messenger, "asador/spp/discovery")
    private val connectionChannel = EventChannel(messenger, "asador/spp/connection")

    private var adapterSink: EventChannel.EventSink? = null
    private var discoverySink: EventChannel.EventSink? = null
    private var connectionSink: EventChannel.EventSink? = null

    private var pendingEnable: MethodChannel.Result? = null

    @Volatile private var socket: BluetoothSocket? = null
    @Volatile private var connectedAddress: String? = null
    @Volatile private var closingByUser = false

    private val adapter: BluetoothAdapter?
        get() = (activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    // ---------------------------------------------------------------- receivers

    private val adapterReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val state = intent?.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
                ?: return
            adapterSink?.success(mapAdapterState(state))
        }
    }

    private val discoveryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                BluetoothDevice.ACTION_FOUND -> {
                    @Suppress("DEPRECATION")
                    val device: BluetoothDevice =
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE) ?: return
                    val rssi = intent.getShortExtra(BluetoothDevice.EXTRA_RSSI, Short.MIN_VALUE)
                    discoverySink?.success(
                        deviceToMap(device) + mapOf(
                            "type" to "found",
                            "rssi" to if (rssi == Short.MIN_VALUE) null else rssi.toInt(),
                        ),
                    )
                }
                BluetoothAdapter.ACTION_DISCOVERY_FINISHED ->
                    discoverySink?.success(mapOf("type" to "finished"))
            }
        }
    }

    /** Detecta la caída del enlace ACL antes que el timeout del socket (ESP32 apagado, fuera de rango). */
    private val aclReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != BluetoothDevice.ACTION_ACL_DISCONNECTED) return
            @Suppress("DEPRECATION")
            val device: BluetoothDevice = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE) ?: return
            val current = socket ?: return
            if (device.address.equals(connectedAddress, ignoreCase = true)) {
                onSocketLost(current, "acl_disconnected")
            }
        }
    }

    init {
        methods.setMethodCallHandler(this)

        adapterChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                adapterSink = events
                register(adapterReceiver, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED))
                events?.success(currentAdapterState())
            }

            override fun onCancel(arguments: Any?) {
                unregister(adapterReceiver)
                adapterSink = null
            }
        })

        discoveryChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                discoverySink = events
                val filter = IntentFilter().apply {
                    addAction(BluetoothDevice.ACTION_FOUND)
                    addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
                }
                register(discoveryReceiver, filter)
            }

            override fun onCancel(arguments: Any?) {
                unregister(discoveryReceiver)
                discoverySink = null
            }
        })

        connectionChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                connectionSink = events
            }

            override fun onCancel(arguments: Any?) {
                connectionSink = null
            }
        })

        register(aclReceiver, IntentFilter(BluetoothDevice.ACTION_ACL_DISCONNECTED))
    }

    // ------------------------------------------------------------------ methods

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "adapterState" -> result.success(currentAdapterState())
                "hasPermissions" -> result.success(hasPermissions())
                "requestEnable" -> requestEnable(result)
                "bondedDevices" -> {
                    val a = adapter ?: return result.success(emptyList<Any>())
                    result.success(a.bondedDevices?.map { deviceToMap(it) } ?: emptyList<Any>())
                }
                "startDiscovery" -> {
                    val a = adapter ?: return result.success(false)
                    if (a.isDiscovering) a.cancelDiscovery()
                    result.success(a.startDiscovery())
                }
                "cancelDiscovery" -> {
                    adapter?.cancelDiscovery()
                    result.success(null)
                }
                "connect" -> {
                    val address = call.argument<String>("address")
                        ?: return result.error("invalid_argument", "address requerido", null)
                    val timeoutMs = call.argument<Number>("timeoutMs")?.toLong() ?: 12000L
                    io.execute {
                        val error = doConnect(address, timeoutMs)
                        main.post {
                            if (error == null) result.success(true)
                            else result.error(error.first, error.second, null)
                        }
                    }
                }
                "write" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                        ?: return result.error("invalid_argument", "bytes requerido", null)
                    io.execute {
                        val error = doWrite(bytes)
                        main.post {
                            if (error == null) result.success(null)
                            else result.error(error, "No se pudo escribir en el socket", null)
                        }
                    }
                }
                "disconnect" -> {
                    closeSocket(byUser = true)
                    result.success(null)
                }
                "isConnected" -> result.success(socket?.isConnected == true)
                "openBluetoothSettings" -> {
                    activity.startActivity(
                        Intent(Settings.ACTION_BLUETOOTH_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: SecurityException) {
            result.error("permission", e.message, null)
        } catch (e: Exception) {
            result.error("error", e.message, null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int) {
        if (requestCode != REQUEST_ENABLE_BT) return
        val pending = pendingEnable ?: return
        pendingEnable = null
        pending.success(resultCode == Activity.RESULT_OK)
    }

    private fun requestEnable(result: MethodChannel.Result) {
        val a = adapter ?: return result.success(false)
        if (a.isEnabled) return result.success(true)
        if (pendingEnable != null) return result.error("busy", "Solicitud ya en curso", null)
        pendingEnable = result
        try {
            // Android muestra su diálogo del sistema "¿Permitir activar Bluetooth?".
            activity.startActivityForResult(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), REQUEST_ENABLE_BT)
        } catch (e: Exception) {
            pendingEnable = null
            result.error("enable_failed", e.message, null)
        }
    }

    // ------------------------------------------------------------------- socket

    /** Devuelve null si conecta, o (código, mensaje) si falla. Corre en el hilo `io`. */
    private fun doConnect(address: String, timeoutMs: Long): Pair<String, String>? {
        val a = adapter ?: return "unsupported" to "Bluetooth no disponible"
        if (!a.isEnabled) return "bluetooth_off" to "Bluetooth apagado"
        closeSocket(byUser = true)
        try {
            a.cancelDiscovery() // Un inquiry activo ralentiza o rompe la conexión RFCOMM.
        } catch (ignored: SecurityException) {
        }

        val device = try {
            a.getRemoteDevice(address)
        } catch (e: IllegalArgumentException) {
            return "invalid_address" to "Dirección inválida"
        }

        // 1) Seguro (igual que Kodular por defecto)  2) Inseguro  3) Canal RFCOMM 1 (sin SDP).
        val attempts: List<() -> BluetoothSocket> = listOf(
            { device.createRfcommSocketToServiceRecord(SPP_UUID) },
            { device.createInsecureRfcommSocketToServiceRecord(SPP_UUID) },
            {
                device.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
                    .invoke(device, 1) as BluetoothSocket
            },
        )

        var last: Exception? = null
        for (make in attempts) {
            var s: BluetoothSocket? = null
            val watchdog = Timer("spp-connect-timeout", true)
            try {
                val created = make()
                s = created
                // BluetoothSocket.connect() no admite timeout: se cierra el socket si se excede.
                watchdog.schedule(object : TimerTask() {
                    override fun run() {
                        try { created.close() } catch (ignored: IOException) {}
                    }
                }, timeoutMs)
                created.connect()
                watchdog.cancel()
                socket = created
                connectedAddress = address
                closingByUser = false
                startReader(created)
                emitConnection(mapOf("type" to "state", "connected" to true, "reason" to "connected"))
                return null
            } catch (e: SecurityException) {
                watchdog.cancel()
                try { s?.close() } catch (ignored: IOException) {}
                return "permission" to (e.message ?: "Permiso BLUETOOTH_CONNECT denegado")
            } catch (e: Exception) {
                watchdog.cancel()
                last = e
                Log.w(TAG, "Intento de conexión fallido: ${e.message}")
                try { s?.close() } catch (ignored: IOException) {}
            }
        }
        return "connect_failed" to (last?.message ?: "No se pudo conectar")
    }

    private fun doWrite(bytes: ByteArray): String? {
        val s = socket ?: return "not_connected"
        return try {
            val out = s.outputStream
            out.write(bytes)
            out.flush()
            null
        } catch (e: IOException) {
            onSocketLost(s, "write_failed")
            "io_error"
        }
    }

    private fun startReader(s: BluetoothSocket) {
        val t = Thread {
            val buffer = ByteArray(256)
            var reason = "closed"
            try {
                val input = s.inputStream
                while (true) {
                    val n = input.read(buffer)
                    if (n < 0) {
                        reason = "eof"
                        break
                    }
                    if (n > 0) emitConnection(mapOf("type" to "data", "bytes" to buffer.copyOf(n)))
                }
            } catch (e: IOException) {
                reason = "io_error"
            }
            onSocketLost(s, reason)
        }
        t.isDaemon = true
        t.name = "asador-spp-reader"
        t.start()
    }

    private fun onSocketLost(s: BluetoothSocket, reason: String) {
        synchronized(this) {
            if (socket !== s) return
            socket = null
            connectedAddress = null
        }
        try { s.close() } catch (ignored: IOException) {}
        val byUser = closingByUser
        closingByUser = false
        emitConnection(
            mapOf("type" to "state", "connected" to false, "reason" to if (byUser) "user" else reason),
        )
    }

    private fun closeSocket(byUser: Boolean) {
        val s = socket ?: return
        closingByUser = byUser
        // Cerrar el socket desbloquea read() en el hilo lector → onSocketLost() emite el evento.
        try { s.close() } catch (ignored: IOException) {}
        onSocketLost(s, "user")
    }

    // ------------------------------------------------------------------ helpers

    private fun currentAdapterState(): String {
        val a = adapter ?: return "unsupported"
        return mapAdapterState(a.state)
    }

    private fun mapAdapterState(state: Int): String = when (state) {
        BluetoothAdapter.STATE_ON -> "on"
        BluetoothAdapter.STATE_TURNING_ON -> "turningOn"
        BluetoothAdapter.STATE_TURNING_OFF -> "turningOff"
        else -> "off"
    }

    private fun hasPermissions(): Boolean {
        fun granted(p: String) =
            activity.checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            granted(Manifest.permission.BLUETOOTH_CONNECT) && granted(Manifest.permission.BLUETOOTH_SCAN)
        } else {
            true // En Android ≤ 11 BLUETOOTH/BLUETOOTH_ADMIN son permisos normales.
        }
    }

    private fun deviceToMap(d: BluetoothDevice): Map<String, Any?> = mapOf(
        "address" to d.address,
        "name" to (try { d.name } catch (ignored: SecurityException) { null }),
        "bonded" to (try { d.bondState == BluetoothDevice.BOND_BONDED } catch (ignored: SecurityException) { false }),
    )

    private fun emitConnection(event: Map<String, Any?>) {
        main.post { connectionSink?.success(event) }
    }

    private fun register(receiver: BroadcastReceiver, filter: IntentFilter) {
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                activity.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                activity.registerReceiver(receiver, filter)
            }
        } catch (e: Exception) {
            Log.w(TAG, "registerReceiver: ${e.message}")
        }
    }

    private fun unregister(receiver: BroadcastReceiver) {
        try {
            activity.unregisterReceiver(receiver)
        } catch (ignored: IllegalArgumentException) {
        }
    }

    fun dispose() {
        closeSocket(byUser = true)
        unregister(adapterReceiver)
        unregister(discoveryReceiver)
        unregister(aclReceiver)
        methods.setMethodCallHandler(null)
        adapterChannel.setStreamHandler(null)
        discoveryChannel.setStreamHandler(null)
        connectionChannel.setStreamHandler(null)
        pendingEnable?.success(false)
        pendingEnable = null
        io.shutdownNow()
    }
}
