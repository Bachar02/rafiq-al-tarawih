package app.rafiq.rafiq

import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    /** What a tapped dhikr notification opened, until Dart asks. */
    private var launchOpen: String? = null

    /** Waiting for the user to come back from the "Appear on top" setting. */
    private var onScreenResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        launchOpen = intent?.getStringExtra(DhikrNotification.EXTRA_OPEN)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.rafiq.rafiq/dhikr").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "schedule" -> {
                        val items = (call.argument<List<Map<*, *>>>("items") ?: emptyList()).map(Dhikr::fromMap)
                        DhikrSchedule.replace(
                            applicationContext,
                            items,
                            call.argument<String>("channelName") ?: "",
                            call.argument<String>("closeLabel") ?: "",
                        )
                        result.success(null)
                    }
                    "show" -> {
                        val item = call.argument<Map<*, *>>("item")
                        if (item != null) {
                            DhikrSchedule.show(
                                applicationContext,
                                Dhikr.fromMap(item),
                                call.argument<String>("channelName"),
                                call.argument<String>("closeLabel"),
                            )
                        }
                        result.success(null)
                    }
                    "canShowOnScreen" -> result.success(Settings.canDrawOverlays(this@MainActivity))
                    // The setting, whether allowed or not: it is also where
                    // the permission is taken back.
                    "requestShowOnScreen" -> {
                        onScreenResult?.success(Settings.canDrawOverlays(this@MainActivity))
                        onScreenResult = result
                        try {
                            @Suppress("DEPRECATION")
                            startActivityForResult(
                                Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")),
                                ON_SCREEN_REQUEST,
                            )
                        } catch (e: Exception) {
                            // No such screen on this phone (Android Go).
                            onScreenResult = null
                            result.success(Settings.canDrawOverlays(this@MainActivity))
                        }
                    }
                    "takeLaunchOpen" -> {
                        result.success(launchOpen)
                        launchOpen = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val open = intent.getStringExtra(DhikrNotification.EXTRA_OPEN) ?: return
        channel?.invokeMethod("open", open)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != ON_SCREEN_REQUEST) return
        val result = onScreenResult ?: return
        onScreenResult = null
        // Some Android versions report the change a moment late.
        Handler(Looper.getMainLooper()).postDelayed({ result.success(Settings.canDrawOverlays(this)) }, 300)
    }

    private companion object {
        const val ON_SCREEN_REQUEST = 4207
    }
}
