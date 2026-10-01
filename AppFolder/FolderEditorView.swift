import AppFolderKit
import SwiftUI
// For `WidgetFamily`, whose grid table in ``FolderGridMetrics`` is what the icon
// size footnote below computes against. The app draws no widgets; it reads the
// same table the widget does so the number it shows is the number the user gets.
import WidgetKit

/// Edits one folder's name and appearance.
///
/// ## Why this is separate from the tiles
///
/// This screen and ``FolderContentEditorView`` were one form, and the two halves
/// answer different questions: *what does this folder look like* and *what is in
/// it*. They are edited at different times by different impulses — the look is
/// settled once and then left alone, the contents change whenever an app is
/// installed or dropped — and stacking them meant scrolling past a live preview
/// and six appearance controls to add an app.
///
/// The split is at the point where nothing is shared: appearance reads the tiles
/// (the preview draws them, the grid capacity depends on how many there are) but
/// never writes them, and the content screen never touches a field this one owns.
///
/// ## Why the name lives here
///
/// It is not obviously an appearance property, but it belongs with one: the name
/// is what the folder is *called*, a fact about the folder as a whole, whereas the
/// other screen is a list of the apps inside it. Giving it a third home would mean
/// a screen with one field.
///
/// Each screen saves on its own, so neither can discard the other's edits: you
/// cannot lose appearance changes by adding an app, which a shared draft with two
/// entry points would have made routine.
struct FolderEditorView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var folder: Folder

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

    /// The grid the small widget would draw for this folder, which is the one
    /// number both the footnote and the preview need. Derived from the folder
    /// rather than from a constant, because the grid setting changes it.
    private static func metrics(for folder: Folder, showsTitles: Bool? = nil) -> FolderGridMetrics {
        FolderGridMetrics(
            tileCount: folder.grid.capacity(for: .systemSmall),
            columns: folder.grid.columns(for: .systemSmall),
            in: widgetSize,
            showsTitles: showsTitles ?? folder.showsTitles,
            iconScale: folder.iconScale
        )
    }

    /// The tiles the small widget draws as apps, which is everything up to the cell
    /// reserved for the door.
    private static func shownTiles(of folder: Folder) -> [FolderTile] {
        Array(folder.tiles.prefix(folder.grid.capacity(for: .systemSmall)))
    }

    /// What is behind the door, or `nil` when nothing overflowed.
    ///
    /// The same ``FolderGrid/nestedCell(for:tileCount:)`` the widget asks, so the
    /// preview and the Home Screen cannot disagree about whether there is a door
    /// at all — which would be the worst possible disagreement, because the one
    /// thing this preview is for is showing the user where their tenth app went.
    private static func nestedCell(of folder: Folder) -> FolderPreviewGrid.NestedCell? {
        guard folder.grid.nestedCell(for: .systemSmall, tileCount: folder.tiles.count) != nil else {
            return nil
        }
        let shown = folder.grid.capacity(for: .systemSmall)
        return FolderPreviewGrid.NestedCell(
            previews: Array(folder.tiles.dropFirst(shown).prefix(4)),
            count: max(0, folder.tiles.count - shown)
        )
    }

    private static func iconSizeFootnote(for folder: Folder) -> String {
        let side = Int(metrics(for: folder).iconSide.rounded())
        let margin = Int(metrics(for: folder, showsTitles: false).margin.rounded())
        let count = folder.grid.capacity(for: .systemSmall)
        var line = "2×2 小组件里每个图标约占 \(side)pt，四周留白 \(margin)pt（系统桌面图标约 60pt）。"
            + "直接显示 \(count) 个，最后一格是「更多」入口。"
        if let overflow = nestedCell(of: folder) {
            line += "现在还有 \(overflow.count) 个在里面，点那一格就能全部展开。"
        }
        return line
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
                                // The same count the widget will draw, not a
                                // fixed nine: a 四宫格 folder shows three on the
                                // Home Screen, and a preview showing nine would
                                // be promising the one thing this preview exists
                                // to promise it will not do.
                                tiles: Self.shownTiles(of: folder),
                                showsTitles: folder.showsTitles,
                                iconScale: folder.iconScale,
                                columns: folder.grid.columns(for: .systemSmall),
                                nested: Self.nestedCell(of: folder)
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

                    // Above the icon-size slider because it sets the room the
                    // slider then works within: a 四宫格 cell is roughly 1.8× the
                    // area of a 九宫格 one, so the same percentage means a visibly
                    // different icon. Somewhere the shape has to come before the
                    // size, and this is where the user decides it.
                    Picker("网格", selection: $folder.grid) {
                        ForEach(FolderGrid.allCases, id: \.self) { grid in
                            Text(grid.localizedName).tag(grid)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(folder.grid.localizedExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)

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
                    Text("桌面上的小组件就是这个样子。改的是它长什么样——里面放哪些 App 在「编辑图块」里。")
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
            .navigationTitle("编辑外观")
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
        }
    }
}

/// Edits which apps are in one folder, and in what order.
///
/// The other half of the split described on ``FolderEditorView``. This screen owns
/// ``Folder/tiles`` and nothing else — no preview, no plate, no grid. It is the
/// one that gets opened repeatedly over a folder's life, so it is the one that
/// should be a plain, fast list.
///
/// It saves on its own rather than through a shared draft, so adding an app can
/// never discard an appearance change the user made and did not yet save — and
/// the two screens cannot be open at once, since each is a sheet from the folder
/// list.
struct FolderContentEditorView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var folder: Folder
    @State private var isPickingTiles = false

    init(folder: Folder) {
        _folder = State(initialValue: folder)
    }

    /// How many of this folder's apps the Home Screen actually shows.
    ///
    /// The grid reserves its last cell for the "open the rest" door, so the
    /// number is one below the cell count — see ``FolderGrid/capacity(for:)``.
    /// Derived from the small widget because that is the tightest of the sizes and
    /// the one a folder is judged on.
    private var shownCount: Int {
        folder.grid.capacity(for: .systemSmall)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
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
                } header: {
                    Text("图块")
                } footer: {
                    // The overflow is stated on this screen rather than only in
                    // the appearance footnote, because this is where the user is
                    // when they add the app that causes it. Silently dropping the
                    // ninth app into a door they have to go and find is how a
                    // folder reads as losing things.
                    if folder.tiles.count > shownCount {
                        Text("桌面上直接显示 \(shownCount) 个，另外 \(folder.tiles.count - shownCount) 个在最后一格的「更多」里，点它就能看到全部。")
                    } else {
                        Text("桌面上按顺序显示，多余的会收进最后一格的「更多」入口。")
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
            .navigationTitle(folder.name)
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
    /// Results from the App Store, or `nil` if the search has not run or failed.
    @State private var storeResults: [AppStoreLookup]?
    /// Set when the search could not be made at all — distinct from "found
    /// nothing", which is what it says.
    @State private var storeFailed = false
    @State private var storeSearching = false
    /// The result awaiting a scheme.
    @State private var pendingLookup: AppStoreLookup?
    let onDone: ([FolderTile]) -> Void

    private var installed: [KnownApp] { filtered.filter { model.installStatus($0) == .installed } }
    private var absent: [KnownApp] { filtered.filter { model.installStatus($0) == .absent } }
    private var unknown: [KnownApp] { filtered.filter { model.installStatus($0) == .unknown } }

    /// The catalogue's matches for the current query.
    ///
    /// Through ``AppCatalog/search(_:includeUnverified:)`` rather than the local
    /// substring filter this used to carry, because that function already ranks
    /// exact matches ahead of prefixes ahead of substrings. The two had drifted —
    /// the catalogue's version was the better one and nothing was calling it.
    private var filtered: [KnownApp] {
        AppCatalog.search(query)
    }

    /// Whether the App Store row should be offered at all.
    ///
    /// Only when the catalogue did not already answer. If the user typed a name
    /// the catalogue knows, the entry is right there with a verified scheme, and
    /// sending them to the App Store to re-find the same app is the WidgetLoft
    /// detour this feature exists to avoid.
    private var shouldOfferStoreSearch: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty && filtered.isEmpty
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

                storeSection
            }
            .searchable(text: $query, prompt: "搜索 App")
            .navigationTitle("添加图块")
            .navigationBarTitleDisplayMode(.inline)
            // Debounced on the query, so a five-letter word is one request rather
            // than five. `task(id:)` cancels the previous one on every keystroke,
            // including the sleep — which is what makes the delay a debounce and
            // not just a slow request.
            .task(id: query) {
                guard shouldOfferStoreSearch else {
                    storeResults = nil
                    storeFailed = false
                    return
                }
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await runStoreSearch()
            }
            .sheet(item: $pendingLookup) { lookup in
                SchemeEntryView(lookup: lookup, title: lookup.name) { tile in
                    onDone([tile])
                }
            }
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

    /// The escape hatch: apps the catalogue does not hold.
    ///
    /// Offered only when the catalogue came up empty for this query, because
    /// otherwise the answer is already on screen — and a second, slower, online
    /// path to the same app is exactly the detour this feature was built to
    /// remove.
    @ViewBuilder
    private var storeSection: some View {
        if shouldOfferStoreSearch {
            Section {
                if storeSearching {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在搜索 App Store…")
                            .foregroundStyle(.secondary)
                    }
                } else if storeFailed {
                    Label {
                        Text("连不上 App Store，检查一下网络。")
                    } icon: {
                        Image(systemName: "wifi.exclamationmark")
                    }
                    .foregroundStyle(.secondary)
                } else if let storeResults {
                    if storeResults.isEmpty {
                        Text("App Store 里也没搜到。可以换个名字，或者用下面「手动添加」。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(storeResults, id: \.trackID) { result in
                            storeRow(result)
                        }
                    }
                }

                // Always reachable, network or not: a scheme typed by hand is the
                // floor this whole screen rests on, and hiding it behind a failed
                // request would make the one path that always works the one path
                // that is missing.
                Button {
                    pendingLookup = AppStoreLookup(
                        trackID: 0,
                        bundleID: nil,
                        name: query.trimmingCharacters(in: .whitespaces),
                        sellerName: nil,
                        artworkURL: nil
                    )
                } label: {
                    Label("手动添加", systemImage: "keyboard")
                }
            } header: {
                Text("App Store")
            } footer: {
                Text("上面找不到的 App，在这里搜。iOS 不让 App 读你装了哪些 App，所以只能按名字找。")
            }
        }
    }

    /// One App Store result.
    ///
    /// The seller is shown because it is the only thing that distinguishes the
    /// apps sharing a name — searching "Keep" returns three — and the user is
    /// looking for one specific icon they can already see on their Home Screen.
    ///
    /// Tapping resolves against the catalogue first. An app the catalogue holds
    /// yields a verified scheme, so the user never sees the scheme screen; only a
    /// genuine stranger reaches ``SchemeEntryView``.
    private func storeRow(_ result: AppStoreLookup) -> some View {
        Button {
            if let entry = AppCatalog.entry(appStoreID: result.trackID) {
                onDone([FolderTile(app: entry)])
            } else {
                pendingLookup = result
            }
        } label: {
            HStack(spacing: 12) {
                AsyncTileIcon(appStoreID: result.trackID, symbolName: "app.dashed")
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text(result.name)
                    if let seller = result.sellerName {
                        Text(seller)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "plus.circle")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .buttonStyle(.plain)
    }

    private func runStoreSearch() async {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        storeSearching = true
        defer { storeSearching = false }

        let results = await AppStoreSearchClient.shared.search(term: term)
        // The query may have moved on while this was in flight; a result for a
        // term the user has since deleted would flash the wrong list.
        guard term == query.trimmingCharacters(in: .whitespaces) else { return }

        storeFailed = results == nil
        storeResults = results ?? []
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
