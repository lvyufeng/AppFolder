import AppFolderKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The share-extension entry point.
///
/// ## What this exists to do
///
/// The Home Screen offers 分享 App on an app's long-press menu, and what it hands
/// over is an App Store link — not the app. That link carries the track id, and a
/// track id resolves through ``AppCatalog/entry(appStoreID:)`` to a *verified*
/// launch scheme. So a share is enough to build a working tile, with no typing and
/// no search.
///
/// This is the one step the clipboard path could not do: sharing the app offered
/// no "拷贝" action, so there was nothing for the app to read.
///
/// ## Why the UI is a folder picker and not a confirmation
///
/// The extension cannot open AppFolder. `UIApplication.shared` is unavailable in
/// an extension — the SDK marks the whole type
/// `NS_EXTENSION_UNAVAILABLE_IOS` — so it cannot launch `appfolder://` to hand the
/// work back. Everything the user needs to decide has to happen here; the app
/// picks the result up on next launch. That is why this shows the folder list
/// rather than a "已添加" toast.
///
/// ## Why it does not write the library
///
/// It deposits into ``PendingImportStore`` instead. The app is the only writer of
/// `library.json`; a second writer would race it. See ``PendingImport``.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        // The URL, lifted off the extension context before any UI exists, so the
        // picker never has to know how the payload arrived.
        loadSharedLink { [weak self] link in
            guard let self else { return }
            Task { @MainActor in
                self.present(link)
            }
        }
    }

    @MainActor
    private func present(_ link: AppStoreLink?) {
        let root = ShareRootView(
            link: link,
            onDone: { [weak self] in self?.finish() },
            onCancel: { [weak self] in self?.cancel() }
        )
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "AppFolder", code: 0))
    }

    /// Pulls the first App Store link out of whatever was shared.
    ///
    /// The provider may vend a `URL` or a `String` for the same link — which one
    /// depends on where the share came from — so both are tried. Anything that is
    /// not an App Store app link resolves to `nil`, and the UI says so rather than
    /// pretending.
    ///
    /// The completion runs off the main actor because `NSItemProvider`'s loading
    /// is; the caller hops back explicitly.
    private func loadSharedLink(completion: @escaping (AppStoreLink?) -> Void) {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let attachments = items.flatMap { $0.attachments ?? [] }
        let urlType = UTType.url.identifier
        let textType = UTType.plainText.identifier

        guard let provider = attachments.first(where: {
            $0.hasItemConformingToTypeIdentifier(urlType) || $0.hasItemConformingToTypeIdentifier(textType)
        }) else {
            completion(nil)
            return
        }

        if provider.hasItemConformingToTypeIdentifier(urlType) {
            provider.loadItem(forTypeIdentifier: urlType, options: nil) { item, _ in
                let url = (item as? URL) ?? (item as? String).flatMap(URL.init(string:))
                completion(url.flatMap(AppStoreLink.parse))
            }
        } else {
            provider.loadItem(forTypeIdentifier: textType, options: nil) { item, _ in
                completion((item as? String).flatMap(AppStoreLink.parseFirst(in:)))
            }
        }
    }
}