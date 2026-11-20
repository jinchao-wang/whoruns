import CryptoKit
import Flutter
import UIKit

/// iOS 侧的入口。
///
/// iOS 不允许第三方 App 读取别的 App 的使用情况（苹果的隐私设计），
/// 所以这里**不实现** `collectAudit` —— 与其给一个半真半假的答案，
/// 不如在界面上把这条边界说清楚，然后提供本机健康自检。
///
/// 提供的方法：
/// - `deviceHealth`：电量、充电状态、存储余量、温度状态；
/// - `deviceFingerprint`：设备指纹（只在本机算哈希，不上传）；
/// - 其余方法返回「不支持」。
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WhorunsAudit") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "com.wjc.whoruns/audit",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "deviceHealth":
        result(Self.deviceHealth())
      case "deviceFingerprint":
        result(Self.fingerprint())
      case "hasUsageAccess":
        // iOS 没有这个权限，永远是「拿不到」。
        result(false)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// 本机状态。iOS 上只有这些是系统允许读的。
  private static func deviceHealth() -> [String: Any?] {
    var out: [String: Any?] = [:]

    let device = UIDevice.current
    device.isBatteryMonitoringEnabled = true
    if device.batteryLevel >= 0 {
      out["batteryLevel"] = Int((device.batteryLevel * 100).rounded())
      out["charging"] = device.batteryState == .charging || device.batteryState == .full
    }

    if let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
      do {
        let values = try url.resourceValues(forKeys: [
          .volumeAvailableCapacityForImportantUsageKey,
          .volumeTotalCapacityKey,
        ])
        if let free = values.volumeAvailableCapacityForImportantUsage {
          out["storageFreeBytes"] = free
        }
        if let total = values.volumeTotalCapacity {
          out["storageTotalBytes"] = total
        }
      } catch {
        // 读不到就算了。
      }
    }

    out["thermalStatus"] = Int(ProcessInfo.processInfo.thermalState.rawValue)
    return out
  }

  /// 设备指纹：vendor id + 机型哈希，只在本机算，不上传。
  private static func fingerprint() -> String {
    let vendorId = UIDevice.current.identifierForVendor?.uuidString ?? ""
    let raw = "\(vendorId)|\(UIDevice.current.model)"
    let digest = SHA256.hash(data: Data(raw.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}
