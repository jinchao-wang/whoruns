package com.wjc.whoruns

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 定期审计的闹钟接收器。
 *
 * 收到就查一次最近这段时间的证据，有硬证据就发通知。
 * 查数据要几十毫秒，所以放到后台线程，再用 `goAsync()` 保住广播的生命周期。
 */
class AuditAlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        if (!AuditNotifier.isEnabled(context)) return
        val pending = goAsync()
        Thread {
            try {
                AuditNotifier.checkAndNotify(context)
            } catch (t: Throwable) {
                // 一次失败不影响下一次。
            } finally {
                pending.finish()
            }
        }.start()
    }
}
