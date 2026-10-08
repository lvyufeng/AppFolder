import SwiftUI

/// The whole app: how to set the widget up, and the one thing it cannot do for
/// you.
///
/// ## Why this screen is the entire app now
///
/// Everything the app used to hold — folders, the editor, the share extension
/// and its resolution queue — is gone. It was all machinery for arranging apps
/// *inside AppFolder*, and the widget no longer draws anything AppFolder stores:
/// the direct-launch widget's slots are `SystemShortcut`s the user picks in the
/// Edit Widget sheet, held by the system, never written to a file of ours. So
/// there is no longer any state for a screen to manage, and what is left for the
/// app to do is explain the one manual step iOS insists on.
///
/// ## Why it is worth keeping at all
///
/// Not politeness — the step is genuinely unguessable. iOS will not let an app
/// place its own widget, the widget is listed under a name (`直接启动`) that is
/// not the app's name, and its most important setting is an app picker that
/// lives behind a long-press. A user who has installed the app and found no
/// widgets has no way to discover any of that from the app's absence.
///
/// ## And why the last section exists
///
/// The app holds no app list, and a user will reasonably read that as an
/// unfinished feature. It is not: the system gives a widget's configuration
/// intent no programmable target list — `SystemShortcut` has no initialiser —
/// so "pick the apps in AppFolder and let the widget read them" is not a design
/// we chose against, it is one the platform does not allow. Saying so is the
/// difference between a limitation and a bug.
struct TutorialView: View {
    var body: some View {
        NavigationStack {
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
                        detail: "在列表里搜「直接启动」——小组件叫这个名字，不叫 AppFolder。"
                    )
                    Step(
                        number: 3,
                        title: "选小尺寸，点「添加小组件」",
                        detail: "只有小尺寸。它一个能放八个 App，点下去直接打开，不经过 AppFolder。"
                    )
                } header: {
                    Text("放到桌面")
                } footer: {
                    Text("iOS 不允许 App 自己往桌面放东西，这一步只能手动完成，系统每次都会这样。")
                }

                Section {
                    Step(
                        number: 1,
                        title: "长按刚放上去的小组件",
                        detail: "点「编辑小组件」。"
                    )
                    Step(
                        number: 2,
                        title: "在「动作」里逐个挑 App",
                        detail: "一次挑一个，挑完可以再挑下一个，它们是累加的。挑的顺序就是格子里从左到右、从上到下的顺序。"
                    )
                    Step(
                        number: 3,
                        title: "按喜好调外观",
                        detail: "网格、显示图标名称、底板、颜色、图标大小，都在同一个面板里。"
                    )
                } header: {
                    Text("配置它")
                } footer: {
                    Text("配置面板里的每一项都立即生效，不用重新添加小组件。")
                }

                Section {
                    Text("九宫格放 8 个，四宫格放 3 个。再多的 App 会收进最后一格的「其他」——那是一扇文件夹门，点一下在原地展开，不会跳走，左上角有「返回」。一页放不下时会多出「更多」翻页。")
                    Text("格子里的图标是 AppFolder 联网取回来存下的，第一次出现在桌面上可能慢一拍；取不到时先显示一个占位方块，不会空着。")
                } header: {
                    Text("放不下的时候")
                }

                Section {
                    Text("小组件里的 App 只能在系统的配置面板里选，App 里做不到。这不是还没做：iOS 给小组件配置项的是一组不透明的「系统动作」，App 拿不到、也构造不出任何可选的 App 列表。")
                    Text("同样地，点图标时是系统直接切换过去，AppFolder 不会被唤起，也不会在中间闪一下。")
                    Text("能改的是**图标**。图标是按格子上的名字去 App Store 找回来的，同名 App 多的时候会认错——比如两个 App 都叫 Authenticator。去「修正图标」告诉它该用哪一个。")
                } header: {
                    Text("为什么不能在 App 里配")
                }

                Section {
                    NavigationLink {
                        IconFixView()
                    } label: {
                        Label("修正图标", systemImage: "wand.and.stars")
                    }
                } footer: {
                    Text("图标认错了、或者某格一直是占位方块时，从这里指定正确的 App。")
                }

                Section("权限") {
                    LabeledContent("读取已安装 App") {
                        Text("不读取")
                    }
                    LabeledContent("联网") {
                        Text("搜索 App、拉取图标")
                    }
                    LabeledContent("账号 / 追踪") {
                        Text("无")
                    }
                }
            }
            .navigationTitle("怎么用")
        }
    }
}

/// One numbered step.
private struct Step: View {
    let number: Int
    let title: String
    let detail: String

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