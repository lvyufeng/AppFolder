import AppFolderKit
import SwiftUI

struct RootView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = BounceRouter()

    var body: some View {
        Group {
            if router.isHandingOff {
                // The bounce is in flight. Draw nothing: see ``BounceRouter`` for
                // why this is what makes the hand-off invisible rather than a
                // visible detour through the launcher.
                Color(.systemBackground)
                    .ignoresSafeArea()
            } else {
                launcher
            }
        }
        // The second half of the bounce route. A widget tile that cannot reach
        // its target directly opens AppFolder with the target in the URL; this is
        // where that hand-off is completed.
        .onOpenURL { url in
            router.handle(url)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            router.scenePhaseChanged(to: phase)
        }
        // The other destination a widget link can carry: the grid's last cell,
        // tapped because the folder holds more apps than the widget has cells.
        // Resolved against the live library rather than against anything the URL
        // carried, so a folder deleted since the widget last drew simply shows
        // nothing.
        .sheet(item: Binding(
            get: { router.expandingFolderID.flatMap(model.folder(withID:)) },
            set: { if $0 == nil { router.expandingFolderID = nil } }
        )) { folder in
            FolderExpandView(folder: folder)
        }
        .alert(
            "打不开",
            isPresented: Binding(
                get: { router.failure != nil },
                set: { if !$0 { router.failure = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(router.failure ?? "")
        }
    }

    private var launcher: some View {
        TabView {
            LibraryView()
                .tabItem { Label("文件夹", systemImage: "square.grid.2x2") }

            AddToHomeScreenView()
                .tabItem { Label("放到桌面", systemImage: "plus.app") }

            TroubleshootingView()
                .tabItem { Label("排查", systemImage: "stethoscope") }

            AboutView()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
    }
}

/// Everything a tap on the Home Screen needs and cannot ask about.
///
/// A widget has no console, no error surface, and no way for the app to reach it
/// once it is placed. So when a tile does nothing, the user's only recourse is to
/// guess — and the guesses that matter, "is the widget seeing my folders" and
/// "would it even draw a background", are both answerable from here. This screen
/// is what turns a silent failure into a diagnosis.
struct TroubleshootingView: View {
    @Environment(LibraryModel.self) private var model

    /// What a widget would find if it looked right now.
    ///
    /// Read through the same ``FolderStore`` the widget uses rather than from the
    /// model's in-memory copy, because the gap between those two is exactly the
    /// failure this screen exists to expose.
    private var widgetVisible: FolderLibrary = FolderStore().load()

    private var widgetTileCount: Int {
        widgetVisible.folders.reduce(0) { $0 + $1.tiles.count }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("共享容器") {
                        Text(model.isSharedStorageAvailable ? "可用" : "不可用")
                            .foregroundStyle(model.isSharedStorageAvailable ? .green : .orange)
                    }
                    LabeledContent("这个 App 里的文件夹") { Text("\(model.folders.count)") }
                    LabeledContent("小组件能读到的文件夹") { Text("\(widgetVisible.folders.count)") }
                    LabeledContent("小组件能读到的图块") { Text("\(widgetTileCount)") }
                    LabeledContent("已缓存图标") {
                        Text("\(IconStore.shared.cachedIconCount) 个")
                            .foregroundStyle(
                                IconStore.shared.isCacheSharedWithWidget ? Color.primary : Color.orange
                            )
                    }
                    if !IconStore.shared.isCacheSharedWithWidget {
                        // Said outright, because the symptom is a blank widget with
                        // perfectly good icons in the app, which reads as a widget
                        // bug rather than a storage one.
                        Text("图标缓存在 App 自己的目录里，小组件读不到，桌面上会显示成空方块。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("小组件能看到什么")
                } footer: {
                    // The two "小组件能读到" lines come through the same code path
                    // the widget uses. If they are zero while the lines above are
                    // not, the widget will draw an empty box, and the cause is
                    // storage rather than the folder.
                    Text("下面两行走的是小组件完全相同的读取路径。如果它们比上面的数字少，桌面上的小组件就是空的——问题在共享存储，不在文件夹。")
                }

                Section("小组件点不动的时候") {
                    Text("图块点下去没反应，只有三种可能：目标 App 没装、链接写错了、或者这个图块选了「直接打开」但目标 App 没有通用链接。")
                    Text("回到文件夹点开那个图块，用「试一下」逐个排除。第三种编辑器会直接标出来。")
                }
            }
            .navigationTitle("排查")
        }
    }
}

/// The folder list, and the entry point to creating one.
///
/// Each row offers two destinations, because a folder has two independent halves —
/// see ``FolderEditorView`` for why they are separate screens. The row itself
/// opens the *contents*, because that is what a folder is for and what changes
/// most often; appearance is one long-press away.
struct LibraryView: View {
    @Environment(LibraryModel.self) private var model

    /// Which screen a row's tap or menu opens.
    ///
    /// One piece of state rather than two, so a row cannot end up presenting two
    /// sheets at once — which is what two `@State var editing: X?` would allow,
    /// and what SwiftUI resolves by silently dropping one of them.
    ///
    /// The folder is carried rather than looked up by id at presentation time, so
    /// that "new folder" is the same shape as the other two and needs no special
    /// case. Its `id` is a fresh `UUID` made once when the destination is set,
    /// which is what keeps the sheet identity stable while it is open.
    private struct Destination: Identifiable {
        enum Mode { case content, appearance }

        let folder: Folder
        let mode: Mode

        var id: String { "\(mode)-\(folder.id)" }
    }

    @State private var destination: Destination?

    var body: some View {
        NavigationStack {
            Group {
                if model.folders.isEmpty {
                    EmptyLibraryView {
                        destination = Destination(
                            folder: Folder(name: "常用"),
                            mode: .appearance
                        )
                    }
                } else {
                    List {
                        ForEach(model.folders) { folder in
                            Button {
                                destination = Destination(folder: folder, mode: .content)
                            } label: {
                                FolderRow(folder: folder)
                            }
                            .buttonStyle(.plain)
                            // The two entries ride on the row's own context menu
                            // rather than a second tap target. A chevron plus a
                            // disclosure button puts two competing affordances on
                            // a row whose primary job is unambiguous — opening the
                            // folder — and the context menu is where iOS users
                            // already look for the second one.
                            .contextMenu {
                                Button {
                                    destination = Destination(folder: folder, mode: .appearance)
                                } label: {
                                    Label("编辑外观", systemImage: "paintbrush")
                                }
                                Button(role: .destructive) {
                                    model.delete(folder)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                        .onMove(perform: model.moveFolders)
                        .onDelete { offsets in
                            for index in offsets {
                                model.delete(model.folders[index])
                            }
                        }
                    }
                }
            }
            .navigationTitle("AppFolder")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Appearance first, because a new folder has no tiles to
                        // arrange and two of its fields — the name and the grid —
                        // decide what the user is about to put in it.
                        destination = Destination(
                            folder: Folder(name: "新文件夹"),
                            mode: .appearance
                        )
                    } label: {
                        Label("新建", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $destination) { destination in
                switch destination.mode {
                case .content:
                    FolderContentEditorView(folder: destination.folder)
                case .appearance:
                    FolderEditorView(folder: destination.folder)
                }
            }
        }
    }
}

private struct EmptyLibraryView: View {
    let onCreate: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("还没有文件夹", systemImage: "square.grid.2x2")
        } description: {
            Text("大文件夹会在桌面上平铺 4 到 9 个 App 图标，点一下直接进 App。")
        } actions: {
            Button("创建第一个文件夹", action: onCreate)
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct FolderRow: View {
    @Environment(LibraryModel.self) private var model
    let folder: Folder

    var body: some View {
        HStack(spacing: 12) {
            FolderPreviewGrid(tiles: Array(folder.tiles.prefix(9)))
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.headline)
                Text("\(folder.tiles.count) 个图块")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
