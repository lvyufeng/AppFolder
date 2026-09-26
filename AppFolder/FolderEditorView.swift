import AppFolderKit
import SwiftUI

/// Edits one folder: its name, tint, and the tiles inside it.
struct FolderEditorView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var folder: Folder
    @State private var isPickingTiles = false

    init(folder: Folder) {
        _folder = State(initialValue: folder)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $folder.name)
                }

                Section("图块") {
                    if folder.tiles.isEmpty {
                        Text("还没有图块，点下面的按钮添加。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($folder.tiles) { $tile in
                            TileEditorRow(tile: $tile)
                        }
                        .onDelete { folder.tiles.remove(atOffsets: $0) }
                        .onMove { folder.tiles.move(fromOffsets: $0, toOffset: $1) }
                    }

                    Button {
                        isPickingTiles = true
                    } label: {
                        Label("添加图块", systemImage: "plus.circle")
                    }
                }

                Section("预览") {
                    FolderPreviewGrid(tiles: Array(folder.tiles.prefix(9)), showsTitles: true)
                        .frame(maxWidth: 220)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.background.secondary, in: .rect(cornerRadius: 20))
                }

                if !model.isSharedStorageAvailable {
                    Section {
                        Label {
                            Text("当前签名没有 App Groups，小组件读不到这些文件夹。")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                        .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("编辑文件夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        model.upsert(folder)
                        dismiss()
                    }
                    .disabled(folder.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $isPickingTiles) {
                TilePickerView { picked in
                    folder.tiles.append(contentsOf: picked)
                }
            }
        }
    }
}

/// Picks tiles from the catalog, split into "installed" and "everything else".
///
/// Ordering installed apps first is the whole point of the probe: it turns a
/// 300-entry list into a short one the user recognises.
struct TilePickerView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selection: Set<String> = []
    let onDone: ([FolderTile]) -> Void

    private var installed: [KnownApp] {
        filtered.filter { model.installedSchemes.contains($0.scheme) }
    }

    private var others: [KnownApp] {
        filtered.filter { !model.installedSchemes.contains($0.scheme) }
    }

    private var filtered: [KnownApp] {
        guard !query.isEmpty else { return AppCatalog.all }
        let needle = query.lowercased()
        return AppCatalog.all.filter {
            $0.name.lowercased().contains(needle)
                || $0.englishName.lowercased().contains(needle)
                || $0.scheme.lowercased().contains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if model.isProbing {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("正在查找已安装的 App…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !installed.isEmpty {
                    Section("已安装") {
                        ForEach(installed) { row($0) }
                    }
                }

                Section(installed.isEmpty ? "全部" : "其他") {
                    ForEach(others) { row($0) }
                }
            }
            .searchable(text: $query, prompt: "搜索 App")
            .navigationTitle("添加图块")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成（\(selection.count)）") {
                        let chosen = AppCatalog.all.filter { selection.contains($0.id) }
                        onDone(chosen.map { FolderTile(app: $0) })
                        dismiss()
                    }
                    .disabled(selection.isEmpty)
                }
            }
            .task {
                await model.refreshInstalledApps()
            }
        }
    }

    private func row(_ app: KnownApp) -> some View {
        let isPicked = selection.contains(app.id)
        let isInstalled = model.installedSchemes.contains(app.scheme)

        return Button {
            if isPicked { selection.remove(app.id) } else { selection.insert(app.id) }
        } label: {
            HStack(spacing: 12) {
                AsyncTileIcon(appStoreID: app.appStoreID, symbolName: "app.dashed")
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                    Text(app.englishName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isInstalled {
                    Text("已安装")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isPicked ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Icon view driven by an App Store id, for entries that are not tiles yet.
struct AsyncTileIcon: View {
    let appStoreID: Int?
    let symbolName: String

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.fill.tertiary)
                    .overlay {
                        Image(systemName: symbolName)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .task(id: appStoreID) {
            guard let appStoreID else { return }
            if let data = await IconStore.shared.icon(forAppStoreID: appStoreID) {
                image = UIImage(data: data)
            }
        }
    }
}
