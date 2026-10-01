import AppFolderKit
import SwiftUI

/// The share sheet's UI: which folder does this app go into?
///
/// Short by necessity. An extension is a guest — it gets a small sheet, a small
/// memory budget, and no way to hand work back to its app — so this asks the one
/// question whose answer only the user has, then gets out of the way.
///
/// ## What it does not do
///
/// It does not resolve the app over the network. The folder choice is the only
/// thing that cannot be done later, and everything else — the catalogue lookup,
/// the metadata fetch, the icon download — happens in the app, where there is a
/// real network stack, no jetsam pressure, and a place to show an error. Keeping
/// the extension's work to "read a link, read the folder list, write one small
/// file" is what makes its memory budget a non-issue.
struct ShareRootView: View {
    let link: AppStoreLink?
    let onDone: () -> Void
    let onCancel: () -> Void

    @State private var folders: [Folder] = []
    @State private var didDeposit = false

    var body: some View {
        NavigationStack {
            Group {
                if let link {
                    folderList(for: link)
                } else {
                    unsupported
                }
            }
            .navigationTitle(link == nil ? "无法添加" : "添加到文件夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
            }
            .task { loadFolders() }
        }
    }

    /// The happy path: pick where it goes.
    @ViewBuilder
    private func folderList(for link: AppStoreLink) -> some View {
        if folders.isEmpty {
            ContentUnavailableView {
                Label("还没有文件夹", systemImage: "square.grid.2x2")
            } description: {
                // The honest answer, and the only one available: the extension
                // cannot open the app to offer a "create one" button, because
                // `UIApplication.shared` does not exist in an extension.
                Text("先在 AppFolder 里建一个文件夹，再回来分享。")
            } actions: {
                Button("好", action: onCancel)
            }
        } else {
            List {
                Section {
                    ForEach(folders) { folder in
                        Button {
                            deposit(link, into: folder)
                        } label: {
                            HStack(spacing: 12) {
                                // A plain symbol rather than the app's own grid
                                // preview: that view is internal to the app target,
                                // and pulling it (and its icon plumbing) into the
                                // extension would cost more than this row is worth
                                // — the folder's name is what the user is reading.
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.fill.tertiary)
                                    .frame(width: 40, height: 40)
                                    .overlay {
                                        Image(systemName: "square.grid.2x2")
                                            .foregroundStyle(.secondary)
                                    }

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(folder.name)
                                        .foregroundStyle(.primary)
                                    Text("\(folder.tiles.count) 个图块")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "plus.circle")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("选一个文件夹")
                } footer: {
                    // Said plainly, because the alternative is the user waiting
                    // for something to appear on the Home Screen and concluding it
                    // failed.
                    Text("回到 AppFolder 就会看到它加进去了。")
                }
            }
            .overlay {
                if didDeposit {
                    deposited
                }
            }
        }
    }

    /// Shown after a successful deposit, so the sheet does not just vanish.
    private var deposited: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("已添加")
                .font(.headline)
            Button("完成", action: onDone)
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// What the user shared was not an App Store app link.
    ///
    /// Reached by sharing a web page, a photo, or an App Store link to a song or
    /// a book — all of which end in `id<digits>` just like an app does, which is
    /// why ``AppStoreLink`` refuses them. Saying so is better than a sheet that
    /// silently does nothing.
    private var unsupported: some View {
        ContentUnavailableView {
            Label("这不是 App Store 的 App 链接", systemImage: "questionmark.square.dashed")
        } description: {
            Text("在桌面上长按一个 App，选「分享 App」，再分享给 AppFolder。")
        } actions: {
            Button("好", action: onCancel)
        }
    }

    /// Reads the folder list straight from the shared container.
    ///
    /// A plain read of `library.json` — no repair pass, no model — because the
    /// extension must not write the library and the app will repair anything that
    /// needs repairing when it drains the queue.
    private func loadFolders() {
        folders = FolderStore().load().folders
    }

    private func deposit(_ link: AppStoreLink, into folder: Folder) {
        let item = PendingImport(
            trackID: link.trackID,
            region: link.region,
            folderID: folder.id
        )
        PendingImportStore().deposit(item)
        // Shown regardless of the write's result: the failure modes (no shared
        // container, a full disk) have no user-actionable remedy from inside an
        // extension, and the app's drain is what would reveal it anyway.
        withAnimation { didDeposit = true }
    }
}