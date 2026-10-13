# App Store Connect 文案（可直接粘贴）

每条都标了 Apple 的字符上限。**名称、副标题、关键词**三处一起决定搜索曝光，
所以关键词里不要重复名称里已有的词。

---

## 简体中文（主语言）

**名称**（≤30）

```
AppFolder - 桌面文件夹小组件
```

**副标题**（≤30）

```
点一下直接打开，不经过中转
```

**关键词**（≤100，逗号分隔，不要空格）

```
文件夹,桌面,小组件,启动器,大文件夹,桌面整理,图标,快捷启动,整理,launcher,widget
```

**推广文本**（≤170，可随时改，不随版本审核）

```
把常用的几个 App 放进桌面上的一个方块，点一下直接打开——不经过 AppFolder，中间不闪任何东西。支持深色图标、纯色/渐变底板，还有一屏教程教你 30 秒放好。
```

**描述**（≤4000）

```
AppFolder 把常用的几个 App 收进主屏幕上的一个方块，点一下直接打开——不经过 AppFolder，中间不闪任何东西。

和普通「快捷方式」不同，这里点下去是系统直接切换过去，AppFolder 不会被唤起。这是 iOS 27 新开放的直开能力，也是本 App 存在的前提。

■ 怎么用
1. 长按桌面空白处 → 编辑 → 添加小组件 → 搜「直接启动」
2. 长按放好的小组件 → 编辑小组件 → 在「动作」里逐个挑 App
3. 按喜好调网格、图标大小、底板与颜色

iOS 不允许 App 自己往桌面放东西，也不知道你在桌面上放了什么，所以第 1、2 步只能手动完成，系统对每个 App 都一样。

■ 特点
· 点一下直开：零跳转，不经过 AppFolder
· 一屏 8 个 App（九宫格）或 3 个（四宫格，图标接近桌面大小）
· 放不下的 App 收进最后一格的「其他」——那是一扇文件夹门，点一下在原地展开，不跳走
· 底板可选自动（系统玻璃）、纯色或渐变；图标大小三档
· 可选显示 App 名称
· 图标认错时，在 App 内的「修正图标」里指定正确的那一个

■ 隐私
不收集任何数据。没有账号、没有统计、没有广告 SDK。唯一的联网是去 Apple 的公开接口取 App 图标，不携带任何关于你的信息。全部配置只存在你自己的设备上。

■ 说明
· 目前只提供小号小组件：它是唯一经过真机实测、在各种图标大小设置下都成立的尺寸
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

**Keywords** (≤100, comma-separated, no spaces)

```
app folder,folder widget,launcher,home screen,organize,shortcut,quick launch,one tap,icons
```

**Promotional text** (≤170)

```
Put your everyday apps in one square on the Home Screen and open them in a single tap — no hop through AppFolder, nothing flashing in between. Dark-ready icons, solid or gradient plates, and a 30-second setup guide.
```

**Description** (≤4000)

```
AppFolder gathers a few everyday apps into one square on the Home Screen, and opens them in a single tap — without going through AppFolder, with nothing flashing in between.

This is not a shortcut runner. The tap is handled by the system: AppFolder is never brought up. It uses the direct-launch capability iOS 27 opened up, which is the whole reason this app exists.

■ Getting set up
1. Touch and hold an empty spot on the Home Screen → Edit → Add Widget → search "Quick Launch"
2. Touch and hold the widget → Edit Widget → pick your apps one at a time under Actions
3. Adjust grid, icon size, plate and color to taste

iOS does not let an app place anything on the Home Screen itself, and an app cannot see what is on yours — so those two steps are always manual, for every app.

■ What it does
· One tap to launch: no hop, no AppFolder in the middle
· Eight apps at a glance (3 × 3), or three at close to Home Screen size (2 × 2)
· Anything beyond that goes into the "Other" cell — a folder door that opens in place without leaving the Home Screen
· Plate: automatic (the system's glass), solid, or gradient; three icon sizes
· Optional app names under the icons
· If an icon belongs to the wrong app, use Fix Icons to say which one you mean

■ Privacy
No data is collected. No accounts, no analytics, no advertising SDK. The only network access is Apple's public endpoint for app artwork, and it carries nothing about you. Everything stays on your device.

■ Notes
· Only the small widget size is offered: it is the only one we measured on a real iPhone and that holds up at every icon-size setting
· Requires iOS 27 or later
```

---

## 审核备注（App Review Information → Notes）

这段**很重要**：审核员打开 App 只会看到一屏教程，写清楚价值在哪，能显著降低 4.2 的风险。

```
AppFolder's value is the Home Screen widget it ships, not the app itself. The app is
deliberately just a guide plus one tool, because iOS keeps a widget's configuration out
of reach: a widget's actions are opaque system values held by WidgetKit, so no app can
list or build them.

HOW TO SEE THE FEATURE (about 30 seconds):
1. Touch and hold an empty area of the Home Screen, tap Edit, then Add Widget.
2. Search for "Quick Launch" (that is the widget's name; it is not called AppFolder).
3. Choose the small size and add it.
4. Touch and hold the widget, tap Edit Widget, and add a few apps under Actions.
5. Tap an icon — the app opens directly, with no hop through AppFolder and no flash.

WHAT ELSE THE APP DOES:
· Tapping the "Other" cell in the last slot opens the rest of the grid in place.
· "Fix Icons" (in the app) lets the user correct an icon the App Store name search
  matched to the wrong app — a real tool, not a placeholder screen.

NOTE ON SIZE: only the small family is offered. Medium and large were measured on
device and their icon sizes did not hold up, so they are not offered.

No account or network service of our own is used; the only request is to Apple's public
iTunes endpoint for app artwork.
```
