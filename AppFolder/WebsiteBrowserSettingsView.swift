import AppFolderKit
import SwiftUI

/// This preference stays on this device and changes no saved website choices.
struct WebsiteBrowserSettingsView: View {
    @AppStorage(WebsiteBrowserSettings.defaultsKey, store: .standard)
    private var browserPreferenceRawValue = WebsiteBrowser.systemDefault.rawValue
    @State private var selectedBrowser = WebsiteBrowserSettings.selectedBrowser()
    @State private var didSave = false
    @State private var saveFailed = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section {
                Picker("统一打开方式", selection: Binding(get: { selectedBrowser }, set: save)) {
                    ForEach(WebsiteBrowser.concreteCases, id: \.self) { browser in
                        Text(LocalizedStringKey(browser.displayName)).tag(browser)
                    }
                }
                .accessibilityIdentifier("websiteBrowserSettings.browser")
            } footer: {
                Text("仅影响明确选择「跟随 App 设置」的网站。其他网站保持各自设置，新建网站仍默认使用系统默认方式。")
            }

            Section {
                switch selectedBrowser {
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
            .font(.footnote).foregroundStyle(.secondary)

            if didSave {
                Section {
                    Label("已保存。跟随 App 设置的网站会在下次打开时使用此选择。", systemImage: "checkmark.circle")
                        .accessibilityIdentifier("websiteBrowserSettings.saved")
                }
            }
            if saveFailed {
                Section {
                    Text("打开方式未保存，请重试。")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("websiteBrowserSettings.saveError")
                }
            }
            Section {
                Text("统一选择只保存在这台设备上；备份保留网站的跟随选择，导入后使用目标设备的统一设置。切换设置不会打开网站、联网或检查已安装的浏览器。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("网站打开设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .onChange(of: browserPreferenceRawValue) { _, _ in refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
    }

    private func save(_ browser: WebsiteBrowser) {
        guard browser != selectedBrowser else { return }
        guard WebsiteBrowserSettings.setBrowser(browser) else {
            didSave = false
            saveFailed = true
            return
        }
        selectedBrowser = WebsiteBrowserSettings.selectedBrowser()
        saveFailed = false
        didSave = true
        // Following websites already route through the host, which reads this
        // setting on tap. A timeline refresh could trigger unrelated icon fetches.
    }

    private func refresh() {
        let current = WebsiteBrowserSettings.selectedBrowser()
        if selectedBrowser != current {
            selectedBrowser = current
            didSave = false
            saveFailed = false
        }
    }
}
