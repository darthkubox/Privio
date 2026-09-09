package com.privio.beacon

import android.Manifest
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import java.nio.ByteBuffer
import java.security.SecureRandom
import java.util.UUID
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Prywatny kanał sterujący po BLE. Reklama nadal zawiera wyłącznie rotujący token
 * obecności; status Maca i komenda blokady płyną dopiero po połączeniu GATT i są
 * uwierzytelnione HMAC sekretem przekazanym przez QR.
 */
class PrivioGattServer(
    private val context: Context,
    private val onMacStatus: (Boolean) -> Unit,
    /// Wołane, gdy zmienia się liczba połączonych centrali (Mac). `true` = ktoś połączony.
    /// Napędza tryb oszczędny beacona: gdy Mac trzyma połączenie, zegarek zwalnia WakeLock
    /// i przestaje rotować/rozgłaszać (obecność niesie połączenie).
    private val onCentralConnectionChange: (Boolean) -> Unit = {}
) {
    companion object {
        val SERVICE_UUID: UUID = UUID.fromString("0000fff0-0000-1000-8000-00805f9b34fb")
        val CONTROL_UUID: UUID = UUID.fromString("0000fff1-0000-1000-8000-00805f9b34fb")
        val IDENTITY_UUID: UUID = UUID.fromString("0000fff2-0000-1000-8000-00805f9b34fb")
        private val CCC_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
        private const val STATUS_TYPE: Byte = 0x10
        private const val LOCK_TYPE: Byte = 0x11
    }

    private var server: BluetoothGattServer? = null
    private var control: BluetoothGattCharacteristic? = null
    private val subscribed = mutableSetOf<BluetoothDevice>()
    private val connectedCentrals = mutableSetOf<BluetoothDevice>()
    private val random = SecureRandom()

    private val callback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            val before = connectedCentrals.isNotEmpty()
            if (newState == BluetoothGatt.STATE_CONNECTED) {
                connectedCentrals.add(device)
            } else {
                subscribed.remove(device)
                connectedCentrals.remove(device)
            }
            val now = connectedCentrals.isNotEmpty()
            if (now != before) onCentralConnectionChange(now)
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice, requestId: Int, descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray
        ) {
            if (descriptor.uuid == CCC_UUID && value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)) {
                subscribed.add(device)
            } else if (descriptor.uuid == CCC_UUID) {
                subscribed.remove(device)
            }
            if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice, requestId: Int, characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray
        ) {
            val valid = characteristic.uuid == CONTROL_UUID && verifyStatus(value)
            if (responseNeeded) server?.sendResponse(
                device, requestId, if (valid) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_FAILURE, 0, null)
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice, requestId: Int, offset: Int,
            characteristic: BluetoothGattCharacteristic
        ) {
            if (characteristic.uuid != IDENTITY_UUID) {
                server?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, 0, null)
                return
            }
            val value = BeaconIdentity.deviceName(context).toByteArray(Charsets.UTF_8)
            if (offset > value.size) {
                server?.sendResponse(device, requestId, BluetoothGatt.GATT_INVALID_OFFSET, offset, null)
            } else {
                server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value.copyOfRange(offset, value.size))
            }
        }
    }

    fun start() {
        if (context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) return
        val manager = context.getSystemService(BluetoothManager::class.java)
        val opened = manager.openGattServer(context, callback) ?: return
        val characteristic = BluetoothGattCharacteristic(
            CONTROL_UUID,
            BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_WRITE
        )
        characteristic.addDescriptor(BluetoothGattDescriptor(
            CCC_UUID, BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE
        ))
        val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        service.addCharacteristic(characteristic)
        service.addCharacteristic(BluetoothGattCharacteristic(
            IDENTITY_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ
        ))
        opened.addService(service)
        server = opened
        control = characteristic
    }

    fun stop() {
        if (context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED) {
            server?.close()
        }
        subscribed.clear()
        connectedCentrals.clear()
        server = null
        control = null
    }

    fun requestMacLock(): Boolean {
        if (context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) return false
        val characteristic = control ?: return false
        val packet = lockPacket()
        var sent = false
        for (device in subscribed.toList()) {
            val result = if (android.os.Build.VERSION.SDK_INT >= 33) {
                server?.notifyCharacteristicChanged(device, characteristic, false, packet)
            } else {
                @Suppress("DEPRECATION")
                characteristic.value = packet
                @Suppress("DEPRECATION")
                if (server?.notifyCharacteristicChanged(device, characteristic, false) == true) BluetoothGatt.GATT_SUCCESS
                else BluetoothGatt.GATT_FAILURE
            }
            sent = sent || result == BluetoothGatt.GATT_SUCCESS
        }
        return sent
    }

    private fun verifyStatus(packet: ByteArray): Boolean {
        if (packet.size != 16 || packet[0] != 0x50.toByte() || packet[1] != 0x56.toByte()
            || packet[2] != STATUS_TYPE) return false
        val slot = ByteBuffer.wrap(packet, 3, 4).int.toLong() and 0xffffffffL
        val current = System.currentTimeMillis() / 30_000L
        if (kotlin.math.abs(slot - current) > 1) return false
        val body = packet.copyOfRange(0, 8)
        val expected = hmac(body).copyOfRange(0, 8)
        if (!expected.contentEquals(packet.copyOfRange(8, 16))) return false
        val locked = packet[7].toInt() == 1
        BeaconIdentity.setMacLocked(context, locked)
        onMacStatus(locked)
        return true
    }

    private fun lockPacket(): ByteArray {
        val slot = (System.currentTimeMillis() / 30_000L).toInt()
        val lockNonce = random.nextInt()
        val body = ByteBuffer.allocate(11)
            .put(0x50).put(0x56).put(LOCK_TYPE).putInt(slot).putInt(lockNonce).array()
        return body + hmac(body).copyOfRange(0, 8)
    }

    private fun hmac(message: ByteArray): ByteArray = Mac.getInstance("HmacSHA256").run {
        init(SecretKeySpec(BeaconIdentity.secret(context), "HmacSHA256"))
        doFinal(message)
    }
}
