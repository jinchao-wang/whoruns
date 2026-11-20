package com.wjc.whoruns

/**
 * 审计用的事件类型。
 *
 * 故意不直接用 `UsageEvents.Event`：
 * 那些是 Android 框架类，JVM 单测里用不了。
 * 这里定义一份自己的枚举，原生层负责把框架事件翻译过来，
 * 于是分类逻辑可以脱离设备直接跑测试。
 */
enum class AuditEventType {
    ACTIVITY_STARTED,
    ACTIVITY_RESUMED,
    ACTIVITY_PAUSED,
    ACTIVITY_STOPPED,
    SCREEN_INTERACTIVE,
    SCREEN_NON_INTERACTIVE,
    USER_PRESENT,
    USER_UNLOCKED,
}

/** 一条原始事件。 */
data class RawEvent(
    val type: AuditEventType,
    val packageName: String,
    val timestamp: Long,
)

/** 证据的种类。 */
enum class EvidenceType {
    /** 息屏时自己启动了后台任务（屏幕关着，人不可能在点）。 */
    LOCK_SCREEN_BACKGROUND_START,

    /** 屏幕刚亮它就把界面拉到前台（中间没有解锁动作）。 */
    LOCK_SCREEN_RESUME,

    /** 压在别的 App 上面：上一个 App 根本没失去焦点。 */
    FOCUS_STEAL,

    /** 长时间没有任何操作痕迹，它自己弹到了前台（线索，不算定论）。 */
    IDLE_SELF_LAUNCH,
}

/** 一条证据。 */
data class EvidenceRecord(
    val packageName: String,
    val type: EvidenceType,
    val timestamp: Long,
    val detail: String,
)

/**
 * 事件分类器：把一串系统事件变成「谁在偷跑」的证据。
 *
 * 设计上只认三种**不会误伤用户主动操作**的事实：
 *
 * 1. 息屏时还有 App 在启动活动 —— 屏幕是黑的，用户不可能刚点过它；
 * 2. 屏幕刚亮、还没解锁，就有 App 把界面拉到前台 —— 它自己点亮了屏幕；
 * 3. 上一个 App 还没失去焦点，新 App 就叠上来了 —— 典型的弹窗抢焦点。
 *
 * 第四种「长时间没人操作却自己弹到前台」只能算**线索**：
 * 用户把手机扔在桌上、解锁后半天没动，这种情况下无法百分百排除是他自己点的。
 * 所以它单独占一个类型，评分时权重也更低。
 */
object AuditClassifier {

    /** 超过这个时长没有任何用户操作痕迹，就算「没人管手机」。 */
    const val IDLE_GAP_MS = 10 * 60 * 1000L

    /** 屏幕亮起后这么多秒内拉到前台，算「它自己点的亮」。 */
    const val SCREEN_WAKE_WINDOW_MS = 15 * 1000L

    /** 10 秒内重复的同类事件只记一条，避免系统重复上报把次数刷高。 */
    private const val DEDUPE_WINDOW_MS = 10 * 1000L

    fun classify(events: List<RawEvent>): List<EvidenceRecord> {
        val sorted = events.sortedBy { it.timestamp }
        val out = ArrayList<EvidenceRecord>()
        val seen = HashSet<String>()

        var foreground: String? = null
        var foregroundPaused = false
        var screenOn = true
        var screenOnAt = 0L
        var unlockedAfterScreenOn = false
        var lastUserActiveAt = 0L

        fun isIdle(ts: Long): Boolean =
            lastUserActiveAt == 0L || ts - lastUserActiveAt >= IDLE_GAP_MS

        fun add(type: EvidenceType, pkg: String, ts: Long, detail: String) {
            val key = "$pkg|${type.name}|${ts / DEDUPE_WINDOW_MS}"
            if (!seen.add(key)) return
            out.add(EvidenceRecord(pkg, type, ts, detail))
        }

        for (event in sorted) {
            when (event.type) {
                AuditEventType.SCREEN_INTERACTIVE -> {
                    screenOn = true
                    screenOnAt = event.timestamp
                    unlockedAfterScreenOn = false
                    lastUserActiveAt = event.timestamp
                }

                AuditEventType.SCREEN_NON_INTERACTIVE -> {
                    screenOn = false
                }

                AuditEventType.USER_PRESENT, AuditEventType.USER_UNLOCKED -> {
                    unlockedAfterScreenOn = true
                    lastUserActiveAt = event.timestamp
                }

                AuditEventType.ACTIVITY_PAUSED, AuditEventType.ACTIVITY_STOPPED -> {
                    if (event.packageName == foreground) {
                        foregroundPaused = true
                    }
                }

                AuditEventType.ACTIVITY_STARTED -> {
                    val fg = foreground
                    if (fg != null && event.packageName != fg) {
                        if (!screenOn) {
                            // 屏幕黑着，它还在启动东西。
                            add(
                                EvidenceType.LOCK_SCREEN_BACKGROUND_START,
                                event.packageName,
                                event.timestamp,
                                "息屏状态下它启动了后台任务",
                            )
                        } else if (!foregroundPaused) {
                            // 前台 App 还占着焦点，它直接叠上来了。
                            add(
                                EvidenceType.FOCUS_STEAL,
                                event.packageName,
                                event.timestamp,
                                "在另一个 App 还在前台时抢到了焦点",
                            )
                        }
                    }
                }

                AuditEventType.ACTIVITY_RESUMED -> {
                    val fg = foreground
                    if (event.packageName != fg) {
                        val wokeScreen = screenOn &&
                            !unlockedAfterScreenOn &&
                            screenOnAt > 0L &&
                            event.timestamp - screenOnAt <= SCREEN_WAKE_WINDOW_MS

                        when {
                            wokeScreen -> add(
                                EvidenceType.LOCK_SCREEN_RESUME,
                                event.packageName,
                                event.timestamp,
                                "屏幕刚亮起来它就把界面拉到了前台",
                            )

                            fg == null -> Unit

                            !foregroundPaused -> add(
                                EvidenceType.FOCUS_STEAL,
                                event.packageName,
                                event.timestamp,
                                "上一个 App 还没退到后台，它就压上来了",
                            )

                            isIdle(event.timestamp) -> add(
                                EvidenceType.IDLE_SELF_LAUNCH,
                                event.packageName,
                                event.timestamp,
                                "长时间没人操作手机，它自己弹到了前台",
                            )

                            else -> Unit
                        }
                    }
                    foreground = event.packageName
                    foregroundPaused = false
                }
            }
        }

        return out
    }
}
