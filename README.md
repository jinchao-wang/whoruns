# 谁在偷跑

> 后台自启、偷偷定位、狂刷流量 —— 到底是谁在干？看完就知道。

Android 上直接读系统事件，告诉你**哪个 App 在你没碰手机的时候自己动了起来**，
并且把每一条判断摊开给你看：**证据是什么、等级有多硬、扣了几分。**

iOS 上苹果不让读别的 App 的用量，所以 iOS 版不假装能做到，
改成做本机健康自检 + 告诉你系统自带的那条路怎么走 + 给一份能照着做的自查清单。

| | Android | iOS |
|---|---|---|
| 谁在后台自启 | ✅ 读系统事件，直接点名 | ❌ 系统不允许 |
| 谁抢过焦点 | ✅ 硬证据 | ❌ |
| 息屏时谁还启动 | ✅ 硬证据 | ❌ |
| 分 App 流量 | ✅（部分 ROM 读不到会明说） | ❌ |
| 后台定位权限风险 | ✅（只查权限，不读坐标） | ❌ |
| 本机健康自检 | ✅ | ✅ |
| 系统路径指引 + 自查清单 | ✅ | ✅ |

---

## 为什么要做这个

「手机变卡了」「流量跑得比电还快」「定位一直开着」——用户心里清楚有问题，
但说不清是哪个 App，也管不住。

市面上的工具大多只给一个「电池健康度 78 分」，
用户看完也不知道该卸哪个、该关哪个权限。

这个 App 的做法不一样：**只给有证据的结论**。

- 每条发现都能指回一个系统事件（什么时间、发生了什么）；
- 分「硬证据」和「线索」：硬证据是系统事件直接证明的，线索只作参考；
- 没有证据就不给分，读不到的数据整条维度不计分（不做归一化，避免普通 App 虚高）。

## 证据是怎么判的

| 证据 | 等级 | 判定依据 |
|---|---|---|
| 息屏启动 | 硬证据 | 屏幕黑着的时候它还在启动后台任务 —— 用户不可能刚点过它 |
| 抢占焦点 | 硬证据 | 上一个 App 还没退到后台，它就压上来了 |
| 分 App 流量 | 硬证据 | 系统统计的流量数字 |
| 后台定位权限 | 线索 | 只说明「有资格定位」，**不等于它定位过** |
| 闲置自启 | 线索 | 10 分钟没有操作痕迹却自己弹到前台（也可能是你点的） |
| 后台驻留 | 线索 | 后台待了多久 |

偷跑指数满分 100，分档：高危 ≥60 / 可疑 ≥35 / 留意 ≥18 / 正常。

评分细节见 [docs/architecture.md](docs/architecture.md)。

## 隐私

- **没有网络权限**，一行代码都不往外发。
- 没有第三方统计、广告、崩溃上报 SDK。
- 采集的只有：各 App 的前台/后台时长、活动事件、屏幕亮灭、分 App 流量、权限授予状态。
- 不采集任何个人内容（短信、聊天、相册、剪贴板），不采集账号，不采集位置坐标。
- 导出的 CSV 只写到你手机自己的目录里。

完整说明见 [docs/privacy-policy.md](docs/privacy-policy.md)。

## 安装

源码在 GitHub，装机包走 Releases（打 tag 自动构建）：

- **Android**：下载 `谁在偷跑-vX.Y.Z.apk`，允许「安装未知来源应用」后安装。
  安装后需要去系统里开一次「使用情况访问权限」（下面有路径）。
- **iOS**：CI 产出的是**未签名** IPA，需要自己用 Xcode 或爱思一类工具签名后安装。
  仓库里没放证书，这是刻意的。

## 第一次用

1. 打开 App，点「去系统设置里开启」；
2. 系统设置 → 应用 → 特殊应用权限 → 使用情况访问权限 → 找到「谁在偷跑」→ 打开；
3. 回到 App，点「开始审计」；
4. 看偷跑榜，点进可疑的 App，看证据链和处理建议。

> 不给权限也能用：App 会一直显示授权引导，不会偷偷采集任何东西。

## 授权（买断 / 订阅）

| 方案 | 价格 | 说明 |
|---|---|---|
| 免费版 | ¥0 | 只看最近 24 小时、榜单前 3 条，不能导出 |
| 买断 | ¥18 | 永久解锁全部历史、完整证据链、CSV 导出、告警 |
| 订阅 | ¥6/月、¥48/年 | 功能同买断，按期解锁 |

授权码是 `WR1.` 开头的字符串，**在本机离线验签**：不联网、不注册账号、没有服务器成本。
签发和发货流程见 [docs/monetization.md](docs/monetization.md)。

## 开发

```bash
# Flutter 3.47.8（Dart 3.13），版本要和 CI 一致
flutter pub get
flutter analyze
flutter test

# 原生侧判定逻辑的 JVM 单测
cd android && ./gradlew :app:testDebugUnitTest -I ci-junit.gradle

# 两个自查脚本（不需要 Android SDK，CI 出问题时先跑它们）
python tool/check_workflows.py     # 校验 .github/workflows 的 YAML 语法
python tool/classifier_probe.py    # 用 Python 复刻一遍分类器，跑一遍边界用例
```

> `tool/check_workflows.py` 值得说一句：GitHub 对工作流 YAML 语法错的处理很隐蔽，
> 不报错，只把工作流名字显示成文件路径，job 也不创建 —— 看起来像「没触发」。
> 两个工作流里都加了 YAML 语法自检步骤，就是为了第一时间暴露这种问题。

### 仓库结构

```
lib/
  models/audit.dart        审计模型：证据、证据等级、评分结果
  utils/scoring.dart       评分引擎（纯函数，有单测）
  services/
    usage_service.dart     MethodChannel 封装（唯一的原生出入口）
    audit_service.dart     审计编排
    license_service.dart   授权码离线验签
    settings_service.dart  本地设置
    export_service.dart    CSV 导出
  screens/                 审计台 / 详情 / 设置 / 激活 / iOS 说明
  theme/                   主题与风险配色
android/app/src/
  main/kotlin/com/wjc/whoruns/
    AuditEvents.kt         事件分类器（纯 Kotlin，可单测）
    UsageAudit.kt          用量、流量、权限采集
    MainActivity.kt        MethodChannel
    AuditNotifier.kt       通知与告警闹钟
  test/kotlin/...          分类器单测
ios/Runner/AppDelegate.swift  iOS 侧：本机健康自检通道
tool/license_tool.dart     授权码签发工具（离线）
docs/                      隐私政策、上架材料、变现手册、架构说明
```

### 为什么平台脚手架不入库

仓库只跟踪 `android/app/src` 下我们自己写的部分和 `ios/Runner` 里改过的两个文件，
Gradle 工程、Xcode 工程、图标资源都不入库 —— CI 里用 `flutter create` 重新生成，
再把我们自己的源码覆盖回去。

好处是仓库里没有一堆和 Flutter 版本绑定的构建脚本，改 Flutter 版本时不会冲突；
代价是本地首次拉下来要先跑一次 `flutter create .` 补齐脚手架。

### CI

| 工作流 | 触发 | 产物 |
|---|---|---|
| `build-android.yml` | 推 `android/`、`lib/`、`test/` 等 | Android release APK |
| `build-ios.yml` | 推 `ios/`、`lib/`、`test/` 等 | iOS 未签名 IPA |
| `release.yml` | 打 `v*` tag | GitHub Release（含 APK） |

三个工作流都会跑：`flutter analyze` → `flutter test` → Kotlin 原生单测 → 构建。

## 上架说明

Google Play 对 `PACKAGE_USAGE_STATS` 和 `QUERY_ALL_PACKAGES` 审核很严，
所以这个项目**默认不走商店**，直接用 GitHub 分发。

但材料都准备好了，真要上也有路：
[docs/play-store-review.md](docs/play-store-review.md) 里有逐项权限声明的填法、
Data safety 表单怎么填、给审核员的备注模板（中英文）。

## 路线图

- [x] Android 证据审计（息屏启动 / 抢焦点 / 闲置自启 / 流量 / 定位权限）
- [x] iOS 本机健康自检 + 系统路径指引 + 自查清单
- [x] 授权码离线验签、买断 / 订阅门禁
- [x] 定期告警（不精确闹钟 + 本地通知）
- [x] CSV 导出
- [ ] 应用耗电排行（需要 `BatteryStats`，普通应用拿不到，得走 ADB 或者系统权限）
- [ ] 桌面小组件（一眼看到今天的偷跑指数）
- [ ] iOS 屏幕使用时间接入（需要向 Apple 申请 Screen Time API 权限）

## 许可

源码开放阅读。装机包按买断 / 订阅授权使用，与源码授权是两回事。
