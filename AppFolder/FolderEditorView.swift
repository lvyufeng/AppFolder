import AppFolderKit
import SwiftUI
// For `WidgetFamily`, whose grid table in ``FolderGridMetrics`` is what the icon
// size footnote below computes against. The app draws no widgets; it reads the
// same table the widget does so the number it shows is the number the user gets.
import WidgetKit

/// Edits one folder: its name, tint, and the tiles inside it.
struct FolderEditorView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var folder: Folder
    @State private var isPickingTiles = false

    init(folder: Folder) {
        _folder = State(initialValue: folder)
    }

    /// The preview's job: everything the folder looks like, resolved the way the
    /// widget resolves it.
    ///
    /// Built through ``FolderStyle/init(_:)`` rather than from the draft's fields
    /// directly, so that a folder with no colour yet is previewed with the same
    /// substituted tint the widget would use — otherwise switching 底板 to 纯色
    /// would preview an invisible plate and then draw a blue one on the Home
    /// Screen.
    private var style: FolderStyle { FolderStyle(folder) }

    /// The grid as the *widget* would lay it out, not as the preview does.
    ///
    /// The preview is drawn at ``FolderPreviewGrid/designWidth`` — 320 pt, a
    /// number chosen so the same drawing scales cleanly to a thumbnail and to a
    /// phone-width editor — while the widget's Small size is 170 pt square.
    /// Icons scale with the container, so a size can only be quoted honestly if
    /// it is computed at the widget's own width; quoting the preview's would
    /// overstate every icon by roughly 1.9×.
    ///
    /// Small is the family to quote because it is the one this control was asked
    /// for and the one that is tightest: the same slider gives a larger icon in
    /// Medium or Large, and a footnote promising a size that only holds in one
    /// family would be wrong in the other two.
    private static let widgetSize = CGSize(width: 170, height: 170)

    private static func iconSize(for folder: Folder) -> CGFloat {
        FolderGridMetrics(
            tileCount: WidgetFamily.systemSmall.gridCapacity,
            columns: WidgetFamily.systemSmall.gridColumns,
            in: widgetSize,
            showsTitles: folder.showsTitles,
            iconScale: folder.iconScale
        ).iconSide
    }

    private static func iconSizeFootnote(for folder: Folder) -> String {
        let side = Int(iconSize(for: folder).rounded())
        let margin = Int(FolderGridMetrics(
            tileCount: WidgetFamily.systemSmall.gridCapacity,
            columns: WidgetFamily.systemSmall.gridColumns,
            in: widgetSize,
            showsTitles: false,
            iconScale: folder.iconScale
        ).margin.rounded())
        return "2×2 小组件里每个图标约占 \(side)pt，四周留白 \(margin)pt（系统桌面图标约 60pt）。九宫格始终放满 9 个。"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $folder.name)
                }

                Section {
                    FolderPlateView(
                        style: style,
                        content: AnyView(
                            FolderPreviewGrid(
                                tiles: Array(folder.tiles.prefix(9)),
                                showsTitles: folder.showsTitles,
                                iconScale: folder.iconScale
                            )
                        )
                    )
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))

                    Picker("底板", selection: $folder.plate) {
                        ForEach(FolderPlate.allCases, id: \.self) { plate in
                            Text(plate.localizedName).tag(plate)
                        }
                    }
                    .pickerStyle(.segmented)

                    FolderPlateFootnote(plate: folder.plate)

                    if folder.plate.usesTint {
                        // Written as a `Color`, read as a `#RRGGBB` string: the
                        // library has stored `colorHex` since the first commit
                        // and the on-disk shape is a contract, so the picker
                        // converts at the boundary rather than the schema
                        // changing under libraries already written.
                        ColorPicker(
                            "颜色",
                            selection: Binding(
                                get: { FolderTint(hex: folder.colorHex)?.color ?? FolderTint.defaultTint.color },
                                set: { folder.colorHex = FolderTint($0).hex }
                            ),
                            supportsOpacity: false
                        )
                    }

                    Toggle("显示图标名称", isOn: $folder.showsTitles)

                    // A plain `Slider`, not a `Picker` of presets. The size is a
                    // continuous thing and the user asked for it adjustable, so
                    // the control should be too; the label carries the number the
                    // layout actually computes rather than an abstract 1–5, which
                    // is the only way to see that the icons have stopped growing.
                    //
                    // What it moves is the gap between icons, not the widget's
                    // outer margin. That is not a shortcut: the margin is what
                    // keeps the corner icons clear of the widget's own corner
                    // radius, so spending it would clip the artwork the user is
                    // trying to enlarge. The gap, by contrast, is charged to the
                    // same pool as the cells, so no setting of this can change
                    // how many apps fit — the 2 × 2 keeps its nine either way.
                    LabeledContent("图标大小") {
                        Text("\(Int((folder.iconScale * 100).rounded()))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $folder.iconScale, in: 0...1, step: 0.05) {
                        Text("图标大小")
                    } minimumValueLabel: {
                        Text("小").font(.caption2)
                    } maximumValueLabel: {
                        Text("大").font(.caption2)
                    }

                    Text(Self.iconSizeFootnote(for: folder))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("外观")
                } footer: {
                    Text("桌面上的小组件就是这个样子。")
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

/// Picks tiles from the catalog, split by what the probe knows.
///
/// Three sections rather than two, because there are three answers and the app
/// can only give one of them honestly:
///
/// * **已安装** — asked, and the system said yes. This is the section the picker
///   exists for; it turns the whole catalogue into a short list of apps the user
///   is actually looking at on their Home Screen.
/// * **未安装** — asked, and the system said no.
/// * **其他** — never asked. `LSApplicationQueriesSchemes` is capped (see
///   ``AppCatalog/queryBudget``), so most of the catalogue can never be checked.
///   These are *not* known to be absent, and the app says so instead of guessing.
///
/// In the simulator nothing third-party is installed, so every declared scheme
/// lands in 未安装 and the list looks like a failure. On a real device the first
/// section is the useful one.
struct TilePickerView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selection: Set<String> = []
    let onDone: ([FolderTile]) -> Void

    private var installed: [KnownApp] { filtered.filter { model.installStatus($0) == .installed } }
    private var absent: [KnownApp] { filtered.filter { model.installStatus($0) == .absent } }
    private var unknown: [KnownApp] { filtered.filter { model.installStatus($0) == .unknown } }

    private var filtered: [KnownApp] {
        let pool = AppCatalog.selectable
        guard !query.isEmpty else { return pool }
        let needle = query.lowercased()
        return pool.filter {
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
                    Section {
                        ForEach(installed) { row($0) }
                    } header: {
                        Text("已安装")
                    } footer: {
                        Text("这些 App 在当前设备上装了，可以放心添加。")
                    }
                }

                if !unknown.isEmpty {
                    Section {
                        ForEach(unknown) { row($0) }
                    } header: {
                        Text("其他")
                    } footer: {
                        // Said plainly, because the alternative is the user
                        // wondering why an app they have isn't in the list above.
                        Text("系统只允许 App 检查约 \(AppCatalog.queryBudget) 个 App 是否安装，其余的在这里。它们能用，只是没法自动判断装没装。")
                    }
                }

                if !absent.isEmpty {
                    Section {
                        ForEach(absent) { row($0) }
                    } header: {
                        Text("未安装")
                    } footer: {
                        Text("当前设备上没有检测到这些 App。")
                    }
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
        let status = model.installStatus(app)

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

                if status != .unknown {
                    Text(status.label)
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
