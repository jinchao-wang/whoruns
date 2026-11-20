import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/audit.dart';
import '../services/audit_service.dart';
import '../services/settings_service.dart';
import '../services/usage_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/scoring.dart';
import '../widgets/common.dart';

/// 某个 App 的详情：证据链 + 处置建议。
class AppDetailScreen extends StatelessWidget {
  const AppDetailScreen({super.key, required this.app});

  final AppAudit app;

  @override
  Widget build(BuildContext context) {
    final score = app.score;
    final bytes = AuditService.instance.iconOf(app.packageName);
    final evidence = [...app.evidence]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Scaffold(
      appBar: AppBar(title: Text(app.label)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _Header(app: app, icon: bytes, score: score),
          const SizedBox(height: 12),
          SectionCard(
            icon: Icons.equalizer,
            title: '偷跑指数 ${score.total}',
            subtitle: '满分 100。每一分都要有下面的证据撑着，没有证据就不给分。',
            child: score.parts.isEmpty
                ? const Text('这段时间它没有可查的异常行为。')
                : Column(
                    children: [
                      for (final part in score.parts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      part.signal.label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${part.points} / ${part.maxPoints}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: context.scheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: part.ratio,
                                  minHeight: 6,
                                  backgroundColor:
                                      context.appColors.neutralContainer,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                part.reason,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: context.scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            icon: Icons.fact_check,
            title: '证据（${evidence.length}）',
            subtitle: '硬证据 = 系统事件直接证明；线索 = 需要你自己再确认一下。',
            child: evidence.isEmpty
                ? const Text('没有记录到可疑事件。')
                : Column(
                    children: [
                      for (final item in evidence)
                        _EvidenceRow(item: item),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            icon: Icons.bar_chart,
            title: '用量事实',
            child: Column(
              children: [
                _FactRow(
                  label: '前台时长',
                  value: Fmt.duration(app.foregroundMillis),
                ),
                _FactRow(
                  label: '后台时长',
                  value: Fmt.duration(app.backgroundMillis),
                ),
                _FactRow(
                  label: '移动流量',
                  value: app.trafficAvailable
                      ? Fmt.bytes(app.trafficBytes)
                      : '这台系统读不到',
                ),
                _FactRow(
                  label: '后台定位权限',
                  value: app.backgroundLocationGranted
                      ? '已授予（不等于它定位过）'
                      : app.hasBackgroundLocation
                          ? '声明了但没授予'
                          : '没有',
                ),
                _FactRow(label: '包名', value: app.packageName),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Actions(app: app),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.app, required this.icon, required this.score});

  final AppAudit app;
  final Uint8List? icon;
  final AuditScore score;

  @override
  Widget build(BuildContext context) {
    final bytes = icon;
    return SectionCard(
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: bytes == null
                ? Container(
                    width: 56,
                    height: 56,
                    color: context.appColors.neutralContainer,
                    child: const Icon(Icons.android, size: 30),
                  )
                : Image.memory(bytes, width: 56, height: 56),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.label,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  score.grade.hint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          GradeBadge(grade: score.grade),
        ],
      ),
    );
  }
}

class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({required this.item});

  final Evidence item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: EvidenceLevelTag(level: item.level),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.detail,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${Fmt.stamp(item.timestamp)} · ${item.signal.label}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.scheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// 处置建议。
class _Actions extends StatelessWidget {
  const _Actions({required this.app});

  final AppAudit app;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      icon: Icons.build,
      title: '怎么处理',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _suggestion(app),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () async {
              await UsageService.instance.openAppSettings(app.packageName);
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('打开它的系统设置'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await SettingsService.instance.setIgnoredOne(app.packageName, true);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已把「${app.label}」加进白名单')),
              );
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.visibility_off),
            label: const Text('加进白名单（别再提醒我）'),
          ),
        ],
      ),
    );
  }

  String _suggestion(AppAudit app) {
    if (app.lockScreenLaunches > 0) {
      return '它在屏幕黑着的时候还启动过 ${app.lockScreenLaunches} 次。'
          '去系统设置里把它的后台活动、后台弹出通知都关掉，'
          '如果它不需要定位，再把「始终允许」的位置权限改成「仅使用期间」。';
    }
    if (app.focusStealCount > 0) {
      return '它抢过 ${app.focusStealCount} 次焦点。'
          '在它的设置里关掉「自启动」「后台弹出通知」，'
          '另外系统设置里的「后台 App 刷新」里把它挪到「限制」。';
    }
    if (app.backgroundLocationGranted && app.selfLaunches > 0) {
      return '它有后台定位权限，而且确实在后台活动过。'
          '建议去系统设置里把位置权限改成「仅使用期间」，或者直接把它从后台限制里放出来。';
    }
    if (app.trafficAvailable && app.trafficMB > 200) {
      return '它消耗了 ${app.trafficMB.toStringAsFixed(0)} MB 流量。'
          '先看看是不是在同步图片/视频，必要时在 App 内关掉「预下载」和「高清画质」。';
    }
    return '先在它的系统设置里关掉「自启动」和「后台弹出通知」，'
        '再看一两天，偷跑指数应该会掉下来。';
  }
}
