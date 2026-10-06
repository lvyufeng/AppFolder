import Foundation

/// Transient widget-display state, kept where both processes can see it.
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

    /// Picks the defaults to use, and reports whether they can round-trip.
    ///
    /// The App Group suite first, because that is the one that survives the
    /// widget extension being rebuilt — but it is *not* required for the tap to
    /// work, which is why a failure falls through to `.standard` rather than
    /// giving up. `.standard` inside the extension is shared between the intent
    /// and the render for the same reason the suite is: one process, one domain.
    /// It needs no entitlement, so it is the more robust of the two for the
    /// in-process path, and the weaker one for persistence.
    ///
    /// The probe is a write and a read-back rather than a check that the suite
    /// exists: `UserDefaults(suiteName:)` returns an object for a suite the
    /// process cannot actually write to, and a `nil` check would then promise
    /// storage that silently drops every value.
    ///
    /// Synchronous and cheap by design — a widget has a tight render budget and
    /// no second process to wait on.
    private static func resolveStorage() -> Storage {
        let token = UUID().uuidString

        if let shared = UserDefaults(suiteName: AppFolderShared.appGroupIdentifier) {
            shared.set(token, forKey: Key.probe)
            if shared.string(forKey: Key.probe) == token {
                shared.removeObject(forKey: Key.probe)
                return Storage(defaults: shared, isAvailable: true)
            }
        }

        let standard = UserDefaults.standard
        standard.set(token, forKey: Key.probe)
        if standard.string(forKey: Key.probe) == token {
            standard.removeObject(forKey: Key.probe)
            return Storage(defaults: standard, isAvailable: true)
        }

        return Storage(defaults: standard, isAvailable: false)
    }
}