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
    /// Shared-in apps that could not be resolved to a launch target, oldest first.
    ///
    /// Held in memory so the editor can list them, and reloaded whenever the queue
    /// changes. The queue is the *only* trace these apps leave: they produce no
    /// tile, so nothing else on screen would show that a share happened at all.
    var pendingResolutions: [PendingResolution] = []

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
        // Read before draining, so a queue left over from a previous launch is on
        // screen immediately rather than one shared-import later.
        reloadPendingResolutions()
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

            if let entry = AppCatalog.entry(appStoreID: item.trackID) {
                // The catalogue knows this app, so its scheme is verified and the
                // tile is finished without asking anyone anything.
                var next = library
                next.folders[index].tiles.append(FolderTile(app: entry))
                apply(next)
                continue
            }

            // Anything else is a *question*, not a tile.
            //
            // This used to take `SchemeGuess.candidates(...).first` and save it
            // straight away, which meant one tap from the user produced a tile with
            // roughly even odds of doing nothing — and the failure is invisible on
            // the Home Screen, so there was no way to tell a guess that worked from
            // one that did not. 票牛 is the example: the guess was `pner://`, the
            // real scheme is `piaoniu://home`, and nothing in the bundle id or the
            // store name leads from one to the other.
            //
            // So it becomes a ``PendingResolution`` — recorded, counted on the app
            // icon, and left for the editor, where ``SchemeEntryView`` can try
            // candidates against the real device instead of guessing.
            //
            // The record carries only what the link carried. No lookup happens
            // here on purpose: this runs on launch and on every return to the
            // foreground, and the network is not always there. Resolving eagerly
            // would make an offline share lose the name and the icon — and, since
            // ``PendingImportStore/drain()`` removes records as it reads them,
            // losing them silently. The editor resolves when it can actually reach
            // the store.
            let pending = PendingResolution(
                trackID: item.trackID,
                region: item.region,
                folderID: item.folderID
            )
            PendingResolutionStore().deposit(pending)
        }
        // Once per drain, not once per record: the badge is one number and this
        // is the only place the queue grows.
        reloadPendingResolutions()
        PendingResolutionBadge.refresh()
    }

    /// Re-reads the unresolved-share queue and republishes it for the editor.
    ///
    /// Also the one place that keeps the badge's number honest on the way *down*:
    /// draining only ever adds, so a confirmed or discarded entry has to come
    /// through here to take the numeral off the icon.
    func reloadPendingResolutions() {
        pendingResolutions = PendingResolutionStore().all()
        PendingResolutionBadge.refresh()
    }

    /// Turns a confirmed share into a real tile.
    ///
    /// The tile lands in the folder the user picked in the share sheet, falling
    /// back to the first folder when that one is gone — the folder can be deleted
    /// between sharing and confirming, and losing the user's chosen destination is
    /// a much smaller harm than losing the share. Same reasoning as
    /// ``drainSharedImports``, and the same shape of guard.
    func resolve(_ pending: PendingResolution, into tile: FolderTile) {
        var next = library
        if let index = next.folders.firstIndex(where: { $0.id == pending.folderID }) {
            next.folders[index].tiles.append(tile)
        } else if let first = next.folders.indices.first {
            next.folders[first].tiles.append(tile)
        } else {
            // No folders at all. Dropping the record would lose the app, so the
            // confirmation is refused rather than half-applied — the editor
            // disables the button in this case, and this is the backstop.
            return
        }
        apply(next)
        PendingResolutionStore().remove(pending.id)
        reloadPendingResolutions()
    }

    /// Throws one away without making a tile.
    ///
    /// A first-class outcome rather than a hidden one: the app may genuinely not be
    /// on the device any more, or the user may have changed their mind about the
    /// share. Either way the queue has to be clearable, or the badge becomes
    /// permanent. See ``resolve(_:into:)`` for why removal is separate from
    /// resolution.
    func discard(_ pending: PendingResolution) {
        PendingResolutionStore().remove(pending.id)
        reloadPendingResolutions()
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
