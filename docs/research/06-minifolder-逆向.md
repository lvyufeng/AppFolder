# MiniFolder 逆向记录

对竞品 **MiniFolder App Folder Launcher**（Sunghyun Kim，bundle id
`com.sunghyunk3510.minifolder`，最低 iOS 26.0，记录时版本 2.18.1）的实测拆解。

**来源**：`ipatool download` 从 App Store 拉取的正式 IPA（本机账户），加一支
官方教程视频与一段本机录屏。IPA 主二进制与组件二进制都是 FairPlay 加密
（`LC_ENCRYPTION_INFO_64 cryptid 1`），所以**没有反汇编**；下面每一条都来自
**未加密的**部分：`Info.plist`、`Metadata.appintents/extract.actionsdata`
（App Intents 导出的 JSON）、各 `*.bundle/*.lproj/Localizable.strings`、
以及符号表/`strings` 里的少量 Swift 字段名。

## 一、结论：它和我们走了相反的路

| | AppFolder | MiniFolder |
|---|---|---|
| 格子点击如何打开 App | `SystemShortcut` + `RunSystemShortcutIntent`，**系统解析 token，零跳转** | **`AppLaunchIntent(bundleId:appId:)`**，自己拿 bundle id 解析，**要中转** |
| 打开失败怎么办 | 不发生（token 一定是有效目标） | `LaunchFailedAppIntent`（`openAppWhenRun: true`）兜底弹「打不开」 |
| App 名字 / 图标 | 系统只给 display name；图标靠目录+商店搜索猜 | 自己存 `name` / `iconFileName` / `iconSymbol` / `iconSymbolColor` |
| 能加哪些 App | **只有系统配置面板里能选的**（App 拿不到 token） | **任意**：bundle id + URL scheme 都是自己的数据 |
| 配置方式 | 在系统的「编辑小组件」里逐个选 | App 内建文件夹、搜索/扫描加 App、排序、配色 |

**一句话**：MiniFolder **没有实现零跳转直开**，它是用「自己存 bundle id + scheme
→ 打开时中转」换来了「任意 App + 完整编辑器」。这正是本项目当初**明确放弃**的
那条路（用户原话：不希望经过 AppFolder 中转）。

## 二、逐项证据

### 点格子打开 = 自己的 intent，不是 SystemShortcut

`MiniFolderWidget.appex/Metadata.appintents/extract.actionsdata`：

* `AppLaunchIntent` — `openAppWhenRun: false`，参数 `bundleId`、`appId`。
* `LaunchFailedAppIntent`（在 `Core` 模块）— `openAppWhenRun: true`，参数 `bundleId`。
* 对组件二进制 grep `SystemShortcut`：**0 次**。它根本没用系统动作槽。

对应文案 `AppFeature...strings`：`APP_LAUNCH_FAILED_MESSAGE` =「这个 App 可能没装，
或者来自别的国家区、用了不同的 bundle ID」——这是在解释**自己解析失败**。

### 它读的数据模型（组件字符串里的字段）

`urlScheme`、`bundleId`、`folderId`、`iconFileName`、`iconSymbol`、
`iconSymbolColor`，以及符号 `loadFoldersWithApps`、`loadFolderData`。
即：**一个文件夹 → 一组 App，每个 App 存名字/图标/scheme/bundleId**。

### 「识别已安装 App」到底是什么

有三条入口，强弱不同：

1. **导入 iOS 分析日志**（`BUNDLE_FINDER_*`，界面叫 "Import Installed Apps"）。
   让用户去 设置 → 隐私与安全 → 分析与改进 → 查看分析日志，搜文件名前缀
   `xp_amp_app_usage_dnu`，把最近的 `.ips` 导入。它的文案明写这份文件是**完整的**：

   * `BUNDLE_FINDER_INTRO` = "We read your iOS analytics log to find **every app
     installed on this device — including TestFlight and enterprise apps that aren't
     on the App Store**."
   * `BUNDLE_FINDER_FULL_INVENTORY_NOTE` = "This file contains the complete list of
     apps installed on the device."
   * `BUNDLE_FINDER_PARTIAL_INVENTORY_NOTE` = 旧文件只含「最近用过的 App」。

   也就是说，**这条路拿到的是全量已安装 App 的 bundle id**，连侧载和企业 App 都有。
   文件只在本机解析、不上传。

2. **系统 App + 头部 App 的 scheme 探测**。`Info.plist` 的
   `LSApplicationQueriesSchemes` 是一张写死的、约 50 条的头部 App scheme 表
   （whatsapp / instagram / weixin / tiktok / chatgpt / claude / alipay …）。
   这一栏的界面自认 `INSTALLED_APPS_NOTICE` = **"Only some major apps can be
   detected"**，另有一个 `LEGACY_AUTO_SCAN`（"Auto Scan (Legacy)"）。

3. **App Store 搜索**（`AppStoreSearch`）——本机录屏里用户实测走的就是这条，
   与我们仓库的 `AppStoreLookup` 同源。

### 它怎么把「装了」变成「能打开」——服务端 scheme 目录

这是它「点什么都开得动」的真正原因，也是本次逆向最重要的一条。相关文案：

* `UPDATE_NOT_IN_CATALOG` = **"This app is not registered in the server."**
* `UPDATE_FROM_SERVER` = "Update App"；`UPDATE_RESULT_SCHEME_ONLY` = "URL Scheme has
  been updated."（批量 `UPDATE_ALL_APPS` 从服务端拉 scheme）
* `APP_CATALOG_TITLE` = "App Catalog"；`POPULAR_APPS_PREPARING` = "Preparing popular
  app list..."；App 里装了 Firebase。

即：**它有一张服务端的 app→URL scheme 目录**，按 bundle id（和 App Store id）
查，查到就把 scheme 连同图标写进本地记录；组件的 `AppLaunchIntent(bundleId:appId:)`
打开时用的就是它。

**目录里没有的 App 怎么办**（这是它给出的兜底，也是我们该照抄的那一半）：

* `URL_SCHEME_INPUT` = "Enter URL scheme to launch %@. Usually add '://' after the
  app name." —— 手填。
* `CANT_FIND_SCHEME` / `SEARCH_ONLINE` = "Search '%@ URL scheme' online" —— 联网搜。
* `REQUEST_SCHEME_DESCRIPTION` = "Contact the app developer to ask for the URL
  scheme." —— 联系开发者。

> 结论：MiniFolder **不是**靠什么系统级能力拿到全部 scheme 的。它是**自己维护了一张
> 服务端目录**，加上**让用户手填**兜底。这两件事本地都能做，只是目录大小和更新方式不同。

### 它满足不了 / 明确承认做不到的

* 组件**不显示文件夹名**（`FAQ_FOLDER_NAME_ANSWER`）——和我们
  `appfolder-widget-label-is-fixed` 的结论一致：组件下面那行字是宿主 App 名。
* 拿不到别的 App 的**角标数字**（`FAQ_BADGE_ANSWER`：Apple 隐私政策不允许），
  只能用 Shortcuts 自动化模拟一个红点（`MARK_/CLEAR_APP_NOTIFICATION_INTENT`）。
* 玻璃组件在深浅色间**自动切换、App 内改不了**（`FAQ_GLASS_WIDGET_BG_ANSWER`）。

## 三、它的「玻璃 / 透明」是怎么做的（可借鉴）

编辑器里 Background 有五种：**Solid / Gradient / Transparent / Fully Transparent /
Translucent**，外加 **Brightness** 滑块；Icon 有 **Icon Size / Icon Appearance
(Default·Light·Dark) / Icon Gloss**；还有 **Dark 图标自动生成**（失败就报
`DARK_ICON_GENERATION_FAILED_*`）。

关键的两条文案坐实了它也有「两个组件」：

* `TRANSPARENT_NOT_APPLIED_TO_GLASS_NOTE` =「文件夹的透明背景**对 Glass 组件不生效**」
* `BLUR_WIDGET_APPEARANCE_MODE_NOTE` =「**Glass 组件**不跟随系统自动切换，图标恒为
  Light 样式；背景色随系统深浅色自动切换，App 内改不了」

这与我们仓库 `appfolder-widget-plate-measurements` 的实测**完全吻合**：
自绘底板（内容层）能做到纯色/渐变/亮度，但**看不透壁纸**；要真玻璃就必须走系统
底板那个版本，而那个版本的自定义被系统接管。MiniFolder 的做法是**两个组件各出一版**。

组件二进制对 `containerBackground` 有引用，和我们一样。

## 四、对我们的意义

1. **用户想要的「任意 App + 编辑器 + 玻璃」= MiniFolder 那一整套，代价是中转。**
   本项目 Core 价值是零跳转直开，二者在当前 API 下不可兼得。
2. **「App 内整屏玻璃库」这一层，MiniFolder 也有**（它的 Apps / Folders 标签页），
   而且那一层里点 App 一样是中转。所以我们原计划的方向没错。
3. **它证明「自绘底板 + 亮度滑块」可行**，且必须与「系统玻璃」分成两个组件——
   我们不必再自己摸索这条边界。
4. **它的 scheme 表还不如我们的目录**：写死 ~50 条、界面自认「只有头部 App」。
   我们的 `AppCatalog` 有 76 条含中文 App 且带 `confidence` 分级，探测上限 25 条
   是按 iOS 27 真实预算收敛过的。**这一项我们更强，不必抄。**