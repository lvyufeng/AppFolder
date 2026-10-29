import Foundation
import WidgetKit

/// Transient widget-display state, kept where both processes can see it.
///
/// Both the app and extension require the App Group container and its writable
/// defaults suite. A suite that only round-trips inside one process is not enough:
/// unsigned installations can create private defaults under the group name even
/// though no shared container exists. When unavailable, reads return empty state
/// and writes are discarded, so the app cannot claim a change reached its widget.
///
/// ## Which grid is expanded, and which page of it
///
/// A widget cannot hold view state, so "this grid is open, showing page two" has
/// to live somewhere both the intent that sets it and the render that reads it can
/// reach. That is all this type is. See ``ToggleDirectLaunchIntent`` for the write
/// side and ``FolderExpansionLayout`` for what the page number means.
///
/// This used to hold a *folder's* expansion as well, for the 大文件夹 widget. That
/// widget is gone — its folder-expansion accessors went with it — and what
/// remains is the direct-launch grid's. The page counter is shared because there
/// is only one thing to page now; when there were two, sharing it was also right,
/// since a user has one expansion open at a time.
///
/// ## Why the page is stored even though the widget knows the grid
///
/// The intent that advances the page has no widget family — an `AppIntent` is
/// handed its parameters by the button, and a button in a grid does not know how
/// many cells it is drawn among. So the stored page can be past the end of the
/// group, or belong to a grid the widget is no longer using. The reader clamps
/// rather than the writer, which is why ``expandedPage`` is a plain `Int` and
/// why ``FolderExpansionLayout/clampedPage(_:)`` exists.
///
/// ## Note what is *absent*
///
/// There is no "did the last launch work" flag, because there is no way to know:
/// a direct launch runs out of process and the system reports nothing back, so
/// from inside the widget a successful tap and a tap that did nothing look
/// identical. Recording every attempt as suspicious would flag working tiles as
/// broken. When per-tile launch behaviour was configurable the app let the user
/// test it by hand and watch the result; that editor is gone, and with it the
/// route that could fail this way — a direct launch has no URL scheme to guess
/// wrong.
public enum WidgetState {
    private enum Key {
        static let expandedPage = "widget.expandedPage"
        /// Written and read back by ``resolveStorage()``; never a real setting.
        static let probe = "widget.probe"
        static let directLaunchKey = "widget.directLaunchKey"
        /// How far the *app* has got with asking for a collapse.
        static let collapseRequest = "widget.collapseRequest"
        /// How far *this process* has got through ``collapseRequest``.
        static let seenCollapseRequest = "widget.seenCollapseRequest"
    }

    /// The defaults this state lives in.
    ///
    /// Resolved once per process, because the entitlement it depends on
    /// cannot change while a process is running.
    ///
    /// `UserDefaults` is documented as thread-safe, so sharing one instance
    /// across the app and the widget's intent runner is sound; the compiler has
    /// no way to know that, because the class predates `Sendable`.
    private nonisolated(unsafe) static let storage = resolveStorage()

    /// The defaults every accessor goes through.
    private static var defaults: UserDefaults { storage.defaults }

    /// The same defaults, for another type that needs to share this storage.
    ///
    /// Internal rather than public on purpose: the storage *resolution* carries the
    /// requirement that neither process may fall back to `.standard`,
    /// and a second copy of it would drift. ``DirectLaunchOverrides`` is the public
    /// face of the second thing that lives here — durable user configuration
    /// rather than the transient render state the rest of this type holds — and it
    /// reads through this seam rather than repeating the lookup.
    static var widgetDefaults: UserDefaults { storage.defaults }

    /// Whether widget state can be read here at all, for the same caller.
    ///
    /// ``DirectLaunchOverrides`` guards its *writes* on this rather than on a plain
    /// read-back, because a record written into a domain nobody else can see is
    /// worse than one not written: it would look like it worked.
    static var widgetStateIsAvailable: Bool { storage.isAvailable }

    /// Whether this installation can access an App Group container and round-trip
    /// the defaults suite shared by the app and widget. This says nothing about
    /// another process's current state or when WidgetKit will grant a reload.
    ///
    /// The answer and defaults come from one lazily initialized value, so an early
    /// availability read cannot observe a flag before the storage probe runs.
    public static var isAvailable: Bool { storage.isAvailable }

    /// The direct-launch grid currently expanded in the widget, if any.
    ///
    /// A key of its own rather than something derived from a folder's id, because
    /// a grid has no id to derive one from: a folder was expanded by tapping a door
    /// the timeline provider built out of stored tiles, while a grid is expanded by
    /// tapping one of the slots the *user* configured in the Edit Widget sheet, and
    /// those slots are opaque to us. See
    /// ``directLaunchExpansionKey(slotNames:)``.
    ///
    /// Read and written through the storage probe: a widget whose App Group is
    /// unreachable gets `nil` and simply does not expand, rather than expanding
    /// into a domain the *next* render cannot read.
    public static var directLaunchKey: String? {
        get { defaults.string(forKey: Key.directLaunchKey) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.directLaunchKey)
            } else {
                defaults.removeObject(forKey: Key.directLaunchKey)
            }
        }
    }

    /// The name of the grid the user has open, from the slots it holds.
    ///
    /// A direct-launch grid has nothing stable to key an expansion on: its slots
    /// are `SystemShortcut`s, which the system will not let us read, compare or
    /// serialise, and the display names are not unique. What *is* available to
    /// both the tap and the render is the list of names — the same list, in the
    /// same order, produced by the same `displayRepresentation` — so the key is a
    /// digest of that.
    ///
    /// Order matters and is part of the key, because it is part of what the user
    /// configured: reordering the slots is a different grid and should not
    /// inherit an expansion.
    ///
    /// Deliberately not the *number* of slots: two grids of nine with different
    /// apps are different grids, and a key that only counted them would expand
    /// the wrong one. `DirectLaunchIcons.stableHash` is the digest because it is
    /// the one hash this package already guarantees is identical in the intent's
    /// process and the render's.
    public static func directLaunchExpansionKey(slotNames: [String]) -> String {
        DirectLaunchIcons.stableHash(slotNames.joined(separator: "\u{1F}"))
    }

    /// Navigation belongs to a layout as well as its actions. Same-name medium
    /// and large widgets must not inherit each other's page or expanded state.
    public static func directLaunchExpansionKey(slotNames: [String], grid: FolderGrid,
                                                 family: WidgetFamily, density: FolderDensity = .standard) -> String {
        let density = density.effective(for: family)
        let key = directLaunchExpansionKey(slotNames: slotNames)
            + "|layout:1|\(grid.rawValue)|\(family.rawValue)|\(grid.columns(for: family, density: density))x\(grid.cellCount(for: family, density: density))"
        return density == .standard ? key : key + "|density:\(density.rawValue)"
    }

    /// Collapses the open grid and returns it to the first page.
    ///
    /// Both keys, always, because they are one piece of state: a stored page with
    /// no stored key is not a state anything reads, and leaving the page behind
    /// means the next expand opens on the page the user left last time rather than
    /// at the start.
    ///
    /// Called by the app when it comes to the foreground, so a grid left open on
    /// the Home Screen is not still open hours later. This is the free half that
    /// only helps when the app and the extension resolve to the same domain; the
    /// half that reaches across processes is ``requestCollapse()``.
    public static func collapse() {
        directLaunchKey = nil
        expandedPage = 0
    }

    /// Asks every widget to drop any expansion, and records that the ask happened.
    ///
    /// A counter rather than a flag, and a counter rather than a plain `collapse()`,
    /// for the reason the display state is stored rather than held: a widget cannot
    /// hold view state, so a collapse has to be something the *next render* can
    /// observe. A bare `collapse()` writes the state the app can see; this makes
    /// the request durable — it survives being read by two widgets, being missed
    /// because WidgetKit declined a reload, and being followed by the app launching
    /// again. Nothing here has to know whether anything was actually expanded: the
    /// request is unconditional and a no-op when nothing is open.
    ///
    /// ## Why this lives here and no longer in the library
    ///
    /// It used to travel in `FolderLibrary` — a file in the App Group — on the
    /// argument that the two processes do not always resolve the defaults to the
    /// same domain, and a cross-process write cannot land in a per-process
    /// fallback. That argument still holds, and this is the answer to it rather
    /// than a contradiction of it: the fallback for either process in
    /// ``resolveStorage()`` is ``UnreadableDefaults``, so a widget whose App Group
    /// is unreachable never expands in the first place — its
    /// ``directLaunchKey`` is always `nil`, and there is nothing for this request
    /// to collapse. The case the library channel was protecting against — a widget
    /// stuck open with no way back — cannot arise here. The library itself has
    /// been deleted along with the folder model it served.
    public static func requestCollapse() {
        collapseRequest &+= 1
        collapse()
    }

    /// How many collapses the app has asked for.
    ///
    /// Written by the app, read by the widget's timeline provider, which compares
    /// it against its own ``seenCollapseRequest`` cursor. See ``requestCollapse()``
    /// for why it is a counter and why it is stored here.
    public static var collapseRequest: Int {
        get { defaults.integer(forKey: Key.collapseRequest) }
        set { defaults.set(newValue, forKey: Key.collapseRequest) }
    }

    /// The ``collapseRequest`` this process has already acted on.
    ///
    /// A cursor, not a flag: the request is shared so both processes can see it,
    /// and this records how far this process has got through them. Kept in the
    /// same defaults as the rest of the state — it is per-process by nature, so a
    /// domain only this process can read is exactly right for it.
    public static var seenCollapseRequest: Int {
        get { defaults.integer(forKey: Key.seenCollapseRequest) }
        set { defaults.set(newValue, forKey: Key.seenCollapseRequest) }
    }

    /// Applies a collapse the app has asked for, if it is newer than the last one
    /// seen here.
    ///
    /// Called from the timeline provider, which is where the widget reads its
    /// shared state. Deliberately not a "collapse on every reload": the whole
    /// point of the counter is that it distinguishes a *new* request from a reload
    /// that merely happened afterwards, so a widget reloading for its own reasons
    /// does not also throw away an expansion the user is looking at.
    ///
    /// Returns whether it collapsed, so the caller can say so in a log or a test.
    @discardableResult
    public static func applyCollapseRequest(_ request: Int) -> Bool {
        guard request != seenCollapseRequest else { return false }
        seenCollapseRequest = request
        collapse()
        return true
    }

    /// Which page of the expanded grid is showing, zero-based.
    ///
    /// Unclamped on purpose — see the type's discussion. A grid that is not
    /// expanded ignores this entirely.
    public static var expandedPage: Int {
        get { defaults.integer(forKey: Key.expandedPage) }
        set { defaults.set(newValue, forKey: Key.expandedPage) }
    }

    /// What this process should store widget state in, and whether it can.
    ///
    /// One value rather than two, so the defaults in use and the answer about
    /// whether they work cannot be initialized in the wrong order — see
    /// ``isAvailable`` for the bug that came of keeping them apart.
    struct Storage {
        let defaults: UserDefaults
        let isAvailable: Bool
    }

    /// No private fallback: both processes see empty state when sharing fails.
    /// The accessors used by widget state and icon overrides never fall through
    /// to UserDefaults.standard or another process-local preferences domain.
    private final class UnreadableDefaults: UserDefaults {
        override func object(forKey defaultName: String) -> Any? { nil }
        override func set(_ value: Any?, forKey defaultName: String) {}
        override func removeObject(forKey defaultName: String) {}
        override func string(forKey defaultName: String) -> String? { nil }
        override func integer(forKey defaultName: String) -> Int { 0 }
        // Overridden for the same reason as the four above: this subclass has no
        // backing store, so an accessor it does not override falls through to the
        // base class and reads the *process's own* domain. That is the exact
        // "silently wrong" state this type exists to avoid — a widget would read a
        // private answer and believe it was the shared one. ``DirectLaunchOverrides``
        // reads a dictionary and the observed-slot list as `Data`, so both are
        // covered here rather than left to inherit.
        override func dictionary(forKey defaultName: String) -> [String: Any]? { nil }
        override func data(forKey defaultName: String) -> Data? { nil }
    }

    /// The shipping iOS app and extension must first have a real App Group
    /// container. UserDefaults(suiteName:) can still succeed without that
    /// entitlement, and its in-process write/read does not prove sharing.
    private static func resolveStorage() -> Storage {
        #if os(iOS)
        return sharedStorage(
            groupContainer: FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: AppFolderShared.appGroupIdentifier
            ),
            makeDefaults: { UserDefaults(suiteName: AppFolderShared.appGroupIdentifier) }
        )
        #else
        // macOS is only the package's host-side test target, never the shipping
        // app. Its local defaults preserve those tests without weakening iOS's
        // entitlement check. Tests of the actual selection rule inject their own
        // defaults through sharedStorage below.
        let local = UserDefaults.standard
        return roundTrips(local)
            ? Storage(defaults: local, isAvailable: true)
            : unavailableStorage()
        #endif
    }

    /// The same selection rule for app and extension, with injectable inputs so
    /// missing entitlements and unwritable suites can be tested without signing.
    static func sharedStorage(
        groupContainer: URL?,
        makeDefaults: () -> UserDefaults?
    ) -> Storage {
        guard groupContainer != nil,
              let shared = makeDefaults(), roundTrips(shared)
        else { return unavailableStorage() }
        return Storage(defaults: shared, isAvailable: true)
    }

    private static func unavailableStorage() -> Storage {
        Storage(defaults: UnreadableDefaults(), isAvailable: false)
    }

    /// Use a unique probe key so app/extension startup cannot overwrite each
    /// other's token. Always clean it up, including a failed read-back.
    private static func roundTrips(_ defaults: UserDefaults) -> Bool {
        let token = UUID().uuidString
        let probe = "\(Key.probe).\(token)"
        defaults.set(token, forKey: probe)
        defer { defaults.removeObject(forKey: probe) }
        return defaults.string(forKey: probe) == token
    }
}
