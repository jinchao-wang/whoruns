import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/license_service.dart';
import '../services/usage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// 授权码激活页。
class ActivateScreen extends StatefulWidget {
  const ActivateScreen({super.key});

  @override
  State<ActivateScreen> createState() => _ActivateScreenState();
}

class _ActivateScreenState extends State<ActivateScreen> {
  final TextEditingController _controller = TextEditingController();
  String? _message;
  bool _ok = false;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final fingerprint = await UsageService.instance.deviceFingerprint();
    final error = await LicenseService.instance.activate(
      _controller.text,
      deviceFingerprint: fingerprint,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ok = error == null;
      _message = error ?? '激活成功，功能已全部解锁。';
    });
    if (error == null) {
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('解锁完整版')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          SectionCard(
            icon: Icons.workspace_premium,
            title: '两种买法',
            child: Column(
              children: const [
                _PlanRow(
                  name: '买断',
                  price: '¥18',
                  detail: '一次买断，永久可用。以后 App 升级都还是这个价格。',
                ),
                SizedBox(height: 10),
                _PlanRow(
                  name: '订阅',
                  price: '¥6 / 月，¥48 / 年',
                  detail: '按年订阅更划算；订阅期内功能和买断一样。',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            icon: Icons.vpn_key,
            title: '输入授权码',
            subtitle: '买完之后会拿到一串以 WR1. 开头的授权码，粘贴进来就行。'
                '授权码在本机离线验签，不用联网、不用注册账号。',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _controller,
                  maxLines: 2,
                  minLines: 2,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    hintText: 'WR1.xxxxx.yyyyy',
                    hintStyle: TextStyle(fontSize: 13),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _activate,
                  child: Text(_busy ? '正在校验…' : '激活'),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        _ok ? Icons.check_circle : Icons.error_outline,
                        size: 18,
                        color: _ok
                            ? context.appColors.safe
                            : context.appColors.danger,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _message!,
                          style: TextStyle(
                            color: _ok
                                ? context.appColors.safe
                                : context.appColors.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            icon: Icons.help_outline,
            title: '在哪买',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '本项目在 GitHub 上开源发布，装机包在 Releases 里，'
                  '授权码单独出售（这样源码和付费是分开的，源码随便看）。\n\n'
                  '买断 ¥18 / 订阅 ¥6 月 / ¥48 年，付款后把订单号发给开发者，'
                  '会给你一串授权码。',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _copyRepoLink(context),
                  icon: const Icon(Icons.copy),
                  label: const Text('复制项目地址'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _copyRepoLink(BuildContext context) {
    Clipboard.setData(const ClipboardData(text: 'github.com/jinchao-wang/whoruns'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制：github.com/jinchao-wang/whoruns')),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.name,
    required this.price,
    required this.detail,
  });

  final String name;
  final String price;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: context.appColors.neutralContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                price,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
