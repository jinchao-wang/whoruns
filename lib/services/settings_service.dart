import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地设置。
///
/// 用 [ChangeNotifier]：首页、详情页、设置页都要跟着变
/// （比如用户把某个 App 加进白名单，榜单要立刻少一条）。
class SettingsService extends ChangeNotifier {
  SettingsService._();

  static final SettingsService instance = SettingsService._();

  static const String _kIgnored = 'ignored_packages';
  static const String _kAlertEnabled = 'alert_enabled';
  static const String _kAlertMinutes = 'alert_every_minutes';
  static const String _kRangeHours = 'audit_range_hours';
  static const String _kLastScan = 'last_scan_at';

  /// 用户加进白名单（不想再看到）的 App。
  Set<String> _ignored = <String>{};

  /// 是否开启定期告警。
  bool _alertsEnabled = false;

  /// 多久查一次（分钟）。
  int _alertMinutes = 30;

  /// 审计回溯多少小时。
  int _rangeHours = 24;

  DateTime? _lastScanAt;

  Set<String> get ignoredPackages => Set.unmodifiable(_ignored);

  bool get alertsEnabled => _alertsEnabled;

  int get alertMinutes => _alertMinutes;

  int get rangeHours => _rangeHours;

  DateTime? get lastScanAt => _lastScanAt;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _ignored = (prefs.getStringList(_kIgnored) ?? const <String>[]).toSet();
    _alertsEnabled = prefs.getBool(_kAlertEnabled) ?? false;
    _alertMinutes = prefs.getInt(_kAlertMinutes) ?? 30;
    _rangeHours = prefs.getInt(_kRangeHours) ?? 24;
    final last = prefs.getInt(_kLastScan);
    _lastScanAt = last == null ? null : DateTime.fromMillisecondsSinceEpoch(last);
    notifyListeners();
  }

  Future<void> setIgnored(Set<String> packages) async {
    _ignored = Set<String>.from(packages);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kIgnored, _ignored.toList()..sort());
    notifyListeners();
  }

  Future<void> setIgnoredOne(String package, bool ignored) async {
    final next = Set<String>.from(_ignored);
    if (ignored) {
      next.add(package);
    } else {
      next.remove(package);
    }
    await setIgnored(next);
  }

  Future<void> setAlertsEnabled(bool value) async {
    _alertsEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAlertEnabled, value);
    notifyListeners();
  }

  Future<void> setAlertMinutes(int value) async {
    _alertMinutes = value.clamp(15, 24 * 60);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kAlertMinutes, _alertMinutes);
    notifyListeners();
  }

  Future<void> setRangeHours(int value) async {
    _rangeHours = value.clamp(1, 24 * 30);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kRangeHours, _rangeHours);
    notifyListeners();
  }

  Future<void> markScanned(DateTime at) async {
    _lastScanAt = at;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastScan, at.millisecondsSinceEpoch);
    notifyListeners();
  }
}
