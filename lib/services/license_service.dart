import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 套餐类型。
enum LicensePlan {
  buyout('买断', '一次买断，永久可用'),
  subscription('订阅', '按订阅期解锁');

  const LicensePlan(this.label, this.hint);

  final String label;
  final String hint;

  static LicensePlan parse(String raw) {
    for (final v in LicensePlan.values) {
      if (v.name == raw) return v;
    }
    return LicensePlan.buyout;
  }
}

/// 授权信息。
class LicenseInfo {
  const LicenseInfo({
    required this.plan,
    required this.issuedAt,
    required this.expiresAt,
    this.note = '',
    this.boundDevice = '',
  });

  final LicensePlan plan;
  final DateTime issuedAt;

  /// 买断的话是 null（永久）。
  final DateTime? expiresAt;

  final String note;

  /// 绑定的设备指纹；为空表示不绑设备。
  final String boundDevice;

  bool get isBuyout => plan == LicensePlan.buyout;

  bool get isExpired => expiresAt != null && expiresAt!.isBefore(DateTime.now());

  bool get isValid => isBuyout || !isExpired;

  int get daysLeft {
    if (isBuyout || expiresAt == null) return -1;
    return expiresAt!.difference(DateTime.now()).inDays + 1;
  }

  Map<String, dynamic> toMap() => {
        'plan': plan.name,
        'iat': issuedAt.millisecondsSinceEpoch,
        'exp': expiresAt?.millisecondsSinceEpoch,
        'note': note,
        'bind': boundDevice,
      };
}

/// 授权码服务。
///
/// 授权码是**离线可验签**的字符串，不联网、不调服务器：
/// 私钥留在你自己手上（不进仓库），App 里只放公钥。
/// 好处是：没有服务器成本，也不会因为服务挂了卖不出货。
///
/// 格式：`WR1.<payload(base64url)>.<签名(base64url)>`
/// payload 是一段 JSON：{"v":1,"plan":"buyout","exp":0,"iat":...}
class LicenseService {
  LicenseService._();

  static final LicenseService instance = LicenseService._();

  static const String _codeKey = 'license_code';
  static const String _deviceKey = 'license_device';

  /// 内置公钥（Ed25519，32 字节，hex）。
  ///
  /// 私钥在仓库外，用 `tool/license_tool.dart keygen` 生成，只有一份。
  /// 换密钥的话：重新 keygen，把新公钥贴到这里，旧授权码全部作废。
  static const String publicKeyHex =
      '6978d96b74969433625776b31a1424c30a5b311d0a3c3dcd06d165940fc4d0e4';

  static final Ed25519 _algorithm = Ed25519();

  LicenseInfo? _cached;

  /// 读当前授权。返回 null 表示还没激活。
  Future<LicenseInfo?> current({String? deviceFingerprint}) async {
    if (_cached != null) return _cached;
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_codeKey);
    if (code == null || code.isEmpty) return null;
    final info = await verify(code, deviceFingerprint: deviceFingerprint);
    _cached = info;
    return info;
  }

  /// 激活一个授权码。
  ///
  /// 返回 null 表示激活成功；返回字符串是失败原因，直接显示给用户。
  Future<String?> activate(String code, {String? deviceFingerprint}) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return '请输入授权码';

    final info = await verify(trimmed, deviceFingerprint: deviceFingerprint);
    if (info == null) return '授权码无效或已被篡改';
    if (info.isExpired) {
      final exp = info.expiresAt;
      return '订阅已于 ${exp?.toIso8601String().substring(0, 10)} 到期';
    }
    if (info.boundDevice.isNotEmpty &&
        deviceFingerprint != null &&
        deviceFingerprint.isNotEmpty &&
        info.boundDevice != deviceFingerprint) {
      return '这个授权码绑定在另一台设备上';
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_codeKey, trimmed);
    if (deviceFingerprint != null && deviceFingerprint.isNotEmpty) {
      await prefs.setString(_deviceKey, deviceFingerprint);
    }
    _cached = info;
    return null;
  }

  /// 解除授权（退款/换机场景）。
  Future<void> deactivate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_codeKey);
    await prefs.remove(_deviceKey);
    _cached = null;
  }

  /// 验签并解析。签名不对、格式不对，一律返回 null。
  Future<LicenseInfo?> verify(String code, {String? deviceFingerprint}) async {
    final parts = code.split('.');
    if (parts.length != 3) return null;
    if (parts[0] != 'WR1') return null;

    final payloadBytes = _decodeBase64Url(parts[1]);
    final sigBytes = _decodeBase64Url(parts[2]);
    if (payloadBytes == null || sigBytes == null) return null;

    final publicKeyBytes = _decodeHex(publicKeyHex);
    if (publicKeyBytes == null || publicKeyBytes.length != 32) {
      debugPrint('[LicenseService] 公钥缺失或长度不对');
      return null;
    }

    try {
      final publicKey = SimplePublicKey(
        publicKeyBytes,
        type: KeyPairType.ed25519,
      );
      final ok = await _algorithm.verify(
        payloadBytes,
        signature: Signature(sigBytes, publicKey: publicKey),
      );
      if (!ok) return null;

      final json = jsonDecode(utf8.decode(payloadBytes));
      if (json is! Map<String, dynamic>) return null;
      if (json['v'] != 1) return null;

      final expMs = (json['exp'] as num?)?.toInt() ?? 0;
      final iatMs = (json['iat'] as num?)?.toInt() ?? 0;
      return LicenseInfo(
        plan: LicensePlan.parse((json['plan'] as String?) ?? 'buyout'),
        issuedAt: DateTime.fromMillisecondsSinceEpoch(iatMs),
        expiresAt: expMs <= 0
            ? null
            : DateTime.fromMillisecondsSinceEpoch(expMs),
        note: (json['note'] as String?) ?? '',
        boundDevice: (json['bind'] as String?) ?? '',
      );
    } catch (e) {
      debugPrint('[LicenseService] 验签失败：$e');
      return null;
    }
  }

  /// 免费版能看多少条。
  static const int freeAppLimit = 3;

  /// 免费版能看多长时间范围。
  static const int freeHours = 24;

  /// 判定某个功能是否已解锁。
  bool isUnlocked(LicenseInfo? info, {required int hours, required int index}) {
    if (info == null || !info.isValid) {
      // 免费版：只看最近 24 小时、榜单前 3 条。
      return hours <= freeHours && index < freeAppLimit;
    }
    return true;
  }

  static Uint8List? _decodeBase64Url(String input) {
    try {
      var normalized = input.replaceAll('-', '+').replaceAll('_', '/');
      while (normalized.length % 4 != 0) {
        normalized += '=';
      }
      return base64Decode(normalized);
    } on FormatException {
      return null;
    }
  }

  static Uint8List? _decodeHex(String hex) {
    if (hex.length.isOdd) return null;
    try {
      final out = Uint8List(hex.length ~/ 2);
      for (var i = 0; i < out.length; i++) {
        out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      }
      return out;
    } on FormatException {
      return null;
    }
  }
}
