import AppFolderKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Turns a shared App Store link into a tile.
///
/// ## The flow this serves
///
/// On the Home Screen, long-press an app → 分享 App → 拷贝. iOS copies an App
/// Store link (`https://apps.apple.com/app/id414478124`), not the app. Bring that
/// link here and it becomes a tile: the link's track id resolves through
/// ``AppCatalog/entry(appStoreID:)`` to a **verified** scheme for anything in the
/// catalogue, and to a looked-up app plus a scheme guess for anything else.
///
/// This is the cheap half of a share-extension design. It costs one extra tap
/// (switch back to AppFolder) compared with a real Share Extension, and in return
/// it needs no new target, no pbxproj surgery, and no签名 work — and it exercises
/// the same parser and the same catalogue lookup, so it is what tells us whether
/// the expensive version is worth building.
///
/// ## Why the paste button and not an automatic read
///
/// Reading the pasteboard programmatically — `UIPasteboard.general.string` — shows
/// the system's "已粘贴 / 来自…" banner every single time. For a feature whose whole
/// selling point is *fewer steps*, a banner asking for permission to do the thing
/// the user just asked for is the wrong trade.
///
/// Two primitives avoid it, and both are used here:
///
/// * ``UIPasteboard/detectedValues(for:)`` reads only *detected links*, which iOS
///   does not gate behind the banner. So the screen can show "检测到一个 App Store
///   链接" on its own, with no permission prompt.
/// * ``SwiftUI/PasteButton`` is the sanctioned user-initiated paste. It never
///   shows the banner because the tap *is* the consent.
///
/// ## The App icon
///
/// The catalogue knows a handful of apps have no App Store artwork — Apple's own
/// apps, which do not ship through the store. For those the link still resolves
/// (a system app has an App Store page) but the fetched icon is blank, and the
/// screen draws the catalogue's SF Symbol instead, matching what the tile itself
/// will show. See ``KnownApp/symbolName``.
struct SharedLinkIntakeView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// The link's own region, when it carried one — a hint for the lookup.
    @State private var detected: AppStoreLink?
    /// The clipboard's first detected link, used only to decide whether to offer
    /// the big paste button. Never read as text, so no banner.
    @State private var clipboardLink: AppStoreLink?
    @State private var resolved: AppStoreLookup?
    @State private var catalogEntry: KnownApp?
    @State private var isResolving = false
    /// Set when the resolver ran and the id did not resolve anywhere.
    @State private var didFailLookup = false

    let onPick: (FolderTile) -> Void

    var body: some View {
        NavigationStack {
            Form {
                if let entry = catalogEntry {
                    catalogSection(entry)
                } else if let resolved {
                    strangerSection(resolved)
                }

                pasteSection
                manualSection
            }
            .navigationTitle("从分享添加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                if let entry = catalogEntry {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("添加") {
                            onPick(FolderTile(app: entry))
                            dismiss()
                        }
                    }
                }
            }
            .task { await readClipboardHint() }
        }
    }

    // MARK: - Sections

    /// The happy path: the shared app is one the catalogue already knows, so its
    /// scheme is verified and there is nothing else to ask.
    @ViewBuilder
    private func catalogSection(_ entry: KnownApp) -> some View {
        Section {
            HStack(spacing: 12) {
                // Symbol first, because for the catalogue's icon-less entries the
                // fetched artwork is blank — drawing it as a hole would misreport
                // what the tile is about to look like.
                AppIconView(appStoreID: entry.appStoreID, symbolName: entry.symbolName ?? "app.dashed")
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                    Text(entry.scheme)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("目录里已经有这个 App")
        } footer: {
            Text("启动链接是验证过的，直接加就行。")
        }
    }

    /// The escape hatch: a real app the catalogue does not hold. Its scheme is not
    /// known, so this hands off to the scheme screen rather than pretending.
    @ViewBuilder
    private func strangerSection(_ lookup: AppStoreLookup) -> some View {
        Section {
            HStack(spacing: 12) {
                AppIconView(appStoreID: lookup.trackID, symbolName: "app.dashed")
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lookup.name)
                    if let seller = lookup.sellerName {
                        Text(seller)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 4)

            // One tap from here now covers the whole job. The destination reads
            // the bundle id off ``AppStoreLookup``, derives its own candidates,
            // and hands back a tile — so the share path no longer needs a
            // throwaway tile of its own just to reach this screen.
            NavigationLink {
                SchemeEntryView(lookup: lookup, title: lookup.name) { tile in
                    onPick(tile)
                    dismiss()
                }
            } label: {
                Label("确认启动链接", systemImage: "link")
            }
        } header: {
            Text("不在目录里")
        } footer: {
            Text("这个 App 目录里没有，需要你确认一下启动链接才能加。")
        }
    }

    @ViewBuilder
    private var pasteSection: some View {
        Section {
            if isResolving {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在识别…").foregroundStyle(.secondary)
                }
            } else if detected != nil {
                Label("已识别到一个 App Store 链接", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            } else if didFailLookup {
                Label("这个链接在 App Store 上查不到", systemImage: "questionmark.circle")
                    .foregroundStyle(.orange)
            }

            // The sanctioned paste: the tap is the consent, so no banner. This is
            // the primary control the flow is built around.
            PasteButton(supportedContentTypes: [.url]) { providers in
                handlePaste(providers)
            }

            // Previewed but not read. `detectedValues` returns links without the
            // banner, so the screen can tell the user what it can see before they
            // commit to pasting it.
            if let clipboardLink, detected == nil {
                Button {
                    Task { await resolve(clipboardLink) }
                } label: {
                    Label("使用剪贴板里的链接（id\(clipboardLink.trackID)）", systemImage: "doc.on.clipboard")
                }
            }
        } header: {
            Text("粘贴 App Store 链接")
        } footer: {
            Text("在桌面上长按一个 App → 分享 App → 拷贝，然后回到这里粘贴。")
        }
    }

    /// Always available, network or not: a scheme typed by hand is the floor this
    /// whole feature rests on.
    ///
    /// Goes through ``SchemeEntryView`` rather than straight to a tile, because
    /// every other path on this screen ends in a scheme the screen has *some*
    /// reason to believe — a catalogue entry's verified one, or a guess informed
    /// by a bundle id. A hand-made tile has neither, and that screen is where a
    /// scheme gets tried for real.
    @ViewBuilder
    private var manualSection: some View {
        Section {
            NavigationLink {
                SchemeEntryView(lookup: AppStoreLookup.manual(name: "新图块"), title: "新图块") { tile in
                    onPick(tile)
                    dismiss()
                }
            } label: {
                Label("手动添加", systemImage: "keyboard")
            }
        } footer: {
            Text("没有链接也可以手动填名字和链接。")
        }
    }

    // MARK: - Behaviour

    /// Looks at the clipboard without reading its text.
    ///
    /// `detectedValues(for: [\.links])` returns only links iOS has already
    /// classified, which is not gated behind the paste banner. Reading
    /// `UIPasteboard.general.string` here instead would make the screen ask for
    /// permission just by being opened.
    private func readClipboardHint() async {
        guard detected == nil, clipboardLink == nil else { return }
        guard let values = try? await UIPasteboard.general.detectedValues(for: [\.links]) else { return }
        for match in values.links {
            guard let link = AppStoreLink.parse(match.url) else { continue }
            clipboardLink = link
            await resolve(link)
            return
        }
    }

    /// Handles the payload of a user-initiated paste.
    ///
    /// The providers arrive as `NSItemProvider`s rather than as a string, because
    /// that is what `PasteButton` hands over. A URL provider may vend either a
    /// `URL` or a `String`, so both are tried — the same link can be either
    /// depending on where it was copied from.
    private func handlePaste(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        isResolving = true

        let urlType = UTType.url.identifier
        let textType = UTType.plainText.identifier

        if provider.hasItemConformingToTypeIdentifier(urlType) {
            provider.loadItem(forTypeIdentifier: urlType, options: nil) { item, _ in
                let url: URL? = (item as? URL) ?? (item as? String).flatMap(URL.init(string:))
                Task { @MainActor in
                    guard let url, let link = AppStoreLink.parse(url) else {
                        isResolving = false
                        return
                    }
                    await resolve(link)
                }
            }
        } else if provider.hasItemConformingToTypeIdentifier(textType) {
            provider.loadItem(forTypeIdentifier: textType, options: nil) { item, _ in
                let text = item as? String
                Task { @MainActor in
                    guard let text, let link = AppStoreLink.parseFirst(in: text) else {
                        isResolving = false
                        return
                    }
                    await resolve(link)
                }
            }
        } else {
            isResolving = false
        }
    }

    /// Resolves a parsed link into something a tile can be built from.
    ///
    /// The catalogue is consulted first and by track id, which is the load-bearing
    /// step: a hit means a *verified* scheme and the user is done. Only a miss
    /// costs a network request, and even then the region the link carried is
    /// preferred over the device's.
    private func resolve(_ link: AppStoreLink) async {
        detected = link
        isResolving = true
        didFailLookup = false

        if let entry = AppCatalog.entry(appStoreID: link.trackID) {
            catalogEntry = entry
            resolved = nil
            isResolving = false
            return
        }

        let lookup = await AppStoreSearchClient.shared.lookup(trackID: link.trackID, region: link.region)
        resolved = lookup
        didFailLookup = lookup == nil
        isResolving = false
    }
}

/// An app's icon, falling back to a symbol when there is no artwork to fetch.
///
/// Prefers real artwork and uses the symbol only when the App Store had nothing —
/// which for the catalogue means Apple's own apps, whose entries carry a
/// ``KnownApp/symbolName`` precisely because they have no store artwork. It is the
/// same rule the tile itself follows, so what is shown here is what the user gets.
struct AppIconView: View {
    let appStoreID: Int?
    let symbolName: String

    @State private var image: UIImage?

    private var isAwaitingArtwork: Bool { appStoreID != nil && image == nil }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else if isAwaitingArtwork {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.fill.tertiary)
                    .overlay {
                        Image(systemName: symbolName).foregroundStyle(.secondary)
                    }
            } else {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.fill.secondary)
                    .overlay {
                        Image(systemName: symbolName)
                            .font(.system(size: 24))
                            .foregroundStyle(.primary)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .task(id: appStoreID) {
            guard let appStoreID else { return }
            if let data = await IconStore.shared.icon(forAppStoreID: appStoreID) {
                image = UIImage(data: data)
            }
        }
    }
}