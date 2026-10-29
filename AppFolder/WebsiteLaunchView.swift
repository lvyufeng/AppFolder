import AppFolderKit
import SwiftUI
import UIKit

/// Non-default widget routes carry IDs only. Read the saved website again before
/// opening so an old widget cannot supply a stale URL or browser preference.
struct WebsiteLaunchView: View {
    let route: WebsiteLaunchRoute
    let automaticLaunchPermission: AutomaticWebsiteLaunchPermission
    let receivedAt: ContinuousClock.Instant
    let onClose: () -> Void
    @State private var website: GroupItem?
    @State private var displayedResolvedBrowser: WebsiteBrowser = .systemDefault
    @State private var hasLoaded = false
    @State private var launchGuard = WebsiteLaunchGuard()
    @State private var openingTask: Task<Void, Never>?
    @State private var browserRequest: WebsiteBrowserRequest?
    @State private var browserAttempt: WebsiteLaunchGuard.Attempt?
    @State private var browserWasAutomatic = false
    @State private var wasOpened = false
    @State private var externalOpenFailed = false
    @State private var message: LocalizedStringKey?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            if let website, let address = website.websiteURL,
               WebsiteURL.validated(address) != nil {
                Section {
                    Label(website.displayTitle, systemImage: "globe")
                        .font(.headline)
                    Text(verbatim: address).textSelection(.enabled)
                        .accessibilityIdentifier("websiteLaunch.address")
                    LabeledContent("打开方式") {
                        Text(LocalizedStringKey(website.effectiveWebsiteBrowser.displayName))
                    }
                    .accessibilityIdentifier("websiteLaunch.browser")
                    if website.effectiveWebsiteBrowser == .appDefault {
                        LabeledContent("当前打开方式") {
                            Text(LocalizedStringKey(displayedResolvedBrowser.displayName))
                        }
                        .accessibilityIdentifier("websiteLaunch.resolvedBrowser")
                    }
                }
                Section {
                    if launchGuard.isOpening { ProgressView("正在打开…") }
                    else if wasOpened { Text("已交给系统处理。") }
                    if let message { Text(message).foregroundStyle(.secondary) }
                    Button("打开网站", systemImage: "globe") {
                        openWebsite(automatically: false)
                    }
                    .disabled(launchGuard.isOpening || scenePhase != .active)
                    .accessibilityIdentifier("websiteLaunch.open")
                    if externalOpenFailed && displayedResolvedBrowser != .systemDefault {
                        Button("使用系统默认方式打开", systemImage: "arrow.up.forward.app") {
                            openWebsite(automatically: false, useSystemDefault: true)
                        }
                        .disabled(launchGuard.isOpening || scenePhase != .active)
                        .accessibilityIdentifier("websiteLaunch.openDefault")
                    }
                }
            } else if hasLoaded {
                Section {
                    Label("网站暂不可用", systemImage: "globe.badge.chevron.backward")
                        .font(.headline)
                    Text("请重新读取，或在「我的分组」中检查这个网站。")
                    Button("重新读取", systemImage: "arrow.clockwise") {
                        launchGuard.disableAutomatic()
                        Task { await reload() }
                    }
                    .accessibilityIdentifier("websiteLaunch.retry")
                }
            } else {
                ProgressView()
            }
        }
        .privacySensitive()
        .navigationTitle("打开网站")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") {
                    launchGuard.disappeared()
                    openingTask?.cancel()
                    browserRequest = nil
                    onClose()
                }
                .accessibilityIdentifier("websiteLaunch.close")
            }
        }
        .background {
            WebsiteBrowserPresenter(request: browserRequest, onDismiss: { id in
                completeBrowser(id, failed: false)
            }, onFailure: { id in
                completeBrowser(id, failed: true)
            })
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
            // Safari's complete modal covers this view. Keep that one request
            // alive until Safari reports dismissal; it cannot launch twice.
            if browserRequest == nil {
                launchGuard.disappeared()
                openingTask?.cancel()
            }
        }
    }

    private func reload() async {
        let route = route
        let result = await Task.detached(priority: .userInitiated) {
            SavedGroupStore.readResult(id: route.groupID)
        }.value
        guard !Task.isCancelled, launchGuard.isVisible else { return }
        if case .loaded(let group) = result {
            website = route.resolve(in: group)
            if let website { displayedResolvedBrowser = resolvedBrowser(for: website) }
        } else {
            website = nil
        }
        hasLoaded = true
    }

    private func attemptInitialLaunch() {
        guard hasLoaded else { return }
        guard website?.websiteURL.flatMap(WebsiteURL.validated) != nil else {
            launchGuard.disableAutomatic()
            return
        }
        openWebsite(automatically: true)
    }

    private func openWebsite(automatically: Bool, useSystemDefault: Bool = false) {
        guard let displayed = website, let displayedAddress = displayed.websiteURL,
              WebsiteURL.validated(displayedAddress) != nil else { return }
        let displayedBrowser = displayedResolvedBrowser
        guard let attempt = launchGuard.begin(
            automatically: automatically, automaticAllowed: automaticLaunchPermission.isAllowed,
            age: receivedAt.duration(to: ContinuousClock().now), isActive: scenePhase == .active
        ) else { return }
        wasOpened = false
        externalOpenFailed = false
        message = nil
        let route = route
        openingTask = Task { @MainActor in
            defer {
                if browserAttempt != attempt { launchGuard.finish(attempt) }
                openingTask = nil
            }
            let result = await Task.detached(priority: .userInitiated) {
                SavedGroupStore.readResult(id: route.groupID)
            }.value
            guard !Task.isCancelled, launchGuard.isVisible else { return }
            guard case .loaded(let group) = result, let current = route.resolve(in: group),
                  let address = current.websiteURL, let url = WebsiteURL.validated(address) else {
                website = nil
                hasLoaded = true
                return
            }
            let currentBrowser = resolvedBrowser(for: current)
            guard current.name == displayed.name, address == displayedAddress,
                  current.effectiveWebsiteBrowser == displayed.effectiveWebsiteBrowser else {
                website = current
                displayedResolvedBrowser = currentBrowser
                externalOpenFailed = useSystemDefault
                message = "网站已更新，请确认后再继续。"
                return
            }
            // A local default can change without changing the saved website.
            // Keep the displayed choice as the confirmation boundary instead
            // of silently opening whichever browser became the latest default.
            guard currentBrowser == displayedBrowser else {
                displayedResolvedBrowser = currentBrowser
                externalOpenFailed = useSystemDefault
                message = "网站打开方式已更新，请确认后再继续。"
                return
            }
            guard !automatically || automaticLaunchPermission.isAllowed,
                  launchGuard.canOpen(attempt, age: receivedAt.duration(to: ContinuousClock().now),
                                      isActive: scenePhase == .active) else { return }
            let selectedBrowser: WebsiteBrowser = useSystemDefault ? .systemDefault : currentBrowser
            if selectedBrowser == .inAppSafari {
                browserAttempt = attempt
                browserWasAutomatic = automatically
                browserRequest = WebsiteBrowserRequest(url: url) {
                    (!automatically || automaticLaunchPermission.isAllowed)
                        && launchGuard.canOpen(attempt, age: receivedAt.duration(to: ContinuousClock().now),
                                               isActive: scenePhase == .active)
                        && resolvedBrowser(for: current) == selectedBrowser
                }
                return
            }
            guard let destination = selectedBrowser.externalURL(for: url) else {
                externalOpenFailed = true
                message = "无法打开所选浏览器。请确认已安装，或使用系统默认方式打开。"
                return
            }
            let opened = await UIApplication.shared.open(destination, options: [:])
            guard !Task.isCancelled, launchGuard.isVisible else { return }
            wasOpened = opened
            externalOpenFailed = !opened
            if !opened {
                message = selectedBrowser == .systemDefault
                    ? "无法打开此网站，请检查网址或设备设置。"
                    : "无法打开所选浏览器。请确认已安装，或使用系统默认方式打开。"
            }
        }
    }

    private func completeBrowser(_ id: UUID, failed: Bool) {
        guard browserRequest?.id == id else { return }
        if let attempt = browserAttempt { launchGuard.finish(attempt) }
        browserAttempt = nil
        browserRequest = nil
        if failed {
            externalOpenFailed = !browserWasAutomatic
            if let website {
                let currentBrowser = resolvedBrowser(for: website)
                displayedResolvedBrowser = currentBrowser
                if currentBrowser != .inAppSafari {
                    message = "网站打开方式已更新，请确认后再继续。"
                    return
                }
            }
            message = browserWasAutomatic ? "请点击打开网站继续。" : "暂时无法打开内置浏览器，请重试。"
        }
    }

    /// Only opted-in websites follow the device-local app setting. Explicit
    /// system-default and concrete-browser records preserve their own choice.
    private func resolvedBrowser(for item: GroupItem) -> WebsiteBrowser {
        item.effectiveWebsiteBrowser.resolved(using: WebsiteBrowserSettings.selectedBrowser())
    }
}
