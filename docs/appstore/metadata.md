# App Store Connect 文案（可直接粘贴）

公开站点已发布（2026-10-30）：经用户确认，首页、支持页、隐私页已作为提交 `e541de294ce8a3075613127ded85de09b88aeee8` 推送至 `lvyufeng/appfolder-site/main`；GitHub Pages 构建 `1325646339` 已成功。三个公开 HTTPS 页面均返回 200，原始内容与已核对的三份 HTML 逐字节一致，支持页的隐私链接已实际点开验证；隐私正文与 App 内版本一致。发布前完成 390px 手机宽度与桌面预览、18 个项目路径内链接／锚点检查。线上地址为 `https://lvyufeng.github.io/appfolder-site/`、`support.html` 与 `privacy.html`，证据位于 `build/AppStore/website-preview/`。另外已从同一 `1.0 (2)` 归档准备开发签名真机演示副本 `build/DeviceReview/1.0-2/AppFolder.app`，三个可执行文件与商店候选的归档符号 UUID 一致，描述文件均包含目标 iPhone；本轮未安装或录制真机。实际界面验收重新检查时，工具仍提示 Mac 锁定，尚未完成。

发行归档检查（2026-10-30）：已生成并校验 App Store 候选 IPA `1.0 (2)`，位于 `build/AppStore/1.0-2/AppFolder.ipa`；对应归档位于 `/Users/lvyufeng/Library/Developer/Xcode/Archives/2026-10-30/AppFolder Store Candidate Build 2.xcarchive`。主 App、Widget、Share 三个 target 均为 App Store 分发签名、调试权限关闭、App Group 一致；严格签名、描述文件、三份 dSYM UUID、隐私政策／清单及 30 份编译翻译文件已校对。Archive 与 Export 均成功，Archive 零警告／零错误。分享扩展的 App Store 描述文件已通过开发者后台创建并下载，先前缺失项已解决；命令行账号读取问题通过三份明确匹配的描述文件手动导出绕过。后台仅有 `1.0 (1)`，因此项目六份配置的构建号统一改为 2；其他编译输入未改。尚未上传 IPA、修改 App Store Connect 文案、回复审核或提交；本地打包通过不代表玻璃未公开 API 合规或实际 UI 验收完成。证据位于 `/tmp/appfolder-store-validation/`，主要校验记录也随候选 IPA 保存。

实际审核来源已核实：App Store Connect 的 2026-10-14 提交仍因 2.1 信息不足处于问题未解决状态。Apple 明确要求最新系统的真机录屏，从启动 App 开始展示典型流程，并提供目的／受众、设置访问方式、外部服务、地区差异及受监管服务／受保护素材说明。下方审核备注已补明确受众和地区一致性，3925 字节；真机视频仍未完成。该反馈没有列出 2.5.1，未公开玻璃 API 是我们另外发现的合规问题，不能将这次信息补充要求描述成 Apple 已因该接口拒审。当前账号页面还提示需确认更新后的 Paid Applications Schedule，以及在欧盟分发前提供交易商状态；未代为接受其他协议或选择身份。线上版本仍显示旧文案与既有截图，需在候选版本验收后更新并复核尺寸来源；尚未改动。

上架收尾（2026-10-30）：以下市场与审核字段已按当前 v16 候选源码同步，限定 App 动作的直开范围，补充联系人、外观预设、精细外观、超大竖屏及锁屏入口。网站仓库 `/Users/lvyufeng/Projects/appfolder-site` 的首页、支持页及隐私页修订已发布，站内链接使用相对路径，线上隐私正文与 App 内版本一致。提交前仍需核对具体候选构建、下述实际流程和 App Store Connect 字段；独立玻璃的未公开接口问题未解决。

支持 URL：https://lvyufeng.github.io/appfolder-site/support.html

隐私 URL：https://lvyufeng.github.io/appfolder-site/privacy.html

网站已部署，这两个地址及相互链接已验证。商店 App Preview 视频可选，具体审核要求另以 Apple 原文为准。

内部验收注记（2026-10-30）：精细外观已实现可选图标间距、四周边距、名称颜色和描边，命名预设同步携带；当前完整备份与单组分享写 v16／读 v1–16，单组分享不带全局预设库，旧版本拒绝新增精细外观字段，未设置字段不注入默认值。共享核心 672 项／85 套通过，36 组默认布局各 11 字段及 16 项默认标题像素对比保持一致；模拟器 Debug 与 iPhone Release 均零警告／零错误构建通过，19,682 项编译翻译资源比对无差异。该轮 Test 模拟器安装启动已核对，原有 13 组未变；实际精细外观控件、颜色选择生命周期、预设复用、保存／撤销、v16 备份界面及真实 WidgetKit 显示仍待验收。证据见 `/tmp/appfolder-fine-appearance-validation/` 下测试、构建、资源及安装验证记录。默认主屏独立玻璃与纯图标布局继续保留，App Store 兼容性仍未解决；本段仅更新内部验收状态，对外市场字段未修改。

此前命名外观预设轮次已接入保存、搜索、复用、改名、更新、移除及条件撤销，该轮完整备份写 v15／读 v1–15。共享核心 642 项／80 套与 Debug／Release 构建通过；该轮预设与 v15 备份界面闭环未完成，既有待验收范围保留。

> 当前提交状态（2026-10-29）：为纠正未经确认的功能回退，工作版本已恢复默认主屏独立玻璃及其原有未公开接口。App Store 接口兼容性尚未解决，本文件的文案准备、历史构建通过及历史公开 API 检查均不代表当前产物可提交。下方本地草稿仅同步网站打开与隐私、备份事实，尚未发布。

此前 F26 开发版本新增本地动作资料库：名称、标签、归档和按标签批量选择；整理显式保存，归档不删除分组或图标。备份写 v12、读 v1–12，完整备份含未引用与归档资料，单组分享只包含实际动作引用；已有同名资料保留，冲突独立于图标判断。核心及构建通过，真实管理／选择／v12 备份界面验收仍待完成；以下 F21 的 v11 记录仅是该轮历史状态。未将这些开发状态写入对外商店字段。

当前 F18 为每个网站保存打开方式：系统默认、App 内浏览、Chrome、Firefox 或跟随 App 设置。本机统一打开偏好只影响明确选择跟随的网站；旧网站和新建网站默认仍由系统直接打开，其他选择通过 AppFolder 交接。该轮备份写 v14、兼容读 v1–14，保留每网站跟随选择但不导出本机统一偏好，导入后按目标设备设置打开。选择方式和导入不联网、不改写保存的网址。这些本地草稿事实不代表浏览器交接已完成界面验收或当前产物已可提交。

各字段按 Apple 规定分别标注字符或字节上限。**名称、副标题、关键词**三处一起决定搜索曝光，
所以关键词里不要重复名称里已有的词。

名称与副标题最多 30 字符，推广文本 170 字符，描述 4000 字符；关键词最多 100 字节，审核备注最多 4000 字节。见 [App 信息](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/)与[平台版本信息](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)。

本轮 F21 已接入本地动态日期样式，可用于动作、联系人、网站与文件夹封面的普通／深色图标；只保存日期类型与颜色，不固定当天日期、locale、时区或 PNG，不读取日历事件／申请日历权限。日期按当前设备日历、时区与语言地区设置显示；主屏与锁屏准备当前及未来三个当地日界线条目，同一 Calendar 用于绘制与排程、每 entry 只格式化一次。请求刷新取下一日界线和必要的 15 分钟恢复重试中较早值，最终由系统安排，不承诺午夜准点；App 前台、显著时间、时区与 locale 通知刷新两种组件和 App 预览，App 未运行时的时区变化不保证立即生效。备份写 v11、读 v1–11，日期配置不计照片，旧 calendar 符号不迁移。

F21 完整共享测试 **494 项／63 套**通过，10.981 秒（`/tmp/appfolder-date-full-tests.log`）；包含隐私说明的最终 Debug／Release 均成功、零编译警告或错误（`/tmp/appfolder-date-final-debug.log:240`、`/tmp/appfolder-date-final-release.log:92`）。真实 iOS 探针直接使用正式 AppFolderKit／CustomIconArtwork，覆盖多语言、非公历、闰月及 12／24／48／96pt，192 次绘制非空、96 组跨日像素对比全部变化，96pt 视检未裁切（`/tmp/appfolder-date-probe/date-render-results.json`）；不是 WidgetKit 宿主，不代表跨午夜投递、Clear 或 RSS 验收。

F21 真实 App UI 仅覆盖独立 Test 的合成文件夹封面：日期模式显示当时完整日期「2026年10月29日星期四」；取消后 Undo 不可用且重开仍是原 mini。普通红色日期／深色黑色日期应用后，预览文件夹 AX value 为完整日期；Undo 恢复 mini 并清日期 value，Redo 恢复。保存、结束进程、安装最终构建并重开后两侧保留，原内部外观与 nine 不变；两个独立资源仅含日期类型、空 value、颜色，无日期快照（`/tmp/appfolder-date-ui-saved.json`）。不扩展为动作／联系人／网站日期图块 UI 已通过。真实 WidgetKit 日界线、设置变化、Clear／色调模式、RSS 与 v11 备份界面往返，以及以下旧待办继续保留。对外商店字段与审核备注未修改。

此前已接入 175 个 App Store 地区的选择与本地名称／英文／代码搜索；默认明确为美国无结果再查中国大陆，手动选区不跨区回退。结果显示实际来源，匹配保存 ID＋地区，缓存按来源隔离，备份写 v10、读 v1–10；搜索偏好仅保存在本机，不导出，不读取或更改 Apple 账户地区及启动动作。地区目录 6 项／1 套聚焦测试通过（`/tmp/appfolder-regions-tests.log`），最终完整共享测试 **474 项／60 套**通过，9.471 秒（`/tmp/appfolder-regions-final-tests.log`）；模拟器 Debug／iPhone Release 均构建成功；补充按钮无障碍特征后的最终增量构建同样成功，无警告或错误（`/tmp/appfolder-region-accessibility-debug.log`、`/tmp/appfolder-region-accessibility-release.log`），已安装到 Test。隐私网页、内置源文件及两份产物 HTML 字节一致。日本与科索沃的 Pages Search／Lookup 公开样例均为 200／1 条并返回各自地区链接和货币（`/tmp/appfolder-storefront-api-verification.json`），不代表 175 个地区全量实测；Mac 已解锁，F22 已实测澳大利亚来源／开发者显示、修改关键词立即清除旧结果并取消旧请求、保存 Pages 与重开来源保持；落盘为 `country=au`／`id=361309726`，缓存 44,356 字节。自动选项的 US→CN 说明已确认，未声称空结果网络回退已实测。名单依据 Apple 地区表与服务可用性清单交叉核对，保留分开的 Niger／Nigeria（ne／ng），不使用所有 ISO 地理区域。商店字段与审核备注未修改。

本轮补验：F13「购物与财务」分类、`banknote.fill` 选择、取消保留草稿，以及普通蓝纸币／深色黑爱心分别保存重开通过。F07 合成空文件夹已验证改 3×3 mini 不开启独立外观、隐藏标题自动独立、转向返回样式、保存重开、改回跟随及撤销，mini 在恢复跟随后仍保留 nine；真实组件及跨容量返回待验收。F19 仅验证手动号码规范化、FaceTime 视频预览、非法输入提示和取消不写组，未保存联系人或发起通信。F14 已打开系统文件选择器，尚未选图／裁剪。两种选择 sheet 的搜索框和 Files 提供商页面缺少 Device Hub AX 内容，坐标操作报 `noWindowsAvailable`；搜索输入、Files 后续流程、联系人保存／启动及其他旧待验收项保留，不将工具边界视为产品故障。v10 备份界面往返仍待验收。

此前符号轮次的选择器扩展为 150 项、10 个分类，保留原 70 项与原名，提供当前语言名称／分类、中英文关键词及 SF 原名的本地搜索；独立选择页面只改打开时的普通或深色草稿，取消不保存。元数据不进入图标编码或资源标识，该轮备份仍写 v9、读 v1–9，旧版不保证能读取新增符号。iOS 27 已通过 150 个 UIImage 取图及 12／24／48／96pt 共 600 次实际 SwiftUI monochrome／semibold 绘制检查，无空图，联系表已视检（`/tmp/appfolder-symbol-probe/symbol-render-results.json`）。完整共享测试 **452 项／56 套**通过，10.560 秒（`/tmp/appfolder-symbols-final-tests.log`）；最终 Debug／Release 均构建成功，无警告或错误（`/tmp/appfolder-symbols-final-debug.log`、`/tmp/appfolder-symbols-final-release.log`）。两个产物的 10 个语言目录均通过 160 个目录／分类键检查，零缺失，简中和九语译文已实际打包。分类／选择／取消及双侧保存重开已在本轮补验，**sheet 搜索输入仍待实际验收**；现有 UI／系统交接待验收范围保持，商店字段未修改。

此前联系人轮次已接入单号码联系人图块：电话、短信、FaceTime 语音／视频四操作，可手填或由系统联系人选择器返回所选姓名与单个号码，不读取整个通讯录或联系人照片；节点独立保存普通／深色图标。主屏与锁屏通过 ID-only 路由进入 AppFolder，电话依系统确认、短信仅编写；FaceTime 必须在 App 内点开始，排队／过期／恢复请求不自动执行。该轮备份写 v9、读 v1–9，并明确导出／分享包含姓名和号码，导入不通信。FaceTime 邮箱、第三方通信 App 未覆盖。完整共享测试 **446 项／55 套**通过，11.664 秒（`/tmp/appfolder-contacts-final-tests.log`），包含通信启动 Guard 的一次性执行与生命周期保护；最终模拟器 Debug 与 iPhone Release 构建均成功，无警告或错误（`/tmp/appfolder-contacts-final-debug.log`、`/tmp/appfolder-contacts-final-release.log`）；本轮仅补验手动草稿，**联系人保存／选择器与系统交接未验收**；当轮曾受 Mac 锁屏阻塞，当前实际 UI 验收进行中，既有待验收范围保留。商店字段未扩写。

此前子文件夹外观轮次已实现：未设置时继承最近祖先的完整外观，首次实改生成独立设置；返回按钮可选三种样式，文件夹内容缩略图可独立选择 4／9 项。关闭「使用分组外观」只停用树内外观覆盖，文件夹封面和自身缩略图网格仍显示。该轮备份写 v8、读 v1–8。完整共享测试 **420 项／50 套**通过，10.662 秒（`/tmp/appfolder-folder-style-full-tests.log`）；最终模拟器 Debug／iPhone Release 构建均成功，无警告或错误（`/tmp/appfolder-folder-style-final-debug.log`、`/tmp/appfolder-folder-style-final-release.log`）。该轮因 Mac 锁屏未验收；本轮已补验上述 App 内独立／继承设置，真实组件与跨容量返回待验收；既有 Files／云端、新密度桌面、锁屏与 Safari 输入端待验收项继续保留。以下记录为历史轮次，商店字段未扩写。

此前 Files 轮次已接入从 Files 选择单张 PNG／JPEG／HEIC／HEIF 图片，复用动作图标、网站图标及文件夹封面的普通／深色草稿和裁剪流程。只读用户选择的文件，按内容校验格式并限制字节／像素，失败或取消保留旧草稿；云端位置可能由系统或服务提供商下载，源 URL、持续授权和原文件不长期保留，也不上传给开发者。完整共享测试 **406 项／48 套**通过，用时 9.649 秒（`/tmp/appfolder-files-full-tests.log`）；已补同侧跨来源晚回调保护，并将 Files 选项限制为四种支持格式。最终模拟器 Debug／iPhone Release 构建均成功，无警告或错误（`/tmp/appfolder-files-final-debug.log`、`/tmp/appfolder-files-final-release.log`）；当轮因 Mac 锁屏未验收；本轮已打开选择器，实际 Files 选图、裁剪、取消、保存及云端下载仍待验收，既有桌面新密度／锁屏／Safari 输入端待验收项继续保留。以下构建和测试总数均属于此前轮次。

此前密度轮次的竖向超大主屏组件和三档布局密度已实现，备份 writer 升为 v7、兼容 reader v1–7。最终模拟器 Debug／iPhone Release 构建均成功且无警告或错误（`/tmp/appfolder-density-final-debug.log`、`/tmp/appfolder-density-final-release.log`）；完整 **389 项／46 套**共享测试通过，11.017 秒（`/tmp/appfolder-density-full-tests.log`）。77 个不同图标的双外观共 154 幅照片解码像素低于 6 MiB，仅证明像素预算，不等于实际扩展 RSS 验收。

App 内人工分组已验证中号 10→8→21 格及撤销／重做、大号 49 格、竖屏 77 格、末页 78／79／80 与跨尺寸文件夹返回；小号仍为九宫格且不显示密度控件。中号 21 格和竖屏 77 格截图无标题重叠，保存后密度与 80 个根项目保留，原有分组／封面资源 SHA 未变。竖屏预览参考 Test 模拟器实测 349.6667 × 565.6667 pt。**新尺寸／密度的真实主屏点按及运行内存仍待验收**，锁屏真实点按和 Safari 分享输入端待验收状态也不变。以下数字与 v5／v6 文件记录属于各自历史轮次；商店字段暂保留上一轮已核长度文案，尚未同步本轮扩展范围。

此前锁屏轮次已实现：独立 kind，圆形 1 项／矩形最多 2 项，以分组与节点组合 ID 选择项目，复用系统动作和网站执行，并提供锁屏专属帮助。共享测试 **373 项、43 套**通过（`/tmp/appfolder-lockscreen-full-tests.log`）；教程第 3 步改为「选择启动项目」后的最终 Debug／Release 增量构建均成功，无警告或错误。帮助路由经 simctl openurl、首页教程经真实 AX 验证；日志已确认两 family 注册、占位加载及缓存启用。实际钟下添加列表当前仅见 6 项系统组件，滚动受 `noWindowsAvailable` 阻断，重启后仍同，因此实际锁屏添加与点按尚未验收，不能推断未注册。Safari 扩展输入端仍待验收，以下保留先前的精确运行范围。

此前收件箱轮次已接入未配置图块的帮助入口、独立网页 Share Extension 和「待添加网页」界面。最终共享测试通过 **364 项、42 套**（`/tmp/appfolder-inbox-final-all-tests.log`），完整模拟器 Debug 与 iPhone Release 构建均成功，无警告或错误。收件箱核心的 18 项、2 套测试覆盖跨进程锁、并发容量、稳定记录标识、重复加入与 Undo 后最终树的消费交集；单分组读取状态新增 7 项回归，相关聚焦共 19 项、3 套，确认读取某一缺失分组不受其他坏分组影响。

配置帮助已在正式小号桌面验证冷启动与热启动：点击缺失「日历」的格子，显示该动作的具体名称和系统配置步骤。网站编辑 sheet 曾遮住帮助页，现通过 UIKit 当前最上层 presenter 呈现；关闭帮助后，网站标题「Web」和父分组「Keep」草稿均保留，取消测试没有写入分组。网站按钮仍正常进入 Safari。帮助使用本地 `appfolder://` 的只读标识路由，不执行或修改系统动作；已配置动作原有的系统直开路径保持不变。

网页分享接收仍待输入端界面验收：真实 Safari 分享面板已出现 AppFolder，但「点击 AppFolder → 扩展中显式保存」尚未实际跑通，不能声称完整端到端已验证。当时 CUA 坐标点击持续报告 `noWindowsAvailable`；此前验证时只读系统状态为 `IOConsoleLocked=false`，当时 Mac 未锁屏，属于点击工具的窗口定位问题，AX 按钮仍可使用。

随后通过 AX 按钮，使用独立模拟器人工建立的两条测试记录完成 App 内闭环，未将其冒充 Safari 真实接收：空列表与首页 0 计数、全选两条后取消目的地保留选择均通过；新建测试组批量加入后，一次 Undo 移除两项，保存空组仍保留两条待添加记录。再次选择该组，Undo/Redo 能恢复整批。仅对新测试组临时注入写失败时，界面提示保存失败，草稿和两条记录均保留，随后恢复原空组文件；子进程暂持收件箱锁时，分组仍成功保存两节点并正常退出，界面提示两条未清理、旧列表暂不可添加。释放锁后重新读取并选择同组，没有重复插入，仍为两节点且 Undo 禁用；再次保存后待添加计数归零，节点 UUID 保持，原有 14 份文件的 SHA 全部未变。故障目录及备份已撤除，测试锁已释放。证据见 `/tmp/appfolder-inbox-ui-verified.json` 与 `appfolder-inbox-save-complete.png`。当前文件夹加入与取消仍未实际完成 UI 验证，核心已覆盖目标路径。以下网站、单分组导出分享及早期测试数量均作为历史运行记录保留。

此前网站格子与单分组分享已接入正式 App/Widget 源码。完整共享测试已通过 331 项、38 套，覆盖分组读取状态、网站模型与网址校验、单分组导出、v6 备份及既有共享逻辑；正式源码的模拟器 Debug 与 iPhone Release 均构建成功，App 与扩展的两种构建 metadata 均包含正式 `OpenWebsiteIntent`，不含 Probe。第二轮 Debug/Release 也已构建成功；双击防重已正式复验，相同双击只新增 1 个节点，一次撤销还原。分享摘要的 VStack 方案实测仍压住状态栏，已改为 UIKit 直接呈现原生分享面板，说明移至分组列表底部，并在完成或取消时显式清理临时文件；第三轮 Debug/Release 构建及正式复验均已通过，分享面板只呈现一次，安全区正常、无状态栏重叠；取消返回列表并清理本次临时目录。以下 302 项、32 套与旧构建记录属于更早一轮。

分组读取状态现区分空库、部分记录无法读取、目录失败与容器不可用；保留可读项，目录失败时提示上次列表可能过时，提供重试和备份恢复，不删除坏文件。12 项聚焦测试、2 套及相关 Debug/Release 构建通过，构建无警告或错误。正式 AppFolder Test 界面验证：仅新增 1 份自造坏 JSON 后显示读取失败和现有组；重试保留坏文件字节，恢复入口进入既有备份界面；移除测试文件后重试清除警告，10 份原分组 SHA 不变。最后的提示标题无障碍标识调整已完成；同一份最终源码的 Debug/Release 构建均通过，无警告或错误，两种构建的 App 与扩展 metadata 均复核包含正式 `OpenWebsiteIntent`，不含 Probe。

正式 App 界面已验证：无效网址保留原文且禁用添加，`example.com` 自动补全 HTTPS；编辑标题与网址保持节点 UUID，添加和编辑可撤销、重做，网站独立紫色书本符号图标保存成功。网站功能加入前的 11 份既有文件 SHA 核对仍全部相同。单分组分享经系统「存储到文件」生成 599 字节 v6 文件，仅含 1 组、1 份网站图标资源、0 个动作图标和 0 条手动匹配。导入预览显示新增 1 组、复用 1 份资源；确认后副本分组 ID 和节点 ID 均改变，网址及资源标识相同，核对的原有文件 SHA 未变。本次覆盖本机已有资源复用，不作为新设备缺资源写入的运行验证。

最终原生分享面板再次将纯网站恢复副本存入「文件」，成功生成 609 字节 v6 文件（副本名称更长），保存文件 SHA 与分享时的临时文件相同，完成后本次临时目录已清理；取消与完成均未改动旧历史测试目录。

正式小号桌面已验证：系统「动作」列表清空、选中网站验证组后，点击网站图块成功进入 Safari 加载 example.org。运行日志确认正式 `OpenWebsiteIntent`、`openAppWhenRun:NO`，以及 chronod 接收并选择正式扩展。混合测试将同一网站移入「Sites」文件夹并加入日历动作；桌面缩略图包含网站，原地展开后日历未配置但网站仍成功打开。此前临时 wrapper 打开 example.com 只作为早期执行路径探针；本次正式验证不扩展到其他尺寸及全部外观组合。

此前已在独立模拟器的实际桌面小号组件中验证：系统「分组布局」列出已保存的「日常」分组，配置地图、日历、提醒事项后，能进入「工作 → 出行」两级文件夹并返回；未配置的天气显示警告，不会运行动作；自定义符号与照片均正确显示在缩略图和完整格子。照片以生成的测试图完成选择、120% 缩放、右下微调、保存与重启恢复。10 项九宫格布局可往返翻页，第二页仍正确直开日历，地图格正确直开地图。四宫格也已在实际桌面验证 10 项三页、空位、文件夹返回与日历直接启动。以上为模拟器桌面交互验证，不是 App 内预览。同名冲突也已验证：重复地图配置显示警告且点击不运行，App 内显示冲突；恢复配置后重新匹配。

中号、大号已保存分组的实际桌面主要路径也已通过独立模拟器验证：开启名称的 21 项布局在中号按 5 × 2 分三页，末页仅一项时网格稳定；从中号第二页切换到大号后从 1/2 开始，按 4 × 4 分为 16 项和 5 项两页，空位保留。第二页文件夹格边缘点击可进入，大号还能继续展开下一层，逐层返回后保持第二页。中号日历格、大号地图格的左侧空白边缘点击均成功直接打开对应系统 App；两种尺寸的配置检查报告均显示三个动作就绪。中号系统配置正确隐藏小号专用网格选项。验证范围不包含所有图标尺寸组合或中、大号默认溢出布局的实际运行。

已撤销的历史版本曾移除未公开的背景接口及 SDK overlay；当前已恢复默认主屏独立玻璃，上架兼容性仍未解决。以下仅记录当时版本的验证：小号组件默认、深色和透明外观已实测，透明模式不再把照片和白色符号变成纯白块。包含编辑历史、分组外观、显示昵称与绑定分离、旧分组和备份兼容、中号/大号几何、共享缩略图遍历、备份恢复与配置检查在内，302 项共享测试、32 套测试全部通过；包含独立普通/深色图标、文件夹封面、备份 v5、分组外观、编辑历史及确认退出修复的模拟器 Debug 与 iPhone Release 构建成功，无编译警告或错误。测试日志另有旧测试的冗余 `#require` 提示。小号桌面导航、分页及直开已录制为模拟器功能验证素材，尚未作为商店预览或审核视频提交。

备份恢复与配置诊断已实现。此前不含文件夹封面资源的备份已在模拟器验证导出、预览取消、确认导入与从「文件」App 打开；v5 含封面备份已实测本地导出及已有资源复用导入：14,199 字节、4 个分组、两份封面资源（一张照片、一个符号）；预览显示新增封面 0、复用 2，并提示包含照片。确认导入新增 4 组，原分组文件逐字节不变；副本树含封面引用，除节点 UUID 外逐字段一致，所有节点 UUID 互不冲突，资源仍为两份。此界面验证覆盖本机资源复用路径；新设备缺资源写入由核心测试覆盖，尚未做相应界面验证。恢复后原分组保留，新增独立副本；已有同名图标与匹配保留。批量添加已验证多选、手动名称去重、取消不写入及保存后顺序保持。配置检查只保留最近最多 24 份本地刷新报告，按分组、布局版本和配置区分，不保存系统动作对象、不作为桌面实例清单，也不进入备份。

昵称编辑与旧数据兼容已实现；模拟器已验证编辑、错误保留、保存重开及实际桌面显示。首次配置已在全新模拟器验证空状态引导、选择内容保留与保存后的指定分组配置入口。系统组件搜索需搜 AppFolder，再选择“直接启动”，教程与以下文案已同步修正。昵称直开已补测：“出行”打开地图，“日程”打开日历。新增动作回流已实测通过：已打开的选择器先选「地图」并搜索「设」，初始无匹配；到系统组件配置打开「设置」App 的动作并保存，再返回原选择器，无需手动刷新即出现「设置」。搜索词、本次「地图」选择和「添加 1 个动作」按钮均保留。本次未实际添加或保存分组，不作为新增动作顺序的运行验证。

该轮备份写入 v10、兼容读取 v1–v10，保存手动图标匹配来源地区、分组与子文件夹外观、布局密度、返回按钮样式、内容缩略图网格、联系人姓名与单号码及操作、普通/深色图标、网站网址及去重后的封面、联系人和网站图标资源；旧文件的单份图标作为普通图标恢复。单分组分享只包含所选已保存分组、关联的动作图标和手动匹配及该组引用的资源，不含其他分组、编辑历史或检查报告；用户在系统分享面板选择目的地，接收后仍需预览确认导入。网站仅允许 HTTP(S)，点击才请求系统打开；不需要额外系统动作，默认地球图标，可为每格单独设置普通/深色图标，文件夹 mini 支持动作与网站混排。网站编辑、单组分享导入及小号网站直开、混合文件夹已验证的范围见上文，最终原生分享弹窗构建与复验也已通过。

此前独立模拟器已验证外观折叠、取消恢复、保存重开和自定义颜色；保存后未启用新开关的已有桌面组件保留原外观。新开关默认关闭；系统面板实测将 Actions 区域独立置顶，分组与开关位于普通外观设置之前。9 个配置分支与 36 种条件组合已通过构建产物检查。本轮已在实际桌面验证开关双向切换：新小号组件选择 21 项多尺寸分组，开启后为紫色渐变、四宫格、1/6 页，关闭后恢复组件自身的自动底板、九宫格、1/3 页；无需改动 QuickLaunch 配置模型。

普通/深色独立图标已实现：普通可以保持自动图标，仅覆盖深色；未单独设置深色时跟随普通。两侧草稿保留各自照片与裁剪，保存另一侧不会重新编码未编辑照片。选择 App Store 图标只替换普通图标，保留深色设置；全部恢复才清除两侧自定义。分组缩略图分别使用 32px 图片，避免双份全尺寸照片增加小组件内存。本轮已在 App 内为日历新增靛色月亮深色图标，并逐字段核对普通照片对象及 PNG 数据未变；提醒事项仅保存黑底闪电深色图标，没有普通图标字段，之后选择 App Store 的 Reminders 仍保留该深色设置。切换系统深色后，App 列表及实际小号、大号桌面组件均显示对应月亮/闪电，小号文件夹缩略图也显示月亮。桌面为系统「透明」玻璃样式，符号显示白色符合该样式。点击深色月亮已确认直接打开系统日历。将模拟器切为 Light 并将主屏设为「默认」后，小号、大号组件中的日历恢复原四色照片、提醒事项恢复所选 Apple 商店图标，文件夹缩略图也恢复照片。保持整体 Light，将主屏自定义设为「深色」且「始终」，小号、大号组件重新显示全彩靛色月亮和黑底闪电，文件夹缩略图也显示月亮；默认浅色与主屏深色样式之间的实际双向切换已通过。本机只切整体 Light 而主屏保留「透明」浅色样式时，小组件仍使用深色变体；该结果说明当前呈现环境与整体外观开关可能不同，不代表透明样式固定使用深色。选图遵循当前界面的明暗环境，透明与色调效果由系统控制。

文件夹封面已接入 App 与组件：每个文件夹独立设置普通/深色照片、符号或文字，未自定义时显示内容缩略图，可以仅覆盖深色；封面带文件夹角标，不改变内容或动作目标。复用现有裁剪与双侧草稿，先应用到分组草稿，再保存整个分组；撤销、重做、移动及复制保留封面引用。封面图片存于本地 App Group 的独立资源区，编辑历史不内嵌照片；备份从 v5 起包含这些资源并去重。存储、失败回滚、历史保留及备份核心测试已通过。显式封面资源读取失败会沿用现有的 15 分钟 timeline 重试计划，合法的仅深色封面不误判；3 项核心回归已通过，未在模拟器人为复现并发读取失败。

封面运行验证已完成以下范围：取消编辑后原分组文件逐字节不变，未产生暂存或持久资源；用系统照片选择器选生成的四色测试图，普通封面 120% 放大并右移，深色另设青色 #007C91 公文包。点击「使用封面」后，原 JSON 不变，只有两份暂存资源；撤销回内容缩略图并恢复配置检查报告，重做恢复照片封面与角标。保存后仅「工作」文件夹的封面引用及更新时间变化，子项、动作、UUID 等全保持；两份资源持久保存，暂存归零。实际小号桌面在主屏「深色」且「始终」时显示青公文包和角标，点击仍进入文件夹内容，返回并切换主屏为「默认」后显示照片和角标。「恢复内容缩略图」菜单、撤销恢复封面和重做恢复 mini 已实际验证；缺失/损坏资源 × 保存/取消的四个核心回归场景也已通过。

确认保存与放弃两路均已实测返回分组列表：原「日常」恢复内容缩略图后确认放弃，原分组文件逐字节未变。重开恢复副本可见照片封面，只把深色青公文包改为棕色 #A65300，使用封面后返回并确认保存，列表显示已保存副本。普通照片的资源标识、完整对象及 PNG 与导出时相同；深色资源标识与颜色更新，除封面及更新时间外其余内容不变，原组文件仍不变。暂存归零，持久资源为原两份加一份新深色资源。

编辑器撤销与重做已实现。独立模拟器已验证多层文件夹删除恢复、重做后的路径修复、空名称草稿继续编辑、连续名称合并、跨文件夹移动恢复和网格撤销；全部撤销后保存，结构、名称与 UUID 均与编辑前一致。颜色面板内连续选色合并、分次打开的独立步骤及撤销/重做往返也已实测。历史仅保留本次编辑，离开或保存后清空。

---

## 简体中文（主语言）

**名称**（≤30）

```
AppFolder - 桌面文件夹小组件
```

**副标题**（≤30）

```
常用动作直开，分组随心整理
```

**关键词**（≤100 字节，逗号分隔，不要空格）

```
文件夹,桌面,小组件,启动器,大文件夹,桌面整理,图标,快捷启动,launcher,widget
```

**推广文本**（≤170，可随时改，不随版本审核）

```
保存动作与网站分组，重排图标、嵌套文件夹或留出空位。小、中、大三种尺寸支持原地导航，也可用照片、符号和文字自定义图标，再通过系统分享面板分享单个分组。
```

**描述**（≤4000）

```
AppFolder 把常用 App 动作、网站和联系人整理进主屏幕小组件。已配置的 App 动作交给系统直接执行，不把 AppFolder 作为中转页面；联系人和部分网站打开方式通过 AppFolder 交接。

你可以选择打开 App，也可以运行 App Shortcut、自定义快捷指令或系统动作。网站格子保存 HTTP(S) 网址，无需额外配置系统动作。默认由系统直接打开；每个网站也可选择 App 内浏览、Chrome、Firefox 或「跟随 App 设置」，通过 AppFolder 交接。统一设置只影响明确选择跟随的网站，旧网站与新建网站仍默认使用系统默认方式。输入、预览、选择打开方式和导入均不会访问网站或改写已保存的网址。

■ 怎么用
1. 长按桌面空白处 → 编辑 → 添加小组件 → 搜 AppFolder → 选择「直接启动」
2. 长按放好的小组件 → 编辑小组件 → 在「动作」里逐个挑 App
3. 可先在 App 内「我的分组」保存布局，再回到「编辑小组件」的「分组布局」选择它
4. 动作格子需在系统面板中设置同名动作；网站无需额外动作。再选择外观，小号还可选择网格

添加小组件和选择实际动作需要你在系统界面完成，AppFolder 不能代你放置组件或选择动作。保存分组后，可以在「小组件配置检查」查看所需动作与最近的匹配结果。点击已保存分组中未配置或同名冲突的图块，还可打开该动作的配置帮助，按具体名称和步骤在系统面板中补充动作。

■ 特点
· App 动作直开：由系统执行已配置的动作，不经过 AppFolder
· 保存多个分组，混排动作和网站、移动到文件夹、添加空位；每组最多 200 项，文件夹最多嵌套四层
· 网站默认显示地球图标，每格可独立设置普通/深色照片、符号或文字；文件夹缩略图按顺序混合展示动作与网站
· 联系人图块保存姓名与一个电话号码，支持电话、短信、FaceTime 语音或视频；通过 AppFolder 交给系统处理，短信不会自动发送，FaceTime 需再次点击开始
· 可手填联系人或使用系统联系人选择器，只接收选中的姓名与号码，不读取整个通讯录
· 从 Safari 等 App 分享一个网址到 AppFolder，手动保存到「待添加网页」；再打开 App，选择已有或新建分组，保存分组后才移出待添加列表
· 待添加网页支持多选，也可加入正在编辑的文件夹；批量加入可一次撤销，取消或失败保留记录，重复加入同一记录不会重复插入
· 本次编辑中可撤销、重做布局、名称和外观修改，误删文件夹也能连同内容恢复
· 保存分组的标准网格为小号 4/9 格、中号 10 格、大号 16 格；返回与翻页以图标显示，并占用网格位置
· 默认布局首页：小号 3/8 个动作、中号 9 个、大号 15 个；超出从「其他」展开，返回与翻页按钮占格
· 分组按名称匹配系统面板中配置的动作；缺失或多个动作同名时会提示重新配置
· 配置检查列出所需动作、缺失和同名冲突，帮助你找到需要补充的动作
· 导出整个资料库备份，或只分享一个已保存分组及其网站打开方式、关联图标、匹配和图片资源；在系统分享面板自行选择目的地
· 单分组分享不带出其他分组、无关图标、编辑历史或检查报告；导入先预览，确认后新增副本并保留已有图标设置
· 外观随分组及子文件夹保存：名称显示、图标大小、底板、颜色、间距、边距和名称描边；小号还能保存网格，其他尺寸可调整密度
· 把常用外观命名保存为预设，在其他分组或子文件夹中主动应用；更改预设不会改动已保存分组
· 在系统面板开启「使用分组外观」即可应用；默认关闭，已有组件保留原外观
· 底板可选自动（独立玻璃）、纯色或渐变；图标大小三档
· 默认主屏外观下即可显示独立玻璃，无需开启全局「透明」或「色调」
· App 内可交互预览小、中、大尺寸及文件夹展开，无需联网
· 可选显示名称，也可为每个动作设置昵称；改昵称不改变绑定目标
· 图标工作室：用照片、符号、表情或文字分别设置普通和深色图标，跟随当前界面明暗外观；桌面透明与色调效果由系统控制
· 可保持普通图标自动匹配，仅自定义深色；未设置深色时跟随普通图标
· 修改一侧保留另一侧照片原样；指定 App Store 图标也会保留独立深色设置
· 动作同名格子共享图标设置；文件夹可单独设置普通/深色照片、符号或文字封面，未自定义时显示内容缩略图

■ 隐私
不向开发者上传个人数据。没有账号、没有统计、没有广告 SDK。图标搜索会向 Apple 发送 App 名称或商店编号并下载图标。分组、联系人姓名与单个号码、网址、图标、外观预设、动作资料库与最多 24 份配置检查报告保存在设备上；报告只反映最近刷新结果，不是当前桌面组件清单。输入、布局预览、选择打开方式和导入不会访问网站。主动点击「获取网站信息」会访问该网站及其图标服务器，服务端会收到请求网址、IP 地址等正常网络信息；获取的名称和图标须由你选择采用。点击「测试链接」或网站图块才按所选方式打开。默认网站图块由系统直接打开；App 内浏览、Chrome、Firefox 和「跟随 App 设置」通过 AppFolder 交接。App 内浏览使用系统 Safari 模态页面，可加载资源和运行脚本；AppFolder 不读取该页面内容或密码，网站及浏览器按各自政策处理数据。单独的「获取网站信息」仅解析有限 HTML，不渲染网页或执行脚本。网页分享扩展只保存完整网址和可选手动名称，不读取分享正文、网页标题、图标或剪贴板，不联网、不自动打开主 App；最多保留 100 条待添加记录，未加入分组的记录不进入备份。备份与分享文件包含选中范围内的联系人姓名与号码、网址、每网站打开方式（含跟随选择）、动作资料及自定义图标和封面照片小图；全库备份另含外观预设，不含本机统一打开偏好、系统动作、编辑历史和检查报告；导入的跟随选择使用目标设备设置，保存或分享目的地由你选择。可在「我的分组」中删除分组；已导出的文件需在「文件」中另行管理。

■ 说明
· 提供小号、中号、大号和超大竖屏主屏小组件，以及圆形和矩形锁屏小组件；以设备系统提供的尺寸为准
· 需要 iOS 27 或更高版本
```

---

## English

**Name** (≤30)

```
AppFolder - App Folder Widget
```

**Subtitle** (≤30)

```
One tap, straight to the app
```

**Keywords** (≤100 bytes, comma-separated, no spaces)

```
app folder,folder widget,launcher,home screen,organize,shortcut,quick launch,one tap,icons
```

**Promotional text** (≤170)

```
Arrange apps and websites in small, medium, or large widgets. Add nested folders and custom icons, then share a saved group through the system share sheet.
```

**Description** (≤4000)

```
AppFolder organizes apps, websites, contacts and shortcuts in Home Screen widgets. iOS runs configured App actions directly. Contacts and some website opening modes use AppFolder to hand off to the system.

GET STARTED
Hold the Home Screen > Edit > Add Widget > search AppFolder > Quick Launch. Hold the widget > Edit Widget > choose apps or shortcuts under Actions. Save a layout in My Groups, then select it under Group Layout. Action tiles need unique matching names; websites need no system action. Widget Configuration Check lists required names, missing actions and conflicts. Tap an unconfigured tile for setup help.

ARRANGE YOUR GROUPS
Mix actions, websites, contacts, folders and empty cells, with up to 200 items and four folder levels. Reorder or move items, rename display labels, and undo or redo during editing. Nicknames do not change action targets. The action library helps organize names with tags and archives; it is not an installed-app list.

Preview folders and layouts offline. Home Screen sizes include small, medium, large and extra-large portrait where offered by iOS. Standard saved-group grids have 4/9, 10 and 16 cells for small, medium and large. Navigation icons occupy cells. Circular and rectangular Lock Screen widgets offer selected items from saved groups; iOS may require unlocking.

MAKE IT YOURS
Save labels, icon size, plate, color, spacing, margins and title outlines with groups or individual folders. Apply named appearance presets without changing previously saved groups. Enable Use Group Appearance in Edit Widget to apply saved styling; off by default. Automatic glass works in the default Home Screen style.

Icon Studio uses selected photos, files, symbols, emoji, text or a date style. Standard and dark artwork are independent; unset dark follows standard. Folders can have their own covers or show their contents. Date refresh timing is controlled by iOS.

WEBSITES AND CONTACTS
HTTP(S) sites open with the system, or via AppFolder using in-app Safari, Chrome, Firefox or Follow app settings. The app preference affects only sites explicitly set to follow it. Fetch Website Information contacts the website and icon servers only on tap; names and images need your approval before saving.

Share a URL from Safari to AppFolder, tap Save, then open My Groups > Pending websites. Select a group and save it to finish adding. Cancelling or a failed group save keeps pending records.

Contact tiles store a name and one number, typed manually or chosen with the system picker. Calls require system confirmation, SMS is not sent automatically, and FaceTime needs a separate Start tap in AppFolder. Editing and importing never initiate contact.

BACKUP AND PRIVACY
Export the library or one saved group, including related icons, matches, websites and contact names/numbers. Full backups also include appearance presets and saved action-library records. Confirm imports to add copies while keeping existing settings. System actions must be configured again. Device preferences stay local; imported Follow choices use the destination device's preference.

No account, advertising or analytics SDK. No personal data is uploaded to the developer. Apple receives icon searches; website and browser services receive requests you initiate. Photos and files are limited to images you select. The share extension stores one URL and optional manual title locally without fetching pages or launching the app. Read the privacy policy in Permissions for retention and deletion details.

Requires iPhone with iOS 27 or later.
```

---

## 审核备注（App Review Information → Notes，≤4000 字节）

说明核心功能入口、配置步骤及外部服务。商店 App Preview 视频为可选项；本案已核实 Apple 在具体审核反馈中要求最新系统真机演示视频，应按该反馈准备与提交版本一致的素材。以下字段是当前源码对应的候选文案，须完成实际流程验收、发行包验证及 App Store Connect 核对后使用。

```
PURPOSE AND ACCESS
AppFolder helps iPhone users reduce Home Screen clutter and reach frequent actions. It organizes App actions, websites and contacts in saved folders, with custom artwork, appearance presets, a local library, backup and sharing. No login, public content feed or in-app purchases.

SETUP
1. Home Screen > Edit > Add Widget > search AppFolder > Quick Launch. Hold the widget > Edit Widget > select apps/shortcuts under Actions. Configured App actions run through iOS without opening AppFolder.
2. Open My Groups. Add actions, websites, contacts, folders or spaces, arrange them and Save Group. Select the saved group under Group Layout in Edit Widget. Action names must uniquely match configured Actions. Missing or conflicting tiles open setup help; help does not change system actions. Websites need no system action.
3. The preview supports navigation and editing without executing actions. Undo/redo stays in the current edit session. Use Group Appearance in Edit Widget applies saved styling and defaults off. Groups/folders save density, spacing, margins, title color/outline, artwork and appearance presets. Existing defaults are preserved. Automatic glass works in Default Home Screen appearance.
4. Home Screen: small, medium, large and extra-large portrait where offered by iOS. Navigation icons occupy cells. Lock Screen: add AppFolder's circular or rectangular launcher, choose saved-group items and configure matching Actions. Authentication follows iOS rules.
5. Website editors offer system default, in-app Safari, Chrome, Firefox or Follow app settings. Only explicit Follow sites use the device preference. Test Link opens the draft choice. Fetch Website Information contacts the target/icon servers on tap; results require adoption. Safari browsing may run scripts; metadata fetching does not. Inputs, previews and imports do not visit sites.
6. Contact tiles accept a manually entered name/number or the system contact picker. Only the chosen name and one number are stored. Taps use AppFolder to hand off calls/SMS; iOS confirms calls and SMS is not sent automatically. FaceTime requires a separate Start tap. Editing/importing never initiates contact.
7. Safari > Share > AppFolder > optional manual title > Save > Done. Open AppFolder > My Groups > Pending websites, choose a group and Save Group. Adding from an editor uses the current folder. Cancel/failure keeps pending records; retry does not duplicate the same record in the group.
8. Icon Studio edits actions by name. Folder, website and contact menus edit their own artwork. Choose a photo/file, symbol, text or date style, apply, then save. Unset dark follows standard; iOS schedules date refreshes.
9. Backup v16 reads v1-16. Share Group exports only the selected saved group and related records/artwork. Full exports also include saved/archived action-library records and appearance presets. Exported files can contain contact names/numbers and full URLs/photos. Imports add copies and missing settings, preserving existing records; reconfigure system actions. Device preferences, pending records, system action tokens, widget settings, caches, edit history and reports are excluded. Choose export destinations in the system sheet.

SERVICES AND PRIVACY
Apple iTunes Search/Lookup supplies App icons. No developer backend, analytics or ads. Groups, URLs, contact fields, presets, artwork and library records stay local. System pickers read selected contacts/images only. Share extension saves one URL and optional title; no page/clipboard read, network request or automatic app launch. Up to 24 local configuration reports show past matches, not a live widget inventory. The current privacy policy is available offline in Permissions.

iPhone, iOS 27+. Features are consistent worldwide; storefronts affect icon results only. A personal productivity utility, not a regulated service. App names/icons do not imply affiliation.
```
