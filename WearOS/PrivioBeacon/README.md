# Privio Beacon for Wear OS

Companion app for Privio on macOS. The watch advertises a small Bluetooth LE
service record that Privio can identify independently of Wear OS rotating BLE
addresses.

## Build

Requirements: Android Studio, Android SDK 35 or newer, and its bundled JDK.

```sh
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"
./gradlew :app:assembleDebug --offline
```

The debug APK is written to:

`app/build/outputs/apk/debug/app-debug.apk`

## Install on a Galaxy Watch

1. On the watch open **Settings > About watch > Software information** and tap
   **Software version** repeatedly until developer mode is enabled.
2. Open **Settings > Developer options**, enable **ADB debugging**, then enable
   **Wireless debugging**. The watch and Mac must use the same Wi-Fi network.
3. In **Wireless debugging**, choose **Pair new device** and note the IP/port and
   six-digit pairing code.
4. On the Mac run `adb pair IP:PAIR_PORT`, enter the pairing code, then run
   `adb connect IP:DEBUG_PORT` using the port shown on the main Wireless
   debugging screen.
5. Install with `adb install -r app/build/outputs/apk/debug/app-debug.apk`.

Open Privio Beacon on the watch, allow Bluetooth/notification permissions, and
tap **Start beacon**. In Privio on the Mac choose **Add device** and select the
entry whose pairing code matches the watch.

## Beacon format (v1 MVP)

- BLE service UUID: `FFF0`
- Service data: ASCII `PV`, byte `01`, and an 8-byte persistent random ID
- The Mac renders the ID as `XXXX-XXXX-XXXX-XXXX`

The v1 identifier is intended for local development. Before public release it
should be replaced with authenticated rotating tokens to avoid broadcasting a
long-lived tracking identifier.

## Planned pairing flow

The watch will display a QR code containing pairing material. Privio on macOS
will scan it with the Mac camera, with manual code entry available as a fallback.
Pairing will provision a shared secret used to authenticate rotating BLE tokens;
the secret itself must never be included in normal advertisements.
