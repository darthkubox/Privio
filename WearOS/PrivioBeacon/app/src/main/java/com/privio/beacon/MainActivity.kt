package com.privio.beacon

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.InputDevice
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter

class MainActivity : Activity() {
    private lateinit var scroll: ScrollView
    private lateinit var root: LinearLayout
    private lateinit var title: TextView
    private lateinit var statusRow: LinearLayout
    private lateinit var statusDot: View
    private lateinit var status: TextView
    private lateinit var backgroundHint: TextView
    private lateinit var macStatus: TextView
    private lateinit var lockMacAction: Button
    private lateinit var action: Button
    private lateinit var pairingHint: TextView
    private lateinit var qrImage: ImageView
    private lateinit var pairingCode: TextView
    private lateinit var pairAction: Button
    private lateinit var versionLabel: TextView
    private val handler = Handler(Looper.getMainLooper())
    private val hidePairing = Runnable { setPairingVisible(false) }
    private val refreshStatus = object : Runnable {
        override fun run() { updateState(); handler.postDelayed(this, 1_000L) }
    }

    private val bgDark = Color.rgb(6, 11, 24)
    private val brandBlue = Color.rgb(74, 120, 255)
    private val onDarkSubtle = Color.rgb(150, 166, 198)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        render()
    }

    override fun onResume() {
        super.onResume()
        if (BeaconIdentity.enabled(this) &&
            checkSelfPermission(Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED) {
            startForegroundService(Intent(this, BeaconService::class.java).setAction(BeaconService.ACTION_START))
        }
        updateState()
        handler.removeCallbacks(refreshStatus)
        handler.post(refreshStatus)
    }

    override fun onPause() {
        setPairingVisible(false)
        handler.removeCallbacks(refreshStatus)
        super.onPause()
    }

    private fun dp(value: Int): Int = (resources.displayMetrics.density * value).toInt()

    /// Jednolity odstęp pionowy między przyciskami (i między statusem a pierwszym).
    private val buttonGap: Int get() = dp(12)

    /// Numer wersji do pokazania na tarczy - żeby było widać, czy wgrał się nowy build.
    private fun appVersion(): String = try {
        val info = packageManager.getPackageInfo(packageName, 0)
        val code = if (android.os.Build.VERSION.SDK_INT >= 28) info.longVersionCode
                   else @Suppress("DEPRECATION") info.versionCode.toLong()
        "${info.versionName} ($code)"
    } catch (_: Exception) { "?" }

    // Fallback: obrotowy pierścień przewija widok nawet gdy fokus ma przycisk.
    override fun onGenericMotionEvent(event: MotionEvent): Boolean {
        if (event.action == MotionEvent.ACTION_SCROLL &&
            event.isFromSource(InputDevice.SOURCE_ROTARY_ENCODER) && ::scroll.isInitialized) {
            val factor = ViewConfiguration.get(this).scaledVerticalScrollFactor
            scroll.smoothScrollBy(0, (-event.getAxisValue(MotionEvent.AXIS_SCROLL) * factor).toInt())
            return true
        }
        return super.onGenericMotionEvent(event)
    }

    private fun render() {
        // Mieści się razem z podpisem, kodem ręcznym i przyciskiem na okrągłym
        // ekranie bez konieczności przewijania.
        val qrSize = (resources.displayMetrics.widthPixels * 0.62f).toInt().coerceIn(210, 330)

        root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            // Duże marginesy góra/dół, aby na okrągłej tarczy nic się nie ucinało
            // (całość i tak przewijalna palcem oraz obrotowym pierścieniem).
            setPadding(dp(22), dp(56), dp(22), dp(56))
            setBackgroundColor(bgDark)
        }

        title = TextView(this).apply {
            text = "Privio"
            textSize = 24f; setTextColor(Color.WHITE); gravity = Gravity.CENTER
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, 0, 0, dp(2))
        }
        root.addView(title)

        // Status: kropka + tekst.
        statusRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER
            setPadding(0, 0, 0, dp(18))
        }
        statusDot = View(this).apply {
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL }
            layoutParams = LinearLayout.LayoutParams(dp(9), dp(9)).apply { rightMargin = dp(7) }
        }
        status = TextView(this).apply {
            textSize = 13f; setTextColor(onDarkSubtle); gravity = Gravity.CENTER
        }
        statusRow.addView(statusDot)
        statusRow.addView(status)
        root.addView(statusRow)

        backgroundHint = TextView(this).apply {
            text = "Działa w tle - możesz zamknąć aplikację.\nWznawia się po restarcie zegarka."
            textSize = 11f; setTextColor(Color.rgb(120, 134, 165)); gravity = Gravity.CENTER
            setPadding(0, 0, 0, dp(16))
            visibility = View.GONE
        }
        root.addView(backgroundHint)

        macStatus = TextView(this).apply {
            textSize = 12f; setTextColor(onDarkSubtle); gravity = Gravity.CENTER
        }
        root.addView(macStatus)

        lockMacAction = pillButton("Zablokuj Maca", brandBlue, Color.WHITE).apply {
            setOnClickListener {
                startForegroundService(Intent(this@MainActivity, BeaconService::class.java)
                    .setAction(BeaconService.ACTION_LOCK_MAC))
            }
        }
        root.addView(lockMacAction, buttonParams(topMargin = buttonGap))

        qrImage = ImageView(this).apply {
            setImageBitmap(qrBitmap(BeaconIdentity.pairingUri(this@MainActivity), qrSize))
            contentDescription = "Kod QR parowania Privio"
            visibility = View.GONE
        }
        root.addView(qrImage, LinearLayout.LayoutParams(qrSize, qrSize))

        pairingHint = TextView(this).apply {
            text = "Pokaż kod aplikacji Privio na Macu"
            textSize = 12f; setTextColor(Color.rgb(36, 82, 190)); gravity = Gravity.CENTER
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, dp(7), 0, 0)
            visibility = View.GONE
        }
        root.addView(pairingHint)

        pairingCode = TextView(this).apply {
            text = BeaconIdentity.code(this@MainActivity)
            textSize = 13f; setTextColor(Color.rgb(90, 100, 120)); gravity = Gravity.CENTER
            typeface = Typeface.MONOSPACE
            letterSpacing = 0.04f
            setPadding(0, dp(5), 0, dp(5))
            visibility = View.GONE
        }
        root.addView(pairingCode)

        action = pillButton("Włącz beacon", brandBlue, Color.WHITE).apply {
            setOnClickListener { toggle() }
        }
        root.addView(action, buttonParams(topMargin = buttonGap))

        pairAction = pillButton("Sparuj z Makiem", Color.rgb(28, 38, 62), Color.rgb(214, 224, 248)).apply {
            setOnClickListener { setPairingVisible(true) }
        }
        root.addView(pairAction, buttonParams(topMargin = buttonGap))

        versionLabel = TextView(this).apply {
            text = "v${appVersion()}"
            textSize = 10f; setTextColor(Color.rgb(96, 108, 138)); gravity = Gravity.CENTER
            letterSpacing = 0.03f
            setPadding(0, dp(14), 0, 0)
        }
        root.addView(versionLabel)

        scroll = ScrollView(this).apply {
            isFillViewport = true
            overScrollMode = View.OVER_SCROLL_NEVER
            setBackgroundColor(bgDark)
            isFocusable = true
            isFocusableInTouchMode = true
            // Scroll obrotowym pierścieniem (rotary encoder) Galaxy Watch.
            setOnGenericMotionListener { v, event ->
                if (event.action == MotionEvent.ACTION_SCROLL &&
                    event.isFromSource(InputDevice.SOURCE_ROTARY_ENCODER)) {
                    val factor = ViewConfiguration.get(this@MainActivity).scaledVerticalScrollFactor
                    val delta = (-event.getAxisValue(MotionEvent.AXIS_SCROLL) * factor).toInt()
                    (v as ScrollView).smoothScrollBy(0, delta)
                    true
                } else false
            }
        }
        scroll.addView(root, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT))
        setContentView(scroll)
        scroll.post { scroll.requestFocus() }   // pierścień wysyła zdarzenia do ufokusowanego widoku
    }

    // Szerokość przycisku ~60% średnicy - mieści się w okrągłym ekranie (z pierścieniem),
    // więc boki nie wchodzą pod krzywiznę bezela.
    private fun buttonParams(topMargin: Int) =
        LinearLayout.LayoutParams((resources.displayMetrics.widthPixels * 0.63f).toInt(),
            ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            this.topMargin = topMargin
        }

    private fun pillButton(label: String, fill: Int, textColor: Int): Button =
        Button(this).apply {
            text = label
            isAllCaps = false
            textSize = 15f
            setTextColor(textColor)
            typeface = Typeface.DEFAULT_BOLD
            stateListAnimator = null
            // Duży promień → GradientDrawable przycina do połowy wysokości = pełne półkola.
            background = GradientDrawable().apply { cornerRadius = 1000f; setColor(fill) }
            setPadding(dp(10), dp(15), dp(10), dp(15))
            maxLines = 1
        }

    /// Ekran kodu jest CAŁY BIAŁY - czytelny cel do skanowania na okrągłej tarczy.
    private fun setPairingVisible(visible: Boolean) {
        if (!::pairingHint.isInitialized) return
        handler.removeCallbacks(hidePairing)

        val bg = if (visible) Color.WHITE else bgDark
        root.setBackgroundColor(bg)
        scroll.setBackgroundColor(bg)
        root.setPadding(dp(22), if (visible) dp(12) else dp(56), dp(22), if (visible) dp(12) else dp(56))

        title.visibility = if (visible) View.GONE else View.VISIBLE
        statusRow.visibility = if (visible) View.GONE else View.VISIBLE
        action.visibility = if (visible) View.GONE else View.VISIBLE
        macStatus.visibility = if (visible) View.GONE else View.VISIBLE
        lockMacAction.visibility = if (visible) View.GONE else View.VISIBLE
        backgroundHint.visibility = if (visible) View.GONE else View.VISIBLE
        if (::versionLabel.isInitialized) versionLabel.visibility = if (visible) View.GONE else View.VISIBLE

        pairingHint.visibility = if (visible) View.VISIBLE else View.GONE
        qrImage.visibility = if (visible) View.VISIBLE else View.GONE
        pairingCode.visibility = if (visible) View.VISIBLE else View.GONE

        if (visible) {
            scroll.scrollTo(0, 0)
            pairAction.text = "Gotowe"
            stylePill(pairAction, fill = Color.rgb(232, 236, 244), textColor = Color.rgb(40, 52, 74))
        } else {
            pairAction.text = "Sparuj z Makiem"
            stylePill(pairAction, fill = Color.rgb(28, 38, 62), textColor = Color.rgb(214, 224, 248))
        }
        pairAction.setOnClickListener { setPairingVisible(!visible) }

        // Nie gaś ekranu podczas skanowania QR.
        if (visible) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        if (visible) handler.postDelayed(hidePairing, 120_000L)
    }

    private fun stylePill(button: Button, fill: Int, textColor: Int) {
        button.setTextColor(textColor)
        button.background = GradientDrawable().apply { cornerRadius = 1000f; setColor(fill) }
    }

    private fun qrBitmap(value: String, size: Int): Bitmap {
        val matrix = QRCodeWriter().encode(value, BarcodeFormat.QR_CODE, size, size)
        return Bitmap.createBitmap(size, size, Bitmap.Config.RGB_565).also { bitmap ->
            for (x in 0 until size) for (y in 0 until size) {
                bitmap.setPixel(x, y, if (matrix[x, y]) Color.BLACK else Color.WHITE)
            }
        }
    }

    private fun toggle() {
        if (BeaconIdentity.enabled(this)) {
            startService(Intent(this, BeaconService::class.java).setAction(BeaconService.ACTION_STOP))
            BeaconIdentity.setEnabled(this, false)
            updateState()
            return
        }
        val permissions = mutableListOf(Manifest.permission.BLUETOOTH_ADVERTISE,
            Manifest.permission.BLUETOOTH_CONNECT)
        if (android.os.Build.VERSION.SDK_INT >= 33) permissions += Manifest.permission.POST_NOTIFICATIONS
        val missing = permissions.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isNotEmpty()) requestPermissions(missing.toTypedArray(), 42) else startBeacon()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, results)
        if (requestCode == 42 && results.isNotEmpty() && results.all { it == PackageManager.PERMISSION_GRANTED }) startBeacon()
        else updateState()
    }

    private fun startBeacon() {
        requestIgnoreBatteryOptimizations()
        startForegroundService(Intent(this, BeaconService::class.java).setAction(BeaconService.ACTION_START))
        BeaconIdentity.setEnabled(this, true)
        updateState()
    }

    /// Wear OS potrafi dławić/ubijać usługę w tle. Bez wyjątku od optymalizacji baterii
    /// beacon przestaje być widziany po zgaśnięciu ekranu. Pytamy tylko raz - gdy już
    /// zwolniony, systemowy ekran się nie pokaże.
    private fun requestIgnoreBatteryOptimizations() {
        val pm = getSystemService(android.os.PowerManager::class.java) ?: return
        if (pm.isIgnoringBatteryOptimizations(packageName)) return
        try {
            startActivity(Intent(
                android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                android.net.Uri.parse("package:$packageName")))
        } catch (_: Exception) { /* niektóre buildy Wear nie mają tego ekranu - pomijamy */ }
    }

    private fun updateState() {
        if (!::status.isInitialized) return
        val enabled = BeaconIdentity.enabled(this)
        status.text = if (enabled) "Aktywny - Privio widzi zegarek" else "Wyłączony"
        (statusDot.background as? GradientDrawable)?.setColor(
            if (enabled) Color.rgb(70, 200, 120) else Color.rgb(120, 130, 150))
        if (::backgroundHint.isInitialized) {
            backgroundHint.text = if (enabled)
                "Działa w tle - możesz zamknąć aplikację.\nWznawia się po restarcie zegarka."
            else
                "Nie działa w tle, nie zużywa baterii\ni nie uruchamia się po restarcie."
            backgroundHint.visibility = View.VISIBLE
        }
        action.text = if (enabled) "Wyłącz beacon" else "Włącz beacon"
        stylePill(action,
            fill = if (enabled) Color.rgb(28, 38, 62) else brandBlue,
            textColor = if (enabled) Color.rgb(214, 224, 248) else Color.WHITE)
        if (::macStatus.isInitialized) {
            val recent = BeaconIdentity.hasRecentMacStatus(this)
            macStatus.text = when {
                !enabled -> "Mac: brak połączenia"
                !recent -> "Mac: oczekiwanie na połączenie"
                BeaconIdentity.macLocked(this) -> "Mac jest zablokowany"
                else -> "Mac jest otwarty"
            }
            lockMacAction.isEnabled = enabled && recent
            lockMacAction.alpha = if (lockMacAction.isEnabled) 1f else 0.45f
        }
    }
}
