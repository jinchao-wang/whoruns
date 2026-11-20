# 技术架构

这个 App 的核心矛盾是：**要在普通 App 的权限范围内，判断出「哪个 App 在偷跑」**。
所以整套设计都围绕一件事——**只给能被系统事件证明的结论**。

## 分层

```
┌─────────────────────────────────────────────┐
│ UI 层（Dart）                                │
│  审计台 / 详情 / 设置 / 激活 / iOS 说明        │
├─────────────────────────────────────────────┤
│ 服务层（Dart）                               │
│  audit_service   审计编排                    │
│  usage_service   MethodChannel 唯一出入口     │
│  license_service 授权码离线验签                │
│  settings_service / export_service           │
├─────────────────────────────────────────────┤
│ 评分引擎（Dart，纯函数）                       │
│  utils/scoring.dart  偷跑指数 0-100          │
├─────────────────────────────────────────────┤
│ 原生层（Kotlin / Swift）                      │
│  UsageAudit.kt    采集：用量/流量/权限        │
│  AuditEvents.kt   事件分类器（纯 Kotlin）      │
│  MainActivity.kt  MethodChannel               │
│  AuditNotifier.kt 通知 + 告警闹钟             │
│  AppDelegate.swift iOS 本机健康自检           │
└─────────────────────────────────────────────┘
```

判断逻辑**不放进原生层**：原生只负责把系统事实原样搬上来，
「这算不算偷跑」由 Dart 侧的纯函数决定。好处有三个：

1. 评分能用 Dart 单测覆盖（29 个测试里有一半在测它）；
2. 换算法不用重新发原生代码；
3. 原生层保持「取数器」的角色，逻辑简单，出错面小。

## Android 采集链路

```
UsageStatsManager.queryEvents(begin, end)
        │  系统事件流（前台/后台活动、屏幕亮灭、解锁）
        ▼
UsageAudit.readEvents()
        │  翻译成自己的事件枚举（隐藏常量走反射）
        ▼
List<RawEvent>
        ▼
AuditClassifier.classify()      ← 纯 Kotlin，可单测
        │  产出 EvidenceRecord（类型 + 时间 + 说明）
        ▼
MethodChannel → Dart AppAudit.fromMap()
        │  证据 → 计数 → 评分
        ▼
utils/scoring.dart computeScore() → 偷跑指数 0-100
```

另外两条采集线是独立的：

- `UsageStatsManager.queryUsageStats(INTERVAL_DAILY, …)` → 前台/后台时长；
- `NetworkStatsManager.queryStatsForUid(uid, begin, end)` → 分 App 流量（部分 ROM 不给普通应用读，会降级）；
  （原来的 `queryStatsForDevice()` 从 API 29 起废弃，新版 SDK 里已经取不到，官方替代就是按 UID 查）；
- `PackageManager` → 权限声明与授予状态。

## 为什么自己定义事件枚举

`UsageEvents.Event` 里有一批常量是**隐藏 API**（`ACTIVITY_STARTED`、`USER_UNLOCKED` 等），
不同 Android 版本对它们的公开程度还不一样。直接引用会同时带来两个麻烦：

- 编译期依赖 SDK 的公开面，换个 compileSdk 可能就编不过；
- 单测跑不起来——`UsageEvents.Event` 是框架类，JVM 上没有。

所以做法是：

1. 在 `AuditEvents.kt` 里定义自己的 `AuditEventType` 枚举（纯 Kotlin，无框架依赖）；
2. 在 `UsageAudit.kt` 里用**反射**读框架常量的真实值，运行时组装一张映射表；
3. 反射拿不到就少一路信号（该类事件直接忽略），**不会让 App 崩，也不会编译失败**。

这样事件分类器就是一段纯函数，可以直接跑 JVM 单测：

```bash
cd android && ./gradlew :app:testDebugUnitTest -I ci-junit.gradle
```

`AuditClassifierTest` 里钉死了每一条判定规则（8 个用例），包括「用户正常切换 App 不产生任何证据」这条**反误报**用例。

## 证据等级：怎么控制误报

误报比漏报更致命——用户被冤枉一次就可能卸载。

| 证据 | 等级 | 为什么这么判 |
|---|---|---|
| 息屏启动 | 硬证据 | 屏幕是黑的，用户不可能刚点过它。这条不依赖任何「用户是不是在操作」的推测。 |
| 抢占焦点 | 硬证据 | 上一个 App 还没收到 `PAUSED`/`STOPPED`，新 App 就叠上来了。正常切换一定会先让出焦点。 |
| 分 App 流量 | 硬证据 | 系统统计的数字，不是推断。 |
| 闲置自启 | 线索 | 10 分钟没有操作痕迹却自己弹前台。但用户完全可能是解锁后放着手机、过了会儿才点的——**不能当定论**。 |
| 后台驻留 | 线索 | 后台待着本身很正常，只有待很久 + 别的信号才值得看。 |
| 定位权限 | 线索 | 只说明「有资格定位」，**不等于它定位过**。Android 没有公开 API 能读别的 App 的定位记录，文案必须写死这一点。 |

判定依据只认系统事件，不做启发式猜测。三条硬证据的共性是：**不需要假设用户做了什么**。

## 评分为什么用绝对分

偷跑指数满分 100，各维度满分之和是 140，最后封顶 100：

| 维度 | 满分 | 算满的阈值 |
|---|---|---|
| 息屏启动 | 45 | 3 次 |
| 抢焦点 | 35 | 3 次 |
| 闲置自启（线索） | 20 | 8 次 |
| 后台驻留 | 12 | 8 小时 |
| 流量 | 18 | 300 MB |
| 定位嫌疑 | 10 | 有后台定位 + 有自启动行为才拿满，否则只给 60% |

分档：高危 ≥60 / 可疑 ≥35 / 留意 ≥18 / 正常。

**为什么不归一化到百分比**：归一化会把「只有一个信号有数据」的情况放大成满分。
比如流量读不到（部分 ROM 的常态）时，剩下三个维度平摊到 100 分，
一个普通 App 也能拿 60 分——用户打开一看满屏高危，直接不信了。

绝对分的好处是**缺数据就是缺数据**：
读不到的维度整条不计分，总分自然低，榜单里该靠后的 App 就在后面。

## iOS：为什么不做同一套

iOS 不允许第三方 App 读取其它 App 的使用情况。这是系统级的隐私设计，
**没有公开 API，也没有合规的绕过方式**。

与其给一个半真半假的答案，iOS 版只做三件真能做的事：

1. **本机健康自检**：电量、充电状态、存储余量、温度状态（`UIDevice` / `ProcessInfo` / `FileManager`）；
2. **系统路径指引**：屏幕使用时间、定位服务、后台 App 刷新分别在哪、怎么改；
3. **隐私自查清单**：勾选自己担心的类别，生成一份能照着做的清单并复制出去。

`UsageService.isSupported` 在 iOS 上返回 `false`，
Android 的整条采集链路在 iOS 上根本不会被触发。
App 里的文案也如实告诉用户「iOS 上我们看不到别的 App」，不假装。

将来如果拿到 Apple 的 Screen Time API 权限（`FamilyControls` / `DeviceActivity`），
可以在 `UsageService` 里补一个 iOS 实现，Dart 侧的模型和评分不用动。

## 数据流与存储

```
系统事件 ──▶ 原生层 ──▶ MethodChannel ──▶ Dart 内存 ──▶ 界面
                                              │
                                              ├─▶ 授权码（SharedPreferences）
                                              ├─▶ 设置（SharedPreferences）
                                              └─▶ CSV（用户主动导出 → App 私有目录）
```

**没有网络权限**，没有统计 SDK，没有任何上传路径。
唯一的「出口」是用户主动点导出，文件写在自己手机的应用私有目录里。

授权码验证也在本机完成：Ed25519 签名 + 内置公钥，不联机查服务器。

## 测试策略

| 位置 | 数量 | 测什么 |
|---|---|---|
| `test/scoring_test.dart` | 10 | 评分边界：什么证据给多少分、什么情况必须给 0 分、缺数据不能虚高、总分不越界、分档边界值 |
| `test/models_test.dart` | 6 | 原生数据解析、证据等级解析、计数从证据推导、CSV 转义 |
| `test/license_test.dart` | 6 | 真签发码能验过、改一个字符就废、格式不对拒绝、免费版门槛 |
| `test/widget_test.dart` | 4 | App 能起来、权限引导、已授权直接审计、设置页内容 |
| `android/.../AuditClassifierTest.kt` | 8 | 事件分类规则，含两条**反误报**用例（正常切 App 不算、刚解锁不久不算闲置自启） |

Dart 侧 29 个（`flutter test`），Kotlin 侧 8 个（`./gradlew :app:testDebugUnitTest`）。
三个 CI 工作流都会跑这两套。

Widget 测试里给平台通道装了 mock：真机上原生一定会回，单测里没人回，
不装 mock 的话调用会一直挂着（这个坑踩过一次——顺便给通道调用加了 30 秒超时，
免得某些 ROM 上采集卡死时界面永远转圈）。

## 工程约定

**平台脚手架不入库。** 仓库只跟踪：

- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/**` 和 `android/app/src/test/kotlin/**`
- `ios/Runner/AppDelegate.swift`、`ios/Runner/Info.plist`
- `lib/**`、`test/**`、`tool/**`、`.github/workflows/**`

Gradle 工程、Xcode 工程、图标资源都由 CI 里的 `flutter create` 现场生成，
生成完再把自有源码覆盖回去。

好处：仓库里没有一堆和 Flutter 版本绑死的构建脚本；
代价：本地第一次拉下来要先 `flutter create .` 补一次脚手架。

Flutter 版本在 CI 里锁死 `3.47.8`——脚手架是按这个版本生成的，
换版本不锁死，Gradle/AGP 配置就可能对不上。

## 已知边界

- **流量读不到**：部分 ROM 不给普通应用分 App 流量。App 会显示「读不到」而不是显示 0。
- **`ACTIVITY_STARTED` 拿不到**：老版本 Android 上这个隐藏常量取不到，
  息屏启动那一路信号会缺失（其余信号正常）。
- **iOS 无后台审计**：见上文。
- **耗电排行没做**：`BatteryStats` 普通应用读不到，要上得靠系统权限或 ADB。
- **告警不是实时的**：用不精确闹钟（15 分钟起），Android 12+ 不需要精确闹钟权限，
  代价是系统可能推迟触发。
