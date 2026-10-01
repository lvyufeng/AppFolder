import AppFolderKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct AppFolderApp: App {
    @State private var model = LibraryModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task {
                    await model.start()
                }
        }
    }
}

/// Owns the folder library and mediates every mutation.
///
/// Writes go through here rather than straight to ``FolderStore`` so that two
/// things always happen together: the file is saved, and the widget is told to
/// redraw. Forgetting either one produces the same confusing symptom — "I
/// changed it and the widget still shows the old thing".
@Observable
@MainActor
final class LibraryModel {
    private let store = FolderStore()
    private let prober = InstallationProber()

    var library: FolderLibrary = .empty
    /// Set when the build has no App Group, which makes widgets read nothing.
    /// Surfaced in the UI because it is otherwise invisible and baffling.
    var isSharedStorageAvailable = true

    var folders: [Folder] { library.folders }
    var installedSchemes: Set<String> { prober.installedSchemes }
    var isProbing: Bool { prober.isProbing }

    /// How many catalogue apps the probe found on this device.
    var installedAppCount: Int { prober.installedSchemes.count }

    /// How many catalogue entries the probe was able to ask about at all.
    ///
    /// Out of ``AppCatalog/queryBudget``, and the reason the picker's "其他" list
    /// exists: an app we never asked about is not the same as an app we know is
    /// absent, and the UI must not blur the two.
    var probedSchemeCount: Int { prober.probedSchemes.count }

    func start() async {
        library = store.load()
        isSharedStorageAvailable = store.hasSharedContainer
        await drainSharedImports()
        await refreshInstalledApps()
    }

    /// Turns anything the share extension left for us into tiles.
    ///
    /// The extension cannot write the library — two writers on one file lose
    /// updates, see ``PendingImport`` — so it deposits a record and this is where
    /// the record becomes real. Called on launch and again whenever the app comes
    /// forward, because the whole point of sharing is that the user does it from
    /// another app and then switches back.
    ///
    /// The catalogue is consulted first and by track id, so an app it already
    /// knows needs no network at all: its scheme is verified and the tile is
    /// finished immediately. Only a stranger costs a lookup, and even then it is
    /// one request rather than a search.
    func drainSharedImports() async {
        let pending = PendingImportStore().drain()
        guard !pending.isEmpty else { return }

        for item in pending {
            guard let index = library.folders.firstIndex(where: { $0.id == item.folderID }) else {
                // The folder was deleted between the share and the return. Dropped
                // rather than re-homed: putting it somewhere the user did not pick
                // is worse than not adding it, and sharing again costs one tap.
                continue
            }

            let tile: FolderTile?
            if let entry = AppCatalog.entry(appStoreID: item.trackID) {
                tile = FolderTile(app: entry)
            } else if let lookup = await AppStoreSearchClient.shared.lookup(
                trackID: item.trackID, region: item.region
            ) {
                // Known to the App Store but not to the catalogue: a name, an
                // icon and an id, but no verified scheme. The tile is still worth
                // making — the app's editor is where a scheme gets filled in and
                // tried, and that is a better place to land than dropping it.
                tile = FolderTile(
                    title: lookup.name,
                    scheme: SchemeGuess.candidates(bundleID: lookup.bundleID, name: lookup.name).first ?? "",
                    appStoreID: lookup.trackID
                )
            } else {
                tile = nil
            }

            guard let tile else { continue }
            var next = library
            next.folders[index].tiles.append(tile)
            apply(next)
        }
    }

    /// Re-probes which apps are installed and persists the result for the widget.
    func refreshInstalledApps() async {
        let result = await prober.probe()
        var next = library
        next.installedSchemes = result.installed
        next.probedSchemes = result.probed
        next.lastProbeAt = .now
        apply(next)
    }

    func upsert(_ folder: Folder) {
        var next = library
        if let index = next.folders.firstIndex(where: { $0.id == folder.id }) {
            next.folders[index] = folder
        } else {
            next.folders.append(folder)
        }
        apply(next)
    }

    func delete(_ folder: Folder) {
        var next = library
        next.folders.removeAll { $0.id == folder.id }
        apply(next)
    }

    func moveFolders(from source: IndexSet, to destination: Int) {
        var next = library
        next.folders.move(fromOffsets: source, toOffset: destination)
        apply(next)
    }

    private func apply(_ next: FolderLibrary) {
        library = next
        persist()
    }

    private func persist() {
        isSharedStorageAvailable = store.save(library)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func folder(withID id: UUID) -> Folder? {
        library.folders.first { $0.id == id }
    }

    /// Whether a tile's target looks reachable right now.
    func isReachable(_ tile: FolderTile) -> Bool {
        library.isReachable(tile)
    }

    /// What we know about whether a catalogue entry is on this device.
    ///
    /// Three answers, and the third one is the point. `TilePickerView` used to
    /// treat "not in `installedSchemes`" as "not installed", which lumps together
    /// two unrelated situations — *we asked and the app isn't there* and *we were
    /// never allowed to ask*. A scheme we cannot check (see
    /// ``AppCatalog/queryBudget``) would then be shown under "其他", quietly
    /// telling the user their app is missing when it is probably right there on
    /// their Home Screen.
    typealias InstallStatus = InstallationProber.InstallStatus

    func installStatus(_ app: KnownApp) -> InstallStatus {
        prober.status(of: app)
    }

    func isInstalled(_ app: KnownApp) -> Bool {
        installStatus(app) == .installed
    }
}
