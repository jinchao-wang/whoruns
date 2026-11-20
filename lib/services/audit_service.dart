import 'package:flutter/foundation.dart';

import '../models/audit.dart';
import 'settings_service.dart';
import 'usage_service.dart';

/// 审计编排：取数、套白名单、缓存图标。
class AuditService extends ChangeNotifier {
  AuditService._();

  static final AuditService instance = AuditService._();

  AuditReport? _report;
  bool _running = false;
  String? _error;
  final Map<String, Uint8List> _icons = {};

  AuditReport? get report => _report;

  bool get running => _running;

  String? get error => _error;

  Uint8List? iconOf(String packageName) => _icons[packageName];

  /// 用户有没有给使用情况访问权限。
  Future<bool> hasPermission() => UsageService.instance.hasUsageAccess();

  /// 跑一次审计。
  ///
  /// 返回 null 表示成功；返回字符串是失败原因。
  Future<String?> runAudit({int? hours}) async {
    if (_running) return '正在审计中';
    _running = true;
    _error = null;
    notifyListeners();
    try {
      final range = hours ?? SettingsService.instance.rangeHours;
      final raw = await UsageService.instance.collectAudit(sinceHours: range);
      if (raw == null) {
        _error = '这台系统读不到 App 用量数据';
        return _error;
      }
      var report = AuditReport.fromMap(raw);

      // 套上用户白名单。
      final ignored = SettingsService.instance.ignoredPackages;
      report = AuditReport(
        scannedAt: report.scannedAt,
        rangeStart: report.rangeStart,
        rangeEnd: report.rangeEnd,
        trafficAvailable: report.trafficAvailable,
        apps: report.apps
            .map((a) => ignored.contains(a.packageName)
                ? a.copyWith(ignored: true)
                : a)
            .toList(),
      );

      _report = report;
      SettingsService.instance.markScanned(report.scannedAt);
      await _loadIcons(report);
      return null;
    } catch (e) {
      _error = '审计失败：$e';
      return _error;
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  /// 只给榜单上要用到的 App 取图标。
  Future<void> _loadIcons(AuditReport report) async {
    final top = report.apps
        .where((a) => !a.ignored)
        .take(40)
        .map((a) => a.packageName)
        .toList();
    if (top.isEmpty) return;
    final icons = await UsageService.instance.appIcons(top);
    _icons
      ..clear()
      ..addAll(icons);
  }
}
