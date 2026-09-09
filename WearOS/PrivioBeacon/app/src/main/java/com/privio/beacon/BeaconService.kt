package com.privio.beacon

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.IBinder
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.os.PowerManager
import java.util.UUID
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

class BeaconService : Service() {
    companion object {
        const val ACTION_START = "com.privio.beacon.START"
        const val ACTION_STOP = "com.privio.beacon.STOP"
        const val ACTION_LOCK_MAC = "com.privio.beacon.LOCK_MAC"
        const val ACTION_MAC_STATUS_CHANGED = "com.privio.beacon.MAC_STATUS_CHANGED"
        const val SERVICE_UUID = "0000fff0-0000-1000-8000-00805f9b34fb"
        private const val CHANNEL = "privio_beacon_status"
        private const val NOTIFICATION_ID = 1001
    }

    private val callback = object : AdvertiseCallback() {}
    private val handler = Handler(Looper.getMainLooper())
    /// Model połączeniowy (jak parowanie z telefonem): gdy Mac trzyma połączenie GATT,
    /// obecność niesie samo połączenie - utrzymuje je kontroler BT, przeżywa Doze, a CPU
    /// może spać. WakeLock jest więc trzymany **tylko gdy jesteśmy ROZŁĄCZENI** (start /
    /// utrata zasięgu): wtedy rotujemy token i rozgłaszamy, żeby Mac mógł (ponownie) się
    /// połączyć. Po połączeniu WakeLock jest zwalniany, rotacja i rozgłaszanie zatrzymane
    /// (to eliminuje główny drenaż baterii). Zwalniany też w stopBeacon()/onDestroy().
    private var wakeLock: PowerManager.WakeLock? = null
    private var gattServer: PrivioGattServer? = null
    /// Czy jakikolwiek central (Mac) jest aktualnie połączony (tryb oszczędny).
    private var macConnected = false
    /// Czy beacon jest już zainicjalizowany w tym cyklu życia usługi (idempotencja onStartCommand).
    private var beaconActive = false
    private val rotate = object : Runnable {
        override fun run() {
            advertiseCurrentToken()
            val delay = 30_100L - (System.currentTimeMillis() % 30_000L)
            handler.postDelayed(this, delay)
        }
    }

    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL, "Privio Beacon", NotificationManager.IMPORTANCE_LOW)
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopBeacon()
            return START_NOT_STICKY
        }
        startForegroundBeacon()
        if (intent?.action == ACTION_LOCK_MAC) {
            val sent = gattServer?.requestMacLock() == true
            sendBroadcast(Intent(ACTION_MAC_STATUS_CHANGED)
                .putExtra("lockRequestSent", sent).setPackage(packageName))
        }
        return START_STICKY
    }

    private fun startForegroundBeacon() {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = Notification.Builder(this, CHANNEL)
            .setSmallIcon(com.privio.beacon.R.drawable.ic_privio)
            .setContentTitle("Privio Beacon działa")
            .setContentText("Mac może wykrywać, gdy odchodzisz")
            .setOngoing(true).setContentIntent(open).build()
        startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)

        if (checkSelfPermission(Manifest.permission.BLUETOOTH_ADVERTISE) != PackageManager.PERMISSION_GRANTED) {
            stopSelf(); return
        }
        if (gattServer == null) {
            gattServer = PrivioGattServer(
                context = this,
                onMacStatus = { locked ->
                    sendBroadcast(Intent(ACTION_MAC_STATUS_CHANGED).putExtra("locked", locked).setPackage(packageName))
                },
                onCentralConnectionChange = { connected -> handler.post { onMacConnectionChanged(connected) } }
            ).also { it.start() }
        }
        if (!beaconActive) {
            beaconActive = true
            macConnected = false
            enterDisconnectedMode()   // rozgłaszaj + rotuj + WakeLock, aż Mac się połączy
        }
        BeaconIdentity.setEnabled(this, true)
    }

    /// Wywoływane (na wątku głównym) przy zmianie stanu połączenia z Makiem.
    private fun onMacConnectionChanged(connected: Boolean) {
        if (connected == macConnected || !beaconActive) return
        macConnected = connected
        if (connected) enterConnectedMode() else enterDisconnectedMode()
    }

    /// Mac połączony: obecność niesie połączenie (kontroler BT, przeżywa Doze) - zwolnij
    /// WakeLock, zatrzymaj rotację i rozgłaszanie, pozwól CPU spać. Główna oszczędność baterii.
    private fun enterConnectedMode() {
        handler.removeCallbacks(rotate)
        stopAdvertising()
        releaseWakeLock()
    }

    /// Rozłączeni (start lub utrata zasięgu): trzymaj WakeLock i rozgłaszaj rotujący token,
    /// żeby Mac mógł (ponownie) wykryć zegarek i połączyć się.
    private fun enterDisconnectedMode() {
        acquireWakeLock()
        handler.removeCallbacks(rotate)
        rotate.run()
    }

    private fun stopAdvertising() {
        if (checkSelfPermission(Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED) {
            getSystemService(BluetoothManager::class.java).adapter?.bluetoothLeAdvertiser?.stopAdvertising(callback)
        }
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(PowerManager::class.java)
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "privio:beacon").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseWakeLock() {
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = null
    }

    private fun advertiseCurrentToken() {
        if (checkSelfPermission(Manifest.permission.BLUETOOTH_ADVERTISE) != PackageManager.PERMISSION_GRANTED) return
        val adapter = getSystemService(BluetoothManager::class.java).adapter ?: return
        val advertiser = adapter.bluetoothLeAdvertiser ?: run { stopSelf(); return }
        advertiser.stopAdvertising(callback)
        val slot = (System.currentTimeMillis() / 30_000L).toInt()
        val counter = byteArrayOf(
            (slot ushr 24).toByte(), (slot ushr 16).toByte(),
            (slot ushr 8).toByte(), slot.toByte()
        )
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(BeaconIdentity.secret(this), "HmacSHA256"))
        val tag = mac.doFinal(byteArrayOf(0x50, 0x56, 0x02) + counter).copyOfRange(0, 4)
        val payload = byteArrayOf(0x50, 0x56, 0x02) + counter + tag
        val data = AdvertiseData.Builder()
            .addServiceData(ParcelUuid(UUID.fromString(SERVICE_UUID)), payload)
            .setIncludeDeviceName(false).setIncludeTxPowerLevel(false).build()
        val settings = AdvertiseSettings.Builder()
            // MUSI zostać LOW_POWER: na kontrolerze Samsunga tryby BALANCED/LOW_LATENCY
            // przełączają nadawanie na LE 5 „extended advertising" (secondary PHY),
            // którego macOS CoreBluetooth NIE odbiera w standardowym skanie - beacon
            // znika z Maca. LOW_POWER daje legacy advert (odbierany przez Maca).
            // Ciągłość przy zgaszonym ekranie zapewnia WakeLock, nie interwał reklamy.
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_POWER)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(true).setTimeout(0).build()
        advertiser.startAdvertising(settings, data, callback)
    }

    private fun stopBeacon() {
        beaconActive = false
        macConnected = false
        handler.removeCallbacks(rotate)
        stopAdvertising()
        releaseWakeLock()
        gattServer?.stop(); gattServer = null
        BeaconIdentity.setEnabled(this, false)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        beaconActive = false
        macConnected = false
        handler.removeCallbacks(rotate)
        releaseWakeLock()
        gattServer?.stop(); gattServer = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

}
