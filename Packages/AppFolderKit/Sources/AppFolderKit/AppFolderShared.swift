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

    /// `UserDefaults` key used when the App Group container is unavailable.
    public static let fallbackDefaultsKey = "library.fallback"
}
