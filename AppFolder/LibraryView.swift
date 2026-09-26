import AppFolderKit
import SwiftUI

struct RootView: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("文件夹", systemImage: "square.grid.2x2") }

            AddToHomeScreenView()
                .tabItem { Label("放到桌面", systemImage: "plus.app") }

            AboutView()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        // The second half of the bounce route. A widget tile that cannot reach
        // its target directly opens AppFolder with the target in the URL; this is
        // where that hand-off is completed.
        //
        // Speed is the whole point: every millisecond here is a millisecond the
        // user stares at AppFolder instead of the app they asked for. So this
        // does the open immediately and does not touch the model or the store.
        .onOpenURL { url in
            guard let target = LaunchLink.targetURL(from: url) else { return }
            UIApplication.shared.open(target)
        }
    }
}

/// The folder list, and the entry point to creating one.
struct LibraryView: View {
    @Environment(LibraryModel.self) private var model
    @State private var editing: Folder?

    var body: some View {
        NavigationStack {
            Group {
                if model.folders.isEmpty {
                    EmptyLibraryView { editing = Folder(name: "常用") }
                } else {
                    List {
                        ForEach(model.folders) { folder in
                            Button {
                                editing = folder
                            } label: {
                                FolderRow(folder: folder)
                            }
                            .buttonStyle(.plain)
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
                        editing = Folder(name: "新文件夹")
                    } label: {
                        Label("新建", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editing) { folder in
                FolderEditorView(folder: folder)
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
