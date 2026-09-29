# Asador · App de control Bluetooth (Flutter)

Reconstrucción profesional de `Kanka_2_copy.apk` (Kodular) en **Flutter + Dart** para **Android e iOS**, con arquitectura por capas, Riverpod, UI oscura de nivel comercial y un protocolo **100 % compatible** con el ESP32 actual.

---

## 1. Análisis del APK original

El APK se decompiló con `jadx` (clases `io.kodular.wilson_silva01.Kanka_2_copy.Screen1/Screen2`, generadas desde los `.yail` de Kodular).

### Pantallas
| Pantalla | Contenido | Lógica |
|---|---|---|
| `Screen1` | Lottie `23948-welcome`, `45479-fish-or-meat`, imagen `linea1.png`, texto "Kanka" | `Clock1` (4000 ms) → `open another screen "Screen2"` |
| `Screen2` | ListPicker `Ajustes` (icono Bluetooth), `btn_Connect`, `Label_Status`, `Slider1`, Lottie velocidad (decorativo), `Lottie3` (flecha ⇄), `Lottie2` (power), `Notifier1`, texto "by Wilson J. Silva" | Todo el control |

### Bluetooth
- Componente **`BluetoothClient`** de App Inventor ⇒ **Bluetooth Clásico SPP (RFCOMM)**, **no BLE**.
- Sin propiedades modificadas ⇒ valores por defecto: conexión *Secure* (`createRfcommSocketToServiceRecord` con UUID SPP `00001101-…`), texto UTF‑8, **sin delimitador**.
- `Ajustes.BeforePicking` → `Elements = BluetoothClient.AddressesAndNames` ⇒ **solo lista dispositivos ya emparejados** en Ajustes de Android (no hay escaneo).
- `Ajustes.AfterPicking` → `BluetoothClient.Connect(Selection)`.
- `btn_Connect.Click` alterna Connect/Disconnect. Textos: *"Select the Bluetooth"*, *"Charging..."*, *"Bluetooth device is connected"*, *"Bluetooth not connected"*.
- `BluetoothError` → solo un `ShowMessageDialog`. **No hay detección de desconexión, ni reconexión, ni lectura de datos** (`ReceiveText` nunca se usa).

### Protocolo real (extraído, no inventado)
Todos los envíos: `if BluetoothClient.IsConnected then SendText(...)`.

| Control | Evento | Envía |
|---|---|---|
| `Slider1` · Min **4**, Max **8**, Thumb inicial **6** | `PositionChanged` | `format as decimal(thumbPosition, 0)` → `"4"`…`"8"` |
| `Lottie3` · flecha bidireccional | `Click` | `"0"` |
| `Lottie2` · botón power | `Click` | `"1"` |

**Un carácter ASCII por comando, sin `\n`.**

### Lo que **no puede determinarse a partir del APK**
- Si `"0"` **alterna** el sentido o fija uno concreto (se asume toggle).
- Si `"1"` es **STOP** o un toggle encendido/apagado (se asume STOP, como describes).
- El PWM/RPM real de cada nivel 4–8.
- Si, tras `"1"`, enviar un nivel vuelve a arrancar (se asume que sí: así arrancaba el slider).
- El ESP32 no devuelve estado ⇒ **no hay RPM ni estado real** disponible.

Todo esto es **configurable** en la app (Ajustes → Protocolo ESP32) y en `lib/core/constants/protocol_config.dart`.

### Permisos del APK original
`BLUETOOTH`, `BLUETOOTH_ADMIN`, `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` + `INTERNET`, `ACCESS_WIFI_STATE`, `ACCESS_NETWORK_STATE`, `READ_EXTERNAL_STORAGE` (inyectados por Kodular, innecesarios → eliminados).

---

## 2. Clásico vs BLE — la decisión

**iOS no permite Bluetooth Clásico SPP** a apps normales: solo accesorios con certificación **MFi** vía External Accessory. Con el firmware actual es **imposible** controlar el asador desde un iPhone.

Solución implementada: **dos transportes intercambiables** detrás de una misma interfaz (`MotorTransport`):

| Transporte | Plataformas | Firmware | Estado |
|---|---|---|---|
| **Clásico SPP** (canal nativo Kotlin propio) | Android | **El actual, sin cambios** | Listo |
| **BLE** (`universal_ble`) | Android + iOS | `firmware/esp32_asador_ble` | Listo (requiere cargar firmware) |

Los **bytes enviados son idénticos** en ambos (`"0"`, `"1"`, `"4"`…`"8"`). El firmware BLE entregado **mantiene también SPP** ⇒ el mismo asador funciona con la app vieja, la nueva en modo Clásico y la nueva en modo BLE (iPhone incluido).

### Perfil BLE (Nordic UART Service, estándar de facto)
```
ESP32 (GATT server, nombre "ASADOR-ESP32")
└─ Service 6E400001-B5A3-F393-E0A9-E50E24DCCA9E
   ├─ RX 6E400002-…  Write/WriteNoResponse   ← app escribe "0" | "1" | "4".."8"
   └─ TX 6E400003-…  Notify                  → "S,<run>,<nivel>,<C|A>\n" (opcional)
```

### Paquetes evaluados
| Paquete | Veredicto |
|---|---|
| `flutter_blue_plus` | Técnicamente excelente, pero **desde 2025 exige licencia comercial de pago** a cualquier empresa con ánimo de lucro (incluso en desarrollo). Descartado para un producto comercial. |
| **`universal_ble`** 2.x | **Elegido.** BSD‑3, mantenido (Navideck), Android/iOS, escaneo, conexión, servicios, write/read, notify, estado del adaptador, `enableBluetooth` en Android. |
| `flutter_blue_classic` | GPL‑3.0 → incompatible con app comercial cerrada. |
| `flutter_bluetooth_serial` | Abandonado. |
| `bluetooth_spp` | MIT y bueno, pero no publicado en pub.dev. |
| **Canal nativo propio** (`ClassicSppChannel.kt`) | **Elegido para SPP**: sin dependencia de terceros, mismo método de conexión que Kodular (secure → insecure → canal 1). |

---

## 3. Arquitectura

```
lib/
├── main.dart / app.dart               ProviderScope, tema, ciclo de vida (resume/detach)
├── core/
│   ├── constants/
│   │   ├── protocol_config.dart       ★ MotorCommand + ProtocolConfig (comandos del APK)
│   │   └── app_constants.dart         UUIDs BLE, timeouts, reintentos
│   ├── theme/                         paleta y ThemeData
│   └── utils/system_settings.dart     abrir Ajustes (Android BT / iOS app-settings)
├── models/                            BtDevice, AdapterStatus, LinkStatus, MotorState…
├── services/
│   ├── transport/
│   │   ├── motor_transport.dart       interfaz común
│   │   ├── classic_spp_transport.dart SPP → MethodChannel nativo
│   │   └── ble_transport.dart         BLE → universal_ble
│   ├── protocol/command_queue.dart    cola serializada + intervalo mínimo + throttle
│   └── settings_repository.dart       SharedPreferencesAsync
├── controllers/                       Riverpod Notifiers
│   ├── providers.dart                 transportes, config de protocolo
│   ├── bluetooth_controller.dart      adaptador · permisos · escaneo · conexión · reconexión
│   └── motor_controller.dart          velocidad · sentido · start/stop · seguridad
├── screens/  splash · home · device_selection · motor_control · settings
└── widgets/  speed_control · direction_button · stop_button · connection_status
              device_card · rotisserie_animation · radar_scan · connected_overlay …
android/app/src/main/kotlin/com/kanka/asador/
├── MainActivity.kt
└── ClassicSppChannel.kt               RFCOMM, descubrimiento, ACL, activar BT
firmware/esp32_asador_ble/             sketch Arduino SPP + BLE
test/widget_test.dart                  pruebas del protocolo y la cola
```

**Riverpod:** la UI solo hace `ref.watch(...)` del estado y llama métodos de los controladores. Los controladores solo hablan con `MotorTransport` (nunca con plugins). `MotorController` escucha (`ref.listen`) el estado de enlace de `BluetoothController` para bloquear controles y abortar maniobras al perder conexión.

---

## 4. UI/UX

- **Tema oscuro "brasa sobre grafito"**: grafito `#0B0C0F`, un único acento cálido `#F07A3E`, verde/ámbar/rojo solo para estados.
- **Inicio:** marca, estado Bluetooth y del dispositivo con punto pulsante, aviso contextual si BT está apagado/sin permiso, botón **CONECTAR ASADOR** (o reconexión rápida al último).
- **Selección:** hoja inferior con radar animado, tarjetas con nombre, estado, MAC/ID, barras RSSI, filtro "solo asadores", selector Clásico/BLE (Android).
- **Confirmación:** animación de check **"ASADOR CONECTADO"**.
- **Panel:** píldora de conexión, espetón animado con inercia (acelera/frena/invierte), estado Girando/Detenido/Sin confirmar, **velocidad por niveles** (barras ascendentes, %, háptica), **sentido con mantener‑pulsado**, **DETENER MOTOR fijo abajo**, siempre visible.
- **Responsive:** `LayoutBuilder`, anchos máximos, 2 columnas a partir de 760 px (tablets/horizontal), `SafeArea`, sin tamaños fijos que rompan.

---

## 5. Seguridad — qué ocurre en cada caso

| Situación | Comportamiento |
|---|---|
| **1. Usuario apaga Bluetooth** | Se detecta al instante (receptor de estado del adaptador). Enlace → *Desconectado*, controles bloqueados, aviso. No se reintenta. |
| **2. Usuario sale de la app** | La conexión se mantiene (el asador sigue en su estado). Al volver se revalida Bluetooth. Un asador suele girar horas con el teléfono bloqueado: **no** se detiene por salir. |
| **3. Pérdida de señal** | Detección por fin de socket / evento ACL (SPP) o `connectionStream` (BLE). 3 reintentos automáticos (2 s, 4 s, 6 s) con controles bloqueados. Estado del motor → *Sin confirmar*. |
| **4. ESP32 se desconecta/apaga** | Igual que 3. |
| **5. Cierre inesperado de la app** | El SO cierra el socket. Opcional "Detener al cerrar la app" (best effort). **La protección real debe estar en el firmware:** `STOP_ON_DISCONNECT`. |
| **6. Invertir con el motor girando** | Secuencia protegida: **STOP → espera configurable (1,5 s) con barra de progreso → "0" → reanudar nivel**. Requiere mantener pulsado 0,7 s. STOP cancela la maniobra en cualquier momento. |
| Comandos continuos | Solo se envía al cambiar de nivel; throttle 250 ms + intervalo mínimo 150 ms entre comandos. |
| Comandos simultáneos | Cola serializada (Dart) + hilo único de escritura (Kotlin) + mutex en firmware. |
| Arranque accidental | Mover la velocidad con el motor parado solo **preselecciona**; arrancar exige **INICIAR GIRO**. |
| STOP | Un toque, sin confirmación, siempre visible; también cancela maniobras en curso. |

> ⚠ **Decisión de producto pendiente:** para un asador, *detener* al perder conexión puede quemar la carne por un lado; *seguir girando* es lo que hace hoy el sistema original. Por eso `STOP_ON_DISCONNECT` viene en `0`. Si prefieres seguridad mecánica, ponlo en `1`.

---

## 6. Ejecutar

Requisitos: Flutter **3.29+** (Dart 3.7+), Android Studio / SDK; para iOS, macOS con Xcode 15+ y CocoaPods.

```bash
cd asador_app
bash tool/setup.sh      # genera Gradle/Xcode que faltan, pub get, Info.plist (macOS)
flutter test            # pruebas del protocolo
flutter run             # con un teléfono conectado
```

`tool/setup.sh` ejecuta `flutter create . --org com.kanka --project-name asador` (que **no sobrescribe** los archivos incluidos) para que el paquete Android sea `com.kanka.asador`, igual que la carpeta Kotlin. Si cambias el `--org`, mueve `MainActivity.kt`/`ClassicSppChannel.kt` y cambia su `package`.

En Windows/Linux sin macOS: ejecuta los mismos comandos del script manualmente y copia a `ios/Runner/Info.plist` las claves de `ios/Info.plist.additions.xml`.

## 7. Generar APK / AAB (Android)
```bash
flutter build apk --release --split-per-abi   # build/app/outputs/flutter-apk/
flutter build appbundle --release             # para Google Play
```
Para Play Store configura la firma (`android/key.properties` + `signingConfigs`): https://docs.flutter.dev/deployment/android

## 8. Generar IPA / app iOS
```bash
bash tool/setup.sh            # en macOS
open ios/Runner.xcworkspace   # Signing & Capabilities → tu Team, Bundle ID
flutter build ipa --release   # build/ios/ipa/
```
Instalar en tu iPhone sin publicar: `flutter run --release` con el iPhone conectado (requiere cuenta Apple Developer para firmar; gratuita = 7 días). **iOS requiere el firmware BLE.**

---

## 9. Probar con el ESP32

### A. Con el firmware actual (Android · Clásico)
1. Enciende el asador. En **Ajustes › Bluetooth** del Android, empareja el ESP32 (como hacías antes).
2. Abre la app → **Conectar asador** → pestaña **Clásico (actual)** → el ESP32 aparece como *Emparejado* → **Conectar**.
3. Pulsa **INICIAR GIRO**: se envía el nivel (p. ej. `"6"`). Cambia niveles: `"4"`…`"8"`. **Invertir** (mantener pulsado): `"1"`, pausa, `"0"`, `"6"`. **DETENER**: `"1"`.
4. Si el comportamiento no coincide (p. ej. `"1"` era un toggle), ajústalo en **Ajustes › Protocolo ESP32** sin recompilar.

### B. Con el firmware BLE (Android + iPhone)
1. Abre `firmware/esp32_asador_ble/esp32_asador_ble.ino` en Arduino IDE (placa *ESP32 Dev Module*, esquema de partición *Huge APP*).
2. **Sustituye el bloque de motor** (`PIN_PWM`, `PIN_DIR`, `DUTY_BY_LEVEL`, `handleCommandLocked`) por la lógica de tu sketch actual. La parte de radio no necesita cambios.
3. Carga el sketch. Monitor serie a 115200: debe mostrar `[ASADOR] listo como "ASADOR-ESP32"`. Puedes teclear `6`, `0`, `1` para probar el motor sin teléfono.
4. (Opcional) Verifica con **nRF Connect**: servicio `6E400001…`, escribe `36` (hex de "6") en RX.
5. App → **BLE** → aparece **ASADOR-ESP32** → Conectar.
6. Prueba de desconexión: apaga el ESP32 con el motor girando → la app muestra *Reconectando…* y bloquea controles; al volver, *Sin confirmar*.

---

## 10. Información que necesito de ti para cerrar al 100 %

1. **El sketch actual del ESP32** (`.ino`): para confirmar qué hacen exactamente `'0'`, `'1'` y `'4'..'8'`, y para integrar tu lógica de motor en el firmware BLE.
2. **Driver y motor**: modelo del driver (L298N, BTS7960, relé + inversor…), pines, PWM, y si el motor tolera inversión en marcha.
3. **Nombre Bluetooth** actual del ESP32 (para destacarlo automáticamente en la lista).
4. **Placa exacta** (ESP32‑WROOM, S3, C3…): S3/C3/C6 **no** tienen Bluetooth Clásico.
5. Tu preferencia sobre **parar o seguir girando** al perder conexión.
6. Si quieres **RPM/estado real**: el ESP32 necesitaría un sensor (hall/encoder) y enviar `S,…` por TX; la app ya tiene el canal de entrada preparado.

---

## 11. Estado de verificación
- ✅ Todo el Dart pasa un análisis sintáctico completo; pruebas unitarias del protocolo incluidas (`flutter test`).
- ⚠ El proyecto **no se ha compilado** en este entorno (sin acceso al SDK de Flutter). Ejecuta `flutter analyze` y `flutter test` como primer paso; cualquier ajuste de versión de paquetes debería ser menor.
- ⚠ No probado aún contra hardware real.
