/// 审计模型：把「谁在偷跑」这件事拆成可核对的证据。
///
/// 设计原则：**只呈现系统给得出的事实，不替用户下结论**。
/// 每一条发现都要能指回一个系统事件或一个明确的事实（权限、流量数字），
/// 并用证据等级告诉用户「这条有多硬」。
library;

/// 一条发现有多硬。
enum EvidenceLevel {
  /// 硬证据：系统事件直接证明，系统日志里查得到。
  hard('硬证据', '系统事件直接证明，可回溯'),

  /// 线索：单项不足以定罪，需要结合其它信号看。
  lead('线索', '需要结合其它信号一起看'),

  /// 用户标注：用户自己标记的，不来自系统。
  userMarked('用户标注', '你自己标记的，不来自系统数据');

  const EvidenceLevel(this.label, this.hint);

  final String label;
  final String hint;

  static EvidenceLevel parse(String? raw) {
    for (final v in EvidenceLevel.values) {
      if (v.name == raw) return v;
    }
    return EvidenceLevel.lead;
  }
}

/// 偷跑的几种典型形态。
enum AuditSignal {
  selfLaunch('后台自启', '没人在动手机时，它自己弹到了前台'),
  lockScreenLaunch('息屏启动', '屏幕黑着的时候它就起来了'),
  focusSteal('抢占焦点', '压在别的 App 上面弹窗，把你拽走'),
  backgroundStay('后台驻留', '长时间待在后台不退出'),
  dataUsage('流量偷跑', '消耗了流量'),
  location('定位嫌疑', '有后台定位权限，而且一直在活动');

  const AuditSignal(this.label, this.hint);

  final String label;
  final String hint;

  static AuditSignal parse(String? raw) {
    for (final v in AuditSignal.values) {
      if (v.name == raw) return v;
    }
    return AuditSignal.backgroundStay;
  }
}

/// 一条证据。
///
/// 每条证据都要说清三件事：发生了什么、什么时候、有多硬。
class Evidence {
  const Evidence({
    required this.signal,
    required this.level,
    required this.timestamp,
    required this.detail,
    this.magnitude = 0,
  });

  final AuditSignal signal;
  final EvidenceLevel level;
  final int timestamp;
  final String detail;

  /// 数值型证据的量纲（分钟、MB、次数…），用于排序和展示。
  final double magnitude;

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(timestamp);

  factory Evidence.fromMap(Map<String, dynamic> map) {
    return Evidence(
      signal: AuditSignal.parse(map['signal'] as String?),
      level: EvidenceLevel.parse(map['level'] as String?),
      timestamp: (map['ts'] as num?)?.toInt() ?? 0,
      detail: (map['detail'] as String?) ?? '',
      magnitude: (map['magnitude'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'signal': signal.name,
        'level': level.name,
        'ts': timestamp,
        'detail': detail,
        'magnitude': magnitude,
      };
}

/// 一个 App 的审计结果。
class AppAudit {
  const AppAudit({
    required this.packageName,
    required this.label,
    required this.foregroundMillis,
    required this.backgroundMillis,
    required this.idleSelfLaunches,
    required this.lockScreenLaunches,
    required this.focusStealCount,
    required this.trafficBytes,
    required this.hasBackgroundLocation,
    required this.backgroundLocationGranted,
    required this.isSystemApp,
    required this.evidence,
    this.ignored = false,
  });

  final String packageName;
  final String label;

  /// 屏幕在前台的时长。
  final int foregroundMillis;

  /// 待在后台的时长。
  final int backgroundMillis;

  /// 长时间没人操作手机，它却自己弹到了前台（线索级）。
  final int idleSelfLaunches;

  /// 息屏状态下它还启动过（硬证据）。
  final int lockScreenLaunches;

  /// 压在别的 App 上面抢焦点（硬证据）。
  final int focusStealCount;

  /// 流量字节数（移动 + Wi-Fi 合计）；-1 表示这台机器/这个系统版本拿不到。
  final int trafficBytes;

  final bool hasBackgroundLocation;
  final bool backgroundLocationGranted;
  final bool isSystemApp;
  final List<Evidence> evidence;

  /// 用户把它加进了白名单（不再出现在榜里，但详情仍可查）。
  final bool ignored;

  bool get trafficAvailable => trafficBytes >= 0;

  double get backgroundHours => backgroundMillis / 3600000.0;

  double get foregroundHours => foregroundMillis / 3600000.0;

  double get trafficMB => trafficBytes < 0 ? 0 : trafficBytes / 1048576.0;

  /// 它自己动起来的总次数（三种证据加起来）。
  int get selfLaunches =>
      idleSelfLaunches + lockScreenLaunches + focusStealCount;

  /// 「用户没碰手机时它自己弹前台」的次数。
  int get plainSelfLaunches => idleSelfLaunches;

  AppAudit copyWith({bool? ignored, List<Evidence>? evidence}) {
    return AppAudit(
      packageName: packageName,
      label: label,
      foregroundMillis: foregroundMillis,
      backgroundMillis: backgroundMillis,
      idleSelfLaunches: idleSelfLaunches,
      lockScreenLaunches: lockScreenLaunches,
      focusStealCount: focusStealCount,
      trafficBytes: trafficBytes,
      hasBackgroundLocation: hasBackgroundLocation,
      backgroundLocationGranted: backgroundLocationGranted,
      isSystemApp: isSystemApp,
      evidence: evidence ?? this.evidence,
      ignored: ignored ?? this.ignored,
    );
  }

  factory AppAudit.fromMap(Map<String, dynamic> map) {
    final rawEvidence = (map['evidence'] as List?) ?? const [];
    final evidence = rawEvidence
        .whereType<Map>()
        .map((e) => Evidence.fromMap(Map<String, dynamic>.from(e)))
        .toList();

    // 计数优先用原生层直接给的数；没给就从证据列表里数出来。
    // 两边都留着，是因为不同机型上原生能拿到的信息不一样。
    int countOf(AuditSignal signal) =>
        evidence.where((e) => e.signal == signal).length;

    return AppAudit(
      packageName: (map['package'] as String?) ?? '',
      label: (map['label'] as String?) ?? '',
      foregroundMillis: (map['foregroundMillis'] as num?)?.toInt() ?? 0,
      backgroundMillis: (map['backgroundMillis'] as num?)?.toInt() ?? 0,
      idleSelfLaunches: (map['idleSelfLaunches'] as num?)?.toInt() ??
          countOf(AuditSignal.selfLaunch),
      lockScreenLaunches: (map['lockScreenLaunches'] as num?)?.toInt() ??
          countOf(AuditSignal.lockScreenLaunch),
      focusStealCount: (map['focusStealCount'] as num?)?.toInt() ??
          countOf(AuditSignal.focusSteal),
      trafficBytes: (map['trafficBytes'] as num?)?.toInt() ?? -1,
      hasBackgroundLocation: (map['hasBackgroundLocation'] as bool?) ?? false,
      backgroundLocationGranted:
          (map['backgroundLocationGranted'] as bool?) ?? false,
      isSystemApp: (map['isSystemApp'] as bool?) ?? false,
      evidence: evidence,
    );
  }
}

/// 一次审计的完整结果。
class AuditReport {
  const AuditReport({
    required this.scannedAt,
    required this.rangeStart,
    required this.rangeEnd,
    required this.apps,
    required this.trafficAvailable,
  });

  final DateTime scannedAt;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final List<AppAudit> apps;

  /// 整台机器上能不能读到分 App 流量。
  final bool trafficAvailable;

  int get totalSelfLaunches =>
      apps.fold(0, (sum, a) => sum + a.selfLaunches);

  /// 自启总次数（不含息屏启动，息屏启动单独看）。
  int get plainSelfLaunches =>
      apps.fold(0, (sum, a) => sum + a.plainSelfLaunches);

  factory AuditReport.fromMap(Map<String, dynamic> map) {
    final rawApps = (map['apps'] as List?) ?? const [];
    return AuditReport(
      scannedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['scannedAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      ),
      rangeStart: DateTime.fromMillisecondsSinceEpoch(
        (map['rangeStart'] as num?)?.toInt() ?? 0,
      ),
      rangeEnd: DateTime.fromMillisecondsSinceEpoch(
        (map['rangeEnd'] as num?)?.toInt() ?? 0,
      ),
      trafficAvailable: (map['trafficAvailable'] as bool?) ?? false,
      apps: rawApps
          .whereType<Map>()
          .map((e) => AppAudit.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// 风险档位。
enum Grade {
  high('高危', '它在偷跑'),
  suspect('可疑', '有点不对劲'),
  watch('留意', '看一眼'),
  normal('正常', '没什么问题');

  const Grade(this.label, this.hint);

  final String label;
  final String hint;

  /// 分档分数线：高危 60 / 可疑 35 / 留意 18。
  static const int highThreshold = 60;
  static const int suspectThreshold = 35;
  static const int watchThreshold = 18;

  static Grade of(int score) {
    if (score >= highThreshold) return Grade.high;
    if (score >= suspectThreshold) return Grade.suspect;
    if (score >= watchThreshold) return Grade.watch;
    return Grade.normal;
  }
}

/// 评分里的一条：某个信号贡献了多少分、为什么。
class ScorePart {
  const ScorePart({
    required this.signal,
    required this.points,
    required this.maxPoints,
    required this.reason,
  });

  final AuditSignal signal;
  final int points;
  final int maxPoints;
  final String reason;

  double get ratio => maxPoints == 0 ? 0 : points / maxPoints;
}

/// 一个 App 的偷跑指数。
///
/// 评分逻辑在 [utils/scoring.dart]，模型这一层只负责描述结果。
class AuditScore {
  const AuditScore({
    required this.total,
    required this.grade,
    required this.parts,
  });

  final int total;
  final Grade grade;
  final List<ScorePart> parts;
}
