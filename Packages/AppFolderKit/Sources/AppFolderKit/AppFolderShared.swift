import Foundation

/// Constants shared by the app, the widget extension and the intents.
///
/// Everything here is a string that must match something outside this package —
/// an entitlement, an Info.plist key, or a widget kind registered by the
/// extension. Keeping them in one place is the difference between "the widget
/// renders blank" and "the widget renders blank, and we know why".
public enum AppFolderShared {
    /// App Group container. Both the app and the widget read the library from it.
    ///
    /// Requires the App Groups capability. On a build signed with a Personal
    /// Team this container is not available — see `FolderStore` for the fallback.
    public static let appGroupIdentifier = "group.com.lvyufeng.appfolder"

    /// `kind` passed to `WidgetConfiguration`, and the value `WidgetCenter`
    /// uses to reload timelines. Must match the widget's `kind` exactly.
    public static let widgetKind = "AppFolderWidget"

    /// File name of the library inside the shared container.
    public static let libraryFileName = "library.json"

    /// Directory inside the shared container holding one file per app the user
    /// shared in, waiting for the app to turn into a tile.
    ///
    /// A directory rather than a file on purpose — see ``PendingImport`` for why
    /// appending to a single JSON would put the extension and the app back into
    /// the same lost-update race the queue exists to avoid.
    public static let importsDirectoryName = "imports"

    /// Directory inside the shared container holding one file per app the user
    /// shared in that could not be resolved to a launch target automatically.
    ///
    /// Separate from ``importsDirectoryName`` because the two hold opposite things.
    /// That one is a *decision* — the extension already knows which app and which
    /// folder — and the app turns it into a tile on sight. This one is a *question*
    /// the app could not answer on its own: the app is real, the folder is known,
    /// and how to open it is not. It waits for the user, which is why it is a
    /// different queue with a different lifetime. See ``PendingResolution``.
    public static let pendingResolutionsDirectoryName = "pending-resolutions"

    /// `UserDefaults` key used when the App Group container is unavailable.
    public static let fallbackDefaultsKey = "library.fallback"
}
