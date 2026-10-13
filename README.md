# AppFolder

给 iPhone 带来「大文件夹」体验 —— 灵感来自小米桌面 / Android 的大文件夹：一个桌面上的方块里直接平铺几个 App 图标，点一下**直接进 App**，不用先「打开文件夹」，也不经过 AppFolder。

iOS 不允许第三方 App 替换桌面，所以本项目的做法是把它做成**主屏上的一个 widget**：系统允许的、唯一能显示自定义内容又能响应点击的桌面元素。

## 它是怎么做到「点一下直开」的

widget 里的链接本来只能打开它自己的宿主 App（Apple 文档原文），所以直开第三方 App 必须绕。本仓库最终走通的是 iOS 27 的 `RunSystemShortcutIntent`：**零跳转、不依赖 URL scheme、任何已装 App 都行**，代价是目标 App 得由用户在「编辑小组件」面板里手选——系统不提供任何可编程的目标列表。

这也解释了本 App 现在的形态：**它只有一屏教程**。小组件的配置全部在系统的编辑面板里完成（存进 widget 自己的配置，不落我们的盘），所以 App 里没有文件夹、没有编辑器、没有分享扩展——那些都是「在 App 里编排 App」的机器，而没有任何东西再读它们。App 唯一还做的事是：打开时请小组件收回展开态。

## 目前状态

App + widget 扩展 + 共享 package 三个 target 可以编译运行，真机验证过直开与原地展开。调研结论见 [`docs/research/`](docs/research/)。

## 先读这三份文档

1. [`docs/research/01-widgetloft-拆解.md`](docs/research/01-widgetloft-拆解.md) —— 参考产品 WidgetLoft 是怎么做的，以及它暴露了哪些平台限制
2. [`docs/research/02-平台限制.md`](docs/research/02-平台限制.md) —— iOS 允许什么、禁止什么，附 Apple 官方文档原文
3. [`docs/research/03-技术方案.md`](docs/research/03-技术方案.md) —— 本仓库的实现方案与理由

## 核心结论

1. **widget 里的链接只能打开它自己的宿主 App**（Apple 文档原文），所以「点图标打开第三方 App」必须绕。
2. 绕法实测有三条，本仓库**最终只保留第三条**：经宿主 App 中转（有闪烁）、`https://` 通用链接（无闪烁但覆盖率只有 6/60）、iOS 27 的 `RunSystemShortcutIntent`（无闪烁、零跳转，由用户手选）。前两条随「大文件夹」widget 一起删掉了。
3. iOS **没有**任何公开 API 能枚举已安装 App。小组件只拿得到一个显示名，图标要靠名字去 App Store 反查、下载后缓存在 App Group 里。

## 目录结构

```
AppFolder/              宿主 App（SwiftUI，只有一屏教程）
AppFolderWidget/        widget 扩展（直开组件）
Packages/AppFolderKit/  共享核心（App 与扩展都链接）
Config/                 Info.plist、entitlements
docs/research/          调研文档
```

## 开发

```bash
# 快速类型检查（比完整构建快得多）
swift build --package-path Packages/AppFolderKit

# 跑共享 package 的测试
swift test --package-path Packages/AppFolderKit

# 构建 App
xcodebuild -project AppFolder.xcodeproj -scheme AppFolder \
  -sdk iphoneos -destination 'generic/platform=iOS' build
```

- Xcode 27.0+ / Swift 6.4（本仓库用 Swift 6 语言模式，严格并发）
- 最低部署目标 iOS 27.0（产品依赖 iOS 27 的 `RunSystemShortcutIntent`，没有更低版本的退路）

> ⚠️ App Group 是 App 与 widget 之间唯一的共享通道。少了它在真机上 widget 仍能渲染（图标由扩展自己取），但 App 发的「收回展开」请求传不过去。

## 免责声明

本项目与小米、Apple、WidgetLoft 均无关联。不涉及越狱、私有 API 或任何绕过 App Store 审核的手段。
