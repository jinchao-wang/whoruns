package com.wjc.whoruns

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 开机后把闹钟重新排上。
 *
 * 重启会清掉所有闹钟，不重排的话告警就永远停了。
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }
        if (!AuditNotifier.isEnabled(context)) return
        AuditNotifier.setSchedule(context, true, AuditNotifier.everyMinutes(context))
    }
}
