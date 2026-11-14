package app.rafiq.rafiq

import android.app.AlarmManager
import android.app.KeyguardManager
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
import android.os.PowerManager
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
import java.util.Calendar
import kotlin.random.Random

/**
 * The dhikr reminders, on the Android side.
 *
 * Dart sends a rule, not a list of times ([DhikrPlan], from
 * lib/services/reminders.dart): a dhikr every few hours in the day, and the
 * adhkar to choose from. The phone follows it on its own for as long as it
 * is on, whether or not Rafiq is opened again: one alarm at a time, each
 * that fires setting the next ([DhikrSchedule]), set again after a restart
 * of the phone ([DhikrReceiver]).
 *
 * Which dhikr comes is drawn when it comes, from a shuffled bag: every one
 * of the adhkar before any comes again, never the same twice in a row.
 *
 * It is shown in a small card at the top right of the screen, over any app,
 * until it is tapped ([DhikrCard]); that needs the user's "Appear on top"
 * permission. Without it, or while the phone is locked (where the card
 * cannot be), it is also a notification that waits on the lock screen and
 * in the shade until it is tapped or swiped away ([DhikrNotification]).
 */
data class DhikrText(val id: String, val arabic: String, val said: String?, val meaning: String?) {
    /** Everything, one per line: the expanded notification. */
    val expanded: String get() = listOfNotNull(arabic, said, meaning).joinToString("\n")

    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("arabic", arabic)
        .put("said", said ?: JSONObject.NULL)
        .put("meaning", meaning ?: JSONObject.NULL)

    companion object {
        fun fromJson(o: JSONObject) = DhikrText(
            id = o.getString("id"),
            arabic = o.getString("arabic"),
            said = if (o.isNull("said")) null else o.getString("said"),
            meaning = if (o.isNull("meaning")) null else o.getString("meaning"),
        )

        fun fromMap(m: Map<*, *>) = DhikrText(
            id = m["id"] as String,
            arabic = m["arabic"] as String,
            said = m["said"] as String?,
            meaning = m["meaning"] as String?,
        )
    }
}

/**
 * The rule: a dhikr on the hour, every [everyHours] hours from [fromHour] to
 * [toHour] each day (local time, as the phone's clock reads it then, so a
 * change of time zone or of clocks follows), none at or before [quietUntil].
 */
data class DhikrPlan(
    val title: String,
    val everyHours: Int,
    val fromHour: Int,
    val toHour: Int,
    val quietUntil: Long?,
    val items: List<DhikrText>,
) {
    private val stride get() = everyHours.coerceAtLeast(1)

    /** The slots of the day [days] days from [t]'s day, in order. */
    private fun slotsOfDay(t: Long, days: Int): List<Long> {
        val day = Calendar.getInstance().apply {
            timeInMillis = t
            add(Calendar.DAY_OF_YEAR, days)
        }
        return (fromHour..toHour step stride).map { hour ->
            (day.clone() as Calendar).apply {
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }.timeInMillis
        }
    }

    /** The first slot after [t], and after [quietUntil]. */
    fun next(t: Long): Long? {
        val after = maxOf(t, quietUntil ?: Long.MIN_VALUE)
        for (days in 0..2) slotsOfDay(after, days).firstOrNull { it > after }?.let { return it }
        return null
    }

    /** The last slot at or before [t]. */
    fun latest(t: Long): Long? {
        for (days in 0 downTo -1) slotsOfDay(t, days).lastOrNull { it <= t }?.let { return it }
        return null
    }

    fun toJson(): JSONObject = JSONObject()
        .put("title", title)
        .put("every", everyHours)
        .put("from", fromHour)
        .put("to", toHour)
        .put("quietUntil", quietUntil ?: JSONObject.NULL)
        .put("items", JSONArray().apply { items.forEach { put(it.toJson()) } })

    companion object {
        fun fromJson(o: JSONObject): DhikrPlan {
            val items = o.getJSONArray("items")
            return DhikrPlan(
                title = o.getString("title"),
                everyHours = o.getInt("every"),
                fromHour = o.getInt("from"),
                toHour = o.getInt("to"),
                quietUntil = if (o.isNull("quietUntil")) null else o.getLong("quietUntil"),
                items = (0 until items.length()).map { DhikrText.fromJson(items.getJSONObject(it)) },
            )
        }

        fun fromMap(m: Map<*, *>) = DhikrPlan(
            title = m["title"] as String,
            everyHours = (m["every"] as Number).toInt(),
            fromHour = (m["from"] as Number).toInt(),
            toHour = (m["to"] as Number).toInt(),
            quietUntil = (m["quietUntil"] as Number?)?.toLong(),
            items = (m["items"] as List<*>).map { DhikrText.fromMap(it as Map<*, *>) },
        )
    }
}

object DhikrSchedule {
    private const val TAG = "RafiqDhikr"
    private const val PREFS = "rafiq_dhikr"
    private const val KEY_PLAN = "plan"
    private const val KEY_BAG = "bag"
    private const val KEY_LAST_ID = "last_id"
    private const val KEY_LAST_SLOT = "last_slot"
    private const val KEY_SHOWING = "showing"
    private const val KEY_CHANNEL = "channel"
    private const val KEY_CLOSE = "close"

    /** Up to 0.9: the next two weeks of adhkar, each with its time. */
    private const val KEY_LEGACY_SCHEDULE = "schedule"
    const val ACTION_FIRE = "app.rafiq.rafiq.DHIKR"

    /** An alarm this close before its slot counts as on time. */
    private const val EARLY_MS = 60_000L
    private const val HOUR_MS = 3_600_000L

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /**
     * Follows [plan] from now on (null: no more adhkar) and sets the next
     * alarm. Turned on just now: slots already past are not missed ones.
     */
    fun replace(context: Context, plan: DhikrPlan?, channelName: String, closeLabel: String) {
        val prefs = prefs(context)
        val edit = prefs.edit()
            .remove(KEY_LEGACY_SCHEDULE)
            .putString(KEY_CHANNEL, channelName)
            .putString(KEY_CLOSE, closeLabel)
        if (plan == null) {
            edit.remove(KEY_PLAN)
        } else {
            if (!prefs.contains(KEY_PLAN)) edit.putLong(KEY_LAST_SLOT, System.currentTimeMillis())
            edit.putString(KEY_PLAN, plan.toJson().toString())
        }
        edit.apply()
        arm(context)
    }

    private fun plan(context: Context): DhikrPlan? {
        val raw = prefs(context).getString(KEY_PLAN, null) ?: return null
        return try {
            DhikrPlan.fromJson(JSONObject(raw))
        } catch (e: Exception) {
            // Unreadable: nothing until the app sends the plan again.
            Log.w(TAG, "unreadable plan", e)
            null
        }
    }

    private fun alarm(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        0,
        Intent(context, DhikrReceiver::class.java).setAction(ACTION_FIRE),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /**
     * Sets the alarm for the next slot, on the minute if Android lets the app
     * set exact alarms (the adhan asks for that), else within Android's window.
     */
    fun arm(context: Context) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val pending = alarm(context)
        manager.cancel(pending)
        val plan = plan(context) ?: return
        if (plan.items.isEmpty()) return
        val after = maxOf(System.currentTimeMillis(), prefs(context).getLong(KEY_LAST_SLOT, 0L))
        val next = plan.next(after) ?: return
        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()
        try {
            if (exact) {
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, pending)
            } else {
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, pending)
            }
        } catch (e: SecurityException) {
            // The permission was taken back between the check and the call.
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, pending)
        }
    }

    /** The alarm went off: the dhikr that is due, then the next alarm. */
    fun fire(context: Context) {
        catchUp(context)
        arm(context)
    }

    /**
     * Shows one dhikr for the latest slot that has come and was not shown,
     * while it is still its turn (before the next slot would have come). An
     * alarm Android held back while the phone slept still brings its dhikr
     * when the phone wakes; one held back into the night brings none, and a
     * few missed slots bring one dhikr, not a pile.
     */
    private fun catchUp(context: Context) {
        val plan = plan(context) ?: return
        if (plan.items.isEmpty()) return
        val now = System.currentTimeMillis()
        val slot = plan.latest(now + EARLY_MS) ?: return
        val prefs = prefs(context)
        if (slot <= prefs.getLong(KEY_LAST_SLOT, 0L)) return
        prefs.edit().putLong(KEY_LAST_SLOT, slot).apply()
        if (plan.quietUntil != null && slot <= plan.quietUntil) return
        if (now - slot >= plan.everyHours.coerceAtLeast(1) * HOUR_MS) return // past its turn
        deliver(context, plan.title, draw(context, plan.items))
    }

    /**
     * The next dhikr from the bag: all of [items] in a random order, then
     * shuffled again, the first of a new round never the last of the one
     * before. Kept across alarms; adhkar no longer offered drop out of it,
     * new ones join at the next shuffle.
     */
    private fun draw(context: Context, items: List<DhikrText>): DhikrText {
        val prefs = prefs(context)
        val byId = items.associateBy { it.id }
        val last = prefs.getString(KEY_LAST_ID, null)
        val bag = try {
            val array = JSONArray(prefs.getString(KEY_BAG, "[]"))
            (0 until array.length()).map { array.getString(it) }.filter { it in byId }.toMutableList()
        } catch (e: Exception) {
            mutableListOf()
        }
        if (bag.isEmpty()) {
            bag.addAll(byId.keys.shuffled())
            if (bag.size > 1 && bag[0] == last) bag.add(bag.removeAt(0))
        }
        val id = bag.removeAt(0)
        prefs.edit()
            .putString(KEY_BAG, JSONArray(bag).toString())
            .putString(KEY_LAST_ID, id)
            .apply()
        return byId.getValue(id)
    }

    /** The phone restarted (or the app was updated): the card again, if one was waiting, a missed dhikr, the next alarm. */
    fun restore(context: Context) {
        showing(context)?.let { (title, text) ->
            if (Settings.canDrawOverlays(context)) {
                try {
                    DhikrCard.show(context, title, text, closeLabel(context))
                } catch (e: Exception) {
                    Log.w(TAG, "card refused", e)
                }
            }
        }
        catchUp(context)
        arm(context)
    }

    /** A dhikr now, drawn from [plan]'s adhkar: the "Show one now" button. */
    fun showNow(context: Context, plan: DhikrPlan, channelName: String?, closeLabel: String?) {
        val edit = prefs(context).edit()
        channelName?.let { edit.putString(KEY_CHANNEL, it) }
        closeLabel?.let { edit.putString(KEY_CLOSE, it) }
        edit.apply()
        if (plan.items.isEmpty()) return
        deliver(context, plan.title, draw(context, plan.items))
    }

    /**
     * In the corner if allowed. Also a notification if the card cannot be
     * shown, or if the phone is locked or asleep: the card waits for the
     * unlock, but the notification is on the lock screen at once, and stays
     * in the shade even if Android ends the app before the phone is used.
     */
    private fun deliver(context: Context, title: String, text: DhikrText) {
        val power = context.getSystemService(PowerManager::class.java)
        val keyguard = context.getSystemService(KeyguardManager::class.java)
        val away = power?.isInteractive == false || keyguard?.isKeyguardLocked == true
        var onScreen = false
        if (Settings.canDrawOverlays(context)) {
            try {
                DhikrCard.show(context, title, text, closeLabel(context))
                prefs(context).edit()
                    .putString(KEY_SHOWING, text.toJson().put("title", title).toString())
                    .apply()
                onScreen = true
            } catch (e: Exception) {
                // Android refused the window (a restricted phone): notify instead.
                Log.w(TAG, "card refused", e)
            }
        }
        if (!onScreen || away) {
            DhikrNotification.post(context, title, text, prefs(context).getString(KEY_CHANNEL, null) ?: "Dhikr reminders")
        } else {
            // A newer dhikr in the corner: an older one in the shade goes.
            DhikrNotification.cancel(context)
        }
    }

    /** The dhikr was seen (its card or its notification tapped): nothing waits any more. */
    fun dismissed(context: Context) {
        prefs(context).edit().remove(KEY_SHOWING).apply()
    }

    private fun showing(context: Context): Pair<String, DhikrText>? {
        val raw = prefs(context).getString(KEY_SHOWING, null) ?: return null
        return try {
            val o = JSONObject(raw)
            o.getString("title") to DhikrText.fromJson(o)
        } catch (e: Exception) {
            null
        }
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
 * and how to say it in Latin letters if the interface is not Arabic. One at
 * a time (a new dhikr replaces the words); a tap anywhere on it closes it,
 * and its notification with it. The rest of the screen is untouched.
 */
object DhikrCard {
    private var view: View? = null
    private var title: TextView? = null
    private var body: TextView? = null
    private var said: TextView? = null

    private fun dp(context: Context, v: Float) =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, context.resources.displayMetrics).toInt()

    private fun font(context: Context, name: String): Typeface? = try {
        // The app's own fonts, from the Flutter assets in the APK.
        Typeface.createFromAsset(context.assets, "flutter_assets/assets/fonts/$name")
    } catch (e: Exception) {
        null
    }

    private fun describe(titleText: String, text: DhikrText, closeLabel: String) =
        listOfNotNull(titleText, text.arabic, text.said, closeLabel).joinToString(". ")

    fun show(context: Context, titleText: String, text: DhikrText, closeLabel: String) {
        if (view != null) {
            title?.text = titleText
            body?.text = text.arabic
            said?.text = text.said
            said?.visibility = if (text.said == null) View.GONE else View.VISIBLE
            view?.contentDescription = describe(titleText, text, closeLabel)
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
            contentDescription = describe(titleText, text, closeLabel)
        }
        val head = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val titleView = TextView(context).apply {
            this.text = titleText
            setTextColor(rubric)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            typeface = if (titleText.any { it in '؀'..'ۿ' }) uiAr ?: ui else ui
            maxLines = 1
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        val close = TextView(context).apply {
            this.text = "✕"
            setTextColor(inkSecondary)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setPadding(dp(context, 12f), 0, 0, 0)
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        head.addView(titleView, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        head.addView(close)
        val bodyView = TextView(context).apply {
            this.text = text.arabic
            setTextColor(ink)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            typeface = font(context, "Amiri-Regular.ttf")
            textDirection = View.TEXT_DIRECTION_RTL
            gravity = Gravity.START
            setLineSpacing(0f, 1.15f)
            maxWidth = cardWidth - 2 * pad
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        // How to say it, left to right under the Arabic.
        val saidView = TextView(context).apply {
            this.text = text.said
            setTextColor(inkSecondary)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.create(ui, Typeface.ITALIC)
            textDirection = View.TEXT_DIRECTION_LTR
            maxLines = 3
            ellipsize = android.text.TextUtils.TruncateAt.END
            maxWidth = cardWidth - 2 * pad
            visibility = if (text.said == null) View.GONE else View.VISIBLE
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        val fill = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        card.addView(head, fill)
        card.addView(bodyView, fill)
        card.addView(saidView, fill)

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
            card.animate().alpha(0f).setDuration(150).withEndAction {
                hide(context)
                DhikrNotification.cancel(context)
            }.start()
        }
        card.alpha = 0f
        manager.addView(card, params)
        card.animate().alpha(1f).setDuration(200).start()
        view = card
        title = titleView
        body = bodyView
        said = saidView
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
        said = null
        DhikrSchedule.dismissed(context)
    }
}

/**
 * The dhikr as a notification on the Dhikr reminders channel: on the lock
 * screen, then in the shade until it is tapped (it opens the adhkar) or
 * swiped away. One at a time: a new dhikr replaces the last.
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

    fun post(context: Context, title: String, text: DhikrText, channelName: String) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && manager.getNotificationChannel(CHANNEL) == null) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, channelName, NotificationManager.IMPORTANCE_HIGH).apply {
                    setSound(null, null)
                    enableVibration(false)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
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
            .setContentTitle(title)
            .setContentText(text.arabic)
            .setStyle(Notification.BigTextStyle().bigText(text.expanded))
            .setCategory(Notification.CATEGORY_REMINDER)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setGroup(GROUP)
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        try {
            manager.notify(ID, notification)
        } catch (e: SecurityException) {
            // Notifications not allowed (Android 13+): the card alone, then.
            Log.w("RafiqDhikr", "notification refused", e)
        }
    }

    fun cancel(context: Context) {
        context.getSystemService(NotificationManager::class.java)?.cancel(ID)
    }
}
