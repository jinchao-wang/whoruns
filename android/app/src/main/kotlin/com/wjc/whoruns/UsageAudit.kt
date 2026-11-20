package com.wjc.whoruns

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import java.util.concurrent.TimeUnit

/**
 * 从系统里把「谁在偷跑」的事实捞出来。
 *
 * 这里只做**取数**，不做判断：
 * 判断（怎么算可疑）交给 [AuditClassifier] 和 Dart 侧的评分引擎，
 * 便于单测，也便于以后换算法。
 */
object UsageAudit {

    private const val BACKGROUND_LOCATION = "android.permission.ACCESS_BACKGROUND_LOCATION"

    /**
     * 「使用情况访问」这个 AppOp 的名字。
     *
     * 直接写字面量而不是用 `AppOpsManager.OPSTR_GET_USAGE_STATS`：
     * 不同 Android 版本里这个常量的公开程度不一样，
     * 写字面量可以保证任何 compileSdk 都能编过（名字本身是稳定的）。
     */
    private const val OP_GET_USAGE_STATS = "android:get_usage_stats"

    /** 用户有没有给「使用情况访问权限」。 */
    fun hasUsageAccess(context: Context): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
        if (appOps != null) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val mode = appOps.unsafeCheckOpNoThrow(
                        OP_GET_USAGE_STATS,
                        Process.myUid(),
                        context.packageName,
                    )
                    if (mode == AppOpsManager.MODE_ALLOWED) return true
                }
            } catch (t: Throwable) {
                // 有些 ROM 的 AppOps 实现不一样，走下面的实测兜底。
            }
        }
        return probeUsageStats(context)
    }

    /**
     * 实测兜底：真查一次，查得到数据就说明有权限。
     *
     * 查不到不一定代表没权限（刚开机还没产生用量），
     * 所以这条只在别的路都说不准时才作为参考。
     */
    private fun probeUsageStats(context: Context): Boolean {
        return try {
            val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
                ?: return false
            val now = System.currentTimeMillis()
            val stats = manager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                now - TimeUnit.DAYS.toMillis(2),
                now,
            )
            stats.isNotEmpty()
        } catch (t: Throwable) {
            false
        }
    }

    /**
     * 跑一次审计，把结果整理成能直接给 Dart 的 Map。
     *
     * @param sinceHours 回溯多少小时。
     */
    fun collect(context: Context, sinceHours: Int): Map<String, Any?> {
        val now = System.currentTimeMillis()
        val begin = now - TimeUnit.HOURS.toMillis(sinceHours.toLong())
        val usageManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
            ?: return emptyResult(now, begin)

        val rawEvents = readEvents(usageManager, begin, now)
        val evidence = AuditClassifier.classify(rawEvents)

        val usage = readUsage(usageManager, begin, now)
        // 后台时长自己算：系统那个 API（getTotalTimeInBackground）已经被移除了。
        val background = AuditClassifier.backgroundMillis(rawEvents, now)
        val uidByPackage = uidsOf(context, usage.keys)
        val traffic = readTraffic(context, begin, now, uidByPackage)
        val selfPackage = context.packageName

        val packages = LinkedHashSet<String>()
        packages.addAll(usage.keys)
        packages.addAll(evidence.map { it.packageName })
        // 有后台定位权限的 App 也列出来：哪怕这段时间没用过，
        // 用户关心的就是「谁有这个权限」。
        packages.addAll(findBackgroundLocationApps(context))

        val apps = ArrayList<Map<String, Any?>>()
        for (pkg in packages) {
            if (pkg == selfPackage) continue
            val info = usage[pkg]
            val pkgEvidence = evidence.filter { it.packageName == pkg }
            val trafficBytes = traffic[pkg]
            val hasBgLocation = hasDeclaredBackgroundLocation(context, pkg)
            val grantedBgLocation = isBackgroundLocationGranted(context, pkg)

            apps.add(
                mapOf(
                    "package" to pkg,
                    "label" to appLabel(context, pkg),
                    "foregroundMillis" to (info?.foregroundMillis ?: 0L),
                    "backgroundMillis" to (background[pkg] ?: 0L),
                    // -1 表示这台系统读不到分 App 流量（不是 0 流量）。
                    "trafficBytes" to (trafficBytes ?: -1L),
                    "hasBackgroundLocation" to hasBgLocation,
                    "backgroundLocationGranted" to grantedBgLocation,
                    "isSystemApp" to isSystemApp(context, pkg),
                    "evidence" to pkgEvidence.map { record ->
                        mapOf(
                            "signal" to signalName(record.type),
                            "level" to levelOf(record.type),
                            "ts" to record.timestamp,
                            "detail" to record.detail,
                            "magnitude" to 1.0,
                        )
                    },
                )
            )
        }

        return mapOf(
            "scannedAt" to now,
            "rangeStart" to begin,
            "rangeEnd" to now,
            "trafficAvailable" to traffic.isNotEmpty(),
            "apps" to apps,
        )
    }

    private fun emptyResult(now: Long, begin: Long): Map<String, Any?> = mapOf(
        "scannedAt" to now,
        "rangeStart" to begin,
        "rangeEnd" to now,
        "trafficAvailable" to false,
        "apps" to emptyList<Map<String, Any?>>(),
    )

    /**
     * 最近一段时间的证据（只取事件，不查流量）。
     *
     * 告警用这个：轻、快，不打扰用户。
     */
    fun recentEvidence(context: Context, sinceMillis: Long): List<EvidenceRecord> {
        val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
            ?: return emptyList()
        val now = System.currentTimeMillis()
        val events = readEvents(manager, now - sinceMillis, now)
        return AuditClassifier.classify(events)
    }

    /** 把框架事件翻译成自己的事件类型，丢掉用不上的。
     *
     * 事件类型的常量全部走反射拿：
     * `UsageEvents.Event` 里有几个常量（ACTIVITY_STARTED、USER_UNLOCKED）
     * 是隐藏 API，不同 Android 版本的公开程度还不一样。
     * 反射拿的好处是**编译期不受 SDK 公开面影响**，取不到就少一路信号，
     * 不会让整个 App 编译不过或者运行崩溃。
     */
    private fun readEvents(manager: UsageStatsManager, begin: Long, end: Long): List<RawEvent> {
        val out = ArrayList<RawEvent>()
        try {
            val typeMap = eventTypeMap()
            if (typeMap.isEmpty()) return out
            val events = manager.queryEvents(begin, end)
            val event = UsageEvents.Event()
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                val type = typeMap[event.eventType] ?: continue
                val pkg = event.packageName ?: continue
                out.add(RawEvent(type, pkg, event.timeStamp))
            }
        } catch (t: Throwable) {
            // 拿不到事件就只保留用量统计，不让整次审计失败。
        }
        return out
    }

    /** 系统事件类型值 -> 我们自己的事件类型。 */
    private fun eventTypeMap(): Map<Int, AuditEventType> {
        if (eventTypeCache != null) return eventTypeCache!!
        val map = HashMap<Int, AuditEventType>()
        constantValue("ACTIVITY_RESUMED")?.let { map[it] = AuditEventType.ACTIVITY_RESUMED }
        constantValue("ACTIVITY_PAUSED")?.let { map[it] = AuditEventType.ACTIVITY_PAUSED }
        constantValue("ACTIVITY_STOPPED")?.let { map[it] = AuditEventType.ACTIVITY_STOPPED }
        constantValue("ACTIVITY_STARTED")?.let { map[it] = AuditEventType.ACTIVITY_STARTED }
        constantValue("SCREEN_INTERACTIVE")?.let { map[it] = AuditEventType.SCREEN_INTERACTIVE }
        constantValue("SCREEN_NON_INTERACTIVE")?.let { map[it] = AuditEventType.SCREEN_NON_INTERACTIVE }
        constantValue("USER_PRESENT")?.let { map[it] = AuditEventType.USER_PRESENT }
        constantValue("USER_UNLOCKED")?.let { map[it] = AuditEventType.USER_UNLOCKED }
        eventTypeCache = map
        return map
    }

    private var eventTypeCache: Map<Int, AuditEventType>? = null

    /** 反射读取 `UsageEvents.Event` 里的 int 常量。取不到就返回 null。 */
    private fun constantValue(name: String): Int? {
        return try {
            val field = UsageEvents.Event::class.java.getDeclaredField(name)
            field.isAccessible = true
            field.getInt(null)
        } catch (t: Throwable) {
            null
        }
    }

    /** 每个包的前台时长。后台时长由 [AuditClassifier.backgroundMillis] 从事件流算。 */
    private fun readUsage(
        manager: UsageStatsManager,
        begin: Long,
        end: Long,
    ): Map<String, UsageEntry> {
        val out = HashMap<String, UsageEntry>()
        try {
            val stats = manager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, begin, end)
            for (stat in stats) {
                val pkg = stat.packageName ?: continue
                val foreground = stat.totalTimeInForeground
                val existing = out[pkg]
                out[pkg] = if (existing == null) {
                    UsageEntry(foreground)
                } else {
                    UsageEntry(existing.foregroundMillis + foreground)
                }
            }
        } catch (t: Throwable) {
            // 权限被回收时这里会抛，忽略即可。
        }
        return out
    }

    /**
     * 包名 -> UID。
     *
     * 流量是按 UID 统计的，所以要先拿到每个包的 UID。
     * 一次 `getApplicationInfo` 就够，不用遍历所有应用。
     */
    private fun uidsOf(context: Context, packages: Collection<String>): Map<String, Int> {
        val out = HashMap<String, Int>()
        try {
            val pm = context.packageManager
            for (pkg in packages) {
                try {
                    val info = pm.getApplicationInfo(pkg, 0)
                    out[pkg] = info.uid
                } catch (t: Throwable) {
                    // 拿不到就跳过这个 App。
                }
            }
        } catch (t: Throwable) {
            // 忽略
        }
        return out
    }

    /**
     * 分 App 的流量。
     *
     * ## 为什么用反射
     *
     * 这一组 API 在 Android 各版本里改动频繁：
     * `NetworkStatsManager.queryStatsForDevice()` 从 API 29 起废弃，在新 SDK 里已经取不到；
     * `NetworkStatsManager` 本身还搬过家（`android.app.usage` → `android.net.netstats`）。
     * 直接引用这些符号，编译期就会被 SDK 的公开面卡住。
     *
     * 所以这里**一个类型名都不写死**：运行时按名字找类和方法，找到就用，
     * 找不到就降级成「读不到分 App 流量」。Dart 侧会明确显示读不到，不会假装是 0。
     */
    private fun readTraffic(
        context: Context,
        begin: Long,
        end: Long,
        uidByPackage: Map<String, Int>,
    ): Map<String, Long> {
        val out = HashMap<String, Long>()
        val service = context.getSystemService(Context.NETWORK_STATS_SERVICE) ?: return out
        val managerClass = findClass(
            "android.app.usage.NetworkStatsManager",
            "android.net.netstats.NetworkStatsManager",
        ) ?: return out
        val method = try {
            managerClass.methods.firstOrNull {
                it.name == "queryStatsForUid" && it.parameterTypes.size == 3
            }
        } catch (t: Throwable) {
            null
        } ?: return out

        for ((pkg, uid) in uidByPackage) {
            try {
                val stats = method.invoke(service, uid, begin, end) ?: continue
                val bytes = sumBucketBytes(stats)
                if (bytes > 0) out[pkg] = bytes
            } catch (t: Throwable) {
                // 这个 UID 读不到就跳过。
            }
        }
        return out
    }

    /** 按名字找类，第一个找到的返回。 */
    private fun findClass(vararg names: String): Class<*>? {
        for (name in names) {
            try {
                return Class.forName(name)
            } catch (t: Throwable) {
                // 试下一个。
            }
        }
        return null
    }

    /** NetworkStats -> 所有 bucket 的收发字节之和。 */
    private fun sumBucketBytes(stats: Any): Long {
        var bytes = 0L
        try {
            val bucketsMethod =
                stats.javaClass.methods.firstOrNull { it.name == "getUsageStats" } ?: return bytes
            val buckets = bucketsMethod.invoke(stats) as? Collection<*> ?: return bytes
            for (bucket in buckets) {
                if (bucket == null) continue
                bytes += longValue(bucket, "getRxBytes") + longValue(bucket, "getTxBytes")
            }
        } catch (t: Throwable) {
            // 读不到就当没有。
        }
        return bytes
    }

    private fun longValue(target: Any, methodName: String): Long {
        return try {
            val method = target.javaClass.methods.firstOrNull { it.name == methodName } ?: return 0L
            (method.invoke(target) as? Number)?.toLong() ?: 0L
        } catch (t: Throwable) {
            0L
        }
    }

    /** 声明了后台定位权限、并且拿到了授权的 App。 */
    private fun findBackgroundLocationApps(context: Context): List<String> {
        val out = ArrayList<String>()
        try {
            val pm = context.packageManager
            val installed = pm.getInstalledApplications(0)
            for (info in installed) {
                if (isBackgroundLocationGranted(context, info.packageName)) {
                    out.add(info.packageName)
                }
            }
        } catch (t: Throwable) {
            // 忽略
        }
        return out
    }

    private fun hasDeclaredBackgroundLocation(context: Context, pkg: String): Boolean {
        return try {
            @Suppress("DEPRECATION")
            val info: android.content.pm.PackageInfo =
                context.packageManager.getPackageInfo(pkg, PackageManager.GET_PERMISSIONS)
            info.requestedPermissions?.contains(BACKGROUND_LOCATION) == true
        } catch (t: Throwable) {
            false
        }
    }

    private fun isBackgroundLocationGranted(context: Context, pkg: String): Boolean {
        return try {
            context.packageManager.checkPermission(BACKGROUND_LOCATION, pkg) ==
                PackageManager.PERMISSION_GRANTED
        } catch (t: Throwable) {
            false
        }
    }

    private fun isSystemApp(context: Context, pkg: String): Boolean {
        return try {
            val info = context.packageManager.getApplicationInfo(pkg, 0)
            val system = info.flags and ApplicationInfo.FLAG_SYSTEM != 0
            val updatedSystem = info.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP != 0
            system && !updatedSystem
        } catch (t: Throwable) {
            false
        }
    }

    private fun appLabel(context: Context, pkg: String): String {
        return try {
            val pm = context.packageManager
            val info = pm.getApplicationInfo(pkg, 0)
            pm.getApplicationLabel(info).toString()
        } catch (t: Throwable) {
            pkg
        }
    }

    /** 证据类型 -> Dart 侧认识的信号名。 */
    private fun signalName(type: EvidenceType): String = when (type) {
        EvidenceType.LOCK_SCREEN_BACKGROUND_START -> "lockScreenLaunch"
        EvidenceType.LOCK_SCREEN_RESUME -> "lockScreenLaunch"
        EvidenceType.FOCUS_STEAL -> "focusSteal"
        EvidenceType.IDLE_SELF_LAUNCH -> "selfLaunch"
    }

    /** 证据类型 -> 证据等级。 */
    private fun levelOf(type: EvidenceType): String = when (type) {
        EvidenceType.LOCK_SCREEN_BACKGROUND_START -> "hard"
        EvidenceType.LOCK_SCREEN_RESUME -> "hard"
        EvidenceType.FOCUS_STEAL -> "hard"
        EvidenceType.IDLE_SELF_LAUNCH -> "lead"
    }

    /** 内部用的时长载体。后台时长另有来源（从事件流算），这里只放系统给的量。 */
    private data class UsageEntry(
        val foregroundMillis: Long,
    )
}
