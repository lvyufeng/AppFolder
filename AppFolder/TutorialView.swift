import AppFolderKit
import SwiftUI

/// A working example first; setup instructions and troubleshooting when needed.
struct TutorialView: View {
    private static let supportURL = URL(string: "https://lvyufeng.github.io/appfolder-site/support.html")!

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        Text("常用 App，一点即开")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text("在桌面上直接打开，不经过 AppFolder。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        WidgetPreviewView()
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section {
                    NavigationLink {
                        SetupGuideView()
                    } label: {
                        Label("添加小组件", systemImage: "plus.app")
                            .fontWeight(.medium)
                    }
                    .accessibilityIdentifier("home.setup")

                    NavigationLink {
                        LockScreenSetupGuideView()
                    } label: {
                        Label("添加锁屏小组件", systemImage: "lock")
                    }
                    .accessibilityIdentifier("home.lockScreenSetup")

                    NavigationLink {
                        SavedGroupsView()
                    } label: {
                        Label("我的分组", systemImage: "square.grid.2x2")
                            .fontWeight(.medium)
                    }
                    .accessibilityIdentifier("home.groups")

                    NavigationLink {
                        ActionLibraryView()
                    } label: {
                        Label("动作资料库", systemImage: "tag")
                    }
                    .accessibilityIdentifier("home.actionLibrary")

                    ShareInboxShortcut()

                    NavigationLink {
                        IconFixView()
                    } label: {
                        Label("图标工作室", systemImage: "paintpalette")
                    }
                    .accessibilityIdentifier("home.fixIcons")

                    NavigationLink {
                        BackupView()
                    } label: {
                        Label("备份与恢复", systemImage: "externaldrive")
                    }
                    .accessibilityIdentifier("home.backup")

                    NavigationLink {
                        WebsiteBrowserSettingsView()
                    } label: {
                        Label("网站打开设置", systemImage: "globe")
                    }
                    .accessibilityIdentifier("home.websiteBrowserSettings")
                } footer: {
                    Text("在这里整理动作、联系人和网站，再到小组件中选择分组。只有 App 动作需要额外配置系统动作。")
                }

                Section("常见问题") {
                    FAQ(
                        question: "放不下的时候",
                        answer: "默认布局会把超出的动作收进「其他」，可原地展开和翻页。保存的分组按自己的文件夹和顺序分页；使用图标网格中的返回和翻页按钮浏览。"
                    )
                    FAQ(
                        question: "如何使用自己保存的分组？",
                        answer: "保存后，在小组件的「分组布局」中选择它。联系人和网站无需额外动作；App 动作需配置对应名称。分组外观可按需开启。"
                    )
                    FAQ(
                        question: "怎样把分组外观应用到桌面？",
                        answer: "外观随分组保存。在「编辑小组件」中选择分组并开启「使用分组外观」即可应用；这个开关默认关闭，关闭时使用小组件自己的外观。预览尺寸不会改变桌面尺寸。"
                    )
                    FAQ(
                        question: "能为文件夹单独设置外观吗？",
                        answer: "可以。从文件夹菜单选择「编辑内部外观」，或在预览中进入文件夹。默认跟随最近上级；修改后成为独立设置，可随时恢复「跟随上级」。内容缩略图可独立选四格或九格。桌面应用这些内部外观仍需开启「使用分组外观」。"
                    )
                    FAQ(
                        question: "图标为什么半天不出现，或者有的格子是灰块？",
                        answer: "商店图标需要联网下载，之后保存在本地。首次显示可能稍慢；取不到时会显示占位方块。图标一直没有出现或匹配错误时，可到「图标工作室」指定正确的 App，也可以设置自己的图标。"
                    )
                    FAQ(
                        question: "格子里的 App 被删了会怎样？",
                        answer: "那一格会点不开。把被删掉的 App 从小组件里移除，或者换一个；系统不会自己帮你换。"
                    )
                    FAQ(
                        question: "修改名称或图标后，桌面会怎样更新？",
                        answer: "分组中的「修改显示名称」只改这个格子的标题，不影响绑定动作或图标。若系统动作的名称变了，请用「更换绑定动作」同步真实名称；需要修正图标时，到「图标工作室」按真实动作名称设置。保存后，桌面可能需要等待系统刷新。"
                    )
                    FAQ(
                        question: "AppFolder 会上传我的数据吗？",
                        answer: "不向开发者上传数据。搜索图标时，会向 Apple 发送 App 名称或商店编号，并下载图标。主动获取网站信息时，会访问该网站及其图标服务器，不使用浏览器登录状态。分组、图标修正和诊断记录保存在设备上。"
                    )
                    FAQ(
                        question: "如何选择小组件尺寸？",
                        answer: "支持小号、中号、大号和竖向超大（可用尺寸由设备决定）。小号可选四宫格或九宫格；其他尺寸可选标准、大图标或密集布局。可先在「我的分组」预览，再在桌面添加对应尺寸。"
                    )
                }

                Section("权限") {
                    LabeledContent("读取已安装 App") { Text("不读取") }
                    LabeledContent("联系人") { Text("仅所选姓名和号码") }
                    LabeledContent("联网") { Text("查询图标、读取所选云端文件") }
                    LabeledContent("账号 / 追踪") { Text("无") }
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label("隐私政策", systemImage: "hand.raised")
                    }
                    Link(destination: Self.supportURL) {
                        Label("帮助与反馈", systemImage: "questionmark.circle")
                    }
                }
            }
            .navigationTitle("AppFolder")
        }
    }
}

struct SetupGuideView: View {
    var showsGroupsLink = true

    var body: some View {
        List {
                Section {
                    Step(
                        number: 1,
                        title: "长按桌面空白处",
                        detail: "图标开始抖动后，点左上角的「编辑」。"
                    )
                    Step(
                        number: 2,
                        title: "点「添加小组件」",
                        detail: "搜索 AppFolder，打开后选择「直接启动」小组件。"
                    )
                    Step(
                        number: 3,
                        title: "选尺寸，点「添加小组件」",
                        detail: "左右滑动选择小号、中号或大号，再点「添加小组件」。尺寸由系统面板设置，App 内的预览不会自动修改桌面。"
                    )
                } header: {
                    Text("放到桌面")
                } footer: {
                    Text("添加和配置小组件需要在桌面上手动完成。")
                }

                Section {
                    Step(
                        number: 1,
                        title: "长按刚放上去的小组件",
                        detail: "点「编辑小组件」。"
                    )
                    Step(
                        number: 2,
                        title: "选择分组，按需添加 App 动作",
                        detail: "在「分组布局」中选择已保存的分组。联系人和网站无需额外动作；App 动作需在「动作」中配置同名系统动作。"
                    )
                    Step(
                        number: 3,
                        title: "按喜好调外观",
                        detail: "小号可选四宫格或九宫格；其他尺寸可选标准、大图标或密集布局。文件夹可单独设置内部外观。选择已保存的分组并开启「使用分组外观」即可应用。"
                    )
                } header: {
                    Text("配置它")
                } footer: {
                    Text("修改后返回桌面，等待系统刷新，无需重新添加。")
                }

                Section {
                    Text("返回 AppFolder，在「我的分组」中添加网站、整理动作。保存后，再到「编辑小组件」的「分组布局」中选择这个分组。")
                    if showsGroupsLink {
                        NavigationLink {
                            SavedGroupsView()
                        } label: {
                            Label("我的分组", systemImage: "square.grid.2x2")
                        }
                        .accessibilityIdentifier("setup.groups")
                    }
                } header: {
                    Text("回到 App 整理分组")
                }
        }
        .navigationTitle("添加小组件")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LockScreenSetupGuideView: View {
    var body: some View {
        List {
            Section {
                Text("先在「我的分组」保存动作、联系人和网站。锁屏小组件从中选择项目，不显示文件夹和空位。")
                NavigationLink { SavedGroupsView() } label: {
                    Label("我的分组", systemImage: "square.grid.2x2")
                }
                .accessibilityIdentifier("lockScreenSetup.groups")
            }
            Section {
                Step(number: 1, title: "自定锁定屏幕",
                     detail: "长按锁定屏幕，点「自定」，再选择锁定屏幕。")
                Step(number: 2, title: "添加「锁屏启动」",
                     detail: "点「添加小组件」，选择 AppFolder 的「锁屏启动」。圆形显示 1 项，矩形显示 2 项。")
                Step(number: 3, title: "选择启动项目",
                     detail: "从已保存分组中选择动作、联系人或网站。只有 App 动作还需在这个面板配置同名系统动作。")
            } footer: {
                Text("完成后返回锁定屏幕。设备锁定时，请按系统提示验证身份并解锁。")
            }
        }
        .navigationTitle("锁屏启动")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One numbered step.
private struct Step: View {
    let number: Int
    // LocalizedStringKey rather than String: `Text(String)` renders verbatim and
    // would quietly opt this screen out of the string catalog, which is exactly the
    // bug the catalog exists to prevent. The literals at the call sites already
    // infer to this type.
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.bold))
                .frame(width: 22, height: 22)
                .background(.tint, in: .circle)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// One question, answered — collapsed until it is asked for.
///
/// `LocalizedStringKey` for both, for the same reason as ``Step``: a plain `String`
/// would render verbatim and never reach the string catalog.
private struct FAQ: View {
    let question: LocalizedStringKey
    let answer: LocalizedStringKey

    var body: some View {
        DisclosureGroup {
            Text(answer)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
        } label: {
            Text(question).font(.body.weight(.medium))
        }
    }
}
