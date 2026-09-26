# AppFolder

给 iPhone 带来「大文件夹」体验 —— 灵感来自小米桌面 / Android 的大文件夹：一个桌面上的方块里直接平铺 4~9 个 App 图标，点一下直接进 App，不用先「打开文件夹」。

iOS 不允许第三方 App 替换桌面，所以本项目的做法是把「大文件夹」做成**主屏上的一个 widget**：系统允许的、唯一能显示自定义内容又能响应点击的桌面元素。

## 目前状态

代码可以编译运行（宿主 App + widget 扩展 + 共享 package），但**还没在真机上跑过**。调研结论见 [`docs/research/`](docs/research/)。

## 先读这三份文档

1. [`docs/research/01-widgetloft-拆解.md`](docs/research/01-widgetloft-拆解.md) —— 参考产品 WidgetLoft 是怎么做的，以及它暴露了哪些平台限制
2. [`docs/research/02-平台限制.md`](docs/research/02-平台限制.md) —— iOS 允许什么、禁止什么，附 Apple 官方文档原文
3. [`docs/research/03-技术方案.md`](docs/research/03-技术方案.md) —— 本仓库的实现方案与理由

## 核心结论（三句话）

1. **widget 里的链接只能打开它自己的宿主 App**（Apple 文档原文），所以「点图标打开第三方 App」必须绕。
2. 绕法有三条：`https://` 通用链接由系统直开（无闪烁，但目标有限）、经宿主 App 中转（有闪烁，但任何目标都行）、iOS 27 的 `RunSystemShortcutIntent`（无闪烁，但由用户手选）。本仓库三条都实现，按图块配置分派。
3. iOS **没有**任何公开 API 能枚举已安装 App，也**没有**能读别人通知的 API。前者靠内置策展目录 + `canOpenURL` 探测解决，后者无解。

## 目录结构

```
AppFolder/              宿主 App（SwiftUI）
AppFolderWidget/        widget 扩展
Packages/AppFolderKit/  共享核心（App 与扩展都链接）
Config/                 Info.plist、entitlements
docs/research/          调研文档
```

## 开发

```bash
# 快速类型检查（比完整构建快得多）
swift build --package-path Packages/AppFolderKit

# 构建 App
xcodebuild -project AppFolder.xcodeproj -scheme AppFolder \
  -sdk iphoneos -destination 'generic/platform=iOS' build

# 检查 Info.plist 里的 LSApplicationQueriesSchemes 与目录是否一致
swift run --package-path Packages/AppFolderKit appfolder-schemes --check
```

- Xcode 27.0+ / Swift 6.4（本仓库用 Swift 6 语言模式，严格并发）
- 最低部署目标 iOS 18.0

> ⚠️ 用**免费 Apple ID** 签名时 App Groups 不可用，widget 会渲染成空。设置页的「放到桌面」标签会显示当前状态。用付费开发者账号才能完整测试 widget。

## 免责声明

本项目与小米、Apple、WidgetLoft 均无关联。不涉及越狱、私有 API 或任何绕过 App Store 审核的手段。
