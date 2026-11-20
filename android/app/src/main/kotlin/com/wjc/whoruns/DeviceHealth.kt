package com.wjc.whoruns

import android.content.Context
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
import java.io.File

/**
 * 本机健康信息。
 *
 * iOS 上是主要用途（iOS 读不到别的 App 的用量，只能先看清自己这台机器）；
 * Android 上顺带返回，方便两边用同一套展示。
 */
object DeviceHealth {

    fun snapshot(context: Context): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        out.putAll(battery(context))
        out.putAll(storage())
        out.putAll(thermal(context))
        return out
    }

    private fun battery(context: Context): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        try {
            val manager = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
            if (manager != null) {
                val capacity = manager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                out["batteryLevel"] = if (capacity in 0..100) capacity else null
                val status = manager.getIntProperty(BatteryManager.BATTERY_PROPERTY_STATUS)
                out["charging"] = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == BatteryManager.BATTERY_STATUS_FULL
            }
        } catch (t: Throwable) {
            // 拿不到就当没有这一项
        }
        return out
    }

    private fun storage(): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        try {
            val stat = StatFs(Environment.getDataDirectory().path)
            val total = stat.totalBytes
            val free = stat.availableBytes
            out["storageTotalBytes"] = total
            out["storageFreeBytes"] = free
            out["storageUsedRatio"] =
                if (total > 0) (1.0 - free.toDouble() / total).toDouble() else null
        } catch (t: Throwable) {
            // 忽略
        }
        return out
    }

    private fun thermal(context: Context): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val power = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                if (power != null) {
                    out["thermalStatus"] = power.currentThermalStatus
                }
            } catch (t: Throwable) {
                // 忽略
            }
        }
        return out
    }
}
