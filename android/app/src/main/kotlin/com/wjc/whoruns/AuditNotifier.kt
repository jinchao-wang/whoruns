package com.wjc.whoruns

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.concurrent.TimeUnit

/**
 * 告警：定期看一眼有没有新的偷跑证据，有就发通知。
 *
 * 用的是**不精确**的重复闹钟（`setInexactRepeating`）：
 * 审计这类事不需要精确到分钟，而且不精确闹钟在 Android 12+ 不需要额外权限，
 * 不会给用户「闹钟/日历」那种敏感提示。
 */
object AuditNotifier {

    const val CHANNEL_ID = "audit_alerts"

    /** shared_preferences 插件在 Android 上的文件名和键前缀。 */
    private const val PREF_SUFFIX = "_preferences"
    private const val KEY_ENABLED = "flutter.alert_enabled"
    private const val KEY_INTERVAL = "flutter.alert_every_minutes"

    private const val REQUEST_ALARM = 9101
    private const val REQUEST_NOTIFICATION = 9102

    fun setSchedule(context: Context, enabled: Boolean, everyMinutes: Int) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val pending = alarmIntent(context)
        manager.cancel(pending)
        if (!enabled) return
        val interval = TimeUnit.MINUTES.toMillis(everyMinutes.coerceAtLeast(15).toLong())
        manager.setInexactRepeating(
            AlarmManager.RTC_WAKEUP,
            System.currentTimeMillis() + interval,
            interval,
            pending,
        )
    }

    private fun alarmIntent(context: Context): PendingIntent {
        val intent = Intent(context, AuditAlarmReceiver::class.java)
        return PendingIntent.getBroadcast(
            context,
            REQUEST_ALARM,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun isEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_ENABLED, false)

    fun everyMinutes(context: Context): Int =
        prefs(context).getInt(KEY_INTERVAL, 30)

    private fun prefs(context: Context) =
        context.getSharedPreferences(context.packageName + PREF_SUFFIX, Context.MODE_PRIVATE)

    /** 检查最近有没有新的硬证据，有就通知。 */
    fun checkAndNotify(context: Context) {
        if (!UsageAudit.hasUsageAccess(context)) return
        val since = TimeUnit.MINUTES.toMillis(everyMinutes(context).toLong())
        val evidence = UsageAudit.recentEvidence(context, since)
        val hard = evidence.filter {
            it.type == EvidenceType.LOCK_SCREEN_BACKGROUND_START ||
                it.type == EvidenceType.LOCK_SCREEN_RESUME ||
                it.type == EvidenceType.FOCUS_STEAL
        }
        if (hard.isEmpty()) return

        val names = hard.map { label(context, it.packageName) }.distinct().take(3)
        val body = buildString {
            append(names.joinToString("、"))
            append(" 在你没操作手机的时候自己动了起来")
            if (hard.size > names.size) {
                append("，还有 ${hard.size - names.size} 个")
            }
            append("。点开看看。")
        }
        show(context, "有 App 在偷跑", body)
    }

    private fun label(context: Context, pkg: String): String {
        return try {
            val pm = context.packageManager
            pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
        } catch (t: Throwable) {
            pkg
        }
    }

    fun show(context: Context, title: String, body: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "偷跑告警",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "发现有 App 在你没操作手机时自己活动"
            }
            manager.createNotificationChannel(channel)
        }

        val launchIntent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }

        val contentIntent = launchIntent?.let {
            PendingIntent.getActivity(
                context,
                REQUEST_NOTIFICATION,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        builder.setSmallIcon(com.wjc.whoruns.R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
        if (contentIntent != null) {
            builder.setContentIntent(contentIntent)
        }

        try {
            manager.notify(REQUEST_NOTIFICATION, builder.build())
        } catch (t: Throwable) {
            // 没有通知权限等情况，忽略。
        }
    }
}
