import Foundation

/// Constants shared by the app, the widget extension and the intents.
///
/// Everything here is a string that must match something outside this package —
/// an entitlement, an Info.plist key, or a widget kind registered by the
/// extension. Keeping them in one place is the difference between "the widget
/// renders blank" and "the widget renders blank, and we know why".
///
/// What used to be here and no longer is: the library file name, the two
/// share-import queue directories, and the `UserDefaults` fallback key. All four
/// served the folder model and the share extension, both of which have been
/// deleted — see ``DirectLaunchIcons`` for where the direct-launch widget's
/// state actually lives now.
public enum AppFolderShared {
    /// App Group container. The widget reads its downloaded icons from it, and
    /// both processes share their transient display state through it.
    ///
    /// Requires the App Groups capability. Without it the widget keeps working —
    /// it resolves and stores its own icons — but the two processes stop being
    /// able to see each other's widget state; see ``WidgetState/resolveStorage()``.
    public static let appGroupIdentifier = "group.com.lvyufeng.appfolder"

    /// The kind of the direct-launch widget, whose slots open apps with no hop.
    ///
    /// Kept in step with the `kind` passed to `WidgetConfiguration` in
    /// ``DirectLaunchWidget``. The *folder* widget's kind used to sit beside this
    /// one; it is gone with the widget. That widget could not simply be repurposed
    /// into this one: this one's configuration intent carries `SystemShortcut`
    /// values, which exist only in a widget's own configuration and cannot be
    /// stored beside a folder.
    public static let directLaunchWidgetKind = "AppFolderDirectLaunch"
}