// 授权码签发工具（离线）。
//
// 用法：
//   dart run tool/license_tool.dart keygen
//   dart run tool/license_tool.dart issue --plan buyout --count 5
//   dart run tool/license_tool.dart issue --plan subscription --days 365 --count 3
//   dart run tool/license_tool.dart issue --plan buyout --note "张三" --bind <设备指纹>
//   dart run tool/license_tool.dart verify WR1.xxx.yyy
//
// 私钥落在仓库外的 secrets 目录（默认 ../.whoruns-secrets/），
// 千万别提交进 git —— 提交了就等于把授权码白送。
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

const _defaultSecretDir = '../.whoruns-secrets';
const _secretFileName = 'license_key.json';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first == 'help' || args.first == '-h') {
    _printHelp();
    return;
  }

  final command = args.first;
  final rest = args.sublist(1);

  switch (command) {
    case 'keygen':
      await _keygen(rest);
    case 'issue':
      await _issue(rest);
    case 'verify':
      await _verify(rest);
    default:
      stderr.writeln('未知命令：$command');
      _printHelp();
      exit(2);
  }
}

void _printHelp() {
  stdout.writeln('''
授权码工具

  keygen                                  生成一对 Ed25519 密钥（只做一次）
  issue --plan buyout|subscription        签发授权码
        [--days N] [--count N] [--note 文本] [--bind 设备指纹] [--out 文件]
  verify <授权码>                          验签并打印内容
''');
}

String? _arg(List<String> args, String name) {
  final index = args.indexOf('--$name');
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

File _secretFile(String dir) => File('$dir/$_secretFileName');

Future<void> _keygen(List<String> args) async {
  final dir = _arg(args, 'dir') ?? _defaultSecretDir;
  final file = _secretFile(dir);
  if (file.existsSync()) {
    stdout.writeln('密钥已存在：${file.path}（不覆盖，删掉再生成）');
    stdout.writeln('公钥：${_readPublicKey(file)}');
    return;
  }

  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPair();
  final privateKey = await keyPair.extractPrivateKeyBytes();
  final publicKey = await keyPair.extractPublicKey();

  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'privateKeyHex': _toHex(privateKey),
      'publicKeyHex': _toHex(publicKey.bytes),
      'createdAt': DateTime.now().toIso8601String(),
    }),
  );

  stdout.writeln('密钥已写入：${file.path}');
  stdout.writeln('');
  stdout.writeln('公钥（贴到 lib/services/license_service.dart 的 publicKeyHex）：');
  stdout.writeln(_toHex(publicKey.bytes));
  stdout.writeln('');
  stdout.writeln('私钥只存在这个文件里，别提交进 git。');
}

Future<void> _issue(List<String> args) async {
  final dir = _arg(args, 'dir') ?? _defaultSecretDir;
  final file = _secretFile(dir);
  if (!file.existsSync()) {
    stderr.writeln('找不到私钥：${file.path}，先跑 keygen');
    exit(1);
  }

  final plan = _arg(args, 'plan') ?? 'buyout';
  final days = int.tryParse(_arg(args, 'days') ?? '') ?? 0;
  final count = int.tryParse(_arg(args, 'count') ?? '') ?? 1;
  final note = _arg(args, 'note') ?? '';
  final bind = _arg(args, 'bind') ?? '';

  final secret = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final privateBytes = _fromHex(secret['privateKeyHex'] as String);
  final algorithm = Ed25519();
  // cryptography 2.9 的 Ed25519 签名要的是 KeyPair（不是 SecretKey），
  // 用种子还原一个出来正好。
  final keyPair = await algorithm.newKeyPairFromSeed(privateBytes);

  final codes = <String>[];
  for (var i = 0; i < count; i++) {
    final now = DateTime.now();
    final payload = <String, dynamic>{
      'v': 1,
      'plan': plan,
      'exp': plan == 'buyout' ? 0 : now.add(Duration(days: days)).millisecondsSinceEpoch,
      'iat': now.millisecondsSinceEpoch,
      'note': note.isEmpty ? '第 ${i + 1} 张' : note,
      'bind': bind,
    };
    final payloadBytes = utf8.encode(jsonEncode(payload));
    final signature = await algorithm.sign(payloadBytes, keyPair: keyPair);
    final code = 'WR1.${_b64Url(payloadBytes)}.${_b64Url(signature.bytes)}';
    codes.add(code);
    stdout.writeln(code);
  }

  final out = _arg(args, 'out');
  if (out != null) {
    File(out).writeAsStringSync(codes.join('\n'));
    stdout.writeln('');
    stdout.writeln('已写入：$out');
  }
}

Future<void> _verify(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('用法：verify <授权码>');
    exit(2);
  }
  final code = args.first;
  final parts = code.split('.');
  if (parts.length != 3) {
    stdout.writeln('格式不对');
    return;
  }
  final payloadBytes = _fromB64Url(parts[1]);
  final sigBytes = _fromB64Url(parts[2]);

  final dir = _arg(args, 'dir') ?? _defaultSecretDir;
  final file = _secretFile(dir);
  if (!file.existsSync()) {
    stderr.writeln('找不到公钥文件：${file.path}');
    exit(1);
  }
  final secret = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final publicKey = SimplePublicKey(
    _fromHex(secret['publicKeyHex'] as String),
    type: KeyPairType.ed25519,
  );
  final ok = await Ed25519().verify(
    payloadBytes,
    signature: Signature(sigBytes, publicKey: publicKey),
  );
  stdout.writeln(ok ? '签名有效' : '签名无效');
  stdout.writeln(utf8.decode(payloadBytes));
}

String _readPublicKey(File file) {
  final secret = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return secret['publicKeyHex'] as String;
}

String _toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> _fromHex(String hex) {
  final out = <int>[];
  for (var i = 0; i + 1 < hex.length; i += 2) {
    out.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return out;
}

String _b64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

List<int> _fromB64Url(String input) {
  var normalized = input.replaceAll('-', '+').replaceAll('_', '/');
  while (normalized.length % 4 != 0) {
    normalized += '=';
  }
  return base64Decode(normalized);
}
