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
    let installedSchemes: Set<String>
    /// How the plate and the labels should be drawn.
    ///
    /// Resolved here rather than in the view so that a folder whose `colorHex` is
    /// empty or malformed has already been given a usable tint by the time
    /// anything draws it — see ``FolderStyle/init(_:)``.
    let style: FolderStyle
}

struct FolderTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FolderEntry {
        FolderEntry(
            date: .now,
            folder: Folder(name: "常用"),
            tiles: FolderEntry.placeholderTiles,
            installedSchemes: [],
            style: FolderStyle()
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

        // How many tiles fit is a function of the family, not of the folder, so
        // the widget never silently drops apps: it truncates to what fits.
        let capacity = Self.capacity(for: context.family)
        let tiles = Array((folder?.tiles ?? []).prefix(capacity))

        return FolderEntry(
            date: .now,
            folder: folder,
            tiles: tiles,
            installedSchemes: library.installedSchemes,
            style: folder.map(FolderStyle.init) ?? FolderStyle()
        )
    }

    static func capacity(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: 4
        case .systemMedium: 6
        case .systemLarge: 9
        case .systemExtraLarge, .systemExtraLargePortrait: 12
        default: 4
        }
    }
}

extension FolderEntry {
    /// Sample tiles for the widget gallery, using the host app's own icon so the
    /// preview looks like a real folder without shipping anyone else's artwork.
    static let placeholderTiles: [FolderTile] = (0..<9).map { index in
        FolderTile(
            title: "App \(index + 1)",
            urlString: "appfolder://placeholder/\(index)",
            symbolName: ["message", "calendar", "camera", "music.note", "map", "envelope", "book", "cart", "photo"][index]
        )
    }
}
