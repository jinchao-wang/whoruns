import 'package:flutter/material.dart';

import '../models/audit.dart';
import '../services/audit_service.dart';
import '../services/export_service.dart';
import '../services/license_service.dart';
import '../services/settings_service.dart';
import '../services/usage_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/scoring.dart';
import '../widgets/common.dart';
import 'app_detail_screen.dart';
import 'activate_screen.dart';
import 'ios_screen.dart';

/// 审计台：首页。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _hasPermission = false;
  bool _checking = true;
  LicenseInfo? _license;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 用户去系统设置里开完权限再回来，立刻重查一遍。
    if (state == AppLifecycleState.resumed) {
      _bootstrap(runAudit: true);
    }
  }

  Future<void> _bootstrap({bool runAudit = false}) async {
    await SettingsService.instance.load();
    _license = await LicenseService.instance.current(
      deviceFingerprint: await UsageService.instance.deviceFingerprint(),
    );
    if (!mounted) return;
    setState(() => _checking = false);

    if (!UsageService.instance.isSupported) return;
    final granted = await UsageService.instance.hasUsageAccess();
    if (!mounted) return;
    setState(() => _hasPermission = granted);
    if (granted && runAudit) {
      await AuditService.instance.runAudit();
    }
  }

  Future<void> _runAudit() async {
    final error = await AuditService.instance.runAudit();
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _openPermissionSettings() async {
    await UsageService.instance.openUsageAccessSettings();
  }

  Future<void> _export() async {
    final report = AuditService.instance.report;
    if (report == null) return;
    final path = await ExportService.exportCsv(report);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(path == null ? '导出失败' : '已导出到 $path'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // iOS 上没有「使用情况访问权限」这回事，直接走另一条线。
    if (!UsageService.instance.isSupported) {
      return Scaffold(
        appBar: AppBar(title: const Text('谁在偷跑')),
        body: const IosScreen(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('谁在偷跑'),
        actions: [
          IconButton(
            tooltip: '导出报告',
            onPressed: _export,
            icon: const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([AuditService.instance, SettingsService.instance]),
        builder: (context, _) {
          if (_checking) {
            return const Center(child: CircularProgressIndicator());
          }
          return RefreshIndicator(
            onRefresh: _runAudit,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                if (!_hasPermission)
                  _PermissionCard(onGrant: _openPermissionSettings),
                const SizedBox(height: 12),
                _RangeSelector(
                  onChanged: (hours) async {
                    await SettingsService.instance.setRangeHours(hours);
                    await _runAudit();
                  },
                ),
                const SizedBox(height: 12),
                _AuditButton(
                  running: AuditService.instance.running,
                  onPressed: _runAudit,
                ),
                const SizedBox(height: 16),
                ..._buildResults(context),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildResults(BuildContext context) {
    final report = AuditService.instance.report;
    if (report == null) {
      return [
        const EmptyHint(
          icon: Icons.travel_explore,
          title: '还没查过',
          detail: '点上面的「开始审计」，看看这 24 小时到底谁在偷跑。',
        ),
      ];
    }

    final ranked = report.ranked;
    final unlocked = _license != null && _license!.isValid;
    final widgets = <Widget>[];

    widgets.add(_SummaryCard(report: report));
    widgets.add(const SizedBox(height: 12));

    if (ranked.isEmpty) {
      widgets.add(const EmptyHint(
        icon: Icons.verified_user,
        title: '这段时间挺干净',
        detail: '没有发现 App 在你没操作手机时自己动起来。',
      ));
      return widgets;
    }

    // 免费版只给看前 3 条；其余的锁住。
    final visible = unlocked ? ranked : ranked.take(LicenseService.freeAppLimit).toList();

    widgets.add(Row(
      children: [
        Text(
          '偷跑榜',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        Text(
          '过去 ${Fmt.duration(report.rangeEnd.difference(report.rangeStart).inMilliseconds)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
        ),
      ],
    ));
    widgets.add(const SizedBox(height: 8));

    for (final app in visible) {
      widgets.add(_AppTile(app: app));
      widgets.add(const SizedBox(height: 8));
    }

    if (!unlocked && ranked.length > visible.length) {
      widgets.add(_LockedCard(
        title: '还有 ${ranked.length - visible.length} 个 App 没显示',
        detail: '免费版只看最近 24 小时、榜单前 ${LicenseService.freeAppLimit} 条。'
            '买断 ¥18 或订阅，解锁全部历史记录和导出。',
      ));
    }

    return widgets;
  }
}

/// 权限引导卡。
class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.onGrant});

  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      icon: Icons.lock_person,
      title: '需要「使用情况访问权限」',
      subtitle: '这是系统给的特殊权限，只能你手动开。开了之后我们才能看到'
          '各 App 的前台时长、启动时机和流量——数据只在本机，不上传。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: onGrant,
            icon: const Icon(Icons.open_in_new),
            label: const Text('去系统设置里开启'),
          ),
          const SizedBox(height: 8),
          Text(
            '路径：设置 → 应用 → 特殊应用权限 → 使用情况访问权限 → 找到「谁在偷跑」并打开',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

/// 时间范围选择。
class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.onChanged});

  final ValueChanged<int> onChanged;

  static const _options = <int, String>{
    24: '24 小时',
    72: '3 天',
    168: '7 天',
    720: '30 天',
  };

  @override
  Widget build(BuildContext context) {
    final current = SettingsService.instance.rangeHours;
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final entry in _options.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(entry.value),
                selected: current == entry.key,
                onSelected: (_) => onChanged(entry.key),
              ),
            ),
        ],
      ),
    );
  }
}

/// 审计按钮。
class _AuditButton extends StatelessWidget {
  const _AuditButton({required this.running, required this.onPressed});

  final bool running;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton.icon(
        onPressed: running ? null : onPressed,
        icon: running
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.radar),
        label: Text(running ? '正在审计…' : '开始审计'),
      ),
    );
  }
}

/// 审计结论卡。
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.report});

  final AuditReport report;

  @override
  Widget build(BuildContext context) {
    final ranked = report.ranked;
    final high = report.highRiskCount;
    final suspect = report.suspectCount;
    final selfLaunches = report.plainSelfLaunches;

    return SectionCard(
      icon: Icons.shield,
      title: '结论',
      subtitle: '上次审计：${Fmt.ago(report.scannedAt)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            high > 0
                ? '有 $high 个 App 在高危偷跑'
                : suspect > 0
                    ? '有 $suspect 个 App 有点可疑'
                    : '暂时没发现明显的偷跑',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '这段时间一共记录到 $selfLaunches 次「没人在动手机时它自己弹到前台」，'
            '${report.trafficAvailable ? '流量数据也能读' : '流量数据这台系统读不到'}。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
          ),
          if (ranked.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...ranked.take(3).map((app) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          app.label,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 120,
                        child: ScoreBar(score: app.score.total, showValue: true),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

/// 榜单里的一项。
class _AppTile extends StatelessWidget {
  const _AppTile({required this.app});

  final AppAudit app;

  @override
  Widget build(BuildContext context) {
    final icon = AuditService.instance.iconOf(app.packageName);
    final score = app.score;
    final tags = <String>[];

    if (app.lockScreenLaunches > 0) {
      tags.add('息屏启动 ${app.lockScreenLaunches} 次');
    }
    if (app.focusStealCount > 0) {
      tags.add('抢焦点 ${app.focusStealCount} 次');
    }
    if (app.plainSelfLaunches > 0) {
      tags.add('自启 ${app.plainSelfLaunches} 次');
    }
    if (app.trafficAvailable && app.trafficMB > 1) {
      tags.add('流量 ${app.trafficMB.toStringAsFixed(0)} MB');
    }
    if (app.backgroundLocationGranted) {
      tags.add('有后台定位');
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AppDetailScreen(app: app),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: icon == null
                    ? Container(
                        width: 44,
                        height: 44,
                        color: context.appColors.neutralContainer,
                        child: const Icon(Icons.android),
                      )
                    : Image.memory(icon, width: 44, height: 44),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            app.label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (app.isSystemApp)
                          Text(
                            '系统',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: context.scheme.onSurfaceVariant,
                                ),
                          ),
                        const Spacer(),
                        GradeBadge(grade: score.grade, compact: true),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ScoreBar(score: score.total),
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final tag in tags)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: context.appColors.neutralContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                tag,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 付费墙。
class _LockedCard extends StatelessWidget {
  const _LockedCard({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      icon: Icons.lock,
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            detail,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ActivateScreen()),
              );
            },
            child: const Text('看看怎么解锁'),
          ),
        ],
      ),
    );
  }
}
