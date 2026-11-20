import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/usage_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// iOS 版本。
///
/// iOS 不允许第三方 App 读取别的 App 的使用情况（这是苹果的隐私设计，不是技术难度问题）。
/// 所以在 iOS 上我们**不假装**能做 Android 那套审计，而是给三样真能做的事：
/// 1. 本机健康自检；
/// 2. 告诉你系统自带的那条路怎么走；
/// 3. 一份可以照着做的隐私自查清单。
class IosScreen extends StatefulWidget {
  const IosScreen({super.key});

  @override
  State<IosScreen> createState() => _IosScreenState();
}

class _IosScreenState extends State<IosScreen> {
  Map<String, dynamic> _health = const {};
  final Set<String> _checked = <String>{};

  static const _checklist = <String, String>{
    '购物类': '购物 App 常驻后台比价、抢券，通知里全是「你该省钱了」',
    '短视频': '短视频 App 会预下载下一批视频，流量和存储都是它吃掉的',
    '地图/出行': '地图类 App 拿「始终允许」的定位权限，会一直上报位置',
    '资讯/推送': '资讯 App 靠推送拉回点击率，后台唤醒频率高得吓人',
    '输入法': '输入法为了「智能联想」会读你输入的内容，权限最该收紧',
    '安全/管家': '预装管家类 App 常驻后台扫描，耗电和流量都在它身上',
    '金融/支付': '支付类 App 不该有后台定位和自启动，开了就关掉',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final health = await UsageService.instance.deviceHealth();
    if (!mounted) return;
    setState(() => _health = health);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          SectionCard(
            icon: Icons.info_outline,
            title: 'iOS 上我们看不到别的 App',
            subtitle: '苹果不允许第三方 App 读取其它 App 的使用情况，'
                '这是系统级的隐私保护，没有绕过的办法。'
                '所以这里的「谁在偷跑」换成了下面这些能真正帮到你的东西。',
            child: const Text(
              'Android 版本能直接读系统事件，直接告诉你哪个 App 在息屏时自己启动。'
              'iOS 版本做不到这一点，也不打算用「大概猜一猜」来糊弄你。',
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            icon: Icons.monitor_heart,
            title: '本机健康自检',
            subtitle: '这些是系统允许读取的本机状态。',
            child: Column(
              children: [
                _HealthRow(
                  icon: Icons.battery_std,
                  label: '电量',
                  value: _batteryText(),
                ),
                _HealthRow(
                  icon: Icons.sd_storage,
                  label: '存储余量',
                  value: _storageText(),
                ),
                _HealthRow(
                  icon: Icons.device_thermostat,
                  label: '温度状态',
                  value: _thermalText(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            icon: Icons.route,
            title: '系统自带的那条路',
            subtitle: '苹果其实把「谁在偷跑」的答案放在设置里，只是藏得深。',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StepRow(
                  index: 1,
                  text: '设置 → 屏幕使用时间 → 查看 App 使用时间',
                ),
                _StepRow(
                  index: 2,
                  text: '设置 → 隐私与安全性 → 定位服务，逐个 App 改成「使用期间」',
                ),
                _StepRow(
                  index: 3,
                  text: '设置 → 通用 → 后台 App 刷新，关掉不用的',
                ),
                _StepRow(
                  index: 4,
                  text: '在「屏幕使用时间」里限制每天的使用时长，'
                      '对最偷跑的那几个最有效',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            icon: Icons.checklist,
            title: '隐私自查清单',
            subtitle: '勾上你担心的类型，生成一份可以直接照着做的清单。',
            child: Column(
              children: [
                for (final entry in _checklist.entries)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: _checked.contains(entry.key),
                    title: Text(
                      entry.key,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      entry.value,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.scheme.onSurfaceVariant,
                          ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _checked.add(entry.key);
                        } else {
                          _checked.remove(entry.key);
                        }
                      });
                    },
                  ),
                if (_checked.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _copyChecklist(context),
                    icon: const Icon(Icons.copy),
                    label: const Text('复制清单'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _batteryText() {
    final level = _health['batteryLevel'];
    if (level is! int) return '读不到';
    final charging = _health['charging'] == true;
    return '$level%${charging ? '（充电中）' : ''}';
  }

  String _storageText() {
    final free = _health['storageFreeBytes'];
    if (free is! int) return '读不到';
    return '可用 ${Fmt.gb(free)}';
  }

  String _thermalText() {
    final status = _health['thermalStatus'];
    if (status is! int) return '读不到';
    const names = {
      0: '正常',
      1: '轻微发热',
      2: '发热',
      3: '严重发热',
      4: '过热',
      5: '严重过热',
      6: '正在关机',
    };
    return names[status] ?? '状态 $status';
  }

  void _copyChecklist(BuildContext context) {
    final buffer = StringBuffer('我要收紧的权限：\n');
    for (final key in _checked) {
      buffer.writeln('· $key —— ${_checklist[key]}');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('清单已复制')),
    );
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.scheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.appColors.neutralContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$index',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}
