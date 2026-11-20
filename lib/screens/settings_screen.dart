import 'package:flutter/material.dart';

import '../models/audit.dart';
import '../services/audit_service.dart';
import '../services/export_service.dart';
import '../services/license_service.dart';
import '../services/settings_service.dart';
import '../services/usage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'activate_screen.dart';

/// 设置页。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  LicenseInfo? _license;
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final license = await LicenseService.instance.current(
      deviceFingerprint: await UsageService.instance.deviceFingerprint(),
    );
    final permission = await UsageService.instance.hasUsageAccess();
    if (!mounted) return;
    setState(() {
      _license = license;
      _hasPermission = permission;
    });
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = _license != null && _license!.isValid;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: AnimatedBuilder(
        animation: SettingsService.instance,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              SectionCard(
                icon: Icons.lock_open,
                title: '使用情况访问权限',
                subtitle: _hasPermission
                    ? '已开启，可以审计了。'
                    : '还没开。系统规定这个权限只能你手动开。',
                child: _hasPermission
                    ? OutlinedButton.icon(
                        onPressed: () async {
                          await UsageService.instance.openUsageAccessSettings();
                        },
                        icon: const Icon(Icons.settings),
                        label: const Text('去系统设置看看'),
                      )
                    : FilledButton.icon(
                        onPressed: () async {
                          await UsageService.instance.openUsageAccessSettings();
                        },
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('去开启'),
                      ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                icon: Icons.workspace_premium,
                title: '套餐',
                subtitle: unlocked
                    ? (_license!.isBuyout
                        ? '买断版，已永久解锁。'
                        : '订阅版，还有 ${_license!.daysLeft} 天到期。')
                    : '免费版：只看最近 24 小时、榜单前 3 条。',
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ActivateScreen(),
                            ),
                          );
                          await _load();
                        },
                        child: Text(unlocked ? '查看/更换授权码' : '解锁完整版'),
                      ),
                    ),
                    if (unlocked) ...[
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: () async {
                          await LicenseService.instance.deactivate();
                          await _load();
                        },
                        child: const Text('解除授权'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                icon: Icons.notifications_active,
                title: '偷跑告警',
                subtitle: '定期查一次，发现硬证据就发通知。'
                    '用的是不精确闹钟，不会在系统里显示成「闹钟」。',
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('开启定期告警'),
                      value: SettingsService.instance.alertsEnabled,
                      onChanged: (value) async {
                        await SettingsService.instance.setAlertsEnabled(value);
                        if (value) {
                          await UsageService.instance.requestNotificationPermission();
                        }
                        await UsageService.instance.setAlertSchedule(
                          enabled: value,
                          everyMinutes: SettingsService.instance.alertMinutes,
                        );
                      },
                    ),
                    if (SettingsService.instance.alertsEnabled)
                      DropdownButtonFormField<int>(
                        initialValue: SettingsService.instance.alertMinutes,
                        decoration: const InputDecoration(
                          labelText: '多久查一次',
                        ),
                        items: const [
                          DropdownMenuItem(value: 15, child: Text('15 分钟')),
                          DropdownMenuItem(value: 30, child: Text('30 分钟')),
                          DropdownMenuItem(value: 60, child: Text('1 小时')),
                          DropdownMenuItem(value: 180, child: Text('3 小时')),
                        ],
                        onChanged: (value) async {
                          if (value == null) return;
                          await SettingsService.instance.setAlertMinutes(value);
                          await UsageService.instance.setAlertSchedule(
                            enabled: true,
                            everyMinutes: value,
                          );
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                icon: Icons.visibility_off,
                title: '白名单',
                subtitle: '不想再看到的 App。榜单里不再出现，详情里还能查。',
                child: _WhitelistBody(
                  onChanged: () => setState(() {}),
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                icon: Icons.ios_share,
                title: '导出报告',
                subtitle: '导出成 CSV，存到你手机里。数据不会上传到任何服务器。',
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final report = AuditService.instance.report;
                    if (report == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('还没审计过，没有可导出的内容')),
                      );
                      return;
                    }
                    final path = await ExportService.exportCsv(report);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(path == null ? '导出失败' : '已导出到 $path'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('导出 CSV'),
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                icon: Icons.info_outline,
                title: '关于',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '谁在偷跑 v1.0.0\n'
                      '所有数据只在本机，不上传、不联网、没有统计 SDK。\n'
                      '源码：github.com/jinchao-wang/whoruns',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '隐私政策',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '采集的内容：各 App 的前台/后台时长、活动事件（何时被启动、'
                      '是否抢焦点）、分 App 流量、各 App 的权限声明情况。\n'
                      '不采集：任何个人内容（短信、聊天、相册）、任何账号信息。\n'
                      '数据流向：不离开设备；只有你主动点导出时才会生成 CSV 文件。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WhitelistBody extends StatelessWidget {
  const _WhitelistBody({required this.onChanged});

  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final ignored = SettingsService.instance.ignoredPackages;
    final report = AuditService.instance.report;

    if (ignored.isEmpty) {
      return const Text('白名单是空的。在某个 App 的详情页里可以把它加进来。');
    }

    return Column(
      children: [
        for (final pkg in ignored.toList()..sort())
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.visibility_off, size: 20),
            title: Text(
              _nameOf(report, pkg),
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: Text(
              pkg,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.scheme.onSurfaceVariant,
                  ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.undo),
              tooltip: '移出白名单',
              onPressed: () async {
                await SettingsService.instance.setIgnoredOne(pkg, false);
                onChanged();
              },
            ),
          ),
      ],
    );
  }

  String _nameOf(AuditReport? report, String pkg) {
    if (report == null) return pkg;
    for (final app in report.apps) {
      if (app.packageName == pkg) return app.label;
    }
    return pkg;
  }
}
