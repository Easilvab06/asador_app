#!/usr/bin/env bash
# Genera los archivos de plataforma que faltan (Gradle, Xcode) SIN tocar el
# código incluido (lib/, AndroidManifest.xml, Kotlin), y aplica la
# configuración de iOS.
#
# Uso:  cd asador_app && bash tool/setup.sh
set -euo pipefail
cd "$(dirname "$0")/.."

command -v flutter >/dev/null || { echo "Flutter no está en el PATH"; exit 1; }

echo "▸ flutter create (solo añade archivos que faltan)…"
# --org + --project-name producen el paquete com.kanka.asador, que coincide
# con android/app/src/main/kotlin/com/kanka/asador/MainActivity.kt
flutter create . --org com.kanka --project-name asador --platforms android,ios

echo "▸ flutter pub get…"
flutter pub get

PLIST="ios/Runner/Info.plist"
if [[ "$(uname)" == "Darwin" && -f "$PLIST" ]]; then
  echo "▸ Configurando Info.plist…"
  PB=/usr/libexec/PlistBuddy
  add_or_set () {
    $PB -c "Set :$1 $2" "$PLIST" 2>/dev/null || $PB -c "Add :$1 string $2" "$PLIST"
  }
  add_or_set NSBluetoothAlwaysUsageDescription "Asador usa Bluetooth para conectarse al asador y controlar la velocidad y el sentido del motor."
  add_or_set NSBluetoothPeripheralUsageDescription "Asador usa Bluetooth para conectarse al asador y controlar el motor."
  add_or_set CFBundleDisplayName "Asador"

  # Plataforma mínima iOS 13 (requerida por universal_ble / CoreBluetooth moderno).
  if [[ -f ios/Podfile ]]; then
    sed -i '' -E "s/^# ?platform :ios, '[0-9.]+'/platform :ios, '13.0'/" ios/Podfile || true
  fi
  echo "▸ pod install…"
  (cd ios && pod install) || echo "  (pod install falló; ejecútalo manualmente)"
else
  echo "▸ No es macOS: añade manualmente las claves de ios/Info.plist.additions.xml"
fi

echo "✔ Listo. Ejecuta: flutter run"
