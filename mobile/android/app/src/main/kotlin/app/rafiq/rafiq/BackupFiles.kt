package app.rafiq.rafiq

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * A backup file (lib/services/backup_files.dart), through the system's own
 * "Save to" and "Open" screens: the user picks the place (Downloads, Drive,
 * a memory card), and the app needs no storage permission.
 *
 * One request at a time; the answer comes back through [onResult], called
 * from the activity's onActivityResult. Reading and writing run off the main
 * thread.
 */
class BackupFiles(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private var pending: MethodChannel.Result? = null
    private var text: String? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "save" -> {
                val name = call.argument<String>("name") ?: "rafiq-backup.json"
                text = call.argument<String>("text") ?: ""
                start(
                    result,
                    Intent(Intent.ACTION_CREATE_DOCUMENT)
                        .addCategory(Intent.CATEGORY_OPENABLE)
                        .setType("application/json")
                        .putExtra(Intent.EXTRA_TITLE, name),
                    SAVE,
                )
            }
            "open" -> start(
                result,
                Intent(Intent.ACTION_OPEN_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    // Some file apps call a .json file text or octet-stream.
                    .setType("*/*")
                    .putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "text/*", "application/octet-stream")),
                OPEN,
            )
            else -> result.notImplemented()
        }
    }

    private fun start(result: MethodChannel.Result, intent: Intent, code: Int) {
        // A request still open (the screen left without an answer): cancelled.
        pending?.success(if (code == SAVE) false else null)
        pending = result
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent, code)
        } catch (e: Exception) {
            pending = null
            result.error("unavailable", "No file picker on this phone", null)
        }
    }

    /** True if [requestCode] was ours. */
    fun onResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != SAVE && requestCode != OPEN) return false
        val result = pending ?: return true
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(if (requestCode == SAVE) false else null)
            return true
        }
        val body = text
        text = null
        Thread {
            try {
                val answer: Any? = if (requestCode == SAVE) write(uri, body ?: "") else read(uri)
                main.post { result.success(answer) }
            } catch (e: Exception) {
                Log.w("RafiqBackup", "file", e)
                main.post { result.error("io", e.message, null) }
            }
        }.start()
        return true
    }

    private fun write(uri: Uri, body: String): Boolean {
        val out = activity.contentResolver.openOutputStream(uri, "wt") ?: return false
        out.use { it.write(body.toByteArray(Charsets.UTF_8)) }
        return true
    }

    private fun read(uri: Uri): String {
        val input = activity.contentResolver.openInputStream(uri) ?: throw IllegalStateException("cannot open")
        input.use {
            val buffer = ByteArrayOutputStream()
            val chunk = ByteArray(64 * 1024)
            while (true) {
                val n = it.read(chunk)
                if (n < 0) break
                buffer.write(chunk, 0, n)
                // Not one of ours: a backup is a few hundred kilobytes.
                if (buffer.size() > MAX_BYTES) throw IllegalStateException("too large")
            }
            return buffer.toString(Charsets.UTF_8.name())
        }
    }

    private companion object {
        const val SAVE = 4301
        const val OPEN = 4302

        /** As Backup.maxBytes in lib/data/backup.dart. */
        const val MAX_BYTES = 20 * 1024 * 1024
    }
}
