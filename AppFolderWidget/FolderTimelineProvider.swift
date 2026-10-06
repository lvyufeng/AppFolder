import AppFolderKit
import AppIntents
import SwiftUI
import WidgetKit

/// Lets the user pick which folder a widget shows.
///
/// `AppIntentConfiguration` rather than `StaticConfiguration` because a user may
/// want several folders on the Home Screen, and because the picker is how a
/// widget gets its parameter at all — widgets can't be configured by the app.
struct FolderSelectionIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "选择文件夹"
    static let description: IntentDescription = "选择这个小组件要显示的文件夹。"

    @Parameter(title: "文件夹")
    var folder: FolderEntity?

    init() {}

    init(folder: FolderEntity?) {
        self.folder = folder
    }
}

/// A folder, as App Intents sees it.
///
/// `EntityQuery` reads the library on demand, so the picker always reflects
/// what the app last saved — no registration step, no cache to invalidate.
struct FolderEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "文件夹"
    static let defaultQuery = FolderEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(folder: Folder) {
        self.init(id: folder.id.uuidString, name: folder.name)
    }
}

struct FolderEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FolderEntity] {
        let wanted = Set(identifiers)
        return FolderStore().load().folders
            .filter { wanted.contains($0.id.uuidString) }
            .map(FolderEntity.init(folder:))
    }

    func suggestedEntities() async throws -> [FolderEntity] {
        FolderStore().load().folders.map(FolderEntity.init(folder:))
    }

    func defaultResult() async -> FolderEntity? {
        try? await suggestedEntities().first
    }
}

/// One point in a widget's timeline: a folder, ready to draw.
struct FolderEntry: TimelineEntry {
    let date: Date
    let folder: Folder?
    let tiles: [FolderTile]
    /// How many tiles the folder holds in total, before the widget truncated it
    /// to what fits.
    ///
    /// Carried rather than read from `folder.tiles.count` at draw time because
    /// the two are not always the same object: a `Folder` can be constructed for
    /// a placeholder or a test with `tiles` already reduced, and the view would
    /// then have no way to tell a folder of four from a folder of twelve that
    /// happens to be showing four.
    ///
    /// The view needs it to decide whether the grid's last cell is an app or the
    /// door, and to count what is behind the door — neither of which is
    /// answerable from `tiles`, which has already been cut down.
    let totalTileCount: Int
    let installedSchemes: Set<String>
    /// How the plate and the labels should be drawn.
    ///
    /// Resolved here rather than in the view so that a folder whose `colorHex` is
    /// empty or malformed has already been given a usable tint by the time
    /// anything draws it — see ``FolderStyle/init(_:)``.
    let style: FolderStyle

    /// Whether this widget is showing the folder expanded rather than as a grid
    /// with a door.
    ///
    /// Resolved against *this* entry's folder rather than read as a bare flag, so
    /// the shared state — one key for the whole device — cannot expand a widget
    /// showing a different folder. Two widgets on the same folder do both expand;
    /// that is consistent rather than wrong, and a per-widget key is not
    /// available because an intent cannot learn which widget configuration it was
    /// tapped from.
    ///
    /// See ``WidgetState`` for where it comes from and
    /// ``FolderExpansionLayout`` for what the page does.
    let isExpanded: Bool
    /// Which page of the expanded folder to draw. Meaningless unless
    /// ``isExpanded``; clamped to the folder's real length at draw time.
    let expandedPage: Int
}

extension FolderEntry {
    /// The apps the door is hiding — the ones an expansion shows.
    ///
    /// One definition, read by both the door's preview and the expansion, which
    /// is the point: a door that previewed one set of apps and opened onto
    /// another would be worse than a door with no preview at all. The count is
    /// ``FolderExpansionLayout/appCount(of:showing:)``, the same number the
    /// collapsed grid used to decide it had overflowed.
    ///
    /// Taken from `folder.tiles` rather than ``tiles``, which the provider has
    /// already truncated to the collapsed capacity — the hidden apps are exactly
    /// the ones that truncation removed.
    var hiddenTiles: [FolderTile] {
        guard let folder else { return [] }
        let shown = tiles.count
        guard folder.tiles.count > shown else { return [] }
        return Array(folder.tiles.dropFirst(shown))
    }
}

struct FolderTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FolderEntry {
        // A folder of twelve is the one that exercises every part of the grid:
        // the timeline hands over the first eight, and the ninth cell draws the
        // door. A placeholder of nine would show the door too, but with only one
        // app behind it — which is the arrangement the feature is least likely to
        // be judged on and the least useful thing to preview.
        FolderEntry(
            date: .now,
            folder: Folder(name: "常用", tiles: FolderEntry.placeholderTiles),
            tiles: Array(FolderEntry.placeholderTiles.prefix(FolderGrid.default.capacity(for: context.family))),
            totalTileCount: FolderEntry.placeholderTiles.count,
            installedSchemes: [],
            style: FolderStyle(),
            // Never expanded: the gallery and the placeholder show the resting
            // state of a folder, which is the grid with its door. A preview that
            // opened expanded would be showing a state the user has not asked
            // for yet.
            isExpanded: false,
            expandedPage: 0
        )
    }

    func snapshot(for configuration: FolderSelectionIntent, in context: Context) async -> FolderEntry {
        entry(for: configuration, context: context)
    }

    func timeline(for configuration: FolderSelectionIntent, in context: Context) async -> Timeline<FolderEntry> {
        // The folder contents only change when the app writes them, and the app
        // calls `reloadAllTimelines()` when it does. So one entry is enough — a
        // refresh policy here would just burn cycles re-reading an unchanged file.
        Timeline(entries: [entry(for: configuration, context: context)], policy: .never)
    }

    private func entry(for configuration: FolderSelectionIntent, context: Context) -> FolderEntry {
        let library = FolderStore().load()

        let folder: Folder?
        if let selected = configuration.folder {
            folder = library.folders.first { $0.id.uuidString == selected.id }
        } else {
            folder = library.folders.first
        }

        // How many tiles fit is a function of the family *and* of the
        // folder's grid setting — a 四宫格 folder shows three in the small widget
        // and eight in medium. One cell is held back for the "open the rest"
        // door, so this is one less than the grid's cell count; see
        // ``FolderGrid/capacity(for:)`` for why the reservation is unconditional.
        //
        // The widget never silently drops apps. Everything past this point is
        // reachable by tapping the door, and the editor shows the same number so
        // the arrangement is visible while the folder is being built rather than
        // on the Home Screen.
        let grid = folder?.grid ?? .default
        let tiles = Array((folder?.tiles ?? []).prefix(grid.capacity(for: context.family)))

        return FolderEntry(
            date: .now,
            folder: folder,
            tiles: tiles,
            totalTileCount: folder?.tiles.count ?? 0,
            installedSchemes: library.installedSchemes,
            style: folder.map(FolderStyle.init) ?? FolderStyle(),
            isExpanded: folder.map { $0.id.uuidString == WidgetState.expandedFolderID } ?? false,
            expandedPage: WidgetState.expandedPage
        )
    }

    /// How many tiles a family shows directly at the default grid.
    ///
    /// Kept for callers that have no folder to hand — the placeholder entry the
    /// gallery draws is the only one left.
    static func capacity(for family: WidgetFamily) -> Int { family.gridCapacity }
}

extension FolderEntry {
    /// Sample tiles for the widget gallery, using the host app's own icon so the
    /// preview looks like a real folder without shipping anyone else's artwork.
    static let placeholderTiles: [FolderTile] = (0..<12).map { index in
        FolderTile(
            title: "App \(index + 1)",
            urlString: "appfolder://placeholder/\(index)",
            symbolName: [
                "message", "calendar", "camera", "music.note",
                "map", "envelope", "book", "cart",
                "photo", "clock", "bell", "star",
            ][index]
        )
    }
}
