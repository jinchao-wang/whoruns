package com.wjc.whoruns

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 事件分类器的单测。
 *
 * 这是整个 App 最容易出错、也最不能错的地方：
 * 误报会让用户卸载，漏报会让用户白买。
 * 所以每一条判定规则都在这里钉死。
 */
class AuditClassifierTest {

    private val minute = 60_000L
    private val hour = 60 * minute

    @Test
    fun `息屏时别的 App 启动后台任务会被记为硬证据`() {
        val evidence = AuditClassifier.classify(
            listOf(
                RawEvent(AuditEventType.ACTIVITY_RESUMED, "com.a", 1_000),
                RawEvent(AuditEventType.ACTIVITY_PAUSED, "com.a", 1_500),
                RawEvent(AuditEventType.SCREEN_NON_INTERACTIVE, "system", 2_000),
                RawEvent(AuditEventType.ACTIVITY_STARTED, "com.sneaky", 3_000),
            )
        )

        val hit = evidence.firstOrNull { it.packageName == "com.sneaky" }
        assertTrue("应该记到息屏启动", hit != null)
        assertEquals(EvidenceType.LOCK_SCREEN_BACKGROUND_START, hit!!.type)
    }

    @Test
    fun `屏幕刚亮还没解锁就把界面拉到前台算硬证据`() {
        val evidence = AuditClassifier.classify(
            listOf(
                RawEvent(AuditEventType.SCREEN_INTERACTIVE, "system", 0),
                RawEvent(AuditEventType.ACTIVITY_RESUMED, "com.sneaky", 5_000),
            )
        )

        val hit = evidence.firstOrNull { it.packageName == "com.sneaky" }
        assertTrue("应该记到息屏拉前台", hit != null)
        assertEquals(EvidenceType.LOCK_SCREEN_RESUME, hit!!.type)
    }

    @Test
    fun `上一个 App 还没退到后台就叠上来算抢焦点`() {
        val evidence = AuditClassifier.classify(
            listOf(
                RawEvent(AuditEventType.SCREEN_INTERACTIVE, "system", 0),
                RawEvent(AuditEventType.USER_PRESENT, "system", 1_000),
                RawEvent(AuditEventType.ACTIVITY_RESUMED, "com.a", 2_000),
                // com.a 没有 PAUSED，直接被 com.b 压了上来。
                RawEvent(AuditEventType.ACTIVITY_RESUMED, "com.b", 3_000),
            )
        )

        val hit = evidence.firstOrNull { it.packageName == "com.b" }
        assertTrue("应该记到抢焦点", hit != null)
        assertEquals(EvidenceType.FOCUS_STEAL, hit!!.type)
    }

    @Test
    fun `用户正常切换 App 不产生任何证据`() {
        val evidence = AuditClassifier.classify(
            listOf(
                RawEvent(AuditEventType.SCREEN_INTERACTIVE, "system", 0),
                RawEvent(AuditEventType.USER_PRESENT, "system", 1_000),
                RawEvent(AuditEventType.ACTIVITY_RESUMED, "com.a", 2_000),
                RawEvent(AuditEventType.ACTIVITY_PAUSED, "com.a", 2_500),
                RawEvent(AuditEventType.ACTIVITY_RESUMED, "com.b", 3_000),
            )
        )

        assertTrue("正常切换不该有证据，实际：$evidence", evidence.isEmpty())
    }

    @Test
    fun `长时间没人操作却自己弹到前台只算线索`() {
        val evidence = AuditClassifier.classify(
            listOf(
                RawEvent(AuditEventType.SCREEN_INTERACTIVE, "system", 0),
                RawEvent(AuditEventType.USER_PRESENT, "system", 1_000),
                RawEvent(AuditEventType.ACTIVITY_RESUMED, "com.a", 2_000),
                RawEvent(AuditEventType.ACTIVITY_PAUSED, "com.a", 2_500),
                // 20 分钟没人碰手机，com.b 自己冒出来了。
                RawEvent(AuditEventType.ACTIVITY_RESUMED, "com.b", 20 * minute + 3_000),
            )
        )

        val hit = evidence.firstOrNull { it.packageName == "com.b" }
        assertTrue("应该记到闲置自启", hit != null)
        assertEquals(EvidenceType.IDLE_SELF_LAUNCH, hit!!.type)
    }

    @Test
    fun `10 秒内重复上报只记一条`() {
        val evidence = AuditClassifier.classify(
            listOf(
                RawEvent(AuditEventType.SCREEN_INTERACTIVE, "system", 0),
                RawEvent(AuditEventType.ACTIVITY_RESUMED, "com.sneaky", 3_000),
                RawEvent(AuditEventType.ACTIVITY_RESUMED, "com.sneaky", 4_000),
                RawEvent(AuditEventType.ACTIVITY_RESUMED, "com.sneaky", 5_000),
            )
        )

        assertEquals(1, evidence.count { it.packageName == "com.sneaky" })
    }

    @Test
    fun `用户刚解锁两分钟内切换 App 不算闲置自启`() {
        val evidence = AuditClassifier.classify(
            listOf(
                RawEvent(AuditEventType.SCREEN_INTERACTIVE, "system", 0),
                RawEvent(AuditEventType.USER_PRESENT, "system", 1_000),
                RawEvent(AuditEventType.ACTIVITY_RESUMED, "com.a", 2_000),
                RawEvent(AuditEventType.ACTIVITY_PAUSED, "com.a", 2_500),
                RawEvent(AuditEventType.ACTIVITY_RESUMED, "com.b", 2 * minute + 3_000),
            )
        )

        assertTrue("刚解锁不久不该算闲置自启，实际：$evidence", evidence.isEmpty())
    }

    @Test
    fun `事件乱序时也能正确分类`() {
        val evidence = AuditClassifier.classify(
            listOf(
                RawEvent(AuditEventType.ACTIVITY_RESUMED, "com.b", 3_000),
                RawEvent(AuditEventType.ACTIVITY_RESUMED, "com.a", 2_000),
                RawEvent(AuditEventType.USER_PRESENT, "system", 1_000),
                RawEvent(AuditEventType.SCREEN_INTERACTIVE, "system", 0),
            )
        )

        val hit = evidence.firstOrNull { it.packageName == "com.b" }
        assertTrue("应该记到抢焦点", hit != null)
        assertEquals(EvidenceType.FOCUS_STEAL, hit!!.type)
    }
}
