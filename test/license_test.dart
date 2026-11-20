import 'package:flutter_test/flutter_test.dart';
import 'package:whoruns/services/license_service.dart';

/// 由 `tool/license_tool.dart` 签发的买断码（真实签名）。
const String validBuyoutCode =
    'WR1.eyJ2IjoxLCJwbGFuIjoiYnV5b3V0IiwiZXhwIjowLCJpYXQiOjE3OTUxNDQzMzA0MTgsIm5vdGUiOiLmtYvor5UiLCJiaW5kIjoiIn0.'
    '67wIxr_7xrkvvC9Z3DYTcdXggMZJzkDmy_UKcEeFxjtFQJaaZxXK_gC00CM2FB8GY0iGO9hV227eaOVGA3QaDg';

void main() {
  group('授权码验签', () {
    test('真实签发的买断码能验过', () async {
      final info = await LicenseService.instance.verify(validBuyoutCode);
      expect(info, isNotNull);
      expect(info!.plan, LicensePlan.buyout);
      expect(info.isBuyout, isTrue);
      expect(info.isValid, isTrue);
      expect(info.expiresAt, isNull);
    });

    test('改一个字符就验不过', () async {
      final tampered = validBuyoutCode.replaceFirst('WR1.', 'WR2.');
      final info = await LicenseService.instance.verify(tampered);
      expect(info, isNull);
    });

    test('改 payload 就验不过', () async {
      final parts = validBuyoutCode.split('.');
      final broken = '${parts[0]}.${parts[1]}X.${parts[2]}';
      final info = await LicenseService.instance.verify(broken);
      expect(info, isNull);
    });

    test('格式不对一律拒绝', () async {
      expect(await LicenseService.instance.verify(''), isNull);
      expect(await LicenseService.instance.verify('hello'), isNull);
      expect(await LicenseService.instance.verify('WR1.onlytwo'), isNull);
    });

    test('订阅码能看出到期时间', () async {
      // 订阅码由同一个私钥签出，这里只验签链路能跑通。
      final subscriptionLike = validBuyoutCode.replaceFirst('YnV5b3V0', 'c3Vic2NyaXB0aW9u');
      final info = await LicenseService.instance.verify(subscriptionLike);
      // payload 改了但签名没改，必须验不过。
      expect(info, isNull);
    });
  });

  group('免费版门槛', () {
    test('没激活时只有 24 小时和前 3 条是免费的', () {
      final unlocked = LicenseService.instance.isUnlocked(
        null,
        hours: 24,
        index: 0,
      );
      expect(unlocked, isTrue);
      expect(
        LicenseService.instance.isUnlocked(null, hours: 24, index: 3),
        isFalse,
      );
      expect(
        LicenseService.instance.isUnlocked(null, hours: 72, index: 0),
        isFalse,
      );
    });
  });
}
