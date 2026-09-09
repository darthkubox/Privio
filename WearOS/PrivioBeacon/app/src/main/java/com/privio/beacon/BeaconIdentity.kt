package com.privio.beacon

import android.Manifest
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.util.Base64
import java.security.MessageDigest
import java.security.SecureRandom

object BeaconIdentity {
    private const val PREFS = "privio_beacon"
    private const val KEY_SECRET = "pairing_secret_v2"
    private const val KEY_ENABLED = "beacon_enabled"
    private const val KEY_MAC_LOCKED = "mac_locked"
    private const val KEY_MAC_STATUS_AT = "mac_status_at"

    fun secret(context: Context): ByteArray {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val existing = prefs.getString(KEY_SECRET, null)
        if (existing != null) return existing.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        val bytes = ByteArray(16).also(SecureRandom()::nextBytes)
        prefs.edit().putString(KEY_SECRET, bytes.toHex()).apply()
        return bytes
    }

    fun publicId(context: Context): ByteArray =
        MessageDigest.getInstance("SHA-256").digest(secret(context)).copyOfRange(0, 8)

    fun code(context: Context): String = base32(secret(context)).chunked(4).joinToString("-")

    fun pairingUri(context: Context): String {
        val id = publicId(context).toHex().uppercase()
        val encodedSecret = Base64.encodeToString(secret(context), Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
        return Uri.Builder().scheme("privio").authority("pair")
            .appendQueryParameter("v", "2")
            .appendQueryParameter("id", id)
            .appendQueryParameter("s", encodedSecret)
            .appendQueryParameter("n", deviceName(context))
            .build().toString()
    }

    /** User-visible device name when available, with a model fallback. */
    fun deviceName(context: Context): String {
        val bluetoothName = if (context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED) {
            context.getSystemService(BluetoothManager::class.java).adapter?.name
        } else null
        val fallbackModel = when (Build.MODEL.uppercase()) {
            "SM-R960", "SM-R965" -> "Galaxy Watch6 Classic"
            "SM-R950", "SM-R955" -> "Galaxy Watch6"
            else -> Build.MODEL
        }
        val candidate = bluetoothName?.trim()?.takeIf {
            it.isNotEmpty() && !it.startsWith("Privio", ignoreCase = true)
        } ?: fallbackModel
        val manufacturer = Build.MANUFACTURER.replaceFirstChar { it.uppercase() }
        return if (candidate.startsWith(manufacturer, ignoreCase = true)) candidate else "$manufacturer $candidate"
    }
    fun enabled(context: Context): Boolean = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        .getBoolean(KEY_ENABLED, false)
    fun setEnabled(context: Context, enabled: Boolean) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        .edit().putBoolean(KEY_ENABLED, enabled).apply()
    fun setMacLocked(context: Context, locked: Boolean) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        .edit().putBoolean(KEY_MAC_LOCKED, locked).putLong(KEY_MAC_STATUS_AT, System.currentTimeMillis()).apply()
    fun macLocked(context: Context): Boolean = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        .getBoolean(KEY_MAC_LOCKED, false)
    fun hasRecentMacStatus(context: Context): Boolean = System.currentTimeMillis() -
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getLong(KEY_MAC_STATUS_AT, 0L) < 90_000L

    private fun ByteArray.toHex() = joinToString("") { "%02x".format(it) }

    private fun base32(data: ByteArray): String {
        val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        val output = StringBuilder()
        var buffer = 0
        var bits = 0
        for (byte in data) {
            buffer = (buffer shl 8) or (byte.toInt() and 0xff)
            bits += 8
            while (bits >= 5) {
                output.append(alphabet[(buffer shr (bits - 5)) and 31])
                bits -= 5
                buffer = if (bits == 0) 0 else buffer and ((1 shl bits) - 1)
            }
        }
        if (bits > 0) output.append(alphabet[(buffer shl (5 - bits)) and 31])
        return output.toString()
    }
}
