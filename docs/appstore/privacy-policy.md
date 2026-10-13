# AppFolder 隐私政策 / Privacy Policy

> 生效日期：2026-10-13　最后更新：2026-10-13
>
> ⚠️ 发布前要把两处 `<>` 占位换成真值：联系邮箱、以及在 App Store Connect 里填同一个 URL。

---

## 中文

AppFolder 不收集你的任何数据。

**我们不收集的东西**：没有账号，没有注册，没有统计埋点，没有崩溃上报，没有广告 SDK，没有任何第三方 SDK。我们不建立用户画像，不做追踪，不出售任何信息。App 内没有可上传你数据的服务器。

**存在你设备上的东西**：桌面小组件的配置（选了哪些 App、外观设置）由 iOS 的 WidgetKit 保存在系统里，AppFolder 读不到也传不走。AppFolder 自己在 App 与小组件之间的共享容器里存两样东西：从 App Store 取回的 App 图标缓存，以及一份用于排查问题的诊断日志（上限 256 KB，随安装一起删除）。卸载 AppFolder 会一并删除这些内容。

**唯一的联网**：为了在格子里显示真实图标，AppFolder 会向你设备所在区域对应的 Apple 公开接口（`itunes.apple.com`）查询 App 的名字与图标。请求里只包含你在小组件上配置的那个 App 的名字，不包含任何关于你的信息、设备标识或位置。除此之外 AppFolder 不发起任何网络请求。

**权限**：AppFolder 不读取你的通讯录、照片、位置、通知或已安装 App 列表。App 内「权限」一节列出的就是全部。

**分析**：AppFolder 使用 Apple 提供的、汇总后无法识别个人的 App Store 统计（下载量、崩溃），这是所有 App 默认都有的，我们无法从中识别任何具体的人。

**儿童**：AppFolder 不面向 13 岁以下儿童，也不会有意收集儿童的信息。

**变更**：本政策如有更新会发布在本页并更新上面的日期。

**联系**：`<你的联系邮箱>`

---

## English

AppFolder does not collect any data about you.

**What we do not collect.** No accounts, no sign-up, no analytics, no crash reporting, no advertising SDK, and no third-party SDKs of any kind. We do not build profiles, we do not track you, and we do not sell anything. The app has no server of ours to upload anything to.

**What stays on your device.** Your widget's configuration — which apps you picked and how it looks — is held by iOS in WidgetKit, where AppFolder can neither read it back out nor send it anywhere. AppFolder itself keeps two things in the shared container between the app and its widget: the app-icon artwork downloaded from Apple's public search API, and a diagnostic log used to investigate problems (capped at 256 KB, removed with the app). Deleting AppFolder deletes all of it.

**The only network access.** To draw a real icon in each cell, AppFolder asks Apple's public endpoint (`itunes.apple.com`) for that app's name and artwork, in the storefront your device is in. The request contains the name of the app you configured, and nothing about you — no device identifier, no location, no account. Nothing else in the app makes a network request.

**Permissions.** AppFolder does not read your contacts, photos, location, notifications, or the list of apps you have installed. The Permissions section inside the app lists exactly this.

**Analytics.** AppFolder receives the standard, aggregated App Store statistics Apple provides for every app (downloads, crashes). These cannot be used to identify any individual.

**Children.** AppFolder is not directed to children under 13, and we do not knowingly collect information from them.

**Changes.** If this policy changes, the update appears on this page with a new date above.

**Contact.** `<your contact email>`
