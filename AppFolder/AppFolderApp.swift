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
        // A real write, not a check that the container exists: see
        // ``FolderStore/isSharedStorageWritable()`` for why the difference is the
        // whole point.
        isSharedStorageAvailable = store.isSharedStorageWritable()
        // A folder left expanded on the Home Screen is a transient view state, and
        // opening the app is a strong signal the user has moved on from it. Left
        // alone, the widget would still be expanded the next time it is looked at,
        // showing a page they never asked to keep.
        //
        // The request goes into the library rather than into `WidgetState`, and
        // that is not a preference. `WidgetState`'s defaults are resolved per
        // process, so the two sides can end up in different domains — on this
        // device they did, and the app was reading an expansion the widget had
        // never written. A collapse written there would have looked like it
        // worked while the widget stayed expanded. The library file is written
        // atomically by ``FolderStore`` and read by both processes, so it is the
        // channel that actually connects them. See
        // ``FolderLibrary/collapseRequest``.
        //
        // Unconditional: the counter is the test, not a preceding read. Checking
        // `expandedFolderID != nil` first would mean asking a domain that may not
        // hold the answer, and answering "nothing to collapse" on the strength of
        // it is the bug being fixed.
        collapseExpandedWidget()
        await drainSharedImports()
        await refreshInstalledApps()
    }

    /// Asks every widget to drop any expansion, and nudges them to look.
    ///
    /// The counter is what makes the request durable and idempotent: the widget
    /// compares it against the value it last acted on, so a request survives
    /// being read by two widgets, being missed because WidgetKit declined a
    /// reload, and being followed by the app launching again. Nothing here has to
    /// know whether anything was actually expanded — the request is unconditional
    /// and a no-op when nothing is open.
    ///
    /// Also clears ``WidgetState`` in *this* process, which is free and helps on
    /// the configurations where the app can reach the same defaults the widget
    /// uses. It is not relied on.
    private func collapseExpandedWidget() {
        WidgetState.collapse()
        var next = library
        next.collapseRequest += 1
        apply(next)
        WidgetCenter.shared.reloadAllTimelines()
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
            // The folder the user picked, falling back to the first one.
            //
            // The fallback is not a nicety. The extension reads the folder list
            // from the shared container, and if the app's last write to that
            // container failed — see ``FolderStore/save(_:)`` — the extension is
            // listing a library the app no longer agrees with. It then deposits
            // against a folder id that does not exist here, and every one of those
            // imports used to be dropped silently: the user shared an app, the
            // sheet said 已添加, and nothing ever appeared.
            //
            // Losing the user's chosen folder is a far smaller harm than losing
            // the import, and it is visible — the tile lands somewhere they can
            // see and move. Dropping it is invisible.
            guard let index = library.folders.firstIndex(where: { $0.id == item.folderID })
                ?? library.folders.indices.first
            else { continue }  // no folders at all; nothing to add to

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
                //
                // The scheme is a guess, so the tile is flagged as one. That flag
                // is what keeps a tile that opens nothing out of the widget and
                // puts a 待确认 warning on it in the editor, where 试一下 is one
                // tap away. Without it the user's only signal was the 打不开 alert
                // on the Home Screen, which names neither the tile nor the reason.
                //
                // The bundle id is stored alongside because it is the guesser's
                // input and the network is the only way to get it. Keeping it
                // means a later improvement — like the one that demoted `iphone`
                // — can repair this tile in place, instead of asking the user to
                // share the app again.
                tile = FolderTile(
                    title: lookup.name,
                    scheme: SchemeGuess.candidates(bundleID: lookup.bundleID, name: lookup.name).first ?? "",
                    appStoreID: lookup.trackID,
                    bundleID: lookup.bundleID,
                    needsSchemeConfirmation: true
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
