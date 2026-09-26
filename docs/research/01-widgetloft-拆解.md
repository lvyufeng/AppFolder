# WidgetLoft 拆解

> 调研日期：2026-09-26。数据来自 iTunes Lookup API、App Store 页面、widgetloft.app 官网与其隐私政策。

## 一句话

WidgetLoft 是「App Folder Launcher」的实体，作者**一个人**做出来的，**免费 + 订阅**（不是买断），最低 iOS 18.0，2026 年 6 月首发、9 月已迭代到 2.1.2。它踩中了 iOS 27 新开放的 widget 直开能力，把「大文件夹」做成了系统允许范围内最接近的形态。

## 基本盘

| 项 | 值 |
|---|---|
| 中区名称 | 应用文件夹: WidgetLoft |
| 美区名称 | App Folder Launcher WidgetLoft |
| Bundle ID | `com.koksoft.foldermini` |
| 开发者 | Mucahit KOKDEMIR（个人，artistId 1784103749） |
| 价格 | **免费** + 内购 + 广告 |
| 内购 | FolderMini Pro Monthly $1.99 / FolderMini Pro Lifetime $6.99 / WidgetLoft Pro Lifetime $14.99 |
| 最低系统 | **iOS 18.0** |
| 首发 / 当前版本 | 2026-06-26 / 2.1.2（2026-09-21） |
| 体积 | 59.2 MB |
| 分类 / 分级 | 工具·效率 / 4+ |
| 评分 | 中区 5.0（14 条）、美区 4.8（17 条） |

**关键线索：Bundle ID 是 `foldermini`。** 早期版本说明里写着 "FolderMini is built by one person"，1.2.0 的更新日志直接叫 "Introducing FolderMini Pro"。所以这是一个**先叫 FolderMini、后来改名 WidgetLoft** 的产品，「App Folder Launcher」是它为美区 ASO 拼的副标题。

对自己的启示：**ASO 名可以后改，Bundle ID 改不了。** 我们要一开始就把中英文关键词想清楚。

## 它到底做了什么

官网列出的能力，按我们的实现难度排序：

| 能力 | 难度 | 说明 |
|---|---|---|
| 一屏平铺 4–9 个真实 App 图标 | 中 | 图标来自 iTunes Search API，隐私政策明说了 |
| 点击直接进第三方 App | **高** | 见下节，这是整件事的核心 |
| 文件夹套文件夹 + 可换样式的返回按钮 | 中 | widget 内状态 + 时间线重载伪造的 |
| 同一分组适配小/中/大/特大四种尺寸 | 低 | |
| 锁屏 + 灵动岛 | 中 | |
| iOS 27 特大小组件，最多 77 个图块 | 低 | 靠系统新尺寸，不是自研 |
| 透明 / 液态玻璃 / 纯色 / 渐变 | 低 | |
| 深色图标（热门 App 预置，其余本地生成） | 中 | |
| 图标工作室（照片 / 符号 / emoji / 文字） | 低 | |
| 网站图块、快捷指令图块、人物图块（电话/短信/WhatsApp） | 低 | 都是不同的 URL scheme |
| 通知红点（iOS 27） | **未知** | 见下 |
| 备份导出 / iCloud 同步 | 低 | |
| 45 种语言 | 低 | 纯苦工 |
| 批量导入已安装 App（2.1.2） | **难** | 见下 |

## 核心机制：点击是怎么打开第三方 App 的

这是整个品类的技术命门，也是我们调研花时间最多的地方。

### 平台铁律

Apple 文档对 widget 的 `Link` / `widgetURL` 说得很直白：

> the system activates the **containing app** and passes the URL to `onOpenURL`

也就是说，**widget 里的链接只能打开它自己的宿主 App**，永远打不开别人的 App。这是 iOS 14 引入 widget 时就定下的规则，一直没变。

### 三条出路

**① 中转（iOS 18 – 26 的唯一办法）**

widget 发一个指向自己的 URL，把目标塞在参数里 → 系统打开 WidgetLoft → WidgetLoft 调 `UIApplication.open(target)` → 目标 App 起来。

代价很明显：**屏幕会闪过一次 WidgetLoft**。MacStories 的 Federico Viticci 写过，这正是他多年不用第三方启动器的原因：

> you would see the launcher app **flash onscreen briefly** before redirecting you

**WidgetLoft 自己在更新日志里承认了这条路的存在**，这是最硬的证据：

-  2.1.1："Apps in the Dynamic Island now open in a single step, **without passing through WidgetLoft**"
-  2.1.2："Schemes the widget could not open, **WeChat and Alipay among them, now open through WidgetLoft**"

第二句尤其关键：**微信和支付宝必须走中转**。我们自己的实现要默认假设中转是常态。

**② 通用链接直开（iOS 18.1 起，部分 App）**

`OpenURLIntent`（iOS 18.0 引入）可以让系统直接打开一个 URL，但它走的是 **universal link**，Apple 文档明确要求目标支持通用链接、自定义 scheme 不支持。所以只有那些把 `https://` 域名和 App 绑定的目标才能享受直开。

竞品 Cromulent Launcher 的帮助页列出了这份名单（Facebook、Instagram、LINE、Netflix、Spotify、Telegram、TikTok、Uber、WhatsApp、YouTube 等），并说了一句很关键的话：

> You will need to **recreate the launchers** running iOS 18.1 or higher

说明直开能力是**在配置期固化进 widget 的**，不是运行期判断的。这与 `SystemShortcut` 由系统代持引用的形态一致。

**③ 系统代持（iOS 27，官方正解）**

iOS 27 新增 `RunSystemShortcutIntent` + `SystemShortcut`。Apple 文档原文：

> An app intent you use in widgets to **open another app** or perform an App Shortcut, custom shortcut, or system action.
>
> When a person configures the widget, they choose the button's action. It can: **Open another installed app.** …

**这是 Apple 第一次给出「widget 按钮直开另一个 App、且不经过宿主」的正规通道。** 代价是 `SystemShortcut` 是**不透明值**：

> An opaque reference to a user-configured action for use in a widget button. … It doesn't provide the app or widget with a custom shortcut's actions, parameters, or implementation details.

也就是说，**用户得自己在小组件配置界面里挑**，我们拿不到任何可编程的目标列表。所以它撑不起一个「9 个格子的文件夹」，但非常适合做「一个最常用 App 的直开图块」。

### 三个机制的选择逻辑

| | 中转 | 通用链接 | 系统代持 |
|---|---|---|---|
| 生效 iOS | 18+ | 18.1+ | **27+** |
| 有闪烁 | **有** | 无 | 无 |
| 任意 App | ✅ | ❌ 需支持通用链接 | ✅ |
| 能撑网格 | ✅ | ✅ | ❌ 每配置位一个 |
| 失败可见 | ✅ | ❌ 静默 | ❌ 静默 |

**结论：三条路都要做，按目标 URL 的形态自动分派。** 这正是本仓库 `LaunchStrategy` 的设计。

## 未解之谜

### 通知红点（iOS 27）

WidgetLoft 2.0.5 的更新日志写着：

> Notification dot — a red dot on the tile of any app that gets a notification (**Shortcuts automation, iOS 27**)

「Shortcuts automation」这个括号说明它**不是**靠 API 读通知——那不可能，iOS 没有任何公开 API 能让一个 App 知道别的 App 有没有通知。（我把本地 SDK 的 WidgetKit / AppIntents / UserNotifications 全量 grep 过，`badge` / `unread` / `notificationDot` 零命中。）

所以它是让用户配一个快捷指令自动化，把「某 App 收到通知」这个事件写进 App 的存储。**这是把 API 缺失转化成了产品功能**，思路值得抄，但对我们来说优先级靠后。

### 批量导入

2.1.2 的 "Import apps in bulk instead of searching for them one by one"。

iOS 没有枚举已安装 App 的公开 API，唯一沾边的是 Screen Time 系的 `FamilyControls`，但：

- `FamilyActivityPicker` 只给**不透明 token**，能渲染图标，拿不到 bundle id / scheme → 对「打开 App」没用
- `FamilyActivityData.shared.installedApplications`（iOS 26.4+）能给 `bundleIdentifier`，但**需要 Apple 单独审批的 entitlement，且只在 EU 可用**

更可能的解释是：WidgetLoft 维护了一个**策展的 App 目录**（1.4.0 的更新日志就是 "A bigger app catalog"），批量导入只是一个多选 UI。竞品 MiniFolder 走的是第三条路——**让用户从系统的「分析数据」文件里解析出已安装 App 列表**（其商店截图里能看到 "This file contains the complete list of apps installed on the device"）。

我们的选择：先做策展目录 + 搜索（本仓库已实现），把「导入」留到后面做。

## 我们可以直接抄的经验

1. **默认走中转**，因为它对任何目标都成立。直开是优化，不是基础。
2. **把「切换方式」做成用户可见的开关**，因为哪种能成只有用户的设备知道。
3. **App 本身要有内容**，不能只是配置器——WidgetLoft 后半段更新几乎全在堆图标工作室、标签、归档、备份、指南。这既是产品需要，也是躲 4.2.2「a collection of links」的必需。
4. **更新日志是竞品情报的第一来源**。它为了 ASO 和留存，会把技术限制说得很清楚。
