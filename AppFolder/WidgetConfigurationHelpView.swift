import AppFolderKit
import SwiftUI

/// A widget link opens a read-only view of the current saved layout. It never
/// executes the tapped item or changes a system configuration or editor draft.
struct WidgetConfigurationHelpView: View {
    let route: SavedGroupHelpRoute
    var onClose: (() -> Void)? = nil
    @State private var group: SavedGroup?
    @State private var failure: ReadFailure?
    @State private var hasRead = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private enum ReadFailure { case unavailable, unreadable, missing }

    var body: some View {
        Group {
            if let group {
                if route.surface == .lockScreen {
                    LockScreenConfigurationHelp(group: group, itemID: route.itemID)
                        .id(group.revision)
                } else {
                    SavedGroupConfigurationDetails(group: group, focusedItemID: route.itemID,
                                                   preferredReportID: route.reportID, isWidgetHelp: true)
                        .id(group.revision)
                }
            } else if hasRead {
                List {
                    Section {
                        Label("无法查看这个分组", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                        switch failure {
                        case .unavailable:
                            Text("共享空间暂时无法读取，请检查 App 的安装后再试。")
                        case .unreadable:
                            Text("这个分组暂时无法读取。请重试，或到「我的分组」检查读取状态。")
                        case .missing, .none:
                            if route.surface == .lockScreen {
                                Text("这个分组已不存在。请编辑锁屏小组件，重新选择项目。")
                            } else {
                                Text("这个分组已不存在，或小组件仍在使用旧的分组。请在「编辑小组件」中重新选择分组。")
                            }
                        }
                    }
                    Section {
                        Button("重新读取", systemImage: "arrow.clockwise", action: reload)
                            .accessibilityIdentifier("widgetHelp.retry")
                        NavigationLink {
                            SavedGroupsView()
                        } label: { Label("我的分组", systemImage: "square.grid.2x2") }
                            .accessibilityIdentifier("widgetHelp.myGroups")
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(route.surface == .lockScreen ? LocalizedStringKey("锁屏启动设置") : LocalizedStringKey("小组件配置检查"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { if let onClose { onClose() } else { dismiss() } }
                    .accessibilityIdentifier("widgetHelp.close")
            }
        }
        .onAppear(perform: reload)
        .onChange(of: route) { _, _ in reload() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
    }

    private func reload() {
        hasRead = true
        switch SavedGroupStore.readResult(id: route.groupID) {
        case .loaded(let current):
            group = current
            failure = nil
        case .unavailable:
            group = nil
            failure = .unavailable
        case .unreadable:
            group = nil
            failure = .unreadable
        case .missing:
            group = nil
            failure = .missing
        }
    }
}

/// A lock-screen widget selects individual leaves; it does not configure the
/// entire saved group or produce the Home Screen's group binding report.
private struct LockScreenConfigurationHelp: View {
    let group: SavedGroup
    let itemID: UUID?
    @State private var copiedName = false

    private var choice: LockScreenItemChoice? {
        itemID.flatMap { LockScreenItemChoice.resolve(.init(groupID: group.id, itemID: $0), in: group) }
    }

    var body: some View {
        List {
            Section("刚才点按的项目") {
                Text(group.name).foregroundStyle(.secondary)
                if let choice {
                    Text(choice.title).font(.headline)
                        .accessibilityIdentifier("lockScreenHelp.focusedItem")
                    if !choice.folderPath.isEmpty {
                        Text(choice.folderPath.joined(separator: " › "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if choice.item.kind == .action {
                        LabeledContent("真实动作名称") { Text(choice.item.name).textSelection(.enabled) }
                        Button {
                            UIPasteboard.general.string = choice.item.name
                            copiedName = true
                        } label: {
                            Label(copiedName ? LocalizedStringKey("已复制动作名称") : LocalizedStringKey("复制动作名称"),
                                  systemImage: copiedName ? "checkmark" : "doc.on.doc")
                        }
                        .accessibilityIdentifier("lockScreenHelp.copyName")
                        Text("请在刚才的小组件的「动作」中检查上方真实名称：缺少时添加，同名有多个时只保留一个。")
                    } else if choice.item.kind == .contact {
                        Text("这个项目是联系人，无需配置系统动作。它会通过 AppFolder 交给对应系统 App 处理。")
                    } else {
                        Text("这个项目是网站，无需配置系统动作。")
                    }
                } else {
                    Text("这个项目已不存在或不能用作锁屏入口，请重新选择。")
                        .accessibilityIdentifier("lockScreenHelp.missingItem")
                }
            }
            Section("设置锁屏启动") {
                Text("长按锁定屏幕，进入「自定」，点按小组件区域，再点按刚才的「锁屏启动」。")
                Text("在「第一个项目」或「第二个项目」中选择已保存分组的项目。圆形只使用第一个项目；矩形最多使用两个项目。")
                Text("仅需配置这一个或两个项目用到的系统动作，分组内其他动作不影响锁屏入口。")
                Text("设备锁定时，启动操作按系统要求解锁。")
            }
            Section {
                Text("这里只显示当前保存的项目，不验证锁屏小组件已配置的系统动作。")
                    .font(.footnote).foregroundStyle(.secondary)
                NavigationLink { SavedGroupsView() } label: {
                    Label("我的分组", systemImage: "square.grid.2x2")
                }
            }
        }
    }
}
