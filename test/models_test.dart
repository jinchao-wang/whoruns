import 'package:flutter_test/flutter_test.dart';
import 'package:whoruns/models/audit.dart';
import 'package:whoruns/services/export_service.dart';
import 'package:whoruns/utils/scoring.dart';

void main() {
  group('原生数据解析', () {
    final raw = <String, dynamic>{
      'package': 'com.demo.sneaky',
      'label': '爱偷跑',
      'foregroundMillis': 600000,
      'backgroundMillis': 7200000,
      'trafficBytes': 52428800,
      'hasBackgroundLocation': true,
      'backgroundLocationGranted': true,
      'isSystemApp': true,
      'evidence': [
        {
          'signal': 'lockScreenLaunch',
          'level': 'hard',
          'ts': 1700000000000,
          'detail': '息屏状态下它启动了后台任务',
          'magnitude': 1.0,
        },
        {
          'signal': 'selfLaunch',
          'level': 'lead',
          'ts': 1700000100000,
          'detail': '长时间没人操作手机，它自己弹到了前台',
          'magnitude': 1.0,
        },
      ],
    };

    test('字段一一对上', () {
      final app = AppAudit.fromMap(raw);
      expect(app.packageName, 'com.demo.sneaky');
      expect(app.label, '爱偷跑');
      expect(app.foregroundHours, closeTo(0.1667, 0.01));
      expect(app.backgroundHours, 2);
      expect(app.trafficMB, 50);
      expect(app.trafficAvailable, isTrue);
      expect(app.isSystemApp, isTrue);
      expect(app.backgroundLocationGranted, isTrue);
    });

    test('证据按等级解析', () {
      final app = AppAudit.fromMap(raw);
      expect(app.evidence.length, 2);
      expect(app.evidence.first.signal, AuditSignal.lockScreenLaunch);
      expect(app.evidence.first.level, EvidenceLevel.hard);
      expect(app.evidence.last.level, EvidenceLevel.lead);
    });

    test('计数从证据列表里数出来', () {
      final app = AppAudit.fromMap(raw);
      expect(app.lockScreenLaunches, 1);
      expect(app.idleSelfLaunches, 1);
      expect(app.focusStealCount, 0);
      expect(app.selfLaunches, 2);
    });

    test('拿不到流量时标记为不可用，而不是 0', () {
      final app = AppAudit.fromMap({...raw, 'trafficBytes': -1});
      expect(app.trafficAvailable, isFalse);
      expect(app.trafficMB, 0);
    });
  });

  group('CSV 导出', () {
    test('表头和每一行都对得上', () {
      final app = AppAudit.fromMap({
        'package': 'com.demo.sneaky',
        'label': '爱偷跑',
        'foregroundMillis': 600000,
        'backgroundMillis': 7200000,
        'trafficBytes': 52428800,
        'hasBackgroundLocation': true,
        'backgroundLocationGranted': true,
        'isSystemApp': false,
        'evidence': const [],
      });
      final report = AuditReport(
        scannedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        rangeStart: DateTime.fromMillisecondsSinceEpoch(1699913600000),
        rangeEnd: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        apps: [app],
        trafficAvailable: true,
      );

      final csv = ExportService.buildCsv(report);
      final lines = csv.trim().split('\n');
      expect(lines.length, 2);
      expect(lines.first, contains('应用名'));
      expect(lines.first, contains('偷跑指数'));
      expect(lines.last, contains('爱偷跑'));
      expect(lines.last, contains('com.demo.sneaky'));
      expect(lines.last, contains('50.0'));
    });

    test('名字里有逗号会被正确转义', () {
      final app = AppAudit.fromMap({
        'package': 'com.demo',
        'label': '带,逗号的应用',
        'foregroundMillis': 0,
        'backgroundMillis': 0,
        'trafficBytes': -1,
        'hasBackgroundLocation': false,
        'backgroundLocationGranted': false,
        'isSystemApp': false,
        'evidence': const [],
      });
      final report = AuditReport(
        scannedAt: DateTime.now(),
        rangeStart: DateTime.now(),
        rangeEnd: DateTime.now(),
        apps: [app],
        trafficAvailable: false,
      );
      final csv = ExportService.buildCsv(report);
      expect(csv, contains('"带,逗号的应用"'));
    });
  });

  group('评分在真实数据上的表现', () {
    test('有息屏启动 + 后台定位的 App 会进高危', () {
      final app = AppAudit.fromMap({
        'package': 'com.demo.sneaky',
        'label': '爱偷跑',
        'foregroundMillis': 600000,
        'backgroundMillis': 7200000,
        'trafficBytes': 52428800,
        'hasBackgroundLocation': true,
        'backgroundLocationGranted': true,
        'isSystemApp': false,
        'evidence': const [
          {
            'signal': 'lockScreenLaunch',
            'level': 'hard',
            'ts': 1700000000000,
            'detail': '息屏状态下它启动了后台任务',
            'magnitude': 1.0,
          },
          {
            'signal': 'lockScreenLaunch',
            'level': 'hard',
            'ts': 1700000100000,
            'detail': '息屏状态下它启动了后台任务',
            'magnitude': 1.0,
          },
          {
            'signal': 'lockScreenLaunch',
            'level': 'hard',
            'ts': 1700000200000,
            'detail': '息屏状态下它启动了后台任务',
            'magnitude': 1.0,
          },
          {
            'signal': 'focusSteal',
            'level': 'hard',
            'ts': 1700000300000,
            'detail': '在另一个 App 还在前台时抢到了焦点',
            'magnitude': 1.0,
          },
          {
            'signal': 'focusSteal',
            'level': 'hard',
            'ts': 1700000400000,
            'detail': '在另一个 App 还在前台时抢到了焦点',
            'magnitude': 1.0,
          },
          {
            'signal': 'focusSteal',
            'level': 'hard',
            'ts': 1700000500000,
            'detail': '在另一个 App 还在前台时抢到了焦点',
            'magnitude': 1.0,
          },
        ],
      });
      expect(app.lockScreenLaunches, 3);
      expect(app.focusStealCount, 3);
      expect(app.score.grade, Grade.high);
      expect(app.score.total, greaterThanOrEqualTo(60));
    });
  });
}
