import 'package:flutter_test/flutter_test.dart';
import 'package:whoruns/models/audit.dart';
import 'package:whoruns/utils/scoring.dart';

AppAudit buildApp({
  int foregroundMillis = 0,
  int backgroundMillis = 0,
  int idleSelfLaunches = 0,
  int lockScreenLaunches = 0,
  int focusStealCount = 0,
  int trafficBytes = -1,
  bool backgroundLocationGranted = false,
  bool hasBackgroundLocation = false,
}) {
  return AppAudit(
    packageName: 'com.demo',
    label: '演示 App',
    foregroundMillis: foregroundMillis,
    backgroundMillis: backgroundMillis,
    idleSelfLaunches: idleSelfLaunches,
    lockScreenLaunches: lockScreenLaunches,
    focusStealCount: focusStealCount,
    trafficBytes: trafficBytes,
    hasBackgroundLocation: hasBackgroundLocation,
    backgroundLocationGranted: backgroundLocationGranted,
    isSystemApp: false,
    evidence: const [],
  );
}

void main() {
  group('偷跑指数', () {
    test('什么证据都没有就是 0 分', () {
      final score = computeScore(buildApp());
      expect(score.total, 0);
      expect(score.grade, Grade.normal);
    });

    test('普通 App 不会因为后台待着就被扣分', () {
      // 后台 3 小时、流量 20MB：都很常见，不该算可疑。
      final score = computeScore(buildApp(
        backgroundMillis: 3 * 3600000,
        trafficBytes: 20 * 1024 * 1024,
      ));
      expect(score.total, lessThan(18));
      expect(score.grade, Grade.normal);
    });

    test('息屏启动是硬证据，几次就进可疑', () {
      final score = computeScore(buildApp(lockScreenLaunches: 3));
      expect(score.total, greaterThanOrEqualTo(35));
      expect(score.grade, Grade.suspect);
    });

    test('息屏启动 + 抢焦点叠加就是高危', () {
      final score = computeScore(buildApp(
        lockScreenLaunches: 3,
        focusStealCount: 3,
      ));
      expect(score.total, greaterThanOrEqualTo(60));
      expect(score.grade, Grade.high);
    });

    test('抢焦点 3 次算可疑', () {
      final score = computeScore(buildApp(focusStealCount: 3));
      expect(score.total, greaterThanOrEqualTo(35));
      expect(score.grade, Grade.suspect);
    });

    test('闲置自启只是线索，分数低', () {
      final score = computeScore(buildApp(idleSelfLaunches: 8));
      expect(score.total, lessThan(35));
      expect(score.grade, Grade.watch);
    });

    test('流量读不到就不给流量分，也不虚高', () {
      final withTraffic = computeScore(buildApp(trafficBytes: 400 * 1024 * 1024));
      final withoutTraffic = computeScore(buildApp(trafficBytes: -1));
      expect(withTraffic.total, greaterThan(withoutTraffic.total));
      expect(
        withoutTraffic.parts.any((p) => p.signal == AuditSignal.dataUsage),
        isFalse,
      );
    });

    test('有后台定位但没动过，只给一半分', () {
      final score = computeScore(buildApp(backgroundLocationGranted: true));
      final part = score.parts.firstWhere((p) => p.signal == AuditSignal.location);
      expect(part.points, lessThan(part.maxPoints));
    });

    test('有后台定位而且自己动过，定位这一项拿满', () {
      final score = computeScore(buildApp(
        backgroundLocationGranted: true,
        lockScreenLaunches: 1,
      ));
      final part = score.parts.firstWhere((p) => p.signal == AuditSignal.location);
      expect(part.points, part.maxPoints);
    });

    test('总分不会超过 100', () {
      final score = computeScore(buildApp(
        idleSelfLaunches: 50,
        lockScreenLaunches: 50,
        focusStealCount: 50,
        backgroundMillis: 100 * 3600000,
        trafficBytes: 10 * 1024 * 1024 * 1024,
        backgroundLocationGranted: true,
      ));
      expect(score.total, lessThanOrEqualTo(100));
    });
  });

  group('分档', () {
    test('按分数落到四档', () {
      expect(Grade.of(0), Grade.normal);
      expect(Grade.of(17), Grade.normal);
      expect(Grade.of(18), Grade.watch);
      expect(Grade.of(34), Grade.watch);
      expect(Grade.of(35), Grade.suspect);
      expect(Grade.of(59), Grade.suspect);
      expect(Grade.of(60), Grade.high);
      expect(Grade.of(100), Grade.high);
    });
  });

  group('榜单排序', () {
    test('分数高的排前面', () {
      final a = buildApp(idleSelfLaunches: 1);
      final b = buildApp(lockScreenLaunches: 3);
      final sorted = [a, b]..sort(compareAudits);
      expect(sorted.first.packageName, b.packageName);
      expect(sorted.first.score.total, greaterThan(sorted.last.score.total));
    });
  });
}
