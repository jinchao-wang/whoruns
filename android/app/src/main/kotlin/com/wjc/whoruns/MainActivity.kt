package com.wjc.whoruns

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.util.concurrent.Executors

/**
 * 和 Dart 之间的唯一通道。
 *
 * 重活（查用量、查流量）一律丢到后台线程：
 * `queryUsageStats` 在包多的机器上要跑两三秒，
 * 放在主线程会直接卡住界面。
 */
class MainActivity : FlutterActivity() {

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                handle(call, result)
            }
        }
    }

    override fun onDestroy() {
        channel?.setMethodCallHandler(null)
        executor.shutdown()
        super.onDestroy()
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasUsageAccess" -> result.success(UsageAudit.hasUsageAccess(this))

            "openUsageAccessSettings" -> {
                result.success(openUsageAccessSettings())
            }

            "collectAudit" -> {
                val sinceHours = (call.argument<Int>("sinceHours") ?: 24).coerceIn(1, 24 * 30)
                executor.execute {
                    try {
                        val report = UsageAudit.collect(this, sinceHours)
                        mainHandler.post { result.success(report) }
                    } catch (t: Throwable) {
                        mainHandler.post {
                            result.error("collect_failed", t.message ?: "审计失败", null)
                        }
                    }
                }
            }

            "appIcons" -> {
                val packages = call.argument<List<String>>("packages") ?: emptyList()
                executor.execute {
                    val icons = AppIcons.load(this, packages)
                    mainHandler.post { result.success(icons) }
                }
            }

            "openAppSettings" -> {
                val pkg = call.argument<String>("package")
                result.success(openAppSettings(pkg))
            }

            "deviceFingerprint" -> result.success(deviceFingerprint())

            "deviceHealth" -> result.success(DeviceHealth.snapshot(this))

            "requestNotificationPermission" -> result.success(requestNotificationPermission())

            "setAlertSchedule" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                val everyMinutes = (call.argument<Int>("everyMinutes") ?: 30).coerceIn(15, 24 * 60)
                AuditNotifier.setSchedule(this, enabled, everyMinutes)
                result.success(true)
            }

            "showNotification" -> {
                val title = call.argument<String>("title") ?: "谁在偷跑"
                val body = call.argument<String>("body") ?: ""
                AuditNotifier.show(this, title, body)
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    /** 跳到系统的「使用情况访问权限」页。 */
    private fun openUsageAccessSettings(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (t: Throwable) {
            try {
                val intent = Intent(Settings.ACTION_SETTINGS)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                true
            } catch (t2: Throwable) {
                false
            }
        }
    }

    /** 打开某个 App 的系统设置页，用户在那里撤销权限、强行停止。 */
    private fun openAppSettings(packageName: String?): Boolean {
        if (packageName.isNullOrEmpty()) return false
        return try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", packageName, null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (t: Throwable) {
            false
        }
    }

    /**
     * 设备指纹：用来把授权码绑到这台机器上。
     *
     * 用 ANDROID_ID（Android 8 以后是「按应用签名隔离」的）加机型一起哈希，
     * 不上传、不联网，只在本地比对。
     */
    private fun deviceFingerprint(): String {
        return try {
            val androidId = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
            val raw = "$androidId|${Build.MANUFACTURER}|${Build.MODEL}|$packageName"
            val digest = MessageDigest.getInstance("SHA-256").digest(raw.toByteArray())
            digest.joinToString("") { "%02x".format(it) }
        } catch (t: Throwable) {
            ""
        }
    }

    /** Android 13+ 通知权限。 */
    private fun requestNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return true
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return true
        }
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATION)
        return false
    }

    companion object {
        const val CHANNEL = "com.wjc.whoruns/audit"
        private const val REQUEST_NOTIFICATION = 3301
    }
}
