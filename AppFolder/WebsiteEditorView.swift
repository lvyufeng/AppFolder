import AppFolderKit
import SwiftUI
import UIKit

/// Nothing is fetched while typing. The parent accepts one complete draft edit.
struct WebsiteEditorView: View {
    let item: GroupItem?
    let canReplaceIcon: Bool
    let onSave: (String, String, WebsiteBrowser, CustomIcon?) -> Bool
    @State private var name: String
    @State private var address: String
    @State private var browser: WebsiteBrowser
    @AppStorage(WebsiteBrowserSettings.defaultsKey, store: .standard)
    private var browserPreferenceRawValue = WebsiteBrowser.systemDefault.rawValue
    @State private var applicationBrowser = WebsiteBrowserSettings.selectedBrowser()
    @State private var failed = false
    @State private var testFailed = false
    @State private var testFailureMessage: LocalizedStringKey = "系统未能打开这个网址。请检查地址后重试。"
    @State private var testRequestID: UUID?
    @State private var browserPresentationPermitID: UUID?
    @State private var browserRequest: WebsiteBrowserRequest?
    @State private var deferredTestFailure = false
    @State private var isVisible = false
    @State private var isSubmitting = false
    @State private var metadata: WebsiteMetadata?
    @State private var metadataAddress: String?
    @State private var metadataTask: Task<Void, Never>?
    @State private var metadataRequestID: UUID?
    @State private var metadataFailed = false
    @State private var usesWebsiteIcon = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    init(item: GroupItem?, canReplaceIcon: Bool = true,
         onSave: @escaping (String, String, WebsiteBrowser, CustomIcon?) -> Bool) {
        self.item = item
        self.canReplaceIcon = canReplaceIcon
        self.onSave = onSave
        _name = State(initialValue: item?.name ?? "")
        _address = State(initialValue: item?.websiteURL ?? "")
        _browser = State(initialValue: item?.effectiveWebsiteBrowser ?? .systemDefault)
    }

    private var normalized: String? {
        guard address.utf8.count <= WebsiteURL.maximumUTF8Bytes else { return nil }
        return WebsiteURL.normalized(address)
    }
    private var url: URL? { normalized.flatMap(WebsiteURL.validated) }
    private var title: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? url?.host ?? "" : trimmed
    }
    private var validName: Bool {
        title.count <= SavedGroup.maximumNameLength && title.utf8.count <= 512
            && !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    private var canSave: Bool { !isSubmitting && testRequestID == nil && url != nil && !title.isEmpty && validName }
    private var isFetching: Bool { metadataRequestID != nil }
    private var resolvedBrowser: WebsiteBrowser { browser.resolved(using: applicationBrowser) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("网站名称（可选）", text: $name)
                        .accessibilityIdentifier("websiteEditor.name")
                    TextField("网址", text: $address, axis: .vertical)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("websiteEditor.url")
                } footer: {
                    Text("未填写名称时使用网站域名。省略 https:// 时会自动补全；仅支持 HTTP 和 HTTPS 网址。")
                }
                browserSection
                if let normalized {
                    Section {
                        Text(normalized).textSelection(.enabled)
                            .font(.subheadline)
                            .accessibilityIdentifier("websiteEditor.normalizedURL")
                        Button("测试链接", systemImage: "arrow.up.right.square") { testLink() }
                            .disabled(isSubmitting || testRequestID != nil)
                            .accessibilityIdentifier("websiteEditor.test")
                    } header: {
                        Text("将打开")
                    } footer: {
                        Text("测试链接使用当前选择的打开方式；获取网站信息会单独访问网站。输入网址不会发起请求。")
                    }
                } else if !address.isEmpty {
                    Section {
                        Label(address.utf8.count > WebsiteURL.maximumUTF8Bytes
                              ? LocalizedStringKey("网址过长，请使用更短的链接。")
                              : LocalizedStringKey("请输入有效网址，且不要包含用户名或密码。"),
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("websiteEditor.urlError")
                    }
                }
                metadataSection
                if let metadata, metadataAddress == normalized { metadataCandidates(metadata) }
                if !validName {
                    Section {
                        Text("名称未保存。请缩短名称（最多 80 个字符），并移除换行或不支持的字符。")
                            .foregroundStyle(.red)
                    }
                }
                if failed {
                    Section {
                        Text("网站未应用到分组。请检查分组容量和图像是否可用，然后重试。")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("websiteEditor.saveError")
                    }
                }
                Section {
                    Text("网站无需额外配置系统动作。这里的修改在保存分组后应用。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(item == nil ? LocalizedStringKey("添加网站") : LocalizedStringKey("编辑网站"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        invalidateMetadata()
                        invalidateTest()
                        dismiss()
                    }
                    .accessibilityIdentifier("websiteEditor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(item == nil ? LocalizedStringKey("添加") : LocalizedStringKey("应用修改"), action: save)
                        .disabled(!canSave)
                        .accessibilityIdentifier("websiteEditor.save")
                }
            }
            .onChange(of: name) { _, _ in failed = false }
            .onChange(of: address) { _, _ in
                failed = false
                invalidateTest()
                invalidateMetadata()
            }
            .onChange(of: browser) { _, _ in
                failed = false
                invalidateTest()
            }
            .onChange(of: browserPreferenceRawValue) { _, _ in refreshBrowserPreference() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    refreshBrowserPreference()
                    showDeferredTestFailure()
                } else {
                    // Revoke pending presentation without closing an already
                    // visible Safari session during authentication or app switching.
                    browserPresentationPermitID = nil
                    if browserRequest == nil { testRequestID = nil }
                }
            }
            .onAppear {
                isVisible = true
                refreshBrowserPreference()
                showDeferredTestFailure()
            }
            .onDisappear {
                isVisible = false
                // Safari's complete modal presentation hides this editor too.
                // Keep its request and the user's metadata selections while it
                // covers us; dismantling the presenter handles actual removal.
                if browserRequest == nil {
                    testRequestID = nil
                    browserPresentationPermitID = nil
                    invalidateMetadata()
                }
            }
            .background {
                WebsiteBrowserPresenter(request: browserRequest, onDismiss: { id in
                    finishBrowserTest(id: id, failed: false)
                }, onFailure: { id in
                    finishBrowserTest(id: id, failed: true)
                })
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .alert("无法打开链接", isPresented: $testFailed) {
                Button("好", role: .cancel) {}
            } message: {
                Text(testFailureMessage)
            }
        }
    }

    private var browserSection: some View {
        Section {
            Picker("打开方式", selection: $browser) {
                ForEach(WebsiteBrowser.allCases, id: \.self) { value in
                    Text(LocalizedStringKey(value.displayName)).tag(value)
                }
            }
            .disabled(isSubmitting)
            .accessibilityIdentifier("websiteEditor.browser")
            if browser == .appDefault {
                LabeledContent("当前打开方式") {
                    Text(LocalizedStringKey(resolvedBrowser.displayName))
                }
                .accessibilityIdentifier("websiteEditor.resolvedBrowser")
            }
        } footer: {
            if browser == .appDefault {
                Text("先进入 AppFolder，再使用「网站打开设置」中的选择；更改统一设置后，此网站会随之改变。")
            }
            switch resolvedBrowser {
            case .systemDefault:
                Text("使用系统默认浏览器或对应网站的 App 打开。")
            case .inAppSafari:
                Text("点击图块后先进入 AppFolder，再在 App 内浏览网站。")
            case .chrome:
                Text("点击图块后先进入 AppFolder，再交由 Chrome 打开。需要已安装 Chrome。")
            case .firefox:
                Text("点击图块后先进入 AppFolder，再交由 Firefox 打开。需要已安装 Firefox。Firefox 会处理网址参数；复杂或带签名的链接建议使用系统默认。")
            case .appDefault:
                EmptyView()
            }
        }
    }

    private var metadataSection: some View {
        Section {
            if isFetching {
                HStack {
                    ProgressView()
                    Text("正在获取网站信息…")
                    Spacer()
                    Button("取消获取") { invalidateMetadata() }
                        .accessibilityIdentifier("websiteEditor.cancelMetadata")
                }
            } else {
                Button("获取网站信息", systemImage: "arrow.down.doc") { fetchMetadata() }
                    .disabled(url == nil || isSubmitting)
                    .accessibilityIdentifier("websiteEditor.fetchMetadata")
            }
            if metadataFailed {
                Text("暂时无法获取网站信息。请检查网址或网络后重试，也可以继续手动编辑。")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("websiteEditor.metadataError")
            }
        } header: {
            Text("网站信息")
        } footer: {
            Text("仅点击获取时访问这个网站及其图标服务器，不使用浏览器的登录状态。返回信息需由你选择应用。")
        }
    }

    private func metadataCandidates(_ metadata: WebsiteMetadata) -> some View {
        Section {
            if let suggestedName = metadata.title {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: suggestedName)
                        .accessibilityIdentifier("websiteEditor.suggestedName")
                    Button("使用此名称") {
                        guard metadataAddress == normalized, self.metadata?.title == suggestedName else { return }
                        name = suggestedName
                    }
                        .disabled(isSubmitting || name == suggestedName)
                        .accessibilityIdentifier("websiteEditor.useSuggestedName")
                }
            } else {
                Text("未找到可用的网站名称，可以继续手动填写。")
                    .foregroundStyle(.secondary)
            }
            if let icon = metadata.icon {
                HStack(spacing: 12) {
                    CustomIconArtwork(icon: icon, cornerRadius: 12, maxPixelSize: 64)
                        .frame(width: 64, height: 64)
                    Toggle("使用此图标", isOn: $usesWebsiteIcon)
                        .disabled(!canReplaceIcon || isSubmitting)
                        .accessibilityIdentifier("websiteEditor.useSuggestedIcon")
                }
                if canReplaceIcon {
                    Text("使用后替换普通图标，已设置的深色图标保持不变。")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("现有图标暂时无法读取，不能应用网站图标。名称和网址仍可编辑。")
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("websiteEditor.existingIconError")
                }
            } else {
                Text("未找到可用的网站图标，可以继续使用默认或自定义图标。")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("信息来源").font(.caption).foregroundStyle(.secondary)
                Text(verbatim: metadata.finalURL.absoluteString)
                    .font(.caption).textSelection(.enabled)
                if let source = metadata.iconSourceURL, metadata.icon != nil {
                    Text("图标网址").font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: source.absoluteString)
                        .font(.caption).textSelection(.enabled)
                }
            }
        } header: {
            Text("网站提供的信息")
        } footer: {
            Text("获取结果不会更改上方网址。选中的图标在应用修改或添加网站时加入草稿，保存分组后生效。")
        }
    }

    private func fetchMetadata() {
        guard let url, let requestedAddress = normalized, !isSubmitting else { return }
        invalidateMetadata()
        let requestID = UUID()
        metadataRequestID = requestID
        metadataTask = Task { @MainActor in
            defer {
                if metadataRequestID == requestID {
                    metadataRequestID = nil
                    metadataTask = nil
                }
            }
            do {
                let result = try await WebsiteMetadataFetcher.fetch(url)
                guard !Task.isCancelled, metadataRequestID == requestID,
                      normalized == requestedAddress else { return }
                metadata = result
                metadataAddress = requestedAddress
            } catch is CancellationError {
                // A cancelled or superseded request may never replace new data.
            } catch {
                guard !Task.isCancelled, metadataRequestID == requestID,
                      normalized == requestedAddress else { return }
                metadataFailed = true
            }
        }
    }

    private func invalidateMetadata() {
        metadataTask?.cancel()
        metadataTask = nil
        metadataRequestID = nil
        metadata = nil
        metadataAddress = nil
        metadataFailed = false
        usesWebsiteIcon = false
    }

    private func testLink() {
        guard let url, let requestedAddress = normalized, !isSubmitting,
              testRequestID == nil, isVisible, scenePhase == .active else { return }
        let requestID = UUID()
        let requestedChoice = browser
        let requestedBrowser = requestedChoice.resolved(using: WebsiteBrowserSettings.selectedBrowser())
        testFailed = false
        deferredTestFailure = false
        testRequestID = requestID
        if requestedBrowser == .inAppSafari {
            browserPresentationPermitID = requestID
            browserRequest = WebsiteBrowserRequest(id: requestID, url: url) {
                browserPresentationPermitID == requestID && testRequestID == requestID
                    && isVisible && !isSubmitting && scenePhase == .active
                    && normalized == requestedAddress && browser == requestedChoice
                    && requestedChoice.resolved(using: WebsiteBrowserSettings.selectedBrowser()) == requestedBrowser
            }
            return
        }
        guard let destination = requestedBrowser.externalURL(for: url) else {
            finishExternalTest(id: requestID, choice: requestedChoice, browser: requestedBrowser,
                               address: requestedAddress, accepted: false)
            return
        }
        if requestedBrowser == .systemDefault {
            openURL(destination) { accepted in
                finishExternalTest(id: requestID, choice: requestedChoice, browser: requestedBrowser,
                                   address: requestedAddress, accepted: accepted)
            }
        } else {
            UIApplication.shared.open(destination, options: [:]) { accepted in
                Task { @MainActor in
                    finishExternalTest(id: requestID, choice: requestedChoice, browser: requestedBrowser,
                                       address: requestedAddress, accepted: accepted)
                }
            }
        }
    }

    private func finishExternalTest(id: UUID, choice requestedChoice: WebsiteBrowser, browser requestedBrowser: WebsiteBrowser,
                                    address requestedAddress: String, accepted: Bool) {
        guard testRequestID == id, isVisible, browser == requestedChoice,
              requestedChoice.resolved(using: WebsiteBrowserSettings.selectedBrowser()) == requestedBrowser,
              normalized == requestedAddress else { return }
        testRequestID = nil
        guard !accepted else { return }
        switch requestedBrowser {
        case .chrome:
            testFailureMessage = "无法在 Chrome 中打开网址。请确认已安装 Chrome，或选择其他打开方式后重试。"
        case .firefox:
            testFailureMessage = "无法在 Firefox 中打开网址。请确认已安装 Firefox，或选择其他打开方式后重试。"
        case .systemDefault, .inAppSafari, .appDefault:
            testFailureMessage = "系统未能打开这个网址。请检查地址后重试。"
        }
        testFailed = true
    }

    private func finishBrowserTest(id: UUID, failed: Bool) {
        guard testRequestID == id, browserRequest?.id == id else { return }
        testRequestID = nil
        browserPresentationPermitID = nil
        browserRequest = nil
        if failed {
            testFailureMessage = "暂时无法在 App 内打开网址。请重试，或选择其他打开方式。"
            deferredTestFailure = true
            showDeferredTestFailure()
        }
    }

    private func showDeferredTestFailure() {
        guard deferredTestFailure, isVisible, scenePhase == .active else { return }
        deferredTestFailure = false
        testFailed = true
    }

    private func refreshBrowserPreference() {
        let selected = WebsiteBrowserSettings.selectedBrowser()
        guard applicationBrowser != selected else { return }
        applicationBrowser = selected
        guard browser == .appDefault else { return }
        // A pending test may not open the old preference. An already visible
        // Safari session stays open and is released by its normal callback.
        browserPresentationPermitID = nil
        if browserRequest == nil { testRequestID = nil }
    }

    private func invalidateTest() {
        testRequestID = nil
        browserPresentationPermitID = nil
        browserRequest = nil
        deferredTestFailure = false
        testFailed = false
    }

    private func save() {
        guard !isSubmitting else { return }
        guard canSave, let normalized else { failed = true; return }
        // Keep this latched after success while the sheet is dismissing. A
        // second tap can arrive before SwiftUI removes the toolbar button.
        isSubmitting = true
        // Stop an in-flight lookup, but keep an already selected candidate if
        // the parent rejects the edit so the same complete draft can be retried.
        metadataTask?.cancel()
        metadataTask = nil
        metadataRequestID = nil
        let icon = canReplaceIcon && usesWebsiteIcon && metadataAddress == normalized ? metadata?.icon : nil
        guard onSave(title, normalized, browser, icon) else {
            isSubmitting = false
            failed = true
            return
        }
        dismiss()
    }
}
