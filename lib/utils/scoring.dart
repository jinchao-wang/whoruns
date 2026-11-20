import '../models/audit.dart';

/// 各维度的满分。总分封顶 100。
///
/// 为什么硬证据权重这么高：
/// 「息屏时它还在启动后台任务」「上一个 App 还没退到后台它就压上来了」
/// 这两条是系统事件直接证明的，误报概率极低，
/// 出现一次就值得用户立刻去看一眼。
///
/// 为什么不用「归一化到百分比」：
/// 归一化会把「只有一个信号有数据」的情况放大成满分
/// （比如流量读不到时，剩下的信号平摊到 100 分，一个普通 App 也能拿 60 分）。
/// 这里用绝对分：满分 140，封顶 100，缺数据就是缺数据，不会虚高。
class ScoreWeights {
  /// 息屏启动（硬证据）。
  static const int lockScreen = 45;

  /// 抢焦点（硬证据）。
  static const int focusSteal = 35;

  /// 闲置自启（线索）。
  static const int selfLaunch = 20;

  /// 后台驻留。
  static const int backgroundStay = 12;

  /// 流量。
  static const int dataUsage = 18;

  /// 定位嫌疑。
  static const int location = 10;

  static const int maxTotal =
      lockScreen + focusSteal + selfLaunch + backgroundStay + dataUsage + location;
}

/// 阈值：超过这个量才算「多」。
class ScoreThresholds {
  /// 息屏启动几次算多。
  static const double lockScreenCount = 3;

  /// 抢焦点几次算多。
  static const double focusStealCount = 3;

  /// 闲置自启几次算多。
  static const double selfLaunchCount = 8;

  /// 后台待多久（小时）算多。
  static const double backgroundHours = 8;

  /// 流量多少 MB 算多。
  static const double trafficMB = 300;
}

/// 给一个 App 打分。
///
/// 纯函数：同样的输入永远得到同样的输出，方便单测。
AuditScore computeScore(AppAudit app) {
  final parts = <ScorePart>[];

  // 息屏启动：屏幕是黑的，用户不可能刚点过它。
  final lock = app.lockScreenLaunches.toDouble();
  if (lock > 0) {
    final ratio = _ratio(lock, ScoreThresholds.lockScreenCount);
    parts.add(ScorePart(
      signal: AuditSignal.lockScreenLaunch,
      points: (ratio * ScoreWeights.lockScreen).round(),
      maxPoints: ScoreWeights.lockScreen,
      reason: '息屏状态下启动了 $lock 次',
    ));
  }

  // 抢焦点弹窗：上一个 App 根本没失去焦点。
  final steals = app.focusStealCount.toDouble();
  if (steals > 0) {
    final ratio = _ratio(steals, ScoreThresholds.focusStealCount);
    parts.add(ScorePart(
      signal: AuditSignal.focusSteal,
      points: (ratio * ScoreWeights.focusSteal).round(),
      maxPoints: ScoreWeights.focusSteal,
      reason: '压在别的 App 上面弹了 $steals 次',
    ));
  }

  // 闲置自启：只能算线索，但次数多了也说明问题。
  final idle = app.idleSelfLaunches.toDouble();
  if (idle > 0) {
    final ratio = _ratio(idle, ScoreThresholds.selfLaunchCount);
    parts.add(ScorePart(
      signal: AuditSignal.selfLaunch,
      points: (ratio * ScoreWeights.selfLaunch).round(),
      maxPoints: ScoreWeights.selfLaunch,
      reason: '长时间没人操作时它自己弹到前台 $idle 次',
    ));
  }

  // 后台驻留。
  if (app.backgroundMillis > 0) {
    final ratio = _ratio(app.backgroundHours, ScoreThresholds.backgroundHours);
    parts.add(ScorePart(
      signal: AuditSignal.backgroundStay,
      points: (ratio * ScoreWeights.backgroundStay).round(),
      maxPoints: ScoreWeights.backgroundStay,
      reason: '后台待了 ${app.backgroundHours.toStringAsFixed(1)} 小时',
    ));
  }

  // 流量。读不到就整条不算，不拿 0 分假装「没有」。
  if (app.trafficAvailable && app.trafficBytes > 0) {
    final ratio = _ratio(app.trafficMB, ScoreThresholds.trafficMB);
    parts.add(ScorePart(
      signal: AuditSignal.dataUsage,
      points: (ratio * ScoreWeights.dataUsage).round(),
      maxPoints: ScoreWeights.dataUsage,
      reason: '消耗了 ${app.trafficMB.toStringAsFixed(0)} MB 流量',
    ));
  }

  // 定位嫌疑：只是线索。有后台定位权限 + 自己动过，才给满分。
  if (app.backgroundLocationGranted) {
    final points = app.selfLaunches > 0
        ? ScoreWeights.location
        : (ScoreWeights.location * 0.6).round();
    parts.add(ScorePart(
      signal: AuditSignal.location,
      points: points,
      maxPoints: ScoreWeights.location,
      reason: app.selfLaunches > 0
          ? '有后台定位权限，而且确实在后台动过'
          : '有后台定位权限（只是权限事实，不等于它定位过）',
    ));
  }

  final total = parts.fold(0, (sum, p) => sum + p.points).clamp(0, 100);
  return AuditScore(
    total: total,
    grade: Grade.of(total),
    parts: parts,
  );
}

double _ratio(double value, double threshold) {
  if (threshold <= 0) return 0;
  return (value / threshold).clamp(0.0, 1.0);
}

/// 给榜单排序用：分数高的排前面，同分时按自启次数、后台时长排。
int compareAudits(AppAudit a, AppAudit b) {
  final byScore = b.score.total.compareTo(a.score.total);
  if (byScore != 0) return byScore;
  final byLaunch = b.selfLaunches.compareTo(a.selfLaunches);
  if (byLaunch != 0) return byLaunch;
  return b.backgroundMillis.compareTo(a.backgroundMillis);
}

/// 把评分挂到模型上，方便各处直接 `app.score.total`。
extension AppAuditScoring on AppAudit {
  AuditScore get score => computeScore(this);
}

extension AuditReportScoring on AuditReport {
  int get highRiskCount => apps.where((a) => a.score.grade == Grade.high).length;

  int get suspectCount =>
      apps.where((a) => a.score.grade == Grade.suspect).length;

  int get watchCount => apps.where((a) => a.score.grade == Grade.watch).length;

  /// 榜单：按分数排序，去掉用户忽略的 App。
  List<AppAudit> get ranked {
    final list = apps.where((a) => !a.ignored).toList()
      ..sort(compareAudits);
    return list;
  }
}
