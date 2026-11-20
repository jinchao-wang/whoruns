import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/audit.dart';
import '../utils/scoring.dart';

/// 把审计结果导成 CSV。
///
/// 只写文件，不联网上传 —— 这是隐私承诺的一部分：
/// 用户的用量数据一辈子不离开这台手机（除非他自己导出去）。
class ExportService {
  const ExportService._();

  static Future<String?> exportCsv(AuditReport report) async {
    final csv = buildCsv(report);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final stamp = report.scannedAt.toIso8601String().replaceAll(':', '-');
      final file = File('${dir.path}/谁在偷跑-审计报告-$stamp.csv');
      await file.writeAsString(csv);
      return file.path;
    } catch (e) {
      return null;
    }
  }

  /// 生成 CSV 文本。
  ///
  /// 单独拆出来是为了能直接单测，不用碰文件系统。
  static String buildCsv(AuditReport report) {
    final buffer = StringBuffer();
    buffer.writeln([
      '应用名',
      '包名',
      '偷跑指数',
      '等级',
      '自启次数',
      '息屏启动',
      '抢焦点',
      '前台时长(分钟)',
      '后台时长(分钟)',
      '移动流量(MB)',
      '有后台定位权限',
      '证据条数',
    ].join(','));

    final ranked = report.apps.toList()..sort(compareAudits);
    for (final app in ranked) {
      buffer.writeln([
        _escape(app.label),
        _escape(app.packageName),
        app.score.total,
        app.score.grade.label,
        app.plainSelfLaunches,
        app.lockScreenLaunches,
        app.focusStealCount,
        (app.foregroundMillis / 60000).round(),
        (app.backgroundMillis / 60000).round(),
        app.trafficAvailable ? app.trafficMB.toStringAsFixed(1) : '读不到',
        app.backgroundLocationGranted ? '是' : '否',
        app.evidence.length,
      ].join(','));
    }
    return buffer.toString();
  }

  /// CSV 字段转义：带逗号、引号、换行的要包起来。
  static String _escape(String value) {
    if (!value.contains(RegExp('[,"\n]'))) return value;
    return '"${value.replaceAll('"', '""')}"';
  }
}
