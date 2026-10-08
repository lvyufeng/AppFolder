import Foundation

/// Transient widget-display state, kept where both processes can see it.
///
/// ## The one case where an accessor deliberately lies
///
/// When the App Group is unreachable *from the extension* there is no domain both
/// processes can share, and the type is readable-only rather than
/// writable-and-private: see ``resolveStorage()``. In that state ``directLaunchKey``
/// reports `nil` to an extension, because answering from a private domain would
/// claim an expansion the app could never clear. The cost is that the widget does
/// not expand; the alternative cost was a widget stuck expanded with no way back
/// except the back cell.
///
/// Deliberately *not* part of a stored, backup-able model: this changes on every tap and
/// must never end up in a user's backup, whereas the library changes rarely and
/// is exactly what should be exported.
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
    /// Backup, resolved once per process, because the entitlement it depends on
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
    /// subtle argument for why an extension must never fall back to `.standard`,
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

    /// Whether state written here can be read back at all in this process.
    ///
    /// False only when even `UserDefaults.standard` refuses a round trip, which is
    /// the signal for a caller to fall back to a route that does not need stored
    /// state — a door that cannot open in place is better drawn as something that
    /// visibly does nothing than as a control that fails silently.
    ///
    /// Read this as "the in-process round trip works", *not* as "the App Group
    /// is healthy". A widget's intent runs in the widget extension's process, so
    /// the write and the read that matters are the same process's memory; that
    /// is the property this measures. Whether the value survives the extension
    /// being torn down and rebuilt is a stronger claim the App Group has to
    /// earn, and it is why the widget can expand correctly today even though the
    /// App Group on this device is not reachable from the app.
    ///
    /// ## Why this is a computed property and not a stored `let`
    ///
    /// It was `static let isAvailable = probeSucceeded` reading a separate
    /// `static var` that the probe set — and that was a real bug, not a style
    /// slip. Swift initializes stored statics lazily and in the order they are
    /// touched, so the first access to `isAvailable` read `probeSucceeded`
    /// *before* the probe had ever run, and got its default of `false`.
    /// The door then took the `Link` branch permanently, and the expansion this
    /// whole type exists for could never happen.
    ///
    /// Folding the answer into the lazily-initialized storage makes the two
    /// impossible to disagree, because there is only one initialization left to
    /// order.
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
    /// than a contradiction of it: the fallback for an *extension* in
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
    private struct Storage {
        let defaults: UserDefaults
        let isAvailable: Bool
    }

    /// A `UserDefaults` that refuses everything without crashing.
    ///
    /// Do not use `.standard` here. In the *app* process `.standard` is a real,
    /// private, writable domain, and handing it to an extension that cannot share
    /// it is precisely the bug: the extension would expand into a place the app
    /// cannot reach to collapse. `.volatile` is per-process and unreachable from
    /// anywhere else by definition, so it is the honest stand-in for "no shared
    /// domain" — writes are accepted and silently discarded from the point of
    /// view of every other process, which is the actual situation.
    private final class UnreadableDefaults: UserDefaults {
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

    /// Picks the defaults to use, and reports whether they can round-trip.
    ///
    /// The App Group suite on a successful round trip, then `.standard` inside an
    /// extension, and otherwise a domain nobody else can read.
    ///
    /// ## Why the extension is not allowed to fall back to `.standard`
    ///
    /// It used to be, and the reasoning was that one process is one domain, so
    /// the intent's write and the render's read always agree. True as far as it
    /// goes — and it stops one step short, because the widget is not the only
    /// writer. The *app* also writes this state: opening AppFolder collapses
    /// whatever was expanded, so the Home Screen is not left showing a page the
    /// user has moved on from.
    ///
    /// A cross-process write cannot land in a per-process fallback. If the
    /// extension put the expansion in `.standard`, the app's `collapse()` would
    /// write `nil` into the app's own plist and the widget would never see it —
    /// the widget would stay expanded forever, and the only way out would be to
    /// tap the back cell. So the fallback is not merely weaker for cross-process
    /// state, it is silently wrong, and being wrong is worse than being
    /// unavailable: an unavailable domain does not expand at all, which is a
    /// widget that behaves normally rather than one stuck open.
    ///
    /// ## And why the app is not either
    ///
    /// The same argument in the other direction. It used to be true on this very
    /// device that the app could not reach the group while the extension could,
    /// which is why an earlier version of this comment said so — but that is no
    /// longer the case and the comment was left behind by the fix. Measured from
    /// the device's App Group plist:
    ///
    /// * `widget.collapseRequest => 9` is present in
    ///   `group.com.lvyufeng.appfolder.plist`. The app is the only writer of that
    ///   counter, so the app is writing into the group.
    /// * The app's *own* `Library/Preferences/com.lvyufeng.appfolder.plist` holds
    ///   no `widget.*` keys at all, so the app is not quietly resolving this state
    ///   to `.standard` either.
    ///
    /// That matters beyond this type: it is the evidence that the group is a
    /// working two-way channel on this build, which is what lets
    /// ``DirectLaunchOverrides`` store a user setting in the group defaults and
    /// have the widget actually see it. If a future signing change removes the
    /// entitlement, the app falls back to `.standard` — the state described above —
    /// and the override list would read as empty in the widget rather than as
    /// wrong. Check the group plist before believing otherwise.
    ///
    /// The probe is a write and a read-back rather than a check that the suite
    /// exists: `UserDefaults(suiteName:)` returns an object for a suite the
    /// process cannot actually write to, and a `nil` check would then promise
    /// storage that silently drops every value.
    ///
    /// Synchronous and cheap by design — a widget has a tight render budget and
    /// no second process to wait on.
    private static func resolveStorage() -> Storage {
        if let shared = UserDefaults(suiteName: AppFolderShared.appGroupIdentifier),
           roundTrips(shared) {
            return Storage(defaults: shared, isAvailable: true)
        }

        // The widget extension is the side that cannot afford a wrong answer: a
        // testable answer is worth more to it than a writable one it cannot share.
        if isExtension {
            return Storage(defaults: UnreadableDefaults(), isAvailable: false)
        }

        return Storage(defaults: UserDefaults.standard, isAvailable: true)
    }

    /// Whether a `UserDefaults` accepts a value and gives it back.
    private static func roundTrips(_ defaults: UserDefaults) -> Bool {
        let token = UUID().uuidString
        defaults.set(token, forKey: Key.probe)
        guard defaults.string(forKey: Key.probe) == token else { return false }
        defaults.removeObject(forKey: Key.probe)
        return true
    }

    /// Whether this process is an app extension rather than the app itself.
    ///
    /// Read from the bundle's own `Info.plist` key, which is what an extension
    /// always has and an app never does. Asking the *main* bundle would answer
    /// for the app in both cases, since `Bundle.main` in an extension is the
    /// extension — so this deliberately reads `Bundle.main` and not a bundle
    /// looked up by identifier.
    ///
    /// Documented by Apple as present for every app extension, and checked here
    /// rather than inferred from the process name or the presence of a
    /// `UIApplication` subclass, both of which are conventions rather than API.
    static var isExtension: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSExtension") != nil
    }
}