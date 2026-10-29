import AppFolderKit
import Combine
import SwiftUI
import UIKit

/// Principal class for com.apple.share-services. The extension only enqueues a
/// website; the containing app owns all group editing and widget changes.
@MainActor
final class ShareViewController: UIViewController {
    private let model = ShareWebsiteModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareWebsiteView(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        model.start(context: extensionContext)
    }
}

@MainActor
private final class ShareWebsiteModel: ObservableObject {
    enum Phase: Equatable { case loading, ready, inputFailure, saved }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var address: String?
    @Published private(set) var inputError: SharedWebsiteInputError?
    @Published private(set) var saveError: ShareInboxError?
    @Published private(set) var isSaving = false
    @Published var title = ""

    private var context: NSExtensionContext?
    private var loadingProgress: Progress?
    private var generation = UUID()
    private var isFinished = false

    var validTitle: Bool {
        title.utf8.count <= ShareInboxStore.maximumTitleUTF8Bytes
            && title.trimmingCharacters(in: .whitespacesAndNewlines).count <= ShareInboxStore.maximumTitleCharacters
            && !title.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    var canSave: Bool {
        phase == .ready && address != nil && validTitle && !isSaving && !isFinished
    }

    func start(context: NSExtensionContext?) {
        guard self.context == nil, !isFinished else { return }
        self.context = context
        loadURL()
    }

    func retryLoading() {
        guard phase == .inputFailure, inputError == .loadingFailed, !isFinished else { return }
        loadURL()
    }

    private func loadURL() {
        generation = UUID()
        loadingProgress?.cancel()
        loadingProgress = nil
        phase = .loading
        inputError = nil
        address = nil
        let token = generation
        do {
            let provider = try SharedWebsiteInput.provider(in: context?.inputItems ?? [])
            // The callback runs on a provider queue. Only Sendable values cross
            // to MainActor, and a cancelled/older callback cannot change state.
            loadingProgress = provider.loadObject(ofClass: URL.self) { [weak self] url, error in
                let result: Result<String, SharedWebsiteInputError>
                if error != nil {
                    result = .failure(.loadingFailed)
                } else {
                    do {
                        result = .success(try SharedWebsiteInput.validatedAddress(url?.absoluteString))
                    } catch {
                        result = .failure(.invalidURL)
                    }
                }
                Task { @MainActor [weak self] in
                    self?.receive(result, generation: token)
                }
            }
        } catch let error as SharedWebsiteInputError {
            receive(.failure(error), generation: token)
        } catch {
            receive(.failure(.loadingFailed), generation: token)
        }
    }

    private func receive(_ result: Result<String, SharedWebsiteInputError>, generation token: UUID) {
        guard !isFinished, generation == token, phase == .loading else { return }
        loadingProgress = nil
        switch result {
        case let .success(address):
            self.address = address
            phase = .ready
        case let .failure(error):
            inputError = error
            phase = .inputFailure
        }
    }

    func save() {
        guard canSave, let address else { return }
        // Latch before the bounded local write. Enqueue takes a nonblocking
        // cross-process lock, so there is no detached write left after Cancel.
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            let saved = try ShareInboxStore.enqueue(url: address, title: title)
            title = saved.title ?? ""
            phase = .saved
        } catch let error as ShareInboxError {
            saveError = error
        } catch {
            saveError = .storageFailure
        }
    }

    func cancel() {
        guard !isFinished, phase != .saved, !isSaving else { return }
        isFinished = true
        invalidateLoading()
        context?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    func complete() {
        guard !isFinished, phase == .saved else { return }
        isFinished = true
        invalidateLoading()
        context?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func invalidateLoading() {
        generation = UUID()
        loadingProgress?.cancel()
        loadingProgress = nil
    }
}

private struct ShareWebsiteView: View {
    @ObservedObject var model: ShareWebsiteModel

    var body: some View {
        NavigationStack {
            Form {
                switch model.phase {
                case .loading:
                    Section {
                        ProgressView("正在读取共享网址…")
                            .accessibilityIdentifier("webShare.loading")
                    }
                case .inputFailure:
                    inputFailureSection
                case .ready:
                    Section {
                        Text("保存到待添加列表，再打开 AppFolder 选择分组。")
                            .accessibilityIdentifier("webShare.instructions")
                    }
                    addressSection
                    Section {
                        TextField("网站名称（可选）", text: $model.title, axis: .vertical)
                            .lineLimit(1...4)
                            .submitLabel(.done)
                            .accessibilityIdentifier("webShare.title")
                    } footer: {
                        Text("留空使用网站域名。名称最多 80 个字符。")
                    }
                    if !model.validTitle {
                        Section {
                            Text("请缩短名称，并移除换行或不支持的字符。")
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("webShare.titleError")
                        }
                    }
                    if let error = model.saveError {
                        Section {
                            Text(saveErrorMessage(error))
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("webShare.saveError")
                        }
                    }
                case .saved:
                    Section {
                        Label("已保存到待添加列表", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityIdentifier("webShare.saved")
                        Text("完成后请自行打开 AppFolder，进入「我的分组」→「待添加网页」，选择分组添加。")
                            .accessibilityIdentifier("webShare.nextStep")
                    }
                    addressSection
                    if !model.title.isEmpty {
                        Section("网站名称") {
                            Text(verbatim: model.title)
                                .accessibilityIdentifier("webShare.savedTitle")
                        }
                    }
                }
            }
            .navigationTitle("保存网页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.phase == .saved {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成", action: model.complete)
                            .accessibilityIdentifier("webShare.done")
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消", action: model.cancel)
                            .disabled(model.isSaving)
                            .accessibilityIdentifier("webShare.cancel")
                    }
                    if model.phase == .ready {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存", action: model.save)
                                .disabled(!model.canSave)
                                .accessibilityIdentifier("webShare.save")
                        }
                    }
                }
            }
        }
    }

    private var addressSection: some View {
        Section {
            if let address = model.address {
                Text(verbatim: address)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityIdentifier("webShare.url")
            }
        } header: {
            Text("网址")
        } footer: {
            Text("仅保存网址，不会读取或下载网页内容。")
        }
    }

    private var inputFailureSection: some View {
        Section {
            Text(inputErrorMessage(model.inputError))
                .foregroundStyle(.red)
                .accessibilityIdentifier("webShare.inputError")
            if model.inputError == .loadingFailed {
                Button("重试", systemImage: "arrow.clockwise", action: model.retryLoading)
                    .accessibilityIdentifier("webShare.retry")
            }
        } footer: {
            Text("请从浏览器的分享菜单发送一个 HTTP 或 HTTPS 网址。")
        }
    }

    private func inputErrorMessage(_ error: SharedWebsiteInputError?) -> LocalizedStringKey {
        switch error {
        case .missingURL: "没有收到网址。仅支持网址分享，无法从文本或文件中提取链接。"
        case .multipleURLs: "一次只能保存一个网址。请只选择一个网页后重试。"
        case .invalidURL: "这个网址无法保存。仅支持不含用户名或密码的有效 HTTP 或 HTTPS 网址。"
        case .loadingFailed, nil: "未能读取共享网址。请重试，或返回浏览器重新分享。"
        }
    }

    private func saveErrorMessage(_ error: ShareInboxError) -> LocalizedStringKey {
        switch error {
        case .unavailable: "无法访问待添加列表。请打开 AppFolder 检查后重新分享。"
        case .full: "待添加列表已满。请先在 AppFolder 中添加或删除部分网址，再重试。"
        case .busy: "待添加列表正在使用中。请稍后重试。"
        case .invalidTitle: "请缩短名称，并移除换行或不支持的字符。"
        case .invalidURL: "这个网址无法保存。仅支持不含用户名或密码的有效 HTTP 或 HTTPS 网址。"
        case .storageFailure, .recordTooLarge, .recordAlreadyExists: "网址尚未保存。请检查设备可用空间，然后重试。"
        }
    }
}
