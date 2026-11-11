package app.rafiq.rafiq

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.provider.Settings
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject

/**
 * The dhikr reminders, on the Android side.
 *
 * Dart sends the next two weeks of adhkar ([DhikrSchedule.replace]); only the
 * next one is set as an alarm, and each one that fires sets the one after it,
 * so a hundred alarms never pile up and a restart of the phone sets one again
 * ([DhikrReceiver]).
 *
 * When one comes, it is shown in a small card at the top right of the screen,
 * over any app, until it is tapped ([DhikrCard]). That needs the user's
 * "Appear on top" permission; without it the dhikr is a notification that
 * waits in the shade until it is tapped or swiped away.
 */
data class Dhikr(val at: Long, val title: String, val body: String, val expanded: String?) {
    fun toJson(): JSONObject = JSONObject()
        .put("at", at)
        .put("title", title)
        .put("body", body)
        .put("expanded", expanded ?: JSONObject.NULL)

    companion object {
        fun fromJson(o: JSONObject) = Dhikr(
            at = o.getLong("at"),
            title = o.getString("title"),
            body = o.getString("body"),
            expanded = if (o.isNull("expanded")) null else o.getString("expanded"),
        )

        fun fromMap(m: Map<*, *>) = Dhikr(
            at = (m["at"] as Number).toLong(),
            title = m["title"] as String,
            body = m["body"] as String,
            expanded = m["expanded"] as String?,
        )
    }
}

object DhikrSchedule {
    private const val TAG = "RafiqDhikr"
    private const val PREFS = "rafiq_dhikr"
    private const val KEY_SCHEDULE = "schedule"
    private const val KEY_SHOWING = "showing"
    private const val KEY_CHANNEL = "channel"
    private const val KEY_CLOSE = "close"
    const val ACTION_FIRE = "app.rafiq.rafiq.DHIKR"

    /** A dhikr this close to its time when the alarm fires is due now. */
    private const val EARLY_MS = 60_000L

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Replaces the whole schedule (none: no more adhkar) and sets the next alarm. */
    fun replace(context: Context, items: List<Dhikr>, channelName: String, closeLabel: String) {
        val array = JSONArray()
        items.sortedBy { it.at }.forEach { array.put(it.toJson()) }
        prefs(context).edit()
            .putString(KEY_SCHEDULE, array.toString())
            .putString(KEY_CHANNEL, channelName)
            .putString(KEY_CLOSE, closeLabel)
            .apply()
        arm(context)
    }

    private fun load(context: Context): List<Dhikr> {
        val raw = prefs(context).getString(KEY_SCHEDULE, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).map { Dhikr.fromJson(array.getJSONObject(it)) }
        } catch (e: Exception) {
            // An unreadable schedule: nothing until the app sends a new one.
            Log.w(TAG, "unreadable schedule", e)
            emptyList()
        }
    }

    private fun save(context: Context, items: List<Dhikr>) {
        val array = JSONArray()
        items.forEach { array.put(it.toJson()) }
        prefs(context).edit().putString(KEY_SCHEDULE, array.toString()).apply()
    }

    private fun alarm(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        0,
        Intent(context, DhikrReceiver::class.java).setAction(ACTION_FIRE),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /**
     * Sets the alarm for the next dhikr, on the minute if Android lets the app
     * set exact alarms (the adhan asks for that), else within Android's window.
     */
    fun arm(context: Context) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val pending = alarm(context)
        manager.cancel(pending)
        val now = System.currentTimeMillis()
        val next = load(context).firstOrNull { it.at > now } ?: return
        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()
        try {
            if (exact) {
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.at, pending)
            } else {
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.at, pending)
            }
        } catch (e: SecurityException) {
            // The permission was taken back between the check and the call.
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.at, pending)
        }
    }

    /** The alarm went off: show the latest dhikr that is due, set the next. */
    fun fire(context: Context) {
        val now = System.currentTimeMillis()
        val items = load(context)
        val due = items.lastOrNull { it.at <= now + EARLY_MS }
        save(context, items.filter { it.at > now + EARLY_MS })
        if (due != null) show(context, due)
        arm(context)
    }

    /** The phone restarted (or the app was updated): the card again, if one was waiting, and the next alarm. */
    fun restore(context: Context) {
        val now = System.currentTimeMillis()
        save(context, load(context).filter { it.at > now })
        showing(context)?.let { if (Settings.canDrawOverlays(context)) DhikrCard.show(context, it, closeLabel(context)) }
        arm(context)
    }

    /** Shows [dhikr] now: in the corner if allowed, else as a notification. */
    fun show(context: Context, dhikr: Dhikr, channelName: String? = null, closeLabel: String? = null) {
        channelName?.let { prefs(context).edit().putString(KEY_CHANNEL, it).apply() }
        closeLabel?.let { prefs(context).edit().putString(KEY_CLOSE, it).apply() }
        if (Settings.canDrawOverlays(context)) {
            try {
                DhikrCard.show(context, dhikr, closeLabel(context))
                prefs(context).edit().putString(KEY_SHOWING, dhikr.toJson().toString()).apply()
                return
            } catch (e: Exception) {
                // Android refused the window (a restricted phone): notify instead.
                Log.w(TAG, "card refused", e)
            }
        }
        DhikrNotification.post(context, dhikr, prefs(context).getString(KEY_CHANNEL, null) ?: "Dhikr reminders")
    }

    /** The card was tapped: nothing waits any more. */
    fun dismissed(context: Context) {
        prefs(context).edit().remove(KEY_SHOWING).apply()
    }

    private fun showing(context: Context): Dhikr? {
        val raw = prefs(context).getString(KEY_SHOWING, null) ?: return null
        return try { Dhikr.fromJson(JSONObject(raw)) } catch (e: Exception) { null }
    }

    private fun closeLabel(context: Context) = prefs(context).getString(KEY_CLOSE, null) ?: "Close"
}

/** The alarm, and the phone's restart. */
class DhikrReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        when (intent.action) {
            DhikrSchedule.ACTION_FIRE -> DhikrSchedule.fire(app)
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON" -> DhikrSchedule.restore(app)
        }
    }
}

/**
 * The card at the top right of the screen: the title, the dhikr in Amiri,
 * its meaning if any. One at a time (a new dhikr replaces the words); a tap
 * anywhere on it closes it. The rest of the screen is untouched.
 */
object DhikrCard {
    private var view: View? = null
    private var title: TextView? = null
    private var body: TextView? = null
    private var meaning: TextView? = null

    private fun dp(context: Context, v: Float) =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, context.resources.displayMetrics).toInt()

    private fun font(context: Context, name: String): Typeface? = try {
        // The app's own fonts, from the Flutter assets in the APK.
        Typeface.createFromAsset(context.assets, "flutter_assets/assets/fonts/$name")
    } catch (e: Exception) {
        null
    }

    fun show(context: Context, dhikr: Dhikr, closeLabel: String) {
        val meaningText = dhikr.expanded?.removePrefix(dhikr.body)?.trim()?.ifEmpty { null }
        if (view != null) {
            title?.text = dhikr.title
            body?.text = dhikr.body
            meaning?.text = meaningText
            meaning?.visibility = if (meaningText == null) View.GONE else View.VISIBLE
            view?.contentDescription = "${dhikr.title}. ${dhikr.body}. $closeLabel"
            return
        }
        val dark = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
            Configuration.UI_MODE_NIGHT_YES
        // Rubric's colours (lib/app/theme.dart): raised surface, ink, rubric red.
        val surface = if (dark) 0xFF1E1A15.toInt() else 0xFFFFFFFF.toInt()
        val hairline = if (dark) 0xFF2C2721.toInt() else 0xFFD9D0C0.toInt()
        val ink = if (dark) 0xFFE8E1D2.toInt() else 0xFF1C1915.toInt()
        val inkSecondary = if (dark) 0xFF9C9384.toInt() else 0xFF655E53.toInt()
        val rubric = if (dark) 0xFFD9603F.toInt() else 0xFFB33E24.toInt()

        val metrics = context.resources.displayMetrics
        val cardWidth = minOf((metrics.widthPixels * 0.6f).toInt(), dp(context, 280f))
        val pad = dp(context, 12f)
        val ui = font(context, "IBMPlexSans-Variable.ttf")
        val uiAr = font(context, "IBMPlexSansArabic-Medium.ttf")

        val card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad + dp(context, 2f), pad - dp(context, 2f), pad + dp(context, 2f), pad)
            background = GradientDrawable().apply {
                cornerRadius = dp(context, 14f).toFloat()
                setColor(surface)
                setStroke(dp(context, 1f), hairline)
            }
            isClickable = true
            contentDescription = "${dhikr.title}. ${dhikr.body}. $closeLabel"
        }
        val head = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val titleView = TextView(context).apply {
            text = dhikr.title
            setTextColor(rubric)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            typeface = if (dhikr.title.any { it in '؀'..'ۿ' }) uiAr ?: ui else ui
            maxLines = 1
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        val close = TextView(context).apply {
            text = "✕"
            setTextColor(inkSecondary)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setPadding(dp(context, 12f), 0, 0, 0)
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        head.addView(titleView, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        head.addView(close)
        val bodyView = TextView(context).apply {
            text = dhikr.body
            setTextColor(ink)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            typeface = font(context, "Amiri-Regular.ttf")
            textDirection = View.TEXT_DIRECTION_RTL
            gravity = Gravity.START
            setLineSpacing(0f, 1.15f)
            maxWidth = cardWidth - 2 * pad
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        val meaningView = TextView(context).apply {
            text = meaningText
            setTextColor(inkSecondary)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            typeface = ui
            maxLines = 2
            ellipsize = android.text.TextUtils.TruncateAt.END
            maxWidth = cardWidth - 2 * pad
            visibility = if (meaningText == null) View.GONE else View.VISIBLE
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        val fill = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        card.addView(head, fill)
        card.addView(bodyView, fill)
        card.addView(meaningView, fill)

        val manager = context.getSystemService(WindowManager::class.java)
        val statusBar = context.resources.getIdentifier("status_bar_height", "dimen", "android")
            .let { if (it > 0) context.resources.getDimensionPixelSize(it) else dp(context, 24f) }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            // Never takes the keyboard or the back key; touches outside it go
            // to the app underneath.
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            // Top right, as asked, whatever the language's direction.
            gravity = Gravity.TOP or Gravity.RIGHT
            x = dp(context, 12f)
            y = statusBar + dp(context, 8f)
            setTitle("Rafiq dhikr")
        }
        card.setOnClickListener {
            card.animate().alpha(0f).setDuration(150).withEndAction { hide(context) }.start()
        }
        card.alpha = 0f
        manager.addView(card, params)
        card.animate().alpha(1f).setDuration(200).start()
        view = card
        title = titleView
        body = bodyView
        meaning = meaningView
    }

    fun hide(context: Context) {
        view?.let {
            try {
                context.getSystemService(WindowManager::class.java).removeView(it)
            } catch (_: Exception) {
                // Already gone with its window.
            }
        }
        view = null
        title = null
        body = null
        meaning = null
        DhikrSchedule.dismissed(context)
    }
}

/**
 * Without "Appear on top": a notification on the Dhikr reminders channel that
 * stays in the shade until it is tapped (it opens the adhkar) or swiped away.
 * One at a time: a new dhikr replaces the last.
 */
object DhikrNotification {
    private const val CHANNEL = "adhkar"

    /** Outside the ids flutter_local_notifications used for dhikr (1000–1499). */
    private const val ID = 1500

    /**
     * A group of its own: Android 16 marks an ungrouped notification silent
     * (and keeps it out of the top of the screen) when another of the app's
     * is already in the shade.
     */
    private const val GROUP = "dhikr"
    const val EXTRA_OPEN = "rafiq_open"

    fun post(context: Context, dhikr: Dhikr, channelName: String) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && manager.getNotificationChannel(CHANNEL) == null) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, channelName, NotificationManager.IMPORTANCE_HIGH).apply {
                    setSound(null, null)
                    enableVibration(false)
                },
            )
        }
        val open = PendingIntent.getActivity(
            context,
            ID,
            Intent(context, MainActivity::class.java)
                .putExtra(EXTRA_OPEN, "adhkar")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_rafiq)
            .setContentTitle(dhikr.title)
            .setContentText(dhikr.body)
            .setStyle(Notification.BigTextStyle().bigText(dhikr.expanded ?: dhikr.body))
            .setCategory(Notification.CATEGORY_REMINDER)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setGroup(GROUP)
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        manager.notify(ID, notification)
    }
}
