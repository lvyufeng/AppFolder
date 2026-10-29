# WidgetLoft 拆解

## 当前功能差距矩阵（2026-10-29）

本节维护完整目标；后面的 2026-09-26 原文保留为历史证据，不代表当前实现或 API 结论。状态以当前工作区源码为准，运行验证以 [README](../../README.md) 的记录为准；“源码已接入”不等于最终构建已验收，更不等于已上架。当前 iPhone / iOS 27 / 四种主屏尺寸是实现范围，**不是用户永久排除 iPad、旧系统或其他尺寸的决定**。

证据分三层：竞品官网／商店记录只证明其公开宣称的产品行为；Apple 文档与本机 SDK 证明公开接口及约束；AppFolder 源码和实际运行记录证明我们自己的实现。不能从竞品“直开”“常驻”“通知计数”等措辞推断它用了什么接口，或承诺 AppFolder 能直接复制。

### 当前来源与优先级

- **W1：[WidgetLoft 官网](https://widgetloft.app/)**：当前展示联系人、锁屏／灵动岛、超大竖屏、不同密度、深色图标及网站打开方式。
- **W2：[WidgetLoft App Store 页面及版本记录](https://apps.apple.com/us/app/app-folder-launcher-widgetloft/id6782827870)**：本次可见 2.1.8；近几版补充子文件夹外观、圆点计数、图标包、文件选图、当天日历等。语言数量口径有差异：官网称 45，商店当前列 English + 38 More；不把任一数字当我们的完成标准。
- **W3：[开发者的网站打开方式说明](https://mucahitk.com/blog/open-website-in-chrome-from-widget-iphone)**：说明指定浏览器／内嵌浏览器与默认打开方式的行为区别。
- **A1：商店地区**：[Apple App Store 地区表](https://developer.apple.com/help/app-store-connect/reference/pricing-and-availability/app-store-pricing-and-availability-start-times-by-country-or-region/)与[Apple 服务可用性](https://support.apple.com/en-us/118205)共同确定 175 个商店地区。前表 NER／Nigeria 行有误，后一清单确认 Niger 与 Nigeria 均有 App Store，分别使用 ne／ng；Kosovo 使用 Apple 的 [xk 商店](https://apps.apple.com/xk/iphone/apps)。[Search API](https://performance-partners.apple.com/search-api)明确默认美国，未提供读取账户地区的语义；Lookup 的 JP／XK 行为另有公开请求实测，不把 Search 参数表冒充 Lookup 单独契约。
- **P0**：完成当前已做功能的上架验收与故障恢复，不增加功能面。
- **P1**：下一批优先交付，公开路径较清楚，能直接减少配置步骤或增加常用入口。
- **P2**：明确保留的产品差距，需要独立模型／布局／迁移工作；不是已否决。
- **P3**：先核验公开机制或产品边界，再决定实现；不是承诺，也不是永久排除。
- **已覆盖**：继续保留回归验证，不因竞品有相似功能而重做。表内优先级是建议，不代表用户已批准每项实现。

### 启动、布局与桌面体验

| ID | 需求／竞品证据 | AppFolder 当前状态及代码证据 | 仍欠缺的最小完整边界／限制 | 优先级 |
| --- | --- | --- | --- | --- |
| F01 | App、App Shortcut、自建快捷指令与系统动作（W2） | **已覆盖用户配置后的启动**。[QuickLaunchIntent](../../AppFolderWidget/QuickLaunchIntent.swift) 持有系统动作数组；[SavedGroupBinding](../../Packages/AppFolderKit/Sources/AppFolderKit/SavedGroup.swift) 只绑定唯一同名项。 | 不等于自动枚举 App、代选系统动作或程序构造其参数；唯一同名也不能证明目标仍安装或动作执行成功。不能把已有快捷指令能力列为未实现。 | 已覆盖 |
| F02 | 保存分组、嵌套、空位、移动与分页（W1/W2） | **基础组织已覆盖，画布编辑已接入**。[SavedGroup](../../Packages/AppFolderKit/Sources/AppFolderKit/SavedGroup.swift) 保留 200 项、四层、列表移动与历史；[画布](../../AppFolder/SavedGroupPreview.swift) 新增原生拖动、650ms 悬停导航和菜单／VoiceOver 选择移动。[原子落点](../../Packages/AppFolderKit/Sources/AppFolderKit/SavedGroupDrop.swift) 按 ID 插入、交换空位或物化虚拟格，一次放下一步撤销；会话 epoch 防取消后迟到重放，无新位置字段。 | 15 项新增核心测试，聚焦 64 项及全量 613 项／77 套通过；最终 Debug／Release 构建通过。Mac 锁定，真实拖动／取消、跨页／层悬停、菜单／VoiceOver、视觉落点与保存／撤销闭环均待验收，不能用模型测试代替。 | P1：完成画布运行验收 |
| F03 | 同组适配小、中、大主屏组件（W1） | **已覆盖**。[DirectLaunchWidget](../../AppFolderWidget/DirectLaunchWidget.swift) 另已加入竖向超大；四种尺寸的预览与组件共用 [FolderGridMetrics](../../Packages/AppFolderKit/Sources/AppFolderKit/FolderGridMetrics.swift)。 | 标准布局保留小号 4／9、中号 10、大号 16 格；新增密度及竖屏的桌面验收见 F04／F05。 | 已覆盖 |
| F04 | iOS 27 超大竖屏、最高 77 格（W1） | **已实现，真实主屏交互待验收**。注册 `systemExtraLargePortrait`；标准 5×8、大图标 4×6、密集 7×11，预览／分页／导航 key 已接入。Test 模拟器 context 实测 349.6667×565.6667 pt，预览已校准。 | 389 项／46 套测试及最终 Debug／Release 通过；App 内 77 格视检、末页及跨尺寸文件夹返回已验证。双外观 154 幅照片像素低于 6 MiB 不等于实际 RSS。保存分组有 77 内容格，默认布局为 76 直开＋其他；真实主屏添加／点按／运行内存仍待验收。 | P1：完成桌面验收 |
| F05 | 多网格密度、不同尺寸的大图标布局（W1/W2） | **已实现，新增密度桌面交互待验收**。[FolderDensity](../../Packages/AppFolderKit/Sources/AppFolderKit/FolderDensity.swift) 提供标准／大图标／密集：中号 10／8／21、大号 16／9／49、竖屏 40／24／77；小号仍用 4／9。图标大小和名称显示独立保留。 | App 内 10→8→21、撤销／重做、49／77、密度保存及小号控件隐藏已验证；共享容量、父页定位、配置摘要、诊断、预览和图片预算已接线。旧标准编码及导航 key 保持兼容；新密度实际桌面点按尚待验收。 | P1：完成桌面验收 |
| F06 | 每组外观、图标名称与显示昵称（W1/W2） | **基础外观、命名预设与精细外观已接入，实际控件待验收**。[SavedGroupAppearance](../../Packages/AppFolderKit/Sources/AppFolderKit/SavedGroupAppearance.swift) 新增可选间距／边距、名称颜色与描边颜色／三档宽度；未设置时保持旧默认及编码。[命名预设](../../AppFolder/AppearancePresetsView.swift) 支持保存快照、搜索、改名、更新、移除及条件撤销，最多 64 条，并包含精细外观。主动应用到当前层为一步编辑撤销，不连带更新其他组。完整备份 v16 包含预设，单组分享不带全局预设库。 | 全量 672 项／85 套、精细外观核心 83 项／备份 7 项／标题 13 项聚焦通过；36 组默认布局各 11 字段和 16 项默认标题像素对比保持一致，模拟器 Debug／iPhone Release 均零警告／零错误构建通过。Test 模拟器已安装启动、原有 13 组未变；真实控件、颜色选择生命周期、保存／复用／独立子文件夹／撤销、v16 备份界面与 WidgetKit 显示仍待验收。独立玻璃链路保留，上架兼容性未定。 | P1：精细外观、预设与 WidgetKit 运行验收 |
| F07 | 子文件夹独立外观与返回按钮样式（W1/W2） | **已实现，App 内作用域与保存已补验**。[GroupItem](../../Packages/AppFolderKit/Sources/AppFolderKit/SavedGroup.swift) 可保存完整 `folderAppearance`；nil 继承最近祖先，首次实改复制继承值。[SavedGroupPageLayout](../../Packages/AppFolderKit/Sources/AppFolderKit/SavedGroupPageLayout.swift) 统一当前布局和父页返回，返回样式可选三种；每个文件夹独立选择 2×2／3×3 内容 mini。编辑、预览、undo、组件与 v8 备份已接入。 | 关闭 `useGroupAppearance` 时内部样式统一使用组件设置，own mini 与封面仍显示；mini 不继承且不隐式创建外观覆盖。完整 420 项／50 套测试及最终 Debug／Release 通过，无警告或错误；本轮合成空文件夹实测：3×3 mini 不开启独立外观，隐藏标题自动独立，turnUpLeft 即时显示且保存重开保留；恢复跟随还原父标题／chevronUp、保留 nine，撤销恢复独立。真实组件／跨容量返回待验收。 | P1：完成真实组件及跨容量返回验收 |
| F08 | 透明、玻璃、纯色和渐变（W1） | **独立玻璃已恢复，上架兼容性未解决**。默认主屏下大号／小号已实测玻璃，无需全局透明／色调；纯色和渐变覆盖行为保留。 | 恢复的是此前已验证的未公开 `preferredBackgroundStyle(.blur)` 与 overlay。此前改用普通自适应底色是功能回退，不能视为满足要求。公开玻璃 probe 仅构建、未完成桌面实验；当前产物不能据此宣称可提交。 | P1：保留独立玻璃并解决上架兼容性 |
| F09 | 文件夹转场、启动后／超时回根（W2） | **部分覆盖**。[WidgetState](../../Packages/AppFolderKit/Sources/AppFolderKit/WidgetState.swift) 和 [SavedGroupNavigation](../../Packages/AppFolderKit/Sources/AppFolderKit/SavedGroupNavigation.swift) 支持导航，App 回前台请求收起。 | 未实现可选转场、可调超时或对所有系统动作启动成功的检测。先定义可观测触发与恢复规则，不能用任意 timeline 刷新推断用户已启动目标。 | P2；不可观测行为先 P3 |
| F10 | 未配置／同名冲突／失效分组的自助恢复 | **诊断已覆盖，格子帮助入口本轮接入**。[BindingReport](../../Packages/AppFolderKit/Sources/AppFolderKit/SavedGroupBindingReport.swift)、[读取状态](../../Packages/AppFolderKit/Sources/AppFolderKit/SavedGroupStore.swift)、[WidgetConfigurationHelpView](../../AppFolder/WidgetConfigurationHelpView.swift)。 | 帮助路由只读，按当前 revision 和目标报告定位，不能拿另一份成功报告掩盖失败；帮助入口最终运行验收单独记录，不能仅凭源码宣称完成。 | P0 |

### 图标与内容类型

| ID | 需求／竞品证据 | AppFolder 当前状态及代码证据 | 仍欠缺的最小完整边界／限制 | 优先级 |
| --- | --- | --- | --- | --- |
| F11 | 普通／深色独立图标、照片、符号和文字（W1） | **已覆盖，补齐草稿提示与照片底色一致性**。[CustomIconVariants](../../Packages/AppFolderKit/Sources/AppFolderKit/CustomIconVariants.swift)、[CustomIconEditorView](../../AppFolder/CustomIconEditorView.swift) 用于动作、网站、联系人和文件夹封面。独立 iOS 探针载入生产编辑器：普通透明红底照片→蓝色符号→照片保持蓝底，深色独立黑底；保存 PNG SHA／4,430 字节不变；深色改为「跟随普通图标」后透明照片显示普通红底。另一侧草稿未完成会说明原因并可跳回，恢复默认后可保存，取消不写入 AppFolder App Group。 | 证据 `/tmp/appfolder-editor-probe/ui-verification.json`；不替代系统 Files／Photos 或真实 WidgetKit 验收。图标按组件环境明暗选择，透明／着色效果由系统决定。 | 已覆盖；系统选择器与组件边界验收保留 |
| F12 | 预置／自动生成深色图标（W1） | **本地生成已接入并完成 App 编辑器验收**。[DarkIconGenerator](../../Packages/AppFolderKit/Sources/AppFolderKit/DarkIconGenerator.swift) 调整语义背景或本地图片，保留日期、alpha、普通原字节及 v11。缓存按已有 ID／地区读取，不下载素材。 | 先对比预览、明确替换、一次撤销；后续编辑清除旧撤销。已验证取消、120% 裁剪恢复、当前裁剪来源、日期保存和缓存缺失／命中。519 项／65 套及最终 Debug／Release 通过。非官方深色图标；复杂图片只轻度调整，真实组件与 UI 竞态验收边界见 README。 | 已覆盖核心与 App 编辑；组件验收待补 |
| F13 | 更多符号及搜索（W2） | **目录与本地搜索已实现，选择／保存已实测**。[CustomIconSymbolCatalog](../../Packages/AppFolderKit/Sources/AppFolderKit/CustomIconSymbolCatalog.swift) 提供 150 项／10 类，原 70 项保留；[选择器](../../AppFolder/CustomIconSymbolPickerView.swift) 支持本地化名称／分类、中英关键词及 SF 原名搜索，按打开时的明暗侧应用，取消不写。 | iOS 27 的 150 个 UIImage 与四种格尺寸共 600 次实际 SwiftUI 绘制全部有像素，联系表无空图；这不等于真实 UI 点按通过。完整 452 项／56 套测试（10.560 秒）及最终 Debug／Release 通过，无警告或错误；两份产物的十语 160 个目录／分类键零缺失。本轮已实测「购物与财务」分类、banknote.fill 选择、取消保留草稿及普通蓝纸币／深色黑爱心分别保存重开；sheet 搜索输入受工具 AX／坐标限制，仍待验收。持久化／资源 hash 不变，该轮备份仍 v9；旧版不保证支持新增符号，拒绝未知内容。 | P1：完成 sheet 搜索输入验收 |
| F14 | 从“文件”导入图片（W2） | **已实现并构建通过，界面验收待完成**。[CustomIconEditorView](../../AppFolder/CustomIconEditorView.swift) 提供系统 Files 单图入口；[IconPhotoFileReader](../../Packages/AppFolderKit/Sources/AppFolderKit/IconPhotoFileReader.swift) 协调只读选中 URL，[IconPhotoImport](../../Packages/AppFolderKit/Sources/AppFolderKit/IconPhotoImport.swift) 有界解码 PNG／JPEG／HEIC／HEIF，复用双外观草稿、裁剪和小图保存。 | 不请求整个照片库，不长期保留源文件／URL 授权；云端文件可由系统或提供商下载。系统 Files 选择器已实测打开；提供商页面缺少工具 AX 内容且坐标不可用，尚未选图／裁剪，取消／保存及云端下载仍待验收。完整 406 项／48 套测试通过；同侧跨来源晚回调已保护，最终 Debug／Release 构建均成功，无警告或错误。 | P1：完成 Files 界面与云端验收 |
| F15 | 图标包／统一线条主题（W2） | **未实现**。没有包 manifest、映射或批量应用／恢复操作。 | 先选有明确再分发许可的本地图标包，定义映射、预览和应用范围；保护已有自定义、可撤销并纳入备份。下载任意 SVG／压缩包不是必要的首版边界。 | P2 |
| F16 | HTTP(S) 网站、独立图标、与动作混排（W1/W2） | **已覆盖**。[WebsiteURL](../../Packages/AppFolderKit/Sources/AppFolderKit/WebsiteURL.swift)、[OpenWebsiteIntent](../../Packages/AppFolderKit/Sources/AppFolderKit/OpenWebsiteIntent.swift)、[WebsiteEditorView](../../AppFolder/WebsiteEditorView.swift) 已接入；零系统动作的网站分组有实际桌面运行证据。 | 输入、预览、导入不访问网址；浏览器／关联 App 由系统处理。此项与“接收网页分享”是两件事。 | 已覆盖 |
| F17 | 自动取得网站名称与站点图标（W3） | **已实现，界面验收进行中**。网站编辑器显式获取名称/图标并分别选择采用；临时独立会话、有界请求/跳转/解码、完整 HTML5 命名实体、PNG/JPEG/多尺寸 ICO。真实网络样例已覆盖名称、声明图标和站点 favicon 回退，输出图像已视检。 | 普通图标替换保留深色图标，名称/网址/图标一次入草稿历史，不改原始启动网址；输入、分享接收和备份导入仍不联网。已有独立资源与 v12 备份直接复用。政策/FAQ/上架草稿已同步，正式 Test App 已验证候选获取/分别采用、手工名称保留、改网址清旧候选、取消/重试和编辑取消；顶部提交受 noWindowsAvailable 限制，保存重开、撤销及已有深色图标保留的 UI 闭环仍待验收。最终共享测试 578 项与 Debug/Release 通过。 | P1：完成网站编辑界面闭环 |
| F18 | 网站指定浏览器／每站覆盖／内嵌浏览（W1/W3） | **部分实现，界面与系统交接验收进行中**。逐网站保存系统默认、App 内 Safari、Chrome、Firefox，或明确跟随本机 App 统一设置；旧网站保持原方式。默认直开，其他选择主屏/锁屏仅 ID 路由经宿主重读，统一偏好变化需重新确认。原生完整模态 Safari 已确认显示并在后台返回后保留；手动失败可显式使用系统默认。字段贯穿编辑/历史/复制/v14 备份，本机统一偏好不导出。 | Firefox 接收端可能重新编码 query；Edge 官方 HTTPS 说明有矛盾，未加入，自定义浏览器模板仍未实现。598 项/75 套核心测试通过，不能替代实际系统交接；编辑保存、Safari 关闭返回、主屏/锁屏实际点击、第三方浏览器接收、统一设置及 v14 界面继续验收。 | P1：完成运行验收；模板 P2 |
| F19 | 联系人：电话、短信、FaceTime、通信 App（W1/W2） | **单号码四操作已接入，446 项／55 套测试及最终 Debug／Release 构建通过，界面待验收**。[ContactTarget](../../Packages/AppFolderKit/Sources/AppFolderKit/ContactTarget.swift) 保存电话／短信／FaceTime 语音／视频及规范号码；[ContactEditorView](../../AppFolder/ContactEditorView.swift) 提供手填和系统单号码选择，无 `CNContactStore`／整个通讯录授权。[ContactLaunchRoute](../../Packages/AppFolderKit/Sources/AppFolderKit/ContactLaunchRoute.swift) 仅携带分组／节点 ID，宿主重读；主屏、锁屏、独立双外观图标和 v9 备份已接入。 | 电话依系统确认，短信仅进入编写；FaceTime 必须明确点开始，排队／过期／恢复请求不自动执行。导出提示含姓名号码，导入不通信。**FaceTime 邮箱、第三方通信 App 未覆盖**；本轮仅验证手动号码规范化、FT 视频预览、非法输入提示与取消不写组；尚未保存联系人，选择器／桌面点按／系统交接待验收，未发起通信。 | P1：验证已实现范围；其余通信类型保留 P2 |
| F20 | 自定义深链／按 App 标识导入／应用商店快捷入口（W2） | **未提供独立配置**。目录里的旧 scheme 是留档，不会由分组自动执行。 | 与普通系统动作及网站分开定义；先验证每类公开打开方式和失败反馈，不把任意 scheme 输入当成“万能零中转”。不存在自动恢复 opaque 系统动作的承诺。 | P3 |
| F21 | 日历图标显示当天日期（W2） | **已接入；渲染与合成文件夹封面 UI 已验证**。[CustomIcon](../../Packages/AppFolderKit/Sources/AppFolderKit/CustomIcon.swift) 独立日期类型只存样式与颜色，已有 calendar 符号保持静态。[DateIconContent](../../Packages/AppFolderKit/Sources/AppFolderKit/DateIconContent.swift) 按当前日历、时区与 locale 绘制及朗读；当前＋未来三个当地日界线共用 Calendar，每 entry 格式化一次。494 项／63 套及含隐私的最终 Debug／Release 通过、零编译警告或错误；正式 renderer 的 192 次绘制非空、96 组跨日像素均变化，96pt 视检未裁切。 | 合成文件夹封面已实测日期说明、取消、普通红／深色黑、完整日期 AX、Undo／Redo、保存及安装最终构建后重开；磁盘只存 date／空 value／颜色，原内部外观与 nine 保留。UI 结果不扩展到动作／联系人／网站。真实 WidgetKit 日界线、设置变化、Clear／色调、RSS 和 v11 备份往返待验收；系统决定刷新，不承诺午夜或未运行时的时区变化立即生效。 | 已接入；继续真实组件与备份验收 |
| F22 | 商店区域选择、图标匹配纠错（W2） | **地区选择与来源保存已实测，搜索输入待验收**。[AppStoreSearchRegion](../../Packages/AppFolderKit/Sources/AppFolderKit/AppStoreSearchRegion.swift) 提供 175 个商店地区及本地化名称／英文／代码搜索；[IconFixView](../../AppFolder/IconFixView.swift) 默认美国无结果再查中国大陆，手动选区只查单区，结果展示实际来源。选中的 ID＋地区进入匹配与 v10 备份，图标缓存按来源隔离；本机搜索偏好不导出。 | 不读取或更改账户地区、设备地区或真实启动动作。名单据两份 Apple 官方清单交叉校正 Niger／Nigeria，非全部 Locale 地理区域；6 项地区聚焦测试通过。日本／科索沃的 Pages Search 与 Lookup 各返回 200／1 条及对应地区链接，仅为有限 API 样例。最终完整 474 项／60 套测试（9.471 秒）及 Debug／Release 通过，无警告或错误；无障碍补丁后最终 Debug／Release 也通过。AU 来源／Apple Pty Limited、查询修改清旧结果／取消旧请求、Pages 保存重开 au＋361309726 及 44,356 字节缓存已实测；自动策略说明已确认，未声称空结果回退已实测。地区 sheet 搜索输入受工具限制待验收。 | P1：完成地区 sheet 搜索与 v10 往返验收 |

### 其他入口、资料库与跨设备

| ID | 需求／竞品证据 | AppFolder 当前状态及代码证据 | 仍欠缺的最小完整边界／限制 | 优先级 |
| --- | --- | --- | --- | --- |
| F23 | 锁屏圆形／矩形组件（W1/W2） | **已实现，锁屏交互待验收**。[独立 kind](../../AppFolderWidget/LockScreenLaunchWidget.swift) 支持圆形 1 个、矩形最多 2 个叶子；[组合 ID](../../Packages/AppFolderKit/Sources/AppFolderKit/LockScreenItemChoice.swift) 定位，分组路径与真实动作／网址区分同名项。网站／系统动作、缺项帮助、privacySensitive、双 kind 刷新、临时读失败重试及九语已接入。 | 373 项／43 套测试通过，包含教程末次文字调整的最终 Debug／Release 增量构建均成功，无警告或错误。simctl 帮助路由（非锁屏点按）及首页教程 AX 验证通过。`/tmp/appfolder-lockscreen-registration.log` 确认两 family 已注册、placeholder 各 1 entry 成功且缓存 enabled；真实钟下区域列表当前只见 6 个系统项，滚动受工具错误阻断，重启仍同。实际添加／点按／解锁尚待验收，不能推断 kind 未注册。 | P1：完成实际锁屏验收 |
| F24 | 灵动岛／锁屏实时活动快捷栏（W1/W2） | **未实现**。无 ActivityKit 生命周期、活动属性或动态岛视图。 | 与锁屏常驻组件分开。先定义有始有终的用户活动、启动／结束／失效恢复；不得暗示无限常驻。竞品重启自动化只证明其产品方案，不证明系统取消时限。 | P3 |
| F25 | App／文件夹通知圆点与计数（W1/W2） | **未实现**。无通知事件输入、计数仓库或对应自动化 Intent。 | 先核验用户可配置的公开事件来源；定义清零、过期、文件夹聚合与同步语义。自己 App 的通知授权不能读取其他 App 通知；计数若由自动化写入，应明确是该来源的记录，不冒充真实未读数。 | P3 |
| F26 | 标签、分类、归档、按分类批量添加（W2） | **模型、界面与 v12 备份已实现，主 App 批量加入已验收**。[资料模型](../../Packages/AppFolderKit/Sources/AppFolderKit/ActionLibrary.swift) 保存名称、标签与归档。已实测取消／顺序／一次撤销重做／保存重开及 199→200 容量边界；标签超限提示、合法输入恢复，以及候选消失后的标签／归档／恢复完整性保护也已验证。 | 编辑中保留本地草稿、批量目标快照、最终 CAS 和读取归属保护已接入。核心既有 555 项通过，最终两构建通过。标签完成与保存、手工记录、编辑中并发／失败恢复、归档分段筛选、嵌套目标及 v12 备份界面仍待验收。证据 /tmp/appfolder-f26-main-editor/ui-verification.json；原有分组保持不变。 | P1：完成 F26 剩余实际验收 |
| F27 | 导入已安装 App／从商店分享添加 App（W2） | **未覆盖自动安装列表导入**。现有候选来自已配置动作与本地图标记录；多选动作名称不能代选系统动作。 | 先区分“添加图标目录项”“添加网站商店链接”“取得可执行系统动作”。竞品宣称批量导入不能作为公开枚举权限证据；不要恢复私有安装探测，或默认要求用户提交整份设备分析日志。 | P3 |
| F28 | 全库备份、导入、单分组分享 | **已实现 v16，读取 v1–16**。[LibraryBackup](../../Packages/AppFolderKit/Sources/AppFolderKit/LibraryBackup.swift) 保留日期、来源地区、联系人、子文件夹外观、动作资料库与逐网站打开方式（含跟随 App 设置），v15 增加命名外观预设，v16 保存根组／递归子文件夹／预设中的精细外观；全库导出包含、单组分享不带预设库，同名本地预设保留；文件上限 32 MiB；全库包含手工与归档记录，单组只携带实际动作名关联的资料。图标与资料冲突独立处理，已有本地资料整条保留；预览后变化会在提交时重查。 | Unicode 等价名图标修复及 505 项／64 套属于 v11 历史验证；v12 资料库聚焦 116 项／13 套、既有共享核心 555 项／68 套通过。导入不通信，缓存、本机搜索地区及网站统一打开偏好不导出；pre-v12 拒绝资料库字段，pre-v13 拒绝网站打开方式字段（含显式默认/null）。照片补偿不是跨文件／崩溃原子事务。v13 拒绝跟随 App 设置等新枚举；v14 导入保留跟随选择并按目标设备统一偏好解析，核心测试覆盖。pre-v15 拒绝预设字段，预设按实际回执认领并条件回滚；pre-v16 拒绝五个精细外观字段的任何显式存在，v16 不为旧数据注入默认字段，新增备份聚焦 7 项通过。v10／v11／v12／v13／v14／v15／v16 界面往返仍待验收；iCloud Drive 文件位置不等于同步。 | 已覆盖；v10–v16 界面往返待验收 |
| F29 | 从浏览器接收网页分享（W2） | **已实现，输入端待验收**。独立 Share Extension 与 App「待添加网页」已接入；人工测试记录的多选、取消目的地、Undo/Redo、保存失败保留、清理忙重试与稳定 ID 防重复已实测。当前子文件夹选择取消→加入→撤销/重做→保存后消费也已通过；新增单项移除/最近一次撤销，含空列表、存储忙重试和其他消费者先移除的保护。 | Safari 分享面板已显示 AppFolder；仍需验证点击入口后显式保存到收件箱，不能标为端到端完成。App 内验证证据 `/tmp/appfolder-inbox-removal-probe/ui-verification.json`；原有 13 组未变、合成数据已清理。扩展只写独立收件箱，保存组后才消费，不读取正文或改写分组。 | P1：补齐 Safari 输入端验收；F23 已实现待验收 |
| F30 | iCloud 自动同步、跨设备恢复（W2） | **未实现自动同步**。[entitlements](../../Config/AppFolder.entitlements) 只有 App Group，未接 CloudKit；现有备份为手动文件操作。 | 先定版本兼容、账号切换、离线冲突、删除墓碑、资产传输／回收及超限行为；系统动作仍需在每台设备配置。备份格式能运输数据不代表同步冲突已解决。 | P2，独立项目阶段 |
| F31 | 原生 iPad、横向超大、跨平台适配（W1/W2） | **未完成原生适配**。[工程配置](../../AppFolder.xcodeproj/project.pbxproj) 的 App 和 widget `TARGETED_DEVICE_FAMILY = 1`；现有方向配置不等于 iPad 支持。 | 开启设备范围前补分栏／弹窗、键盘与横竖屏布局，测量 iPad 实际 widget family 和尺寸；横向超大与 iPhone 超大竖屏是两项不同几何。 | P2 |
| F32 | 更多语言、App 内语言选择（W1/W2） | **部分覆盖**。[Info.plist](../../Config/AppFolder-Info.plist) 声明简中源语言及九种译文；界面跟随系统，无独立语言设置。 | 按实际用户地区扩展；需覆盖 widget metadata、参数标题、动态插值、无障碍与教程，不能只增加 catalog 数量。 | P2 |
| F33 | iOS 18–26、Mac／Vision 的可用范围（W2） | **当前未覆盖**。App 与 widget 最低 iOS 27；package 的 macOS 声明用于本机测试，不是已发布 Mac App。 | 如扩展旧系统，要为系统动作建立明确受限体验或独立公开启动路线，并诚实区分是否经过宿主。原生平台适配另验，不把 lowered deployment target 当兼容完成。 | P3，产品范围决策 |

### 实现前必须保持的公开边界

1. **尺寸与交互要按当前文档核验。** 本机 iOS 27 SDK 已公开 `systemExtraLargePortrait`，专项 [API 页面](https://developer.apple.com/documentation/widgetkit/widgetfamily/systemextralargeportrait) 也列出 iOS 主屏；旧 HIG 表格／历史研究若仍写 iPhone 不支持，不能压过当前接口和实测。同样，当前 [组件深链接文档](https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity) 已把 `systemSmall` 列为可放多个 Link 的 family；不能沿用旧“只有一个 Link”假设。接口可用仍不等于 AppFolder 已完成布局或真实点击验收。
2. **锁屏与灵动岛分开验收。** [交互文档](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities) 明确圆形／矩形锁屏组件可用按钮，锁定时需要认证；`accessoryInline` 不能当多按钮条。新 kind 不能遗漏分组、图标、备份导入后的刷新，也不能把仅选中两项的成功状态冒充整组配置成功。[ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) 仍有 8 小时活动上限、最多额外 4 小时锁屏留存与载荷预算；[HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities) 要求围绕有起止的活动设计。
3. **联系人选择不需要整本通讯录授权。** [CNContactPickerViewController](https://developer.apple.com/documentation/contactsui/cncontactpickerviewcontroller) 可返回用户选中的资料快照。首版不必使用持续读取的 CNContactStore，也不必储存整张联系人卡片。但是 [OpenURLIntent](https://developer.apple.com/documentation/appintents/openurlintent) 的官方约束不能被解释成已支持 tel／sms 零中转；[UIApplication.open](https://developer.apple.com/documentation/uikit/uiapplication/open%28_%3Aoptions%3Acompletionhandler%3A%29) 是宿主内的公开打开途径，[电话链接](https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/PhoneLinks/PhoneLinks.html) 还有系统拨号确认。竞品宣称联系人直开，不证明其调用方式。
4. **通知输入必须有来源。** [UNUserNotificationCenter 的 delivered notifications](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getdeliverednotifications%28completionhandler%3A%29) 面向调用者自己的 App。不能申请 AppFolder 通知权限后声称可以获得其他 App 的红点；若采用用户主动配置的快捷指令自动化，要先取得当前系统可运行的公开证据，再说明计数的准确范围。
5. **分享扩展先保持单写入者。** [扩展激活规则](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/AppExtensionKeys.html) 可以限定一个网页 URL；无需抓取页面、注入 JavaScript 或读取剪贴板。[NSExtensionContext.open](https://developer.apple.com/documentation/foundation/nsextensioncontext/open%28_%3Acompletionhandler%3A%29) 的支持由扩展点决定，不能依赖 Share 扩展强行拉起宿主。当前 [FolderCoverAssetCoordinator](../../Packages/AppFolderKit/Sources/AppFolderKit/FolderCoverAssets.swift) 是进程内锁与 lease，[FolderCoverEditSession](../../Packages/AppFolderKit/Sources/AppFolderKit/FolderCoverEditSession.swift) 的暂存清理也按进程内活跃记录判断；扩展创建会话可能误清理 App 草稿。独立 UUID 收件箱避免改写同一分组；直接追加旧分组则需要先完成跨进程协调、编辑 revision 冲突处理和资源生命周期改造。
6. **新的高密度或内容字段要把整个数据链路做完。** 新布局同时更新默认布局、保存分组、预览、导航 key 和点按区域；77 格不能继续无区别保留两份 256px 图片。新联系人、日期图标、子文件夹外观或浏览器字段都需要校验、复制、undo、revision、备份版本及旧版拒绝规则；源图片仍存独立资源，不进入 GroupItem／50 步编辑历史。云同步还需解决多写入者冲突，不能只把现有 JSON 放进云盘。

### 建议交付顺序与完成定义

优先完成已接入的 **F21 日期图标的真实组件日界线、设置变化与运行内存验收**，以及 **F04/F05 超大竖屏与新密度桌面验收、F23 锁屏实际交互验收、F29 Safari 输入端验收**；App 内预览与核心测试不能替代这些入口的真实点按。F14 已打开文件选择器，后续选图／裁剪／保存和云端下载待验收；F07 App 内独立／跟随外观与 mini 设置已补验，真实组件和跨容量返回仍待验收。F19 已选择经宿主处理的单号码四操作路径，先验收选择、确认和系统交接，再扩展 FaceTime 邮箱或第三方通信 App；F13 分类／选择／取消／双侧保存、F22 选区／来源保存已实测，两种 sheet 搜索输入及来源地区／日期样式备份的界面往返（v10／v11／v12）仍待验收；F26 已接入并进入真实资料库界面验收；F17 已接入显式网站信息获取并通过真实网络样例，编辑界面闭环继续验收；F15 图标主题仍属后续图标迭代。F30/F31 跨设备工作需独立设计数据一致性；F24/F25/F27/F33 先取得机制证据，不从待办表删除。

每次完成一项应更新对应 F 编号的“源码状态、备份兼容、实际验证范围、尚余限制”，而不是只追加测试总数。已实现的网站、分组分享、普通／深色图标、文件夹封面、四种主屏尺寸与密度不能重新变成开发待办；尚未完成的桌面／锁屏／分享输入端验收、联系人与同步仍需明确保留。广告、追踪及订阅本身不作为需要复制的功能欠账，商业化另作产品决定。

---


## 历史调研原文（2026-09-26，以下保留原结论与推测）

> 调研日期：2026-09-26。数据来自 iTunes Lookup API、App Store 页面、widgetloft.app 官网与其隐私政策。

> 历史调研记录：以下版本、价格与实现难度评估是当时的快照，不能作为当前产品或 Apple API 的确认结论。AppFolder 目前已实现分组、嵌套文件夹、四宫格/九宫格分页、自定义图标、备份恢复及配置检查；实际交付与验证范围见 [README](../../README.md)。

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

**当时的判断（网格限制已被后续实现推翻）**：用户得自己在小组件配置界面里挑，我们拿不到任何可编程的目标列表；因此当时误判它撑不起「9 个格子的文件夹」，只适合单个直开图块。

> 当前实现校正（2026-10-29）：AppFolder 在系统配置中接收多个 `SystemShortcut`，由系统持有动作引用，再将各个按钮交给公开的 `RunSystemShortcutIntent` 执行。动作不透明限制了枚举和程序化指定目标，并不限制把多个用户已配置动作排成网格。当前小号 4/9 格、中号 10 格、大号 16 格的已保存分组已有实际桌面验证，具体范围见 [README](../../README.md)。

### 三个机制的选择逻辑（历史评估，不再用于当前实现）

| | 中转 | 通用链接 | 系统代持 |
|---|---|---|---|
| 生效 iOS | 18+ | 18.1+ | **27+** |
| 有闪烁 | **有** | 无 | 无 |
| 任意 App | ✅ | ❌ 需支持通用链接 | ✅ |
| 能撑网格 | ✅ | ✅ | 当时误判为 ❌；当前已验证可配置多个动作组成网格 |
| 失败可见 | ✅ | ❌ 静默 | ❌ 静默 |

**历史方案（现已废弃）**：当时的结论是“三条路都要做，按目标 URL 的形态自动分派”，并据此设计 `LaunchStrategy`。当前 App 动作只采用 `RunSystemShortcutIntent`，旧三路自动分派不再是仓库实现。新增网站格子使用独立的 `OpenWebsiteIntent` 打开用户保存的 HTTP(S) 网址，不承担已安装 App 的名称匹配或三路回退。

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
