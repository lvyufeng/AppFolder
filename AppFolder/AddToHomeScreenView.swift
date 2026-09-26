import AppFolderKit
import SwiftUI
import WidgetKit

/// Explains the one thing the app cannot do for the user.
///
/// iOS will not let an app place its own widget on the Home Screen, so the last
/// step is always manual, and it is the step users get wrong. Showing the
/// gesture rather than describing it is the difference between a working install
/// and an app that gets deleted as broken.
struct AddToHomeScreenView: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Step(number: 1, title: "长按桌面空白处", detail: "图标开始抖动后，点左上角的「编辑」。")
                    Step(number: 2, title: "点「添加小组件」", detail: "在列表里搜 AppFolder。")
                    Step(number: 3, title: "选中号或大号，点「添加小组件」", detail: "中号放 6 个图标，大号放 9 个。")
                    Step(number: 4, title: "长按刚添加的小组件", detail: "点「编辑小组件」，选择要显示的文件夹。")
                } header: {
                    Text("四步放到桌面")
                } footer: {
                    Text("iOS 不允许 App 自己往桌面放东西，这一步只能手动完成，系统每次都会这样。")
                }

                Section("当前存储状态") {
                    LabeledContent("App Group") {
                        Text(model.isSharedStorageAvailable ? "可用" : "不可用")
                            .foregroundStyle(model.isSharedStorageAvailable ? .green : .orange)
                    }
                    LabeledContent("已识别 App") {
                        Text("\(model.installedSchemes.count) 个")
                    }
                }
            }
            .navigationTitle("放到桌面")
        }
    }
}

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

/// The honest version of a privacy policy: say what the app can and cannot see.
struct AboutView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("这个 App 怎么工作") {
                    Text("iOS 不允许第三方 App 替换桌面，所以 AppFolder 用的是小组件：系统唯一允许出现在桌面上、又能显示你自己内容的机制。")
                    Text("点图块时，小组件会把链接交给系统，由系统打开目标 App。AppFolder 自己不会被唤起，也不会在中间闪一下。")
                }

                Section("权限") {
                    LabeledContent("读取已安装 App") {
                        Text("不读取")
                    }
                    LabeledContent("联网") {
                        Text("仅用于拉取 App 图标")
                    }
                    LabeledContent("账号 / 追踪") {
                        Text("无")
                    }
                }

                Section {
                    Text("iOS 没有提供「列出已安装 App」的接口。本 App 的做法是拿一份常见 App 的 URL Scheme 清单逐个询问系统「这个能打开吗」——系统只回答能或不能，不暴露任何其他信息。清单之外的 App 需要手动填写它的链接。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("关于")
        }
    }
}
