import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 和原生层对话的唯一入口。
///
/// Android 侧靠 `UsageStatsManager` 拿系统事件；iOS 侧没有这个能力，
/// 原生方法会返回「不支持」，由 [UsageService.isSupported] 区分。
class UsageService {
  UsageService._();

  static final UsageService instance = UsageService._();

  static const MethodChannel _channel = MethodChannel('com.wjc.whoruns/audit');

  /// 当前平台能不能读别的 App 的用量。
  ///
  /// iOS 没有这个 API（隐私设计如此），所以 iOS 端会走「本机自检」那条线。
  bool get isSupported => defaultTargetPlatform != TargetPlatform.iOS;

  /// 用户是否已经给了「使用情况访问权限」。
  ///
  /// Android 上这是个特殊权限，只能跳到系统设置页手动开。
  Future<bool> hasUsageAccess() async {
    if (!isSupported) return false;
    final ok = await _invoke<bool>('hasUsageAccess');
    return ok ?? false;
  }

  /// 跳到系统的「使用情况访问权限」设置页。
  Future<bool> openUsageAccessSettings() async {
    if (!isSupported) return false;
    final ok = await _invoke<bool>('openUsageAccessSettings');
    return ok ?? false;
  }

  /// 跑一次审计，拿回原始数据。
  ///
  /// [sinceHours] 是回溯时间范围（小时）。
  Future<Map<String, dynamic>?> collectAudit({required int sinceHours}) async {
    if (!isSupported) return null;
    return _invoke<Map<String, dynamic>>(
      'collectAudit',
      <String, dynamic>{'sinceHours': sinceHours},
    );
  }

  /// 批量取 App 图标（base64 PNG）。
  ///
  /// 一次只取榜单上要用到的那几个，避免一次拉几百个图标把内存吃满。
  Future<Map<String, Uint8List>> appIcons(List<String> packages) async {
    if (!isSupported || packages.isEmpty) return const {};
    final raw = await _invoke<Map<String, dynamic>>(
      'appIcons',
      <String, dynamic>{'packages': packages},
    );
    if (raw == null) return const {};
    final out = <String, Uint8List>{};
    raw.forEach((key, value) {
      if (value is! String || value.isEmpty) return;
      try {
        out[key] = base64Decode(value);
      } on FormatException {
        // 某个图标取不到就跳过，不影响其它 App。
      }
    });
    return out;
  }

  /// 打开某个 App 的系统设置页（用户在那里撤销权限、强行停止）。
  Future<bool> openAppSettings(String packageName) async {
    final ok = await _invoke<bool>(
      'openAppSettings',
      <String, dynamic>{'package': packageName},
    );
    return ok ?? false;
  }

  /// 设备指纹，用来把授权码绑到这台机器上。
  Future<String> deviceFingerprint() async {
    final value = await _invoke<String>('deviceFingerprint');
    return value ?? '';
  }

  /// 本机健康信息：电量、存储、温度状态。
  Future<Map<String, dynamic>> deviceHealth() async {
    final value = await _invoke<Map<String, dynamic>>('deviceHealth');
    return value ?? const {};
  }

  /// 申请通知权限（Android 13+ 需要）。
  Future<bool> requestNotificationPermission() async {
    final ok = await _invoke<bool>('requestNotificationPermission');
    return ok ?? false;
  }

  /// 打开/关闭定期告警。
  Future<bool> setAlertSchedule({
    required bool enabled,
    required int everyMinutes,
  }) async {
    final ok = await _invoke<bool>(
      'setAlertSchedule',
      <String, dynamic>{'enabled': enabled, 'everyMinutes': everyMinutes},
    );
    return ok ?? false;
  }

  /// 立刻发一条本地通知（主要给自检用）。
  Future<bool> showNotification({
    required String title,
    required String body,
  }) async {
    final ok = await _invoke<bool>(
      'showNotification',
      <String, dynamic>{'title': title, 'body': body},
    );
    return ok ?? false;
  }

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? args]) async {
    try {
      // 原生那边要是没响应（比如某些 ROM 上采集卡住），
      // 不能让界面一直转圈 —— 超时就当这次没结果。
      final result = await _channel
          .invokeMethod<T>(method, args)
          .timeout(const Duration(seconds: 30));
      return result;
    } on MissingPluginException {
      // iOS 上没实现的原生方法会走到这里，按「不支持」处理。
      return null;
    } catch (e) {
      // 原生那边要是抛了别的（甚至直接崩），也不能把界面卡住：
      // 审计失败顶多是「这次没结果」，不该让整个 App 白屏。
      debugPrint('[UsageService] $method 失败：$e');
      return null;
    }
  }
}
