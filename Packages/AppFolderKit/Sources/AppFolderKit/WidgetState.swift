import Foundation

/// Transient widget-display state, kept where both processes can see it.
///
/// ## The one case where an accessor deliberately lies
///
/// When the App Group is unreachable *from the extension* there is no domain both
/// processes can share, and the type is readable-only rather than
/// writable-and-private: see ``resolveStorage()``. In that state ``expandedFolderID``
/// reports `nil` to an extension, because answering from a private domain would
/// claim an expansion the app could never clear. The cost is that the widget does
/// not expand; the alternative cost was a widget stuck expanded with no way back
/// except the back cell.
///
/// Deliberately *not* part of ``FolderLibrary``: this changes on every tap and
/// must never end up in a user's backup, whereas the library changes rarely and
/// is exactly what should be exported.
///
/// ## Which folder is expanded, and which page of it
///
/// A widget cannot hold view state, so "this folder is open, showing page two"
/// has to live somewhere both the intent that sets it and the render that reads
/// it can reach. That is all this type is. See ``ToggleFolderIntent`` for the
/// write side and ``FolderExpansionLayout`` for what the page number means.
///
/// ## Why the page is stored even though the widget knows the grid
///
/// The intent that advances the page has no widget family — an `AppIntent` is
/// handed its parameters by the button, and a button in a grid does not know how
/// many cells it is drawn among. So the stored page can be past the end of the
/// folder, or belong to a grid the widget is no longer using. The reader clamps
/// rather than the writer, which is why ``expandedPage`` is a plain `Int` and
/// why ``FolderExpansionLayout/clampedPage(_:)`` exists.
///
/// ## Note what is *absent*
///
/// There is no "did the last launch work" flag, because there is no way to know:
/// a direct launch runs out of process and the system reports nothing back, so
/// from inside the widget a successful tap and a tap that did nothing look
/// identical. Recording every attempt as suspicious would flag working tiles as
/// broken. Per-tile launch behaviour is therefore configured and tested in the
/// app, where the user can see what happened — see `FolderEditorView`.
public enum WidgetState {
    private enum Key {
        static let expandedFolderID = "widget.expandedFolderID"
        static let expandedPage = "widget.expandedPage"
        /// Written and read back by ``resolveStorage()``; never a real setting.
        static let probe = "widget.probe"
        /// How far this process has got through ``FolderLibrary/collapseRequest``.
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

    /// Whether state written here can be read back at all in this process.
    ///
    /// False only when even `UserDefaults.standard` refuses a round trip, which
    /// is the signal for a caller to fall back to a route that does not need
    /// stored state — see ``ToggleFolderIntent`` and the door in
    /// `FolderWidgetView`.
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

    /// The folder currently expanded inside the widget, if any.
    public static var expandedFolderID: String? {
        get { defaults.string(forKey: Key.expandedFolderID) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.expandedFolderID)
            } else {
                defaults.removeObject(forKey: Key.expandedFolderID)
            }
        }
    }

    /// Which page of the expanded folder is showing, zero-based.
    ///
    /// Unclamped on purpose — see the type's discussion. A folder that is not
    /// expanded ignores this entirely.
    public static var expandedPage: Int {
        get { defaults.integer(forKey: Key.expandedPage) }
        set { defaults.set(newValue, forKey: Key.expandedPage) }
    }

    /// The ``FolderLibrary/collapseRequest`` this process has already acted on.
    ///
    /// A cursor, not a flag: the request travels in the library so both processes
    /// can see it, and this records how far this process has got through them.
    /// Kept in the same defaults as the rest of the state — it is per-process by
    /// nature, so a domain only this process can read is exactly right for it.
    public static var seenCollapseRequest: Int {
        get { defaults.integer(forKey: Key.seenCollapseRequest) }
        set { defaults.set(newValue, forKey: Key.seenCollapseRequest) }
    }

    /// Applies a collapse the app has asked for, if it is newer than the last
    /// one seen here.
    ///
    /// Called from the timeline provider, which is the only place that has the
    /// library in hand. Deliberately not a "collapse on every reload": the whole
    /// point of the counter is that it distinguishes a *new* request from a
    /// reload that merely happened afterwards, so a widget reloading because the
    /// user added an app does not also throw away an expansion they are looking at.
    ///
    /// Returns whether it collapsed, so the caller can say so in a log or a test.
    @discardableResult
    public static func applyCollapseRequest(_ request: Int) -> Bool {
        guard request != seenCollapseRequest else { return false }
        seenCollapseRequest = request
        collapse()
        return true
    }

    /// Collapses whatever is open and returns it to the first page.
    ///
    /// Both keys, always, because they are one piece of state: a stored page with
    /// no stored folder is not a state anything reads, and leaving it behind
    /// means the next expand opens on the page the user left last time rather
    /// than at the start.
    public static func collapse() {
        expandedFolderID = nil
        expandedPage = 0
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
    /// unavailable: an unavailable domain degrades to the `Link` route, which
    /// still works.
    ///
    /// ## And why the app is not either
    ///
    /// The same argument in the other direction, which is the state this device
    /// is actually in: the app cannot reach the group container while the
    /// extension can. If the app wrote the expansion to its own `.standard`,
    /// nothing would read it. So the app is given the read-only domain — it
    /// still *reads* widget state, in case the group works, but the collapse it
    /// asks for is carried through the shared library file, which is the channel
    /// ``FolderStore`` already gates and which both processes can see.
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