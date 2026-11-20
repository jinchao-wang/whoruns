import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoruns/main.dart';

/// 把首页那一串异步初始化（读设置、查权限）跑完。
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// 装一个假的原生通道。
///
/// 真机上原生那边一定会回；单测里没人回，调用会一直挂着，
/// 所以这里自己把常见方法的返回值堵上。
void mockChannel({required bool hasUsageAccess}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('com.wjc.whoruns/audit'),
    (call) async {
      switch (call.method) {
        case 'hasUsageAccess':
          return hasUsageAccess;
        case 'deviceFingerprint':
          return 'test-fingerprint';
        case 'deviceHealth':
          return <String, dynamic>{};
        case 'collectAudit':
          return <String, dynamic>{
            'scannedAt': 1700000000000,
            'rangeStart': 1699913600000,
            'rangeEnd': 1700000000000,
            'trafficAvailable': false,
            'apps': <Map<String, dynamic>>[],
          };
        default:
          return null;
      }
    },
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    mockChannel(hasUsageAccess: false);
  });

  testWidgets('App 能起来，首页能看到「谁在偷跑」', (tester) async {
    await tester.pumpWidget(const WhorunsApp());
    await settle(tester);

    expect(find.text('谁在偷跑'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('没给权限时能看到授权引导', (tester) async {
    await tester.pumpWidget(const WhorunsApp());
    await settle(tester);

    // 平台通道在单测里返回「没授权」。
    expect(find.text('需要「使用情况访问权限」'), findsOneWidget);
    expect(find.text('去系统设置里开启'), findsOneWidget);
  });

  testWidgets('给了权限就会直接跑审计', (tester) async {
    mockChannel(hasUsageAccess: true);

    await tester.pumpWidget(const WhorunsApp());
    await settle(tester);

    // 有权限时不再显示授权卡，而是显示审计按钮。
    expect(find.text('需要「使用情况访问权限」'), findsNothing);
    expect(find.text('开始审计'), findsOneWidget);
  });

  testWidgets('设置页能看到套餐和隐私说明', (tester) async {
    await tester.pumpWidget(const WhorunsApp());
    await settle(tester);

    await tester.tap(find.text('设置'));
    await settle(tester);

    expect(find.text('套餐'), findsOneWidget);

    // 隐私说明在页面最下面，列表是懒加载的，要滚过去才建出来。
    await tester.scrollUntilVisible(
      find.text('隐私政策'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('隐私政策'), findsOneWidget);
  });
}
