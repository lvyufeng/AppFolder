import AppFolderKit
import SwiftUI
import UIKit

/// The external route contains IDs only. A current, validated local contact is
/// reread before handing anything to the system. FaceTime always needs a tap in
/// this view because its native URL may start a call without a system prompt.
struct ContactLaunchView: View {
    let route: ContactLaunchRoute
    let automaticLaunchPermission: AutomaticContactLaunchPermission
    let receivedAt: ContinuousClock.Instant
    let onClose: () -> Void
    @State private var contact: GroupItem?
    @State private var hasLoaded = false
    @State private var launchGuard = ContactLaunchGuard()
    @State private var wasOpened = false
    @State private var message: LocalizedStringKey?
    @State private var openingTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            if let contact, let target = contact.contactTarget {
                Section {
                    Label(contact.name, systemImage: target.operation.systemImage)
                        .font(.headline)
                    Text(verbatim: target.number).textSelection(.enabled)
                        .accessibilityIdentifier("contactLaunch.number")
                    Text(operationTitle(target.operation))
                    switch target.operation {
                    case .phone: Text("拨号前由系统确认。")
                    case .message: Text("将在信息中编写消息，发送前仍需你确认。")
                    case .faceTimeAudio, .faceTimeVideo: Text("点击开始后将发起 FaceTime 通话。")
                    }
                }
                Section {
                    if launchGuard.isOpening { ProgressView("正在打开…") }
                    else if wasOpened { Text("已交给系统处理。") }
                    if let message { Text(message).foregroundStyle(.secondary) }
                    Button { openContact(automatically: false) } label: {
                        Label(buttonTitle(target.operation), systemImage: target.operation.systemImage)
                    }
                    .disabled(launchGuard.isOpening || scenePhase != .active)
                    .accessibilityIdentifier("contactLaunch.start")
                }
            } else if hasLoaded {
                Section {
                    Label("联系人暂不可用", systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(.headline)
                    Text("请重新读取，或在「我的分组」中检查这个联系人。")
                    Button("重新读取", systemImage: "arrow.clockwise") {
                        launchGuard.disableAutomatic()
                        Task { await reload() }
                    }
                    .accessibilityIdentifier("contactLaunch.retry")
                }
            } else {
                ProgressView()
            }
        }
        .privacySensitive()
        .navigationTitle("联系此人")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") {
                    launchGuard.disappeared()
                    openingTask?.cancel()
                    onClose()
                }
                .accessibilityIdentifier("contactLaunch.close")
            }
        }
        .task {
            launchGuard.appeared(isActive: scenePhase == .active)
            await reload()
            attemptInitialLaunch()
        }
        .onChange(of: scenePhase) { _, phase in
            launchGuard.sceneChanged(isActive: phase == .active, isBackground: phase == .background)
            if phase == .active { attemptInitialLaunch() }
        }
        .onDisappear {
            launchGuard.disappeared()
            openingTask?.cancel()
        }
    }

    private func reload() async {
        let route = route
        let result = await Task.detached(priority: .userInitiated) {
            SavedGroupStore.readResult(id: route.groupID)
        }.value
        guard !Task.isCancelled, launchGuard.isVisible else { return }
        if case .loaded(let group) = result { contact = route.resolve(in: group) }
        else { contact = nil }
        hasLoaded = true
    }

    private func attemptInitialLaunch() {
        guard hasLoaded else { return }
        guard contact?.contactTarget != nil else {
            launchGuard.disableAutomatic()
            return
        }
        openContact(automatically: true)
    }

    private func openContact(automatically: Bool) {
        guard let displayed = contact, let target = displayed.contactTarget else { return }
        // Claim synchronously, before reading or yielding. A second tap and a
        // scene callback cannot start another system request in parallel.
        guard let attempt = launchGuard.begin(
            operation: target.operation,
            automatically: automatically,
            automaticAllowed: automaticLaunchPermission.isAllowed,
            age: receivedAt.duration(to: ContinuousClock().now),
            isActive: scenePhase == .active
        ) else { return }
        wasOpened = false
        message = nil
        let route = route
        openingTask = Task { @MainActor in
            defer { launchGuard.finish(attempt); openingTask = nil }
            let result = await Task.detached(priority: .userInitiated) {
                SavedGroupStore.readResult(id: route.groupID)
            }.value
            guard !Task.isCancelled, launchGuard.isVisible else { return }
            guard case .loaded(let group) = result, let current = route.resolve(in: group),
                  let currentTarget = current.contactTarget else {
                contact = nil
                hasLoaded = true
                return
            }
            guard current.name == displayed.name, currentTarget == target else {
                contact = current
                message = "联系人已更新，请确认后再继续。"
                return
            }
            guard !automatically || automaticLaunchPermission.isAllowed,
                  launchGuard.canOpen(
                attempt,
                age: receivedAt.duration(to: ContinuousClock().now),
                isActive: scenePhase == .active
            ) else { return }
            let opened = await UIApplication.shared.open(currentTarget.url, options: [:])
            guard !Task.isCancelled, launchGuard.isVisible else { return }
            wasOpened = opened
            if !opened { message = "无法打开此操作。请检查这台设备是否支持，并确认对应 App 可用。" }
        }
    }

    private func operationTitle(_ operation: ContactTarget.Operation) -> LocalizedStringKey {
        switch operation {
        case .phone: "电话"
        case .message: "短信"
        case .faceTimeAudio: "FaceTime 语音"
        case .faceTimeVideo: "FaceTime 视频"
        }
    }

    private func buttonTitle(_ operation: ContactTarget.Operation) -> LocalizedStringKey {
        switch operation {
        case .phone: "拨打电话"
        case .message: "编写短信"
        case .faceTimeAudio: "开始 FaceTime 语音"
        case .faceTimeVideo: "开始 FaceTime 视频"
        }
    }
}
