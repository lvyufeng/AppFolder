# AppFolder

给 iPhone 带来「大文件夹」体验 —— 灵感来自小米桌面 / Android 的大文件夹：一个桌面上的方块里直接平铺 4~9 个 App 图标，点一下直接进 App，不用先「打开文件夹」。

iOS 不允许第三方 App 替换桌面（SpringBoard），所以本项目的核心命题是：**用系统允许的机制，尽量逼近大文件夹的体验**，并把这个机制的上限、代价和边界摸清楚。

> 当前状态：**调研阶段**。`docs/` 下是调研结论，代码尚未开始。

## 为什么需要调研

App Store 上已经有同类付费产品（如 App Folder Launcher / WidgetLoft）。它们能做到「桌面上一个方块、里面 4~8 个图标、点了直接跳对应 App」，但 iOS 没有任何公开 API 能枚举已安装 App，也没有 API 能让桌面显示别人的图标。所以这类产品一定是靠组合下面这些能力「拼」出来的：

- WidgetKit 小组件 + `Link` / `widgetURL` / `AppIntent` 交互
- Shortcuts（快捷指令）的「添加到主屏幕」自定义图标书签
- `LSApplicationQueriesSchemes` + `canOpenURL` + 一份巨大的 URL Scheme 数据库
- 宿主机 App 作为「中转」（点小组件 → 先拉起自己 → 再用 `UIApplication.open` 跳到目标 App）

本仓库要回答的是：**这些手段各自的边界在哪、体验代价多大、能不能过审。**

## 目录结构

```
docs/           调研文档（技术可行性、平台限制、竞品分析、上架风险）
Sources/        （预留）核心逻辑
App/            （预留）宿主 App 与 Widget Extension
```

## 文档

- [`docs/research/`](docs/research/) — 调研报告

## 开发环境

- Xcode 27.0 (Build 27A266a)
- Swift 6.4
- 目标平台：iOS 26+（待定，取决于调研结论）

## 免责声明

本项目与小米、Apple 无关联。不涉及越狱、私有 API 或任何绕过 App Store 审核的手段。
