# WidgetLoft 液态玻璃：重新分析

日期：2026-10-01。目标：从原始证据重新定位 **默认主屏幕外观下、逐小组件的 Liquid Glass**，不继承以前的机制结论。

## 固定前提与证据边界

用户已经明确确认：WidgetLoft 在默认主屏幕外观下就支持液态玻璃，不需要开启系统全局 Clear。这个观察是分析前提，不再要求用户重复确认。

**本轮终次结果：独立第三方测试 widget 已通过 `.preferredBackgroundStyle(.blur)` 在默认外观下复现系统玻璃；随后验证了内容层实心填充会把它盖掉。A=0 白板、B=2 玻璃、C=2+内容层实心色只在填充边缘透出玻璃，真实主屏对照截图与成功 UI/timeline 证据见第 7 节第六、七段。**竞品实际调用方式、真机与审核可用性仍未验证。

本轮没有修改 AppFolder 应用源代码、真实 SDK、真机、原有模拟器或它们的已安装应用；没有手改描述符数据库、全局 Clear 或主屏外观。后续运行对照只在新建的独立模拟器上构建、安装、启动临时测试 app，通过正常图库 UI 添加测试 widget；文件与产物放在独立临时目录。本文是研究记录，不是已经修好的功能声明。

必须分别回答两个问题：

1. **系统有没有逐小组件选择玻璃底板的路径？** 可用本地系统二进制、编译和以后受控运行实验回答。
2. **WidgetLoft 实际使用哪一条路径？** 需要竞品实际配置、调用链、描述符或渲染归档；截图相似和本方实验不能代替这些证据。

## 1. 已独立复核的竞品第一方证据

作者指南：<https://mucahitk.com/blog/transparent-widget-iphone>。

步骤是应用内 Edit Group → Transparent，然后在小组件图库选择：

| 名称 | 作者描述 | 图标外观 |
| --- | --- | --- |
| WidgetLoft | fully see-through | 支持 Automatic |
| WidgetLoft · Liquid Glass | frosted glass | 选择 Light 或 Dark |

透明/玻璃功能要求 iOS 26+；产品整体最低 iOS 18 不等于玻璃功能最低 iOS 18。流程没有全局 Clear 设置步骤。

这提供了两个入口的**配置差分**线索，但名称不能证明两个 `.appex`，也不能证明实际 kind 数量或使用了 SwiftUI `Material`。Apple 的 `WidgetBundle` 本来就允许一个 extension 暴露多个 widget：<https://developer.apple.com/documentation/swiftui/widgetbundle>。

独立重取的原文：

- `/private/tmp/wl-reset-20261001/public-contract/verify-jdtvbyk6/widgetloft-developer-transparency.html`
- `/private/tmp/wl-reset-20261001/competitor-originals/verify-W2ChZHkS/developer-guide.visible-text.txt:13–44`

商店版本历史也把文件夹底板与系统外观下的图标效果分开：1.4.3，2026-07-11，原文 “Transparent folders now look like real glass — and in Clear or Tinted Home Screen mode the app icons turn to glass too”。其中应用内的 global switch 不能误读成 OS 全局 Clear。

版本历史原件：`/private/tmp/wl-reset-20261001/public-contract/verify-jdtvbyk6/widgetloft-appstore.html`，`serialized-server-data` 的 `/data/0/data/shelfMapping/mostRecentVersion/seeAllAction/pageData/shelves/0/items/10`。

## 2. 系统数据流：已完成独立静态复核

检查环境是 Xcode 27.0（27A266a）、iPhoneOS 27.0 SDK。系统取证分别记录 simulator 27.0（24A434）与 DeviceSupport 27.0.1 原件，不能混用地址或把它们当作用户手机当前运行状态。

独立复核原始缓存、reflection、字段偏移和调用目标后，确认下面的配置路径：

```text
WidgetConfiguration.preferredBackgroundStyle(...)
    ↓ transformPreference
WidgetKit.WidgetDescriptor.preferredBackgroundStyle
    ↓ descriptor 转换
CHSMutableWidgetDescriptor.setPreferredBackgroundStyle:
    ↓ 宿主检查背景策略、材质绘制条件与 filterStyle
CHUISWidgetHostViewController 的背景视图模式
    ↓ 满足相应条件时
CHUISSolariumEffectView
```

这是配置偏好到宿主背景的路径，**不是** `containerBackground { Color.clear }` 的颜色推断。

渲染环境的方向相反：ChronoKit 读取已有系统 descriptor，再设置 `EnvironmentValues._preferredSystemWidgetBackgroundStyle`。因此单次环境值 `1` 不能证明 extension 向注册系统回报了 descriptor `1`。

独立复核确认：

- `WidgetKit.WidgetBackgroundStyle` 的枚举项是 `opaque = 0`、`transparent = 1`、`blur = 2`。不能把任何一个枚举项直接重命名为 `glass`。
- 正常 `StaticConfiguration` 所构造的源 descriptor 将 `preferredBackgroundStyle` 初始化为 `opaque = 0`。后续 configuration preference 仍可改变它，不能把初始值等同某次注册最终值。0 本身不是扩展崩溃、拒绝授权或注册失败的证明。
- 普通 appearanceType 0/1 的 tint 配置存在 `filterStyle = 7 / solariumColorized` 路径。宿主在 `backgroundViewPolicy = 0`、偏好为 `blur = 2`、`_drawSystemBackgroundMaterialIfNecessary = true` 时，以 filterStyle 7 选择 mode 3 并创建 Solarium 视图。**2 单独并不充分。**同一分支里偏好为 1 则返回无系统背景的 mode 0，不是创建 Solarium。这一静态路径不要求全局 Clear 的 `wantsGlassMaterial` 分支；实际设备的 policy/draw 等值仍未测量。
- 配置偏好的导出 ABI 在 SDK 链接桩中确实存在，公开 Swift 接口却没有对应声明。这是未公开入口的调查线索，不是竞品调用证据或可上架保证。同一 `.tbd` 也导出公开接口明确 iOS unavailable 的 `widgetTexture`，所以导出表本身不能证明第三方 iOS 可用性。

原始证据目录：`/private/tmp/wl-reset-20261001/system-runtime/evidence.QlUEGv/`。

关键文件：

- `WidgetKit.resolved.0x1ca9580c4.0x1ca958384.1790825244667388000.txt`：正常默认初始化。
- `WidgetKit.resolved.0x1ca984858.0x1ca9848f4.1790824737354501000.txt`：配置 preference 路径。
- `WidgetKit.resolved.0x1ca92a078.0x1ca92af68.1790824416300945000.txt`：源字段转给 CHS setter。
- `ChronoKit.resolved.0x1f7cf40ac.0x1f7cf44b4.1790824416288593000.txt`：descriptor → 渲染环境。
- `ChronoUIServices.resolved.0x20dcad784.0x20dcad854.1790824045574346000.txt:35–60`：背景模式条件。
- `ChronoUIServices.resolved.0x20dcad8bc.0x20dcade80.1790824982213684000.txt:237–270`：Solarium 背景创建。
- `resolved-calls-v2.json`：调用目标解析。

不能据此宣称 descriptor 只在首次 live render、开机或 picker 重加时计算。本轮尚未打通 chronod 请求、reply 和写库的完整时序。

## 3. 旧结论中需要撤回或降级的部分

### “style 0 只是扩展崩溃；解锁重加即可变玻璃”

独立核验的旧日志有成功取得新 descriptor、记录 `preferredBackgroundStyle = 0` 的 metadata 更新/插入、并接受新 timeline 的记录：`/private/tmp/chronod.log:3274–3305,4535–4569,4658–4680`。同一 bundle/kind 与扩展 PID 77729 可关联，metadata 版本为 `1-1-(2026-09-30T04:07:53Z)`；未绑定当前源码/二进制 UUID，也未核验数据库事务落盘。这不是完整 untouched baseline，但反驳了“0 只能由 crash-loop 造成”。重加是否改变结果仍未测，不能当作已证实修复。

### “SPI 编译/链接成功、但运行无效，所以系统忽略第三方调用”

旧实验中有实际扩展 SIGSEGV，错误 `_silgen_name` wrapper 以 `(C, Int32) -> C` 近似真实的泛型、枚举、opaque-return 方法。返回值、枚举身份和 ABI 没有正确表达。旧 crash 不能作为接口被系统忽略的负实验，后续未执行的调用也不能一并判无效。

原始例子：`/Users/lvyufeng/Library/Logs/DiagnosticReports/Retired/AppFolderWidget-2026-09-30-100437.ips:45,50,78`，其 debug dylib UUID 对应 `/private/tmp/afspi2/Build/Products/Debug-iphonesimulator/AppFolder.app/PlugIns/AppFolderWidget.appex/AppFolderWidget.debug.dylib`。

另外，用本地 opaque-return wrapper 导致 swift-frontend 的 substitution/codegen abort，只证明那个声明/代码生成失败，不证明正确导入真实接口必然无法编译。

### “像素相关性证明 WidgetLoft 使用相同 backgroundStyle”

复算旧全矩形 ROI，r² 约为 0.618；内缩空板区域可得到约 0.975。相关性受 ROI/mask 影响，只能刻画输出，不能识别 API、宿主/内容层，也不能检测实时采样。不能从本方修改 descriptor 后的相似外观倒推竞品实现。

复算原件：`/private/tmp/wl-reset-20261001/competitor-originals/verify-W2ChZHkS/verified-core.json:1464–1543`。

### “没列出 WidgetLoft／容器里没有图片，所以是特殊系统授权”

`devicectl device info apps` 默认只列 developer apps。旧 `/private/tmp/glass/apps_all.json:24–36` 用包含非 developer apps 的清单实际记录了 WidgetLoft 2.1.2/build 3；它是历史记录，不证明今天状态。

`widgetloft-probe.sh` 的复制失败、空目录、图片数量都不能区分系统 plate 与其他实现。该脚本本轮未执行。没有可信的竞品容器导出，更没有验真的竞品 `.appex`、descriptor 或渲染归档。

## 4. AppFolder 当前能确定的缺口与不能确定的缺口

当前源码已经有 `containerBackground(for: .widget) { Color.clear }` 与 `containerBackgroundRemovable(true)`。因此不能继续建议“补这两个调用”作为已定位修复。

真实配置没有调用 `preferredBackgroundStyle`；`glassEffect` 位于独立 preview，不等于 live widget 使用它。内容层是否存在实体填充取决于实际 entry.style，尚未取得实际 entry/归档，不能排除遮挡。

**有代码与终次对照支撑的缺口**：生产 AppFolder 没有提交逐 widget 的背景 preference；最小测试的 A 同样不提交，保持 opaque，B 提交 `.blur` 后注册为 2 并在 simulator 默认主屏显示玻璃。生产代码尚未接入。**尚未证明的部分**：WidgetLoft 实际是否使用同一入口，以及真机／iOS 26 上的运行与材质条件。

公开 `glassEffect` 在当前 SDK 可编译，不能由此直接推出 WidgetKit archive 能采样主屏壁纸；同样不能笼统宣称被禁止。

## 5. 最终定点验证结果

### 静态机制与旧实验

源字段身份、枚举、默认初始化、配置 preference、descriptor/environment 方向和普通外观下的条件性 Solarium 分支已独立复核。检查器修正过 field-offset-vector 单位和间接 type-ref 解码错误后，终次验证均 exit 0；早先检查器 exit 1 不是框架反例。

独立原件与输出：

- `/private/tmp/wl-reset-20261001/decisive-checks/system-refutation.ktozpler/source.final.txt:3–39`
- 同目录 `direction.verified.txt`、`host.final.txt:86–118,190–198`、`host.verified.txt`

旧日志独立复核支持第 3 节的限定结论；保留的错误 ABI 源码未与每份 crash UUID 逐一绑定，不能宣称每次崩溃的唯一根因都已经逐构建确认。

### 编译桥已成功：不需要伪造返回类型

只测试一个声明方案。在原始 WidgetKit textual interface 的**独立副本**中补充真实模块的非 frozen 枚举声明和正确的 opaque-return 方法声明，再生成可导入模块。没有修改真实 SDK，也没有编写 shadow enum 实现或自行定义 opaque descriptor。

客户端实际调用：

```swift
StaticConfiguration(kind: "compile-only.private-background", provider: ProbeProvider()) { _ in
    Text("Compile-only")
}
.preferredBackgroundStyle(.blur)
```

**这段调用需要本轮生成的接口副本，普通 SDK import 下不可直接使用。**

测试环境：Swift 6.4.0.34.1，iPhoneOS 27.0 SDK，客户端 `arm64e-apple-ios27.0`，Swift 6 语言模式。

| 检查 | 结果 |
| --- | --- |
| 从接口副本生成 WidgetKit.swiftmodule | exit 0 |
| 客户端 typecheck | exit 0 |
| emit-object | exit 0 |
| 链接原生 iOS dylib | exit 0 |
| 符号来源、load commands 核验 | exit 0 |

首次链接有继承 macOS SDKROOT 的 warning；保留该日志后，对同一目标文件仅重新链接，并在子进程明确设置 iPhoneOS SDKROOT。最终 linker trace 使用原始 iPhoneOS WidgetKit.tbd；产物 LC_BUILD_VERSION 为 IOS，minos/sdk 均 27.0，无代码签名。没有运行产物。

最终 dylib 引用的方法、真实 opaque descriptor、`.blur` case、rawValue getter 和枚举 metadata 均为 **undefined external (from WidgetKit)**，不是本地伪实现。

可复核原件：

- `/private/tmp/wl-reset-20261001/decisive-checks/compiler-bridge.ZD5ubj/attempt1/WidgetKit.swiftinterface:1740–1752`
- 同目录 `Probe.swift:24–33`
- 同目录 `commands-and-status.json`、`linkage-check-status.json`
- 同目录 `12-referenced-demangle.stdout.txt:1–5`
- 同目录 `08-native-link.stdout.txt:1`

命令 `run_attempt1.py` 与 `verify_linkage.py` 均 exit 0。原始 SDK interface/tbd 前后 SHA-256 不变。

**该编译阶段只证实正确表达真实接口并编译链接。**当时尚未运行调用或展示小组件；后续第 7 节已完成 simulator 的真实调用、0/2 注册及默认主屏玻璃对照，不能继续把早期阶段的证据边界当作终次状态。仍没有竞品使用此接口的直接证据；入口未公开，编译与 simulator 运行成功都不等于 App Store 审核允许。

## 6. 已执行的最小运行对照设计（实际结果见第 7 节）

最高信息量的下一步是在经授权的独立测试环境中，默认主屏外观、相同无内容填充的 entry、同一个最小扩展：

- A：不调用背景偏好 modifier。
- B：通过本轮接口桥调用 `.preferredBackgroundStyle(.blur)`，不是 `.transparent`。

记录构建 UUID、成功的新 descriptor 与 timeline，分开判断：调用是否安全、最终 descriptor 是否从 0 变为 2、宿主是否显示 Solarium。若值已变而效果未出现，继续检查 policy/draw 等必要条件，不能立刻把 API 判为无效。不手改缓存，不以重加/解锁代替因果对照，不修改现有 AppFolder 或真机。

按用户 2026-10-01 的要求，后续由主会话出方案、测试标准与审阅结论，执行验证用 headless Claude Code + `deepseek-v4.1-flash`，避免高成本模型重复复核。该模型的无工具 headless 调用已成功返回，CLI modelUsage 为 `deepseek-v4.1-flash`；这只验证模型通道，不等于上述运行对照已执行。

## 7. 实际运行记录：headless Flash

### 第一段：构建、安装、宿主启动已通过；尚未观测到配置查询

执行器：headless Claude Code，`modelUsage` 为 `deepseek-v4.1-flash`。一次执行约 178 秒，16 个记录阶段全部 exit 0。

- 独立目录：`/private/tmp/afglass-runtime-ab.uNmtgQ/`
- 新模拟器：`7A458AFF-6C1E-4194-871A-9F30ED14F455`，名称 `AFGlass AB unmtgq`，iOS 27.0 / iPhone 18 Pro。
- 独立 app：`com.lvyufeng.afglasslab.unmtgq`；extension：同前缀 `.widget`。
- simulator 专用接口副本、app 和 extension 均编译成功，签名、安装、宿主启动成功。
- 已收集日志中观测到 `AFGLASS_AB_HOST_STARTED`，未观测到 control/blur 配置 body 标记或目标 descriptor 查询；只读查询尚未取得目标 Descriptors 行。
- 结果是 `registration_trigger_or_descriptor_unconfirmed`，**不是接口无效或运行时 ABI 已通过**。宿主运行成功不能代替 extension 配置执行。
- 尚未放置小组件；本段留下的是默认外观的裸主屏截图，不是玻璃成功证据。
- 5 份相关仓库文件前后 SHA-256 相同，真实 SDK interface SHA-256 不变；未修改描述符缓存或全局 Clear。

原件：同目录 `result.json`、`runtime-stream.ndjson`、`headless-summary.json`、主屏截图、`08-uuid-widget.stdout.txt`。

下一段通过正常小组件图库 UI 触发查询并放置 A/B，由 Flash 执行。不能先要求存在 descriptor 再允许进入图库，否则会把可能的查询触发前提变成循环条件。实际模拟器是中文本地化，UI 测试兼容中文/英文标签，不修改语言或系统外观。

### 第二段：UI 工程通过编译，但扩展启动引导崩溃，图库没有测试条目

修正 headless 子进程路径授权后，Flash 无 permission denial，CLI exit 0，约 249.58 秒。内层 `xcodebuild` exit 65：工程编译通过，`testPlaceWidgets` 在 `lab-gallery-entry-A` 失败；约 185.43 秒的 runner 记录保存在 `Visual/`。不能把外层 CLI 成功当成 UI 成功。

实际失败截图明确显示“未找到 Glass AB Lab 的相关结果”，不是仅有自动化选择器匹配失败。A/B 均未放置，Descriptors 为空，源文件与原始 extension hash 不变。图库已实际触发目标 `getAllDescriptors`，但请求收到 NSCocoaErrorDomain 4099，扩展连接失效。

主会话审阅真实日志与 matching crash 后确认：

- 日志观测到目标 `GlassABWidgets` 启动及 `WidgetHost - Optional(WidgetKit.ResolvedWidgetBundleHost)`，随后以 `SIGTRAP` 退出；没有 A/B 配置体标记。
- Crash：`/Users/lvyufeng/Library/Logs/DiagnosticReports/GlassABWidgets-2026-10-01-142544.ips`，pid 58499，procPath 包含本轮独立 simulator UUID，目标 executable UUID 为 `60D0EEEF-2D54-4B8D-8D3D-4A5473B39C1F`。
- 触发栈顶是 `ExtensionFoundation` 的 `_EXRunningExtension._shared` 初始化，经 `_EXExtension.bootstrap(with:)`、WidgetKit 返回测试 bundle 的 `$main`。这是启动引导阶段的 crash，不是 `.preferredBackgroundStyle(.blur)` 已执行后被忽略的证据。
- 手工构建产物的 `LC_MAIN entryoff = 16268`，对应 `_main`。只读检查现有 Xcode-built reference 的 debug dylib，确认 `_NSExtensionMain (from Foundation)` 及 `___debug_main_executable_dylib_entry_point` 对它的 indirect alias。两者启动入口不同，是有原件支撑的修正线索，尚未证明它是唯一根因。

第一轮 UI 原件：`Visual/result.json`、`Visual/runtime-stream.ndjson`、`Visual/Run.xcresult`、`Visual/Attachments/manifest.json`；失败截图保存在 `Visual/Attachments/`（本机，不入库）。

下一次受控验证已交给 headless Flash：保持 widget source 与原始 executable 不变，只在 `Visual/Bootstrap/` 新构建标准 `_NSExtensionMain` 入口的副本，记录新 UUID；临时 app/extension build version 同步变为 2，通过正常安装触发新注册。单次 UI 结果写入新的 `Visual/BootstrapRun/`，保留第一轮失败证据，不修改 AppFolder、真实 SDK、全局外观或缓存。此处记录的是待验证的修正，不是启动成功或玻璃成功声明。

### 第三段：真实配置已执行，新 descriptor A=0 / B=2；玻璃视觉尚未验证

headless Flash 用约 4.07 秒成功构建新入口副本，5 个记录步骤均 exit 0。源代码 SHA-256 不变，原始 executable 未修改，真实 SDK interface hash 不变。新测试 UUID 为 `2EDB7341-C0C3-4980-95C5-5ECDBF0EEAE4`，`LC_MAIN entryoff = 25624`，引用真实 Foundation 的 `_NSExtensionMain`。入口与 version 变更均已记录，不能把它当成原始二进制。

主会话核对原始 runtime stream 与 archive：

- pid 62520 / 新 UUID 在 14:41:16.646 记录 `AFGLASS_AB_CONTROL_BODY`，14:41:16.652 记录 `AFGLASS_AB_BLUR_BODY raw=2`；随后有实际 placeholder 调用。
- 新 Descriptors 行 rowid 41 的 `descriptor-row-41.bplist`，object 2 为 `AFGlassAB.Control / backgroundStyle=0`，object 17 为 `AFGlassAB.Blur / backgroundStyle=2`。只读解码全部 archive objects，未执行 UPDATE 或写缓存。
- 两个 widget 在同一个新测试扩展中；源配置差分仍是 B 增加 `.preferredBackgroundStyle(.blur)`，相同内容、provider、family 与 clear container。

**现在已经有运行证据证明：正确导入的真实 opaque-return API 能在该 simulator 27.0 / 第三方测试扩展中执行，并改变系统注册 descriptor。**此前“第三方调用必被忽略／唯一来源是系统授权”的否定结论不能维持。这不是竞品真实调用证明，也不是 iOS 26／真机／审核可用性保证。

UI 本轮仍未通过：runner 在 330 秒上限中断，`status=ui_test_timed_out`，实际 testcase 于约 141.86 秒在 `lab-gallery-entry-A` 失败；附件导出 exit 64，不能声称完整 xcresult 已完成。该轮结束时的主屏截图实际显示了 Glass AB Lab 搜索条目，说明已不是注册缺失。旧选择器只查询 Button / StaticText / Other，未覆盖 Cell；接下来只修 UI 选择器与导航，复用已证明的 widget binary，结果写到 `Visual/PlacementRun/`。

原件：`Visual/Bootstrap/result.json`、`Visual/BootstrapRun/result.json`、`Visual/BootstrapRun/runtime-stream.ndjson:1945,1961`、`Visual/BootstrapRun/descriptor-row-41.bplist`。

**视觉边界仍未改变：尚未放置 A/B，没有默认主屏玻璃成功截图，未测量实际宿主 policy/draw 值。**不能把 0/2 的机制突破写成完整玻璃功能已经实现。

### 第四段：只修元素类型仍失败；未产生任何玻璃视觉证据

`Visual/PlacementRun/` 的 testcase 在约 8.223 秒再次因 `lab-gallery-entry-A` 失败，随后 xcodebuild reporter 未退出，runner 到 330 秒上限才中断；这不是 330 秒有效 UI 工作。A/B 都未放置，读到的 0/2 是上一段已经注册的 descriptor，不是本段新注册或玻璃渲染证据。源与原始 extension 仍未修改；defer 的正常 Home 操作确实关闭了图库，最终截图是裸主屏。

新选择器虽然查询全部元素类型，却仍使用 `.firstMatch`。同名主屏图标可能位于图库弹层后面；第一个不可点击的匹配并不能说明不存在可点击的前景条目。这一原因尚待候选元素 type/frame/hittable 记录确认，不再把 Cell 单独视为已验证根因。

下一次 UI-only 检查枚举全部同名候选，只取可点击元素；把 UI 树直接输出到测试日志，避免依赖未完成 xcresult 的附件导出；只在已审阅的独立 lab 页面通过正常空白壁纸长按进入编辑模式。新 runner 上限 240 秒，实际 testcase 完成后若 reporter 仍挂住，仅留 15 秒收尾，再中断本轮自建进程。结果保存在新的 `Visual/HitRun/`。不重编或改变已验证的 widget executable，不改缓存／外观。

### 第五段：同名遮挡根因已证实；A 卡片可见，按钮标签有前导空格

`Visual/HitRun/` 的 runner 约 39.79 秒，case 约 18.017 秒，xcodebuild exit 65。此次附件成功导出。原始 candidate 日志与截图确认：同名匹配包含被弹层遮住的主屏 Icon（type 44，hit=false）、前景 Cell（type 75，hit=true）与 StaticText（type 48，hit=false）。枚举可点击候选后，实际进入了 A Default 卡片，截图清楚显示 A 的白色底板与下方蓝色添加按钮。

失败不是“按钮被系统禁用”。原始 UI 树的按钮 label 为 `" 添加小组件"`，有一个前导空格；旧匹配 `"添加小组件"` 未覆盖这个原始字符串。A 的身份已在原件中确认，本轮并没有 manifest 所列以外的三次 selector 截图；不能采信子执行器关于“三次滑动均失败”的附带叙述。A/B 仍未放置，0/2 仍为已验证的既有 descriptor。

另一个执行报告错误也已保留：`headless-summary.json` 记录一次不在 allowlist 内的 Bash/awk 日志检查被拒绝，但子报告结尾声称“无权限拒绝”。未执行被拒的 Bash 操作，不扩权或代执行它；后续只允许既有 trusted runner 与已授权的 Read 取日志，实际 denial 必须如实记录。

原件：`Visual/HitRun/result.json`、`headless-summary.json:9–17`、`Visual/HitRun/Attachments/` 下的截图与 UI 树文本（本机，不入库）。

下一次 UI-only 检查只补实际按钮字符串及相应英文前导空格形式，把卡片滑动坐标移到已审阅截图的实际预览中心；复用相同 widget binary 与 scoped permissions，保留全部历史结果，新输出为 `Visual/SpaceRun/`。

### 第六段：完成正常放置，默认外观原生玻璃已复现

headless Flash 本轮约 63.06 秒；实际 UI case 37.017 秒，runner 43.38 秒，`xcodebuild`、主屏截图与附件导出全部 exit 0，case passed。按普通图库流程明确选择 A Default，再选 B Blur，添加两者并退出编辑模式；没有手改 descriptor、IconState 或全局外观。

主会话审阅原始截图、选择过程、归档与 timeline 日志后确认：

| 最终主屏位置 | 配置 | registered backgroundStyle | 实际输出 |
| --- | --- | --- | --- |
| 左上 | B：`.preferredBackgroundStyle(.blur)` | 2 | 透出壁纸、边缘与曲线明显形变的玻璃底板，白色内容 |
| 右上 | A：无背景 preference | 0 | 不透明白色底板，黑色内容 |

两者为相同 systemSmall 内容、provider、clear container；widget 源没有 `glassEffect`、Material 填充或壁纸图片。本次不是仅比较图库 preview：退出编辑模式后的主屏截图同时显示两者，普通彩色 app 图标保持默认外观。SDK、AppFolder 仓库源、原始测试 executable 都未变。

已保留未编辑的截图，全部只在本机，不随仓库提交（`docs/research/evidence/` 已被 `.gitignore` 忽略）：

- 默认外观 A/B 对照（左侧 B.blur 玻璃，右侧 A 默认白板）、明确选择 B 的图库卡片、以及第 7 节第七段的 A/B/C 对照，均在 `docs/research/evidence/`。
- 对应原始附件在同轮 `Visual/SpaceRun/Attachments/`、`Visual/PlateRun6/Attachments/`。
- defer 按 Home 后的主屏截图是回到第 1 页的系统 widgets，**不是**本次 A/B 证据，不能引用错。
- `Visual/SpaceRun/runtime-stream.ndjson:1962,3013` 有两次实际 `AFGLASS_AB_TIMELINE`，pid 62520 / UUID `2EDB7341-C0C3-4980-95C5-5ECDBF0EEAE4`；另有 snapshot 与 chronod `getTimelines(1)` result。
- 经主会话核对，标准入口副本与本轮 app 嵌入的 extension executable SHA-256 都仍是 `458feea92473b8888c5f790fcb79af2f856c576931d34bdfba5e8b8a5a19605b`。
- 原始记录：`Visual/SpaceRun/result.json`、`Run.xcresult`、`Attachments/manifest.json`。

**此次完成的结论**：在 simulator iOS 27.0 / 默认主屏外观下，第三方最小 widget 能通过真实的 configuration-level `.preferredBackgroundStyle(.blur)` 路径请求系统玻璃底板，正确注册 `backgroundStyle=2` 并实际显示；不需要修改全局 Clear 或缓存。这提供了与 WidgetLoft 用户确认行为一致的可复现机制，推翻“第三方无法申请／必须特殊系统 grant／API 一概被忽略”的旧否定。

**尚未完成的结论**：没有直接读取 WidgetLoft 原版 `.appex`／descriptor，所以不能断言竞品实际使用这一 API；没有实测真机或 iOS 26；入口依然未公开，普通 SDK import 无法直接调用，需要本轮声明接口桥，不能保证审核允许。实际宿主的 policy/draw/filterStyle 或 Solarium 对象实例没有动态采集，静态条件链与观察到的 native 输出应分别记述。生产 AppFolder 尚未接入此 modifier。

### 第七段：内容层实心填充会盖掉玻璃（阶段 C）

第 0 步问题：AppFolder 的内容层可能按 `entry.style.plateFill` 画一块 `Rectangle().fill`。玻璃是宿主背景，内容层若画实心色就会盖住它。在同一个独立 lab 上用第三个变体验证，**不修改 AppFolder 任何源码**。

阶段 C 的 widget 源是父会话在 `Visual/PlateWidgets.swift` 新建的文件，不是 `sources/GlassABWidgets.swift` 的修改；A、B 逐字保留作为同轮对照，C 复制 AppFolder 的真实排布：内容层 `.background { Rectangle().fill(#3478F6) }`、`containerBackground { Color.clear }`、`containerBackgroundRemovable(true)`、`contentMarginsDisabled()`，配置上加 `.preferredBackgroundStyle(.blur)`。

| 变体 | 配置 | registered backgroundStyle | 实际输出 |
| --- | --- | --- | --- |
| A Default | 无 preference | 0 | 不透明白板，黑字 |
| B Blur | `.blur` | 2 | 整块玻璃，壁纸透出并形变 |
| C Plate | `.blur` + 内容层实心填充 | 2 | **同一 widget 内：蓝色填充处是纯色，填充未覆盖的边缘透出玻璃** |

C 的 descriptor 与 B 完全同值（`2`），说明玻璃底板确实存在；但视觉上它只在内容层没有画色的地方可见。把已复现的机制接进 AppFolder 时，**玻璃与"用户挑选的实心色"在同一个 widget 上只能二选一**：当前默认的 透明（`plateFill == nil`）能拿到玻璃，纯色/渐变会在内容层把它盖掉。这是既有的 `FolderPlate` 设计在被证实之前就已经写下的取舍，现在有了直接证据。

本机保留的默认外观 A/B/C 对照（A 白板、B 整块玻璃、C 玻璃只从填充边缘露出）在 `docs/research/evidence/`，原始附件在 `Visual/PlateRun6/Attachments/`，均不随仓库提交。

- 阶段 C 构建记录：`Visual/PlateProject/result.json`，新扩展 UUID `F361155D-B723-4507-898D-3E664C8A8637`，扩展可执行 SHA-256 `4e5ed8607e196f6fc5abf97f5c249354a2c30e5415eb3b2198a479ecd3954279`，与本轮 runner 记录的 `tested_extension_sha256` 一致。
- 成功 UI 运行：`Visual/PlateRun6/result.json`，`status = ui_test_completed`，`case_outcome = passed`，case 76.412 秒，`xcodebuild_exit_status = 0`，`export-attachments_exit_status = 0`，`repo_unchanged = true`，`original_extension_unchanged = true`。
- 三条 descriptor 同属 rowid 41：`AFGlassAB.Control = 0`（object 2）、`AFGlassAB.Blur = 2`（object 17）、`AFGlassAB.Plate = 2`（object 22）。
- 本轮多次 UI 失败都发生在导航阶段（gallery 入口、卡片滑动坐标），与 widget 机制无关；成功那次只在翻页逐页查找 App 图标后长按进入编辑模式。这些失败运行各自独立保存在 `Visual/PlateRun…/`，未覆盖。
- widget 源与原始扩展二进制全程未变；未改 SDK、AppFolder 仓库源、缓存或全局外观。

## 一手资料

- 作者操作指南：<https://mucahitk.com/blog/transparent-widget-iphone>
- 商店版本历史：<https://apps.apple.com/cn/app/app-folder-launcher-widgetloft/id6782827870?l=en-GB>
- WidgetBundle：<https://developer.apple.com/documentation/swiftui/widgetbundle>
- 容器背景契约：<https://developer.apple.com/documentation/widgetkit/displaying-the-right-widget-background>
- glassEffect：<https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)>
- Clear/Tinted 的常规适配路径（不是本任务答案）：<https://developer.apple.com/documentation/widgetkit/optimizing-your-widget-for-accented-rendering-mode-and-liquid-glass>
- App Review 2.5.1：<https://developer.apple.com/app-store/review/guidelines/#software-requirements>
