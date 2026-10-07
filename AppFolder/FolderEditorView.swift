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
            previews: Array(folder.tiles.dropFirst(shown).prefix(MiniGridDensity.maximumCapacity)),
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
    @State private var isImportingSharedLink = false

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

    /// Shared-in apps that never became tiles, because how to open them is not
    /// known.
    ///
    /// ## Why this section is load-bearing rather than tidy
    ///
    /// These apps leave **no trace anywhere else**. They produce no tile, no
    /// placeholder, nothing in the widget — so without this, the person who just
    /// shared an app from the Home Screen would be looking at a folder that had
    /// not changed, with no way to tell whether the share worked. The app icon's
    /// badge says *that* something is waiting; this says *what*, and is the only
    /// way to resolve it.
    ///
    /// ## Why it shows the whole queue, not just this folder's
    ///
    /// The queue is global — it belongs to the app, not to a folder — and a share
    /// can name a folder the user is not currently editing. Filtering to this
    /// folder would hide a waiting app behind a screen the user has no reason to
    /// open. Each row says which folder it will land in, so the list is still
    /// unambiguous about where confirming will put things.
    @ViewBuilder
    private var pendingSection: some View {
        if !model.pendingResolutions.isEmpty {
            Section {
                ForEach(model.pendingResolutions) { pending in
                    NavigationLink {
                        PendingResolutionView(pending: pending)
                    } label: {
                        PendingResolutionRow(pending: pending)
                    }
                }
            } header: {
                Text("待确认的分享")
            } footer: {
                Text("这些是从桌面分享进来的 App，但 AppFolder 猜不到能打开它们的链接。点进去试一下，确认后才会有图块——猜错的图块点不动，比没有更糟。")
            }
        }
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
                        Label("选择 App", systemImage: "plus.circle")
                    }

                    // The other way in, and the faster one when the app is already
                    // on the Home Screen: share it there, copy the link, paste it
                    // here. No searching, no typing, no region to pick.
                    Button {
                        isImportingSharedLink = true
                    } label: {
                        Label("从分享添加", systemImage: "square.and.arrow.down")
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

                pendingSection

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
                TilePickerView(currentTiles: folder.tiles) { picked in
                    folder.tiles = picked
                }
            }
            .sheet(isPresented: $isImportingSharedLink) {
                SharedLinkIntakeView { tile in
                    folder.tiles.append(tile)
                }
            }
        }
    }
}

/// Picks tiles from the catalog, split by what the probe knows.
///
/// Two sections, not three:
///
/// * **已安装** — asked, and the system said yes.
/// * **其他 App** — everything else, which is two different things wearing one
///   label: apps the probe asked about and got a *no*, and apps it was never
///   allowed to ask about. `LSApplicationQueriesSchemes` is capped at
///   ``AppCatalog/queryBudget``, and the cap is real — measured on device, 133
///   declared schemes yielded exactly 25 answers — so the second group is the
///   large one and cannot be shrunk by trying harder.
///
/// The *未安装* section this screen used to carry is gone, deliberately. Only the
/// first 25 catalogue entries can be checked at all, so for the other thirty an
/// "未安装" heading would have been the app asserting something it never
/// measured — and the user's own eyes can see the app on their Home Screen. A
/// list that claims to know and is wrong is worse than one that admits the
/// boundary, which the 其他 footer now states outright.
///
/// In the simulator nothing third-party is installed, so most of the list falls
/// into 其他 App. On a real device the first section is the useful one.
///
/// ## Why the folder's own apps come in selected
///
/// This screen answers "which apps are in this folder", and the honest way to ask
/// that is to show the folder as it is — every app it holds already checked — and
/// let the user change their mind. The alternative, a blank list that accumulates
/// picks, makes the same gesture mean *add* here and *remove* in
/// ``FolderContentEditorView``, one screen away, with nothing on screen to say
/// which it is. Arriving pre-filled also makes the list's first state a true
/// answer to "what is in here", which is worth more than an empty slate.
///
/// The list is seeded when the sheet appears rather than in `init`, because the
/// probe runs in a `.task` and the tiles it would prefill from are the model's,
/// not a snapshot taken before the user could have looked.
struct TilePickerView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    /// The apps the folder will end up holding: seeded from the folder's own
    /// tiles, then toggled.
    ///
    /// One value rather than the two `@State`s this used to be, because the split
    /// between "catalogue entries" and "hand-built tiles" only means anything at
    /// the point they are merged back together — and having them as separate state
    /// let one half be written and the other forgotten. See ``TileSelection`` for
    /// the bug that came of it.
    @State private var selection = TileSelection()
    @State private var didSeed = false
    let currentTiles: [FolderTile]
    /// The folder's apps after the user is done, in catalogue order with any
    /// hand-added tiles kept at the front.
    let onDone: ([FolderTile]) -> Void
    /// Results from the App Store, or `nil` if the search has not run or failed.
    @State private var storeResults: [AppStoreLookup]?
    /// Set when the search could not be made at all — distinct from "found
    /// nothing", which is what it says.
    @State private var storeFailed = false
    @State private var storeSearching = false
    /// The result awaiting a scheme.
    @State private var pendingLookup: AppStoreLookup?
    /// The storefront the App Store search runs against, or `nil` to use the
    /// device's own. See ``storeCountry`` for why this is switchable.
    @State private var storeCountryOverride: String?

    private var installed: [KnownApp] { filtered.filter { model.installStatus($0) == .installed } }
    /// Everything the probe could not confirm. Includes apps the system
    /// explicitly said no to and apps it was never allowed to ask about — see the
    /// type's own note for why those two cannot be told apart on screen.
    private var unknown: [KnownApp] { filtered.filter { model.installStatus($0) != .installed } }

    /// The catalogue's matches for the current query.
    ///
    /// Through ``AppCatalog/search(_:includeUnverified:)`` rather than the local
    /// substring filter this used to carry, because that function already ranks
    /// exact matches ahead of prefixes ahead of substrings. The two had drifted —
    /// the catalogue's version was the better one and nothing was calling it.
    private var filtered: [KnownApp] {
        AppCatalog.search(query)
    }

    /// Whether the App Store section should be shown for this query.
    ///
    /// Two ways in, and the second one is the change:
    ///
    /// 1. **The catalogue came up empty.** The original rule, and still the
    ///    common case: type a name the catalogue has never heard of and the
    ///    online search is the only door.
    /// 2. **The user asked for it.** A non-empty *non-matching* query is
    ///    deliberately not enough — the catalogue having an answer is not the same
    ///    as its answer being the app the user wants, but it is a good enough
    ///    guess that re-searching online on every keystroke would be the WidgetLoft
    ///    detour this feature exists to remove. So the second path is opened by a
    ///    tap, not by typing.
    ///
    /// ## Why (2) exists at all
    ///
    /// The catalogue matches on **name**, and a name is not an identity. Search
    /// "Keep" and the catalogue answers with 健身 Keep — correct, and possibly not
    /// the app the user has, because the store also sells a step counter called
    /// Keep. Before this, that answer was terminal: `filtered` was non-empty, so
    /// the App Store section never appeared, and the user could not reach the app
    /// they could see on their own Home Screen. There was nothing to retype,
    /// because the query was already right.
    ///
    /// ## Why it is a tap rather than automatic
    ///
    /// `search` is a network request per term, debounced at 350 ms. Firing one for
    /// every query the catalogue happens to answer would put a request behind
    /// every keystroke of the common path — which is the path that works. One tap
    /// from the user who has actually found the catalogue's answer wrong is a much
    /// better trigger than a heuristic that cannot know.
    private var shouldOfferStoreSearch: Bool {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return false }
        return filtered.isEmpty || wantsStoreSearch
    }

    /// Set by the user tapping 「还是搜 App Store」, cleared as soon as the query
    /// changes.
    ///
    /// Handled outside ``TileSelection`` because none of this is selection state —
    /// it is which of two *sources* the query is being answered from, and it does
    /// not outlive the query it was asked about.
    ///
    /// Cleared in an `onChange` rather than inside the search task. The task is
    /// keyed on ``storeSearchKey``, which includes this flag, so a task that reset
    /// its own trigger would cancel itself on the way in. Splitting the two — reset
    /// on the query edge, run the search on the key — keeps each doing one thing.
    @State private var wantsStoreSearch = false

    /// What the debounced search is keyed on.
    ///
    /// Carries ``wantsStoreSearch`` as well as the query, which is what lets the
    /// tap start a search: `task(id:)` re-runs whenever the id changes, and the
    /// flag going up is a change. The region is in here for the same reason it
    /// always was — switching storefront has to re-issue the request rather than
    /// leave the previous store's answer on screen under the new store's label.
    private var storeSearchKey: String {
        "\(storeCountry ?? "")|\(wantsStoreSearch)|\(query)"
    }

    /// Which storefront the App Store search runs against.
    ///
    /// Defaults to the device's own — the right answer for almost everyone — but
    /// it is switchable because "the store I bought this app from" is not the
    /// same question as "the store this device is signed into". One account can
    /// span regions: an app bought years ago in one storefront stays installed
    /// after the account moves to another, and searching only the current region
    /// then finds either nothing or, worse, a *different* app with the same name.
    /// 微信 / WeChat and Netflix are the clear cases — the same query in `cn` and
    /// `us` returns different apps, so the wrong storefront does not merely miss,
    /// it substitutes.
    ///
    /// The override is applied per search rather than resolved once, so switching
    /// it re-runs immediately and the user sees the other store's results without
    /// retyping.
    private var storeCountry: String? { storeCountryOverride }

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

                if !selection.extraTiles.isEmpty {
                    Section {
                        ForEach(selection.extraTiles) { tile in
                            Button {
                                selection.removeTile(id: tile.id)
                            } label: {
                                HStack(spacing: 12) {
                                    AsyncTileIcon(appStoreID: tile.appStoreID, symbolName: "app.dashed")
                                        .frame(width: 32, height: 32)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(tile.title)
                                        Text(tile.urlString)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("手动添加的")
                    } footer: {
                        Text("这些 App 不在目录里，链接是你自己填的。点一下可以移出文件夹。")
                    }
                }

                if !installed.isEmpty {
                    Section {
                        ForEach(installed) { row($0) }
                    } header: {
                        Text("已安装")
                    } footer: {
                        Text("这些 App 检测到装在当前设备上。")
                    }
                }

                if !unknown.isEmpty {
                    Section {
                        ForEach(unknown) { row($0) }
                    } header: {
                        Text("其他 App")
                    } footer: {
                        // Said plainly, because the alternative is the user
                        // wondering why an app they have isn't in the list above.
                        // The count is the honest part: the limit is exactly why
                        // these are here, and a user who knows that can tell
                        // "not detected" apart from "not installed" — which the
                        // list itself cannot, so it does not claim to.
                        Text("系统只允许 App 检查 \(AppCatalog.queryBudget) 个 App 是否安装，其余的都在这里。装着的也在里面，只是没法自动认出来。")
                    }
                }

                catalogueAnsweredSection
                storeSection
            }
            .searchable(text: $query, prompt: "搜索 App")
            .onChange(of: query) { _, _ in
                // A new term is a new question, and it starts on the catalogue's
                // answer — see ``wantsStoreSearch``. Only the *query* resets it, so
                // a mid-search region change does not throw the user back.
                wantsStoreSearch = false
            }
            .navigationTitle("选择 App")
            .navigationBarTitleDisplayMode(.inline)
            // Debounced on the query, so a five-letter word is one request rather
            // than five. `task(id:)` cancels the previous one on every keystroke,
            // including the sleep — which is what makes the delay a debounce and
            // not just a slow request.
            //
            // Keyed on the region as well as the query, so switching storefront
            // re-issues the search rather than leaving the previous store's
            // results on screen under a label that says otherwise. The id is a
            // string because a tuple is not `Equatable` enough for `task(id:)` in
            // the way this needs, and the separator cannot appear in either part.
            .task(id: storeSearchKey) {
                guard shouldOfferStoreSearch else {
                    storeResults = nil
                    storeFailed = false
                    return
                }
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await runStoreSearch()
            }
            // The scheme screen hands back a finished tile, and the picker **adds** it
// rather than finishing on it.
            //
            // It used to call `onDone([tile])`, which is this screen's own exit —
            // so adding one app by hand replaced the folder's entire contents with
            // that one app. Invisible from here: the sheet closes and the result
            // is handed over in the same turn, so the list the user was looking at
            // is never re-rendered with the loss in it. The merge is in
            // ``TileSelection/add(_:)`` now, with tests.
            //
            // Dismissing the *scheme* sheet lands back on this list, where the new
            // tile appears in the 手动添加的 section and a second tap on 完成
            // commits it — the same shape as ticking a catalogue row.
            .sheet(item: $pendingLookup) { lookup in
                SchemeEntryView(lookup: lookup, title: lookup.name) { tile in
                    selection.add(tile)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { onDone(selection.resolved); dismiss() }
                }
            }
            .task {
                await model.refreshInstalledApps()
            }
            .task {
                guard !didSeed else { return }
                didSeed = true
                seedFromCurrentTiles()
            }
        }
    }

    /// The escape hatch: apps the catalogue does not hold.
    ///
    /// Offered only when the catalogue came up empty for this query, because
    /// otherwise the answer is already on screen — and a second, slower, online
    /// path to the same app is exactly the detour this feature was built to
    /// remove.
    /// The way out when the catalogue answered, but with the wrong app.
    ///
    /// Rendered only in the case that needs it — the catalogue found something and
    /// the user has not already asked for the online search. Every other state has
    /// the App Store section on screen already, and a second control pointing at it
    /// would be two doors to one room.
    ///
    /// The wording matters here more than it looks. "还是搜 App Store" is a
    /// correction, not a suggestion: it tells the user their query was understood
    /// and that the list above it may still be the wrong app, which is exactly the
    /// situation — the catalogue matches on name, and a name is not an identity.
    @ViewBuilder
    private var catalogueAnsweredSection: some View {
        if !wantsStoreSearch, !query.trimmingCharacters(in: .whitespaces).isEmpty, !filtered.isEmpty {
            Section {
                Button {
                    wantsStoreSearch = true
                } label: {
                    Label("还是搜 App Store", systemImage: "magnifyingglass")
                }
            } footer: {
                Text("上面按名字匹配，同名的不一定是你装的那个。App Store 里有图标和开发者，能认出来。")
            }
        }
    }

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
                        Text("这个商店里没搜到。可以换个名字，或者换下面的地区试试。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(storeResults, id: \.trackID) { result in
                            storeRow(result)
                        }
                    }
                }

                storeRegionPicker

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
        } else if query.trimmingCharacters(in: .whitespaces).isEmpty, !hasSelection {
            Section {
                Text("这个文件夹还是空的。勾一个 App 就加进去。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The storefront the search runs against.
    ///
    /// Worth a row of its own rather than a buried setting: the device's store and
    /// the store an app came from can be different regions, and when they are, the
    /// default search is not merely empty — it returns a different app with the
    /// same name. Nothing on screen would otherwise explain that, and the user
    /// would conclude the app simply is not on the App Store.
    ///
    /// Only a few regions are offered. This is not a country list — it is the
    /// cheap escape hatch for the case that actually happens, and a complete list
    /// would be a worse picker for it. "跟随设备" is the default and the first
    /// row, so the common path stays one tap away.
    private var storeRegionPicker: some View {
        Picker(selection: $storeCountryOverride) {
            Text("跟随设备").tag(String?.none)
            // From ``AppStoreRegions`` rather than a list written out here. The
            // list used to live on this view as a `private static`, which is how
            // it escaped testing: 英国 was `uk`, which is not a storefront Apple
            // accepts, and nothing could reach the array to check. See that type
            // for what the user saw instead — not "no results", but a network
            // error, because a 400 and an outage look the same downstream.
            ForEach(AppStoreRegions.storefronts) { region in
                Text(region.label).tag(String?.some(region.code))
            }
        } label: {
            Label("搜索地区", systemImage: "globe")
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
    ///
    /// Either way it **adds** to the selection and leaves the picker open. This is
    /// the second door into the same bug the manual path had: it used to call
    /// `onDone([FolderTile(app: entry)])`, which is this screen's exit, so a
    /// catalogue hit from an App Store search replaced everything the folder held.
    ///
    /// Staying open is also the only version that makes sense of the icon on this
    /// row being a `plus.circle`: it means "add this", and the user can add three
    /// apps from one search instead of repeating the search per app.
    private func storeRow(_ result: AppStoreLookup) -> some View {
        Button {
            if let entry = AppCatalog.entry(appStoreID: result.trackID) {
                selection.add(FolderTile(app: entry))
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

                // Reflects what the tap did, because the row now stays open and a
                // control that looks identical after it has been pressed reads as
                // one that did nothing. A stranger has no id to check against —
                // it goes to the scheme screen instead — so it keeps the plus.
                let isAdded = AppCatalog.entry(appStoreID: result.trackID)
                    .map { selection.catalogIDs.contains($0.id) } ?? false
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isAdded ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func runStoreSearch() async {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        storeSearching = true
        defer { storeSearching = false }

        let country = storeCountry
        let results = await AppStoreSearchClient.shared.search(term: term, country: country)
        // The query may have moved on while this was in flight; a result for a
        // term the user has since deleted would flash the wrong list. The region
        // is checked the same way — switching it mid-flight must not let the
        // previous store's answer land under the new store's label.
        guard term == query.trimmingCharacters(in: .whitespaces), country == storeCountry else { return }

        storeFailed = results == nil
        storeResults = results ?? []
    }

    /// Splits the folder's current tiles into the two things this screen tracks.
    ///
    /// A tile made from a catalogue entry carries that entry's id and is fully
    /// described by it, so it reduces to a checkmark. A hand-added tile carries a
    /// scheme the user worked out — a fact that exists nowhere else — so it is
    /// kept whole and always travels back, whether or not it appears in any list
    /// here.
    private func seedFromCurrentTiles() {
        selection = .seeded(from: currentTiles)
    }

    /// Whether anything is picked, so the screen can tell "you removed them all"
    /// apart from "this folder was already empty".
    private var hasSelection: Bool { !selection.isEmpty }

    private func row(_ app: KnownApp) -> some View {
        let isPicked = selection.catalogIDs.contains(app.id)

        return Button {
            selection.setCatalog(app.id, isSelected: !isPicked)
        } label: {
            HStack(spacing: 12) {
                AsyncTileIcon(appStoreID: app.appStoreID, symbolName: app.symbolName ?? "app.dashed")
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                    Text(app.englishName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isPicked ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Icon view driven by an App Store id, for entries that are not tiles yet.
///
/// Three states, and which one is showing matters. Fetched artwork is the real
/// icon. When there is an id but the fetch has not landed (or failed) the tile is
/// a neutral placeholder — honest, because something *is* coming. When there is no
/// id at all, nothing is coming, so a placeholder would just be a hole in the
/// list; the symbol is drawn as a deliberate mark instead.
struct AsyncTileIcon: View {
    let appStoreID: Int?
    let symbolName: String

    @State private var image: UIImage?

    /// Whether this icon is waiting on a fetch that could plausibly succeed.
    private var isAwaitingArtwork: Bool { appStoreID != nil && image == nil }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else if isAwaitingArtwork {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.fill.tertiary)
                    .overlay {
                        Image(systemName: symbolName)
                            .foregroundStyle(.secondary)
                    }
            } else {
                // No id, so this app has no store artwork to fetch — Apple's own
                // apps. Drawn larger and in the accent-adjacent foreground so it
                // reads as the icon rather than as a missing one; the same size
                // as the placeholder glyph would still look like a failure.
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.fill.secondary)
                    .overlay {
                        Image(systemName: symbolName)
                            .font(.system(size: 18))
                            .foregroundStyle(.primary)
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
