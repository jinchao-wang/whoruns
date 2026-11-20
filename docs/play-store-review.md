# Google Play 上架材料包

这份文档是给「谁在偷跑」准备的上架材料：权限声明问卷的答法、Data safety 表单的填法、审核备注模板，以及隐私政策怎么托管。

**写给谁看**：以后决定上 Google Play、或者要回答平台审核问询的人。

> **政策以官方最新版本为准。**
> 本文提到的「Google Play 的设备与网络滥用政策」是这类要求的通称，Play 的政策条款号和问卷措辞会随时间调整、也可能因地区和开发者账号类型而不同。
> **真正提交时，请以 Play Console 里当时实际显示的问题和官方帮助文档为准**，本文提供的是「怎么答才和 App 行为对得上」的思路和可直接抄的中英文措辞。

---

## 一、先把现实说清楚：为什么不先上 Google Play

这是一个真实的取舍，不是「我们过不了审」，而是**先绕开商店审核、直接分发更划算**。

**支持先走 GitHub 分发的理由：**

1. **审核周期长、成本高。** `PACKAGE_USAGE_STATS` 和 `QUERY_ALL_PACKAGES` 属于审核最严的一类权限，需要提交详细的正当理由、可能被要求提供录屏和额外说明，还可能被反复要求补充材料。个人开发者项目没有稳定的商业化预期，排队审核的性价比很低。
2. **更新会被卡住。** 一旦上了 Play，之后每次改权限描述都要走一遍审核。对一个还在快速迭代的审计工具，这是持续的摩擦。
3. **收入本来就走授权码。** 本 App 不联网、不收会员、不做广告，收入来自卖授权码。这件事跟商店审核没有半点关系 —— 上架拿不到一分钱流量，还会多一层审核不确定性。
4. **我们保留了上架的可能。** 所以合规材料该写还是要写（就是这份文档），隐私政策独立成页、可公开访问。将来想上随时能上。

**代价也要认：**

- GitHub 分发意味着用户要自己下载 APK、自己允许「安装未知来源应用」，信任成本和流失率都明显高于应用商店。
- APK 直接分发没有自动更新，要靠 Release 通知用户自己下载。
- 面向不熟悉 APK 安装的用户时，可发现性几乎为零。

**结论：** 先走 GitHub Release + 授权码变现，把商店上架材料备好但暂不提交。本文接下来的内容，就是「备好」的那部分。

---

## 二、权限声明问卷：建议答案

Play Console 的问卷措辞会变，下面按**问题类型**给出建议答案和理由。

### ⚠️ 第一原则

> **答案必须和 App 的实际行为完全一致。**
> Play 会审查 APK 本身。如果问卷里写「不用于分析」，但代码里把数据传给了第三方 SDK，账号会被直接处理。
> 本 App 目前的实际情况是：**没有 `INTERNET` 权限、没有任何第三方 SDK、不传输任何数据**。下面所有答案都建立在这个前提上。将来一旦加了联网或第三方 SDK，**这些答案必须全部重新填**。

---

### 2.1 `PACKAGE_USAGE_STATS`（使用情况访问权限）

**问题类型 A：**「你使用这个权限是为了分析、广告，还是与第三方共享数据？」

> **建议答案：No（否）**
>
> **中文版：**
> 否。本权限仅用于在本机展示各应用的前台/后台使用时长、活动事件时间和分应用流量消耗（移动 + Wi-Fi 合计）。所有读取到的数据只保存在设备内存中，用于在本应用界面内生成审计结果与评分。本应用没有网络传输权限（未声明 `android.permission.INTERNET`），不含任何第三方统计或广告 SDK，不会将任何数据传输到设备之外。
>
> **English version:**
> No. This permission is used only to display, on-device, each app's foreground/background usage time, activity event timestamps, and per-app data usage (mobile + Wi-Fi combined). All data read stays in device memory and is used solely to render the audit results and scores inside this app. This app does not declare the `android.permission.INTERNET` permission and contains no third-party analytics or advertising SDK. No data is transmitted off the device.

**问题类型 B：**「这个权限的使用是否受用户控制？」
本权限是 Android 的特殊权限，系统不允许应用自行弹框授权，必须由用户在系统设置中手动开启。答案是**是，完全受用户控制**。

**问题类型 C：**「这个权限是否用于广告定位或广告相关的用户画像？」

> **建议答案：No（否）**
>
> **中文版：**
> 否。本应用不展示任何广告，不包含任何广告 SDK，也不构建用户画像。本应用不请求任何定位权限，也不接收任何位置信息。
>
> **English version:**
> No. This app displays no ads, contains no advertising SDK, and builds no user profiles. It does not request any location permission and does not receive any location information.

---

### 2.2 `QUERY_ALL_PACKAGES`（查询所有安装的包）

**问题类型：**「请说明使用 `QUERY_ALL_PACKAGES` 的正当理由。」

> **建议答案：**
>
> **中文版：**
> 本应用的核心功能是列出设备上所有应用的用量与后台活动情况，并按「偷跑指数」排序。Android 11（API 30）起，包可见性默认被限制，未声明此权限时 `PackageManager` 只能枚举出极少数包，结果是审计榜单严重缺失、无法反映真实情况。
>
> 具体使用方式：
> 1. 通过 `PackageManager.getInstalledApplications()` 枚举已安装应用，以便对每一个应用单独查询其使用情况统计；
> 2. 通过 `PackageManager.getPackageInfo(package, GET_PERMISSIONS)` 读取各应用声明的权限列表（尤其是 `ACCESS_BACKGROUND_LOCATION`），并通过 `PackageManager.checkPermission()` 确认其授予状态。
>
> 本应用不会基于包列表做广告投放或用户画像；枚举结果仅用于在本机对各应用统计用量并排序展示。
>
> **English version:**
> The core purpose of this app is to enumerate every installed app's usage and background activity and rank them by a "background activity score." Since Android 11 (API 30), package visibility is restricted by default; without this permission `PackageManager` exposes only a small subset of packages, which would make the audit list severely incomplete and unrepresentative of reality.
>
> Concretely, this app uses the permission to:
> 1. Enumerate installed applications via `PackageManager.getInstalledApplications()` so that usage statistics can be queried per package;
> 2. Read each app's declared permissions via `PackageManager.getPackageInfo(package, GET_PERMISSIONS)` — in particular `ACCESS_BACKGROUND_LOCATION` — and confirm the grant state via `PackageManager.checkPermission()`.
>
> The app does not use the package list for advertising or user profiling. Enumeration is used solely to aggregate per-app usage locally and to sort and display the results on-device.

**问题类型：**「有没有考虑用更窄的可见性（`<queries>`）替代？」

> **建议答案：**
> 考虑过，但不适用。本应用的核心功能按定义就是「覆盖设备上的全部应用」——它的价值恰恰在于能发现用户自己没料到的那个 App。要真正达成这个目标就必须看到全部包，因此 `<queries>` 的按需声明方式无法满足需求。

---

### 2.3 `READ_NETWORK_STATE`（读取网络状态）

> **建议答案（用途说明）：**
>
> **中文版：**
> 用于通过 `NetworkStatsManager.queryStatsForUid(uid, begin, end)` 读取各应用的流量消耗量（移动 + Wi-Fi 合计），以便在审计结果中显示「该应用消耗了多少流量」。本应用不发起任何网络请求，不读取网络连接之外的内容。
>
> **English version:**
> Used with `NetworkStatsManager.queryStatsForUid(uid, begin, end)` to read per-app data consumption (mobile + Wi-Fi combined), so the audit report can show how much data each app used. The app makes no network requests and reads nothing beyond network usage counters.

---

### 2.4 `POST_NOTIFICATIONS`（发送通知）

> **建议答案：**
>
> **中文版：**
> 用于在定时审计发现新的「息屏启动」或「抢占焦点」事件时，向用户发送本地通知提醒。通知内容不包含任何第三方数据，全部由本机系统事件生成。Android 13 及以上版本由系统弹框征求用户同意。
>
> **English version:**
> Used to send a local notification when a scheduled audit detects a new screen-off launch or focus-steal event. Notification content is generated entirely from on-device system events and contains no third-party data. On Android 13+, the system prompts the user for consent.

---

### 2.5 `RECEIVE_BOOT_COMPLETED`（开机完成）

> **建议答案：**
>
> **中文版：**
> 用于在设备重启后重新注册本应用的定时审计闹钟，否则重启会中断告警计划。本应用不读取任何开机时的用户数据，也不执行任何开机自启行为（没有 `RECEIVE_BOOT_COMPLETED` 之外的后台拉活逻辑）。
>
> **English version:**
> Used to re-register the app's scheduled audit alarm after a device reboot, so the alerting schedule is not interrupted. The app reads no user data at boot and performs no other auto-start behavior.

---

### 2.6 权限用途声明草稿（贴到 Play Console 的「权限」说明栏）

> **中文版：**
>
> **使用情况访问权限（`PACKAGE_USAGE_STATS`）**
> 读取各应用的前台/后台使用时长、活动事件（何时被启动到前台、是否抢占焦点、是否在息屏状态下启动）以及屏幕亮灭事件。用于识别「在用户未操作手机时自行启动」的异常行为。属 Android 特殊权限，需用户在系统设置中手动开启。数据仅在本机处理，不上传。
>
> **查询所有安装的包（`QUERY_ALL_PACKAGES`）**
> 枚举设备上全部已安装应用，以便逐一统计其用量并排序展示；同时读取各应用声明的权限与授予状态（特别是后台定位权限）。不用于广告或用户画像。
>
> **读取网络状态（`READ_NETWORK_STATE`）**
> 读取分应用的流量消耗量（移动 + Wi-Fi 合计），用于显示「流量偷跑」。不发起任何网络请求。
>
> **发送通知（`POST_NOTIFICATIONS`）**
> 在定时审计发现异常事件时发送本地通知提醒。
>
> **开机完成（`RECEIVE_BOOT_COMPLETED`）**
> 设备重启后重新注册定时审计闹钟。

---

## 三、Data safety 表单怎么填

Play 的 Data safety 表单问的是「你的应用**收集**哪些数据」。按 Play 的口径，**「收集」指数据被传出设备**。本应用没有 `INTERNET` 权限、没有任何数据传输，因此所有类别都应该填「不收集」。

### 3.1 逐项填写

| 表单条目 | 怎么选 | 说明 |
|---|---|---|
| 位置信息 Location | **不收集** | 不请求定位权限，不接收坐标。仅读取其它 App 的后台定位**权限授予状态** |
| 个人信息 Personal info | **不收集** | 无姓名、邮箱、ID、地址等 |
| 财务信息 Financial info | **不收集** | 无支付信息采集。授权码与支付完全解耦 |
| 健康与健身 Health and fitness | **不收集** | 无 |
| 消息 Messages | **不收集** | 不读取短信、聊天记录、通知 |
| 照片和视频 Photos and videos | **不收集** | 不访问相册 |
| 音频文件 Audio files | **不收集** | 不访问麦克风 |
| 文件和文档 Files and docs | **不收集** | 不读取其它 App 的文件 |
| 日历 Calendar | **不收集** | 无 |
| 联系人 Contacts | **不收集** | 不读取通讯录 |
| 应用活动 App activity | **不收集** | ⚠️ 见下方说明 |
| 网页浏览 Web browsing | **不收集** | 无 |
| 应用信息与性能 App info and performance | **不收集** | ⚠️ 见下方说明 |
| 设备或其他 ID Device or other IDs | **不收集** | 设备指纹仅在本机计算与比对，不传出 |

### 3.2 三个容易被填错的地方

**「应用活动 App activity」这一项 —— 为什么不填「收集」。**
本应用确实**读取**了其它应用的用量统计和活动事件。但这些数据**从未离开设备**：没有 `INTERNET` 权限，没有上传逻辑，没有第三方 SDK。按 Play 对「收集」的定义（数据被传出设备），它不构成「收集」。填「收集」会让审核问出一堆关于数据去向的问题，而实际上没有数据去向可答。

**「应用信息与性能」这一项 —— 同理。**
本应用读取各应用的包名、图标、权限声明。这些信息全部来自本机 `PackageManager`，不传出。

**如果将来加了联网功能，上表必须全部重填。**
本表所有「不收集」的答案，都建立在「没有 `INTERNET` 权限」这一条上。只要有一天加了网络请求（比如加个在线更新检查），这几个答案立刻变成不实。

### 3.3 表单末尾的几个通用问题

| 问题 | 建议答案 |
|---|---|
| 你的应用是否加密传输收集的数据？ | **不适用 / No** —— 不传输任何数据。**（如果以后加了联网，这题要改成「是」）** |
| 用户能否请求删除收集的数据？ | **不适用** —— 不收集数据。用户卸载 App 即删除全部本地数据 |
| 你的应用是否与第三方共享收集的数据？ | **否** |

### 3.4 商店 listing 里的其它必填项

| 项目 | 怎么填 |
|---|---|
| 隐私政策 URL | 见第五节 |
| 「数据安全」区域 | 与上面这张表保持一致 |
| 内容分级问卷 | 按实际情况如实填写。若提交分类问卷，选「不含以下内容」 |
| 目标受众 | 选择「13 岁及以上」为默认基线；若定位含儿童需另行评估（本 App 不面向儿童） |
| 政府应用 | 否 |
| 金融功能 | 否 |
| 健康功能 | 否 |

---

## 四、给审核员的应用说明（审核备注）

Play Console 里有一个「App 访问 / 审核备注」之类的字段，用来给审核员说明。这里有一份可以直接抄的模板。

> **提醒：** 请根据提交时的实际版本核对一遍操作路径。不同 ROM 的系统设置文案略有差异，如果审核员用的是 Pixel 原生系统，路径一般就是下面写的这个。

### 4.1 中文模板

```
【应用用途】
「谁在偷跑」是一款本地运行的手机后台行为审计工具。它读取 Android 系统记录的用量事件，
判断哪些 App 在用户未操作手机时自行启动，并按「偷跑指数」排序展示，帮助用户关闭不需要的后台活动。

【为什么需要「使用情况访问权限」】
本应用的核心功能完全依赖 Android 的系统用量事件流（UsageStatsManager）：
  - 各 App 的前台/后台时长
  - 活动事件时间（何时被启动到前台、是否抢占焦点、是否在息屏状态下启动）
  - 屏幕亮灭事件
  - 分 App 的流量消耗（NetworkStatsManager，按 UID 查询）
这些信息没有其他公开 API 可以获取。若没有该权限，应用将无法提供任何核心功能。

【用户操作路径】
应用内首页会显示一张「需要使用情况访问权限」的引导卡，点击「去系统设置里开启」按钮
会直接跳转到系统的使用情况访问权限设置页。

系统路径：
  设置 → 应用 → 特殊应用权限 → 使用情况访问权限 → 找到「谁在偷跑」→ 打开开关

系统不允许应用代替用户开启该权限，这是 Android 的设计，授权完全由用户手动完成。

【未授权时的降级行为】
用户未授权时：
  - 应用首页显示一张授权引导卡，明确告知需要开启哪个权限；
  - 不执行任何数据采集，不调用 UsageStatsManager.queryEvents / queryUsageStats，
    也不调用 NetworkStatsManager；
  - 不显示任何审计结果、榜单或评分；
  - 应用其余部分（授权码激活、设置、隐私说明）仍可正常使用。
没有任何后台采集行为，也不需要网络连接。

【数据处理】
  - 应用未声明 android.permission.INTERNET 权限，在系统层面即不具备联网能力；
  - 不含任何第三方统计、广告、崩溃上报 SDK；
  - 所有采集到的数据仅存在于设备内存中，用于本机渲染审计结果；
  - 审计结果可通过用户主动点击「导出」按钮写为 CSV 文件保存在本机，除此之外无任何数据落盘或外传。

【权限说明】
  - PACKAGE_USAGE_STATS：读取用量事件与时长，用于生成审计结果（核心功能）
  - QUERY_ALL_PACKAGES：枚举全部已安装应用并读取其权限声明与授予状态，
    Android 11 起若不使用则只能看到极少数应用，审计结果会严重不完整
  - READ_NETWORK_STATE：读取分 App 的流量消耗
  - POST_NOTIFICATIONS：发现新的异常事件时发送本地通知提醒
  - RECEIVE_BOOT_COMPLETED：开机后重新注册定时审计闹钟

【建议随审核材料附上录屏】
见下方录屏脚本（建议 2–3 分钟，无剪辑，展示真机完整操作）。
```

### 4.2 English version

```
【What this app does】
"Who Is Running Behind" is a fully on-device Android background-activity audit tool.
It reads the Android usage-events stream, determines which apps start themselves while
the user is not touching the phone, and ranks them by a "background activity score"
so the user can disable background activity they do not need.

【Why the Usage Access permission is required】
The core feature depends entirely on the system usage-events stream exposed by
UsageStatsManager:
  - per-app foreground / background time
  - activity event timestamps (launched to foreground, stole focus, started while the screen was off)
  - screen on/off events
  - per-app mobile data usage (NetworkStatsManager)
There is no other public API that exposes this information. Without the permission the
app cannot provide its core functionality.

【User flow】
On first launch, the home screen shows a card titled "Usage Access permission required"
with a button "Enable in system settings". Tapping it opens the system Usage Access
settings page directly.

System path:
  Settings → Apps → Special app access → Usage access → find "Who Is Running Behind" → toggle ON

Android does not allow an app to grant this permission on the user's behalf; the user
must enable it manually by design.

【Degraded behaviour without the permission】
When the permission is not granted:
  - the home screen shows only the permission-guidance card;
  - the app performs NO data collection: it does not call UsageStatsManager.queryEvents /
    queryUsageStats, and does not call NetworkStatsManager;
  - no audit results, rankings or scores are shown;
  - the rest of the app (license activation, settings, privacy notice) remains usable.
There is no background collection of any kind, and no network access is required.

【Data handling】
  - The app does NOT declare the android.permission.INTERNET permission, so it cannot
    reach the network at the OS level.
  - It contains no third-party analytics, advertising or crash-reporting SDK.
  - All collected data stays in device memory and is used only to render results on-device.
  - The user may explicitly export a CSV report to local storage; there is no other
    persistence or transmission of collected data.

【Permission summary】
  - PACKAGE_USAGE_STATS: read usage events and durations to produce the audit (core feature)
  - QUERY_ALL_PACKAGES: enumerate all installed apps and read their permission declarations
    and grant states; without it (Android 11+) only a small subset of apps is visible and
    the audit would be severely incomplete
  - READ_NETWORK_STATE: read per-app mobile data usage
  - POST_NOTIFICATIONS: send a local notification when new abnormal events are detected
  - RECEIVE_BOOT_COMPLETED: re-register the scheduled audit alarm after reboot

【Suggested screen recording】
A 2-3 minute uncut device recording is attached / can be provided on request
(see the script below).
```

---

## 五、隐私政策 URL 与 GitHub Pages 托管

### 5.1 Play Console 里填什么

| 字段 | 填什么 |
|---|---|
| 隐私政策 URL | `https://jinchao-wang.github.io/whoruns/privacy-policy.html` |
| App Access → 隐私政策 | 同上 |
| App Access → 其它说明 | 填第五节的审核备注模板 |

**填写前必须自查三件事：**

1. **能匿名访问。** 在无痕窗口里打开 URL，必须能直接看到政策全文。Play 审核员不会登录你的账号。
2. **是网页，不是 PDF。** 托管成 HTML 页最稳。
3. **内容与 APK 行为一致。** 政策里写的每一条收集项，都要在代码里找得到对应实现。

### 5.2 用仓库的 `docs/` 目录开 GitHub Pages

仓库里已经有 `docs/privacy-policy.md`，直接用它当 Pages 源目录，不用额外维护一份。

**操作步骤：**

1. 推送到 GitHub（仓库 `whoruns`，归属 `jinchao-wang`）。
2. 仓库 **Settings → Pages**。
3. **Build and deployment → Source** 选 **Deploy from a branch**。
4. Branch 选 `main`（或你实际用的主分支），目录选 **`/docs`**，保存。
5. 等 1–2 分钟，Pages 会给出访问地址：
   `https://jinchao-wang.github.io/whoruns/`
6. 政策页地址就是：
   `https://jinchao-wang.github.io/whoruns/privacy-policy.html`

**为什么 Markdown 能变成 HTML：** GitHub Pages 会用 Jekyll 处理 `docs/` 目录，`.md` 文件会渲染成同名 `.html`。所以 `docs/privacy-policy.md` 对应 `/privacy-policy.html`。`docs/` 下每个 `.md` 都会生成一个页面，目录索引页可以用 `docs/index.md` 提供。

**几个注意点：**

- **仓库必须是公开的。** 私有仓库的 Pages 在免费账号下不是完全对外可访问的，而 Play 要求政策页对任何人可打开。
- **如果不想让 Jekyll 改动文件**，在 `docs/` 下放一个空文件 `.nojekyll`，Pages 会把目录当静态文件原样发布。
- **改完 md 要等一次构建**（约 1–2 分钟）才会生效。
- **不要把 `docs/` 里的文件删了又重建**导致链接失效；政策页 URL 一旦填进 Play，就别再改路径。

### 5.3 备选：用 GitHub Actions 发布

如果希望 `main` 一变就自动更新页面，或者想把源文件放在别处，可以加一个部署 workflow：

```yaml
# .github/workflows/pages.yml
name: Deploy docs to GitHub Pages
on:
  push:
    branches: [main]
    paths: ['docs/**']
permissions:
  contents: read
  pages: write
  id-token: write
jobs:
  deploy:
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/configure-pages@v5
      - uses: actions/upload-pages-artifact@v3
        with:
          path: docs
```

同样需要仓库 **Settings → Pages → Source** 选 **GitHub Actions**。

### 5.4 提交前自查清单

- [ ] 隐私政策 URL 在无痕窗口里能匿名打开
- [ ] 政策内容与当前 APK 行为完全一致（新增权限或新增采集项时同步更新）
- [ ] Data safety 表单与政策、以及 APK 行为三方一致
- [ ] 权限问卷答案与 APK 行为一致（尤其是「不用于分析/广告/共享」）
- [ ] 应用内「设置」页能跳转到这份政策（同一份文件，避免两处说法不一致）
- [ ] 录屏已录好，含授权全过程 + 未授权时的降级表现
- [ ] 应用无 `INTERNET` 权限，`aapt dump permissions` 确认过
- [ ] 装一次 release APK 从头到尾点一遍，确认没有崩溃和异常行为

---

## 六、常见退回原因与应对

| 可能的退回理由 | 应对 |
|---|---|
| 「`QUERY_ALL_PACKAGES` 的理由不充分」 | 强调 Android 11 包可见性限制导致默认可见包极少、审计结果严重失真；强调枚举结果不用于广告或画像。附上未授权对照演示 |
| 「无法验证 `PACKAGE_USAGE_STATS` 的使用」 | 附真机录屏：从首页引导卡一路走到系统设置页、开启权限、回到应用看到审计结果。录屏要完整，不要剪辑 |
| 「隐私政策与 Data safety 声明不一致」 | 三方逐条对齐：政策写了「不收集位置」→ Data safety 位置选「不收集」→ 代码里确实不请求定位权限 |
| 「应用功能需要权限但拒绝时体验异常」 | 展示降级行为：未授权时是干净的引导页，不崩溃、不空转、不弹错误 |
| 「权限用途声明过于笼统」 | 用第五节模板，把每个权限的**具体 API 调用**写进去，而不是只写「用于收集使用信息」 |

---

## 七、附：文件位置

| 文件 | 作用 |
|---|---|
| `docs/privacy-policy.md` | 隐私政策正文，同时作为 GitHub Pages 的源文件 |
| `docs/play-store-review.md` | 本文件，上架材料与答法 |
| `docs/monetization.md` | 变现与授权码运营手册 |
| `docs/architecture.md` | 技术架构说明 |
