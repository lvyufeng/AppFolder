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
        await refreshInstalledApps()
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
